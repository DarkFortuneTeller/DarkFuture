// -----------------------------------------------------------------------------
// DFInteractionSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles various player-initiated interactions,
//	 particularly actions in V's apartments. Correctly grants bonuses,
//   applies effects, and so on as if an item had been consumed.
//
// - Also handles the bulk of Time Skip logic, which is fairly complex.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.*
import DarkFuture.Utils.{
	DFRunGuard,
	DFIsSleeping,
	HoursToGameTimeSeconds
}
import DarkFuture.Main.{
	DFMainSystem,
	DFNeedsDatum,
	DFAddictionDatum,
	DFAddictionUpdateDatum,
	DFHumanityLossDatum,
	DFBiocorruptionDatum,
	DFFutureHoursData,
	DFNeedChangeDatum,
	DFTimeSkipData,
	DFTimeSkipType
}
import DarkFuture.Services.{
	DFGameStateService,
	DFPlayerStateService,
	DFNotificationService,
	DFAnimationService,
	DFNotification,
	DFAudioCue,
	DFVisualEffect,
	DFNotificationCallback,
	DFManagedEffect,
	DFManagedEffectType,
	DFCrashAnimMode,
	DFManagedEffectPipelineResult,
	DFManagedEffectMode
}
import DarkFuture.Needs.{
	DFHydrationSystem,
	DFNutritionSystem,
	DFEnergySystem,
	DFNerveSystem,
	DFNeedChangeUIFlags,
	DFChangeNeedValueProps,
	DFNeedChangeWithRecoverLimit,
	DFQueuedNeedValueChange
}
import DarkFuture.Addictions.{
	DFAddictionSystemBase,
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
import DarkFuture.Conditions.{
	DFHumanityLossConditionSystem,
	DFHumanityLossRestorationActivityType,
	DFHumanityLossRestorationType,
	DFHumanityLossCostType,
	DFBiocorruptionConditionSystem
}

//  Edgerunner's Mansion Compatibility - Detect shower interactions.
//
@wrapMethod(ArcadeMachine)
protected cb func OnTakeControl(ri: EntityResolveComponentsInterface) -> Bool {
	//DFProfile();
	// The shower device entity in the Edgerunner's Mansion is
	// a device of type Arcade Machine with a showerWorkspot component.

	let r: Bool = wrappedMethod(ri);

	let showerWorkspot: wref<IComponent> = this.FindComponentByName(n"showerWorkspot");
	if IsDefined(showerWorkspot) {
		DFNerveSystem.Get().SetNerveRegenTarget(100.0);
	}

	return r;
}

//  Hotscenes Compatibility
//
@wrapMethod(InvisibleSceneStash)
protected cb func OnQuestDressPlayer(evt: ref<DressPlayer>) -> Bool {
	let r: Bool = wrappedMethod(evt);

	DFInteractionSystem.Get().CheckHotscene();

	return r;
}

//	QuestTrackerGameController - Detect quest objective updates.
//
@wrapMethod(QuestTrackerGameController)
protected cb func OnStateChanges(hash: Uint32, className: CName, notifyOption: JournalNotifyOption, changeType: JournalChangeType) -> Bool {
	//DFProfile();
	if Equals(className, n"gameJournalQuestObjective") {
		DFInteractionSystem.Get().OnQuestObjectiveUpdate(hash);
	}
	
	return wrappedMethod(hash, className, notifyOption, changeType);
}

public struct DFAddictionTimeSkipIterationStateDatum {
	public let addictionAmount: Float;
	public let addictionAmountAsPercentage: Float;
	public let addictionStage: Int32;
	public let activeEffectApplied: Bool;
	public let backoffDuration: Float;
	public let withdrawalLevel: Int32;
	public let withdrawalDuration: Float;
	public let isWithdrawalLevelWorsened: Bool;
	public let hasLostAddictionAmountToday: Bool;
}

public struct DFHumanityLossTimeSkipIterationStateDatum {
	public let level: Uint32;
	public let newTimeUntilNextCyberpsychosisAllowed: Float;
	public let newEndotrisineDuration: Float;
}

public struct DFBiocorruptionTimeSkipIterationStateDatum {
	public let newCrashDuration: Float;
	public let newCrashStackCount: Uint32;
	public let highestCrashStackCount: Uint32;
	public let newTimeUntilRestless: Float;
	public let isRestless: Bool;
	public let crashOccuredDuringTimeskip: Bool;
}

public struct DFJournalEntryUpdate {
	public let questID: String;
	public let phaseID: String;
	public let entryID: String;
	public let state: gameJournalEntryState;
}

public class DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFInteractionSystem.Get().clearLastAttemptedChoiceForFXCheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFInteractionSystem.Get().OnClearLastAttemptedChoiceForFXCheck();
	}
}

public class DFInteractionSystemSmokeChoiceDebounceCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new DFInteractionSystemSmokeChoiceDebounceCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFInteractionSystem.Get().smokePromptDebounceDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFInteractionSystem.Get().OnSmokePromptDebounceCallback();
	}
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
	//DFProfile();
	let interactionSystem: ref<DFInteractionSystem> = DFInteractionSystem.Get();
	let effectID: TweakDBID = evt.staticData.GetID();

	if IsSystemEnabledAndRunning(interactionSystem) {		
		if Equals(effectID, t"HousingStatusEffect.Energized") {
			interactionSystem.DrankCoffeeFromChoice();
		}
	}

	return wrappedMethod(evt);
}

class DFInteractionSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFInteractionSystem> {
		//DFProfile();
		return DFInteractionSystem.Get();
	}
}

public final class DFInteractionSystem extends DFSystem {
	private let MainSystem: ref<DFMainSystem>;
    private let GameStateService: ref<DFGameStateService>;
	private let PlayerStateService: ref<DFPlayerStateService>;
	private let NotificationService: ref<DFNotificationService>;
	private let AnimationService: ref<DFAnimationService>;
    private let HydrationSystem: ref<DFHydrationSystem>;
	private let NutritionSystem: ref<DFNutritionSystem>;
	private let EnergySystem: ref<DFEnergySystem>;
	private let NerveSystem: ref<DFNerveSystem>;
	private let VehicleSleepSystem: ref<DFVehicleSleepSystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
	private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
	private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;
	private let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;
	private let RelaxActionSystem: ref<DFRelaxActionSystem>;

	private let QuestsSystem: ref<QuestsSystem>;
    private let BlackboardSystem: ref<BlackboardSystem>;
    private let UIInteractionsBlackboard: ref<IBlackboard>;

	// Choice Detection
	private let injectedInteractionIconEnumNames: array<CName>;
    private let choiceListener: ref<CallbackHandle>;
	private let choiceHubListener: ref<CallbackHandle>;

    private let lastAttemptedChoiceCaption: String;
	private let lastAttemptedChoiceIconName: CName;
	private let lastAttemptedInjectedInteractionIconName: CName;

    public let clearLastAttemptedChoiceForFXCheckDelayID: DelayID;
    private let clearLastAttemptedChoiceForFXCheckDelayInterval: Float = 10.0;

    // Location Memory from Prompts
	public let mq006_lastRollercoasterPosition: Vector4;
	private let lastCoffeePosition: Vector4;

	// Sleeping and Waiting
	private let skippingTimeFromHubMenu: Bool = false;
	private let lastEnergyBeforeSleeping: Float = 0.0;

	// Smoke prompt debounce timer (Compatibility with Idle Anywhere)
	public let smokePromptDebounceDelayID: DelayID;
	private let smokePromptDebounceDelayInterval: Float = 6.0;
	public let isWithinSmokePromptDebounceWindow: Bool = false;

	// Quest-related Sleep Journal Entry Updates
	private let journalEntryUpdate_JackieDeath_q005: DFJournalEntryUpdate;
	private let journalEntryUpdate_Cross_sq023: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq026: DFJournalEntryUpdate;
	private let journalEntryUpdate_Suicide_sq026: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq027: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq030: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q302: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq029: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq021: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q103a: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q103b: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq004: DFJournalEntryUpdate;
	private let journalEntryUpdate_Romance_q003: DFJournalEntryUpdate;
	private let journalEntryUpdate_LizziesBDs: DFJournalEntryUpdate;
	private let journalEntryUpdate_Ripperdoc_q001: DFJournalEntryUpdate;
	private let journalEntryUpdate_Funeral_sq018: DFJournalEntryUpdate;
	private let journalEntryUpdate_XBD_STSWatNID04: DFJournalEntryUpdate;
	private let journalEntryUpdate_BD_sq021: DFJournalEntryUpdate;
	private let journalEntryUpdate_Biocorruption_sq031: DFJournalEntryUpdate;

	// See: darkfuture/localization_interactions/*/onscreens/darkfuture_interactions_donotmodify.json
	private const let locKey_Interaction_Sleep_BaseGame: CName = n"DarkFutureInteraction_mq000_01_apartment_Sleep";
	private const let locKey_Interaction_Sleep_KressStreet: CName = n"DarkFutureInteraction_mq300_safehouse_Sleep";
	public const let locKey_Interaction_EnterRollercoaster: CName = n"DarkFutureInteraction_mq006_02_finale_EnterRollercoaster";
	public const let locKey_Interaction_MQ014MonkFinishPromptA: CName = n"DarkFutureInteraction_mq014_01_hook_MonkFinishPromptA";
	public const let locKey_Interaction_MQ014MonkFinishPromptB: CName = n"DarkFutureInteraction_mq014_03_second_MonkFinishPromptB";
	public const let locKey_Interaction_MQ014MonkFinishPromptC: CName = n"DarkFutureInteraction_mq014_05_third_MonkFinishPromptC";
	public const let locKey_Interaction_MQ014MonkFinishPromptD: CName = n"DarkFutureInteraction_mq014_07_fourth_MonkFinishPromptD";
	private const let locKey_Interaction_Cuddle: CName = n"DarkFutureInteraction_mq055_01_Cuddle";
	private const let locKey_Interaction_Kiss: CName = n"DarkFutureInteraction_mq055_01_Kiss";
	private const let locKey_Interaction_Dance: CName = n"DarkFutureInteraction_mq300_safehouse_Dance";
	public const let locKey_Interaction_Meditate: CName = n"DarkFutureInteraction_mq300_safehouse_Meditate";
	public const let locKey_Interaction_Q003TakeInhaler: CName = n"DarkFutureInteraction_q003_03_deal_TakeInhaler";
	private const let locKey_Interaction_Q003MeredithStoutPrompt: CName = n"DarkFutureInteraction_q003_08_stout_MeredithStoutPrompt";
	private const let locKey_Interaction_Eat: CName = n"DarkFutureInteraction_q112_01_market_02_Eat";
	private const let locKey_Interaction_Q303SitAndDrink: CName = n"DarkFutureInteraction_q303_04_SitAndDrink";
	private const let locKey_Interaction_Q303PlayBraindance: CName = n"DarkFutureInteraction_q303_10_concert_PlayBraindance";
	private const let locKey_Interaction_CoffeeDrink: CName = n"DarkFutureInteraction_sq017_06_capitan_caliente_Drink";
	private const let locKey_Interaction_DLC6DrinkTea: CName = n"DarkFutureInteraction_dlc6_apart_cct_dtn_DrinkTea";
	private const let locKey_Interaction_DLC6HitBall: CName = n"DarkFutureInteraction_dlc6_hey_gle_HitBall";
	private const let locKey_Interaction_DLC6BurnIncense: CName = n"DarkFutureInteraction_dlc6_apart_wbr_jpn_BurnIncense";
	private const let locKey_Interaction_Smoke: CName = n"DarkFutureInteraction_dlc6_apart_wbr_jpn_Smoke";
	private const let locKey_Interaction_TakeDrag: CName = n"DarkFutureInteraction_dlc6_apart_wbr_jpn_TakeDrag";
	private const let locKey_Interaction_ThrowBall: CName = n"DarkFutureInteraction_q302_06_basketball_Throw";
	private const let locKey_Interaction_SureThrowBall: CName = n"DarkFutureInteraction_q302_06_basketball_SureThrow";
	public const let locKey_Interaction_MistyTarotFirst: CName = n"DarkFutureInteraction_MistyTarot_First";
	public const let locKey_Interaction_MistyTarotRepeat: CName = n"DarkFutureInteraction_MistyTarot_Repeat";

	private const let questFact_MetroSelectedTrack: CName = n"ue_metro_track_selected";

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFInteractionSystem> {
		//DFProfile();
		let instance: ref<DFInteractionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFInteractionSystem>()) as DFInteractionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFInteractionSystem> {
		//DFProfile();
		return DFInteractionSystem.GetInstance(GetGameInstance());
	}

	public final func DoPostSuspendActions() -> Void {
		//DFProfile();
		this.lastAttemptedChoiceCaption = "";
		this.lastAttemptedChoiceIconName = n"";
		this.mq006_lastRollercoasterPosition = Vector4(0.0, 0.0, 0.0, 0.0);
		this.lastCoffeePosition = Vector4(0.0, 0.0, 0.0, 0.0);
		this.skippingTimeFromHubMenu = false;
		this.lastEnergyBeforeSleeping = 0.0;
	}
	public final func DoPostResumeActions() -> Void {}

	private final func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public final func SetupData() -> Void {
		//DFProfile();
		this.journalEntryUpdate_JackieDeath_q005 = DFJournalEntryUpdate("q005_heist", "return", "02_leave_delamain", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Cross_sq023 = DFJournalEntryUpdate("sq023_real_passion", "objectives", "bd_director", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_sq026 = DFJournalEntryUpdate("sq026_03_pizza", "01_pizza_night", "breakfast", gameJournalEntryState.Active);
		this.journalEntryUpdate_Suicide_sq026 = DFJournalEntryUpdate("sq026_01_suicide", "01_suicide", "evelyn_carry", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq027 = DFJournalEntryUpdate("sq027_01_basilisk_convoy", "03_ambush", "get_in_car", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq030 = DFJournalEntryUpdate("sq030_judy_romance", "hut", "stuff1", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_q302 = DFJournalEntryUpdate("q302_reed", "04_squot", "follow_myers3", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_sq029 = DFJournalEntryUpdate("sq029_sobchak_romance", "breakfast", "talk_with_river", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq021 = DFJournalEntryUpdate("sq021_sick_dreams", "bbq", "sleep", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_q103a = DFJournalEntryUpdate("q103_warhead", "roadhouse", "bed_upstairs", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_q103b = DFJournalEntryUpdate("q103_warhead", "roadhouse", "bed_downstairs", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_sq004 = DFJournalEntryUpdate("sq004_riders_on_the_storm", "03_escape", "panam_talk", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Romance_q003 = DFJournalEntryUpdate("q003_stout", "stout", "02_enjoy_evening", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_LizziesBDs = DFJournalEntryUpdate("main_quest", "select_bd", "watch_bd", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Ripperdoc_q001 = DFJournalEntryUpdate("q001_01_victor", "ripperdoc", "talk_to_viktor", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Funeral_sq018 = DFJournalEntryUpdate("sq018_jackie", "03_el_coyote_funeral", "03_take_part_in_ceremony", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_XBD_STSWatNID04 = DFJournalEntryUpdate("sts_wat_nid_04", "sts_wat_nid_04", "find_recording", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_BD_sq021 = DFJournalEntryUpdate("sq021_sick_dreams", "bd", "06_leave_bd", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Biocorruption_sq031 = DFJournalEntryUpdate("sq031_smack_my_bitch_up", "04_smack_motel", "03_talk_to_johnny", gameJournalEntryState.Succeeded);

		this.injectedInteractionIconEnumNames = [
			n"DarkFutureInteraction_Sleep_BaseGame",
			n"DarkFutureInteraction_Sleep_KressStreet",
			n"DarkFutureInteraction_EnterRollercoaster",
			n"DarkFutureInteraction_MQ014MonkFinishPromptA",
			n"DarkFutureInteraction_MQ014MonkFinishPromptB",
			n"DarkFutureInteraction_MQ014MonkFinishPromptC",
			n"DarkFutureInteraction_MQ014MonkFinishPromptD",
			n"DarkFutureInteraction_Cuddle",
			n"DarkFutureInteraction_Kiss",
			n"DarkFutureInteraction_Dance",
			n"DarkFutureInteraction_Meditate",
			n"DarkFutureInteraction_Q003TakeInhaler",
			n"DarkFutureInteraction_Q003MeredithStoutPrompt",
			n"DarkFutureInteraction_Eat",
			n"DarkFutureInteraction_Q303SitAndDrink",
			n"DarkFutureInteraction_Q303PlayBraindance",
			n"DarkFutureInteraction_CoffeeDrink",
			n"DarkFutureInteraction_DLC6DrinkTea",
			n"DarkFutureInteraction_DLC6HitBall",
			n"DarkFutureInteraction_DLC6BurnIncense",
			n"DarkFutureInteraction_Smoke",
			n"DarkFutureInteraction_TakeDrag",
			n"DarkFutureInteraction_ThrowBall",
			n"DarkFutureInteraction_SureThrowBall",
			n"DarkFutureInteraction_MistyTarotFirst",
			n"DarkFutureInteraction_MistyTarotRepeat"
		];
	}

	private final func RegisterAllRequiredDelayCallbacks() -> Void {}
	public final func OnTimeSkipStart() -> Void {}
	public final func OnTimeSkipCancelled() -> Void {}
	public final func OnTimeSkipBegin() -> Void {}
	public final func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}
    public final func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	public func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
        // This system does not have a system-specific toggle.
		return true;
    }

	private final func GetSystemToggleSettingString() -> String {
		//DFProfile();
		// This system does not have a system-specific toggle.
        return "INVALID";
    }

	public final func GetSystems() -> Void {
		//DFProfile();
		let gameInstance: GameInstance = GetGameInstance();
		
		this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
		this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
		this.NotificationService = DFNotificationService.GetInstance(gameInstance);
		this.AnimationService = DFAnimationService.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
		this.VehicleSleepSystem = DFVehicleSleepSystem.GetInstance(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
		this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
		this.HumanityLossConditionSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
		this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
		this.RelaxActionSystem = DFRelaxActionSystem.GetInstance(gameInstance);
        this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
		this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
	}

	private final func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		this.UIInteractionsBlackboard = this.BlackboardSystem.Get(GetAllBlackboardDefs().UIInteractions);
	}

	public final func UnregisterAllDelayCallbacks() -> Void {
		//DFProfile();
		this.UnregisterClearLastAttemptedChoiceForFXCheckCallback();
	}

    private final func RegisterListeners() -> Void {
		//DFProfile();
        this.RegisterChoiceListener();
        this.RegisterChoiceHubListener();
    }

    private final func UnregisterListeners() -> Void {
		//DFProfile();
        this.UnregisterChoiceListener();
        this.UnregisterChoiceHubListener();
    }

    private final func RegisterChoiceListener() -> Void {
		//DFProfile();
		this.choiceListener = this.UIInteractionsBlackboard.RegisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this, n"OnLastAttemptedChoice");
	}

    private final func RegisterChoiceHubListener() -> Void {
		//DFProfile();
		this.choiceHubListener = this.UIInteractionsBlackboard.RegisterListenerVariant(GetAllBlackboardDefs().UIInteractions.DialogChoiceHubs, this, n"OnChoiceHub");
	}

    private final func UnregisterChoiceListener() -> Void {
		//DFProfile();
		this.UIInteractionsBlackboard.UnregisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this.choiceListener);
	}

	private final func UnregisterChoiceHubListener() -> Void {
		//DFProfile();
		this.UIInteractionsBlackboard.UnregisterListenerVariant(GetAllBlackboardDefs().UIInteractions.DialogChoiceHubs, this.choiceHubListener);
	}

    //
    //  Interaction Choices
    //
    private final func IsSleepChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		if (Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Sleep_BaseGame)) || Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Sleep_KressStreet))) && Equals(choiceIconName, n"Wait") {
			return true;
		}

		return false;
	}

	private final func IsNerveRegenInteractionChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		// Multiple Apartment / Location Interactions
		if Equals(choiceIconName, n"Shower") {
			return true;

		} else if Equals(choiceIconName, n"Dance") {
			return true;

		}

		return false;
	}

    private final func IsNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		// Romantic Activities
		if Equals(choiceIconName, n"Prostitute") {
			return true;

		// Rollercoaster
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_EnterRollercoaster)) && Vector4.DistanceSquared(this.mq006_lastRollercoasterPosition, this.player.GetWorldPosition()) < 10.0 {
			return true;

		// Zen Master meditation sessions
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptA)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptB)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptC)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptD)) {
			return true;

		// Phantom Liberty: Kress Street Hideout Interactions
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Meditate)) {
			return true;

		// Phantom Liberty: Bootleg Shard (V's Apartment)
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Q303PlayBraindance)) {
			return true;
		}

		return false;
	}

    private final func IsSmallNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_DLC6BurnIncense)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_DLC6HitBall)) {
			return true;
		} else if Equals(choiceIconName, n"PlayGuitar") {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Kiss)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Cuddle)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_ThrowBall)) {
			return true;
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_SureThrowBall)) {
			return true;
		}

		return false;
	}

    private final func IsHydrationRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		return this.IsDrinkTeaInCorpoPlazaChoice(choiceCaption) || this.IsDrinkTeaWithMrHandsChoice(choiceCaption);
	}

    private final func IsDrinkTeaInCorpoPlazaChoice(choiceCaption: String) -> Bool {
		//DFProfile();
		// Corpo Plaza Apartment Interaction
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_DLC6DrinkTea)) {
			return true;
		}

		return false;
	}

	private final func IsDrinkTeaWithMrHandsChoice(choiceCaption: String) -> Bool {
		//DFProfile();
		// Phantom Liberty: Mr. Hands scene in Heavy Hearts Club
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Q303SitAndDrink)) {
			return true;
		}

		return false;
	}

    private final func IsDrinkCoffeeInDialogChoice(choiceCaption: String) -> Bool {
		//DFProfile();
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_CoffeeDrink)) && Vector4.DistanceSquared(this.lastCoffeePosition, this.player.GetWorldPosition()) < 10.0 {
			return true;
		}

		return false;
	}

    private final func IsNutritionRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		//DFProfile();
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Eat)) {
			return true;
		}

		return false;
	}

	private final func HandleIsHumanityLossRestoreChoice(captionParts: array<ref<InteractionChoiceCaptionPart>>, choiceCaption: String, choiceIconName: CName) -> Void {
		let onMetro: Bool = this.QuestsSystem.GetFact(this.questFact_MetroSelectedTrack) > 0;

		// Meditation
		if Equals(choiceIconName, n"Sit") && Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Meditate)) {
			this.HumanityLossConditionSystem.TryToRestoreHumanityLossFromMeditation();
		
		// Zen Masters
		} else if Equals(choiceIconName, n"GetUp") && (Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptA)) ||
													   Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptB)) ||
													   Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptC)) || 
						                               Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_MQ014MonkFinishPromptD))) {
					
					this.HumanityLossConditionSystem.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMinor);

		// Rollercoaster
		} else if Equals(choiceIconName, n"GetIn") && Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_EnterRollercoaster)) && Vector4.DistanceSquared(this.mq006_lastRollercoasterPosition, this.player.GetWorldPosition()) < 10.0 {
			this.HumanityLossConditionSystem.TryToRestoreHumanityLossFromRollercoaster();

		// Dance, Vibe Out
		} else if Equals(choiceIconName, n"Dance") {
			this.HumanityLossConditionSystem.TryToRestoreHumanityLossFromDance();

		// Romantic Hangouts
		} else if Equals(choiceIconName, n"Wait") {
			let journalManager: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
			let romanceLeaveObjectiveBeforeSleep: ref<JournalQuestObjectiveBase> = journalManager.GetEntryByString("quests/minor_quest/mq055_romance_apartment/06_date/leave_end", "gameJournalQuestObjective") as JournalQuestObjectiveBase;
			let apartmentRomanceActive: Bool = Equals(journalManager.GetEntryState(romanceLeaveObjectiveBeforeSleep), gameJournalEntryState.Active) && journalManager.GetIsObjectiveOptional(romanceLeaveObjectiveBeforeSleep);

			if apartmentRomanceActive {
				this.HumanityLossConditionSystem.TryToRestoreHumanityLossFromIntimacy();
			}
		
		// Metro Beggar
		} else if onMetro {
			let foundMetroBeggarChoice: Bool = false;
			for captionPart in captionParts {
				// Metro - Infer if this choice was giving to the beggar.
				if Equals(captionPart.GetType(), gamedataChoiceCaptionPartType.Blueline) {
					let asBluelineChoicePart: ref<InteractionChoiceCaptionBluelinePart> = captionPart as InteractionChoiceCaptionBluelinePart;
					for bluelinePart in asBluelineChoicePart.blueline.parts {
						let asPayment: ref<PaymentBluelinePart> = bluelinePart as PaymentBluelinePart;
						if IsDefined(asPayment) && asPayment.passed {
							// We selected a payment option, and we are on the metro. We gave to the beggar.
							this.HumanityLossConditionSystem.TryToRestoreHumanityLossFromCharity();
							foundMetroBeggarChoice = true;
						}
						if foundMetroBeggarChoice { break; }
					}
				}
				if foundMetroBeggarChoice { break; }
			}
		}
	}

	private final func IsDumDumBlackLaceChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Q003TakeInhaler)) {
			return true;
		}

		return false;
	}

	//
	//	Sleeping and Waiting
	//
	public final func SetSkippingTimeFromHubMenu(value: Bool) -> Void {
		//DFProfile();
		this.skippingTimeFromHubMenu = value;
	}

	public final func IsPlayerSleeping() -> Bool {
		//DFProfile();
		if !this.skippingTimeFromHubMenu && !this.IsImmersiveTimeskipActive() {
			return true;
		}

		return false;
	}

	public final func CalculateAddictionWithdrawalStateFromTimeSkip(
		logName: String,
		addictionSystem: ref<DFAddictionSystemBase>,
		addictionAmount: Float,
		addictionAmountAsPercentage: Float,
		addictionStage: Int32, 
		activeEffectApplied: Bool, 
		backoffDuration: Float, 
		withdrawalLevel: Int32, 
		withdrawalDuration: Float,
		currentHour: Int32,
		hasLostAddictionAmountToday: Bool,
		hasEuphoria: Bool
	) -> DFAddictionTimeSkipIterationStateDatum {
		//DFProfile();
		
		let withdrawalDurations: array<Float> = addictionSystem.GetAddictionWithdrawalDurationsInGameTimeSeconds();
		let addictionBackoffDurations: array<Float> = addictionSystem.GetAddictionBackoffDurationsInGameTimeSecondsByStage();

		if currentHour == 0 && !hasLostAddictionAmountToday {
			addictionAmount = MaxF(addictionAmount - addictionSystem.GetAddictionAmountLossPerDay(), 0.0);
			addictionAmountAsPercentage = addictionSystem.GetAddictionAmountAsPercentageToNextStageInProvidedState(addictionAmount, addictionStage);
			hasLostAddictionAmountToday = true;
		}

		// Is the player currently addicted?
		if addictionStage > 0 {
			// Does the player have a backoff duration, taking into account pre-existing durations?
			if backoffDuration > 0.0 {
				backoffDuration -= 300.0;
				if backoffDuration <= 0.0 {
					backoffDuration = 0.0;
					withdrawalLevel = 1;
					if withdrawalLevel < addictionStage {
						withdrawalDuration = HoursToGameTimeSeconds(2);
					} else {
						withdrawalDuration = withdrawalDurations[withdrawalLevel];
					}
				}
			// If not, does the player have a withdrawal duration, taking into account pre-existing durations?
			} else if withdrawalDuration > 0.0 {
				withdrawalDuration -= 300.0;
				if withdrawalDuration <= 0.0 {
					// The withdrawal has expired. Should their withdrawal advance, or are they cured?
					withdrawalDuration = 0.0;
					if withdrawalLevel == 5 {
						// Cured
						withdrawalLevel = 0;
						addictionStage = 0;
					} else {
						// Advance
						if withdrawalLevel < addictionStage {
							withdrawalLevel += 1;
						} else {
							// Cessation
							withdrawalLevel = 5;
						}
					}

					if withdrawalLevel > 0 {
						if withdrawalLevel < addictionStage {
							withdrawalDuration = HoursToGameTimeSeconds(2);
						} else {
							withdrawalDuration = withdrawalDurations[withdrawalLevel];
						}
					}
				}

			} else if activeEffectApplied && !hasEuphoria {
				activeEffectApplied = false;
				
				// The primary effect expired; start a fake back-off timer.
				backoffDuration = addictionBackoffDurations[addictionStage];
			}
		}

		/*DFLog(this, "=====================================================================================");

		DFLog(this, "Predictive " + logName + " AddictionAmount: " + ToString(addictionAmount));
		DFLog(this, "Predictive " + logName + " AddictionAmountAsPercentage: " + ToString(addictionAmountAsPercentage));
		DFLog(this, "Predictive " + logName + " AddictionStage: " + ToString(addictionStage));
		DFLog(this, "Predictive " + logName + " BackoffDuration: " + ToString(backoffDuration));
		DFLog(this, "Predictive " + logName + " WithdrawalDuration: " + ToString(withdrawalDuration));
		DFLog(this, "Predictive " + logName + " WithdrawalLevel: " + ToString(withdrawalLevel));
		DFLog(this, "Predictive " + logName + " activeEffectApplied: " + ToString(activeEffectApplied));

		DFLog(this, "=====================================================================================");
		*/

		let addictionTimeSkipIterationStateData: DFAddictionTimeSkipIterationStateDatum;
		addictionTimeSkipIterationStateData.addictionAmount = addictionAmount;
		addictionTimeSkipIterationStateData.addictionAmountAsPercentage = addictionAmountAsPercentage;
		addictionTimeSkipIterationStateData.addictionStage = addictionStage;
		addictionTimeSkipIterationStateData.activeEffectApplied = activeEffectApplied;
		addictionTimeSkipIterationStateData.backoffDuration = backoffDuration;
		addictionTimeSkipIterationStateData.withdrawalLevel = withdrawalLevel;
		addictionTimeSkipIterationStateData.withdrawalDuration = withdrawalDuration;
		addictionTimeSkipIterationStateData.hasLostAddictionAmountToday = hasLostAddictionAmountToday;

		return addictionTimeSkipIterationStateData;
	}

	public final func GetCalculatedValuesForFutureHours(timeSkipType: DFTimeSkipType, startingHour: Int32) -> DFFutureHoursData {
		//DFProfile();
		let isSleeping: Bool = DFIsSleeping(timeSkipType);

		// Need Variables
		let calculatedBasicNeedsData: array<DFNeedsDatum>;
		let calculatedHydrationAtHour: Float = this.HydrationSystem.GetNeedValue();
		let calculatedHydrationMaxAtHour: Float = this.HydrationSystem.GetNeedMax();
		let calculatedNutritionAtHour: Float = this.NutritionSystem.GetNeedValue();
		let calculatedNutritionMaxAtHour: Float = this.NutritionSystem.GetNeedMax();
		let calculatedEnergyAtHour: Float = this.EnergySystem.GetNeedValue();
		let calculatedEnergyMaxAtHour: Float = this.EnergySystem.GetNeedMax();
		let calculatedNerveAtHour: Float = this.NerveSystem.GetNeedValue();
		let calculatedEuphoriaAtHour: Float = this.NerveSystem.GetOverchargeValue();
		let calculatedNerveMaxAtHour: Float = this.NerveSystem.GetNeedMax();

		let calculatedDelayedHydrationAtHour: Float = this.HydrationSystem.GetAccumulatedDelayedNeedLoss();
		let calculatedDelayedNutritionAtHour: Float = this.NutritionSystem.GetAccumulatedDelayedNeedLoss();
		let calculatedDelayedEnergyAtHour: Float = this.EnergySystem.GetAccumulatedDelayedNeedLoss();

		// Energy Variables
		let managedEffectState: array<DFManagedEffect> = this.PlayerStateService.GetManagedEffectsState();

		// Addiction Variables
		let calculatedAddictionData: array<DFAddictionDatum>;

		// Alcohol Variables
		let alcoholDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		alcoholDataAccumulator.addictionAmount = this.AlcoholAddictionSystem.GetAddictionAmount();
		alcoholDataAccumulator.addictionAmountAsPercentage = this.AlcoholAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
		alcoholDataAccumulator.withdrawalLevel = this.AlcoholAddictionSystem.GetWithdrawalLevel();
		alcoholDataAccumulator.addictionStage = this.AlcoholAddictionSystem.GetAddictionStage();
		alcoholDataAccumulator.backoffDuration = this.AlcoholAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		alcoholDataAccumulator.withdrawalDuration = this.AlcoholAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		alcoholDataAccumulator.activeEffectApplied = this.PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Alcohol) > 0u;

		// Nicotine Variables
		let nicotineDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		nicotineDataAccumulator.addictionAmount = this.NicotineAddictionSystem.GetAddictionAmount();
		nicotineDataAccumulator.addictionAmountAsPercentage = this.NicotineAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
		nicotineDataAccumulator.withdrawalLevel = this.NicotineAddictionSystem.GetWithdrawalLevel();
		nicotineDataAccumulator.addictionStage = this.NicotineAddictionSystem.GetAddictionStage();
		nicotineDataAccumulator.backoffDuration = this.NicotineAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		nicotineDataAccumulator.withdrawalDuration = this.NicotineAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		nicotineDataAccumulator.activeEffectApplied = this.PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Nicotine) > 0u;

		// Narcotic Variables
		let narcoticDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		narcoticDataAccumulator.addictionAmount = this.NarcoticAddictionSystem.GetAddictionAmount();
		narcoticDataAccumulator.addictionAmountAsPercentage = this.NarcoticAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
		narcoticDataAccumulator.withdrawalLevel = this.NarcoticAddictionSystem.GetWithdrawalLevel();
		narcoticDataAccumulator.addictionStage = this.NarcoticAddictionSystem.GetAddictionStage();
		narcoticDataAccumulator.backoffDuration = this.NarcoticAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		narcoticDataAccumulator.withdrawalDuration = this.NarcoticAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		narcoticDataAccumulator.activeEffectApplied = this.PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Narcotic) > 0u;

		// Store the original withdrawal level values.
		let originalAlcoholWithdrawalLevel: Int32 = alcoholDataAccumulator.withdrawalLevel;
		let originalNicotineWithdrawalLevel: Int32 = nicotineDataAccumulator.withdrawalLevel;
		let originalNarcoticWithdrawalLevel: Int32 = narcoticDataAccumulator.withdrawalLevel;

		// Addiction Treatment Variables
		let addictionTreatmentDuration: Float = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();

		// Humanity Loss Variables
		let calculatedHumanityLossData: array<DFHumanityLossDatum>;

		let humanityLossDataAccumulator: DFHumanityLossTimeSkipIterationStateDatum;
		humanityLossDataAccumulator.level = this.HumanityLossConditionSystem.GetConditionLevel();
		humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed = this.HumanityLossConditionSystem.GetTimeUntilNextCyberpsychosisAllowed();
		humanityLossDataAccumulator.newEndotrisineDuration = this.HumanityLossConditionSystem.GetRemainingEndotrisineDurationInGameTimeSeconds();

		// Biocorruption Variables
		let calculatedBiocorruptionData: array<DFBiocorruptionDatum>;

		let biocorruptionDataAccumulator: DFBiocorruptionTimeSkipIterationStateDatum;
		biocorruptionDataAccumulator.newCrashDuration = this.BiocorruptionConditionSystem.GetRemainingCrashStackDurationInGameTimeSeconds();
		biocorruptionDataAccumulator.newCrashStackCount = this.BiocorruptionConditionSystem.GetLastKnownCrashStackCount();
		biocorruptionDataAccumulator.highestCrashStackCount = biocorruptionDataAccumulator.newCrashStackCount;
		biocorruptionDataAccumulator.newTimeUntilRestless = this.BiocorruptionConditionSystem.GetRemainingTimeUntilRestlessInGameTimeSeconds();
		biocorruptionDataAccumulator.isRestless = false;
		biocorruptionDataAccumulator.crashOccuredDuringTimeskip = false;

		let i: Int32 = 0;
		while i < 24 { // Iterate over each hour
			let needHydration: DFNeedChangeDatum = DFNeedChangeDatum(0.0, 0.0, 0.0, 100.0, false, 0.0);
			let needNutrition: DFNeedChangeDatum = DFNeedChangeDatum(0.0, 0.0, 0.0, 100.0, false, 0.0);
			let needEnergy: DFNeedChangeDatum = DFNeedChangeDatum(0.0, 0.0, 0.0, 100.0, false, 0.0);
			let needNerve: DFNeedChangeDatum = DFNeedChangeDatum(0.0, 0.0, 0.0, 100.0, false, 0.0);

			let basicNeedsData: DFNeedsDatum;
			basicNeedsData.hydration = needHydration;
			basicNeedsData.nutrition = needNutrition;
			basicNeedsData.energy = needEnergy;
			basicNeedsData.nerve = needNerve;
			
			let addictionAlcohol: DFAddictionUpdateDatum;
			addictionAlcohol.addictionAmount = alcoholDataAccumulator.addictionAmount;
			addictionAlcohol.addictionAmountAsPercentage = alcoholDataAccumulator.addictionAmountAsPercentage;
			addictionAlcohol.addictionStage = alcoholDataAccumulator.addictionStage;
			addictionAlcohol.withdrawalLevel = alcoholDataAccumulator.withdrawalLevel;
			addictionAlcohol.remainingBackoffDuration = alcoholDataAccumulator.backoffDuration;
			addictionAlcohol.remainingWithdrawalDuration = alcoholDataAccumulator.withdrawalDuration;

			let addictionNicotine: DFAddictionUpdateDatum;
			addictionNicotine.addictionAmount = nicotineDataAccumulator.addictionAmount;
			addictionNicotine.addictionAmountAsPercentage = nicotineDataAccumulator.addictionAmountAsPercentage;
			addictionNicotine.addictionStage = nicotineDataAccumulator.addictionStage;
			addictionNicotine.withdrawalLevel = nicotineDataAccumulator.withdrawalLevel;
			addictionNicotine.remainingBackoffDuration = nicotineDataAccumulator.backoffDuration;
			addictionNicotine.remainingWithdrawalDuration = nicotineDataAccumulator.withdrawalDuration;

			let addictionNarcotic: DFAddictionUpdateDatum;
			addictionNarcotic.addictionAmount = narcoticDataAccumulator.addictionAmount;
			addictionNarcotic.addictionAmountAsPercentage = narcoticDataAccumulator.addictionAmountAsPercentage;
			addictionNarcotic.addictionStage = narcoticDataAccumulator.addictionStage;
			addictionNarcotic.withdrawalLevel = narcoticDataAccumulator.withdrawalLevel;
			addictionNarcotic.remainingBackoffDuration = narcoticDataAccumulator.backoffDuration;
			addictionNarcotic.remainingWithdrawalDuration = narcoticDataAccumulator.withdrawalDuration;

			let addictionData: DFAddictionDatum;
			addictionData.alcohol = addictionAlcohol;
			addictionData.nicotine = addictionNicotine;
			addictionData.narcotic = addictionNarcotic;

			let humanityLossData: DFHumanityLossDatum;
			humanityLossData.newTimeUntilNextCyberpsychosisAllowed = humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed;
			humanityLossData.newEndotrisineDuration = humanityLossDataAccumulator.newEndotrisineDuration;

			let biocorruptionData: DFBiocorruptionDatum;
			biocorruptionData.newCrashDuration = biocorruptionDataAccumulator.newCrashDuration;
			biocorruptionData.newCrashStackCount = biocorruptionDataAccumulator.newCrashStackCount;
			biocorruptionData.highestCrashStackCount = biocorruptionDataAccumulator.highestCrashStackCount;
			biocorruptionData.newTimeUntilRestless = biocorruptionDataAccumulator.newTimeUntilRestless;
			biocorruptionData.isRestless = biocorruptionDataAccumulator.isRestless;
			biocorruptionData.crashOccuredDuringTimeskip = biocorruptionDataAccumulator.crashOccuredDuringTimeskip;

			let showNerveLock: Bool = false;
			let showEnergyLock: Bool = false;

			// Accumulate all of the changes by iterating over each update cycle within the hour (60 / 12, or every 5 minutes)
			let j: Int32 = 1;
			while j <= 12 {
				//
				// Addiction
				//
				let currentHour: Int32 = startingHour + i;
				if currentHour > 23 {
					currentHour = (startingHour + i) - 24;
				}
				DFLog(this, "startingHour = " + ToString(startingHour) + ", currentHour = " + ToString(currentHour));

				let nicotineDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Nicotine", 
					this.NicotineAddictionSystem,
					nicotineDataAccumulator.addictionAmount,
					nicotineDataAccumulator.addictionAmountAsPercentage,
					nicotineDataAccumulator.addictionStage, 
					nicotineDataAccumulator.activeEffectApplied, 
					nicotineDataAccumulator.backoffDuration,
					nicotineDataAccumulator.withdrawalLevel, 
					nicotineDataAccumulator.withdrawalDuration,
					currentHour,
					nicotineDataAccumulator.hasLostAddictionAmountToday,
					calculatedEuphoriaAtHour > 0.0
				);

				let alcoholDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Alcohol", 
					this.AlcoholAddictionSystem,
					alcoholDataAccumulator.addictionAmount,
					alcoholDataAccumulator.addictionAmountAsPercentage,
					alcoholDataAccumulator.addictionStage, 
					alcoholDataAccumulator.activeEffectApplied, 
					alcoholDataAccumulator.backoffDuration,
					alcoholDataAccumulator.withdrawalLevel, 
					alcoholDataAccumulator.withdrawalDuration,
					currentHour,
					alcoholDataAccumulator.hasLostAddictionAmountToday,
					calculatedEuphoriaAtHour > 0.0
				);

				let narcoticDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Narcotic", 
					this.NarcoticAddictionSystem,
					narcoticDataAccumulator.addictionAmount,
					narcoticDataAccumulator.addictionAmountAsPercentage,
					narcoticDataAccumulator.addictionStage, 
					narcoticDataAccumulator.activeEffectApplied, 
					narcoticDataAccumulator.backoffDuration,
					narcoticDataAccumulator.withdrawalLevel, 
					narcoticDataAccumulator.withdrawalDuration,
					currentHour,
					narcoticDataAccumulator.hasLostAddictionAmountToday,
					calculatedEuphoriaAtHour > 0.0
				);

				// Update the accumulators.
				alcoholDataAccumulator.activeEffectApplied = alcoholDataForIter.activeEffectApplied;
				alcoholDataAccumulator.addictionAmount = alcoholDataForIter.addictionAmount;
				alcoholDataAccumulator.addictionAmountAsPercentage = alcoholDataForIter.addictionAmountAsPercentage;
				alcoholDataAccumulator.addictionStage = alcoholDataForIter.addictionStage;
				alcoholDataAccumulator.withdrawalLevel = alcoholDataForIter.withdrawalLevel;
				alcoholDataAccumulator.backoffDuration = alcoholDataForIter.backoffDuration;
				alcoholDataAccumulator.withdrawalDuration = alcoholDataForIter.withdrawalDuration;
				alcoholDataAccumulator.isWithdrawalLevelWorsened = alcoholDataForIter.withdrawalLevel > originalAlcoholWithdrawalLevel && alcoholDataForIter.withdrawalLevel != 5;
				alcoholDataAccumulator.hasLostAddictionAmountToday = alcoholDataForIter.hasLostAddictionAmountToday;

				nicotineDataAccumulator.activeEffectApplied = nicotineDataForIter.activeEffectApplied;
				nicotineDataAccumulator.addictionAmount = nicotineDataForIter.addictionAmount;
				nicotineDataAccumulator.addictionAmountAsPercentage = nicotineDataForIter.addictionAmountAsPercentage;
				nicotineDataAccumulator.addictionStage = nicotineDataForIter.addictionStage;
				nicotineDataAccumulator.withdrawalLevel = nicotineDataForIter.withdrawalLevel;
				nicotineDataAccumulator.backoffDuration = nicotineDataForIter.backoffDuration;
				nicotineDataAccumulator.withdrawalDuration = nicotineDataForIter.withdrawalDuration;
				nicotineDataAccumulator.isWithdrawalLevelWorsened = nicotineDataForIter.withdrawalLevel > originalNicotineWithdrawalLevel && nicotineDataForIter.withdrawalLevel != 5;
				nicotineDataAccumulator.hasLostAddictionAmountToday = nicotineDataForIter.hasLostAddictionAmountToday;

				narcoticDataAccumulator.activeEffectApplied = narcoticDataForIter.activeEffectApplied;
				narcoticDataAccumulator.addictionAmount = narcoticDataForIter.addictionAmount;
				narcoticDataAccumulator.addictionAmountAsPercentage = narcoticDataForIter.addictionAmountAsPercentage;
				narcoticDataAccumulator.addictionStage = narcoticDataForIter.addictionStage;
				narcoticDataAccumulator.withdrawalLevel = narcoticDataForIter.withdrawalLevel;
				narcoticDataAccumulator.backoffDuration = narcoticDataForIter.backoffDuration;
				narcoticDataAccumulator.withdrawalDuration = narcoticDataForIter.withdrawalDuration;
				narcoticDataAccumulator.isWithdrawalLevelWorsened = narcoticDataForIter.withdrawalLevel > originalNarcoticWithdrawalLevel && narcoticDataForIter.withdrawalLevel != 5;
				narcoticDataAccumulator.hasLostAddictionAmountToday = narcoticDataForIter.hasLostAddictionAmountToday;

				//
				// Biocorruption
				//
				let crashedOnThisIter: Bool = false;

				// Calculate the Biocorruption Level. Because the Addiction states are the source of truth for the level, we don't store it in an accumulator.
				let biocorruptionLevelAtIter: Uint32 = this.BiocorruptionConditionSystem.GetCalculatedBiocorruptionLevelInProvidedState(alcoholDataAccumulator.addictionStage, nicotineDataAccumulator.addictionStage, narcoticDataAccumulator.addictionStage, alcoholDataAccumulator.addictionAmountAsPercentage, nicotineDataAccumulator.addictionAmountAsPercentage, narcoticDataAccumulator.addictionAmountAsPercentage);
				DFLog(this, "biocorruptionLevelAtIter: " + ToString(biocorruptionLevelAtIter));

				// Allow the Crash duration to reduce if the player is NOT sleeping, NOT euphoric, and
				if (!isSleeping || (isSleeping && !biocorruptionDataAccumulator.crashOccuredDuringTimeskip)) && calculatedEuphoriaAtHour == 0.0 && biocorruptionDataAccumulator.newCrashStackCount > 0u {
					biocorruptionDataAccumulator.newCrashDuration = ClampF(biocorruptionDataAccumulator.newCrashDuration - 300.0, 0.0, HoursToGameTimeSeconds(0.5));
					if biocorruptionDataAccumulator.newCrashDuration <= 0.0 {
						DFLog(this, "Would remove Crash stack this iter.");

						if biocorruptionDataAccumulator.newCrashStackCount > 0u {
							biocorruptionDataAccumulator.newCrashStackCount -= 1u;
							biocorruptionDataAccumulator.newCrashDuration = HoursToGameTimeSeconds(0.5);
						} else {
							biocorruptionDataAccumulator.newCrashDuration = 0.0;
						}						
					}
				}

				//
				// Nutrition and Hydration
				//
				let nutritionChangeTemp: DFNeedChangeWithRecoverLimit = this.NutritionSystem.GetNeedChangeWithRecoverLimit(calculatedNutritionAtHour, isSleeping, calculatedEuphoriaAtHour > 0.0);
				calculatedDelayedNutritionAtHour += nutritionChangeTemp.delayedLoss;

				let hydrationChangeTemp: DFNeedChangeWithRecoverLimit = this.HydrationSystem.GetNeedChangeWithRecoverLimit(calculatedHydrationAtHour, isSleeping, calculatedEuphoriaAtHour > 0.0);
				calculatedDelayedHydrationAtHour += hydrationChangeTemp.delayedLoss;
				
				//
				// Nerve
				//
				// Allow Nerve to recover.
				let nerveSoftCapAtIter: Float = this.HumanityLossConditionSystem.GetNerveSoftCapFromHumanityLossAtLevel(humanityLossDataAccumulator.level);
				let hydrationStageAtHour: Int32 = this.HydrationSystem.GetNeedStageAtValue(calculatedHydrationAtHour);
				let nutritionStageAtHour: Int32 = this.NutritionSystem.GetNeedStageAtValue(calculatedNutritionAtHour);
				let energyStageAtHour: Int32 = this.EnergySystem.GetNeedStageAtValue(calculatedEnergyAtHour);

				if calculatedEuphoriaAtHour > 0.0 {
					// Euphoria depletes at a constant rate before Nerve.
					let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, calculatedEuphoriaAtHour, hydrationStageAtHour, nutritionStageAtHour, energyStageAtHour);
					calculatedEuphoriaAtHour += nerveChangeTemp;
					if calculatedEuphoriaAtHour <= 0.0 {
						calculatedEuphoriaAtHour = 0.0;
						crashedOnThisIter = true;

						// Crash.
						biocorruptionDataAccumulator.newCrashDuration = HoursToGameTimeSeconds(0.5);
						biocorruptionDataAccumulator.newCrashStackCount += this.BiocorruptionConditionSystem.crashStacksAfterEuphoriaPerBiocorruptionLevel[Cast<Int32>(biocorruptionLevelAtIter)];
						if biocorruptionDataAccumulator.newCrashStackCount > this.BiocorruptionConditionSystem.GetMaxCrashStackCount() {
							biocorruptionDataAccumulator.newCrashStackCount = this.BiocorruptionConditionSystem.GetMaxCrashStackCount();
						}

						biocorruptionDataAccumulator.crashOccuredDuringTimeskip = true;
						
						// Track the highest Crash stack count so that we can play the most severe animation even if the player waits for all of them to expire.
						if biocorruptionDataAccumulator.newCrashStackCount > biocorruptionDataAccumulator.highestCrashStackCount {
							biocorruptionDataAccumulator.highestCrashStackCount = biocorruptionDataAccumulator.newCrashStackCount;
						}

						// Allow any Addictions to progress their Withdrawals in the next iteration.

						DFLog(this, "CRASHED on this iter!");
					}

				} else {
					if Equals(timeSkipType, DFTimeSkipType.Blackout) {
						// Don't change Nerve when blacking out. (Prevents dying after waking up)

					} else if Equals(timeSkipType, DFTimeSkipType.FullSleep) {
						if calculatedNerveAtHour <= nerveSoftCapAtIter && hydrationStageAtHour < 3 && nutritionStageAtHour < 3 {
							// Recover Nerve when sleeping in a bed.
							calculatedNerveAtHour += this.NerveSystem.nerveRecoverAmountSleeping;

							if calculatedNerveAtHour > this.NerveSystem.nerveRecoverAmountSleepingMax {
								calculatedNerveAtHour = this.NerveSystem.nerveRecoverAmountSleepingMax;
							}

							if calculatedNerveAtHour >= nerveSoftCapAtIter {
								calculatedNerveAtHour = nerveSoftCapAtIter;
								if nerveSoftCapAtIter < 100.0 {
									showNerveLock = true;
								}
							}
						} else {
							let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, calculatedEuphoriaAtHour, hydrationStageAtHour, nutritionStageAtHour, energyStageAtHour);
							calculatedNerveAtHour += nerveChangeTemp;
						}

					} else {
						let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, calculatedEuphoriaAtHour, hydrationStageAtHour, nutritionStageAtHour, energyStageAtHour);
						calculatedNerveAtHour += nerveChangeTemp;
					}
				}

				//
				// Biocorruption
				//
				
				// Does the player have a Restless duration?
				if biocorruptionDataAccumulator.newTimeUntilRestless > 0.0 {
					biocorruptionDataAccumulator.newTimeUntilRestless = ClampF(biocorruptionDataAccumulator.newTimeUntilRestless - 300.0, 0.0, HoursToGameTimeSeconds(48));
				}

				// Are they Restless?
				if biocorruptionDataAccumulator.newTimeUntilRestless == 0.0 && biocorruptionLevelAtIter > 0u {
					biocorruptionDataAccumulator.isRestless = true;
				} else {
					biocorruptionDataAccumulator.isRestless = false;
				}

				//
				// Energy
				//
				let energyChangeTemp: DFNeedChangeWithRecoverLimit = this.EnergySystem.GetNeedChangeWithRecoverLimit(
					                                                       calculatedEnergyAtHour, 
																		   timeSkipType, 
																		   calculatedEuphoriaAtHour > 0.0,
																		   biocorruptionDataAccumulator.isRestless,
																		   calculatedDelayedEnergyAtHour);

				DFLog(this, "energyChangeTemp.change: " + ToString(energyChangeTemp.change) + ", energyChangeTemp.delayedLoss: " + ToString(energyChangeTemp.delayedLoss));
				calculatedDelayedEnergyAtHour += energyChangeTemp.delayedLoss;
				showEnergyLock = energyChangeTemp.showLock;
				let energyMax: Float = this.EnergySystem.GetNeedMax();
				DFLog(this, "energyChangeTemp.needMax: " + ToString(energyMax));

				// Nuke any temporary Energy effects the player might have.
				let energy_i: Int32 = 0;
				while energy_i < ArraySize(managedEffectState) {
					let canClear: Bool = false;
					if Equals(managedEffectState[energy_i].effectMode, DFManagedEffectMode.Timed) || crashedOnThisIter {
						canClear = true;
						for activeEffectEnergyChange in managedEffectState[energy_i].activeEffectEnergyChanges {
							energyChangeTemp.change += -activeEffectEnergyChange;
						}
					}
					
					if canClear {
						ArrayClear(managedEffectState[energy_i].activeEffectEnergyChanges);
						managedEffectState[energy_i].toleranceEffectCount = 0;
					}

					energy_i += 1;
				}

				calculatedEnergyAtHour = ClampF(calculatedEnergyAtHour + energyChangeTemp.change, 0.0, energyMax);

				// Apply delayed Energy loss, if necessary. Don't damage Energy if Crashing while asleep.
				if crashedOnThisIter {
					if calculatedDelayedEnergyAtHour < 0.0 {
						DFLog(this, "Applying " + ToString(calculatedDelayedEnergyAtHour) + " delayed Energy.");
						calculatedEnergyAtHour = ClampF(calculatedEnergyAtHour + calculatedDelayedEnergyAtHour, 0.0, 100.0);
						calculatedDelayedEnergyAtHour = 0.0;
					}
				}

				//
				// Hydration and Nutrition (Post-Biocorruption Calculation)
				//
				calculatedNutritionAtHour = ClampF(calculatedNutritionAtHour + nutritionChangeTemp.change, 0.0, this.NutritionSystem.GetNeedMax());
				calculatedHydrationAtHour = ClampF(calculatedHydrationAtHour + hydrationChangeTemp.change, 0.0, this.HydrationSystem.GetNeedMax());

				// Apply delayed Hydration and Nutrition loss, if necessary.
				if crashedOnThisIter {
					DFLog(this, "Applying " + ToString(calculatedDelayedNutritionAtHour) + " delayed Nutrition.");
					calculatedNutritionAtHour += calculatedDelayedNutritionAtHour;
					if calculatedNutritionAtHour < 0.0 {
						calculatedNutritionAtHour = 0.0;
					}
					calculatedDelayedNutritionAtHour = 0.0;
				}

				if crashedOnThisIter {
					DFLog(this, "Applying " + ToString(calculatedDelayedHydrationAtHour) + " delayed Hydration.");
					calculatedHydrationAtHour += calculatedDelayedHydrationAtHour;
					if calculatedHydrationAtHour < 0.0 {
						calculatedHydrationAtHour = 0.0;
					}
					calculatedDelayedHydrationAtHour = 0.0;
				}

				//
				// Addiction Treatment
				//

				// Does the player have an Addiction Treatment duration?
				if addictionTreatmentDuration > 0.0 {
					addictionTreatmentDuration = ClampF(addictionTreatmentDuration - 300.0, 0.0, HoursToGameTimeSeconds(12));
				}

				//
				// Cyberpsychosis
				//

				// Does the player have a time until next Cyberpsychosis duration?
				if humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed > 0.0 {
					humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed = ClampF(humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed - 300.0, 0.0, HoursToGameTimeSeconds(24));
				}

				//
				// Humanity Loss
				//

				// Does the player have an Endotrisine duration?
				if humanityLossDataAccumulator.newEndotrisineDuration > 0.0 {
					humanityLossDataAccumulator.newEndotrisineDuration = ClampF(humanityLossDataAccumulator.newEndotrisineDuration - 300.0, 0.0, HoursToGameTimeSeconds(24));
				}

				// Basic Needs (final calculation)
				calculatedHydrationMaxAtHour = this.HydrationSystem.GetCalculatedBasicNeedMaxInProvidedState(Cast<Int32>(biocorruptionDataAccumulator.newCrashStackCount), 0, calculatedEuphoriaAtHour > 0.0);
				calculatedHydrationAtHour = ClampF(calculatedHydrationAtHour, 0.0, calculatedHydrationMaxAtHour);

				calculatedNutritionMaxAtHour = this.NutritionSystem.GetCalculatedBasicNeedMaxInProvidedState(Cast<Int32>(biocorruptionDataAccumulator.newCrashStackCount), 0, calculatedEuphoriaAtHour > 0.0);
				calculatedNutritionAtHour = ClampF(calculatedNutritionAtHour, 0.0, calculatedNutritionMaxAtHour);

				//
				// Nerve (final calculation)
				//
				calculatedNerveMaxAtHour = this.NerveSystem.GetCalculatedNerveMaxInProvidedState(addictionTreatmentDuration, alcoholDataAccumulator.withdrawalLevel, nicotineDataAccumulator.withdrawalLevel, narcoticDataAccumulator.withdrawalLevel, calculatedEuphoriaAtHour > 0.0);
				calculatedNerveAtHour = ClampF(calculatedNerveAtHour, 0.0, calculatedNerveMaxAtHour);

				j += 1;
			};

			// Store the target values for each need at this specific hour.
			basicNeedsData.energy.value = calculatedEnergyAtHour;
			basicNeedsData.energy.delayedValue = calculatedDelayedEnergyAtHour;
			basicNeedsData.energy.showLock = showEnergyLock;
			basicNeedsData.energy.ceiling = calculatedEnergyMaxAtHour;
			basicNeedsData.nutrition.value = calculatedNutritionAtHour;
			basicNeedsData.nutrition.delayedValue = calculatedDelayedNutritionAtHour;
			basicNeedsData.nutrition.ceiling = calculatedNutritionMaxAtHour;
			basicNeedsData.hydration.value = calculatedHydrationAtHour;
			basicNeedsData.hydration.delayedValue = calculatedDelayedHydrationAtHour;
			basicNeedsData.hydration.ceiling = calculatedHydrationMaxAtHour;
			basicNeedsData.nerve.value = calculatedNerveAtHour;
			basicNeedsData.nerve.overcharge = calculatedEuphoriaAtHour;
			basicNeedsData.nerve.ceiling = calculatedNerveMaxAtHour;
			basicNeedsData.nerve.showLock = showNerveLock;

			ArrayPush(calculatedBasicNeedsData, basicNeedsData);

			// Store the target values for each addiction at this specific hour.
			addictionData.alcohol.addictionAmount = alcoholDataAccumulator.addictionAmount;
			addictionData.alcohol.addictionStage = alcoholDataAccumulator.addictionStage;
			addictionData.alcohol.withdrawalLevel = alcoholDataAccumulator.withdrawalLevel;
			addictionData.alcohol.remainingBackoffDuration = alcoholDataAccumulator.backoffDuration;
			addictionData.alcohol.remainingWithdrawalDuration = alcoholDataAccumulator.withdrawalDuration;
			addictionData.alcohol.isWithdrawalLevelWorsened = alcoholDataAccumulator.isWithdrawalLevelWorsened;

			addictionData.nicotine.addictionAmount = nicotineDataAccumulator.addictionAmount;
			addictionData.nicotine.addictionStage = nicotineDataAccumulator.addictionStage;
			addictionData.nicotine.withdrawalLevel = nicotineDataAccumulator.withdrawalLevel;
			addictionData.nicotine.remainingBackoffDuration = nicotineDataAccumulator.backoffDuration;
			addictionData.nicotine.remainingWithdrawalDuration = nicotineDataAccumulator.withdrawalDuration;
			addictionData.nicotine.isWithdrawalLevelWorsened = nicotineDataAccumulator.isWithdrawalLevelWorsened;

			addictionData.narcotic.addictionAmount = narcoticDataAccumulator.addictionAmount;
			addictionData.narcotic.addictionStage = narcoticDataAccumulator.addictionStage;
			addictionData.narcotic.withdrawalLevel = narcoticDataAccumulator.withdrawalLevel;
			addictionData.narcotic.remainingBackoffDuration = narcoticDataAccumulator.backoffDuration;
			addictionData.narcotic.remainingWithdrawalDuration = narcoticDataAccumulator.withdrawalDuration;
			addictionData.narcotic.isWithdrawalLevelWorsened = narcoticDataAccumulator.isWithdrawalLevelWorsened;

			addictionData.newAddictionTreatmentDuration = addictionTreatmentDuration;

			ArrayPush(calculatedAddictionData, addictionData);

			humanityLossData.newTimeUntilNextCyberpsychosisAllowed = humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed;
			humanityLossData.newEndotrisineDuration = humanityLossDataAccumulator.newEndotrisineDuration;

			ArrayPush(calculatedHumanityLossData, humanityLossData);

			biocorruptionData.newCrashDuration = biocorruptionDataAccumulator.newCrashDuration;
			biocorruptionData.newCrashStackCount = biocorruptionDataAccumulator.newCrashStackCount;
			biocorruptionData.highestCrashStackCount = biocorruptionDataAccumulator.highestCrashStackCount; // Consumed by Energy System
			biocorruptionData.newTimeUntilRestless = biocorruptionDataAccumulator.newTimeUntilRestless;
			biocorruptionData.isRestless = biocorruptionDataAccumulator.isRestless;
			biocorruptionData.crashOccuredDuringTimeskip = biocorruptionDataAccumulator.crashOccuredDuringTimeskip;

			ArrayPush(calculatedBiocorruptionData, biocorruptionData);

			DFLog(this, "--------------------------------------------------------");
			DFLog(this, "calculatedEnergyAtHour = " + ToString(calculatedEnergyAtHour));
			DFLog(this, "calculatedDelayedEnergyAtHour = " + ToString(calculatedDelayedEnergyAtHour));
			DFLog(this, "showEnergyLock = " + ToString(showEnergyLock));
			DFLog(this, "calculatedNutritionAtHour = " + ToString(calculatedNutritionAtHour));
			DFLog(this, "calculatedDelayedNutritionAtHour = " + ToString(calculatedDelayedNutritionAtHour));
			DFLog(this, "calculatedHydrationAtHour = " + ToString(calculatedHydrationAtHour));
			DFLog(this, "calculatedDelayedHydrationAtHour = " + ToString(calculatedDelayedHydrationAtHour));
			DFLog(this, "biocorruptionData.newCrashDuration = " + ToString(biocorruptionData.newCrashDuration));
			DFLog(this, "biocorruptionData.newCrashStackCount = " + ToString(biocorruptionData.newCrashStackCount));
			DFLog(this, "biocorruptionData.newTimeUntilRestless = " + ToString(biocorruptionData.newTimeUntilRestless));
			DFLog(this, "biocorruptionData.crashOccuredDuringTimeskip = " + ToString(biocorruptionData.crashOccuredDuringTimeskip));

			i += 1;
		};

		let calculatedData: DFFutureHoursData = DFFutureHoursData(calculatedBasicNeedsData, calculatedAddictionData, calculatedHumanityLossData, calculatedBiocorruptionData);

		return calculatedData;
	}

    //
    //  Logic
    //
	public final func OnChoiceHub(value: Variant) {
		//DFProfile();
		if DFRunGuard(this) { return; }

		let hubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(value);
		
		for hub in hubs.choiceHubs {
			DFLog(this, "Hub Title: " + GetLocalizedText(hub.title));
			if Equals(GetLocalizedText(hub.title), GetLocalizedTextByKey(n"Story-base-quest-minor_quests-mq006-scenes-mq006_02_finale-mq006_02_ch_rc_get_in_displayNameOverride")) {
				// Pacifica Rollercoaster
				this.mq006_lastRollercoasterPosition = this.player.GetWorldPosition();
			} else if Equals(GetLocalizedText(hub.title), GetLocalizedTextByKey(n"Story-base-quest-side_quests-sq030-scenes-sq030_11_morning-sq030_11_ch_drink_displayNameOverride")) {
				// "Rebel! Rebel!" / "Pyramid Song" - Coffee with Kerry in Captain Caliente, coffee with Judy on the pier
				this.lastCoffeePosition = this.player.GetWorldPosition();
			}
		}
	}

    public final func OnLastAttemptedChoice(value: Variant) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }

		let choiceData: InteractionAttemptedChoice = FromVariant<InteractionAttemptedChoice>(value);
		let choiceCaption: String = choiceData.choice.caption;
		let choiceCaptionParts: array<ref<InteractionChoiceCaptionPart>> = choiceData.choice.captionParts.parts;
		let choiceIconName: CName = n"";
		let injectedInteractionIconName: CName = n"";
		for part in choiceCaptionParts {
			let icon: wref<ChoiceCaptionIconPart_Record> = (part as InteractionChoiceCaptionIconPart).iconRecord;
			if IsDefined(icon) {
				let injectedInteractionIcon: Bool;
				for name in this.injectedInteractionIconEnumNames {
					if Equals(name, icon.EnumName()) {
						injectedInteractionIcon = true;
						break;
					}
				}
				
				if injectedInteractionIcon {
					injectedInteractionIconName = icon.EnumName();
				} else {
					choiceIconName = icon.EnumName();
				}
			}
		}

		// Store the last attempted choice so that the Scene Tier Change event has an opportunity to check them.
		// Register for callback to clear these values shortly after.
		this.lastAttemptedChoiceCaption = choiceCaption;
		this.lastAttemptedChoiceIconName = choiceIconName;
		this.lastAttemptedInjectedInteractionIconName = injectedInteractionIconName;
		this.RegisterClearLastAttemptedChoiceForFXCheckCallback();

		this.HandleIsHumanityLossRestoreChoice(choiceCaptionParts, choiceCaption, choiceIconName);
		
		// If this originated from Relax Action Mode, stop here.
		if this.RelaxActionSystem.GetInRelaxActionMode() { return; }

		if this.IsSleepChoice(choiceCaption, choiceIconName) {
			this.SleepChoiceSelected();
		
		} else if this.IsDrinkTeaInCorpoPlazaChoice(choiceCaption) {
			this.DrankTeaFromChoice();
		
		} else if this.IsDrinkTeaWithMrHandsChoice(choiceCaption) {
			this.DrankTeaFromChoice();

		} else if this.IsDrinkCoffeeInDialogChoice(choiceCaption) {
			this.DrankCoffeeFromChoice();

		} else if StrContains(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Smoke)) || StrContains(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_TakeDrag)) {
			this.SmokedFromChoice();

		} else if this.IsNerveRegenInteractionChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.SetNerveRegenTarget(100.0);
			
		} else if this.IsNerveRestorationChoice(choiceCaption, choiceIconName) {
			let queuedChange: DFQueuedNeedValueChange;
			queuedChange.value = 100.0;
			queuedChange.forceMomentaryUIDisplay = true;
			queuedChange.isSoftCapRestrictedChange = true;
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(queuedChange);

		} else if this.IsSmallNerveRestorationChoice(choiceCaption, choiceIconName) {
			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now instead of a queued change
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;
			changeNeedValueProps.suppressRecoveryNotification = true;
			changeNeedValueProps.isSoftCapRestrictedChange = true;

			this.NerveSystem.ChangeNeedValue(20.0, changeNeedValueProps);

		} else if this.IsNutritionRestorationChoice(choiceCaption, choiceIconName) {
			this.PlayerStateService.HandleManagedConsumable(TweakDBInterface.GetItemRecord(t"Items.GoodQualityFood9"), true); // Gojilla
		
		} else if this.IsDumDumBlackLaceChoice(choiceCaption, choiceIconName) {
			// Specifically apply as many Narcotic stacks as the player can currently handle.
			let itemRecord: ref<Item_Record> = TweakDBInterface.GetItemRecord(t"Items.BlackLaceV0");
			let overridePipeline: DFManagedEffectPipelineResult = this.PlayerStateService.ManagedConsumablePipeline(itemRecord, true);
			this.PlayerStateService.HandleManagedConsumable(itemRecord, true, true, overridePipeline);
		}
	}

    public final func DrankCoffeeFromChoice() -> Void {
		//DFProfile();
		DFLog(this, "DrankCoffeeFromChoice");
		if this.GameStateService.IsValidGameState(this, true) {
			// Remove the base game Energized effect. It's no longer used in Dark Future due to being
			// functionally identical to Hydrated.
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"HousingStatusEffect.Energized") {
				StatusEffectHelper.RemoveStatusEffect(this.player, t"HousingStatusEffect.Energized");
			}
			
			// Since the player can repeatedly activate the coffee machine to obtain max Hydration,
			// just grant all of it on the first use.
			let queuedChange: DFQueuedNeedValueChange;
			queuedChange.value = 100.0;
			queuedChange.forceMomentaryUIDisplay = true;
			queuedChange.isSoftCapRestrictedChange = true;
            this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(queuedChange);

			// Treat the Energy restoration from the coffee machine like consuming normal coffee items.
			this.PlayerStateService.HandleManagedConsumable(TweakDBInterface.GetItemRecord(t"Items.LowQualityDrink1"), true);
		}
	}

	public final func SmokedFromChoice() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			DFLog(this, "============= Smoking prompt debounce window START");
			this.isWithinSmokePromptDebounceWindow = true;
			this.RegisterSmokePromptDebounceCallback();

			this.PlayerStateService.HandleManagedConsumable(TweakDBInterface.GetItemRecord(t"DarkFutureItem.CigarettePackC"), true);

			/*
			// Remove any pre-existing item effects.
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureSmoking");
			}
			
			// TODO - Needed still? Should just bail on the fallback FX when in a higher scene tier
			// Smoking status effect variant to suppress additional unneeded FX
			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");
			*/
		}
	}

	private final func SleepChoiceSelected() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			// Used to suppress VFX, notifications, and animations until the player gets up.
			this.GameStateService.SetInSleepCinematic(true);
		}
	}

    private final func DrankTeaFromChoice() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			let queuedChange: DFQueuedNeedValueChange;
			queuedChange.value = 100.0;
			queuedChange.forceMomentaryUIDisplay = true;
			queuedChange.isSoftCapRestrictedChange = true;
			queuedChange.effectToApplyAfterValueChange = t"DarkFutureStatusEffect.Sated";
			this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(queuedChange);
		}
	}

    public final func ShouldAllowFX() -> Bool {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			// Check if the last choice prompt we selected was part of an allowed workspot (sleeping, showering, etc)
			// If so, don't suppress VFX and SFX.
			if NotEquals(this.lastAttemptedChoiceCaption, "") {
				if this.IsSleepChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;

				} else if this.IsNerveRegenInteractionChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;

				} else if this.IsNerveRestorationChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;

				} else if this.IsSmallNerveRestorationChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;

				} else if this.IsHydrationRestorationChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;

				} else if this.IsNutritionRestorationChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
					return true;
				}

				return false;
			} else {
				return this.GameStateService.IsValidGameState(this);
			}
		} else {
			return false;
		}
	}

    public final func OnClearLastAttemptedChoiceForFXCheck() -> Void {
		//DFProfile();
		this.lastAttemptedChoiceCaption = "";
		this.lastAttemptedChoiceIconName = n"";
	}

	public final func GetLastAttemptedChoiceCaption() -> String {
		//DFProfile();
		return this.lastAttemptedChoiceCaption;
	}

	//
	//	FX
	//
	public final func QueueVomitFromInteractionChoice() -> Void {
		//DFProfile();
		this.QuestsSystem.SetFact(n"df_fact_crash_override_notification", 1);
		this.AnimationService.TryToQueueCrashAnimation(DFCrashAnimMode.ForceVomit);
	}

	//
	// Misc
	//
	public final func OnQuestObjectiveUpdate(hash: Uint32) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }

		let sleptDuringQuest: Bool = false;
		let romanceDuringQuest: Bool = false;
		let restoreHumanityLossDuringQuestMinor: Bool = false;
		let restoreHumanityLossDuringQuestMajor: Bool = false;
		let restoreHumanityLossDuringQuestPivotal: Bool = false;
		let increaseHumanityLossDuringQuestMinor: Bool = false;
		let increaseHumanityLossDuringQuestMajor: Bool = false;
		let increaseHumanityLossDuringQuestPivotal: Bool = false;

		let gameInstance: GameInstance = GetGameInstance();
		let journalManager: ref<JournalManager> = GameInstance.GetJournalManager(gameInstance);

		let entry: wref<JournalEntry> = journalManager.GetEntry(hash);
		if IsDefined(entry) {
			let questPhase: wref<JournalQuestPhase> = journalManager.GetParentEntry(entry) as JournalQuestPhase;
			if IsDefined(questPhase) {
				let quest: wref<JournalQuest> = journalManager.GetParentEntry(questPhase) as JournalQuest;
				if IsDefined(quest) {
					let state: gameJournalEntryState = journalManager.GetEntryState(entry);
					// Check against Quest Objectives we care about.
					let journalEntryUpdate: DFJournalEntryUpdate;
					journalEntryUpdate.questID = quest.GetId();
					journalEntryUpdate.phaseID = questPhase.GetId();
					journalEntryUpdate.entryID = entry.GetId();
					journalEntryUpdate.state = state;

					DFLog(this, "questID: " + journalEntryUpdate.questID + ", phaseID: " + journalEntryUpdate.phaseID + ", entryID: " + journalEntryUpdate.entryID + ", state: " + ToString(journalEntryUpdate.state));

					if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_JackieDeath_q005) {
						increaseHumanityLossDuringQuestPivotal = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Cross_sq023) {
						if this.QuestsSystem.GetFact(n"sq023_telem_bd_not_nailing") == 1 {
							increaseHumanityLossDuringQuestMinor = true;
						} else if this.QuestsSystem.GetFact(n"sq023_telem_bd_yes_nailing") == 1 {
							increaseHumanityLossDuringQuestMajor = true;
						}

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq026) {
						// Judy: Talkin' Bout A Revolution - Waking up after crashing on Judy's couch
						sleptDuringQuest = true;
						restoreHumanityLossDuringQuestMinor = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Suicide_sq026) {
						// Both Sides, Now - Evelyn's suicide
						increaseHumanityLossDuringQuestMajor = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq027) {
						// Panam: With A Little Help From My Friends - Waking up after sleeping under stars
						sleptDuringQuest = true;
						restoreHumanityLossDuringQuestMinor = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq030) {
						// Judy: Pyramid Song - Waking up after sleeping in the cottage
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q302) {
						// Phantom Liberty: Lucretia My Reflection - Waking up after sleeping on the mattress in the safehouse
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq029) {
						// River: Following the River - Waking up after spending the night at River's
						// River is always a friend after this quest, so we don't have to watch for a specific quest outcome.
						sleptDuringQuest = true;
						restoreHumanityLossDuringQuestMajor = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq021) {
						// River: The Hunt - Waking up after sleeping at Joss' place
						sleptDuringQuest = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q103a) {
						// Panam: Ghost Town - Slept in upstairs room of Sunset Motel
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q103b) {
						// Panam: Ghost Town - Slept in downstairs room of Sunset Motel
						sleptDuringQuest = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq004) {
						// Panam: Riders On The Storm - Slept in the abandoned farmhouse on the couch with Panam
						sleptDuringQuest = true;
						restoreHumanityLossDuringQuestMinor = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Romance_q003) {
						// Stout: Venus in Furs - Spent the evening with Meredith Stout
						romanceDuringQuest = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_LizziesBDs) {
						// Lizzie's Braindances - Finished a BD of any type
						romanceDuringQuest = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Ripperdoc_q001) {
						// The Ripperdoc - Took Victor's Immunosuppressant
						StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Immunosuppressant");
						GameInstance.GetTransactionSystem(GetGameInstance()).GiveItemByTDBID(this.player, t"DarkFutureItem.ImmunosuppressantDrug", 2);
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Funeral_sq018) {
						// Participate in Jackie's Funeral
						restoreHumanityLossDuringQuestPivotal = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_XBD_STSWatNID04) {
						// Gig: Dirty Biz
						increaseHumanityLossDuringQuestMajor = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_BD_sq021) {
						// The Hunt (Finish BD)
						increaseHumanityLossDuringQuestMinor = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Biocorruption_sq031) {
						// A Cool Metal Fire (complete)
						this.BiocorruptionConditionSystem.ApplyCrash(10u, true);
						this.AlcoholAddictionSystem.TryToAdvanceAddiction(this.AlcoholAddictionSystem.GetAddictionAmountOnUse(), 12, DFManagedEffectType.Alcohol, true);
						this.NicotineAddictionSystem.TryToAdvanceAddiction(this.NicotineAddictionSystem.GetAddictionAmountOnUse(), 3, DFManagedEffectType.Nicotine, true);
						this.NarcoticAddictionSystem.TryToAdvanceAddiction(this.NarcoticAddictionSystem.GetAddictionAmountOnUse(), 6, DFManagedEffectType.Narcotic, true);
					}
				}
			}
		}

		if sleptDuringQuest {
			this.SimulateSleepFromQuest();

		} else if romanceDuringQuest {
			// TODO - Does this still make sense?
			this.PlayerStateService.ClearAllManagedEffects();
			
			let queuedChange: DFQueuedNeedValueChange;
			queuedChange.value = 100.0;
			queuedChange.forceMomentaryUIDisplay = true;
			queuedChange.isSoftCapRestrictedChange = true;
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(queuedChange);
		}

		if restoreHumanityLossDuringQuestMinor {
			this.HumanityLossConditionSystem.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMinor);
		} else if restoreHumanityLossDuringQuestMajor {
			this.HumanityLossConditionSystem.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
		} else if restoreHumanityLossDuringQuestPivotal {
			this.HumanityLossConditionSystem.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventPivotal);
		} else if increaseHumanityLossDuringQuestMinor {
			this.HumanityLossConditionSystem.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventMinor);
		} else if increaseHumanityLossDuringQuestMajor {
			this.HumanityLossConditionSystem.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventMajor);
		} else if increaseHumanityLossDuringQuestPivotal {
			this.HumanityLossConditionSystem.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventPivotal);
		}
	}

	private final func JournalEntryUpdateEquals(journalUpdateA: DFJournalEntryUpdate, journalUpdateB: DFJournalEntryUpdate) -> Bool {
		//DFProfile();
		if Equals(journalUpdateA.questID, journalUpdateB.questID) && 
		   Equals(journalUpdateA.phaseID, journalUpdateB.phaseID) && 
		   Equals(journalUpdateA.entryID, journalUpdateB.entryID) && 
		   Equals(journalUpdateA.state, journalUpdateB.state) {
			return true;
		}
		return false;
	}

	public final func SimulateSleepFromQuest() -> Void {
		//DFProfile();
		// TODO: Does this still make sense?
		this.PlayerStateService.ClearAllManagedEffects();
		// TODO: this.EnergySystem.ClearCrashStacksByHours();

		let queuedEnergyChange: DFQueuedNeedValueChange;
		queuedEnergyChange.value = 100.0;
		queuedEnergyChange.isSoftCapRestrictedChange = true;

		let queuedNerveChange: DFQueuedNeedValueChange;
		queuedNerveChange.value = 100.0;
		queuedNerveChange.forceMomentaryUIDisplay = true;
		queuedNerveChange.isSoftCapRestrictedChange = true;
		
		this.EnergySystem.QueueContextuallyDelayedNeedValueChange(queuedEnergyChange);
		this.NerveSystem.QueueContextuallyDelayedNeedValueChange(queuedNerveChange);
	}

	public final func CheckHotscene() -> Void {
	/*  Reproducible crash with code below - Needs debugging
	
		let appliedEffects: array<ref<StatusEffect>>;

		GameInstance.GetStatusEffectSystem(GetGameInstance()).GetAppliedEffectsWithID(this.player.GetEntityID(), t"GameplayRestriction.NoMovement", appliedEffects);
		for effect in appliedEffects {
			let foundEffect: Bool = false;
			let sources: array<gameSourceData> = effect.sourcesData;
			let i: Int32 = 0;
			while i < ArraySize(sources) {
				let cond_A: Bool = Equals(sources[i].name, n"hey_gle_prostittute_male");
				let cond_B: Bool = Equals(sources[i].name, n"hey_gle_prostittute_female");
				let cond_C: Bool = Equals(sources[i].name, n"wbr_sm_jpn_prostitute_female");
				let cond_D: Bool = Equals(sources[i].name, n"wbr_sm_jpn_prostitute_male");

				if cond_A || cond_B || cond_C || cond_D {
					this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true, true);
					foundEffect = true;
					break;
				}

				i += 1;
			}

			if foundEffect {
				break;
			}
		}
	*/
	}

	//
	// Smoke Choice Debounce Callback
	//
	public final func OnSmokePromptDebounceCallback() -> Void {
		this.isWithinSmokePromptDebounceWindow = false;
		DFLog(this, "============= Smoking prompt debounce window END");
	}

	public final func IsWithinSmokePromptDebounceWindow() -> Bool {
		return this.isWithinSmokePromptDebounceWindow;
	}

    //
    //  Registration
    //
    private final func RegisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback.Create(), this.clearLastAttemptedChoiceForFXCheckDelayID, this.clearLastAttemptedChoiceForFXCheckDelayInterval);
	}

	private final func RegisterSmokePromptDebounceCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DFInteractionSystemSmokeChoiceDebounceCallback.Create(), this.smokePromptDebounceDelayID, this.smokePromptDebounceDelayInterval);
	}

	//
	//	Deregistration
	//

	private final func UnregisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.clearLastAttemptedChoiceForFXCheckDelayID);
	}

	private final func UnregisterSmokePromptDebounceCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.smokePromptDebounceDelayID);
	}

	//
	//  Immersive Timeskip Detection
	//

	@if(ModuleExists("ImmersiveTimeskip.Hotkey"))
	private final func IsImmersiveTimeskipActive() -> Bool {
		//DFProfile();
		return this.player.itsTimeskipActive;
	}

	@if(!ModuleExists("ImmersiveTimeskip.Hotkey"))
	private final func IsImmersiveTimeskipActive() -> Bool {
		//DFProfile();
		return false;
	}
}

@wrapMethod(DialogHubLogicController)
private final func UpdateDialogHubData() -> Void {
	let i: Int32 = 0;
	while i < ArraySize(this.m_data.choices) {
		let currentItem: ref<DialogChoiceLogicController> = this.m_itemControllers[i];
		currentItem.m_choiceTitle = this.m_data.title;
		currentItem.m_fullChoiceText = this.m_data.choices[i].localizedName;
		i += 1;
	}
	wrappedMethod();
}

@addField(DialogChoiceLogicController)
public let m_choiceTitle: String;

@addField(DialogChoiceLogicController)
public let m_fullChoiceText: String;

@addField(DialogChoiceLogicController)
public let m_humanityLossHolder: ref<inkFlex>;

@wrapMethod(DialogChoiceLogicController)
private final func HideAllCaptionParts() -> Void {
	wrappedMethod();
	if IsDefined(this.m_humanityLossHolder) {
		let parent: ref<inkHorizontalPanel> = this.m_TextFlex.GetParentWidget() as inkHorizontalPanel;
		parent.RemoveChild(this.m_humanityLossHolder);
		this.m_humanityLossHolder = null;
	}
}

@wrapMethod(DialogChoiceLogicController)
public final func SetCaptionParts(const argList: script_ref<[ref<InteractionChoiceCaptionPart>]>) -> Void {
	wrappedMethod(argList);

	let gameInstance: GameInstance = GetGameInstance();
	let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.GetInstance(gameInstance);
	let InteractionSystem: ref<DFInteractionSystem> = DFInteractionSystem.GetInstance(gameInstance);

	let currType: gamedataChoiceCaptionPartType;
	let i: Int32 = 0;
	while i < ArraySize(Deref(argList)) {
		let shouldAddHumanityLossRestoreIconWidget: Bool = false;
		currType = Deref(argList)[i].GetType();

		if Equals(currType, gamedataChoiceCaptionPartType.Icon) {
			let icon: wref<ChoiceCaptionIconPart_Record> = (Deref(argList)[i] as InteractionChoiceCaptionIconPart).iconRecord;
			
			let journalManager: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
			let romanceLeaveObjectiveBeforeSleep: ref<JournalQuestObjectiveBase> = journalManager.GetEntryByString("quests/minor_quest/mq055_romance_apartment/06_date/leave_end", "gameJournalQuestObjective") as JournalQuestObjectiveBase;
			let apartmentRomanceActive: Bool = Equals(journalManager.GetEntryState(romanceLeaveObjectiveBeforeSleep), gameJournalEntryState.Active) && journalManager.GetIsObjectiveOptional(romanceLeaveObjectiveBeforeSleep);

			// Meditation
			if Equals(icon.EnumName(), n"Sit") {
				if Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_Meditate)) {
					if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Meditation) {
						shouldAddHumanityLossRestoreIconWidget = true;
					}
				
				} else if Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MistyTarotFirst)) || Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MistyTarotRepeat)) {
					if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.TarotReading) {
						shouldAddHumanityLossRestoreIconWidget = true;
					}
				}
			} else if Equals(icon.EnumName(), n"GetIn") {
				// Rollercoaster
				if (Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_EnterRollercoaster))) &&
					Vector4.DistanceSquared(InteractionSystem.mq006_lastRollercoasterPosition, InteractionSystem.player.GetWorldPosition()) < 10.0 {
					if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Rollercoaster) {
						shouldAddHumanityLossRestoreIconWidget = true;
					}
				}
			
			} else if Equals(icon.EnumName(), n"GetUp") {
				// Meditation (Monks)
				if (Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MQ014MonkFinishPromptA)) ||
						Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MQ014MonkFinishPromptB)) ||
						Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MQ014MonkFinishPromptC)) || 
						Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_MQ014MonkFinishPromptD))) {
							shouldAddHumanityLossRestoreIconWidget = true;
				}

			// Dancing
			} else if Equals(icon.EnumName(), n"Dance") {
				if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Dance) {
					shouldAddHumanityLossRestoreIconWidget = true;
				}

			// Sleep with Romantic Partner
			} else if Equals(icon.EnumName(), n"Wait") && apartmentRomanceActive {
				if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Intimacy) {
					shouldAddHumanityLossRestoreIconWidget = true;
				}
			}

		} else if Equals(currType, gamedataChoiceCaptionPartType.Blueline) {
			let bluelinePart: ref<InteractionChoiceCaptionBluelinePart> = Deref(argList)[i] as InteractionChoiceCaptionBluelinePart;
			if IsDefined(bluelinePart) {
				for blp in bluelinePart.blueline.parts {
					let asPayment: ref<PaymentBluelinePart> = blp as PaymentBluelinePart;
					if IsDefined(asPayment) {
						// Homeless, Metro Beggar
						if Equals(GetLocalizedText(this.m_choiceTitle), GetLocalizedTextByKey(n"Story-base-quest-main_quests-prologue-q000-scenes-q000_kid_01a_bar_activities-q000_kid_ch_interact_with_hobo_displayNameOverride")) || GameInstance.GetQuestsSystem(GetGameInstance()).GetFact(n"ue_metro_track_selected") > 0 {
							if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Charity) {
								shouldAddHumanityLossRestoreIconWidget = true;
							}
						}
					}
				}
			}
		}

		if shouldAddHumanityLossRestoreIconWidget {
			this.PrependHumanityLossRestoreIconWidget(this.m_CaptionControllers[i], this.m_SecondaryCaptionControllers[i]);
		}

		i += 1;
	}
}

public final class DFHumanityLossRestoreChoiceCaptionPart extends InteractionChoiceCaptionPart {}

@addMethod(DialogChoiceLogicController)
private final func PrependHumanityLossRestoreIconWidget(currController: ref<CaptionImageIconsLogicController>, currentSecondaryController: ref<CaptionImageIconsLogicController>) -> Void {
	let parent: ref<inkHorizontalPanel> = this.m_TextFlex.GetParentWidget() as inkHorizontalPanel;
	let hubVert: ref<inkVerticalPanel> = parent.GetParentWidget().GetParentWidget().GetParentWidget().GetParentWidget() as inkVerticalPanel;

	let humanityLossHolder: ref<inkFlex> = new inkFlex();
	humanityLossHolder.SetName(n"humanityLossHolder");
	humanityLossHolder.SetVisible(true);
	humanityLossHolder.SetSize(100.0, 100.0);
	humanityLossHolder.SetFitToContent(false);
	humanityLossHolder.SetAffectsLayoutWhenHidden(false);

	let bg: ref<inkRectangle> = new inkRectangle();
	bg.SetName(n"bg");
	bg.SetVisible(true);
	bg.SetHAlign(inkEHorizontalAlign.Left);
	bg.SetTintColor(this.m_SelectedBg.GetTintColor());
	bg.SetOpacity(this.m_SelectedBg.GetOpacity());
	// Work-around: If a member of multiple choices or a choice part is visible, adjust the margin to avoid a 1px offset.
	if hubVert.GetNumChildren() > 2 || inkWidgetRef.IsVisible(currController.m_LifeHolder) || inkWidgetRef.IsVisible(currentSecondaryController.m_CheckHolder) || inkWidgetRef.IsVisible(currController.m_PayHolder) {
		bg.SetMargin(0.0, 0.0, 0.0, 0.0);
	} else {
		bg.SetMargin(0.0, 1.0, 0.0, 0.0);
	}
	bg.SetSize(100.0, 100.0);
	bg.Reparent(humanityLossHolder);

	let icon: ref<inkImage> = new inkImage();
	icon.SetName(n"icon");
	icon.SetVisible(true);
	// Work-around: If a choice part is visible, adjust the width margin.
	if inkWidgetRef.IsVisible(currController.m_LifeHolder) || inkWidgetRef.IsVisible(currentSecondaryController.m_CheckHolder) || inkWidgetRef.IsVisible(currController.m_PayHolder) {
		icon.SetMargin(30.0, 0.0, 0.0, 0.0);
	} else {
		icon.SetMargin(30.0, 0.0, 10.0, 0.0);
	}
	icon.SetSize(64.0, 64.0);
	icon.SetFitToContent(false);
	icon.SetAffectsLayoutWhenHidden(true);
	icon.SetAtlasResource(r"darkfuture\\condition_images\\condition_assets.inkatlas");
	icon.SetTexturePart(n"ico_condition_humanityloss");
	icon.SetTintColor(HDRColor(0.0, 0.0, 0.0, 1.0));
	icon.Reparent(humanityLossHolder);

	parent.AddChildWidget(humanityLossHolder);
	parent.ReorderChild(humanityLossHolder, 0);

	this.m_humanityLossHolder = humanityLossHolder;
}

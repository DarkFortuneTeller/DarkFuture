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
	DFFutureHoursData,
	DFNeedChangeDatum,
	DFTimeSkipData,
	DFTimeSkipType,
	DFTempEnergyItemType
}
import DarkFuture.Services.{
	DFGameStateService,
	DFPlayerStateService,
	DFNotificationService,
	DFNotification,
	DFAudioCue,
	DFVisualEffect,
	DFNotificationCallback
}
import DarkFuture.Needs.{
	DFHydrationSystem,
	DFNutritionSystem,
	DFEnergySystem,
	DFNerveSystem,
	DFNeedChangeUIFlags,
	DFChangeNeedValueProps
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
import DarkFuture.Conditions.{
	DFHumanityLossConditionSystem,
	DFHumanityLossRestorationActivityType,
	DFHumanityLossRestorationType,
	DFHumanityLossCostType
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
	public let addictionStage: Int32;
	public let primaryEffectDuration: Float;
	public let backoffDuration: Float;
	public let withdrawalLevel: Int32;
	public let withdrawalDuration: Float;
	public let stackCount: Uint32;
	public let isWithdrawalLevelWorsened: Bool;
}

public struct DFHumanityLossTimeSkipIterationStateDatum {
	public let level: Uint32;
	public let newTimeUntilNextCyberpsychosisAllowed: Float;
	public let newEndotrisineDuration: Float;
}

public struct DFJournalEntryUpdate {
	public let questID: String;
	public let phaseID: String;
	public let entryID: String;
	public let state: gameJournalEntryState;
}

public class VomitFromInteractionChoiceStage2Callback extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<VomitFromInteractionChoiceStage2Callback> = new VomitFromInteractionChoiceStage2Callback();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.InteractionSystem.vomitFromInteractionChoiceStage2DelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.InteractionSystem.OnVomitFromInteractionChoiceStage2();
	}
}

public class DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback> = new DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.InteractionSystem.clearLastAttemptedChoiceForFXCheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.InteractionSystem.OnClearLastAttemptedChoiceForFXCheck();
	}
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
	//DFProfile();
	let interactionSystem: ref<DFInteractionSystem> = DFInteractionSystem.Get();
	let effectID: TweakDBID = evt.staticData.GetID();
	let effectTags: array<CName> = evt.staticData.GameplayTags();

	if IsSystemEnabledAndRunning(interactionSystem) {		
		if Equals(effectID, t"HousingStatusEffect.Energized") {
			if DFNerveSystem.Get().GetHasNausea() {
				if StatusEffectSystem.ObjectHasStatusEffect(this, t"HousingStatusEffect.Energized") {
					StatusEffectHelper.RemoveStatusEffect(this, t"HousingStatusEffect.Energized");
				}
				interactionSystem.QueueVomitFromInteractionChoice();
			} else {
				interactionSystem.DrankCoffeeFromChoice();
			}
		}
	}

	if ArrayContains(effectTags, n"DarkFutureSmokingFromItem") {
		interactionSystem.HandleSmokingFromItem();
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
    private let HydrationSystem: ref<DFHydrationSystem>;
	private let NutritionSystem: ref<DFNutritionSystem>;
	private let EnergySystem: ref<DFEnergySystem>;
	private let NerveSystem: ref<DFNerveSystem>;
	private let VehicleSleepSystem: ref<DFVehicleSleepSystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
	private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
	private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;

	private let QuestsSystem: ref<QuestsSystem>;
    private let BlackboardSystem: ref<BlackboardSystem>;
    private let UIInteractionsBlackboard: ref<IBlackboard>;

    private let choiceListener: ref<CallbackHandle>;
	private let choiceHubListener: ref<CallbackHandle>;

    private let lastAttemptedChoiceCaption: String;
	private let lastAttemptedChoiceIconName: CName;

    public let clearLastAttemptedChoiceForFXCheckDelayID: DelayID;
    private let clearLastAttemptedChoiceForFXCheckDelayInterval: Float = 10.0;

    // Location Memory from Prompts
	public let mq006_lastRollercoasterPosition: Vector4;
	private let lastCoffeePosition: Vector4;

	// Sleeping and Waiting
	private let skippingTimeFromHubMenu: Bool = false;
	private let lastEnergyBeforeSleeping: Float = 0.0;

	private let sleepingReduceMetabolismMult: Float = 0.4;

	public let vomitFromInteractionChoiceStage2DelayID: DelayID;
	private let vomitFromInteractionChoiceStage2DelayInterval: Float = 1.5;

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
	}

	private final func RegisterAllRequiredDelayCallbacks() -> Void {}
	public final func OnTimeSkipStart() -> Void {}
	public final func OnTimeSkipCancelled() -> Void {}
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
		let gameInstance = GetGameInstance();
		
		this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
		this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
		this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
		this.VehicleSleepSystem = DFVehicleSleepSystem.GetInstance(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
		this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
		this.HumanityLossConditionSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
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
		this.UnregisterVomitFromInteractionChoiceStage2Callback();
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
		addictionBackoffDurations: array<Float>, 
		withdrawalDurations: array<Float>,
		addictionAmountLossPerDay: Float,
		addictionAmount: Float,
		addictionStage: Int32, 
		primaryEffectDuration: Float, 
		backoffDuration: Float, 
		withdrawalLevel: Int32, 
		withdrawalDuration: Float,
		stackCount: Uint32,
		opt useStackCount: Bool,
		opt basePrimaryEffectDuration: Float
	) -> DFAddictionTimeSkipIterationStateDatum {
		//DFProfile();
		// Decrease the player's addiction amount.
		let minutesPerUpdate: Float = 300.0 / 60.0;
		let updatesPerDay: Float = (60.0 / minutesPerUpdate) * 24.0;
		
		let addictionAmountLossPerUpdate = addictionAmountLossPerDay / updatesPerDay;
		addictionAmount -= addictionAmountLossPerUpdate;

		// Is the player currently addicted?
		if addictionStage > 0 {
			// Does the player have a backoff duration, taking into account pre-existing durations?
			if backoffDuration > 0.0 {
				backoffDuration -= 300.0;
				if backoffDuration <= 0.0 {
					backoffDuration = 0.0;
					withdrawalLevel = 1;
					if withdrawalLevel < addictionStage {
						withdrawalDuration = HoursToGameTimeSeconds(1);
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
							withdrawalDuration = HoursToGameTimeSeconds(1);
						} else {
							withdrawalDuration = withdrawalDurations[withdrawalLevel];
						}
					}
				}

			} else if primaryEffectDuration > 0.0 && (!useStackCount || stackCount > 0u) {
				primaryEffectDuration -= 300.0;
				if primaryEffectDuration <= 0.0 {
					primaryEffectDuration = 0.0;

					let theBackoffDuration: Float = (addictionBackoffDurations[addictionStage] * this.Settings.timescale) * 60.0;
					if useStackCount {
						// A stack of the primary effect expired. Decrease the stack count. If the stack count is now 0, start a fake back-off timer.
						// Otherwise, reset the primary effect duration.
						stackCount -= 1u;
						if Equals(stackCount, 0u) {
							backoffDuration = theBackoffDuration;
						} else {
							primaryEffectDuration = basePrimaryEffectDuration;
						}
					} else {
						// The primary effect expired, and we don't use stacks on this primary effect; start a fake back-off timer.
						backoffDuration = theBackoffDuration;
					}
				}
			}
		}

		DFLog(this, "=====================================================================================");

		DFLog(this, "Predictive " + logName + " AddictionAmount; " + ToString(addictionAmount));
		DFLog(this, "Predictive " + logName + " AddictionStage: " + ToString(addictionStage));
		DFLog(this, "Predictive " + logName + " PrimaryEffectDuration: " + ToString(primaryEffectDuration));
		DFLog(this, "Predictive " + logName + " BackoffDuration: " + ToString(backoffDuration));
		DFLog(this, "Predictive " + logName + " WithdrawalDuration: " + ToString(withdrawalDuration));
		DFLog(this, "Predictive " + logName + " WithdrawalLevel: " + ToString(withdrawalLevel));
		DFLog(this, "Predictive " + logName + " StackCount: " + ToString(stackCount));

		DFLog(this, "=====================================================================================");

		let addictionTimeSkipIterationStateData: DFAddictionTimeSkipIterationStateDatum;
		addictionTimeSkipIterationStateData.addictionAmount = addictionAmount;
		addictionTimeSkipIterationStateData.addictionStage = addictionStage;
		addictionTimeSkipIterationStateData.primaryEffectDuration = primaryEffectDuration;
		addictionTimeSkipIterationStateData.backoffDuration = backoffDuration;
		addictionTimeSkipIterationStateData.withdrawalLevel = withdrawalLevel;
		addictionTimeSkipIterationStateData.withdrawalDuration = withdrawalDuration;
		addictionTimeSkipIterationStateData.stackCount = stackCount;

		return addictionTimeSkipIterationStateData;
	}

	public final func GetCalculatedValuesForFutureHours(timeSkipType: DFTimeSkipType) -> DFFutureHoursData {
		//DFProfile();
		let isSleeping: Bool = DFIsSleeping(timeSkipType);

		// Need Variables
		let calculatedBasicNeedsData: array<DFNeedsDatum>;
		let calculatedHydrationAtHour: Float = this.HydrationSystem.GetNeedValue();
		let calculatedNutritionAtHour: Float = this.NutritionSystem.GetNeedValue();
		let calculatedEnergyAtHour: Float = this.EnergySystem.GetNeedValue();
		let calculatedNerveAtHour: Float = this.NerveSystem.GetNeedValue();
		let calculatedNerveMaxAtHour: Float = this.NerveSystem.GetNeedMax();

		// Energy Variables
		let energyRestoredFromEnergized: Float = this.EnergySystem.GetTotalEnergyRestoredFromEnergized();

		// Addiction Variables
		let calculatedAddictionData: array<DFAddictionDatum>;

		// Alcohol Variables
		let alcoholDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		alcoholDataAccumulator.addictionAmount = this.AlcoholAddictionSystem.GetAddictionAmount();
		alcoholDataAccumulator.withdrawalLevel = this.AlcoholAddictionSystem.GetWithdrawalLevel();
		alcoholDataAccumulator.addictionStage = this.AlcoholAddictionSystem.GetAddictionStage();
		alcoholDataAccumulator.backoffDuration = this.AlcoholAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		alcoholDataAccumulator.withdrawalDuration = this.AlcoholAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		alcoholDataAccumulator.primaryEffectDuration = 0.0;
		alcoholDataAccumulator.stackCount = 0u;
		// Does the player have a Alcohol Primary Effect?
		let alcoholEffects: array<ref<StatusEffect>>;
		StatusEffectHelper.GetAppliedEffectsWithTag(this.player, this.AlcoholAddictionSystem.GetAddictionPrimaryStatusEffectTag(), alcoholEffects);
		if ArraySize(alcoholEffects) > 0 {
			alcoholDataAccumulator.primaryEffectDuration = alcoholEffects[0].GetRemainingDuration();
			alcoholDataAccumulator.stackCount = alcoholEffects[0].GetStackCount();
		}

		// Nicotine Variables
		let nicotineDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		nicotineDataAccumulator.addictionAmount = this.NicotineAddictionSystem.GetAddictionAmount();
		nicotineDataAccumulator.withdrawalLevel = this.NicotineAddictionSystem.GetWithdrawalLevel();
		nicotineDataAccumulator.addictionStage = this.NicotineAddictionSystem.GetAddictionStage();
		nicotineDataAccumulator.backoffDuration = this.NicotineAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		nicotineDataAccumulator.withdrawalDuration = this.NicotineAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		nicotineDataAccumulator.primaryEffectDuration = 0.0;
		// Does the player have a Nicotine Primary Effect?
		let nicotineEffects: array<ref<StatusEffect>>;
		StatusEffectHelper.GetAppliedEffectsWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNicotine", nicotineEffects);
		if ArraySize(nicotineEffects) > 0 {
			nicotineDataAccumulator.primaryEffectDuration = nicotineEffects[0].GetRemainingDuration();
		}

		// Narcotic Variables
		let narcoticDataAccumulator: DFAddictionTimeSkipIterationStateDatum;
		narcoticDataAccumulator.addictionAmount = this.NarcoticAddictionSystem.GetAddictionAmount();
		narcoticDataAccumulator.withdrawalLevel = this.NarcoticAddictionSystem.GetWithdrawalLevel();
		narcoticDataAccumulator.addictionStage = this.NarcoticAddictionSystem.GetAddictionStage();
		narcoticDataAccumulator.backoffDuration = this.NarcoticAddictionSystem.GetRemainingBackoffDurationInGameTimeSeconds();
		narcoticDataAccumulator.withdrawalDuration = this.NarcoticAddictionSystem.GetRemainingWithdrawalDurationInGameTimeSeconds();
		narcoticDataAccumulator.primaryEffectDuration = 0.0;
		// Does the player have a Narcotic Primary Effect?
		let narcoticEffects: array<ref<StatusEffect>>;
		StatusEffectHelper.GetAppliedEffectsWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNarcotic", narcoticEffects);
		if ArraySize(narcoticEffects) > 0 {
			narcoticDataAccumulator.primaryEffectDuration = narcoticEffects[0].GetRemainingDuration();
		}

		// Store the original withdrawal level values.
		let originalAlcoholWithdrawalLevel: Int32 = alcoholDataAccumulator.withdrawalLevel;
		let originalNicotineWithdrawalLevel: Int32 = nicotineDataAccumulator.withdrawalLevel;
		let originalNarcoticWithdrawalLevel: Int32 = narcoticDataAccumulator.withdrawalLevel;

		// Addiction Treatment Variables
		let addictionTreatmentDuration = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();

		// Humanity Loss Variables
		let calculatedHumanityLossData: array<DFHumanityLossDatum>;

		let humanityLossDataAccumulator: DFHumanityLossTimeSkipIterationStateDatum;
		humanityLossDataAccumulator.level = this.HumanityLossConditionSystem.GetConditionLevel();
		humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed = this.HumanityLossConditionSystem.GetTimeUntilNextCyberpsychosisAllowed();
		humanityLossDataAccumulator.newEndotrisineDuration = this.HumanityLossConditionSystem.GetRemainingEndotrisineDurationInGameTimeSeconds();

		let i = 0;
		while i < 24 { // Iterate over each hour
			let needHydration = DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needNutrition = DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needEnergy = DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needNerve = DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);

			let basicNeedsData: DFNeedsDatum;
			basicNeedsData.hydration = needHydration;
			basicNeedsData.nutrition = needNutrition;
			basicNeedsData.energy = needEnergy;
			basicNeedsData.nerve = needNerve;
			
			let addictionAlcohol: DFAddictionUpdateDatum;
			addictionAlcohol.addictionAmount = alcoholDataAccumulator.addictionAmount;
			addictionAlcohol.addictionStage = alcoholDataAccumulator.addictionStage;
			addictionAlcohol.withdrawalLevel = alcoholDataAccumulator.withdrawalLevel;
			addictionAlcohol.remainingBackoffDuration = alcoholDataAccumulator.backoffDuration;
			addictionAlcohol.remainingWithdrawalDuration = alcoholDataAccumulator.withdrawalDuration;

			let addictionNicotine: DFAddictionUpdateDatum;
			addictionNicotine.addictionAmount = nicotineDataAccumulator.addictionAmount;
			addictionNicotine.addictionStage = nicotineDataAccumulator.addictionStage;
			addictionNicotine.withdrawalLevel = nicotineDataAccumulator.withdrawalLevel;
			addictionNicotine.remainingBackoffDuration = nicotineDataAccumulator.backoffDuration;
			addictionNicotine.remainingWithdrawalDuration = nicotineDataAccumulator.withdrawalDuration;

			let addictionNarcotic: DFAddictionUpdateDatum;
			addictionNarcotic.addictionAmount = narcoticDataAccumulator.addictionAmount;
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

			// Accumulate all of the changes by iterating over each update cycle within the hour (60 / 12, or every 5 minutes)
			let j = 1;
			while j <= 12 {
				//
				// Nutrition and Hydration
				//
				let nutritionChangeTemp: Float = this.NutritionSystem.GetNutritionChange();
				let hydrationChangeTemp: Float = this.HydrationSystem.GetHydrationChange();

				if isSleeping {
					// Reduced metabolism - Reduce Nutrition and Hydration at reduced rate
					nutritionChangeTemp *= this.sleepingReduceMetabolismMult;
					hydrationChangeTemp *= this.sleepingReduceMetabolismMult;
				}

				calculatedNutritionAtHour = ClampF(calculatedNutritionAtHour + nutritionChangeTemp, 0.0, this.NutritionSystem.GetNeedMax());
				calculatedHydrationAtHour = ClampF(calculatedHydrationAtHour + hydrationChangeTemp, 0.0, this.HydrationSystem.GetNeedMax());
				
				//
				// Energy
				//
				let energyChangeTemp: Float = this.EnergySystem.GetEnergyChangeWithRecoverLimit(calculatedEnergyAtHour, timeSkipType);

				// Nuke any temporary Energy effects the player might have.
				energyChangeTemp -= energyRestoredFromEnergized;
				energyRestoredFromEnergized = 0.0;

				let energyMax: Float = this.EnergySystem.GetNeedMax();
				let calculatedEnergyAtHourBeforeNerveCalc = ClampF(calculatedEnergyAtHour + energyChangeTemp, 0.0, energyMax);
				
				//
				// Nerve
				//	
				// Allow Nerve to recover even if Energy is not.
				let nerveSoftCapAtIter: Float = this.HumanityLossConditionSystem.GetNerveSoftCapFromHumanityLossAtLevel(humanityLossDataAccumulator.level);
				let hydrationStageAtHour: Int32 = this.HydrationSystem.GetNeedStageAtValue(calculatedHydrationAtHour);
				let nutritionStageAtHour: Int32 = this.NutritionSystem.GetNeedStageAtValue(calculatedNutritionAtHour);
				let energyStageAtHour: Int32 = this.EnergySystem.GetNeedStageAtValue(calculatedEnergyAtHour);
				if Equals(timeSkipType, DFTimeSkipType.FullSleep) {
					if calculatedNerveAtHour <= nerveSoftCapAtIter && hydrationStageAtHour < 3 && nutritionStageAtHour < 3 {
						// When sleeping, Nerve also recovers if below the sleeping recovery max.
						if (energyChangeTemp > 0.0 || calculatedEnergyAtHourBeforeNerveCalc == energyMax) && 
							calculatedNerveAtHour < this.NerveSystem.nerveRecoverAmountSleepingMax {
							
							calculatedNerveAtHour += this.NerveSystem.nerveRecoverAmountSleeping;

							if calculatedNerveAtHour > this.NerveSystem.nerveRecoverAmountSleepingMax {
								calculatedNerveAtHour = this.NerveSystem.nerveRecoverAmountSleepingMax;
							}

							if calculatedNerveAtHour > nerveSoftCapAtIter {
								calculatedNerveAtHour = nerveSoftCapAtIter;
							}
						}
					} else {
						let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, hydrationStageAtHour, nutritionStageAtHour, energyStageAtHour);
						calculatedNerveAtHour += nerveChangeTemp;
					}

				} else {
					let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, hydrationStageAtHour, nutritionStageAtHour, energyStageAtHour);
					calculatedNerveAtHour += nerveChangeTemp;
				}

				//
				// Energy (Post-Nerve Calculation)
				//
				if  this.NerveSystem.GetNeedStageAtValue(calculatedNerveAtHour) < 3 {
					// Recover Energy, for real.
					calculatedEnergyAtHour = calculatedEnergyAtHourBeforeNerveCalc;
				} else {
					// Don't recover Energy if the player's Nerve is at or below Distressed.
					calculatedEnergyAtHour = ClampF(calculatedEnergyAtHour + this.EnergySystem.GetEnergyChange(), 0.0, energyMax);
				}

				let nicotineDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Nicotine", 
					this.NicotineAddictionSystem.GetAddictionBackoffDurationsInRealTimeMinutesByStage(),
					this.NicotineAddictionSystem.GetAddictionWithdrawalDurationsInGameTimeSeconds(),
					this.NicotineAddictionSystem.GetAddictionAmountLossPerDay(),
					nicotineDataAccumulator.addictionAmount,
					nicotineDataAccumulator.addictionStage, 
					nicotineDataAccumulator.primaryEffectDuration, 
					nicotineDataAccumulator.backoffDuration,
					nicotineDataAccumulator.withdrawalLevel, 
					nicotineDataAccumulator.withdrawalDuration,
					0u
				);

				let alcoholDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Alcohol", 
					this.AlcoholAddictionSystem.GetAddictionBackoffDurationsInRealTimeMinutesByStage(),
					this.AlcoholAddictionSystem.GetAddictionWithdrawalDurationsInGameTimeSeconds(),
					this.AlcoholAddictionSystem.GetAddictionAmountLossPerDay(),
					alcoholDataAccumulator.addictionAmount,
					alcoholDataAccumulator.addictionStage, 
					alcoholDataAccumulator.primaryEffectDuration, 
					alcoholDataAccumulator.backoffDuration,
					alcoholDataAccumulator.withdrawalLevel, 
					alcoholDataAccumulator.withdrawalDuration,
					alcoholDataAccumulator.stackCount,
					true,
					this.AlcoholAddictionSystem.GetDefaultEffectDuration()
				);

				let narcoticDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Narcotic", 
					this.NarcoticAddictionSystem.GetAddictionBackoffDurationsInRealTimeMinutesByStage(),
					this.NarcoticAddictionSystem.GetAddictionWithdrawalDurationsInGameTimeSeconds(),
					this.NarcoticAddictionSystem.GetAddictionAmountLossPerDay(),
					narcoticDataAccumulator.addictionAmount,
					narcoticDataAccumulator.addictionStage, 
					narcoticDataAccumulator.primaryEffectDuration, 
					narcoticDataAccumulator.backoffDuration,
					narcoticDataAccumulator.withdrawalLevel, 
					narcoticDataAccumulator.withdrawalDuration,
					0u
				);

				// Update the accumulators.
				alcoholDataAccumulator.primaryEffectDuration = alcoholDataForIter.primaryEffectDuration;
				alcoholDataAccumulator.addictionAmount = alcoholDataForIter.addictionAmount;
				alcoholDataAccumulator.addictionStage = alcoholDataForIter.addictionStage;
				alcoholDataAccumulator.withdrawalLevel = alcoholDataForIter.withdrawalLevel;
				alcoholDataAccumulator.backoffDuration = alcoholDataForIter.backoffDuration;
				alcoholDataAccumulator.withdrawalDuration = alcoholDataForIter.withdrawalDuration;
				alcoholDataAccumulator.stackCount = alcoholDataForIter.stackCount;
				alcoholDataAccumulator.isWithdrawalLevelWorsened = alcoholDataForIter.withdrawalLevel > originalAlcoholWithdrawalLevel && alcoholDataForIter.withdrawalLevel != 5;

				nicotineDataAccumulator.primaryEffectDuration = nicotineDataForIter.primaryEffectDuration;
				nicotineDataAccumulator.addictionAmount = nicotineDataForIter.addictionAmount;
				nicotineDataAccumulator.addictionStage = nicotineDataForIter.addictionStage;
				nicotineDataAccumulator.withdrawalLevel = nicotineDataForIter.withdrawalLevel;
				nicotineDataAccumulator.backoffDuration = nicotineDataForIter.backoffDuration;
				nicotineDataAccumulator.withdrawalDuration = nicotineDataForIter.withdrawalDuration;
				nicotineDataAccumulator.isWithdrawalLevelWorsened = nicotineDataForIter.withdrawalLevel > originalNicotineWithdrawalLevel && nicotineDataForIter.withdrawalLevel != 5;

				narcoticDataAccumulator.primaryEffectDuration = narcoticDataForIter.primaryEffectDuration;
				narcoticDataAccumulator.addictionAmount = narcoticDataForIter.addictionAmount;
				narcoticDataAccumulator.addictionStage = narcoticDataForIter.addictionStage;
				narcoticDataAccumulator.withdrawalLevel = narcoticDataForIter.withdrawalLevel;
				narcoticDataAccumulator.backoffDuration = narcoticDataForIter.backoffDuration;
				narcoticDataAccumulator.withdrawalDuration = narcoticDataForIter.withdrawalDuration;
				narcoticDataAccumulator.isWithdrawalLevelWorsened = narcoticDataForIter.withdrawalLevel > originalNarcoticWithdrawalLevel && narcoticDataForIter.withdrawalLevel != 5;

				// Does the player have an Addiction Treatment duration?
				if addictionTreatmentDuration > 0.0 {
					addictionTreatmentDuration = ClampF(addictionTreatmentDuration - 300.0, 0.0, HoursToGameTimeSeconds(12));
				}

				// Does the player have a time until next Cyberpsychosis duration?
				if humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed > 0.0 {
					humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed = ClampF(humanityLossDataAccumulator.newTimeUntilNextCyberpsychosisAllowed - 300.0, 0.0, HoursToGameTimeSeconds(24));
				}

				// Does the player have an Endotrisine duration?
				if humanityLossDataAccumulator.newEndotrisineDuration > 0.0 {
					humanityLossDataAccumulator.newEndotrisineDuration = ClampF(humanityLossDataAccumulator.newEndotrisineDuration - 300.0, 0.0, HoursToGameTimeSeconds(24));
				}

				calculatedNerveMaxAtHour = this.NerveSystem.GetCalculatedNeedMaxInProvidedState(addictionTreatmentDuration, alcoholDataAccumulator.withdrawalLevel, nicotineDataAccumulator.withdrawalLevel, narcoticDataAccumulator.withdrawalLevel);
				calculatedNerveAtHour = ClampF(calculatedNerveAtHour, 0.0, calculatedNerveMaxAtHour);

				j += 1;
			};

			// Store the target values for each need at this specific hour.
			basicNeedsData.energy.value = calculatedEnergyAtHour;
			basicNeedsData.nutrition.value = calculatedNutritionAtHour;
			basicNeedsData.hydration.value = calculatedHydrationAtHour;
			basicNeedsData.nerve.value = calculatedNerveAtHour;
			basicNeedsData.nerve.ceiling = calculatedNerveMaxAtHour;

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

			i += 1;
		};

		let calculatedData: DFFutureHoursData = DFFutureHoursData(calculatedBasicNeedsData, calculatedAddictionData, calculatedHumanityLossData);

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
		for part in choiceCaptionParts {
			let icon: wref<ChoiceCaptionIconPart_Record> = (part as InteractionChoiceCaptionIconPart).iconRecord;
			if IsDefined(icon) {
				choiceIconName = icon.EnumName();
			}
		}

		// Store the last attempted choice so that the Scene Tier Change event has an opportunity to check them.
		// Register for callback to clear these values shortly after.
		this.lastAttemptedChoiceCaption = choiceCaption;
		this.lastAttemptedChoiceIconName = choiceIconName;
		this.RegisterClearLastAttemptedChoiceForFXCheckCallback();

		if this.IsSleepChoice(choiceCaption, choiceIconName) {
			this.SleepChoiceSelected();
		
		} else if this.IsDrinkTeaInCorpoPlazaChoice(choiceCaption) {
			if !this.NerveSystem.GetHasNausea() {
				this.DrankTeaFromChoice();
			} else {
				this.QueueVomitFromInteractionChoice();
			}
		
		} else if this.IsDrinkTeaWithMrHandsChoice(choiceCaption) {
			// Story moment - Ignore Nausea
			this.DrankTeaFromChoice();

		} else if this.IsDrinkCoffeeInDialogChoice(choiceCaption) {
			// Story moment - Ignore Nausea
			this.DrankCoffeeFromChoice();

		} else if StrContains(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Smoke)) || StrContains(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_TakeDrag)) {
			this.SmokedFromChoice();

		} else if this.IsNerveRegenInteractionChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.SetNerveRegenTarget(100.0);
			
		} else if this.IsNerveRestorationChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true, true);

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
			this.NutritionSystem.QueueContextuallyDelayedNeedValueChange(20.0, true, false, t"DarkFutureStatusEffect.WellFed");
		}

		this.HandleIsHumanityLossRestoreChoice(choiceCaptionParts, choiceCaption, choiceIconName);
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
            this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);

			// Treat the Energy restoration from the coffee machine like consuming normal coffee items.
			// Grant all stacks possible from coffee at once.
            this.EnergySystem.TryToApplyEnergizedStacks(this.EnergySystem.energizedMaxStacksFromCaffeine, DFTempEnergyItemType.Caffeine, true, true);
		}
	}

	public final func SmokedFromChoice() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			// Remove any pre-existing item effects.
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureSmoking");
			}
			
			// Smoking status effect variant to suppress additional unneeded FX
			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");

			// Use Vargas Black Label as an example item when calculating the max override.
			let itemRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(t"DarkFutureItem.CigarettePackC");
			this.MainSystem.DispatchItemConsumedEvent(itemRecord, true, true);
		}
	}

	private final func SleepChoiceSelected() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			// Used to suppress VFX and notifications until the player gets up.
			this.GameStateService.SetInSleepCinematic(true);
		}
	}

    private final func DrankTeaFromChoice() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(100.0, true, false, t"DarkFutureStatusEffect.Sated");
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
	public final func HandleSmokingFromItem() {
		//DFProfile();
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice") {
			StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");
		}
	}

	public final func QueueVomitFromInteractionChoice() -> Void {
		//DFProfile();
		if this.Settings.nauseaInteractableEffectEnabled {
			// Vomit from Interaction Choice: Fade to black, mini-map shake, vomit VO

			let vomitNotification: DFNotification;
			vomitNotification.sfx = DFAudioCue(n"sq032_sc_04_v_pukes", 0);
			vomitNotification.vfx = DFVisualEffect(n"blink_slow", null);
			this.NotificationService.QueueNotification(vomitNotification);

			let shakeNotification: DFNotification;
			shakeNotification.vfx = DFVisualEffect(n"stagger_effect", null);
			this.NotificationService.QueueNotification(shakeNotification);

			this.RegisterVomitFromInteractionChoiceStage2();
		}
	}

	public final func OnVomitFromInteractionChoiceStage2() -> Void {
		//DFProfile();
		// Vomit from Interaction Choice: Splash SFX (ew!)

		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"w_melee_gore_blood_splat_small";
		this.player.QueueEvent(evt);
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

		let gameInstance = GetGameInstance();
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

					}
				}
			}
		}

		if sleptDuringQuest {
			this.SimulateSleepFromQuest();
		} else if romanceDuringQuest {
			this.EnergySystem.ClearEnergyManagementEffects();
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);
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
		this.EnergySystem.ClearEnergyManagementEffects();
		this.EnergySystem.QueueContextuallyDelayedNeedValueChange(100.0);
		this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);
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
    //  Registration
    //
    private final func RegisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback.Create(this), this.clearLastAttemptedChoiceForFXCheckDelayID, this.clearLastAttemptedChoiceForFXCheckDelayInterval);
	}

	private final func RegisterVomitFromInteractionChoiceStage2() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, VomitFromInteractionChoiceStage2Callback.Create(this), this.vomitFromInteractionChoiceStage2DelayID, this.vomitFromInteractionChoiceStage2DelayInterval);
	}

	//
	//	Unregistration
	//

	private final func UnregisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.clearLastAttemptedChoiceForFXCheckDelayID);
	}

	private final func UnregisterVomitFromInteractionChoiceStage2Callback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.vomitFromInteractionChoiceStage2DelayID);
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

	let gameInstance = GetGameInstance();
	let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.GetInstance(gameInstance);
	let InteractionSystem: ref<DFInteractionSystem> = DFInteractionSystem.GetInstance(gameInstance);

	let currType: gamedataChoiceCaptionPartType;
	let i: Int32 = 0;
	while i < ArraySize(Deref(argList)) {
		let shouldAddHumanityLossRestoreIconWidget: Bool = false;
		currType = Deref(argList)[i].GetType();

		if Equals(currType, gamedataChoiceCaptionPartType.Icon) {
			let icon = (Deref(argList)[i] as InteractionChoiceCaptionIconPart).iconRecord;
			
			let journalManager: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
			let romanceLeaveObjectiveBeforeSleep: ref<JournalQuestObjectiveBase> = journalManager.GetEntryByString("quests/minor_quest/mq055_romance_apartment/06_date/leave_end", "gameJournalQuestObjective") as JournalQuestObjectiveBase;
			let apartmentRomanceActive: Bool = Equals(journalManager.GetEntryState(romanceLeaveObjectiveBeforeSleep), gameJournalEntryState.Active) && journalManager.GetIsObjectiveOptional(romanceLeaveObjectiveBeforeSleep);

			// Meditation
			if Equals(icon.EnumName(), n"Sit") {
				if Equals(this.m_fullChoiceText, GetLocalizedTextByKey(InteractionSystem.locKey_Interaction_Meditate)) {
					if HumanityLossConditionSystem.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Meditation) {
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

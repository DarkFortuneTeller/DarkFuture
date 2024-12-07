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
import DarkFuture.Utils.IsSleeping
import DarkFuture.Utils.HoursToGameTimeSeconds
import DarkFuture.Main.{
	DFMainSystem,
	DFNeedsDatum,
	DFAddictionDatum,
	DFAddictionUpdateDatum,
	DFFutureHoursData,
	DFNeedChangeDatum,
	DFTimeSkipData,
	DFTimeSkipType
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
	DFNeedChangeUIFlags
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}

//	JournalNotificationQueue - Detect quest completion events.
//
@wrapMethod(JournalNotificationQueue)
private final func PushQuestNotification(questEntry: wref<JournalQuest>, state: gameJournalEntryState) -> Void {
	let journalManager: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());

	let primaryKeyQuestTitle = ToString(GetLocalizedText(questEntry.GetTitle(journalManager)));
	if Equals(state, gameJournalEntryState.Succeeded) {
		if Equals(primaryKeyQuestTitle, ToString(GetLocalizedTextByKey(n"LizziesBDs-Main_Mod-Name"))) {
			// Lizzie's Braindances - Completion of a braindance
			DFNerveSystem.Get().QueueContextuallyDelayedNeedValueChange(100.0, true);
		}
	}

	wrappedMethod(questEntry, state);
}

//	QuestTrackerGameController - Detect quest objective updates.
//
@wrapMethod(QuestTrackerGameController)
protected cb func OnStateChanges(hash: Uint32, className: CName, notifyOption: JournalNotifyOption, changeType: JournalChangeType) -> Bool {
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
}

public struct DFJournalEntryUpdate {
	public let questID: String;
	public let phaseID: String;
	public let entryID: String;
	public let state: gameJournalEntryState;
}

public class SmokingFromItemFXDelayCallbackStage1 extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		let self: ref<SmokingFromItemFXDelayCallbackStage1> = new SmokingFromItemFXDelayCallbackStage1();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InteractionSystem.smokingFXStage1DelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InteractionSystem.OnSmokingFromItemFXStage1();
	}
}

public class SmokingFromItemFXDelayCallbackStage2 extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		let self: ref<SmokingFromItemFXDelayCallbackStage2> = new SmokingFromItemFXDelayCallbackStage2();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InteractionSystem.smokingFXStage2DelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InteractionSystem.OnSmokingFromItemFXStage2();
	}
}

public class SmokingFromItemFXDelayCallbackStage3 extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		let self: ref<SmokingFromItemFXDelayCallbackStage3> = new SmokingFromItemFXDelayCallbackStage3();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InteractionSystem.smokingFXStage3DelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InteractionSystem.OnSmokingFromItemFXStage3();
	}
}

public class VomitFromInteractionChoiceStage2Callback extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		let self: ref<VomitFromInteractionChoiceStage2Callback> = new VomitFromInteractionChoiceStage2Callback();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InteractionSystem.vomitFromInteractionChoiceStage2DelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InteractionSystem.OnVomitFromInteractionChoiceStage2();
	}
}

public class DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback extends DFDelayCallback {
	public let InteractionSystem: wref<DFInteractionSystem>;

	public static func Create(interactionSystem: wref<DFInteractionSystem>) -> ref<DFDelayCallback> {
		let self: ref<DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback> = new DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback();
		self.InteractionSystem = interactionSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InteractionSystem.clearLastAttemptedChoiceForFXCheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InteractionSystem.OnClearLastAttemptedChoiceForFXCheck();
	}
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
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

    private let BlackboardSystem: ref<BlackboardSystem>;
    private let UIInteractionsBlackboard: ref<IBlackboard>;

    private let choiceListener: ref<CallbackHandle>;
	private let choiceHubListener: ref<CallbackHandle>;

    private let lastAttemptedChoiceCaption: String;
	private let lastAttemptedChoiceIconName: CName;

    private let clearLastAttemptedChoiceForFXCheckDelayID: DelayID;
    private let clearLastAttemptedChoiceForFXCheckDelayInterval: Float = 10.0;

    // Location Memory from Prompts
	private let mq006_lastRollercoasterPosition: Vector4;
	private let lastCoffeePosition: Vector4;

	// Sleeping and Waiting
	private let skippingTimeFromSleeping: Bool = false;
	private let lastEnergyBeforeSleeping: Float = 0.0;

	private let sleepingReduceMetabolismMult: Float = 0.4;
    
	// FX
	private let queuedSmokingFX: Bool = false;
	private let smokingFXStage1DelayID: DelayID;
	private let smokingFXStage2DelayID: DelayID;
	private let smokingFXStage3DelayID: DelayID;
	private let smokingFXStage1DelayInterval: Float = 0.01;
	private let smokingFXStage2DelayInterval: Float = 0.75;
	private let smokingFXStage3DelayInterval: Float = 2.5;

	private let vomitFromInteractionChoiceStage2DelayID: DelayID;
	private let vomitFromInteractionChoiceStage2DelayInterval: Float = 1.5;

	// Quest-related Sleep Journal Entry Updates
	private let journalEntryUpdate_Sleep_sq027: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq026: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq030: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q302: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq029: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_sq021: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q103a: DFJournalEntryUpdate;
	private let journalEntryUpdate_Sleep_q103b: DFJournalEntryUpdate;
	private let journalEntryUpdate_Romance_q003: DFJournalEntryUpdate;

	// See: darkfuture/localization_interactions/*/onscreens/darkfuture_interactions_donotmodify.json
	private const let locKey_Interaction_Sleep: CName = n"DarkFutureInteraction_mq000_01_apartment_Sleep";
	private const let locKey_Interaction_TakeShower: CName = n"DarkFutureInteraction_mq000_01_apartment_TakeShower";
	private const let locKey_Interaction_ExitRollercoaster: CName = n"DarkFutureInteraction_mq006_02_finale_ExitRollercoaster";
	private const let locKey_Interaction_MQ014MonkFinishPromptA: CName = n"DarkFutureInteraction_mq014_01_hook_MonkFinishPromptA";
	private const let locKey_Interaction_MQ014MonkFinishPromptB: CName = n"DarkFutureInteraction_mq014_03_second_MonkFinishPromptB";
	private const let locKey_Interaction_MQ014MonkFinishPromptC: CName = n"DarkFutureInteraction_mq014_05_third_MonkFinishPromptC";
	private const let locKey_Interaction_MQ014MonkFinishPromptD: CName = n"DarkFutureInteraction_mq014_07_fourth_MonkFinishPromptD";
	private const let locKey_Interaction_Cuddle: CName = n"DarkFutureInteraction_mq055_01_Cuddle";
	private const let locKey_Interaction_Kiss: CName = n"DarkFutureInteraction_mq055_01_Kiss";
	private const let locKey_Interaction_Dance: CName = n"DarkFutureInteraction_mq300_safehouse_Dance";
	private const let locKey_Interaction_EndMeditation: CName = n"DarkFutureInteraction_mq300_safehouse_EndMeditation";
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

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFInteractionSystem> {
		let instance: ref<DFInteractionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Gameplay.DFInteractionSystem") as DFInteractionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFInteractionSystem> {
		return DFInteractionSystem.GetInstance(GetGameInstance());
	}

	private final func DoPostSuspendActions() -> Void {
		this.lastAttemptedChoiceCaption = "";
		this.lastAttemptedChoiceIconName = n"";
		this.mq006_lastRollercoasterPosition = new Vector4(0.0, 0.0, 0.0, 0.0);
		this.lastCoffeePosition = new Vector4(0.0, 0.0, 0.0, 0.0);
		this.skippingTimeFromSleeping = false;
		this.lastEnergyBeforeSleeping = 0.0;
		this.queuedSmokingFX = false;
	}
	private final func DoPostResumeActions() -> Void {}
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}
	private final func DoStopActions() -> Void {}

	private final func SetupData() -> Void {
		this.journalEntryUpdate_Sleep_sq027 = new DFJournalEntryUpdate("sq027_01_basilisk_convoy", "03_ambush", "get_in_car", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq026 = new DFJournalEntryUpdate("sq026_03_pizza", "01_pizza_night", "breakfast", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq030 = new DFJournalEntryUpdate("sq030_judy_romance", "hut", "stuff1", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_q302 = new DFJournalEntryUpdate("q302_reed", "04_squot", "follow_myers7", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq029 = new DFJournalEntryUpdate("sq029_sobchak_romance", "breakfast", "talk_with_river", gameJournalEntryState.Active);
		this.journalEntryUpdate_Sleep_sq021 = new DFJournalEntryUpdate("sq021_sick_dreams", "bbq", "sleep", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_q103a = new DFJournalEntryUpdate("q103_warhead", "roadhouse", "bed_upstairs", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Sleep_q103b = new DFJournalEntryUpdate("q103_warhead", "roadhouse", "bed_downstairs", gameJournalEntryState.Succeeded);
		this.journalEntryUpdate_Romance_q003 = new DFJournalEntryUpdate("q003_stout", "stout", "02_enjoy_evening", gameJournalEntryState.Succeeded);
	}

	private final func RegisterAllRequiredDelayCallbacks() -> Void {}
	public final func OnTimeSkipStart() -> Void {}
	public final func OnTimeSkipCancelled() -> Void {}
	public final func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}
    public final func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	private func GetSystemToggleSettingValue() -> Bool {
        // This system does not have a system-specific toggle.
		return true;
    }

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
        return "INVALID";
    }

	private final func GetSystems() -> Void {
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
        this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
	}

	private final func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
		this.UIInteractionsBlackboard = this.BlackboardSystem.Get(GetAllBlackboardDefs().UIInteractions);
	}

	private final func UnregisterAllDelayCallbacks() -> Void {
		this.UnregisterClearLastAttemptedChoiceForFXCheckCallback();
		this.UnregisterAllSmokingFXCallbacks();
		this.UnregisterVomitFromInteractionChoiceStage2Callback();
	}

    private final func RegisterListeners() -> Void {
        this.RegisterChoiceListener();
        this.RegisterChoiceHubListener();
    }

    private final func UnregisterListeners() -> Void {
        this.UnregisterChoiceListener();
        this.UnregisterChoiceHubListener();
    }

    private final func RegisterChoiceListener() -> Void {
		this.choiceListener = this.UIInteractionsBlackboard.RegisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this, n"OnLastAttemptedChoice");
	}

    private final func RegisterChoiceHubListener() -> Void {
		this.choiceHubListener = this.UIInteractionsBlackboard.RegisterListenerVariant(GetAllBlackboardDefs().UIInteractions.DialogChoiceHubs, this, n"OnChoiceHub");
	}

    private final func UnregisterChoiceListener() -> Void {
		this.UIInteractionsBlackboard.UnregisterListenerVariant(GetAllBlackboardDefs().UIInteractions.LastAttemptedChoice, this.choiceListener);
	}

	private final func UnregisterChoiceHubListener() -> Void {
		this.UIInteractionsBlackboard.UnregisterListenerVariant(GetAllBlackboardDefs().UIInteractions.DialogChoiceHubs, this.choiceHubListener);
	}

    //
    //  Interaction Choices
    //
    private final func IsSleepChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Sleep)) && Equals(choiceIconName, n"Wait") {
			return true;
		}

		return false;
	}

	private final func IsNerveRegenInteractionChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		// Multiple Apartment / Location Interactions
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_TakeShower)) {
			return true;

		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Dance)) {
			return true;

		}

		return false;
	}

    private final func IsNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		// Romantic Activities
		if Equals(choiceIconName, n"Prostitute") {
			return true;

		// Rollercoaster
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_ExitRollercoaster)) && Vector4.DistanceSquared(this.mq006_lastRollercoasterPosition, this.player.GetWorldPosition()) < 10.0 {
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
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_EndMeditation)) {
			return true;

		// Phantom Liberty: Bootleg Shard (V's Apartment)
		} else if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Q303PlayBraindance)) {
			return true;
		}

		return false;
	}

    private final func IsSmallNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
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
		}

		return false;
	}

    private final func IsHydrationRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		return this.IsDrinkTeaInCorpoPlazaChoice(choiceCaption) || this.IsDrinkTeaWithMrHandsChoice(choiceCaption);
	}

    private final func IsDrinkTeaInCorpoPlazaChoice(choiceCaption: String) -> Bool {
		// Corpo Plaza Apartment Interaction
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_DLC6DrinkTea)) {
			return true;
		}

		return false;
	}

	private final func IsDrinkTeaWithMrHandsChoice(choiceCaption: String) -> Bool {
		// Phantom Liberty: Mr. Hands scene in Heavy Hearts Club
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Q303SitAndDrink)) {
			return true;
		}

		return false;
	}

    private final func IsDrinkCoffeeInDialogChoice(choiceCaption: String) -> Bool {
		if Equals(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_CoffeeDrink)) && Vector4.DistanceSquared(this.lastCoffeePosition, this.player.GetWorldPosition()) < 10.0 {
			return true;
		}

		return false;
	}

    private final func IsNutritionRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if StrContains(choiceCaption, GetLocalizedTextByKey(this.locKey_Interaction_Eat)) {
			return true;
		}

		return false;
	}

	//
	//	Sleeping and Waiting
	//
	public final func SetSkippingTimeFromSleeping(value: Bool) -> Void {
		this.skippingTimeFromSleeping = value;
	}

	public final func IsPlayerSleeping() -> Bool {
		if this.skippingTimeFromSleeping {
			DFLog(this.debugEnabled, this, "Player is sleeping.");
			return true;
		} else {
			DFLog(this.debugEnabled, this, "Player is skipping time.");
			return false;
		}
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

		DFLog(this.debugEnabled, this, "=====================================================================================");

		DFLog(this.debugEnabled, this, "Predictive " + logName + " AddictionAmount; " + ToString(addictionAmount));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " AddictionStage: " + ToString(addictionStage));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " PrimaryEffectDuration: " + ToString(primaryEffectDuration));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " BackoffDuration: " + ToString(backoffDuration));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " WithdrawalDuration: " + ToString(withdrawalDuration));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " WithdrawalLevel: " + ToString(withdrawalLevel));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " StackCount: " + ToString(stackCount));

		DFLog(this.debugEnabled, this, "=====================================================================================");

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
		
		let isSleeping: Bool = IsSleeping(timeSkipType);

		// Need Variables
		let calculatedBasicNeedsData: array<DFNeedsDatum>;
		let calculatedHydrationAtHour: Float = this.HydrationSystem.GetNeedValue();
		let calculatedNutritionAtHour: Float = this.NutritionSystem.GetNeedValue();
		let calculatedEnergyAtHour: Float = this.EnergySystem.GetNeedValue();
		let calculatedNerveAtHour: Float = this.NerveSystem.GetNeedValue();
		let calculatedNerveMaxAtHour: Float = this.NerveSystem.GetNeedMax();

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

		// Addiction Treatment Variables
		let addictionTreatmentDuration = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();

		let i = 0;
		while i < 24 { // Iterate over each hour
			let needHydration = new DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needNutrition = new DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needEnergy = new DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);
			let needNerve = new DFNeedChangeDatum(0.0, 0.0, 100.0, 0.0);

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
				let energyMax: Float = this.EnergySystem.GetNeedMax();
				calculatedEnergyAtHour = ClampF(calculatedEnergyAtHour + energyChangeTemp, 0.0, energyMax);
				
				//
				// Nerve
				//
				if Equals(timeSkipType, DFTimeSkipType.FullSleep) {
					// When sleeping, if getting full sleep, Nerve also recovers if below the sleeping recovery max.
					if (energyChangeTemp > 0.0 || calculatedEnergyAtHour == energyMax) && calculatedNerveAtHour < this.NerveSystem.nerveRecoverAmountSleepingMax {
						calculatedNerveAtHour += this.NerveSystem.nerveRecoverAmountSleeping;
						if calculatedNerveAtHour > this.NerveSystem.nerveRecoverAmountSleepingMax {
							calculatedNerveAtHour = this.NerveSystem.nerveRecoverAmountSleepingMax;
						}
					}

				} else {
					let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, this.HydrationSystem.GetNeedStageAtValue(calculatedHydrationAtHour), this.NutritionSystem.GetNeedStageAtValue(calculatedNutritionAtHour), this.EnergySystem.GetNeedStageAtValue(calculatedEnergyAtHour));
					calculatedNerveAtHour += nerveChangeTemp;
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

				nicotineDataAccumulator.primaryEffectDuration = nicotineDataForIter.primaryEffectDuration;
				nicotineDataAccumulator.addictionAmount = nicotineDataForIter.addictionAmount;
				nicotineDataAccumulator.addictionStage = nicotineDataForIter.addictionStage;
				nicotineDataAccumulator.withdrawalLevel = nicotineDataForIter.withdrawalLevel;
				nicotineDataAccumulator.backoffDuration = nicotineDataForIter.backoffDuration;
				nicotineDataAccumulator.withdrawalDuration = nicotineDataForIter.withdrawalDuration;

				narcoticDataAccumulator.primaryEffectDuration = narcoticDataForIter.primaryEffectDuration;
				narcoticDataAccumulator.addictionAmount = narcoticDataForIter.addictionAmount;
				narcoticDataAccumulator.addictionStage = narcoticDataForIter.addictionStage;
				narcoticDataAccumulator.withdrawalLevel = narcoticDataForIter.withdrawalLevel;
				narcoticDataAccumulator.backoffDuration = narcoticDataForIter.backoffDuration;
				narcoticDataAccumulator.withdrawalDuration = narcoticDataForIter.withdrawalDuration;

				// Does the player have an Addiction Treatment duration?
				if addictionTreatmentDuration > 0.0 {
					addictionTreatmentDuration = ClampF(addictionTreatmentDuration - 300.0, 0.0, HoursToGameTimeSeconds(12));
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

			addictionData.nicotine.addictionAmount = nicotineDataAccumulator.addictionAmount;
			addictionData.nicotine.addictionStage = nicotineDataAccumulator.addictionStage;
			addictionData.nicotine.withdrawalLevel = nicotineDataAccumulator.withdrawalLevel;
			addictionData.nicotine.remainingBackoffDuration = nicotineDataAccumulator.backoffDuration;
			addictionData.nicotine.remainingWithdrawalDuration = nicotineDataAccumulator.withdrawalDuration;

			addictionData.narcotic.addictionAmount = narcoticDataAccumulator.addictionAmount;
			addictionData.narcotic.addictionStage = narcoticDataAccumulator.addictionStage;
			addictionData.narcotic.withdrawalLevel = narcoticDataAccumulator.withdrawalLevel;
			addictionData.narcotic.remainingBackoffDuration = narcoticDataAccumulator.backoffDuration;
			addictionData.narcotic.remainingWithdrawalDuration = narcoticDataAccumulator.withdrawalDuration;

			addictionData.newAddictionTreatmentDuration = addictionTreatmentDuration;

			ArrayPush(calculatedAddictionData, addictionData);

			i += 1;
		};

		let calculatedData: DFFutureHoursData = new DFFutureHoursData(calculatedBasicNeedsData, calculatedAddictionData);

		return calculatedData;
	}

    //
    //  Logic
    //
	public final func OnChoiceHub(value: Variant) {
		let hubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(value);
		
		for hub in hubs.choiceHubs {
			DFLog(this.debugEnabled, this, "Hub Title: " + GetLocalizedText(hub.title));
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
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureSmoking");
			}
			
			// Smoking status effect variant to suppress additional unneeded FX
			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");

			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now instead of a queued change
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			this.NerveSystem.ChangeNeedValue(this.Settings.nerveCigarettes, uiFlags, true);

		} else if this.IsNerveRegenInteractionChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.SetNerveRegenTarget(100.0);
			
		} else if this.IsNerveRestorationChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);

		} else if this.IsSmallNerveRestorationChoice(choiceCaption, choiceIconName) {
			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now instead of a queued change
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			this.NerveSystem.ChangeNeedValue(20.0, uiFlags, true);

		} else if this.IsNutritionRestorationChoice(choiceCaption, choiceIconName) {
			this.NutritionSystem.QueueContextuallyDelayedNeedValueChange(20.0, true);

		}
	}

    public final func DrankCoffeeFromChoice() -> Void {
		DFLog(this.debugEnabled, this, "DrankCoffeeFromChoice");
		if this.GameStateService.IsValidGameState("DrankCoffeeFromChoice", true) {
			// Remove the Energized effect. It's no longer used in Dark Future due to being
			// functionally identical to Hydrated.
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"HousingStatusEffect.Energized") {
				StatusEffectHelper.RemoveStatusEffect(this.player, t"HousingStatusEffect.Energized");
			}
			
			// Since the player can repeatedly activate the coffee machine to obtain max Hydration,
			// just grant all of it on the first use. Also apply the Hydrated effect, like coffee items.
            this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(100.0, true, t"BaseStatusEffect.Sated");

			// Treat the Energy restoration from the coffee machine like consuming normal coffee items.
			let energyToRestore: Float = this.Settings.energyTier1;
            this.EnergySystem.ChangeEnergyFromItems(energyToRestore, energyToRestore, true);
		}
	}

	private final func SleepChoiceSelected() -> Void {
		if this.GameStateService.IsValidGameState("SleepChoiceSelected", true) {
			this.SetSkippingTimeFromSleeping(true);
			this.GameStateService.SetInSleepCinematic(true);
		}
	}

    private final func DrankTeaFromChoice() -> Void {
		if this.GameStateService.IsValidGameState("DrankTeaFromChoice", true) {
			this.HydrationSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);
		}
	}

    public final func ShouldAllowFX() -> Bool {
		if this.GameStateService.IsValidGameState("ShouldAllowFX", true, true) {
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
				return this.GameStateService.IsValidGameState("ShouldAllowFX", false, true);
			}
		} else {
			return false;
		}
	}

    public final func OnClearLastAttemptedChoiceForFXCheck() -> Void {
		this.lastAttemptedChoiceCaption = "";
		this.lastAttemptedChoiceIconName = n"";
	}

	public final func GetLastAttemptedChoiceCaption() -> String {
		return this.lastAttemptedChoiceCaption;
	}

	//
	//	FX
	//
	public final func HandleSmokingFromItem() {
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice") {
			StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");
		}

		if this.Settings.smokingEffectsEnabled {
			if !this.queuedSmokingFX {
				this.queuedSmokingFX = true;
				this.RegisterSmokingFXCallbackStage1();
			}
		}
	}

	public final func OnSmokingFromItemFXStage1() -> Void {
		// Smoking FX Stage 1: Lighter flick
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"g_sc_v_work_lighter";
		this.player.QueueEvent(evt);

		this.RegisterSmokingFXCallbackStage2();
	}

	public final func OnSmokingFromItemFXStage2() -> Void {
		// Smoking FX Stage 2: Drag
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"q001_sc_01_v_takes_a_drag";
		this.player.QueueEvent(evt);

		this.RegisterSmokingFXCallbackStage3();
	}

	public final func OnSmokingFromItemFXStage3() -> Void {
		// Smoking FX Stage 3: Blow smoke
		GameObjectEffectHelper.StartEffectEvent(this.player, n"cigarette_smoke_exhaust", false, null, true);
		this.queuedSmokingFX = false;
	}

	public final func QueueVomitFromInteractionChoice() -> Void {
		if this.Settings.nauseaInteractableEffectEnabled {
			// Vomit from Interaction Choice: Fade to black, mini-map shake, vomit VO

			let vomitNotification: DFNotification;
			vomitNotification.sfx = new DFAudioCue(n"sq032_sc_04_v_pukes", 0);
			vomitNotification.vfx = new DFVisualEffect(n"blink_slow", null);
			this.NotificationService.QueueNotification(vomitNotification);

			let shakeNotification: DFNotification;
			shakeNotification.vfx = new DFVisualEffect(n"stagger_effect", null);
			this.NotificationService.QueueNotification(shakeNotification);

			this.RegisterVomitFromInteractionChoiceStage2();
		}
	}

	public final func OnVomitFromInteractionChoiceStage2() -> Void {
		// Vomit from Interaction Choice: Splash SFX (ew!)

		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"w_melee_gore_blood_splat_small";
		this.player.QueueEvent(evt);
	}

	public final func OnQuestObjectiveUpdate(hash: Uint32) -> Void {
		let sleptDuringQuest: Bool = false;
		let romanceDuringQuest: Bool = false;

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

					DFLog(this.debugEnabled, this, "questID: " + journalEntryUpdate.questID + ", phaseID: " + journalEntryUpdate.phaseID + ", entryID: " + journalEntryUpdate.entryID + ", state: " + ToString(journalEntryUpdate.state));

					if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq027) {
						// Panam: With A Little Help From My Friends - Waking up after sleeping under stars
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq026) {
						// Judy: Talkin' Bout A Revolution - Waking up after crashing on Judy's couch
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq030) {
						// Judy: Pyramid Song - Waking up after sleeping in the cottage
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q302) {
						// Phantom Liberty: Lucretia My Reflection - Waking up after sleeping on the mattress in the safehouse
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq029) {
						// River: Following the River - Waking up after spending the night at River's
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_sq021) {
						// River: The Hunt - Waking up after sleeping at Joss' place
						sleptDuringQuest = true;
					
					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q103a) {
						// Panam: Ghost Town - Slept in upstairs room of Sunset Motel
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Sleep_q103b) {
						// Panam: Ghost Town - Slept in downstairs room of Sunset Motel
						sleptDuringQuest = true;

					} else if this.JournalEntryUpdateEquals(journalEntryUpdate, this.journalEntryUpdate_Romance_q003) {
						// Stout: Venus in Furs - Spent the evening with Meredith Stout
						romanceDuringQuest = true;
					}
				}
			}
		}

		if sleptDuringQuest {
			this.SimulateSleepFromQuest();
		} else if romanceDuringQuest {
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);
		}
	}

	private final func JournalEntryUpdateEquals(journalUpdateA: DFJournalEntryUpdate, journalUpdateB: DFJournalEntryUpdate) -> Bool {
		if Equals(journalUpdateA.questID, journalUpdateB.questID) && 
		   Equals(journalUpdateA.phaseID, journalUpdateB.phaseID) && 
		   Equals(journalUpdateA.entryID, journalUpdateB.entryID) && 
		   Equals(journalUpdateA.state, journalUpdateB.state) {
			return true;
		}
		return false;
	}

	public final func SimulateSleepFromQuest() -> Void {
		this.EnergySystem.PerformQuestSleep();
		this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);
	}

    //
    //  Registration
    //
    private final func RegisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, DFInteractionSystemClearLastAttemptedChoiceForFXCheckCallback.Create(this), this.clearLastAttemptedChoiceForFXCheckDelayID, this.clearLastAttemptedChoiceForFXCheckDelayInterval);
	}

	private final func RegisterSmokingFXCallbackStage1() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SmokingFromItemFXDelayCallbackStage1.Create(this), this.smokingFXStage1DelayID, this.smokingFXStage1DelayInterval);
	}

	private final func RegisterSmokingFXCallbackStage2() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SmokingFromItemFXDelayCallbackStage2.Create(this), this.smokingFXStage2DelayID, this.smokingFXStage2DelayInterval);
	}

	private final func RegisterSmokingFXCallbackStage3() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SmokingFromItemFXDelayCallbackStage3.Create(this), this.smokingFXStage3DelayID, this.smokingFXStage3DelayInterval);
	}

	private final func RegisterVomitFromInteractionChoiceStage2() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, VomitFromInteractionChoiceStage2Callback.Create(this), this.vomitFromInteractionChoiceStage2DelayID, this.vomitFromInteractionChoiceStage2DelayInterval);
	}

	//
	//	Unregistration
	//

	private final func UnregisterClearLastAttemptedChoiceForFXCheckCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.clearLastAttemptedChoiceForFXCheckDelayID);
	}

	private final func UnregisterAllSmokingFXCallbacks() -> Void {
		this.queuedSmokingFX = false;
		UnregisterDFDelayCallback(this.DelaySystem, this.smokingFXStage1DelayID);
		UnregisterDFDelayCallback(this.DelaySystem, this.smokingFXStage2DelayID);
		UnregisterDFDelayCallback(this.DelaySystem, this.smokingFXStage3DelayID);
	}

	private final func UnregisterVomitFromInteractionChoiceStage2Callback() {
		UnregisterDFDelayCallback(this.DelaySystem, this.vomitFromInteractionChoiceStage2DelayID);
	}
}

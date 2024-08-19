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
import DarkFuture.Utils.HoursToGameTimeSeconds
import DarkFuture.Main.{
	DFMainSystem,
	DFNeedsDatum,
	DFAddictionDatum,
	DFAddictionUpdateDatum,
	DFAfflictionDatum,
	DFAfflictionUpdateDatum,
	DFFutureHoursData,
	DFNeedChangeDatum,
	DFTimeSkipData
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
import DarkFuture.Afflictions.DFTraumaAfflictionSystem

public struct DFAddictionTimeSkipIterationStateDatum {
	public let addictionAmount: Float;
	public let addictionStage: Int32;
	public let primaryEffectDuration: Float;
	public let backoffDuration: Float;
	public let withdrawalLevel: Int32;
	public let withdrawalDuration: Float;
	public let stackCount: Uint32;
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

	if IsSystemEnabledAndRunning(interactionSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();
		let effectTags: array<CName> = evt.staticData.GameplayTags();
			
		if Equals(effectID, t"HousingStatusEffect.Energized") {
			if DFNerveSystem.Get().GetHasNausea() {
				if StatusEffectSystem.ObjectHasStatusEffect(this, t"HousingStatusEffect.Energized") {
					StatusEffectHelper.RemoveStatusEffect(this, t"HousingStatusEffect.Energized");
				}
				interactionSystem.QueueVomitFromInteractionChoice();
			} else {
				interactionSystem.DrankCoffeeFromChoice();
			}

		} else if Equals(effectID, t"DarkFutureStatusEffect.GlitterStaminaMovement") {
			interactionSystem.ProcessGlitterConsumed();

		} else if ArrayContains(effectTags, n"DarkFutureSmokingFX") {
			interactionSystem.TryToPlaySmokingFromItemFX();

		}
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
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
	private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
	private let TraumaSystem: ref<DFTraumaAfflictionSystem>;

    private let BlackboardSystem: ref<BlackboardSystem>;
    private let UIInteractionsBlackboard: ref<IBlackboard>;

    private let choiceListener: ref<CallbackHandle>;
	private let choiceHubListener: ref<CallbackHandle>;

    private let lastAttemptedChoiceCaption: String;
	private let lastAttemptedChoiceIconName: CName;

    private let clearLastAttemptedChoiceForFXCheckDelayID: DelayID;
    private let clearLastAttemptedChoiceForFXCheckDelayInterval: Float = 10.0;

    // Location Memory from Prompts
	private let q003_lastMeredithStoutPosition: Vector4;
	private let mq006_lastRollercoasterPosition: Vector4;
	private let sq017_lastKerryCoffeePosition: Vector4;

	// Sleeping and Waiting
	private let skippingTimeFromRadialHubMenu: Bool = false;
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
		this.q003_lastMeredithStoutPosition = new Vector4(0.0, 0.0, 0.0, 0.0);
		this.mq006_lastRollercoasterPosition = new Vector4(0.0, 0.0, 0.0, 0.0);
		this.sq017_lastKerryCoffeePosition = new Vector4(0.0, 0.0, 0.0, 0.0);
		this.skippingTimeFromRadialHubMenu = false;
		this.lastEnergyBeforeSleeping = 0.0;
		this.queuedSmokingFX = false;
	}
	private final func DoPostResumeActions() -> Void {}
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}
	private final func DoStopActions() -> Void {}
	private final func SetupData() -> Void {}
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
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
		this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
		this.TraumaSystem = DFTraumaAfflictionSystem.GetInstance(gameInstance);
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
		DFLog(this.debugEnabled, this, "choiceIconName: " + NameToString(choiceIconName));
		if StrContains(choiceCaption, "[Sleep]") && Equals(choiceIconName, n"Wait") {
			return true;
		}

		return false;
	}

    private final func IsFXAllowedChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if Equals(choiceCaption, "[Take shower]") {
			return true;
		} else if Equals(choiceCaption, "[Look in mirror]") {
			return true;
		} else if Equals(choiceCaption, "[Sit]") {
			return true;
		} else if Equals(choiceCaption, "[Stand]") {
			return true;
		} else if Equals(choiceCaption, "[Turn on TV]") {
			return true;
		} else if Equals(choiceCaption, "[Look outside]") {
			return true;
		} else if Equals(choiceCaption, "[Stop looking]") {
			return true;
		} else if Equals(choiceCaption, "[Step away]") {
			return true;
		} else if Equals(choiceCaption, "[Smoke]") {
			return true;
		} else if Equals(choiceCaption, "[Take a drag]") {
			return true;
		} else if Equals(choiceCaption, "[Flick ash]") {
			return true;
		} else if Equals(choiceCaption, "[Put out]") {
			return true;
		} else if Equals(choiceCaption, "[Stop playing]") {
			return true;
		} else if Equals(choiceCaption, "[Lean]") {
			return true;
		} else if Equals(choiceCaption, "[Straighten up]") {
			return true;
		} else if StrContains(choiceCaption, "[Drink") {
			return true;
		} else if Equals(choiceCaption, "[Sit at bar] Could use a drink.") {
			return true;
		} else if Equals(choiceCaption, "[Step away from bar]") {
			return true;
		}

		return false;
	}

	private final func IsNerveRegenInteractionChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		// Multiple Apartment / Location Interactions
		if Equals(choiceCaption, "[Take shower]") {
			return true;

		} else if Equals(choiceCaption, "[Dance]") {
			return true;

		}

		return false;
	}

    private final func IsNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		// Romantic Activities
		if Equals(choiceIconName, n"Prostitute") {
			return true;
		
		// Romance - q003 Meredith Stout Scene
		} else if Equals(choiceCaption, "So what now?") && Vector4.DistanceSquared(this.q003_lastMeredithStoutPosition, this.player.GetWorldPosition()) < 10.0 {
			return true;
		
		// Japantown Apartment Interactions
		} else if Equals(choiceIconName, n"PlayGuitar") && StrContains(choiceCaption, "[Play ") {
			return true;

		// Rollercoaster
		} else if Equals(choiceCaption, "[Get out]") && Vector4.DistanceSquared(this.mq006_lastRollercoasterPosition, this.player.GetWorldPosition()) < 10.0 {
			return true;

		// Zen Master meditation sessions
		} else if Equals(choiceCaption, "[Stand] Nice trick.") {
			return true;
		} else if Equals(choiceCaption, "[Stand] He's gone again.") {
			return true;
		} else if Equals(choiceCaption, "[Stand] Of course.") {
			return true;
		} else if Equals(choiceCaption, "[Stand] There he goes again.") {
			return true;

		// Phantom Liberty: Kress Street Hideout Interactions
		} else if Equals(choiceCaption, "[End meditation]") {
			return true;

		// Phantom Liberty: Bootleg Shard (V's Apartment)
		} else if Equals(choiceCaption, "[Play braindance]") {
			return true;
		}

		return false;
	}

    private final func IsSmallNerveRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if Equals(choiceCaption, "[Burn incense]") {
			return true;
		} else if Equals(choiceCaption, "[Hit ball]") {
			return true;
		} else if StrContains(choiceCaption, "[Kiss]") {
			return true;
		} else if StrContains(choiceCaption, "[Cuddle]") {
			return true;
		} else if StrContains(choiceCaption, "[Hug]") {
			return true;
		}

		return false;
	}

    private final func IsHydrationRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		return this.IsDrinkTeaInCorpoPlazaChoice(choiceCaption) || this.IsDrinkTeaWithMrHandsChoice(choiceCaption);
	}

    private final func IsDrinkTeaInCorpoPlazaChoice(choiceCaption: String) -> Bool {
		// Corpo Plaza Apartment Interaction
		if Equals(choiceCaption, "[Drink tea]") {
			return true;
		}

		return false;
	}

	private final func IsDrinkTeaWithMrHandsChoice(choiceCaption: String) -> Bool {
		// Phantom Liberty: Mr. Hands scene in Heavy Hearts Club
		if Equals(choiceCaption, "[Sit and drink]") {
			return true;
		}

		return false;
	}

    private final func IsDrinkCoffeeWithKerryChoice(choiceCaption: String) -> Bool {
		if Equals(choiceCaption, "[Drink]") && Vector4.DistanceSquared(this.sq017_lastKerryCoffeePosition, this.player.GetWorldPosition()) < 10.0 {
			return true;
		}

		return false;
	}

    private final func IsNutritionRestorationChoice(choiceCaption: String, choiceIconName: CName) -> Bool {
		if StrContains(choiceCaption, "[Eat") {
			return true;
		}

		return false;
	}

	//
	//	Sleeping and Waiting
	//
	public final func SetSkippingTimeFromRadialHubMenu(value: Bool) -> Void {
		this.skippingTimeFromRadialHubMenu = value;
	}

	public final func IsPlayerSleeping() -> Bool {
		if this.skippingTimeFromRadialHubMenu {
			DFLog(this.debugEnabled, this, "Player is skipping time.");
			return false;
		} else {
			DFLog(this.debugEnabled, this, "Player is sleeping.");
			return true;
		}
	}

	public final func CalculateAddictionWithdrawalStateFromTimeSkip(
		logName: String, 
		addictionBackoffDurations: array<Float>, 
		mildWithdrawalDuration: Float, 
		severeWithdrawalDuration: Float,
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
					withdrawalDuration = mildWithdrawalDuration;
					withdrawalLevel = 1;
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
						if withdrawalLevel <= 2 {
							withdrawalDuration = mildWithdrawalDuration;
						} else {
							withdrawalDuration = severeWithdrawalDuration;
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
						if stackCount == 0u {
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

	public final func CalculateAfflictionStateFromTimeSkip(
		logName: String,
		stackCount: Uint32,
		cureDuration: Float,
		suppressionDuration: Float,
		hasQualifyingSuppressionActiveStatusEffect: Bool
	) -> DFAfflictionUpdateDatum {
		// Does the player have a cure duration?
		if cureDuration > 0.0 {
			cureDuration -= 300.0;
			if cureDuration <= 0.0 {
				cureDuration = 0.0;
				if stackCount > 0u {
					stackCount -= 1u;
				}
			}
		}

		// Does the player have a suppression duration?
		if suppressionDuration > 0.0 {
			suppressionDuration -= 300.0;
			if suppressionDuration <= 0.0 {
				suppressionDuration = 0.0;
			}
		}

		// Does the player have a qualifying suppression active status effect?
		if hasQualifyingSuppressionActiveStatusEffect {
			// No active status effect will be active at the end of the iteration; mark it as expired.
			hasQualifyingSuppressionActiveStatusEffect = false;
		}

		DFLog(this.debugEnabled, this, "=====================================================================================");
		DFLog(this.debugEnabled, this, "Predictive " + logName + " StackCount; " + ToString(stackCount));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " CureDuration; " + ToString(cureDuration));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " SuppressionDuration: " + ToString(suppressionDuration));
		DFLog(this.debugEnabled, this, "Predictive " + logName + " HasQualifyingSuppressionActiveStatusEffect: " + ToString(hasQualifyingSuppressionActiveStatusEffect));
		DFLog(this.debugEnabled, this, "=====================================================================================");

		let afflictionTimeSkipIterationData: DFAfflictionUpdateDatum;
		afflictionTimeSkipIterationData.stackCount = stackCount;
		afflictionTimeSkipIterationData.cureDuration = cureDuration;
		afflictionTimeSkipIterationData.suppressionDuration = suppressionDuration;
		afflictionTimeSkipIterationData.hasQualifyingSuppressionActiveStatusEffect = hasQualifyingSuppressionActiveStatusEffect;

		return afflictionTimeSkipIterationData;
	}

	public final func GetCalculatedValuesForFutureHours() -> DFFutureHoursData {
		let isSleeping: Bool = this.IsPlayerSleeping();
		
		// Need Variables
		let calculatedBasicNeedsData: array<DFNeedsDatum>;
		let calculatedHydrationAtHour: Float = this.HydrationSystem.GetNeedValue();
		let calculatedNutritionAtHour: Float = this.NutritionSystem.GetNeedValue();
		let calculatedEnergyAtHour: Float = this.EnergySystem.GetNeedValue();
		let calculatedNerveAtHour: Float = this.NerveSystem.GetNeedValue();
		let calculatedHardNerveMaxAtHour: Float = this.NerveSystem.GetNeedMax();

		// Addiction Variables
		let calculatedAddictionData: array<DFAddictionDatum>;

		// Affliction Variables
		let calculatedAfflictionData: array<DFAfflictionDatum>;

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

		// Trauma Affliction Variables
		let traumaDataAccumulator: DFAfflictionUpdateDatum;
		traumaDataAccumulator.stackCount = this.TraumaSystem.GetAfflictionStacks();
		traumaDataAccumulator.cureDuration = this.TraumaSystem.GetCurrentAfflictionCureDurationInGameTimeSeconds();
		traumaDataAccumulator.suppressionDuration = this.TraumaSystem.GetCurrentAfflictionSuppressionDurationInGameTimeSeconds();
		traumaDataAccumulator.hasQualifyingSuppressionActiveStatusEffect = this.TraumaSystem.HasQualifyingSuppressionActiveStatusEffect();

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
			
			let traumaData: DFAfflictionUpdateDatum;
			traumaData.stackCount = traumaDataAccumulator.stackCount;
			traumaData.cureDuration = traumaDataAccumulator.cureDuration;
			traumaData.suppressionDuration = traumaDataAccumulator.suppressionDuration;
			traumaData.hasQualifyingSuppressionActiveStatusEffect = traumaDataAccumulator.hasQualifyingSuppressionActiveStatusEffect;

			let afflictionData: DFAfflictionDatum;
			afflictionData.trauma = traumaData;

			// Accumulate all of the changes by iterating over each update cycle within the hour (60 / 12, or every 5 minutes)
			let j = 1;
			while j <= 12 {
				//
				// Nutrition and Hydration
				//
				let nutritionChangeTemp: Float = this.NutritionSystem.GetNutritionChange();
				let hydrationChangeTemp: Float = this.HydrationSystem.GetHydrationChange(true);

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
				let energyChangeTemp: Float = this.EnergySystem.GetEnergyChangeWithRecoverLimit(calculatedEnergyAtHour, calculatedNerveAtHour, isSleeping);
				calculatedEnergyAtHour = ClampF(calculatedEnergyAtHour + energyChangeTemp, 0.0, this.EnergySystem.GetNeedMax());

				//
				// Nerve
				//
				
				if isSleeping {
					// When sleeping, if recovering Energy, Nerve also recovers.
					if (energyChangeTemp > 0.0 || calculatedEnergyAtHour == 100.0) {
						calculatedNerveAtHour += this.NerveSystem.nerveRecoverAmountSleeping;
					}
				} else {
					let nerveChangeTemp: Float = this.NerveSystem.GetNerveChangeFromTimeInProvidedState(calculatedNerveAtHour, this.HydrationSystem.GetNeedStageAtValue(calculatedHydrationAtHour), this.NutritionSystem.GetNeedStageAtValue(calculatedNutritionAtHour), this.EnergySystem.GetNeedStageAtValue(calculatedEnergyAtHour));
					calculatedNerveAtHour += nerveChangeTemp;
				}

				let nicotineDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Nicotine", 
					this.NicotineAddictionSystem.GetAddictionBackoffDurationsInRealTimeMinutesByStage(),
					this.NicotineAddictionSystem.GetAddictionMildWithdrawalDurationInGameTimeSeconds(),
					this.NicotineAddictionSystem.GetAddictionSevereWithdrawalDurationInGameTimeSeconds(),
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
					this.AlcoholAddictionSystem.GetAddictionMildWithdrawalDurationInGameTimeSeconds(),
					this.AlcoholAddictionSystem.GetAddictionSevereWithdrawalDurationInGameTimeSeconds(),
					this.AlcoholAddictionSystem.GetAddictionAmountLossPerDay(),
					alcoholDataAccumulator.addictionAmount,
					alcoholDataAccumulator.addictionStage, 
					alcoholDataAccumulator.primaryEffectDuration, 
					alcoholDataAccumulator.backoffDuration,
					alcoholDataAccumulator.withdrawalLevel, 
					alcoholDataAccumulator.withdrawalDuration,
					alcoholDataAccumulator.stackCount,
					true,
					this.AlcoholAddictionSystem.GetEffectDuration()
				);

				let narcoticDataForIter: DFAddictionTimeSkipIterationStateDatum = this.CalculateAddictionWithdrawalStateFromTimeSkip("Narcotic", 
					this.NarcoticAddictionSystem.GetAddictionBackoffDurationsInRealTimeMinutesByStage(),
					this.NarcoticAddictionSystem.GetAddictionMildWithdrawalDurationInGameTimeSeconds(),
					this.NarcoticAddictionSystem.GetAddictionSevereWithdrawalDurationInGameTimeSeconds(),
					this.NarcoticAddictionSystem.GetAddictionAmountLossPerDay(),
					narcoticDataAccumulator.addictionAmount,
					narcoticDataAccumulator.addictionStage, 
					narcoticDataAccumulator.primaryEffectDuration, 
					narcoticDataAccumulator.backoffDuration,
					narcoticDataAccumulator.withdrawalLevel, 
					narcoticDataAccumulator.withdrawalDuration,
					0u
				);

				let traumaDataForIter: DFAfflictionUpdateDatum = this.CalculateAfflictionStateFromTimeSkip("Trauma",
					traumaDataAccumulator.stackCount,
					traumaDataAccumulator.cureDuration,
					traumaDataAccumulator.suppressionDuration,
					traumaDataAccumulator.hasQualifyingSuppressionActiveStatusEffect
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

				traumaDataAccumulator.stackCount = traumaDataForIter.stackCount;
				traumaDataAccumulator.cureDuration = traumaDataForIter.cureDuration;
				traumaDataAccumulator.suppressionDuration = traumaDataForIter.suppressionDuration;
				traumaDataAccumulator.hasQualifyingSuppressionActiveStatusEffect = traumaDataForIter.hasQualifyingSuppressionActiveStatusEffect;

				// Does the player have an Addiction Treatment duration?
				if addictionTreatmentDuration > 0.0 {
					addictionTreatmentDuration = ClampF(addictionTreatmentDuration - 300.0, 0.0, HoursToGameTimeSeconds(24));
				}

				// "Soft" cap Nerve based on Withdrawal. "Hard" cap Nerve based on Trauma.
				calculatedHardNerveMaxAtHour = this.NerveSystem.GetCalculatedNeedMaxInProvidedState(traumaDataForIter);
				let withdrawalTargetForIter: Float = this.NerveSystem.GetNerveWithdrawalTargetFromProvidedState(addictionTreatmentDuration, alcoholDataAccumulator.withdrawalLevel, nicotineDataAccumulator.withdrawalLevel, narcoticDataAccumulator.withdrawalLevel);
				let lowestNerveMaxAtHour = MinF(calculatedHardNerveMaxAtHour, withdrawalTargetForIter);
				calculatedNerveAtHour = ClampF(calculatedNerveAtHour, 0.0, lowestNerveMaxAtHour);

				j += 1;
			};
			
			// Store the target values for each need at this specific hour.
			basicNeedsData.energy.value = calculatedEnergyAtHour;
			basicNeedsData.nutrition.value = calculatedNutritionAtHour;
			basicNeedsData.hydration.value = calculatedHydrationAtHour;
			basicNeedsData.nerve.value = calculatedNerveAtHour;
			basicNeedsData.nerve.ceiling = calculatedHardNerveMaxAtHour;
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
			ArrayPush(calculatedAddictionData, addictionData);

			// Store the target values for Trauma at this specific hour.
			afflictionData.trauma.stackCount = traumaDataAccumulator.stackCount;
			afflictionData.trauma.cureDuration = traumaDataAccumulator.cureDuration;
			afflictionData.trauma.suppressionDuration = traumaDataAccumulator.suppressionDuration;
			afflictionData.trauma.hasQualifyingSuppressionActiveStatusEffect = traumaDataAccumulator.hasQualifyingSuppressionActiveStatusEffect;
			ArrayPush(calculatedAfflictionData, afflictionData);

			i += 1;
		};

		let calculatedData: DFFutureHoursData = new DFFutureHoursData(calculatedBasicNeedsData, calculatedAddictionData, calculatedAfflictionData);

		return calculatedData;
	}

    //
    //  Logic
    //
	public final func OnChoiceHub(value: Variant) {
		let hubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(value);
		
		for hub in hubs.choiceHubs {
			DFLog(this.debugEnabled, this, "Hub Title: " + ToString(hub.title));
			if Equals(hub.title, "Stout") {
				// Used to catch a Romance activity event, combined with the caption prompt.
				this.q003_lastMeredithStoutPosition = this.player.GetWorldPosition();
			} else if Equals(hub.title, "LocKey#46442") {
				// Pacifica Rollercoaster
				this.mq006_lastRollercoasterPosition = this.player.GetWorldPosition();
			} else if Equals(hub.title, "LocKey#37579") {
				// "Rebel! Rebel!" Coffee with Kerry in Captain Caliente
				this.sq017_lastKerryCoffeePosition = this.player.GetWorldPosition();
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

		} else if this.IsDrinkCoffeeWithKerryChoice(choiceCaption) {
			this.DrankCoffeeFromChoice();

		} else if StrContains(choiceCaption, "[Smoke]") || StrContains(choiceCaption, "[Take a drag]") {
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureSmoking");
			}
			
			// Smoking status effect variant to suppress additional unneeded FX
			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");

			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now instead of a queued change
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			this.NerveSystem.ChangeNeedValue(15.0, uiFlags, false, true);

		} else if this.IsNerveRegenInteractionChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.SetNerveRegenTarget(100.0);
			
		} else if this.IsNerveRestorationChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);

		} else if this.IsSmallNerveRestorationChoice(choiceCaption, choiceIconName) {
			this.NerveSystem.QueueContextuallyDelayedNeedValueChange(15.0, true);

		} else if this.IsNutritionRestorationChoice(choiceCaption, choiceIconName) {
			this.NutritionSystem.QueueContextuallyDelayedNeedValueChange(100.0, true);

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
            this.EnergySystem.ChangeEnergyFromItems(12.0, 12.0, true);
		}
	}

	private final func SleepChoiceSelected() -> Void {
		if this.GameStateService.IsValidGameState("SleepChoiceSelected", true) {
			this.GameStateService.SetInSleepCinematic(true);
		}
	}

	public final func ProcessGlitterConsumed() -> Void {
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.GlitterSlowTime");
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

				} else if this.IsFXAllowedChoice(this.lastAttemptedChoiceCaption, this.lastAttemptedChoiceIconName) {
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
	public final func TryToPlaySmokingFromItemFX() {
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
			if Equals(this.player.GetResolvedGenderName(), n"Female") {
				vomitNotification.sfx = new DFAudioCue(n"cmn_generic_female_vomit", 0);
			} else {
				vomitNotification.sfx = new DFAudioCue(n"cmn_generic_male_vomit", 0);
			}
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

//
//	Base Game Methods
//

//	HubTimeSkipController - Catch pressing the "Skip Time" button and store a value.
//	If pressed and the value is set, this means that we are NOT sleeping.
//
@wrapMethod(HubTimeSkipController)
protected cb func OnTimeSkipButtonPressed(e: ref<inkPointerEvent>) -> Bool {
	let interactionSystem: ref<DFInteractionSystem> = DFInteractionSystem.Get();

	if IsSystemEnabledAndRunning(interactionSystem) {
		if e.IsAction(n"click") {
			interactionSystem.SetSkippingTimeFromRadialHubMenu(true);
		}
	}

	return wrappedMethod(e);
}

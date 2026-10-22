// -----------------------------------------------------------------------------
// DFAddictionSystemBase
// -----------------------------------------------------------------------------
//
// - Base class for creating addiction gameplay systems.
//
// - Used by:
//   - DFAddictionSystemAlcohol
//   - DFAddictionSystemNicotine
//   - DFAddictionSystemNarcotic
//

module DarkFuture.Addictions

import DarkFuture.Logging.*
import DarkFuture.Settings.*
import DarkFuture.System.*
import DarkFuture.Utils.{
    HoursToGameTimeSeconds,
    DFRunGuard
}
import DarkFuture.Main.{
    DFMainSystem,
    DFAddictionDatum,
    DFAddictionUpdateDatum,
    DFTimeSkipData
}
import DarkFuture.Services.{
    DFGameStateService,
    DFTutorial,
    DFGameStateServiceSceneTierChangedEvent,
    DFGameStateServiceFuryChangedEvent,
    DFGameStateServiceCyberspaceChangedEvent,
    DFPlayerStateService,
    PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent,
    PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent,
    PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent,
    PlayerStateServiceAddictionManagedEffectAppliedEvent,
    PlayerStateServiceAddictionManagedEffectRemovedEvent,
    DFNotificationService,
    DFCyberwareService,
    DFMessageContext,
    DFMessage,
    DFNotification,
    DFAddictionType,
    DFManagedEffectType
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Conditions.DFBiocorruptionConditionSystem

public enum DFAddictionEventType {
    UpdateFromTime = 0,
    UpdateFromTimeSkip = 1,
    AddictiveItemConsumed = 2
}

public struct DFAddictionValueChangedEventDatum {
	public let addictionType: DFAddictionType;
    public let eventType: DFAddictionEventType;
	public let amountChange: Float;
	public let newAmount: Float;
	public let stageChange: Int32;
	public let newStage: Int32;
}

public class DFAddictionValueChangedEvent extends CallbackSystemEvent {
	private let data: DFAddictionValueChangedEventDatum;

	public func GetData() -> DFAddictionValueChangedEventDatum {
		//DFProfile();
        return this.data;
    }

    public static func Create(data: DFAddictionValueChangedEventDatum) -> ref<DFAddictionValueChangedEvent> {
		//DFProfile();
        let event = new DFAddictionValueChangedEvent();
        event.data = data;
        return event;
    }
}

public class DFAddictionCurrentDayUpdateEvent extends Event {
    private let AddictionSystem: ref<DFAddictionSystemBase>;

    public func GetData() -> ref<DFAddictionSystemBase> {
        return this.AddictionSystem;
    }

    public static func Create(addictionSystem: ref<DFAddictionSystemBase>) -> ref<DFAddictionCurrentDayUpdateEvent> {
        let self: ref<DFAddictionCurrentDayUpdateEvent> = new DFAddictionCurrentDayUpdateEvent();
        self.AddictionSystem = addictionSystem;
        return self;
    }
}

@addMethod(PlayerPuppet)
private cb func OnDarkFutureAddictionCurrentDayUpdate(evt: ref<DFAddictionCurrentDayUpdateEvent>) -> Bool {
    evt.GetData().OnDayUpdate();
}

public abstract class DFAddictionSystemEventListener extends DFSystemEventListener {
    //
	// Required Overrides
	//
    private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
        //DFProfile();
		DFLogNoSystem(DFSystemlessDebugEnabled(), this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceSceneTierChangedEvent>(), this, n"OnGameStateServiceSceneTierChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceFuryChangedEvent>(), this, n"OnGameStateServiceFuryChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceCyberspaceChangedEvent>(), this, n"OnGameStateServiceCyberspaceChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent>(), this, n"OnPlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent>(), this, n"OnPlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent>(), this, n"OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionManagedEffectAppliedEvent>(), this, n"OnPlayerStateServiceAddictionManagedEffectAppliedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionManagedEffectRemovedEvent>(), this, n"OnPlayerStateServiceAddictionManagedEffectRemovedEvent", true);
    }

    private cb func OnGameStateServiceSceneTierChangedEvent(event: ref<DFGameStateServiceSceneTierChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnSceneTierChanged(event.GetData());
	}

	private cb func OnGameStateServiceFuryChangedEvent(event: ref<DFGameStateServiceFuryChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnFuryStateChanged(event.GetData());
	}

    private cb func OnGameStateServiceCyberspaceChangedEvent(event: ref<DFGameStateServiceCyberspaceChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnCyberspaceChanged(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent(event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnUpdate(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent>) {
        //DFProfile();
        this.GetSystemInstance().AddictionTreatmentDurationUpdateFromTimeSkipFinished(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent(event: ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionTreatmentEffectAppliedOrRemoved();
    }

    private cb func OnPlayerStateServiceAddictionManagedEffectAppliedEvent(event: ref<PlayerStateServiceAddictionManagedEffectAppliedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionManagedEffectApplied(event.GetType(), event.GetStackCount(), event.GetActiveEffectApplied());
    }

    private cb func OnPlayerStateServiceAddictionManagedEffectRemovedEvent(event: ref<PlayerStateServiceAddictionManagedEffectRemovedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionManagedEffectRemoved(event.GetType());
    }
}

public abstract class DFAddictionSystemBase extends DFSystem {
    private persistent let currentAddictionAmountRev2: Float = 0.0;
    private persistent let currentAddictionStageRev2: Int32 = 0;
    private persistent let currentWithdrawalLevelRev2: Int32 = 0;
    public persistent let remainingWithdrawalDurationInGameTimeSecondsRev2: Float = 0.0;
    public persistent let remainingBackoffDurationInGameTimeSecondsRev2: Float = 0.0;
    private persistent let hasEverPlayedTier1WithdrawalAnimRev2: Bool = false;
    private persistent let hasEverPlayedTier2WithdrawalAnimRev2: Bool = false;

    public persistent let hasEverBeenAddicted: Bool = false;
    private let therapySetAddictionStateIndexFactListener: Uint32;
    
    private let lastWithdrawalLevel: Int32 = 0;

    private let TransactionSystem: ref<TransactionSystem>;
    public let QuestsSystem: ref<QuestsSystem>;
    private let MainSystem: ref<DFMainSystem>;
    public let GameStateService: ref<DFGameStateService>;
    public let PlayerStateService: ref<DFPlayerStateService>;
    public let NotificationService: ref<DFNotificationService>;
    public let CyberwareService: ref<DFCyberwareService>;
    public let NerveSystem: ref<DFNerveSystem>;
    public let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;

    private let dayTimeListener: Uint32;

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    private func RegisterListeners() -> Void {
        this.therapySetAddictionStateIndexFactListener = this.QuestsSystem.RegisterListener(this.GetSetTherapyAddictionStateIndexFactAction(), this, n"OnSetTherapyAddictionStateIndexFactChanged");

        // Update at midnight each day.
        let now: GameTime = GetGameInstance().GetGameTime();
        let dayTomorrow: Int32 = now.Days() + 1;
        let midnightTomorrow: GameTime = GameTime.MakeGameTime(dayTomorrow, 0);
        this.dayTimeListener = GameInstance.GetTimeSystem(GetGameInstance()).RegisterListener(this.player, DFAddictionCurrentDayUpdateEvent.Create(this), midnightTomorrow, 0);
    }

	private func UnregisterListeners() -> Void {
        this.QuestsSystem.UnregisterListener(this.GetSetTherapyAddictionStateIndexFactAction(), this.therapySetAddictionStateIndexFactListener);
        this.therapySetAddictionStateIndexFactListener = 0u;

        GameInstance.GetTimeSystem(GetGameInstance()).UnregisterListener(this.dayTimeListener);
        this.dayTimeListener = 0u;
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
	public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipBegin() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
    }

    public func GetSystems() -> Void {
        //DFProfile();
		let gameInstance = GetGameInstance();
        this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.currentAddictionAmountRev2 = 0.0;
        this.currentAddictionStageRev2 = 0;
        this.currentWithdrawalLevelRev2 = 0;
        this.remainingWithdrawalDurationInGameTimeSecondsRev2 = 0.0;
        this.remainingBackoffDurationInGameTimeSecondsRev2 = 0.0;
        this.lastWithdrawalLevel = 0;

        StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetWithdrawalStatusEffectTag());
        this.MainSystem.UpdateCodexEntries();
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.SetupData();
        this.ReevaluateSystem();
        this.MainSystem.UpdateCodexEntries();
    }

    //
	//	RunGuard Protected Methods
	//

    // Addiction Systems don't maintain their own update registrations, and instead tick
    // after the PlayerStateService has updated the Addiction Treatment Duration. This
    // prevents a race condition between updating the Addiction Treatment Duration and
    // all other Addictions.
	public func OnUpdate(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "OnUpdate");

		if this.GameStateService.IsValidGameState(this, true) {
            let addictionAmount: Float = this.GetAddictionAmount();
            let addictionStage: Int32 = this.GetAddictionStage();
            
            this.ReduceWithdrawalDuration(gameTimeSecondsToReduce);
            this.ReduceBackoffDuration(gameTimeSecondsToReduce);

            let addictionAmountDelta: Float = 0.0;
            let addictionStageDelta: Int32 = 0;

            if this.GetAddictionStage() == 0 && addictionStage > 0 {
                // This update cured the addiction, update the values.
                // Averts a floating point imprecision error if doing math on floats that are very similar.
                let newAddictionAmount: Float = this.GetAddictionAmount();
                let newAddictionStage: Int32 = this.GetAddictionStage();
                addictionAmountDelta = newAddictionAmount - addictionAmount;
                addictionStageDelta = newAddictionStage - addictionStage;
                addictionAmount = newAddictionAmount;
                addictionStage = newAddictionStage;
            }

            this.DispatchAddictionValueChangedEvent(DFAddictionEventType.UpdateFromTime, addictionAmountDelta, addictionAmount, addictionStageDelta, addictionStage);
		}
	}

    public func OnDayUpdate() -> Void {
        if DFRunGuard(this) { return; }
        DFLog(this, "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ OnDayUpdate ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^");

        if this.GameStateService.IsValidGameState(this, true) {
            this.ReduceAddictionFromTime();
        }
    }

    public func OnAddictionTreatmentEffectAppliedOrRemoved() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnAddictionTreatmentEffectAppliedOrRemoved");

        this.ReevaluateSystem();
    }

    public func OnSceneTierChanged(value: GameplayTier) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnSceneTierChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func OnFuryStateChanged(value: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnFuryStateChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func OnCyberspaceChanged(value: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnCyberspaceChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func AddictionTreatmentDurationUpdateFromTimeSkipFinished(addictionData: DFAddictionDatum) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "addictionData: " + ToString(addictionData));

        let oldAddictionAmount: Float = this.currentAddictionAmountRev2;
        let oldStage: Int32 = this.currentAddictionStageRev2;

        let updateDatum: DFAddictionUpdateDatum = this.GetSpecificAddictionUpdateData(addictionData);
        //this.SetAddictionAmount(updateDatum.addictionAmount);
        // TODO above, why commented out?
        this.SetAddictionStage(updateDatum.addictionStage);
        this.SetWithdrawalLevel(updateDatum.withdrawalLevel, true);
        this.SetRemainingBackoffDurationInGameTimeSeconds(updateDatum.remainingBackoffDuration);
        this.SetRemainingWithdrawalDurationInGameTimeSeconds(updateDatum.remainingWithdrawalDuration);

        this.ReevaluateSystem(); // This can mutate Withdrawal Level, Stage, and Addiction Amount!

        let newAddictionAmount: Float = this.currentAddictionAmountRev2;
        this.DispatchAddictionValueChangedEvent(DFAddictionEventType.UpdateFromTimeSkip, newAddictionAmount - oldAddictionAmount, newAddictionAmount, updateDatum.addictionStage - oldStage, updateDatum.addictionStage);
	}

    public func GetAddictionAmount() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentAddictionAmountRev2;
    }

    public func GetAddictionAmountAsPercentageToNextStage() -> Float {
        if DFRunGuard(this) { return 0.0; }

        let addictionStageAdvanceAmounts: array<Float> = this.GetAddictionStageAdvanceAmounts();
        return this.currentAddictionAmountRev2 / addictionStageAdvanceAmounts[this.GetAddictionStage()];
    }

    public func GetAddictionAmountAsPercentageToNextStageInProvidedState(amount: Float, stage: Int32) -> Float {
        if DFRunGuard(this) { return 0.0; }

        let addictionStageAdvanceAmounts: array<Float> = this.GetAddictionStageAdvanceAmounts();
        return amount / addictionStageAdvanceAmounts[stage];
    }

    public func SetAddictionAmount(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.currentAddictionAmountRev2 = MaxF(value, 0.0);
    }

    public func ModAddictionAmount(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.currentAddictionAmountRev2 += value;
        this.currentAddictionAmountRev2 = MaxF(this.currentAddictionAmountRev2, 0.0);
        
        return this.currentAddictionAmountRev2;
    }

    public func GetAddictionStage() -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentAddictionStageRev2;
    }

    public func SetAddictionStage(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.currentAddictionStageRev2 = Clamp(value, 0, 4);

        if this.currentAddictionStageRev2 > 0 {
            this.hasEverBeenAddicted = true;
        }

        this.QuestsSystem.SetFact(this.GetAddictionStageFact(), value);
    }

    public func ModAddictionStage(value: Int32) -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        this.currentAddictionStageRev2 += value;
        this.currentAddictionStageRev2 = Clamp(this.currentAddictionStageRev2, 0, 4);

        if this.currentAddictionStageRev2 > 0 {
            this.hasEverBeenAddicted = true;
        }

        this.QuestsSystem.SetFact(this.GetAddictionStageFact(), this.currentAddictionStageRev2);

        return this.currentAddictionStageRev2;
    }

    public func GetWithdrawalLevel() -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentWithdrawalLevelRev2;
    }

    public func SetWithdrawalLevel(value: Int32, opt isFromTimeskip: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevelRev2;
        this.currentWithdrawalLevelRev2 = Clamp(value, 0, 5);

        if !isFromTimeskip {
            this.BiocorruptionConditionSystem.HandleWithdrawalLevelChange();
        }

        this.NerveSystem.ForceNeedMaxValueUpdate();
    }

    public func ModWithdrawalLevel(value: Int32) -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevelRev2;
        this.currentWithdrawalLevelRev2 += value;
        this.currentWithdrawalLevelRev2 = Clamp(this.currentWithdrawalLevelRev2, 0, 5);
        this.NerveSystem.ForceNeedMaxValueUpdate();
        this.BiocorruptionConditionSystem.HandleWithdrawalLevelChange();

        return this.currentWithdrawalLevelRev2;
    }

    public func GetRemainingWithdrawalDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        return this.remainingWithdrawalDurationInGameTimeSecondsRev2;
    }

    public func SetRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.remainingWithdrawalDurationInGameTimeSecondsRev2 = MaxF(value, 0.0);
    }

    public func ModRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.remainingWithdrawalDurationInGameTimeSecondsRev2 += value;
        this.remainingWithdrawalDurationInGameTimeSecondsRev2 = MaxF(this.remainingWithdrawalDurationInGameTimeSecondsRev2, 0.0);

        return this.remainingWithdrawalDurationInGameTimeSecondsRev2;
    }

    public func GetRemainingBackoffDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.remainingBackoffDurationInGameTimeSecondsRev2;
    }

    public func SetRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.remainingBackoffDurationInGameTimeSecondsRev2 = MaxF(value, 0.0);
    }

    public func ModRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.remainingBackoffDurationInGameTimeSecondsRev2 += value;
        this.remainingBackoffDurationInGameTimeSecondsRev2 = MaxF(this.remainingBackoffDurationInGameTimeSecondsRev2, 0.0);

        return this.remainingBackoffDurationInGameTimeSecondsRev2;
    }

    //
    //  Required Overrides
    //
    private func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
        //DFProfile();
		this.LogMissingOverrideError("GetSpecificAddictionUpdateData");
        let none: DFAddictionUpdateDatum;
        return none;
	}

	private func GetEffectDuration() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetEffectDuration");
        return 0.0;
    }

	private func GetAddictionMaxStage() -> Int32 {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionMaxStage");
        return 0;
    }

	private func GetAddictionProgressionChance() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionProgressionChance");
        return 0.0;
    }

	public func GetAddictionAmountOnUse() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionAmountOnUse");
        return 0.0;
    }

	private func GetAddictionStageAdvanceAmounts() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionStageAdvanceAmounts");
        return [];
    }

	public func GetAddictionNeedLimits() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionNeedLimits");
        return [];
    }

	public func GetAddictionBackoffDurationsInGameTimeSecondsByStage() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionBackoffDurationsInGameTimeSecondsByStage");
        return [];
    }

	public func GetAddictionAmountLossPerDay() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionAmountLossPerDay");
        return 0.0;
    }

	public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionWithdrawalDurationsInGameTimeSeconds");
        return [];
    }

    private func DoPostAddictionCureActions() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("DoPostAddictionCureActions");
    }

    private func DoPostAddictionAdvanceActions() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("DoPostAddictionAdvanceActions");
    }

    public func PlayWithdrawalAdvanceSFX() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("PlayWithdrawalAdvanceSFX");
    }

    private func GetWithdrawalStatusEffectTag() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetWithdrawalStatusEffectTag");
        return n"";
    }

    private func GetAddictionStatusEffectBaseID() -> TweakDBID {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionStatusEffectBaseID");
        return t"";
    }

    public func GetAddictionManagedEffectType() -> DFManagedEffectType {
		//DFProfile();
        this.LogMissingOverrideError("GetAddictionManagedEffectType");
        return DFManagedEffectType.None;
    }

    private func GetTutorialTitleKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetTutorialTitleKey");
		return n"";
	}

	private func GetTutorialMessageKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetTutorialMessageKey");
		return n"";
	}

    public func GetWithdrawalAnimationLowFirstTimeMessageKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetWithdrawalAnimationLowFirstTimeMessageKey");
		return n"";
	}

    public func GetWithdrawalAnimationHighFirstTimeMessageKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetWithdrawalAnimationHighFirstTimeMessageKey");
		return n"";
	}

    private func GetAddictionNotificationMessageKeyStage1() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageKeyStage1");
		return n"";
	}

    private func GetAddictionNotificationMessageKeyStage2() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageKeyStage2");
		return n"";
	}

    private func GetAddictionNotificationMessageKeyStage3() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageKeyStage3");
		return n"";
	}

    private func GetAddictionNotificationMessageKeyStage4() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageKeyStage4");
		return n"";
	}

    private func GetAddictionNotificationMessageKeyCured() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageKeyCured");
		return n"";
	}

    private func GetAddictionNotificationMessageContext() -> DFMessageContext {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionNotificationMessageContext");
		return DFMessageContext.None;
	}

    private func GetAddictionTherapyResponseIndexFact() -> CName {
		//DFProfile();
		this.LogMissingOverrideError("GetAddictionTherapyResponseIndexFact");
		return n"";
	}

    private func GetAddictionStageFact() -> CName {
		//DFProfile();
		this.LogMissingOverrideError("GetAddictionStageFact");
		return n"";
	}

    private func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetSetTherapyAddictionStateIndexFactAction");
		return n"";
    }

    private func GetAddictionAdvanceNotificationKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionAdvanceNotificationKey");
		return n"";
    }

    private func GetAddictionWithdrawalRemovedNotificationKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionWithdrawalRemovedNotificationKey");
		return n"";
    }

    private func GetAddictionType() -> DFAddictionType {
        //DFProfile();
		this.LogMissingOverrideError("GetAddictionType");
		return DFAddictionType.None;
    }

    //
    //  System Methods
    //
    public func ReevaluateSystem() -> Void {
        //DFProfile();
		this.RefreshAddictionStatusEffects();
	}

    public func OnAddictionManagedEffectApplied(type: DFManagedEffectType, stackCount: Int32, activeEffectApplied: Bool) -> Void {
		//DFProfile();
        if Equals(type, this.GetAddictionManagedEffectType()) {
			if DFRunGuard(this) { return; }

            if activeEffectApplied {
                if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, this.GetWithdrawalStatusEffectTag()) {
                    StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetWithdrawalStatusEffectTag());

                    if this.GameStateService.IsInAnyMenu() {
                        let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
                        notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
                        notificationEvent.m_title = GetLocalizedTextByKey(this.GetAddictionWithdrawalRemovedNotificationKey());
                        notificationEvent.m_overrideCurrentNotification = false;
                        
                        GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
                    }
                }
                this.SetWithdrawalLevel(0);
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);
                this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
            }

			// Try to advance the player's addiction.
			this.TryToAdvanceAddiction(this.GetAddictionAmountOnUse(), stackCount, type);
		}
    }

	public func OnAddictionManagedEffectRemoved(type: DFManagedEffectType) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
        DFLog(this, "type: " + ToString(type));

        if Equals(type, this.GetAddictionManagedEffectType()) {
			if this.PlayerStateService.GetManagedEffectTotalStacksByType(this.GetAddictionManagedEffectType()) == 0u {
				if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
    }

    // TODO - Do we need to reregister?
    private final func ReduceAddictionFromTime() -> Void {
        //DFProfile();		
		let addictionAmountLoss = this.GetAddictionAmountLossPerDay();
        this.ModAddictionAmount(-addictionAmountLoss);
        this.DispatchAddictionValueChangedEvent(DFAddictionEventType.UpdateFromTime, -addictionAmountLoss, this.currentAddictionAmountRev2, 0, this.GetAddictionStage());
		DFLog(this, "ReduceAddictionFromTime currentAddictionAmountRev2 = " + ToString(this.currentAddictionAmountRev2));
	}

	private final func ReduceWithdrawalDuration(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		if this.GetRemainingWithdrawalDurationInGameTimeSeconds() > 0.0 {
            let remainingDuration: Float = this.ModRemainingWithdrawalDurationInGameTimeSeconds(-gameTimeSecondsToReduce);
			
			DFLog(this, "remainingWithdrawalDurationInGameTimeSecondsRev2 = " + ToString(remainingDuration));

            if remainingDuration == 0.0 {
                this.AdvanceWithdrawal();
            } 
		}
	}

	private final func ReduceBackoffDuration(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		if this.GetRemainingBackoffDurationInGameTimeSeconds() > 0.0 {
			let remainingDuration: Float = this.ModRemainingBackoffDurationInGameTimeSeconds(-gameTimeSecondsToReduce);

			DFLog(this, "remainingBackoffDurationInGameTimeSecondsRev2 = " + ToString(remainingDuration));

			if remainingDuration == 0.0 {
				this.AdvanceWithdrawal();
			}
		}
	}

    public final func TryToAdvanceAddiction(addictionAmountOnUse: Float, stackCount: Int32, type: DFManagedEffectType, opt fromQuest: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        
        let oldAddictionAmount: Float = this.GetAddictionAmount();
        let oldAddictionStage: Int32 = this.GetAddictionStage();

        let currentAddictionStageRev2 = oldAddictionStage;
        let i: Int32 = 0;
        while i < stackCount {
            if currentAddictionStageRev2 < this.GetAddictionMaxStage() {
                // Roll to check for addiction advancement.
                let progressionAttempt: Float = RandRangeF(0.0, 100.0);
                DFLog(this, "TryToAdvanceAddiction progressionAttempt = " + ToString(progressionAttempt));

                if progressionAttempt <= this.GetAddictionProgressionChance() {
                    let currentAddictionAmountRev2: Float = this.ModAddictionAmount(addictionAmountOnUse);

                    DFLog(this, "TryToAdvanceAddiction Advancing addiction! Addiction amount now: " + ToString(currentAddictionAmountRev2));
                    let addictionStageAdvanceAmounts: array<Float> = this.GetAddictionStageAdvanceAmounts();
                    if currentAddictionAmountRev2 >= addictionStageAdvanceAmounts[currentAddictionStageRev2] {
                        this.SetAddictionAmount(0.0);
                        currentAddictionStageRev2 = this.ModAddictionStage(1);
                        this.DoPostAddictionAdvanceActions();
                        this.QueueAddictionNotification(currentAddictionStageRev2);

                        if !fromQuest {
                            // If not originating from sq031 ("A Cool Metal Fire"), max out the player's active Tolerance count.
                            this.PlayerStateService.SetManagedEffectToleranceCountToMaxByType(type);
                        }

                        // Tutorial
                        if this.Settings.tutorialsEnabled && !this.PlayerStateService.hasShownAddictionTutorial {
                            this.PlayerStateService.hasShownAddictionTutorial = true;

                            let tutorial: DFTutorial;
                            tutorial.title = GetLocalizedTextByKey(n"DarkFutureTutorialAddictionTitle");
                            tutorial.message = GetLocalizedTextByKey(n"DarkFutureTutorialAddiction");
                            tutorial.iconID = t"";
                            this.NotificationService.QueueTutorial(tutorial);
                        }

                        if this.GameStateService.IsInAnyMenu() {
                            let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
                            notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
                            notificationEvent.m_title = GetLocalizedTextByKey(this.GetAddictionAdvanceNotificationKey());
                            notificationEvent.m_overrideCurrentNotification = false;
                            
                            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
                        }

                        DFLog(this, "TryToAdvanceAddiction Player addiction has advanced to stage " + ToString(currentAddictionStageRev2) + "!");
                    }
                }
            } else {
                DFLog(this, "TryToAdvanceAddiction Player already at max addiction stage.");
            }
            i += 1;
        }

        this.DispatchAddictionValueChangedEvent(DFAddictionEventType.AddictiveItemConsumed, this.currentAddictionAmountRev2 - oldAddictionAmount, this.currentAddictionAmountRev2, currentAddictionStageRev2 - oldAddictionStage, currentAddictionStageRev2);
	}

    private func AdvanceWithdrawal() -> Void {
        //DFProfile();
		DFLog(this, "AdvanceWithdrawal");

        let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
		if withdrawalLevel < this.currentAddictionStageRev2 {
			withdrawalLevel = this.ModWithdrawalLevel(1);
		} else if withdrawalLevel == this.currentAddictionStageRev2 {
            // Jump to Cessation
			this.SetWithdrawalLevel(5);
            withdrawalLevel = 5;
		} else if withdrawalLevel == 5 {
			this.SetWithdrawalLevel(0);
            withdrawalLevel = 0;
		}

		if withdrawalLevel > 0 {
            if withdrawalLevel < this.GetAddictionStage() {
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(HoursToGameTimeSeconds(2));
            } else {
                let durations: array<Float> = this.GetAddictionWithdrawalDurationsInGameTimeSeconds();
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(durations[withdrawalLevel]);
            }
			
            // Notification SFX
            if !this.BiocorruptionConditionSystem.GetHasEuphoria() {
                this.PlayWithdrawalAdvanceSFX();
            }
		}

		this.ReevaluateSystem();
	}

    private func RefreshAddictionStatusEffects() -> Void {
        //DFProfile();
		let currentAddictionStageRev2: Int32 = this.GetAddictionStage();
		let currentWithdrawalLevelRev2: Int32 = this.GetWithdrawalLevel();
        let hasEuphoria: Bool = this.BiocorruptionConditionSystem.GetHasEuphoria();
		let validGameState: Bool = this.GameStateService.IsValidGameState(this);

		StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetWithdrawalStatusEffectTag());

		if !validGameState {
			return;
		}

        if this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() == 0.0 {
            let baseID: TweakDBID = this.GetAddictionStatusEffectBaseID();
            let indexToken: TweakDBID = t"";
            let progressionToken: TweakDBID = t"";

            switch currentWithdrawalLevelRev2 {
                case 5:
                    indexToken = t"Cessation";
                    break;
                case 4:
                    indexToken = t"04";
                    break;
                case 3:
                    indexToken = t"03";
                    break;
                case 2:
                    indexToken = t"02";
                    break;
                case 1:
                    indexToken = t"01";
                    break;
            }

            if currentWithdrawalLevelRev2 != 5 {
                if currentWithdrawalLevelRev2 == currentAddictionStageRev2 {
                    progressionToken = t"_NoProgression";
                } else if currentWithdrawalLevelRev2 < currentAddictionStageRev2 {
                    progressionToken = t"_WithProgression";
                }
            }

            if currentWithdrawalLevelRev2 > 0 && !hasEuphoria {
                StatusEffectHelper.ApplyStatusEffect(this.player, baseID + indexToken + progressionToken);
            }
        }
        
        if currentWithdrawalLevelRev2 == 0 &&
            this.lastWithdrawalLevel > 0 && 
            this.PlayerStateService.GetManagedEffectTotalStacksByType(this.GetAddictionManagedEffectType()) == 0u &&
            this.GetRemainingWithdrawalDurationInGameTimeSeconds() == 0.0 &&
            this.GetRemainingBackoffDurationInGameTimeSeconds() == 0.0 {
                this.CureAddiction();
                this.DoPostAddictionCureActions();
        }
	}

    private final func QueueAddictionNotification(stage: Int32) -> Void {
        //DFProfile();
		let messageKey: CName;
		let messageType: SimpleMessageType;
		switch stage {
			case 4:
				messageKey = this.GetAddictionNotificationMessageKeyStage4();
				messageType = SimpleMessageType.Negative;
				break;
			case 3:
				messageKey = this.GetAddictionNotificationMessageKeyStage3();
				messageType = SimpleMessageType.Negative;
				break;
			case 2:
				messageKey = this.GetAddictionNotificationMessageKeyStage2();
				messageType = SimpleMessageType.Negative;
				break;
			case 1:
				messageKey = this.GetAddictionNotificationMessageKeyStage1();
				messageType = SimpleMessageType.Negative;
				break;
			case 0:
				messageKey = this.GetAddictionNotificationMessageKeyCured();
				messageType = SimpleMessageType.Neutral;
				break;
		}

		let message: DFMessage;
		message.key = messageKey;
		message.type = messageType;
		message.context = this.GetAddictionNotificationMessageContext();

		let notification: DFNotification;
		notification.message = message;
		notification.allowPlaybackInCombat = false;

		if this.Settings.addictionMessagesEnabled || Equals(message.type, SimpleMessageType.Neutral) {
			this.NotificationService.QueueNotification(notification);
		}
    }

    public final func StartBackoffDuration() -> Void {
        //DFProfile();
		DFLog(this, "StartBackoffDuration");
		let currentAddictionStageRev2: Int32 = this.GetAddictionStage();
		if currentAddictionStageRev2 > 0 {
            let backoffDurations: array<Float> = this.GetAddictionBackoffDurationsInGameTimeSecondsByStage();
			this.SetRemainingBackoffDurationInGameTimeSeconds(backoffDurations[currentAddictionStageRev2]);
		}
	}

    public final func CureAddiction() {
        //DFProfile();
        this.SetAddictionStage(0);
        this.SetWithdrawalLevel(0);
        this.SetAddictionAmount(0.0);

		// If this was called outside of the normal flow, we should clean up any backoff or withdrawal effects still ongoing.
        let withdrawalStatusEffectTag: CName = this.GetWithdrawalStatusEffectTag();
		if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, withdrawalStatusEffectTag) {
			StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, withdrawalStatusEffectTag);
		}
        this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
        this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);

		this.QueueAddictionNotification(this.GetAddictionStage());
	}

    //
    //  Addiction Withdrawal FX and Animation
    //
    public func GetHasEverPlayedTier1WithdrawalAnim() -> Bool {
        //DFProfile();
        return this.hasEverPlayedTier1WithdrawalAnimRev2;
    }

    public func SetHasEverPlayedTier1WithdrawalAnim(hasEverPlayed: Bool) -> Void {
        //DFProfile();
        this.hasEverPlayedTier1WithdrawalAnimRev2 = hasEverPlayed;
    }

    public func GetHasEverPlayedTier2WithdrawalAnim() -> Bool {
        //DFProfile();
        return this.hasEverPlayedTier2WithdrawalAnimRev2;
    }

    public func SetHasEverPlayedTier2WithdrawalAnim(hasEverPlayed: Bool) -> Void {
        //DFProfile();
        this.hasEverPlayedTier2WithdrawalAnimRev2 = hasEverPlayed;
    }

    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
		// Used by DFAlcoholAddictionSystem
	}

    //
    //  Therapy Texts
    //
    private final func OnSetTherapyAddictionStateIndexFactChanged(value: Int32) -> Void {
        if Equals(value, 1) {
            this.SetTherapyAddictionStateIndexForMessage();
            this.QuestsSystem.SetFact(this.GetSetTherapyAddictionStateIndexFactAction(), 0);
        }
    }

    public final func SetTherapyAddictionStateIndexForMessage() -> Void {
        //DFProfile();
		if !IsSystemEnabledAndRunning(this) {
			this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), -1);
            return;
		}

		let stage: Int32 = this.GetAddictionStage();
        if stage == 5 || (stage >= 1 && this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() > 0.0) {
            this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 5);
        } else if stage >= 3 {
			this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 4);
		} else if stage >= 1 {
			this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 3);
		} else if this.GetAddictionAmount() > 0.0 {
			this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 2);
		} else {
			if this.hasEverBeenAddicted {
				this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 1);
			} else {
				this.QuestsSystem.SetFact(this.GetAddictionTherapyResponseIndexFact(), 0);
			}
		}
    }

    //
    //  Events for Dark Future Add-Ons and Mods
    //
    public final func DispatchAddictionValueChangedEvent(eventType: DFAddictionEventType, amountChange: Float, newAmount: Float, stageChange: Int32, newStage: Int32) -> Void {
		//DFProfile();
		let data = DFAddictionValueChangedEventDatum(this.GetAddictionType(), eventType, amountChange, newAmount, stageChange, newStage);
        GameInstance.GetCallbackSystem().DispatchEvent(DFAddictionValueChangedEvent.Create(data));
    }
}
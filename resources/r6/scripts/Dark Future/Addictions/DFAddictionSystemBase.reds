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
    PlayerStateServiceAddictionPrimaryEffectAppliedEvent,
    PlayerStateServiceAddictionPrimaryEffectRemovedEvent,
    DFNotificationService,
    DFCyberwareService,
    DFMessageContext,
    DFMessage,
    DFNotification
}
import DarkFuture.Needs.DFNerveSystem

public abstract class DFAddictionSystemEventListener extends DFSystemEventListener {
    //
	// Required Overrides
	//
    private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
        //DFProfile();
		DFLogNoSystem(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceSceneTierChangedEvent", this, n"OnGameStateServiceSceneTierChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceFuryChangedEvent", this, n"OnGameStateServiceFuryChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceCyberspaceChangedEvent", this, n"OnGameStateServiceCyberspaceChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent", this, n"OnPlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent", this, n"OnPlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent", this, n"OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceAddictionPrimaryEffectAppliedEvent", this, n"OnPlayerStateServiceAddictionPrimaryEffectAppliedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceAddictionPrimaryEffectRemovedEvent", this, n"OnPlayerStateServiceAddictionPrimaryEffectRemovedEvent", true);
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

    private cb func OnPlayerStateServiceAddictionPrimaryEffectAppliedEvent(event: ref<PlayerStateServiceAddictionPrimaryEffectAppliedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionPrimaryEffectApplied(event.GetEffectID(), event.GetEffectGameplayTags());
    }

    private cb func OnPlayerStateServiceAddictionPrimaryEffectRemovedEvent(event: ref<PlayerStateServiceAddictionPrimaryEffectRemovedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionPrimaryEffectRemoved(event.GetEffectID(), event.GetEffectGameplayTags());
    }
}

public abstract class DFAddictionSystemBase extends DFSystem {
    private persistent let currentAddictionAmount: Float = 0.0;
    private persistent let currentAddictionStage: Int32 = 0;
    private persistent let currentWithdrawalLevel: Int32 = 0;
    public persistent let remainingWithdrawalDurationInGameTimeSeconds: Float = 0.0;
    public persistent let remainingBackoffDurationInGameTimeSeconds: Float = 0.0;
    private persistent let hasEverPlayedTier1WithdrawalAnim: Bool = false;
    private persistent let hasEverPlayedTier2WithdrawalAnim: Bool = false;

    public persistent let hasEverBeenAddicted: Bool = false;
    private let therapySetAddictionStateIndexFactListener: Uint32;
    
    private let lastWithdrawalLevel: Int32 = 0;

    private let TransactionSystem: ref<TransactionSystem>;
    public let QuestsSystem: ref<QuestsSystem>;
    private let MainSystem: ref<DFMainSystem>;
    public let GameStateService: ref<DFGameStateService>;
    private let PlayerStateService: ref<DFPlayerStateService>;
    public let NotificationService: ref<DFNotificationService>;
    public let CyberwareService: ref<DFCyberwareService>;
    public let NerveSystem: ref<DFNerveSystem>;

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    private func RegisterListeners() -> Void {
        this.therapySetAddictionStateIndexFactListener = this.QuestsSystem.RegisterListener(this.GetSetTherapyAddictionStateIndexFactAction(), this, n"OnSetTherapyAddictionStateIndexFactChanged");
    }

	private func UnregisterListeners() -> Void {
        this.QuestsSystem.UnregisterListener(this.GetSetTherapyAddictionStateIndexFactAction(), this.therapySetAddictionStateIndexFactListener);
        this.therapySetAddictionStateIndexFactListener = 0u;
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
	public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
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
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.currentAddictionAmount = 0.0;
        this.currentAddictionStage = 0;
        this.currentWithdrawalLevel = 0;
        this.remainingWithdrawalDurationInGameTimeSeconds = 0.0;
        this.remainingBackoffDurationInGameTimeSeconds = 0.0;
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
			this.ReduceAddictionFromTime(gameTimeSecondsToReduce);
            this.ReduceWithdrawalDuration(gameTimeSecondsToReduce);
            this.ReduceBackoffDuration(gameTimeSecondsToReduce);
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
		DFLog(this, "AddictionTreatmentDurationUpdateFromTimeSkipFinished");

        let updateDatum: DFAddictionUpdateDatum = this.GetSpecificAddictionUpdateData(addictionData);
        this.SetAddictionAmount(updateDatum.addictionAmount);
        this.SetAddictionStage(updateDatum.addictionStage);
        this.SetWithdrawalLevel(updateDatum.withdrawalLevel);
        this.SetRemainingBackoffDurationInGameTimeSeconds(updateDatum.remainingBackoffDuration);
        this.SetRemainingWithdrawalDurationInGameTimeSeconds(updateDatum.remainingWithdrawalDuration);

        this.ReevaluateSystem();
	}

    public func GetAddictionAmount() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentAddictionAmount;
    }

    public func SetAddictionAmount(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.currentAddictionAmount = MaxF(value, 0.0);
    }

    public func ModAddictionAmount(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.currentAddictionAmount += value;
        this.currentAddictionAmount = MaxF(this.currentAddictionAmount, 0.0);
        
        return this.currentAddictionAmount;
    }

    public func GetAddictionStage() -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentAddictionStage;
    }

    public func SetAddictionStage(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.currentAddictionStage = Clamp(value, 0, 4);

        if this.currentAddictionStage > 0 {
            this.hasEverBeenAddicted = true;
        }
    }

    public func ModAddictionStage(value: Int32) -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        this.currentAddictionStage += value;
        this.currentAddictionStage = Clamp(this.currentAddictionStage, 0, 4);

        if this.currentAddictionStage > 0 {
            this.hasEverBeenAddicted = true;
        }

        return this.currentAddictionStage;
    }

    public func GetWithdrawalLevel() -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.currentWithdrawalLevel;
    }

    public func SetWithdrawalLevel(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevel;
        this.currentWithdrawalLevel = Clamp(value, 0, 5);
        this.NerveSystem.ForceNeedMaxValueUpdate();
    }

    public func ModWithdrawalLevel(value: Int32) -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevel;
        this.currentWithdrawalLevel += value;
        this.currentWithdrawalLevel = Clamp(this.currentWithdrawalLevel, 0, 5);
        this.NerveSystem.ForceNeedMaxValueUpdate();

        return this.currentWithdrawalLevel;
    }

    public func GetRemainingWithdrawalDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        return this.remainingWithdrawalDurationInGameTimeSeconds;
    }

    public func SetRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.remainingWithdrawalDurationInGameTimeSeconds = MaxF(value, 0.0);
    }

    public func ModRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.remainingWithdrawalDurationInGameTimeSeconds += value;
        this.remainingWithdrawalDurationInGameTimeSeconds = MaxF(this.remainingWithdrawalDurationInGameTimeSeconds, 0.0);

        return this.remainingWithdrawalDurationInGameTimeSeconds;
    }

    public func GetRemainingBackoffDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0; }

        return this.remainingBackoffDurationInGameTimeSeconds;
    }

    public func SetRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.remainingBackoffDurationInGameTimeSeconds = MaxF(value, 0.0);
    }

    public func ModRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        this.remainingBackoffDurationInGameTimeSeconds += value;
        this.remainingBackoffDurationInGameTimeSeconds = MaxF(this.remainingBackoffDurationInGameTimeSeconds, 0.0);

        return this.remainingBackoffDurationInGameTimeSeconds;
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

    public func GetDefaultEffectDuration() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetDefaultEffectDuration");
        return 0.0;
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

	private func GetAddictionAmountOnUse() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionAmountOnUse");
        return 0.0;
    }

	private func GetAddictionStageAdvanceAmounts() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionStageAdvanceAmounts");
        return [];
    }

	public func GetAddictionNerveLimits() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionNerveLimits");
        return [];
    }

	public func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionBackoffDurationsInRealTimeMinutesByStage");
        return [];
    }

	public func GetAddictionAmountLossPerDay() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionAmountLossPerDay");
        return 0.0;
    }

	public func GetAddictionMinStacksPerStage() -> array<Uint32> {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionMinStacksPerStage");
        return [];
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

    public func GetAddictionPrimaryStatusEffectTag() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetAddictionPrimaryStatusEffectTag");
        return n"";
    }

    public func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("AddictionPrimaryEffectApplied");
    }

    public func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("AddictionPrimaryEffectRemoved");
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

    private func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetSetTherapyAddictionStateIndexFactAction");
		return n"";
    }

    //
    //  System Methods
    //
    private func ReevaluateSystem() -> Void {
        //DFProfile();
		this.RefreshAddictionStatusEffects();
	}

    private final func ReduceAddictionFromTime(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		let minutesPerUpdate: Float = gameTimeSecondsToReduce / 60.0;
		let updatesPerDay: Float = (60.0 / minutesPerUpdate) * 24.0;
		
		let addictionAmountLossPerUpdate = this.GetAddictionAmountLossPerDay() / updatesPerDay;
        this.ModAddictionAmount(-addictionAmountLossPerUpdate);

		DFLog(this, "ReduceAddictionFromTime currentAddictionAmount = " + ToString(this.currentAddictionAmount));
	}

	private final func ReduceWithdrawalDuration(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		if this.GetRemainingWithdrawalDurationInGameTimeSeconds() > 0.0 {
            let remainingDuration: Float = this.ModRemainingWithdrawalDurationInGameTimeSeconds(-gameTimeSecondsToReduce);
			
			DFLog(this, "remainingWithdrawalDurationInGameTimeSeconds = " + ToString(remainingDuration));

            if remainingDuration == 0.0 {
                this.AdvanceWithdrawal();
            } 
		}
	}

	private final func ReduceBackoffDuration(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
		if this.GetRemainingBackoffDurationInGameTimeSeconds() > 0.0 {
			let remainingDuration: Float = this.ModRemainingBackoffDurationInGameTimeSeconds(-gameTimeSecondsToReduce);

			DFLog(this, "remainingBackoffDurationInGameTimeSeconds = " + ToString(remainingDuration));

			if remainingDuration == 0.0 {
				this.AdvanceWithdrawal();
			}
		}
	}

    public final func TryToAdvanceAddiction(addictionAmountOnUse: Float) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        
        let currentAddictionStage = this.GetAddictionStage();
		if currentAddictionStage < this.GetAddictionMaxStage() {
			// Roll to check for addiction advancement.
			let progressionAttempt: Float = RandRangeF(0.0, 100.0);
			DFLog(this, "TryToAdvanceAddiction progressionAttempt = " + ToString(progressionAttempt));

			if progressionAttempt <= this.GetAddictionProgressionChance() {
				let currentAddictionAmount: Float = this.ModAddictionAmount(addictionAmountOnUse);

				DFLog(this, "TryToAdvanceAddiction Advancing addiction! Addiction amount now: " + ToString(currentAddictionAmount));
				let addictionStageAdvanceAmounts: array<Float> = this.GetAddictionStageAdvanceAmounts();
                if currentAddictionAmount >= addictionStageAdvanceAmounts[currentAddictionStage] {
					this.SetAddictionAmount(0.0);
					currentAddictionStage = this.ModAddictionStage(1);
                    this.DoPostAddictionAdvanceActions();
                    this.QueueAddictionNotification(currentAddictionStage);

                    // Tutorial
                    if this.Settings.tutorialsEnabled && !this.PlayerStateService.hasShownAddictionTutorial {
                        this.PlayerStateService.hasShownAddictionTutorial = true;

                        let tutorial: DFTutorial;
                        tutorial.title = GetLocalizedTextByKey(n"DarkFutureTutorialAddictionTitle");
                        tutorial.message = GetLocalizedTextByKey(n"DarkFutureTutorialAddiction");
                        tutorial.iconID = t"";
                        this.NotificationService.QueueTutorial(tutorial);
                    }

					DFLog(this, "TryToAdvanceAddiction Player addiction has advanced to stage " + ToString(currentAddictionStage) + "!");
				}
			}
		} else {
			DFLog(this, "TryToAdvanceAddiction Player already at max addiction stage.");
		}
	}

    private final func AdvanceWithdrawal() -> Void {
        //DFProfile();
		DFLog(this, "AdvanceWithdrawal");

        let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
		if withdrawalLevel < this.currentAddictionStage {
			withdrawalLevel = this.ModWithdrawalLevel(1);
		} else if withdrawalLevel == this.currentAddictionStage {
            // Jump to Cessation
			this.SetWithdrawalLevel(5);
            withdrawalLevel = 5;
		} else if withdrawalLevel == 5 {
			this.SetWithdrawalLevel(0);
            withdrawalLevel = 0;
		}

		if withdrawalLevel > 0 {
            if withdrawalLevel < this.GetAddictionStage() {
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(HoursToGameTimeSeconds(1));
            } else {
                let durations: array<Float> = this.GetAddictionWithdrawalDurationsInGameTimeSeconds();
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(durations[withdrawalLevel]);
            }
			
            // Notification SFX
            this.PlayWithdrawalAdvanceSFX();
		}

		this.ReevaluateSystem();
	}

    private final func RefreshAddictionStatusEffects() -> Void {
        //DFProfile();
		let currentAddictionStage: Int32 = this.GetAddictionStage();
		let currentWithdrawalLevel: Int32 = this.GetWithdrawalLevel();
		let validGameState: Bool = this.GameStateService.IsValidGameState(this);

		StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetWithdrawalStatusEffectTag());

		if !validGameState {
			return;
		}

        if this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() == 0.0 {
            let baseID: TweakDBID = this.GetAddictionStatusEffectBaseID();
            let indexToken: TweakDBID = t"";
            let progressionToken: TweakDBID = t"";

            switch currentWithdrawalLevel {
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

            if currentWithdrawalLevel != 5 {
                if currentWithdrawalLevel == currentAddictionStage {
                    progressionToken = t"_NoProgression";
                } else if currentWithdrawalLevel < currentAddictionStage {
                    progressionToken = t"_WithProgression";
                }
            }

            if currentWithdrawalLevel > 0 {
                StatusEffectHelper.ApplyStatusEffect(this.player, baseID + indexToken + progressionToken);
            }
        }
        
        if currentWithdrawalLevel == 0 &&
            this.lastWithdrawalLevel > 0 && 
            !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, this.GetAddictionPrimaryStatusEffectTag()) &&
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
		let currentAddictionStage: Int32 = this.GetAddictionStage();
		if currentAddictionStage > 0 {
            let backoffDurations: array<Float> = this.GetAddictionBackoffDurationsInRealTimeMinutesByStage();
			this.SetRemainingBackoffDurationInGameTimeSeconds((backoffDurations[currentAddictionStage] * this.Settings.timescale) * 60.0);
		}
	}

    private final func CureAddiction() {
        //DFProfile();
        this.SetAddictionStage(0);
        this.SetWithdrawalLevel(0);
        this.SetAddictionAmount(0.0);

		// If this was called by some sort of item, we should clean up any backoff or withdrawal effects still ongoing.
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
        return this.hasEverPlayedTier1WithdrawalAnim;
    }

    public func SetHasEverPlayedTier1WithdrawalAnim(hasEverPlayed: Bool) -> Void {
        //DFProfile();
        this.hasEverPlayedTier1WithdrawalAnim = hasEverPlayed;
    }

    public func GetHasEverPlayedTier2WithdrawalAnim() -> Bool {
        //DFProfile();
        return this.hasEverPlayedTier2WithdrawalAnim;
    }

    public func SetHasEverPlayedTier2WithdrawalAnim(hasEverPlayed: Bool) -> Void {
        //DFProfile();
        this.hasEverPlayedTier2WithdrawalAnim = hasEverPlayed;
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
}
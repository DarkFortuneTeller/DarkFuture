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
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
    DFMainSystem,
    DFAddictionDatum,
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
    DFNotificationService
}
import DarkFuture.Needs.DFNerveSystem


public abstract class DFAddictionSystemEventListener extends DFSystemEventListener {
    //
	// Required Overrides
	//
    private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	private cb func OnLoad() {
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
		this.GetSystemInstance().OnSceneTierChanged(event.GetData());
	}

	private cb func OnGameStateServiceFuryChangedEvent(event: ref<DFGameStateServiceFuryChangedEvent>) {
		this.GetSystemInstance().OnFuryStateChanged(event.GetData());
	}

    private cb func OnGameStateServiceCyberspaceChangedEvent(event: ref<DFGameStateServiceCyberspaceChangedEvent>) {
        this.GetSystemInstance().OnCyberspaceChanged(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent(event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent>) {
        this.GetSystemInstance().OnUpdate(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent>) {
        this.GetSystemInstance().AddictionTreatmentDurationUpdateFromTimeSkipFinished(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent(event: ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent>) {
        this.GetSystemInstance().OnAddictionTreatmentEffectAppliedOrRemoved();
    }

    private cb func OnPlayerStateServiceAddictionPrimaryEffectAppliedEvent(event: ref<PlayerStateServiceAddictionPrimaryEffectAppliedEvent>) {
        this.GetSystemInstance().OnAddictionPrimaryEffectApplied(event.GetEffectID(), event.GetEffectGameplayTags());
    }

    private cb func OnPlayerStateServiceAddictionPrimaryEffectRemovedEvent(event: ref<PlayerStateServiceAddictionPrimaryEffectRemovedEvent>) {
        this.GetSystemInstance().OnAddictionPrimaryEffectRemoved(event.GetEffectID(), event.GetEffectGameplayTags());
    }
}

public abstract class DFAddictionSystemBase extends DFSystem {
    private persistent let currentAddictionAmount: Float = 0.0;
    private persistent let currentAddictionStage: Int32 = 0;
    private persistent let currentWithdrawalLevel: Int32 = 0;
    private persistent let remainingWithdrawalDurationInGameTimeSeconds: Float = 0.0;
    private persistent let remainingBackoffDurationInGameTimeSeconds: Float = 0.0;
    private let lastWithdrawalLevel: Int32 = 0;

    private let MainSystem: ref<DFMainSystem>;
    private let GameStateService: ref<DFGameStateService>;
    private let PlayerStateService: ref<DFPlayerStateService>;
    private let NotificationService: ref<DFNotificationService>;
    private let NerveSystem: ref<DFNerveSystem>;

    private let updateIntervalInGameTimeSeconds: Float = 300.0;

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterAllDelayCallbacks() -> Void {}
	private func DoStopActions() -> Void {}
    public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
    }

    private func GetSystems() -> Void {
		let gameInstance = GetGameInstance();
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
    }

    private func DoPostSuspendActions() -> Void {
        this.currentAddictionAmount = 0.0;
        this.currentAddictionStage = 0;
        this.currentWithdrawalLevel = 0;
        this.remainingWithdrawalDurationInGameTimeSeconds = 0.0;
        this.remainingBackoffDurationInGameTimeSeconds = 0.0;
        this.lastWithdrawalLevel = 0;

        StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetWithdrawalStatusEffectTag());
    }

    private func DoPostResumeActions() -> Void {
        this.SetupData();
        this.ReevaluateSystem();
    }

    //
	//	RunGuard Protected Methods
	//

    // Addiction Systems don't maintain their own update registrations, and instead tick
    // after the PlayerStateService has updated the Addiction Treatment Duration. This
    // prevents a race condition between updating the Addiction Treatment Duration and
    // all other Addictions.
	public func OnUpdate(gameTimeSecondsToReduce: Float) -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnUpdate");

		if this.GameStateService.IsValidGameState("DFAddictionSystemBase:OnUpdate") {
			this.ReduceAddictionFromTime(gameTimeSecondsToReduce);
            this.ReduceWithdrawalDuration(gameTimeSecondsToReduce);
            this.ReduceBackoffDuration(gameTimeSecondsToReduce);
		}
	}

    public func OnAddictionTreatmentEffectAppliedOrRemoved() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnAddictionTreatmentEffectAppliedOrRemoved");

        this.ReevaluateSystem();
    }

    public func OnSceneTierChanged(value: GameplayTier) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnSceneTierChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func OnFuryStateChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnFuryStateChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func OnCyberspaceChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnCyberspaceChanged value = " + ToString(value));

		this.ReevaluateSystem();
	}

    public func AddictionTreatmentDurationUpdateFromTimeSkipFinished(addictionData: DFAddictionDatum) -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "AddictionTreatmentDurationUpdateFromTimeSkipFinished");

		if this.GameStateService.IsValidGameState("DFAddictionSystemBase:AddictionTreatmentDurationUpdateFromTimeSkipFinished", true) {
            this.OnTimeSkipFinishedActual(addictionData);
            this.ReevaluateSystem();
            if NotEquals(this.lastWithdrawalLevel, this.GetWithdrawalLevel()) {
                this.NerveSystem.UpdateNerveWithdrawalTarget();
                this.PlayWithdrawalAdvanceSFX();
            }
		}
	}

    public func GetAddictionAmount() -> Float {
        if RunGuard(this) { return 0; }

        return this.currentAddictionAmount;
    }

    public func SetAddictionAmount(value: Float) -> Void {
        if RunGuard(this) { return; }

        this.currentAddictionAmount = MaxF(value, 0.0);
    }

    public func ModAddictionAmount(value: Float) -> Float {
        if RunGuard(this) { return 0.0; }

        this.currentAddictionAmount += value;
        this.currentAddictionAmount = MaxF(this.currentAddictionAmount, 0.0);
        
        return this.currentAddictionAmount;
    }

    public func GetAddictionStage() -> Int32 {
        if RunGuard(this) { return 0; }

        return this.currentAddictionStage;
    }

    public func SetAddictionStage(value: Int32) -> Void {
        if RunGuard(this) { return; }

        this.currentAddictionStage = Clamp(value, 0, 4);
    }

    public func ModAddictionStage(value: Int32) -> Int32 {
        if RunGuard(this) { return 0; }

        this.currentAddictionStage += value;
        this.currentAddictionStage = Clamp(this.currentAddictionStage, 0, 4);

        return this.currentAddictionStage;
    }

    public func GetWithdrawalLevel() -> Int32 {
        if RunGuard(this) { return 0; }

        return this.currentWithdrawalLevel;
    }

    public func SetWithdrawalLevel(value: Int32) -> Void {
        if RunGuard(this) { return; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevel;
        this.currentWithdrawalLevel = Clamp(value, 0, 5);
        this.NerveSystem.UpdateNerveWithdrawalTarget();
    }

    public func ModWithdrawalLevel(value: Int32) -> Int32 {
        if RunGuard(this) { return 0; }

        this.lastWithdrawalLevel = this.currentWithdrawalLevel;
        this.currentWithdrawalLevel += value;
        this.currentWithdrawalLevel = Clamp(this.currentWithdrawalLevel, 0, 5);
        this.NerveSystem.UpdateNerveWithdrawalTarget();

        return this.currentWithdrawalLevel;
    }

    public func GetRemainingWithdrawalDurationInGameTimeSeconds() -> Float {
        if RunGuard(this) { return 0.0; }

        return this.remainingWithdrawalDurationInGameTimeSeconds;
    }

    public func SetRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Void {
        if RunGuard(this) { return; }

        this.remainingWithdrawalDurationInGameTimeSeconds = MaxF(value, 0.0);
    }

    public func ModRemainingWithdrawalDurationInGameTimeSeconds(value: Float) -> Float {
        if RunGuard(this) { return 0.0; }

        this.remainingWithdrawalDurationInGameTimeSeconds += value;
        this.remainingWithdrawalDurationInGameTimeSeconds = MaxF(this.remainingWithdrawalDurationInGameTimeSeconds, 0.0);

        return this.remainingWithdrawalDurationInGameTimeSeconds;
    }

    public func GetRemainingBackoffDurationInGameTimeSeconds() -> Float {
        if RunGuard(this) { return 0; }

        return this.remainingBackoffDurationInGameTimeSeconds;
    }

    public func SetRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Void {
        if RunGuard(this) { return; }

        this.remainingBackoffDurationInGameTimeSeconds = MaxF(value, 0.0);
    }

    public func ModRemainingBackoffDurationInGameTimeSeconds(value: Float) -> Float {
        if RunGuard(this) { return 0.0; }

        this.remainingBackoffDurationInGameTimeSeconds += value;
        this.remainingBackoffDurationInGameTimeSeconds = MaxF(this.remainingBackoffDurationInGameTimeSeconds, 0.0);

        return this.remainingBackoffDurationInGameTimeSeconds;
    }

    public func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if RunGuard(this) { return; }

        this.AddictionPrimaryEffectAppliedActual(effectID, effectGameplayTags);
    }

    public func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if RunGuard(this) { return; }

        this.AddictionPrimaryEffectRemovedActual(effectID, effectGameplayTags);
    }

    //
    //  Required Overrides
    //
    private func GetDefaultEffectDuration() -> Float {
        this.LogMissingOverrideError("GetDefaultEffectDuration");
        return 0.0;
    }

    private func OnTimeSkipFinishedActual(addictionData: DFAddictionDatum) -> Void {
        this.LogMissingOverrideError("OnTimeSkipFinishedActual");
    }

	private func GetEffectDuration() -> Float {
        this.LogMissingOverrideError("GetEffectDuration");
        return 0.0;
    }

    public func ResetEffectDuration() -> Void {
        this.LogMissingOverrideError("ResetEffectDuration");
    }

	private func GetAddictionMaxStage() -> Int32 {
        this.LogMissingOverrideError("GetAddictionMaxStage");
        return 0;
    }

	private func GetAddictionProgressionChance() -> Float {
        this.LogMissingOverrideError("GetAddictionProgressionChance");
        return 0.0;
    }

	private func GetAddictionAmountOnUse() -> Float {
        this.LogMissingOverrideError("GetAddictionAmountOnUse");
        return 0.0;
    }

	private func GetAddictionStageAdvanceAmounts() -> array<Float> {
        this.LogMissingOverrideError("GetAddictionStageAdvanceAmounts");
        return [];
    }

	private func GetAddictionNerveTargets() -> array<Float> {
        this.LogMissingOverrideError("GetAddictionNerveTargets");
        return [];
    }

	private func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
        this.LogMissingOverrideError("GetAddictionBackoffDurationsInRealTimeMinutesByStage");
        return [];
    }

	private func GetAddictionAmountLossPerDay() -> Float {
        this.LogMissingOverrideError("GetAddictionAmountLossPerDay");
        return 0.0;
    }

	private func GetAddictionMinStacksPerStage() -> array<Uint32> {
        this.LogMissingOverrideError("GetAddictionMinStacksPerStage");
        return [];
    }

	private func GetAddictionMildWithdrawalDurationInGameTimeSeconds() -> Float {
        this.LogMissingOverrideError("GetAddictionMildWithdrawalDurationInGameTimeSeconds");
        return 0.0;
    }

	private func GetAddictionSevereWithdrawalDurationInGameTimeSeconds() -> Float {
        this.LogMissingOverrideError("GetAddictionSevereWithdrawalDurationInGameTimeSeconds");
        return 0.0;
    }

    private func DoPostAddictionCureActions() -> Void {
        this.LogMissingOverrideError("DoPostAddictionCureActions");
    }

    private func DoPostAddictionAdvanceActions() -> Void {
        this.LogMissingOverrideError("DoPostAddictionAdvanceActions");
    }

    private func PlayWithdrawalAdvanceSFX() -> Void {
        this.LogMissingOverrideError("PlayWithdrawalAdvanceSFX");
    }

    private func GetWithdrawalStatusEffectTag() -> CName {
        this.LogMissingOverrideError("GetWithdrawalStatusEffectTag");
        return n"";
    }

    private func GetAddictionStatusEffectBaseID() -> TweakDBID {
        this.LogMissingOverrideError("GetAddictionStatusEffectBaseID");
        return t"";
    }

    private func GetAddictionPrimaryStatusEffectTag() -> CName {
        this.LogMissingOverrideError("GetAddictionPrimaryStatusEffectTag");
        return n"";
    }

    private func QueueAddictionNotification(stage: Int32) -> Void {
		this.LogMissingOverrideError("QueueAddictionNotification");
    }

    private func AddictionPrimaryEffectAppliedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        this.LogMissingOverrideError("AddictionPrimaryEffectAppliedActual");
    }

    private func AddictionPrimaryEffectRemovedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        this.LogMissingOverrideError("AddictionPrimaryEffectRemovedActual");
    }

    private func GetTutorialTitleKey() -> CName {
		this.LogMissingOverrideError("GetTutorialTitleKey");
		return n"";
	}

	private func GetTutorialMessageKey() -> CName {
		this.LogMissingOverrideError("GetTutorialMessageKey");
		return n"";
	}

    //
    //  System Methods
    //
    private func ReevaluateSystem() -> Void {
		this.RefreshAddictionStatusEffects();
	}

    private final func ReduceAddictionFromTime(gameTimeSecondsToReduce: Float) -> Void {
		let minutesPerUpdate: Float = gameTimeSecondsToReduce / 60.0;
		let updatesPerDay: Float = (60.0 / minutesPerUpdate) * 24.0;
		
		let addictionAmountLossPerUpdate = this.GetAddictionAmountLossPerDay() / updatesPerDay;
        this.ModAddictionAmount(-addictionAmountLossPerUpdate);

		DFLog(this.debugEnabled, this, "ReduceAddictionFromTime currentAddictionAmount = " + ToString(this.currentAddictionAmount));
	}

	private final func ReduceWithdrawalDuration(gameTimeSecondsToReduce: Float) -> Void {
		if this.GetRemainingWithdrawalDurationInGameTimeSeconds() > 0.0 {
            let remainingDuration: Float = this.ModRemainingWithdrawalDurationInGameTimeSeconds(-gameTimeSecondsToReduce);
			
			DFLog(this.debugEnabled, this, "remainingWithdrawalDurationInGameTimeSeconds = " + ToString(remainingDuration));

            if remainingDuration == 0.0 {
                this.AdvanceWithdrawal();
            } 
		}
	}

	private final func ReduceBackoffDuration(gameTimeSecondsToReduce: Float) -> Void {
		if this.GetRemainingBackoffDurationInGameTimeSeconds() > 0.0 {
			let remainingDuration: Float = this.ModRemainingBackoffDurationInGameTimeSeconds(-gameTimeSecondsToReduce);

			DFLog(this.debugEnabled, this, "remainingBackoffDurationInGameTimeSeconds = " + ToString(remainingDuration));

			if remainingDuration == 0.0 {
				this.AdvanceWithdrawal();
			}
		}
	}

    private final func TryToAdvanceAddiction(addictionAmountOnUse: Float) -> Void {
        if RunGuard(this) { return; }
        
        let currentAddictionStage = this.GetAddictionStage();
		if currentAddictionStage < this.GetAddictionMaxStage() {
			// Roll to check for addiction advancement.
			let progressionAttempt: Float = RandRangeF(0.0, 100.0);
			DFLog(this.debugEnabled, this, "TryToAdvanceAddiction progressionAttempt = " + ToString(progressionAttempt));

			if progressionAttempt <= this.GetAddictionProgressionChance() {
				let currentAddictionAmount: Float = this.ModAddictionAmount(addictionAmountOnUse);

				DFLog(this.debugEnabled, this, "TryToAdvanceAddiction Advancing addiction! Addiction amount now: " + ToString(currentAddictionAmount));
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
                        this.NotificationService.QueueTutorial(tutorial);
                    }

					DFLog(this.debugEnabled, this, "TryToAdvanceAddiction Player addiction has advanced to stage " + ToString(currentAddictionStage) + "!");
				}
			}
		} else {
			DFLog(this.debugEnabled, this, "TryToAdvanceAddiction Player already at max addiction stage.");
		}
	}

    private final func AdvanceWithdrawal() -> Void {
		DFLog(this.debugEnabled, this, "AdvanceWithdrawal");

        let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
		if withdrawalLevel < this.currentAddictionStage {
			withdrawalLevel = this.ModWithdrawalLevel(1);
		} else if withdrawalLevel == this.currentAddictionStage {
            // Jump to Cessation
			this.SetWithdrawalLevel(5);
            withdrawalLevel = 5;
		} else if withdrawalLevel == 5 {
			this.SetWithdrawalLevel(0);
		}

		if withdrawalLevel > 0 {
			if withdrawalLevel <= 2 {
                this.SetRemainingWithdrawalDurationInGameTimeSeconds(this.GetAddictionMildWithdrawalDurationInGameTimeSeconds());
			} else {
				this.SetRemainingWithdrawalDurationInGameTimeSeconds(this.GetAddictionSevereWithdrawalDurationInGameTimeSeconds());
			}

            // Notification SFX
            this.PlayWithdrawalAdvanceSFX();
		}

		this.ReevaluateSystem();
	}

    private final func RefreshAddictionStatusEffects() -> Void {
		let currentAddictionStage: Int32 = this.GetAddictionStage();
		let currentWithdrawalLevel: Int32 = this.GetWithdrawalLevel();
		let validGameState: Bool = this.GameStateService.IsValidGameState("RefreshAddictionStatusEffects");

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

    private final func StartBackoffDuration() -> Void {
		DFLog(this.debugEnabled, this, "StartBackoffDuration");
		let currentAddictionStage: Int32 = this.GetAddictionStage();
		if currentAddictionStage > 0 {
            let backoffDurations: array<Float> = this.GetAddictionBackoffDurationsInRealTimeMinutesByStage();
			this.SetRemainingBackoffDurationInGameTimeSeconds((backoffDurations[currentAddictionStage] * this.Settings.timescale) * 60.0);
		}
	}

    private final func CureAddiction() {
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
	//	Logging
	//
	private final func LogMissingOverrideError(funcName: String) -> Void {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}
}
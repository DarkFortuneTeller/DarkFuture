// -----------------------------------------------------------------------------
// DFEnergySystem
// -----------------------------------------------------------------------------
//
// - Energy Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
	DFNeedsDatum, 
	DFTimeSkipData
}
import DarkFuture.Services.{
	DFGameStateService,
	DFNotificationService,
	DFAudioCue,
	DFVisualEffect,
	DFUIDisplay,
	DFNotification,
	DFNotificationCallback
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.DFSettings

class DFEnergySystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFEnergySystem.Get();
	}
}

public final class DFEnergySystem extends DFNeedSystemBase {
	private persistent let currentStimulantToleranceStacks: Uint32 = 0u;

	private let NerveSystem: ref<DFNerveSystem>;

	private let energyRecoverLimitPerNerveStage: array<Float>;
    private let energyRecoverAmountSleeping: Float = 0.4667;
	private let energyLimitAddictionTreatment: Float = 50.0;

    private let stimulantEffectMaxStackCount: Uint32 = 3u;

    //
	//	System Methods
	//
	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFEnergySystem> {
		let instance: ref<DFEnergySystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Needs.DFEnergySystem") as DFEnergySystem;
		return instance;
	}

	public final static func Get() -> ref<DFEnergySystem> {
		return DFEnergySystem.GetInstance(GetGameInstance());
	}

    //
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}
	
	private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	private func GetSystems() -> Void {
		super.GetSystems();
		this.NerveSystem = DFNerveSystem.Get();
	}

	private func SetupData() -> Void {
		this.needStageThresholdDeficits = [15.0, 25.0, 50.0, 75.0, 100.0];
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.EnergyPenalty_01",
			t"DarkFutureStatusEffect.EnergyPenalty_02",
			t"DarkFutureStatusEffect.EnergyPenalty_03",
			t"DarkFutureStatusEffect.EnergyPenalty_04"
		];
		this.energyRecoverLimitPerNerveStage = [100.0, 100.0, 100.0, 50.0, 0.0, 0.0];
	}

	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.ClearStimulantTolerance();
	}

    //
	//	Overrides
	//
	private func ReevaluateSystem() -> Void {
		super.ReevaluateSystem();
		this.RefreshStimulantToleranceEffect();
	}

	private final func OnUpdateActual() -> Void {
		this.ChangeNeedValue(this.GetEnergyChange());
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.energy.value - this.GetNeedValue());
		
		if data.wasSleeping {
			this.ClearStimulantTolerance();
		}
	}

	private final func OnItemConsumedActual(itemData: wref<gameItemData>) {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemData);

		if consumableNeedsData.energy.value != 0.0 {
			this.ChangeEnergyFromItems(this.GetClampedNeedChangeFromData(consumableNeedsData.energy), consumableNeedsData.energy.value);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Energy;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this.debugEnabled, this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;

		if stage >= 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_breath_heavy", 10);
			}

			if this.Settings.energyNeedVFXEnabled {
				notification.vfx = new DFVisualEffect(n"waking_up", null);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Energy, true, false);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_exhale_02", 20);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Energy, false, true);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		return n"DarkFutureEnergyNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		return n"DarkFutureNeedEnergy";
	}

	public final func CheckIfBonusEffectsValid() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState("CheckIfBonusEffectsValid", true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"HousingStatusEffect.Rested") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"HousingStatusEffect.Rested");
				}
			}
		}
	}

	private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialEnergyTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialEnergy";
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeEnergyFromItems(energyAmount: Float, opt unclampedEnergyAmount: Float, opt contextuallyDelayed: Bool) -> Void {
		if RunGuard(this) { return; }

		// The Stimulant Tolerance effect prevents consumables from restoring Energy forever without sleeping.
		let shouldUpdateEnergy: Bool = false;
		let useStimulantTolerance: Bool = false;

		if energyAmount < 0.0 {
			shouldUpdateEnergy = true;
		} else if unclampedEnergyAmount > 0.0 && this.currentStimulantToleranceStacks < this.stimulantEffectMaxStackCount {
			shouldUpdateEnergy = true;
			useStimulantTolerance = true;
		}

		if shouldUpdateEnergy {
			if contextuallyDelayed {
				this.QueueContextuallyDelayedNeedValueChange(energyAmount, true);
			} else {
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = true;
				uiFlags.forceBright = true;
				this.ChangeNeedValue(energyAmount, uiFlags);
			}
		}

		if useStimulantTolerance {
			this.currentStimulantToleranceStacks += 1u;
			let stimulantStackCount: Uint32 = StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.StimulantEffect").GetStackCount();
			if this.currentStimulantToleranceStacks == stimulantStackCount + 1u {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");
			} else {
				// The Stimulant Tolerance Stack counter and the stack count have diverged; refresh the status effect
				// in order to bring the player-facing status effect in line with reality.
				this.RefreshStimulantToleranceEffect();
			}
		}
	}

    //
    //  System-Specific Methods
    //
    private final func GetEnergyChange() -> Float {
        // Subtract 100 points every 36 in-game hours (4.5 hours of gameplay)
		// The player will feel the first effects of this need after 7.2 in-game hours (54 minutes of gameplay)

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		return (100.0 / ((36.0 * 60.0) / 5.0) * -1.0) * (this.Settings.energyLossRatePct / 100.0);
	}

	private final func GetEnergyChangeWithRecoverLimit(energyValue: Float, nerveValue: Float, isSleeping: Bool) -> Float {
		let amountToChange: Float;

		if isSleeping {
			let nerveStage: Int32 = this.NerveSystem.GetNeedStageAtValue(nerveValue);
			let recoverLimit: Float = this.energyRecoverLimitPerNerveStage[nerveStage];
			

			if energyValue > recoverLimit {
				amountToChange = this.GetEnergyChange();
				if energyValue + amountToChange < recoverLimit {
					amountToChange = energyValue - recoverLimit;
				}

			} else {
				amountToChange = this.energyRecoverAmountSleeping;
				if energyValue + amountToChange > recoverLimit {
					amountToChange = recoverLimit - energyValue;
				}
			}
		
		} else {
			amountToChange = this.GetEnergyChange();
		}

		return amountToChange;
	}

	private final func RefreshStimulantToleranceEffect() -> Void {
		let validGameState: Bool = this.GameStateService.IsValidGameState("RefreshStimulantToleranceEffect");
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");

		if validGameState && this.currentStimulantToleranceStacks > 0u {
			let i = 0u;
			while i < this.currentStimulantToleranceStacks {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");
				i += 1u;
			}
		}
	}

	private final func ClearStimulantTolerance() -> Void {
		this.currentStimulantToleranceStacks = 0u;
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");
	}
}

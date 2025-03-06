// -----------------------------------------------------------------------------
// DFEnergySystem
// -----------------------------------------------------------------------------
//
// - Energy Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.{
	RunGuard,
	IsSleeping
}
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFTimeSkipData,
	DFTimeSkipType
}
import DarkFuture.Services.{
	DFGameStateService,
	DFNotificationService,
	DFPlayerStateService,
	DFAudioCue,
	DFVisualEffect,
	DFUIDisplay,
	DFNotification,
	DFNotificationCallback
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.{
	DFSettings,
	DFSleepQualitySetting
}

class DFEnergySystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFEnergySystem.Get();
	}
}

public final class DFEnergySystem extends DFNeedSystemBase {
	private persistent let stimulantStacks: Uint32 = 0u;

	private let NerveSystem: ref<DFNerveSystem>;

    private let energyRecoverAmountSleeping: Float = 0.4667;
	private let stimulantMaxStacks: Uint32 = 4u;
	private let stimulantEnergyRestoreMultPerStack: Float = 0.25;

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
	}

	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.ClearStimulant();
	}

	private func DoPostResumeActions() -> Void {
		super.DoPostResumeActions();
		this.RefreshStimulantEffect();
	}

    //
	//	Overrides
	//
	private final func OnUpdateActual() -> Void {
		this.ChangeNeedValue(this.GetEnergyChange());
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.energy.value - this.GetNeedValue());

		// If Energy is fully replenished, and the time skip reason is sleeping, clear stimulant.
		if data.targetNeedValues.energy.value > 99.0 && 
		   (Equals(data.timeSkipType, DFTimeSkipType.FullSleep) || (Equals(data.timeSkipType, DFTimeSkipType.LimitedSleep))) {
			
			this.ClearStimulant();
		}
	}

	public final func PerformQuestSleep() -> Void {
		this.QueueContextuallyDelayedNeedValueChange(100.0);
		this.ClearStimulant();
	}

	private final func OnItemConsumedActual(itemRecord: wref<ConsumableItem_Record>) -> Void {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.energy.value != 0.0 {
			this.ChangeEnergyFromItems(this.GetClampedNeedChangeFromData(consumableNeedsData.energy), consumableNeedsData.energy.value, false);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Energy;
	}

	private final func GetNeedType() -> DFNeedType {
		return DFNeedType.Energy;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
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
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_exhale_02", 20);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_breath_heavy", 20);
				}
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Energy, false, true);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				} else {
					notification.sfx = new DFAudioCue(n"q001_sc_01_v_male_sigh", 30);
				}
				
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
		DFLog(this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState(this, true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"HousingStatusEffect.Rested") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"HousingStatusEffect.Rested");
				}
			}
		}
	}

	private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialCombinedNeedsTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialCombinedNeeds";
	}

	private func GetHasShownTutorialForNeed() -> Bool {
		return this.PlayerStateService.hasShownBasicNeedsTutorial;
	}

	private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		this.PlayerStateService.hasShownBasicNeedsTutorial = hasShownTutorial;
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeEnergyFromItems(energyAmount: Float, opt unclampedEnergyAmount: Float, opt contextuallyDelayed: Bool) -> Void {
		if RunGuard(this) { return; }

		// The Stimulant effect prevents consumables from restoring Energy forever without sleeping.
		let shouldUpdateEnergy: Bool = false;
		let useStimulant: Bool = false;

		if energyAmount < 0.0 {
			shouldUpdateEnergy = true;
		} else if unclampedEnergyAmount > 0.0 && this.stimulantStacks < this.stimulantMaxStacks {
			shouldUpdateEnergy = true;
			useStimulant = true;
		}

		if shouldUpdateEnergy {
			if useStimulant {
				energyAmount *= (1.0 - (this.stimulantEnergyRestoreMultPerStack * Cast<Float>(this.stimulantStacks)));

				if energyAmount + this.GetNeedValue() > this.GetNeedMax() {
					energyAmount = this.GetNeedMax() - this.GetNeedValue();
				}
			}
			
			if contextuallyDelayed {
				this.QueueContextuallyDelayedNeedValueChange(energyAmount, true);
			} else {
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = true;
				uiFlags.forceBright = true;
				uiFlags.momentaryDisplayIgnoresSceneTier = true;
				this.ChangeNeedValue(energyAmount, uiFlags);
			}
		}

		if useStimulant {
			this.stimulantStacks += 1u;
			this.RefreshStimulantEffect();
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

	public final func GetStimulantStacks() -> Uint32 {
		return this.stimulantStacks;
	}

	private final func GetEnergyChangeWithRecoverLimit(energyValue: Float, timeSkipType: DFTimeSkipType) -> Float {
		let amountToChange: Float;

		if IsSleeping(timeSkipType) {
			let recoverLimit: Float;
			switch timeSkipType {
				case DFTimeSkipType.FullSleep:
					recoverLimit = 100.0;
					break;
				case DFTimeSkipType.LimitedSleep:
					recoverLimit = this.Settings.limitedEnergySleepingInVehicles;
					break;
			}

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

	private func ReevaluateSystem() -> Void {
		super.ReevaluateSystem();
		this.RefreshStimulantEffect();
	}

	private final func RefreshStimulantEffect() -> Void {
		let validGameState: Bool = this.GameStateService.IsValidGameState(this);
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");

		if validGameState && this.stimulantStacks > 0u {
			let i: Uint32 = 0u;
			while i < this.stimulantStacks {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");
				i += 1u;
			}
		}
	}

	public func ChangeNeedValue(amount: Float, opt uiFlags: DFNeedChangeUIFlags, opt suppressRecoveryNotification: Bool, opt maxOverride: Float) -> Void {
		super.ChangeNeedValue(amount, uiFlags, suppressRecoveryNotification, maxOverride);
		this.CheckIfBonusEffectsValid();
	}

	private final func ClearStimulant() -> Void {
		this.stimulantStacks = 0u;
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.StimulantEffect");
	}
}

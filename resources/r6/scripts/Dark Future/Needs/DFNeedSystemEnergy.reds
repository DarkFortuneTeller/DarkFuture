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
	DFTimeSkipType,
	DFTempEnergyItemType
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

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
	let effectID: TweakDBID = evt.staticData.GetID();
	let mainSystemEnabled: Bool = DFSettings.Get().mainSystemEnabled;
	if mainSystemEnabled {
		if Equals(effectID, t"DarkFutureStatusEffect.EnergizedEffect") {
			DFEnergySystem.Get().OnEnergizedEffectRemoved();
		}
	}
	
	return wrappedMethod(evt);
}

class DFEnergySystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFEnergySystem.Get();
	}
}

public final class DFEnergySystem extends DFNeedSystemBase {
	private persistent let energyRestoredPerEnergizedStack: array<Float>;

	private let energizedEffectID: TweakDBID = t"DarkFutureStatusEffect.EnergizedEffect";

	private let NerveSystem: ref<DFNerveSystem>;

    private let energyRecoverAmountSleeping: Float = 0.4667;
	private let energizedMaxStacksFromCaffeine: Uint32 = 3u;
	private let energizedMaxStacksFromStimulants: Uint32 = 6u;

	private let isSkippingTime: Bool = false;

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
		this.ClearEnergyManagementEffects();
	}

	private func DoPostResumeActions() -> Void {
		super.DoPostResumeActions();
	}

    //
	//	Overrides
	//
	private final func OnUpdateActual() -> Void {
		this.ChangeNeedValue(this.GetEnergyChange());
	}

	public final func OnTimeSkipStart() -> Void {
		super.OnTimeSkipStart();
		this.isSkippingTime = true;
	}

	public final func OnTimeSkipCancelled() -> Void {
		super.OnTimeSkipCancelled();
		this.isSkippingTime = false;
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		this.ClearEnergyManagementEffects();
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.energy.value - this.GetNeedValue());
		this.isSkippingTime = false;
	}

	public final func PerformQuestSleep() -> Void {
		this.ClearEnergyManagementEffects();
		this.QueueContextuallyDelayedNeedValueChange(100.0);
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.energy.value < 0.0 {
			this.ReduceEnergyFromItem(this.GetClampedNeedChangeFromData(consumableNeedsData.energy), false, consumableNeedsData.energy.value);
		} else {
			let tempEnergyItemType: DFTempEnergyItemType;
			if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCaffeine") {
				tempEnergyItemType = DFTempEnergyItemType.Caffeine;
			} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedStimulant") {
				tempEnergyItemType = DFTempEnergyItemType.Stimulant;
			} else {
				return;
			}

			let energizedStacksToApply: Uint32 = this.GetEnergizedStackCountFromItemRecord(itemRecord);

			this.TryToApplyEnergizedStacks(energizedStacksToApply, tempEnergyItemType, false);
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
	public final func ReduceEnergyFromItem(energyAmount: Float, animateUI: Bool, opt unclampedEnergyAmount: Float) -> Void {		
		if RunGuard(this) { return; }

		if energyAmount < 0.0 {
			if energyAmount + this.GetNeedValue() > this.GetNeedMax() {
				energyAmount = this.GetNeedMax() - this.GetNeedValue();
			}
			
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;
			this.ChangeNeedValue(energyAmount, uiFlags);
		}
	}

	public final func TryToApplyEnergizedStacks(energizedStacksFromItem: Uint32, tempEnergyItemType: DFTempEnergyItemType, animateUI: Bool, opt contextuallyDelayed: Bool) -> Void {
		if RunGuard(this) { return; }

		let shouldUpdateEnergy: Bool = false;
		let energizedStacksToApply: Uint32 = 0u;
		let totalEnergyAmount: Float = 0.0;

		let availableStacks: Uint32;
		if Equals(tempEnergyItemType, DFTempEnergyItemType.Caffeine) {
			availableStacks = this.energizedMaxStacksFromCaffeine - this.GetEnergizedStacks();
		} else if Equals(tempEnergyItemType, DFTempEnergyItemType.Stimulant) {
			availableStacks = this.energizedMaxStacksFromStimulants - this.GetEnergizedStacks();
		}

		if availableStacks > 0u {
			shouldUpdateEnergy = true;
			energizedStacksToApply = Cast<Uint32>(Min(Cast<Int32>(energizedStacksFromItem), Cast<Int32>(availableStacks)));
			
			let i: Uint32 = 0u;
			let needValue: Float = this.GetNeedValue();
			while i < energizedStacksToApply {
				// Keep track of the actual amount of Energy replenished, so that we can subtract it later.
				let energyAmount: Float = this.Settings.energyPerEnergizedStack;
				if energyAmount + needValue > this.GetNeedMax() {
					energyAmount = this.GetNeedMax() - needValue;
				}
				needValue += energyAmount;
				totalEnergyAmount += energyAmount;
				ArrayPush(this.energyRestoredPerEnergizedStack, energyAmount);

				// Apply the stack.
				StatusEffectHelper.ApplyStatusEffect(this.player, this.energizedEffectID);

				i += 1u;
			}
		}

		DFLog(this, "energyRestoredPerEnergizedStack: " + ToString(this.energyRestoredPerEnergizedStack));
		
		if contextuallyDelayed {
			this.QueueContextuallyDelayedNeedValueChange(totalEnergyAmount, true);
		} else {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;
			this.ChangeNeedValue(totalEnergyAmount, uiFlags);
		}
	}

	public final func GetItemEnergyChangePreviewAmount(itemRecord: wref<Item_Record>, needsData: DFNeedsDatum) -> Float {
		if needsData.energy.value < 0.0 {
			return needsData.energy.value;

		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergized") {
			// Temporary Energy

			// How many stacks can the item apply?
			let energizedStacksFromItem: Uint32 = this.GetEnergizedStackCountFromItemRecord(itemRecord);

			// How many stacks can currently be applied, given its type?
			let availableStacks: Uint32;
			if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCaffeine") {
				availableStacks = this.energizedMaxStacksFromCaffeine - this.GetEnergizedStacks();
			} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedStimulant") {
				availableStacks = this.energizedMaxStacksFromStimulants - this.GetEnergizedStacks();
			}

			if availableStacks > 0u {
				let energizedStacksToApply: Uint32 = Cast<Uint32>(Min(Cast<Int32>(energizedStacksFromItem), Cast<Int32>(availableStacks)));
				return this.Settings.energyPerEnergizedStack * Cast<Float>(energizedStacksToApply);
			} else {
				return 0.0;
			}
		} else {
			return 0.0;
		}
	}

	public final func OnEnergizedEffectRemoved() -> Void {
		if RunGuard(this) { return; }
		if this.isSkippingTime { return; }

		DFLog(this, "OnEnergizedEffectRemoved");
		let stackCount: Uint32 = StatusEffectHelper.GetStatusEffectByID(this.player, this.energizedEffectID).GetStackCount();
		let internalStackCount: Uint32 = this.GetEnergizedStacks();
		
		if stackCount < internalStackCount {
			let delta: Int32 = Cast<Int32>(internalStackCount - stackCount);
			let i: Int32 = 0;
			while i < delta {
				let energyToRemove: Float = ArrayPop(this.energyRestoredPerEnergizedStack);
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = false;
				uiFlags.forceBright = true;
				this.ChangeNeedValue(-energyToRemove, uiFlags);
				i += 1;
			}
		}

		DFLog(this, "energyRestoredPerEnergizedStack: " + ToString(this.energyRestoredPerEnergizedStack));
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

	public final func GetEnergizedStacks() -> Uint32 {
		return Cast<Uint32>(ArraySize(this.energyRestoredPerEnergizedStack));
	}

	public final func GetTotalEnergyRestoredFromEnergized() -> Float {
		let totalEnergy: Float = 0.0;
		
		if ArraySize(this.energyRestoredPerEnergizedStack) > 0 {
			for val in this.energyRestoredPerEnergizedStack {
				totalEnergy += val;
			}
		}

		return totalEnergy;
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
	}

	public func ChangeNeedValue(amount: Float, opt uiFlags: DFNeedChangeUIFlags, opt suppressRecoveryNotification: Bool, opt maxOverride: Float) -> Void {
		super.ChangeNeedValue(amount, uiFlags, suppressRecoveryNotification, maxOverride);
		this.CheckIfBonusEffectsValid();
	}

	private final func ClearEnergyManagementEffects() -> Void {
		DFLog(this, "Clearing energy management effects.");
		ArrayClear(this.energyRestoredPerEnergizedStack);
		StatusEffectHelper.RemoveStatusEffect(this.player, this.energizedEffectID, this.energizedMaxStacksFromStimulants);
	}

	private final func GetEnergizedStackCountFromItemRecord(itemRecord: wref<Item_Record>) -> Uint32 {
		if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCount1") {
			return 1u;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCount2") {
			return 2u;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCount3") {
			return 3u;
		} else {
			return 0u;
		}
	}
}

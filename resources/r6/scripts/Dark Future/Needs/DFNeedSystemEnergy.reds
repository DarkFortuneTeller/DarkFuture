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
	DFRunGuard,
	DFIsSleeping
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
	//DFProfile();
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
		//DFProfile();
		return DFEnergySystem.Get();
	}
}

public final class DFEnergySystem extends DFNeedSystemBase {
	private persistent let energyRestoredPerEnergizedStack: array<Float>;

	private let energizedEffectID: TweakDBID = t"DarkFutureStatusEffect.EnergizedEffect";

	private let NerveSystem: ref<DFNerveSystem>;

    private let energyRecoverAmountSleeping: Float = 0.74;
	public let energizedMaxStacksFromCaffeine: Uint32 = 3u;
	private let energizedMaxStacksFromStimulants: Uint32 = 6u;

	private let isSkippingTime: Bool = false;

    //
	//	System Methods
	//
	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFEnergySystem> {
		//DFProfile();
		let instance: ref<DFEnergySystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFEnergySystem>()) as DFEnergySystem;
		return instance;
	}

	public final static func Get() -> ref<DFEnergySystem> {
		//DFProfile();
		return DFEnergySystem.GetInstance(GetGameInstance());
	}

    //
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}
	
	public final func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		//DFProfile();
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	public func GetSystems() -> Void {
		//DFProfile();
		super.GetSystems();
		this.NerveSystem = DFNerveSystem.Get();
	}

	public final func SetupData() -> Void {
		//DFProfile();
		super.SetupData();
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.EnergyPenalty_01",
			t"DarkFutureStatusEffect.EnergyPenalty_02",
			t"DarkFutureStatusEffect.EnergyPenalty_03",
			t"DarkFutureStatusEffect.EnergyPenalty_04"
		];
	}

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		super.DoPostSuspendActions();
		this.ClearEnergyManagementEffects();
	}

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		super.DoPostResumeActions();
	}

    //
	//	Overrides
	//
	private final func OnUpdateActual() -> Void {
		//DFProfile();
		this.ChangeNeedValue(this.GetEnergyChange());
	}

	public final func OnTimeSkipStart() -> Void {
		//DFProfile();
		super.OnTimeSkipStart();
		this.isSkippingTime = true;
	}

	public final func OnTimeSkipCancelled() -> Void {
		//DFProfile();
		super.OnTimeSkipCancelled();
		this.isSkippingTime = false;
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		//DFProfile();
		this.ClearEnergyManagementEffects();
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.energy.value - this.GetNeedValue());
		this.isSkippingTime = false;
	}

	public final func PerformQuestSleep() -> Void {
		//DFProfile();
		this.ClearEnergyManagementEffects();
		this.QueueContextuallyDelayedNeedValueChange(100.0);
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
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
		//DFProfile();
		return DFHUDBarType.Energy;
	}

	private final func GetNeedType() -> DFNeedType {
		//DFProfile();
		return DFNeedType.Energy;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		//DFProfile();
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;

		if stage >= 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_breath_heavy", 10);
			}

			if this.Settings.energyNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"waking_up", null);
			}
			
			notification.ui = DFUIDisplay(DFHUDBarType.Energy, true, false, false, false);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_exhale_02", 20);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_breath_heavy", 20);
				}
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Energy, false, true, false, false);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				} else {
					notification.sfx = DFAudioCue(n"q001_sc_01_v_male_sigh", 30);
				}
				
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureEnergyNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		//DFProfile();
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		//DFProfile();
		return n"DarkFutureNeedEnergy";
	}

	private final func GetTutorialTitleKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialCombinedNeedsTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialCombinedNeeds";
	}

	private final func GetHasShownTutorialForNeed() -> Bool {
		//DFProfile();
		return this.PlayerStateService.hasShownBasicNeedsTutorial;
	}

	private final func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		//DFProfile();
		this.PlayerStateService.hasShownBasicNeedsTutorial = hasShownTutorial;
	}

	private final func GetBonusEffectTDBID() -> TweakDBID {
		//DFProfile();
		return t"HousingStatusEffect.Rested";
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ReduceEnergyFromItem(energyAmount: Float, animateUI: Bool, opt unclampedEnergyAmount: Float) -> Void {		
		//DFProfile();
		if DFRunGuard(this) { return; }

		if energyAmount < 0.0 {
			if energyAmount + this.GetNeedValue() > this.GetNeedMax() {
				energyAmount = this.GetNeedMax() - this.GetNeedValue();
			}
			
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;

			this.ChangeNeedValue(energyAmount, changeNeedValueProps);
		}
	}

	public final func TryToApplyEnergizedStacks(energizedStacksFromItem: Uint32, tempEnergyItemType: DFTempEnergyItemType, animateUI: Bool, opt contextuallyDelayed: Bool) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }

		let energizedStacksToApply: Uint32 = 0u;
		let totalEnergyAmount: Float = 0.0;

		let availableStacks: Int32;
		if Equals(tempEnergyItemType, DFTempEnergyItemType.Caffeine) {
			availableStacks = Cast<Int32>(this.energizedMaxStacksFromCaffeine) - Cast<Int32>(this.GetEnergizedStacks());
		} else if Equals(tempEnergyItemType, DFTempEnergyItemType.Stimulant) {
			availableStacks = Cast<Int32>(this.energizedMaxStacksFromStimulants) - Cast<Int32>(this.GetEnergizedStacks());
		}

		if availableStacks > 0 {
			energizedStacksToApply = Cast<Uint32>(Min(Cast<Int32>(energizedStacksFromItem), availableStacks));
			
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
			let changeNeedValueProps: DFChangeNeedValueProps;
			
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;

			this.ChangeNeedValue(totalEnergyAmount, changeNeedValueProps);
		}
	}

	public final func GetItemEnergyChangePreviewAmount(itemRecord: wref<Item_Record>, needsData: DFNeedsDatum) -> Float {
		//DFProfile();
		if needsData.energy.value < 0.0 {
			return needsData.energy.value;

		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergized") {
			// Temporary Energy

			// How many stacks can the item apply?
			let energizedStacksFromItem: Uint32 = this.GetEnergizedStackCountFromItemRecord(itemRecord);

			// How many stacks can currently be applied, given its type?
			let availableStacks: Int32;
			if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCaffeine") {
				availableStacks = Cast<Int32>(this.energizedMaxStacksFromCaffeine) - Cast<Int32>(this.GetEnergizedStacks());
			} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedStimulant") {
				availableStacks = Cast<Int32>(this.energizedMaxStacksFromStimulants) - Cast<Int32>(this.GetEnergizedStacks());
			}

			if availableStacks > 0 {
				let energizedStacksToApply: Uint32 = Cast<Uint32>(Min(Cast<Int32>(energizedStacksFromItem), availableStacks));
				return this.Settings.energyPerEnergizedStack * Cast<Float>(energizedStacksToApply);
			} else {
				return 0.0;
			}
		} else {
			return 0.0;
		}
	}

	public final func OnEnergizedEffectRemoved() -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		if this.isSkippingTime { return; }

		DFLog(this, "OnEnergizedEffectRemoved");
		let stackCount: Uint32 = StatusEffectHelper.GetStatusEffectByID(this.player, this.energizedEffectID).GetStackCount();
		let internalStackCount: Uint32 = this.GetEnergizedStacks();
		
		if stackCount < internalStackCount {
			let delta: Int32 = Cast<Int32>(internalStackCount - stackCount);
			let i: Int32 = 0;
			while i < delta {
				let energyToRemove: Float = ArrayPop(this.energyRestoredPerEnergizedStack);

				let changeNeedValueProps: DFChangeNeedValueProps;

				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = false;
				uiFlags.forceBright = true;

				changeNeedValueProps.uiFlags = uiFlags;

				this.ChangeNeedValue(-energyToRemove, changeNeedValueProps);
				i += 1;
			}
		}

		DFLog(this, "energyRestoredPerEnergizedStack: " + ToString(this.energyRestoredPerEnergizedStack));
	}

    //
    //  System-Specific Methods
    //
    public final func GetEnergyChange() -> Float {
		//DFProfile();
        // Subtract 100 points every 30 in-game hours
		// The player will feel the first effects of this need after 4.5 in-game hours (33.75 minutes of gameplay)

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		return (100.0 / ((30.0 * 60.0) / 5.0) * -1.0) * (this.Settings.energyLossRatePct / 100.0);
	}

	public final func GetEnergizedStacks() -> Uint32 {
		//DFProfile();
		return Cast<Uint32>(ArraySize(this.energyRestoredPerEnergizedStack));
	}

	public final func GetTotalEnergyRestoredFromEnergized() -> Float {
		//DFProfile();
		let totalEnergy: Float = 0.0;
		
		if ArraySize(this.energyRestoredPerEnergizedStack) > 0 {
			for val in this.energyRestoredPerEnergizedStack {
				totalEnergy += val;
			}
		}

		return totalEnergy;
	}

	public final func GetEnergyChangeWithRecoverLimit(energyValue: Float, timeSkipType: DFTimeSkipType) -> Float {
		//DFProfile();
		let amountToChange: Float;

		if DFIsSleeping(timeSkipType) {
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

	public func ReevaluateSystem() -> Void {
		//DFProfile();
		super.ReevaluateSystem();
	}

	public final func ChangeNeedValue(amount: Float, opt changeValueProps: DFChangeNeedValueProps) -> Void {
		//DFProfile();
		super.ChangeNeedValue(amount, changeValueProps);
		this.CheckIfBonusEffectsValid();
	}

	public final func ClearEnergyManagementEffects() -> Void {
		//DFProfile();
		DFLog(this, "Clearing energy management effects.");
		ArrayClear(this.energyRestoredPerEnergizedStack);
		StatusEffectHelper.RemoveStatusEffect(this.player, this.energizedEffectID, this.energizedMaxStacksFromStimulants);
	}

	private final func GetEnergizedStackCountFromItemRecord(itemRecord: wref<Item_Record>) -> Uint32 {
		//DFProfile();
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

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
	DFBarUIDisplay,
	DFNotification,
	DFNotificationCallback
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.{
	DFSettings,
	DFSleepQualitySetting
}
import DarkFuture.Conditions.{
	DFBiocorruptionConditionSystem,
	DFBiocorruptionConditionState,
	BiocorruptionConditionSystemApplyDelayedNeedLossEvent
}

public struct DFEnergyChangeWithRecoverLimit {
	public let change: Float;
	public let delayedLoss: Float;
	public let showLock: Bool;
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
	//DFProfile();
	let effectID: TweakDBID = evt.staticData.GetID();
	let mainSystemEnabled: Bool = DFSettings.Get().mainSystemEnabled;
	if mainSystemEnabled {
		if Equals(effectID, t"DarkFutureStatusEffect.EnergizedEffect") {
			DFEnergySystem.Get().OnEnergizedEffectRemoved();
		
		} else if Equals(effectID, t"BaseStatusEffect.Drunk") {
			DFEnergySystem.Get().OnAlcoholEffectRemoved();

		}
	}
	
	return wrappedMethod(evt);
}

class DFEnergySystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		//DFProfile();
		return DFEnergySystem.Get();
	}

	public cb func OnLoad() {
		//DFProfile();
		super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<BiocorruptionConditionSystemApplyDelayedNeedLossEvent>(), this, n"OnBiocorruptionConditionSystemApplyDelayedNeedLossEvent", true);
	}

	private cb func OnBiocorruptionConditionSystemApplyDelayedNeedLossEvent(event: ref<BiocorruptionConditionSystemApplyDelayedNeedLossEvent>) {
		//DFProfile();
        this.GetSystemInstance().ApplyDelayedNeedLoss();
    }
}

public final class DFEnergySystem extends DFNeedSystemBase {
	private persistent let energyRestoredPerEnergizedStack: array<Float>;
	private persistent let energyDrainedPerAlcoholStack: array<Float>;

	let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;

	private let energizedEffectID: TweakDBID = t"DarkFutureStatusEffect.EnergizedEffect";
	private let alcoholEffectID: TweakDBID = t"BaseStatusEffect.Drunk";

    private const let energyRecoverAmountSleeping: Float = 0.74;
	private const let energyRecoverAmountBlackout: Float = 0.41;
	public const let energizedMaxStacksFromCaffeine: Uint32 = 3u;
	private const let energizedMaxStacksFromStimulants: Uint32 = 6u;
	private const let alcoholMaxStacks: Uint32 = 10u;
	private const let energyPercentToDeferPerBiocorruptionLevel: Float = 0.25;
	private const let blackoutEnergyRecoveryLimit: Float = 20.0;

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
		this.debugEnabled = true;
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

	public final func GetSystems() -> Void {
		super.GetSystems();
		this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.Get();
	}

    //
	//	Overrides
	//
	private final func OnUpdateActual() -> Void {
		//DFProfile();
		let props: DFChangeNeedValueProps;
		
		if Equals(this.BiocorruptionConditionSystem.GetCurrentBiocorruptionState(), DFBiocorruptionConditionState.Bonus) {
			props.delayPercent = this.energyPercentToDeferPerBiocorruptionLevel * Cast<Float>(this.BiocorruptionConditionSystem.GetConditionLevel());
		}
		
		this.ChangeNeedValue(this.GetEnergyChange(this.GetNeedValue()), props);
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
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.energy.value - this.GetNeedValue(), false, false, t"", Equals(data.timeSkipType, DFTimeSkipType.Blackout));
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
			let energizedStacksToApply: Uint32;
			let alcoholStacksToApply: Uint32;

			if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedCaffeine") {
				tempEnergyItemType = DFTempEnergyItemType.Caffeine;
				energizedStacksToApply = this.GetEnergizedStackCountFromItemRecord(itemRecord);

			} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergizedStimulant") {
				tempEnergyItemType = DFTempEnergyItemType.Stimulant;
				energizedStacksToApply = this.GetEnergizedStackCountFromItemRecord(itemRecord);

			} else if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcoholWeak") {
				tempEnergyItemType = DFTempEnergyItemType.WeakAlcohol;
				alcoholStacksToApply = 1u;

			} else if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcoholStrong") {
				tempEnergyItemType = DFTempEnergyItemType.StrongAlcohol;
				alcoholStacksToApply = 3u;

			} else {
				return;
			}

			this.TryToApplyTemporaryEnergy(energizedStacksToApply, alcoholStacksToApply, tempEnergyItemType, false);
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
			
			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Energy, true, false, false, false);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_exhale_02", 20);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_breath_heavy", 20);
				}
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Energy, false, true, false, false);
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

	private final func GetNeedDeathSettingValue() -> Bool {
		return false;
	}

	private final func GetNeedSoftCapValue() -> Float {
		if Equals(this.BiocorruptionConditionSystem.GetCurrentBiocorruptionState(), DFBiocorruptionConditionState.Crash) {
			return this.BiocorruptionConditionSystem.GetCurrentBasicNeedSoftCapFromBiocorruption();
		
		} else {
			return 100.0;
		}
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeNeedValue(amount: Float, opt changeValueProps: DFChangeNeedValueProps) -> Void {
		super.ChangeNeedValue(amount, changeValueProps);

		let currentNeedValue: Float = this.GetNeedValue();

		// TODO - If Energy is restored while a blackout is pending, cancel the pending blackout and animation registration
		if currentNeedValue == 0.0 && !this.blackoutNeedChangePending {
			this.blackoutNeedChangePending = true;
			this.PlayerStateService.TryToStartBlackoutAnimation();
		}
	}
	
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

	public final func TryToApplyTemporaryEnergy(energizedStacksFromItem: Uint32, alcoholStacksFromItem: Uint32, tempEnergyItemType: DFTempEnergyItemType, animateUI: Bool, opt contextuallyDelayed: Bool) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }

		let energizedStacksToApply: Uint32 = 0u;
		let alcoholStacksToApply: Uint32 = 0u;
		let totalEnergyAmount: Float = 0.0;

		let availableEnergizedStacks: Int32;
		let availableAlcoholStacks: Int32;
		if Equals(tempEnergyItemType, DFTempEnergyItemType.Caffeine) {
			availableEnergizedStacks = Cast<Int32>(this.energizedMaxStacksFromCaffeine) - Cast<Int32>(this.GetEnergizedStacks());

		} else if Equals(tempEnergyItemType, DFTempEnergyItemType.Stimulant) {
			availableEnergizedStacks = Cast<Int32>(this.energizedMaxStacksFromStimulants) - Cast<Int32>(this.GetEnergizedStacks());

		} else if Equals(tempEnergyItemType, DFTempEnergyItemType.WeakAlcohol) || Equals(tempEnergyItemType, DFTempEnergyItemType.StrongAlcohol) {
			availableAlcoholStacks = Cast<Int32>(this.alcoholMaxStacks) - Cast<Int32>(this.GetAlcoholStacks());

		}

		if energizedStacksFromItem > 0u && availableEnergizedStacks > 0 {
			energizedStacksToApply = Cast<Uint32>(Min(Cast<Int32>(energizedStacksFromItem), availableEnergizedStacks));
			
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
		
		} else if alcoholStacksFromItem > 0u && availableAlcoholStacks > 0 {
			// We are just pushing temporary energy loss without any Status Effect stack management.
			alcoholStacksToApply = Cast<Uint32>(Min(Cast<Int32>(alcoholStacksFromItem), availableAlcoholStacks));

			let i: Uint32 = 0u;
			let needValue: Float = this.GetNeedValue();

			while i < alcoholStacksToApply {
				// Keep track of the actual amount of Energy drained, so that we can add it later.
				// TODO - Make Setting
				let energyAmount: Float = -10.0;
				if energyAmount + needValue < 0.0 {
					energyAmount = -needValue;
				}
				needValue += energyAmount;
				totalEnergyAmount += energyAmount;
				ArrayPush(this.energyDrainedPerAlcoholStack, energyAmount);

				i += 1u;
			}
		}

		DFLog(this, "energyRestoredPerEnergizedStack: " + ToString(this.energyRestoredPerEnergizedStack));
		DFLog(this, "energyDrainedPerAlcoholStack: " + ToString(this.energyDrainedPerAlcoholStack));
		
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
			// Temporary Energy (Replenish)

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
		} else if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcohol") {
			// Temporary Energy (Drain)

			// How many stacks can the item apply?
			let alcoholStacksFromItem: Uint32;
			if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcoholWeak") {
				alcoholStacksFromItem = 1u;

			} else if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcoholStrong") {
				alcoholStacksFromItem = 3u;
			}

			// How many stacks can currently be applied, given its type?
			let availableStacks: Int32 = Cast<Int32>(this.alcoholMaxStacks) - Cast<Int32>(this.GetAlcoholStacks());

			if availableStacks > 0 {
				let alcoholStacksToApply: Uint32 = Cast<Uint32>(Min(Cast<Int32>(alcoholStacksFromItem), availableStacks));
				// TODO - Setting
				return -10.0 * Cast<Float>(alcoholStacksToApply);
			} else {
				return 0.0;
			}

		} else {
			return 0.0;
		}
	}

	// TODO - Convert effect to remove all stacks at once and simplify
	// TODO - Actually, think I'm moving away from that approach. Maybe?
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

	public final func OnAlcoholEffectRemoved() -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		if this.isSkippingTime { return; }

		DFLog(this, "OnAlcoholEffectRemoved");
		let stackCount: Uint32 = StatusEffectHelper.GetStatusEffectByID(this.player, this.alcoholEffectID).GetStackCount();
		let internalStackCount: Uint32 = this.GetAlcoholStacks();
		
		if stackCount < internalStackCount {
			let delta: Int32 = Cast<Int32>(internalStackCount - stackCount);
			let i: Int32 = 0;
			while i < delta {
				let energyToAdd: Float = ArrayPop(this.energyDrainedPerAlcoholStack) * -1.0;

				let changeNeedValueProps: DFChangeNeedValueProps;

				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = false;
				uiFlags.forceBright = true;

				changeNeedValueProps.uiFlags = uiFlags;

				this.ChangeNeedValue(energyToAdd, changeNeedValueProps);
				i += 1;
			}
		}

		DFLog(this, "energyDrainedPerAlcoholStack: " + ToString(this.energyDrainedPerAlcoholStack));
	}

    //
    //  System-Specific Methods
    //
    public final func GetEnergyChange(currentEnergy: Float) -> Float {
		//DFProfile();
        // Subtract 100 points every 30 in-game hours
		// The player will feel the first effects of this need after 4.5 in-game hours (33.75 minutes of gameplay)

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		// Lose points non-linearly.

		let totalPointLossInRange: Float;
		let targetHoursInRange: Float;
		if currentEnergy > this.Settings.basicNeedThresholdValue1V2 {
			totalPointLossInRange = 100.0 - this.Settings.basicNeedThresholdValue1V2;
			targetHoursInRange = 20.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue2V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue1V2 - this.Settings.basicNeedThresholdValue2V2;
			targetHoursInRange = 6.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue3V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue2V2 - this.Settings.basicNeedThresholdValue3V2;
			targetHoursInRange = 6.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue4V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue3V2 - this.Settings.basicNeedThresholdValue4V2;
			targetHoursInRange = 4.0;

		} else {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue4V2;
			targetHoursInRange = 4.0;
		}

		return (totalPointLossInRange / ((targetHoursInRange * 60.0) / 5.0) * -1.0) * (this.Settings.energyLossRatePctV2 / 100.0);
	}

	public final func GetEnergizedStacks() -> Uint32 {
		//DFProfile();
		return Cast<Uint32>(ArraySize(this.energyRestoredPerEnergizedStack));
	}

	public final func GetAlcoholStacks() -> Uint32 {
		return Cast<Uint32>(ArraySize(this.energyDrainedPerAlcoholStack));
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

	public final func GetTotalEnergyDrainedFromAlcohol() -> Float {
		//DFProfile();
		let totalEnergy: Float = 0.0;
		
		if ArraySize(this.energyDrainedPerAlcoholStack) > 0 {
			for val in this.energyDrainedPerAlcoholStack {
				totalEnergy += val;
			}
		}

		return totalEnergy;
	}

	public final func GetEnergyChangeWithRecoverLimit(energyValue: Float, timeSkipType: DFTimeSkipType, isDistressed: Bool, biocorruptionLevel: Uint32, sufferingBiocorruptionCrashAtSkipTimeStart: Bool, percentageOfBasicNeedLossToDelay: Float, alreadyDelayedAmount: Float) -> DFEnergyChangeWithRecoverLimit {
		//DFProfile();
		let amountToChange: Float;
		let delayedEnergyLoss: Float;
		let showLock: Bool = false;
		let limitFromBiocorruption: Bool = false;

		if DFIsSleeping(timeSkipType) {
			if isDistressed && NotEquals(timeSkipType, DFTimeSkipType.Blackout) {
				// If Distressed and not sleeping due to blacking out, reduce Energy.

				if biocorruptionLevel > 0u && !sufferingBiocorruptionCrashAtSkipTimeStart {
					// Get the change taking into account the already delayed amount,
					// because the loss rate is non-linear.
					energyValue += alreadyDelayedAmount;
					amountToChange = this.GetEnergyChange(energyValue);
					delayedEnergyLoss = amountToChange * percentageOfBasicNeedLossToDelay;
					amountToChange -= delayedEnergyLoss;
				} else {
					amountToChange = this.GetEnergyChange(energyValue);
				}

				return DFEnergyChangeWithRecoverLimit(amountToChange, delayedEnergyLoss, false);
			}

			let recoverLimit: Float;
			switch timeSkipType {
				case DFTimeSkipType.FullSleep:
					recoverLimit = 100.0;
					break;
				case DFTimeSkipType.LimitedSleep:
					recoverLimit = this.Settings.limitedEnergySleepingInVehicles;
					break;
				case DFTimeSkipType.Blackout:
					recoverLimit = this.blackoutEnergyRecoveryLimit;
					break;
			}

			if biocorruptionLevel > 0u && sufferingBiocorruptionCrashAtSkipTimeStart {
				let biocorruptionSoftCap: Float = this.BiocorruptionConditionSystem.GetBasicNeedSoftCapFromBiocorruptionAtLevel(biocorruptionLevel);
				if biocorruptionSoftCap < recoverLimit {
					recoverLimit = biocorruptionSoftCap;
					limitFromBiocorruption = true;
				}
			}

			if energyValue > recoverLimit {
				if biocorruptionLevel > 0u && !sufferingBiocorruptionCrashAtSkipTimeStart {
					// Get the change taking into account the already delayed amount,
					// because the loss rate is non-linear.
					energyValue += alreadyDelayedAmount;
					amountToChange = this.GetEnergyChange(energyValue);
					delayedEnergyLoss = amountToChange * percentageOfBasicNeedLossToDelay;
					amountToChange -= delayedEnergyLoss;
				} else {
					amountToChange = this.GetEnergyChange(energyValue);
				}
				
				if energyValue + amountToChange < recoverLimit {
					amountToChange = energyValue - recoverLimit;
				}

			} else {
				if Equals(timeSkipType, DFTimeSkipType.Blackout) {
					amountToChange = this.energyRecoverAmountBlackout;
				} else {
					amountToChange = this.energyRecoverAmountSleeping;
				}
				
				if energyValue + amountToChange >= recoverLimit {
					amountToChange = recoverLimit - energyValue;

					if limitFromBiocorruption {
						showLock = true;
					}
				}
			}
		} else {
			amountToChange = this.GetEnergyChange(energyValue);

			if biocorruptionLevel > 0u && !sufferingBiocorruptionCrashAtSkipTimeStart {
				delayedEnergyLoss = amountToChange * percentageOfBasicNeedLossToDelay;
				amountToChange -= delayedEnergyLoss;
			}
		}

		return DFEnergyChangeWithRecoverLimit(amountToChange, delayedEnergyLoss, showLock);
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

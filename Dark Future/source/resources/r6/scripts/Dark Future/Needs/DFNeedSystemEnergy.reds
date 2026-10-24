// -----------------------------------------------------------------------------
// DFEnergySystem
// -----------------------------------------------------------------------------
//
// - Energy Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
	DFRunGuard,
	DFIsSleeping,
	RandRangeInclusive
}
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFBiocorruptionDatum,
	DFTimeSkipData,
	DFTimeSkipType,
	DFEnergyChangePreview
}
import DarkFuture.Conditions.{
	DFBiocorruptionConditionSystem,
	DFBiocorruptionDelayedNeedLossDatum,
	DFQueuedCrashType
}
import DarkFuture.Services.{
	DFGameStateService,
	DFNotificationService,
	DFPlayerStateService,
	DFAnimationService,
	DFAudioCue,
	DFVisualEffect,
	DFBarUIDisplay,
	DFNotification,
	DFNotificationCallback,
	DFManagedEffectItemDefinition,
	DFManagedEffectStackCountMode,
	DFManagedEffectType,
	DFManagedEffect,
	DFManagedEffectDefinition,
	DFManagedEffectStackCountDef,
	DFManagedEffectPipelineResult,
	DFCrashAnimMode,
	DFCyberwareService
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.{
	DFSettings,
	DFSleepQualitySetting,
	DFCrashAnimSetting
}
import DarkFuture.Addictions.{
	DFAddictionSystemBase
}

public enum DFStackCountExceedResult {
	Invalid = 0,
	CrashHeadache = 1,
	CrashVomit = 2,
	Overdose = 3
}

class DFEnergySystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		//DFProfile();
		return DFEnergySystem.Get();
	}
}

public final class DFEnergySystem extends DFNeedSystemBase {
	let AnimationService: ref<DFAnimationService>;
	let NerveSystem: ref<DFNerveSystem>;
	let NutritionSystem: ref<DFNutritionSystem>;
	let HydrationSystem: ref<DFHydrationSystem>;
	let QuestsSystem: ref<QuestsSystem>;

    public const let energyRecoverAmountSleeping: Float = 0.74;
	//private const let energyRecoverAmountBlackout: Float = 0.41;
	private const let energyPercentToDeferPerBiocorruptionLevel: Float = 0.25;
	private const let blackoutEnergyRecoveryLimit: Float = 40.0;
	private const let restlessEnergyRecoveryLimit: Float = 50.0;

	private const let caffeinatedMaxStackCount: Uint32 = 3u;

	public let isSkippingTime: Bool = false;

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

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		super.DoPostResumeActions();
	}

	public final func GetSystems() -> Void {
		//DFProfile();
		super.GetSystems();

		let gameInstance: GameInstance = GetGameInstance();
		this.AnimationService = DFAnimationService.GetInstance(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
	}

	private final func RegisterListeners() -> Void {}
	private final func UnregisterListeners() -> Void {}

	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		super.InitSpecific(attachedPlayer);
		this.TryToSetupBlackoutWithCrash(true, 0u);
	}

    //
	//	Overrides
	//
	private final func OnUpdateActual() -> Void {
		//DFProfile();
		let props: DFChangeNeedValueProps;
		
		if this.BiocorruptionConditionSystem.GetHasEuphoria() {
			props.delayPercent = 1.0;
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
		
		let queuedChange: DFQueuedNeedValueChange;
		queuedChange.value = data.targetNeedValues.energy.value;
		queuedChange.targetDelayedValue = data.targetNeedValues.energy.delayedValue;
		queuedChange.isFromBlackout = Equals(data.timeSkipType, DFTimeSkipType.Blackout);
		queuedChange.finalChangeInEuphoriaDepletion = true;
		queuedChange.targetValueMode = true;
		queuedChange.skipSevereNeedMessage = data.skipSevereNeedMessage;
		queuedChange.isFromTimeskip = true;
		queuedChange.highestCrashStackCountOnTimeskip = data.targetBiocorruptionValues.highestCrashStackCount;

		// To avoid race conditions, set this data from this update.
		if data.targetBiocorruptionValues.crashOccuredDuringTimeskip {
			this.BiocorruptionConditionSystem.SetCrashQueued(DFQueuedCrashType.FromTimeskip);
		}

		this.QueueContextuallyDelayedNeedValueChange(queuedChange);

		this.isSkippingTime = false;
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		// Drug Penalties
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.energy.value < 0.0 {
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;
			changeNeedValueProps.isSoftCapRestrictedChange = true;

			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.energy), changeNeedValueProps);
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

			// TODO - Make setting for impaired driving
			if this.Settings.energyNeedVFXEnabled && (stage < this.PlayerStateService.impairedDrivingEnergyThreshold || !this.PlayerStateService.wasAboveImpairedDrivingSpeedThreshold) {
				// Don't show this VFX when above the Impaired Driving threshold, as this effect is used then as well.
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
		//DFProfile();
		return false;
	}

	private final func GetNeedSoftCapValue() -> Float {
		//DFProfile();
		return 100.0;
	}

	public final func ApplyDelayedNeedLoss(data: DFBiocorruptionDelayedNeedLossDatum) -> Void {
		//DFProfile();
		// Sets isFinalChangeInEuphoriaDepletion to True to signal that it's allowed to
        // trigger a Crash animation if a Blackout never played (prevents race condition between
        // Nerve and Energy updates).

		if data.depleteEnergy {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			let props: DFChangeNeedValueProps;
			props.uiFlags = uiFlags;

			if data.fromQuest {
				// Special Handling - sq031 (A Cool Metal Fire)
				// Don't play a Crash animation, and set the player's Energy appropriately.
				props.finalChangeInEuphoriaDepletion = false;
				props.skipSevereNeedMessage = true;
				props.targetValueMode = true;
			
				this.ChangeNeedValue(65.0, props);
				this.currentDelayedNeedLoss = 0.0;

			} else {
				// All other cases.
				props.finalChangeInEuphoriaDepletion = true;
			
				if NotEquals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.Off) {
					props.skipSevereNeedMessage = true;
				}

				this.ChangeNeedValue(this.GetAccumulatedDelayedNeedLoss(), props);
				this.currentDelayedNeedLoss = 0.0;
			}
		}
	}

	public final func GetNeedMaxAfterItemUse(itemRecord: wref<Item_Record>) -> Float {
		//DFProfile();
		return 100.0;
	}

	public final func GetCalculatedNeedMax() -> Float {
		//DFProfile();
		return 100.0;
	}

	// Overrides parent implementation
	public final func GetCalculatedBasicNeedMaxInProvidedState(crashStacks: Uint32, hasEuphoria: Bool) -> Float {
		//DFProfile();
		return 100.0;
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeNeedValue(amount: Float, opt changeValueProps: DFChangeNeedValueProps) -> Void {
		//DFProfile();
		super.ChangeNeedValue(amount, changeValueProps);
		// TODO: >>>>>>>>>>>> Ask the Biocorruption Condition, or whoever has the time skip info, for the latest data here regarding crash stacks.

		let crashStackCountFromTimeskip: Uint32 = changeValueProps.highestCrashStackCountOnTimeskip;
		this.TryToSetupBlackoutWithCrash(changeValueProps.finalChangeInEuphoriaDepletion, crashStackCountFromTimeskip);

		// If the Need Stage is high, enable impaired driving.
		// TODO - Make setting
		/*if this.GetNeedStage() >= 4 {
			this.QuestsSystem.SetFact(n"df_fact_enable_impaired_driving", 1);
		} else {
			this.QuestsSystem.SetFact(n"df_fact_enable_impaired_driving", 0);
		}*/
	}

	private final func TryToSetupBlackoutWithCrash(crashAllowed: Bool, crashStackCountFromTimeskip: Uint32) -> Void {
		//DFProfile();
		let currentNeedValue: Float = this.GetNeedValue();

		// TODO - If Energy is restored while a blackout is pending, cancel the pending blackout and animation registration
		if currentNeedValue == 0.0 && !this.blackoutNeedChangePending {
			this.blackoutNeedChangePending = true;
			
			// Ensure that a vomit takes place, if necessary. If this Blackout turns out not to include a vomit,
			// we'll get that data back after the event and can re-queue it at that time.
			// TODO - Check Crash stack count
			if NotEquals(this.BiocorruptionConditionSystem.GetCrashQueued(), DFQueuedCrashType.None) && this.BiocorruptionConditionSystem.GetConditionLevel() > 1u {
				this.QuestsSystem.SetFact(this.AnimationService.GetNextBlackoutShouldIncludeCrashFact(), 1);
				
				// If a Crash animation is already queued, unqueue it.
				this.AnimationService.UnqueuePendingCrashAnim();
			} else {
				this.QuestsSystem.SetFact(this.AnimationService.GetNextBlackoutShouldIncludeCrashFact(), 0);
			}

			this.AnimationService.TryToQueueBlackoutAnimation();
			
		} else if currentNeedValue > 0.0 {
			if !this.AnimationService.IsBlackoutQueued() && 
				NotEquals(this.BiocorruptionConditionSystem.GetCrashQueued(), DFQueuedCrashType.None) && 
				crashAllowed {
				// Looks like we changed Energy, and while we didn't black out, the Biocorruption Condition wants a
				// Crash to occur. There are no more Energy changes coming related to Euphoria depletion, this was the last
				// one. Since we're definitely not blacking out, queue a Crash animation instead.
				this.AnimationService.TryToQueueCrashAnimation(DFCrashAnimMode.FromCrash, crashStackCountFromTimeskip);
			}
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

	/*
	public final func TryToApplyTemporaryEnergy(managementStatus: DFEnergyManagementStatus, stackCount: Uint32, animateUI: Bool, contextuallyDelayed: Bool, opt stackCountOverride: Uint32, opt isFromTimeskip: Bool) -> Uint32 {
		let interruptApplication: Bool = false;
		let totalEnergyAmount: Float = 0.0;

		// How many stacks can currently be applied, given its type?
		let currentStacksApplied: Uint32 = this.GetEnergyManagementEffectStacksByType(managementStatus.type);
		
		// Handle these stack counts as Int32, because the stacks applied could be greater than the max allowed stacks,
		// which would cause a Uint32 overflow.

		// Max Allowed Stacks - Trigger Effects
		if Equals(managementStatus.itemRecordTag, n"DarkFutureManagedConsumableCaffeine") {
			if currentStacksApplied + stackCount > this.caffeinatedMaxStackCount {
				stackCount = this.caffeinatedMaxStackCount - currentStacksApplied;
			}

		} else if Equals(managementStatus.itemRecordTag, n"DarkFutureManagedConsumableNicotine") {
			if currentStacksApplied + stackCount >= this.BiocorruptionConditionSystem.maxNicotineStacksUntilDebuffPerBiocorruptionLevel[Cast<Int32>(this.BiocorruptionConditionSystem.GetConditionLevel())] {
				// Crash - Headache
				this.HandleStackCountExceeded(managementStatus, DFStackCountExceedResult.CrashHeadache);
				interruptApplication = true;
			}
		
		} else if Equals(managementStatus.itemRecordTag, n"DarkFutureManagedConsumableAlcohol") {
			if currentStacksApplied + stackCount >= this.BiocorruptionConditionSystem.maxAlcoholStacksUntilDebuffPerBiocorruptionLevel[Cast<Int32>(this.BiocorruptionConditionSystem.GetConditionLevel())] {
				// Crash - Vomit
				this.HandleStackCountExceeded(managementStatus, DFStackCountExceedResult.CrashVomit);
				interruptApplication = true;
			}
		
		} else if Equals(managementStatus.itemRecordTag, n"DarkFutureManagedConsumableWeakNarcotic") {
			if currentStacksApplied + stackCount >= this.BiocorruptionConditionSystem.maxNarcoticStacksUntilDebuffPerBiocorruptionLevel[Cast<Int32>(this.BiocorruptionConditionSystem.GetConditionLevel())] {
				// Crash - Vomit
				this.HandleStackCountExceeded(managementStatus, DFStackCountExceedResult.CrashVomit);
				interruptApplication = true;
			}
		
		} else if Equals(managementStatus.itemRecordTag, n"DarkFutureManagedConsumableStrongNarcotic") {
			if currentStacksApplied + stackCount >= this.BiocorruptionConditionSystem.maxNarcoticStacksUntilDebuffPerBiocorruptionLevel[Cast<Int32>(this.BiocorruptionConditionSystem.GetConditionLevel())] {
				// Overdose
				this.HandleStackCountExceeded(managementStatus, DFStackCountExceedResult.Overdose);
				this.NerveSystem.SetOverdoseBehavior(true);
				interruptApplication = true;
			}
		}
		
		let i: Uint32 = 0u;
		let needValue: Float = this.GetNeedValue();
		if !interruptApplication {
			while i < stackCount {
				// Keep track of the actual amount of Energy changed, so that we can subtract it later.
				
				// We don't handle clamping to 0, because this would cause a Blackout anyway.
				let energyAmount: Float = managementStatus.change;
				if energyAmount + needValue > this.GetNeedMax() {
					energyAmount = this.GetNeedMax() - needValue;
				}
				needValue += energyAmount;
				totalEnergyAmount += energyAmount;

				ArrayPush(this.energyManagementActiveEffects, DFEnergyManagementStatus(managementStatus.type, managementStatus.effect, managementStatus.itemRecordTag, energyAmount, managementStatus.maxStacks));

				// Apply the stack.
				// TODO - You don't know if we should be applying the regular effect, the lasting effect, or just a tolerance stack here. Must be checked earlier.
				StatusEffectHelper.ApplyStatusEffect(this.player, managementStatus.effect);

				i += 1u;
			}

			// If this was from a Timeskip, don't actually change the value.
			if isFromTimeskip {
				DFLog(this, "================== FROM TIMESKIP ==================: Not actually changing Energy!");
				totalEnergyAmount = 0.0;
			}
			
			if contextuallyDelayed {
				let queuedChange: DFQueuedNeedValueChange;
				queuedChange.value = totalEnergyAmount;
				queuedChange.forceMomentaryUIDisplay = true;
				this.QueueContextuallyDelayedNeedValueChange(queuedChange);
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

			DFLog(this, "energyManagementActiveEffects - " + ToString(this.energyManagementActiveEffects));
		}

		return stackCount;
	}

	private final func HandleStackCountExceeded(managementStatus: DFEnergyManagementStatus, result: DFStackCountExceedResult) -> Void {
		 
	}
	*/

	public final func GetItemEnergyChangePreviewAmountWithCrashInfo(itemRecord: wref<Item_Record>) -> DFEnergyChangePreview {
		//DFProfile();
		let r: DFEnergyChangePreview;
		let pipelineResult: DFManagedEffectPipelineResult = this.PlayerStateService.ManagedConsumablePipeline(itemRecord);
		if pipelineResult.managedEffectStateIndex == -1 || Equals(pipelineResult.managedEffectItemDef.itemRecordTag, n"") { return r; }
		
		// If the stack count granted is random, we can't know the effect on the player's Energy.
		if Equals(pipelineResult.managedEffectItemDef.stackCountDef.mode, DFManagedEffectStackCountMode.Random) { 
			r.indeterminate = true;
			return r; 
		}
		
		// If no active effect applied, bail.
		if pipelineResult.activeStacksToApply == 0 { return r; }
		
		let change: Float = pipelineResult.managedEffectItemDef.energyChangeWhileActive;
		if Equals(pipelineResult.type, DFManagedEffectType.Alcohol) {
			change += this.CyberwareService.GetAlcoholEnergyLossBonus();
		}

		r.change = Cast<Float>(pipelineResult.activeStacksToApply) * change;

		if pipelineResult.triggerExcessStackEffect {
			r.wouldCrash = true;
		}

		return r;
	}

	// TODO - Convert effect to remove all stacks at once and simplify
	// TODO - Actually, think I'm moving away from that approach. Maybe?
	/*public final func OnEnergizedEffectRemoved() -> Void {
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
	}*/

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
			targetHoursInRange = 12.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue2V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue1V2 - this.Settings.basicNeedThresholdValue2V2;
			targetHoursInRange = 4.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue3V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue2V2 - this.Settings.basicNeedThresholdValue3V2;
			targetHoursInRange = 4.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue4V2 {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue3V2 - this.Settings.basicNeedThresholdValue4V2;
			targetHoursInRange = 4.0;

		} else {
			totalPointLossInRange = this.Settings.basicNeedThresholdValue4V2;
			targetHoursInRange = 2.0;
		}

		return (totalPointLossInRange / ((targetHoursInRange * 60.0) / 5.0) * -1.0) * (this.Settings.energyLossRatePctV2 / 100.0);

		// OLD:
		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		//return (100.0 / ((30.0 * 60.0) / 5.0) * -1.0) * (this.Settings.energyLossRatePctV2 / 100.0);
	}

	public final func GetNeedChangeWithRecoverLimit(needValue: Float, timeSkipType: DFTimeSkipType, hasEuphoria: Bool, hasRestless: Bool, alreadyDelayedAmount: Float) -> DFNeedChangeWithRecoverLimit {
		//DFProfile();
		let hasInsomniaNow: Bool = this.NerveSystem.GetNeedStage() >= this.NerveSystem.insomniaNeedStageThreshold;
		let hasHungerThirstPangsNow: Bool = this.NutritionSystem.GetNeedStage() >= this.NutritionSystem.hungerPangNeedStageThreshold || this.HydrationSystem.GetNeedStage() >= this.HydrationSystem.thirstPangNeedStageThreshold;
		let amountToChange: Float = 0.0;
		let delayedNeedLoss: Float = 0.0;
		let isNeedReducing: Bool = false;
		let wasSleeping: Bool = false;
		let showLock: Bool = false;

		if DFIsSleeping(timeSkipType) {
			let recoverLimit: Float;
			if (hasInsomniaNow || hasHungerThirstPangsNow) && NotEquals(timeSkipType, DFTimeSkipType.Blackout) {
				// If Distressed at the moment Sleep started, and not blacking out, reduce Energy down to 50, but not below.
				recoverLimit = this.restlessEnergyRecoveryLimit;
				wasSleeping = true;

			} else if Equals(timeSkipType, DFTimeSkipType.FullSleep) {
				// The player always recovers Energy, even if becoming Distressed while asleep.
				recoverLimit = 100.0;
				wasSleeping = true;
				
			} else if Equals(timeSkipType, DFTimeSkipType.LimitedSleep) {
				recoverLimit = this.Settings.limitedEnergySleepingInVehicles;
				wasSleeping = true;

			} else if Equals(timeSkipType, DFTimeSkipType.Blackout) {
				recoverLimit = this.blackoutEnergyRecoveryLimit;
			}

			if wasSleeping && hasRestless {
				if recoverLimit > this.restlessEnergyRecoveryLimit  {
					recoverLimit = this.restlessEnergyRecoveryLimit;
				}
			}

			if needValue > recoverLimit {
				// Above the recovery limit, reduce Energy.
				isNeedReducing = true;

			} else {
				if Equals(timeSkipType, DFTimeSkipType.Blackout) {
					// TODO: Temp
					amountToChange = 30.0 + Cast<Float>(RandRangeInclusive(2, 7));
				} else {
					amountToChange = this.GetEnergySleepingRecoveryAmountAtIteration(needValue);
				}
				
				if needValue + amountToChange >= recoverLimit {
					amountToChange = recoverLimit - needValue;

					if wasSleeping && (hasRestless || hasInsomniaNow || hasHungerThirstPangsNow) {
						// We are sleeping and we have Restless, and we're capped at the recovery limit;
						// show the lock.
						showLock = true;
					} else if Equals(timeSkipType, DFTimeSkipType.LimitedSleep) && recoverLimit == this.Settings.limitedEnergySleepingInVehicles {
						// Sleeping in a vehicle, show the lock.
						showLock = true;
					}
				}
			}
			
		} else {
			isNeedReducing = true;
		}

		if isNeedReducing {
			if hasEuphoria {
				// Get the change taking into account the already delayed amount,
				// because the loss rate is non-linear.
				needValue += alreadyDelayedAmount;
				delayedNeedLoss = this.GetEnergyChange(needValue);
			} else {
				amountToChange = this.GetEnergyChange(needValue);
			}
		}

		return DFNeedChangeWithRecoverLimit(amountToChange, delayedNeedLoss, showLock);
	}

	private final func GetEnergySleepingRecoveryAmountAtIteration(currentEnergy: Float) -> Float {
		//DFProfile();
		// Regain points non-linearly.

		let totalPointRecoveryInRange: Float;
		let targetSleepingHoursInRange: Float;
		if currentEnergy > this.Settings.basicNeedThresholdValue1V2 {
			totalPointRecoveryInRange = 100.0 - this.Settings.basicNeedThresholdValue1V2;
			targetSleepingHoursInRange = 4.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue2V2 {
			totalPointRecoveryInRange = this.Settings.basicNeedThresholdValue1V2 - this.Settings.basicNeedThresholdValue2V2;
			targetSleepingHoursInRange = 3.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue3V2 {
			totalPointRecoveryInRange = this.Settings.basicNeedThresholdValue2V2 - this.Settings.basicNeedThresholdValue3V2;
			targetSleepingHoursInRange = 2.0;

		} else if currentEnergy > this.Settings.basicNeedThresholdValue4V2 {
			totalPointRecoveryInRange = this.Settings.basicNeedThresholdValue3V2 - this.Settings.basicNeedThresholdValue4V2;
			targetSleepingHoursInRange = 2.0;

		} else {
			totalPointRecoveryInRange = this.Settings.basicNeedThresholdValue4V2;
			targetSleepingHoursInRange = 1.0;
		}

		return (totalPointRecoveryInRange / targetSleepingHoursInRange) / 12.0;
	}

	public final func GetRestlessEnergyRecoveryLimit() -> Float {
		//DFProfile();
		return this.restlessEnergyRecoveryLimit;
    }

	public final func RemoveCrashDurationByHours(hours: Int32) -> Void {
		//DFProfile();
		// TODO
		/*
		let stacksToClear: Uint32 = Cast<Uint32>(hours * 2);
		this.ClearCrashStacks(stacksToClear);
		*/
	}
}

// -----------------------------------------------------------------------------
// DFHydrationSystem
// -----------------------------------------------------------------------------
//
// - Hydration Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
	DFRunGuard,
	DFIsSleeping
}
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFTimeSkipData,
	DFTimeSkipType
}
import DarkFuture.Addictions.DFAddictionSystemBase
import DarkFuture.Conditions.{
	DFBiocorruptionConditionSystem,
	DFBiocorruptionDelayedNeedLossDatum
}
import DarkFuture.Services.{
	DFCyberwareService,
	DFGameStateService,
	DFPlayerStateService,
	DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback,
	DFNotificationCallback,
	DFNotification,
	DFAudioCue,
	DFBarUIDisplay,
	DFNotificationService,
	DFManagedEffectExcessStackDef,
	DFManagedEffectExcessStackItemActionType,
	DFManagedEffectItemDefinition
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.{
	DFSettings,
	DFCrashAnimSetting
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
	//DFProfile();
    let effectID: TweakDBID = evt.staticData.GetID();
	if Equals(effectID, t"BaseStatusEffect.Sated") {
		StatusEffectHelper.RemoveStatusEffect(this, t"BaseStatusEffect.Sated");
		StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.Sated");
	}

	return wrappedMethod(evt);
}

class DFHydrationSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		//DFProfile();
		return DFHydrationSystem.Get();
	}
}

public final class DFHydrationSystem extends DFNeedSystemBase {
	public const let thirstPangNeedStageThreshold: Int32 = 4;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHydrationSystem> {
		//DFProfile();
		let instance: ref<DFHydrationSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFHydrationSystem>()) as DFHydrationSystem;
		return instance;
	}

	public final static func Get() -> ref<DFHydrationSystem> {
		//DFProfile();
		return DFHydrationSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}
	
	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		super.DoPostSuspendActions();
		this.PlayerStateService.UpdateStaminaCosts();
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
			t"DarkFutureStatusEffect.HydrationPenalty_01",
			t"DarkFutureStatusEffect.HydrationPenalty_02",
			t"DarkFutureStatusEffect.HydrationPenalty_03",
			t"DarkFutureStatusEffect.HydrationPenalty_04"
		];
	}

	//
	//  Required Overrides
	//
	private final func OnUpdateActual() -> Void {
		//DFProfile();
		DFLog(this, "OnUpdateActual");
		if !StatusEffectSystem.ObjectHasStatusEffect(this.player, this.GetBonusEffectTDBID()) {
			let props: DFChangeNeedValueProps;

			if this.BiocorruptionConditionSystem.GetHasEuphoria() {
				props.delayPercent = 1.0;
			}

			let change: Float = this.GetHydrationChange();
			this.ChangeNeedValue(change, props);
		}
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		//DFProfile();
		DFLog(this, "OnTimeSkipFinishedActual");

		let queuedChange: DFQueuedNeedValueChange;
		queuedChange.value = data.targetNeedValues.hydration.value;
		queuedChange.targetDelayedValue = data.targetNeedValues.hydration.delayedValue;
		queuedChange.targetValueMode = true;
		queuedChange.skipSevereNeedMessage = data.skipSevereNeedMessage;

		this.QueueContextuallyDelayedNeedValueChange(queuedChange);
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.hydration.value != 0.0 {
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;
			changeNeedValueProps.isSoftCapRestrictedChange = true;

			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.hydration), changeNeedValueProps);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		//DFProfile();
		return DFHUDBarType.Hydration;
	}

	private final func GetNeedType() -> DFNeedType {
		//DFProfile();
		return DFNeedType.Hydration;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		//DFProfile();
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
		
		let notification: DFNotification;
		if stage >= 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_effort_short", 10);
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Hydration, true, false, false, false);
			notification.callback = DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback.Create();
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_curious", 20);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_phone", 20);
				}
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Hydration, false, true, false, false);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_inhale_post_drink", 30);
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureHydrationNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		//DFProfile();
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		//DFProfile();
		return n"DarkFutureNeedHydration";
	}

	private final func GetTutorialTitleKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialCombinedNeedsTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialCombinedNeeds";
	}

	private func GetHasShownTutorialForNeed() -> Bool {
		//DFProfile();
		return this.PlayerStateService.hasShownBasicNeedsTutorial;
	}

	private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		//DFProfile();
		this.PlayerStateService.hasShownBasicNeedsTutorial = hasShownTutorial;
	}

	private final func GetBonusEffectTDBID() -> TweakDBID {
		//DFProfile();
		return t"DarkFutureStatusEffect.Sated";
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
		if data.depleteHydration {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			let props: DFChangeNeedValueProps;
			props.uiFlags = uiFlags;
			
			if NotEquals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.Off) {
				props.skipSevereNeedMessage = true;
			}

			this.ChangeNeedValue(this.GetAccumulatedDelayedNeedLoss(), props);
			this.currentDelayedNeedLoss = 0.0;
		}
	}

	public final func GetNeedMaxAfterItemUse(itemRecord: wref<Item_Record>) -> Float {
		//DFProfile();
		let needMax: Float = 100.0;

		if this.BiocorruptionConditionSystem.GetHasEuphoria() {
			return needMax;
		}

		if IsDefined(itemRecord) {
			let effectiveCrashStackCount: Int32 = Max(Cast<Int32>(this.BiocorruptionConditionSystem.GetLastKnownCrashStackCount()) - this.BiocorruptionConditionSystem.GetCrashSuppressionStackCount(itemRecord), 0);
			needMax -= 5.0 * Cast<Float>(effectiveCrashStackCount);
		}

		return needMax;
	}

	public final func GetCalculatedNeedMax() -> Float {
		//DFProfile();
		return this.GetCalculatedBasicNeedMaxInProvidedState(
					Cast<Int32>(this.BiocorruptionConditionSystem.GetLastKnownCrashStackCount()),
					this.BiocorruptionConditionSystem.GetCrashSuppressionStackCount(),
					this.BiocorruptionConditionSystem.GetHasEuphoria());
	}

	//
	//	Overrides
	//
	public final func RefreshNeedStatusEffects() -> Void {
		//DFProfile();
		super.RefreshNeedStatusEffects();

		// Set effects that can't be applied via a Status Effect.
		this.PlayerStateService.UpdateStaminaCosts();
	}

	//
	//  System-Specific Methods
	//
	public final func GetHydrationChange() -> Float {
		//DFProfile();
		// Subtract 100 points every 18 in-game hours.

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		let loss: Float = (100.0 / ((18.0 * 60.0) / 5.0) * -1.0) * (this.Settings.hydrationLossRatePct / 100.0);
		
		return loss;
	}

	public final func GetNeedChangeWithRecoverLimit(needValue: Float, isSleeping: Bool, hasEuphoria: Bool) -> DFNeedChangeWithRecoverLimit {
		//DFProfile();
		let amountToChange: Float = 0.0;
		let needLoss: Float = 0.0;
		let delayedNeedLoss: Float = 0.0;

		amountToChange = this.GetHydrationChange();

		// If sleeping, reduce the change amount.
		if isSleeping {
			amountToChange *= this.sleepingReduceMetabolismMult;
		}

		if hasEuphoria {
			delayedNeedLoss = amountToChange;
		} else {
			needLoss = amountToChange;
		}

		return DFNeedChangeWithRecoverLimit(needLoss, delayedNeedLoss, false);
	}
}
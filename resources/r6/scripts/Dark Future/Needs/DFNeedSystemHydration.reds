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
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFTimeSkipData
}
import DarkFuture.Services.{
	DFCyberwareService,
	DFGameStateService,
	DFPlayerStateService,
	DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback,
	DFNotificationCallback,
	DFNotification,
	DFAudioCue,
	DFUIDisplay,
	DFNotificationService
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let effectID: TweakDBID = evt.staticData.GetID();
	let mainSystemEnabled: Bool = DFSettings.Get().mainSystemEnabled;
	if Equals(effectID, t"DarkFutureStatusEffect.Sated") && mainSystemEnabled {
        DFHydrationSystem.Get().RegisterBonusEffectCheckCallback();
	} else if Equals(effectID, t"BaseStatusEffect.Sated") && !mainSystemEnabled {
		// The base game Hydrated effect was applied while Dark Future was disabled - Apply the
		// Dark Future variant instead.
		StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.Sated");
	}

	return wrappedMethod(evt);
}

class DFHydrationSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFHydrationSystem.Get();
	}
}

public final class DFHydrationSystem extends DFNeedSystemBase {
	private let NerveSystem: ref<DFNerveSystem>;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHydrationSystem> {
		let instance: ref<DFHydrationSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Needs.DFHydrationSystem") as DFHydrationSystem;
		return instance;
	}

	public final static func Get() -> ref<DFHydrationSystem> {
		return DFHydrationSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}
	
	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.PlayerStateService.UpdateStaminaCosts();
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
		DFLog(this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetHydrationChange());
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		DFLog(this, "OnTimeSkipFinishedActual");

		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.hydration.value - this.GetNeedValue());
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.hydration.value != 0.0 {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;
			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.hydration), uiFlags);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Hydration;
	}

	private final func GetNeedType() -> DFNeedType {
		return DFNeedType.Hydration;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
		
		let notification: DFNotification;
		if stage >= 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_effort_short", 10);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Hydration, true, false);
			notification.callback = DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback.Create();
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_curious", 20);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_bump", 20);
				}
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Hydration, false, true);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_inhale_post_drink", 30);
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		return n"DarkFutureHydrationNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		return n"DarkFutureNeedHydration";
	}

	public final func CheckIfBonusEffectsValid() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState(this, true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.Sated") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Sated");
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
	//	Overrides
	//
	private final func RefreshNeedStatusEffects() -> Void {
		super.RefreshNeedStatusEffects();

		// Set effects that can't be applied via a Status Effect.
		this.PlayerStateService.UpdateStaminaCosts();
	}

	//
	//  System-Specific Methods
	//
	private final func GetHydrationChange() -> Float {
		// Subtract 100 points every 18 in-game hours.

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		return (100.0 / ((20.0 * 60.0) / 5.0) * -1.0) * (this.Settings.hydrationLossRatePct / 100.0);
	}
}
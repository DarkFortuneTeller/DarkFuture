// -----------------------------------------------------------------------------
// DFNutritionSystem
// -----------------------------------------------------------------------------
//
// - Nutrition Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
	RunGuard
}
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFTimeSkipData
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
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let effectID: TweakDBID = evt.staticData.GetID();
	if Equals(effectID, t"BaseStatusEffect.WellFed") {
        DFNutritionSystem.Get().RegisterBonusEffectCheckCallback();
	}

	return wrappedMethod(evt);
}

public final class DFNutritionSystemVFXStopCallback extends DFNotificationCallback {
	public static func Create() -> ref<DFNutritionSystemVFXStopCallback> {
		return new DFNutritionSystemVFXStopCallback();
	}

	public final func Callback() -> Void {
		let NutritionSystem: wref<DFNutritionSystem> = DFNutritionSystem.Get();
		RegisterDFDelayCallback(NutritionSystem.DelaySystem, InsufficientNeedFXStopDelayCallback.Create(NutritionSystem), NutritionSystem.insufficientNeedFXStopDelayID, NutritionSystem.insufficientNeedFXStopDelayInterval);
	}
}

class DFNutritionSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFNutritionSystem.Get();
	}
}

public final class DFNutritionSystem extends DFNeedSystemBase {
	private let insufficientNeedFXStopDelayInterval: Float = 2.1;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNutritionSystem> {
		let instance: ref<DFNutritionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Needs.DFNutritionSystem") as DFNutritionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNutritionSystem> {
		return DFNutritionSystem.GetInstance(GetGameInstance());
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

	private func SetupData() -> Void {
		this.needStageThresholdDeficits = [15.0, 25.0, 50.0, 75.0, 100.0];
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.NutritionPenalty_01",
			t"DarkFutureStatusEffect.NutritionPenalty_02",
			t"DarkFutureStatusEffect.NutritionPenalty_03",
			t"DarkFutureStatusEffect.NutritionPenalty_04"
		];
	}

    //
	//  Required Overrides
	//
    private final func OnUpdateActual() -> Void {
		DFLog(this.debugEnabled, this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetNutritionChange());
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		DFLog(this.debugEnabled, this, "OnTimeSkipFinishedActual");
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nutrition.value - this.GetNeedValue());
	}

	private final func OnItemConsumedActual(itemData: wref<gameItemData>) {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemData);

		if consumableNeedsData.nutrition.value != 0.0 {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = true;
			uiFlags.forceBright = true;
			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.nutrition), uiFlags);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Nutrition;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this.debugEnabled, this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;
		if stage == 4 || stage == 3 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_effort_long", 10);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_effort", 10);
				}
			}

			if this.Settings.nutritionNeedVFXEnabled {
				notification.vfx = new DFVisualEffect(n"status_bleeding", DFNutritionSystemVFXStopCallback.Create());
			}
			notification.ui = new DFUIDisplay(DFHUDBarType.Nutrition, true, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_greet", 20);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_bump", 20);
				}
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Nutrition, false, true);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_phone", 30);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_exhale_02", 30);
				}
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		return n"DarkFutureNutritionNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		return n"DarkFutureNeedNutrition";
	}

	public final func CheckIfBonusEffectsValid() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState("CheckIfBonusEffectsValid", true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.WellFed") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.WellFed");
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
    //  System-Specific Methods
    //
    private final func GetNutritionChange() -> Float {
		// Subtract 100 points every 24 in-game hours.

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		let value: Float = (100.0 / ((24.0 * 60.0) / 5.0) * -1.0) * (this.Settings.nutritionLossRatePct / 100.0);
		return value;
	}

    //
    //  Callback Handlers
    //
	public final func OnInsufficientNeedFXStop() {
        GameObjectEffectHelper.StopEffectEvent(this.player, n"status_bleeding");
    }
}
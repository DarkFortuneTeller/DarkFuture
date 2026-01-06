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
	DFRunGuard
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
	//DFProfile();
    let effectID: TweakDBID = evt.staticData.GetID();
	let mainSystemEnabled: Bool = DFSettings.Get().mainSystemEnabled;
	if Equals(effectID, t"DarkFutureStatusEffect.WellFed") && mainSystemEnabled {
        DFNutritionSystem.Get().RegisterBonusEffectCheckCallback();
	} else if Equals(effectID, t"BaseStatusEffect.WellFed") && !mainSystemEnabled {
		// The base game Nourishment effect was applied while Dark Future was disabled - Apply the
		// Dark Future variant instead.
		StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.WellFed");
	}

	return wrappedMethod(evt);
}

public final class DFNutritionSystemVFXStopCallback extends DFNotificationCallback {
	public static func Create() -> ref<DFNutritionSystemVFXStopCallback> {
		//DFProfile();
		return new DFNutritionSystemVFXStopCallback();
	}

	public final func Callback() -> Void {
		//DFProfile();
		let NutritionSystem: wref<DFNutritionSystem> = DFNutritionSystem.Get();
		RegisterDFDelayCallback(NutritionSystem.DelaySystem, InsufficientNeedFXStopDelayCallback.Create(NutritionSystem), NutritionSystem.insufficientNeedFXStopDelayID, NutritionSystem.insufficientNeedFXStopDelayInterval);
	}
}

class DFNutritionSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		//DFProfile();
		return DFNutritionSystem.Get();
	}
}

public final class DFNutritionSystem extends DFNeedSystemBase {
	public let insufficientNeedFXStopDelayInterval: Float = 2.1;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNutritionSystem> {
		//DFProfile();
		let instance: ref<DFNutritionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNutritionSystem>()) as DFNutritionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNutritionSystem> {
		//DFProfile();
		return DFNutritionSystem.GetInstance(GetGameInstance());
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
		//DFProfile();
		DFLog(this, "OnUpdateActual");
		if !StatusEffectSystem.ObjectHasStatusEffect(this.player, this.GetBonusEffectTDBID()) {
			this.ChangeNeedValue(this.GetNutritionChange());
		}
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		//DFProfile();
		DFLog(this, "OnTimeSkipFinishedActual");
		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nutrition.value - this.GetNeedValue());
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

		if consumableNeedsData.nutrition.value != 0.0 {
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;

			changeNeedValueProps.uiFlags = uiFlags;

			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.nutrition), changeNeedValueProps);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		//DFProfile();
		return DFHUDBarType.Nutrition;
	}

	private final func GetNeedType() -> DFNeedType {
		//DFProfile();
		return DFNeedType.Nutrition;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		//DFProfile();
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;
		if stage == 4 || stage == 3 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_effort_long", 10);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_effort", 10);
				}
			}

			if this.Settings.nutritionNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"status_bleeding", DFNutritionSystemVFXStopCallback.Create());
			}
			notification.ui = DFUIDisplay(DFHUDBarType.Nutrition, true, false, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_greet", 20);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_bump", 20);
				}
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Nutrition, false, true, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_phone", 30);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_exhale_02", 30);
				}
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureNutritionNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		//DFProfile();
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		//DFProfile();
		return n"DarkFutureNeedNutrition";
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
		return t"DarkFutureStatusEffect.WellFed";
	}

    //
    //  System-Specific Methods
    //
    public final func GetNutritionChange() -> Float {
		//DFProfile();
		// Subtract 100 points every 22 in-game hours.

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		let value: Float = (100.0 / ((22.0 * 60.0) / 5.0) * -1.0) * (this.Settings.nutritionLossRatePct / 100.0);
		return value;
	}

    //
    //  Callback Handlers
    //
	public final func OnInsufficientNeedFXStop() {
		//DFProfile();
        GameObjectEffectHelper.StopEffectEvent(this.player, n"status_bleeding");
    }
}
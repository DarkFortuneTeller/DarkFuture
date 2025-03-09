// -----------------------------------------------------------------------------
// DFNeedSystemBase
// -----------------------------------------------------------------------------
//
// - Base class for creating "Basic Need" gameplay systems.
//
// - Used by:
//   - DFNeedSystemHydration
//   - DFNeedSystemNutrition
//   - DFNeedSystemEnergy
//   - DFNeedSystemNerve
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.*
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
	DFMainSystem,
	DFTimeSkipData,
	DFNeedChangeDatum,
	MainSystemItemConsumedEvent
}
import DarkFuture.Gameplay.DFInteractionSystem
import DarkFuture.Services.{
	DFPlayerStateService,
	DFCyberwareService,
	DFGameStateService,
	GameState,
	DFGameStateServiceSceneTierChangedEvent,
	DFGameStateServiceFuryChangedEvent,
	DFGameStateServiceCyberspaceChangedEvent,
	DFNotificationService,
	DFMessage,
	DFMessageContext,
	DFTutorial

}
import DarkFuture.UI.{
	DFNeedHUDUIUpdate,
	DFHUDBarType,
	HUDSystemUpdateUIRequestEvent
}

public enum DFNeedType {
  None = 0,
  Hydration = 1,
  Nutrition = 2,
  Energy = 3,
  Nerve = 4
}

public struct DFNeedChangeUIFlags {
	public let forceMomentaryUIDisplay: Bool;
	public let instantUIChange: Bool;
	public let forceBright: Bool;
	public let momentaryDisplayIgnoresSceneTier: Bool;
}

public struct DFQueuedNeedValueChange {
	public let value: Float;
	public let forceMomentaryUIDisplay: Bool;
	public let effectToApplyAfterValueChange: TweakDBID;
}

public struct DFNeedValueChangedEventDatum {
	public let needType: DFNeedType;
	public let newValue: Float;
}

public class NeedUpdateDelayCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new NeedUpdateDelayCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.updateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.OnUpdate();
	}
}

public class NeedStageChangeFXStartDelayCallback extends DFDelayCallback {
	public let NeedSystemBase: wref<DFNeedSystemBase>;
	public let needStage: Int32;
	public let suppressRecoveryNotification: Bool;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>, needStage: Int32, suppressRecoveryNotification: Bool) -> ref<DFDelayCallback> {
		let self = new NeedStageChangeFXStartDelayCallback();
		self.NeedSystemBase = needSystemBase;
		self.needStage = needStage;
		self.suppressRecoveryNotification = suppressRecoveryNotification;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.needStageChangeFXStartDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.OnNeedStageChangeFXStart(this.needStage, this.suppressRecoveryNotification);
	}
}

public class InsufficientNeedFXStopDelayCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new InsufficientNeedFXStopDelayCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.insufficientNeedFXStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.OnInsufficientNeedFXStop();
	}
}

public class InsufficientNeedRepeatFXDelayCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new InsufficientNeedRepeatFXDelayCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.insufficientNeedRepeatFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.OnInsufficientNeedRepeatFX();
	}
}

public class ContextuallyDelayedNeedValueChangeDelayCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new ContextuallyDelayedNeedValueChangeDelayCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.contextuallyDelayedNeedValueChangeDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.TryToApplyContextuallyDelayedNeedValueChange();
	}
}

public class SceneTierChangedCheckFXCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new SceneTierChangedCheckFXCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.sceneTierChangedCheckFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.OnSceneTierChangedCheckFXCallback();
	}
}

public class BonusEffectCheckCallback extends DFDelayCallback {
	public let NeedSystemBase: ref<DFNeedSystemBase>;

	public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
		let self = new BonusEffectCheckCallback();
		self.NeedSystemBase = needSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.NeedSystemBase.bonusEffectCheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.NeedSystemBase.CheckIfBonusEffectsValid();
	}
}

public class UpdateHUDUIEvent extends CallbackSystemEvent {
    private let data: DFNeedHUDUIUpdate;

    public func GetData() -> DFNeedHUDUIUpdate {
        return this.data;
    }

    static func Create(data: DFNeedHUDUIUpdate) -> ref<UpdateHUDUIEvent> {
        let event = new UpdateHUDUIEvent();
        event.data = data;
        return event;
    }
}

public class NeedValueChangedEvent extends CallbackSystemEvent {
	private let data: DFNeedValueChangedEventDatum;

	public func GetData() -> DFNeedValueChangedEventDatum {
        return this.data;
    }

    static func Create(data: DFNeedValueChangedEventDatum) -> ref<NeedValueChangedEvent> {
        let event = new NeedValueChangedEvent();
        event.data = data;
        return event;
    }
}

public abstract class DFNeedSystemEventListener extends DFSystemEventListener {
	//
	// Required Overrides
	//
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		DFLogNoSystem(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	private cb func OnLoad() {
		super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemItemConsumedEvent", this, n"OnMainSystemItemConsumedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceSceneTierChangedEvent", this, n"OnGameStateServiceSceneTierChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceFuryChangedEvent", this, n"OnGameStateServiceFuryChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceCyberspaceChangedEvent", this, n"OnGameStateServiceCyberspaceChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.UI.HUDSystemUpdateUIRequestEvent", this, n"OnHUDSystemUpdateUIRequestEvent", true);
    }

	private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI());
    }

	private cb func OnGameStateServiceSceneTierChangedEvent(event: ref<DFGameStateServiceSceneTierChangedEvent>) {
		this.GetSystemInstance().OnSceneTierChanged(event.GetData());
	}

	private cb func OnGameStateServiceFuryChangedEvent(event: ref<DFGameStateServiceFuryChangedEvent>) {
		this.GetSystemInstance().OnFuryStateChanged(event.GetData());
	}

	private cb func OnGameStateServiceCyberspaceChangedEvent(event: ref<DFGameStateServiceCyberspaceChangedEvent>) {
        this.GetSystemInstance().OnCyberspaceChanged(event.GetData());
    }

	private cb func OnHUDSystemUpdateUIRequestEvent(event: ref<HUDSystemUpdateUIRequestEvent>) {
		this.GetSystemInstance().UpdateNeedHUDUI();
	}
}

public abstract class DFNeedSystemBase extends DFSystem {
    private persistent let needValue: Float = 100.0;
	
	private let MainSystem: ref<DFMainSystem>;
	private let InteractionSystem: ref<DFInteractionSystem>;
	private let GameStateService: ref<DFGameStateService>;
	private let NotificationService: ref<DFNotificationService>;
	private let CyberwareService: ref<DFCyberwareService>;
	private let PlayerStateService: ref<DFPlayerStateService>;

    private let needStageThresholdDeficits: array<Float>;
    private let needStageStatusEffects: array<TweakDBID>;
    private let queuedContextuallyDelayedNeedValueChange: array<DFQueuedNeedValueChange>;
    
	private let updateDelayID: DelayID;
    private let contextuallyDelayedNeedValueChangeDelayID: DelayID;
    private let needStageChangeFXStartDelayID: DelayID;
    private let insufficientNeedRepeatFXDelayID: DelayID;
	private let sceneTierChangedCheckFXDelayID: DelayID;
	private let bonusEffectCheckDelayID: DelayID;
	private let insufficientNeedFXStopDelayID: DelayID;

    private let updateIntervalInGameTimeSeconds: Float = 300.0;
    private let contextuallyDelayedNeedValueChangeDelayInterval: Float = 0.25;
    private let needStageChangeFXStartDelayInterval: Float = 0.1;
    private let insufficientNeedRepeatFXStage3DelayInterval: Float = 240.0;
	private let insufficientNeedRepeatFXStage4DelayInterval: Float = 120.0;
	private let sceneTierChangedCheckFXDelayInterval: Float = 2.0;
	private let bonusEffectCheckDelayInterval: Float = 0.1;
    
	private let needMax: Float = 100.0;
    private let lastNeedStage: Int32 = 0;

	//
	//	DFSystem Required Methods
	//
	private func RegisterListeners() -> Void {}
	private func UnregisterListeners() -> Void {}

	private func DoPostSuspendActions() -> Void {
		this.SuspendFX();

		// Failsafe
		if this.needValue < 10.0 {
			this.needValue = 10.0;
		}
		this.lastNeedStage = 0;

		this.ResetContextuallyDelayedNeedValueChange();
		StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetNeedStageStatusEffectTag());
	}

	private func DoPostResumeActions() -> Void {
		this.SetupData();
		this.ResetContextuallyDelayedNeedValueChange();
		this.lastNeedStage = this.GetNeedStage();
		this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
		this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
		this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		this.ReevaluateSystem();
	}

	private func DoStopActions() -> Void {}
	
	private func GetSystems() -> Void {
		let gameInstance = GetGameInstance();
		this.MainSystem = DFMainSystem.GetInstance(gameInstance);
		this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
		this.NotificationService = DFNotificationService.GetInstance(gameInstance);
		this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
		this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
	}

	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	private func RegisterAllRequiredDelayCallbacks() -> Void {
		this.RegisterUpdateCallback();
	}

	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		this.ResetContextuallyDelayedNeedValueChange();
		this.lastNeedStage = this.GetNeedStage();
		this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
		this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
		this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
	}

	private func UnregisterAllDelayCallbacks() -> Void {
		this.UnregisterUpdateCallback();
		this.UnregisterAllNeedFXCallbacks();
		this.UnregisterContextuallyDelayedNeedValueChange();
		this.UnregisterSceneTierChangedCheckFXCallback();
	}

	public final func OnPlayerDeath() -> Void {
		this.SuspendFX();
		super.OnPlayerDeath();
	}

	public func OnTimeSkipStart() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.UnregisterUpdateCallback();
		this.UnregisterAllNeedFXCallbacks();
	}

	public func OnTimeSkipCancelled() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.RegisterUpdateCallback();

		if this.GameStateService.IsValidGameState(this, true) {
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

		this.RegisterUpdateCallback();

		if this.GameStateService.IsValidGameState(this, true) {
			this.OnTimeSkipFinishedActual(data);
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		if ArrayContains(changedSettings, "needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds") || ArrayContains(changedSettings, "needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds") {
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	//
	//  Required Overrides
	//
	private func OnUpdateActual() -> Void {
		this.LogMissingOverrideError("OnUpdateActual");
	}

	private func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		this.LogMissingOverrideError("OnTimeSkipFinishedActual");
	}

	private func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		this.LogMissingOverrideError("OnItemConsumedActual");
	}

	private func GetNeedHUDBarType() -> DFHUDBarType {
		this.LogMissingOverrideError("GetNeedHUDBarType");
		return DFHUDBarType.None;
	}

	private func GetNeedType() -> DFNeedType {
		this.LogMissingOverrideError("GetNeedType");
		return DFNeedType.None;
	}

	private func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		this.LogMissingOverrideError("QueueNeedStageNotification");
    }

	private func GetSevereNeedMessageKey() -> CName {
		this.LogMissingOverrideError("GetSevereNeedMessageKey");
		return n"";
	}

	private func GetSevereNeedCombinedContextKey() -> CName {
		this.LogMissingOverrideError("GetSevereNeedCombinedContextKey");
		return n"";
	}

	private func GetNeedStageStatusEffectTag() -> CName {
		this.LogMissingOverrideError("GetNeedStageStatusEffectTag");
		return n"";
	}

	private func CheckIfBonusEffectsValid() -> Void {
		this.LogMissingOverrideError("CheckIfBonusEffectsValid");
	}

	private func GetTutorialTitleKey() -> CName {
		this.LogMissingOverrideError("GetTutorialTitleKey");
		return n"";
	}

	private func GetTutorialMessageKey() -> CName {
		this.LogMissingOverrideError("GetTutorialMessageKey");
		return n"";
	}

	private func GetHasShownTutorialForNeed() -> Bool {
		this.LogMissingOverrideError("GetHasShownTutorialForNeed");
		return false;
	}

	private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		this.LogMissingOverrideError("SetHasShownTutorialForNeed");
	}

	//
	//	RunGuard Protected Methods
	//
	public func OnUpdate() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnUpdate");

		if this.GameStateService.IsValidGameState(this) && !this.GameStateService.IsInAnyMenu() {
			this.OnUpdateActual();
		}

		this.RegisterUpdateCallback();
	}

	public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnItemConsumed");

		if this.GameStateService.IsValidGameState(this, true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.Weakened") {
				DFLog(this, "OnItemConsumed - Ignoring consumable (currently Weakened)");
				return;
			}

			this.OnItemConsumedActual(itemRecord, animateUI);
		}
	}

	public func OnSceneTierChanged(value: GameplayTier) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this, "OnSceneTierChanged value = " + ToString(value));

		this.ReevaluateSystem();

		if this.GameStateService.IsValidGameState(this) {
			this.ReapplyFX();
		} else {
			// This might be a scene tier that allows FX; check in a few seconds.
			this.RegisterSceneTierChangedCheckFXCallback();
		}
	}

	public func OnFuryStateChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this, "OnFuryStateChanged value = " + ToString(value));

		this.ReevaluateSystem();

		if Equals(value, true) {
			this.SuspendFX();
		} else {
			this.ReapplyFX();
		}
	}

	public func OnCyberspaceChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this, "OnCyberspaceChanged value = " + ToString(value));

		this.ReevaluateSystem();

		if Equals(value, true) {
			this.SuspendFX();
		} else {
			this.ReapplyFX();
		}
	}

    public final func GetNeedValue() -> Float {
		if RunGuard(this) { return -1.0; }

        return this.needValue;
    }

    public final func GetNeedMax() -> Float {
		if RunGuard(this) { return -1.0; }

        return this.needMax;
    }

    public func ChangeNeedValue(amount: Float, opt uiFlags: DFNeedChangeUIFlags, opt suppressRecoveryNotification: Bool, opt maxOverride: Float) -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "ChangeNeedValue: amount = " + ToString(amount) + ", uiFlags = " + ToString(uiFlags) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
		
		let needMax: Float = this.GetNeedMax();
		this.needMax = needMax;
		this.needValue = ClampF(this.needValue + amount, 0.0, needMax);
		this.UpdateNeedHUDUI(uiFlags.forceMomentaryUIDisplay, uiFlags.instantUIChange, uiFlags.forceBright, uiFlags.momentaryDisplayIgnoresSceneTier);

		let stage: Int32 = this.GetNeedStage();
		if NotEquals(stage, this.lastNeedStage) {
			DFLog(this, "ChangeNeedValue: Last Need stage (" + ToString(this.lastNeedStage) + ") != current stage (" + ToString(stage) + "). Refreshing status effects and FX.");
			this.RefreshNeedStatusEffects();
			this.UpdateNeedFX();
		}

		if stage > this.lastNeedStage && this.lastNeedStage < 4 && stage >= 4 {
			this.QueueSevereNeedMessage();
		}

		this.CheckIfBonusEffectsValid();
		this.TryToShowTutorial();
		
		this.lastNeedStage = stage;

		this.DispatchNeedValueChangedEvent(this.needValue);
		DFLog(this, "ChangeNeedValue: New needValue = " + ToString(this.needValue));
	}

    public final func GetNeedStage() -> Int32 {
		if RunGuard(this) { return -1; }

        return this.GetNeedStageImpl(this.needValue);
    }

    public final func GetNeedStageAtValue(needValue: Float) -> Int32 {
		if RunGuard(this) { return -1; }

        return this.GetNeedStageImpl(needValue);
    }

	private final func GetClampedNeedChangeFromData(needChange: DFNeedChangeDatum) -> Float {
		if needChange.value != 0.0 {
			let currentValue: Float = this.GetNeedValue();
			let needNewValue: Float = currentValue + needChange.value + needChange.valueOnStatusEffectApply;
			let isIncreasing: Bool = (needChange.value + needChange.valueOnStatusEffectApply) > 0.0;

			if isIncreasing {
				if currentValue >= needChange.ceiling {
					// The current value is already at or above the ceiling; don't change.
					return 0.0;
				} else {
					if needNewValue < needChange.ceiling {
						// The new value will be below the ceiling; change the full amount.
						return needChange.value;
					} else {
						// The new value will exceed the ceiling; change a portion of the requested amount.
						return needChange.ceiling - currentValue;
					}
				}
			} else {
				if currentValue <= needChange.floor {
					// The current value is already at or below the floor; don't change.
					return 0.0;
				} else {
					if needNewValue > needChange.floor {
						// The new value will be above the floor; change the full amount.
						return needChange.value;
					} else {
						// The new value will exceed the floor; change a portion of the requested amount.
						return needChange.floor - currentValue;
					}
				}
			}
		} else {
			return 0.0;
		}
	}

    public final func QueueContextuallyDelayedNeedValueChange(value: Float, opt forceMomentaryUIDisplay: Bool, opt effectToApplyAfterValueChange: TweakDBID) -> Void {
		if RunGuard(this) { return; }

		DFLog(this, "QueueContextuallyDelayedNeedValueChange value: " + ToString(value));
		
		let queuedNeedValueChange: DFQueuedNeedValueChange = new DFQueuedNeedValueChange(value, forceMomentaryUIDisplay, effectToApplyAfterValueChange);
		ArrayPush(this.queuedContextuallyDelayedNeedValueChange, queuedNeedValueChange);
		this.RegisterContextuallyDelayedNeedValueChange();
	}

    public final func TryToApplyContextuallyDelayedNeedValueChange() -> Void {
		if RunGuard(this) { return; }

		DFLog(this, "TryToApplyContextuallyDelayedNeedValueChange");
		
		let gs: GameState = this.GameStateService.GetGameState(this);

		if Equals(gs, GameState.Valid) && !this.player.IsInCombat() {
			while ArraySize(this.queuedContextuallyDelayedNeedValueChange) > 0 {
				let queuedChange: DFQueuedNeedValueChange = ArrayPop(this.queuedContextuallyDelayedNeedValueChange);
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = queuedChange.forceMomentaryUIDisplay;
				uiFlags.instantUIChange = false;
				uiFlags.forceBright = true;
				this.ChangeNeedValue(queuedChange.value, uiFlags);

				if NotEquals(queuedChange.effectToApplyAfterValueChange, t"") {
					StatusEffectHelper.ApplyStatusEffect(this.player, queuedChange.effectToApplyAfterValueChange);
				}
			}
			this.ResetContextuallyDelayedNeedValueChange();

		// If Game State only Temporarily Invalid, try again later. Otherwise, throw away this request.
		} else if Equals(gs, GameState.TemporarilyInvalid) {
			this.RegisterContextuallyDelayedNeedValueChange();
		}
	}

	public final func OnSceneTierChangedCheckFXCallback() -> Void {
		if RunGuard(this) { return; }

		if !this.InteractionSystem.ShouldAllowFX() {
			this.SuspendFX();
		}
	}

	//
	//	Private Methods
	//

	//	Status Effects
	//
	private final func GetNeedStageImpl(needValue: Float) -> Int32 {
		let needValueDeficit: Float = 100.0 - needValue;

		let i: Int32 = 0;
		while i < ArraySize(this.needStageThresholdDeficits) {
			if needValueDeficit < this.needStageThresholdDeficits[i] {
				return i;
			} else if i == ArraySize(this.needStageThresholdDeficits) - 1 && needValueDeficit <= this.needStageThresholdDeficits[i] {
				return i;
			}
			i += 1;
		}

		DFLog(this, "GetNeedStageImpl didn't resolve the current need value (" + ToString(needValue) + ") to a stage! This is a defect and should be addressed!", DFLogLevel.Error);
		return 0;
	}

	private func ReevaluateSystem() -> Void {
		this.RefreshNeedStatusEffects();
		this.UpdateNeedHUDUI();
	}

    private func RefreshNeedStatusEffects() -> Void {
		DFLog(this, "RefreshNeedStatusEffects -- Removing all Status Effects and re-applying");

		// Remove the status effects associated with this Need.
		StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetNeedStageStatusEffectTag());

        let currentValue: Float = this.needValue;
        let currentStage: Int32 = this.GetNeedStageAtValue(currentValue);

        if currentStage > 0 && this.GameStateService.IsValidGameState(this) {
            DFLog(this, "        Applying status effect " + TDBID.ToStringDEBUG(this.needStageStatusEffects[currentStage - 1]));
			StatusEffectHelper.ApplyStatusEffect(this.player, this.needStageStatusEffects[currentStage - 1]);
        }
    }

    //  UI
    //
    private final func UpdateNeedHUDUI(opt forceMomentaryDisplay: Bool, opt instantUIChange: Bool, opt forceBright: Bool, opt momentaryDisplayIgnoresSceneTier: Bool) -> Void {
        let update: DFNeedHUDUIUpdate;
		update.bar = this.GetNeedHUDBarType();
		update.newValue = this.needValue;
		update.newLimitValue = this.GetNeedMax();
		update.forceMomentaryDisplay = forceMomentaryDisplay;
		update.instant = instantUIChange;
		update.forceBright = forceBright;
		update.momentaryDisplayIgnoresSceneTier = momentaryDisplayIgnoresSceneTier;

		DFLog(this, "UpdateNeedHUDUI newValue: " + ToString(update.newValue) + ", forceMomentaryDisplay: " + ToString(update.forceMomentaryDisplay) + ", instant: " + ToString(update.instant) + ", forceBright: " + ToString(update.forceBright));

		GameInstance.GetCallbackSystem().DispatchEvent(UpdateHUDUIEvent.Create(update));
    }

	private final func TryToShowTutorial() -> Void {
        if RunGuard(this) { return; }

        if this.Settings.tutorialsEnabled && !this.GetHasShownTutorialForNeed() && this.GetNeedStage() > 0 {
			this.SetHasShownTutorialForNeed(true);
			let tutorial: DFTutorial;
			tutorial.title = GetLocalizedTextByKey(this.GetTutorialTitleKey());
			tutorial.message = GetLocalizedTextByKey(this.GetTutorialMessageKey());
			tutorial.iconID = t"";
			this.NotificationService.QueueTutorial(tutorial);
		}
	}

    //  FX
    //
	private func SuspendFX() -> Void {
		this.UnregisterAllNeedFXCallbacks();
	}

	private func ReapplyFX() -> Void {
		if this.InteractionSystem.ShouldAllowFX() {
			this.UpdateNeedFX();
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

    private func UpdateNeedFX(opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this, "UpdateNeedFX");

		let currentStage = this.GetNeedStage();
		
		if NotEquals(currentStage, this.lastNeedStage) && (currentStage > this.lastNeedStage || currentStage == 0) {
			this.RegisterNeedStageChangeFXStartCallback(currentStage, suppressRecoveryNotification);
		}

		this.UpdateInsufficientNeedRepeatFXCallback(currentStage);
	}

    private final func UpdateInsufficientNeedRepeatFXCallback(stageToCheck: Int32) -> Void {
		if RunGuard(this) { return; }
		
		DFLog(this, "UpdateInsufficientNeedRepeatFXCallback stageToCheck = " + ToString(stageToCheck));

		this.UnregisterInsufficientNeedRepeatFXCallback();

		if stageToCheck == 3 {
			this.RegisterInsufficientNeedFXRepeatStage3Callback();
		} else if stageToCheck == 4 {
			this.RegisterInsufficientNeedFXRepeatStage4Callback();
		}
	}

    private final func ResetContextuallyDelayedNeedValueChange() -> Void {
		DFLog(this, "ResetContextuallyDelayedNeedValueChange");

		ArrayClear(this.queuedContextuallyDelayedNeedValueChange);
	}

    private final func QueueSevereNeedMessage() -> Void {
		DFLog(this, "QueueSevereNeedMessage");
		if !this.Settings.needMessagesEnabled { return; }

		if this.GameStateService.IsValidGameState(this, true) {
			let message: DFMessage;
			message.key = this.GetSevereNeedMessageKey();
			message.type = SimpleMessageType.Negative;
			message.context = DFMessageContext.Need;
			message.combinedContextKey = this.GetSevereNeedCombinedContextKey();

			this.NotificationService.QueueMessage(message);
		}
	}

    private final func GetRandomRepeatCallbackOffsetTime() -> Float {
		return RandRangeF(-20.0, 20.0);
	}

    //  Registration
    //
	private final func RegisterUpdateCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NeedUpdateDelayCallback.Create(this), this.updateDelayID, this.updateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

    private final func RegisterNeedStageChangeFXStartCallback(needStage: Int32, suppressRecoveryNotification: Bool) -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NeedStageChangeFXStartDelayCallback.Create(this, needStage, suppressRecoveryNotification), this.needStageChangeFXStartDelayID, this.needStageChangeFXStartDelayInterval);
	}

    private final func RegisterInsufficientNeedFXRepeatStage3Callback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, InsufficientNeedRepeatFXDelayCallback.Create(this), this.insufficientNeedRepeatFXDelayID, this.Settings.needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds + this.GetRandomRepeatCallbackOffsetTime());
	}

	private final func RegisterInsufficientNeedFXRepeatStage4Callback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, InsufficientNeedRepeatFXDelayCallback.Create(this), this.insufficientNeedRepeatFXDelayID, this.Settings.needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds + this.GetRandomRepeatCallbackOffsetTime());
	}

    private final func RegisterContextuallyDelayedNeedValueChange() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedNeedValueChangeDelayCallback.Create(this), this.contextuallyDelayedNeedValueChangeDelayID, this.contextuallyDelayedNeedValueChangeDelayInterval);
	}

	private final func RegisterSceneTierChangedCheckFXCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SceneTierChangedCheckFXCallback.Create(this), this.sceneTierChangedCheckFXDelayID, this.sceneTierChangedCheckFXDelayInterval);
	}

	public final func RegisterBonusEffectCheckCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, BonusEffectCheckCallback.Create(this), this.bonusEffectCheckDelayID, this.bonusEffectCheckDelayInterval);
	}

    //  Unregistration
    //
	private final func UnregisterUpdateCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.updateDelayID);
	}

    private final func UnregisterAllNeedFXCallbacks() -> Void {
		DFLog(this, "UnregisterAllNeedFXCallbacks");

		this.UnregisterNeedStageChangeFXStartCallback();
		this.UnregisterInsufficientNeedRepeatFXCallback();
	}

    private final func UnregisterNeedStageChangeFXStartCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.needStageChangeFXStartDelayID);
	}

    private final func UnregisterInsufficientNeedRepeatFXCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.insufficientNeedRepeatFXDelayID);
	}

    private final func UnregisterContextuallyDelayedNeedValueChange() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedNeedValueChangeDelayID);
	}

	private final func UnregisterSceneTierChangedCheckFXCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.sceneTierChangedCheckFXDelayID);
	}

	private final func UnregisterBonusEffectCheckCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.bonusEffectCheckDelayID);
	}

    //  Callback Handlers
    //
    public final func OnNeedStageChangeFXStart(needStage: Int32, suppressRecoveryNotification: Bool) -> Void {
		DFLog(this, "OnNeedStageChangeFXStart");

		this.QueueNeedStageNotification(needStage, suppressRecoveryNotification);
		this.UpdateInsufficientNeedRepeatFXCallback(needStage);
	}

	public func OnInsufficientNeedFXStop() {
		// Override
    }

    public final func OnInsufficientNeedRepeatFX() -> Void {
		DFLog(this, "OnInsufficientNeedRepeatFX");
		let needStage: Int32 = this.GetNeedStage();

		if this.Settings.needNegativeEffectsRepeatEnabled {
			this.QueueNeedStageNotification(needStage);
		}

		this.UpdateInsufficientNeedRepeatFXCallback(needStage);
	}

	//
	//	Logging
	//
	private final func LogMissingOverrideError(funcName: String) -> Void {
		DFLog(this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}

	//
    //  Events for Dark Future Add-Ons and Mods
    //
    public final func DispatchNeedValueChangedEvent(newValue: Float) -> Void {
		let data = new DFNeedValueChangedEventDatum(this.GetNeedType(), newValue);
        GameInstance.GetCallbackSystem().DispatchEvent(NeedValueChangedEvent.Create(data));
    }
}
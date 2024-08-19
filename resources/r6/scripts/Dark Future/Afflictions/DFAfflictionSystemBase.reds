// -----------------------------------------------------------------------------
// DFAfflictionSystemBase
// -----------------------------------------------------------------------------
//
// - Base class for creating long-term affliction gameplay systems.
// - Afflictions have a single status effect that stack multiple times,
//   unlike other status effects in this system (like Needs and Addictions).
// - Afflictions do not heal on their own, and have infinite durations.
// - Afflictions can be suppressed, or cured.
//
// - Used by:
//   - DFInjuryAfflictionSystem
//   - DFTraumaAfflictionSystem
//

module DarkFuture.Afflictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.DFSettings
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
	DFMainSystem,
	DFTimeSkipData,
    DFAfflictionDatum,
    DFAfflictionUpdateDatum
}
import DarkFuture.Services.{
	DFGameStateService,
    DFNotificationService,
	DFGameStateServiceSceneTierChangedEvent,
	DFGameStateServiceFuryChangedEvent,
    DFGameStateServiceCyberspaceChangedEvent,
    PlayerStateServiceOnDamageReceivedEvent
}

enum DFAfflictionEffectTimerMode {
    Instantaneous = 0,
    UseEffectDuration = 1,
    UseScriptManagedDuration = 2
}

enum DFAfflictionCureAmount {
    AllStacks = 0,
    SingleStack = 1
}

public struct DFAfflictionSuppressionEffect {
    public let effectTag: CName = n"";
    public let suppressionTimerMode: DFAfflictionEffectTimerMode = DFAfflictionEffectTimerMode.UseEffectDuration;
    public let suppressionDurationInGameTimeSeconds: Float = 0.0;
    public let requiresMatchingStackCount: Bool = false;
}

public struct DFAfflictionCureEffect {
    public let effectID: TweakDBID = t"";
    public let cureTimerMode: DFAfflictionEffectTimerMode = DFAfflictionEffectTimerMode.Instantaneous;
    public let cureDurationInGameTimeSeconds: Float = 0.0;
}

public class AfflictionCureTimerDelayCallback extends DFDelayCallback {
	public let AfflictionSystemBase: ref<DFAfflictionSystemBase>;

	public static func Create(afflictionSystemBase: ref<DFAfflictionSystemBase>) -> ref<DFDelayCallback> {
		let self = new AfflictionCureTimerDelayCallback();
		self.AfflictionSystemBase = afflictionSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        this.AfflictionSystemBase.afflictionCureTimerDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.AfflictionSystemBase.OnAfflictionCureTimerDelayCallback(this.AfflictionSystemBase.GetAfflictionTimerUpdateIntervalInGameTimeSeconds());
	}
}

public class AfflictionSuppressionTimerDelayCallback extends DFDelayCallback {
	public let AfflictionSystemBase: ref<DFAfflictionSystemBase>;

	public static func Create(afflictionSystemBase: ref<DFAfflictionSystemBase>) -> ref<DFDelayCallback> {
		let self = new AfflictionSuppressionTimerDelayCallback();
		self.AfflictionSystemBase = afflictionSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        this.AfflictionSystemBase.afflictionSuppressionTimerDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.AfflictionSystemBase.OnAfflictionSuppressionTimerDelayCallback(this.AfflictionSystemBase.GetAfflictionTimerUpdateIntervalInGameTimeSeconds());
	}
}

public abstract class DFAfflictionSystemEventListener extends DFSystemEventListener {
	//
	// Required Overrides
	//
	private func GetSystemInstance() -> wref<DFAfflictionSystemBase> {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	private cb func OnLoad() {
        super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceSceneTierChangedEvent", this, n"OnGameStateServiceSceneTierChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceFuryChangedEvent", this, n"OnGameStateServiceFuryChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceCyberspaceChangedEvent", this, n"OnGameStateServiceCyberspaceChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceOnDamageReceivedEvent", this, n"OnPlayerStateServiceDamageReceivedEvent", true);
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

    private cb func OnPlayerStateServiceDamageReceivedEvent(event: ref<PlayerStateServiceOnDamageReceivedEvent>) {
        this.GetSystemInstance().OnDamageReceivedEvent(event.GetData());
    }
}

public abstract class DFAfflictionSystemBase extends DFSystem {
    private let MainSystem: ref<DFMainSystem>;
	private let GameStateService: ref<DFGameStateService>;
    private let NotificationService: ref<DFNotificationService>;

    private let suppressionEffect: DFAfflictionSuppressionEffect;
    private let cureEffect: DFAfflictionCureEffect;

    private persistent let currentAfflictionStacks: Uint32 = 0u;
    private persistent let currentAfflictionSuppressionDuration: Float = 0.0;
    private persistent let currentAfflictionCureDuration: Float = 0.0;
    private persistent let hasShownTutorial: Bool = false;
    private let lastSuppressed: Bool = false;
    
    private let afflictionTimerUpdateIntervalInGameTimeSeconds: Float = 300.0;
    private let afflictionSuppressionTimerDelayID: DelayID;
    private let afflictionCureTimerDelayID: DelayID;

    //
    //  DFSystem Required Methods
    //
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
    }

    private func GetSystems() -> Void {
		let gameInstance = GetGameInstance();
		this.MainSystem = DFMainSystem.GetInstance(gameInstance);
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
    }

    private func DoPostSuspendActions() -> Void {
        this.currentAfflictionStacks = 0u;
        this.currentAfflictionSuppressionDuration = 0.0;
        this.currentAfflictionCureDuration = 0.0;
        StatusEffectHelper.RemoveStatusEffect(this.player, this.GetAfflictionEffect());
        StatusEffectHelper.RemoveStatusEffect(this.player, this.cureEffect.effectID);
        this.lastSuppressed = false;
        // Suppression effects are always managed by effect durations and don't need to be removed here.
    }

    private func DoPostResumeActions() -> Void {
        this.SetupData();
        this.RefreshAfflictionStatusEffects();
    }

    private func DoStopActions() -> Void {}

    private func UnregisterAllDelayCallbacks() -> Void {
        this.UnregisterAfflictionCureTimerDelayCallback();
        this.UnregisterAfflictionSuppressionTimerDelayCallback();
    }

    //
	//  Required Overrides
	//
    public func OnDamageReceivedEvent(evt: ref<gameDamageReceivedEvent>) -> Void {
        this.LogMissingOverrideError("OnDamageReceived");
	}

    private func OnTimeSkipFinishedActual(afflictionData: DFAfflictionDatum) -> Void {
        this.LogMissingOverrideError("OnTimeSkipFinishedActual");
    }

    public func GetMaxAfflictionStacks() -> Uint32 {
        this.LogMissingOverrideError("GetMaxAfflictionStacks");
        return 0u;
    }

    public func GetAfflictionEffect() -> TweakDBID {
        this.LogMissingOverrideError("GetAfflictionEffect");
        return t"";
    }

    private func DoPostAfflictionSuppressionActions() -> Void {
        this.LogMissingOverrideError("DoPostAfflictionSuppressionActions");
    }

    private func DoPostAfflictionApplyActions() -> Void {
        this.LogMissingOverrideError("DoPostAfflictionApplyActions");
    }

    private func DoPostAfflictionCureActions() -> Void {
        this.LogMissingOverrideError("DoPostAfflictionCureActions");
    }

    private func GetTutorialTitleKey() -> CName {
		this.LogMissingOverrideError("GetTutorialTitleKey");
		return n"";
	}

	private func GetTutorialMessageKey() -> CName {
		this.LogMissingOverrideError("GetTutorialMessageKey");
		return n"";
	}

    private func CheckTutorial() -> Void {
        this.LogMissingOverrideError("CheckTutorial");
    }
    
	//
	//	RunGuard Protected Methods
	//
	public func OnSceneTierChanged(value: GameplayTier) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnSceneTierChanged value = " + ToString(value));

        this.RefreshAfflictionStatusEffects();
	}

	public func OnFuryStateChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnFuryStateChanged value = " + ToString(value));

        this.RefreshAfflictionStatusEffects();
	}

    public func OnCyberspaceChanged(value: Bool) -> Void {
		if RunGuard(this, true) { return; }
		DFLog(this.debugEnabled, this, "OnCyberspaceChanged value = " + ToString(value));

		this.RefreshAfflictionStatusEffects();
	}

    public func OnStatusEffectApplied(effectID: TweakDBID, effectTags: array<CName>) -> Void {
        if RunGuard(this, true) { return; }
        if !this.GameStateService.IsValidGameState("OnStatusEffectApplied") { return; }

        // Check Cure effects
        if Equals(effectID, this.cureEffect.effectID) {
            if Equals(this.cureEffect.cureTimerMode, DFAfflictionEffectTimerMode.Instantaneous) {

                // Hack - Injury Treatment - Handle all instantaneous cures as all stacks
                this.CureAffliction(DFAfflictionCureAmount.AllStacks);
                return;
            } else if Equals(this.cureEffect.cureTimerMode, DFAfflictionEffectTimerMode.UseScriptManagedDuration) {
                // Ignore duplicate applications
                if this.currentAfflictionCureDuration == 0.0 {
                    this.currentAfflictionCureDuration = this.cureEffect.cureDurationInGameTimeSeconds;
                    this.RegisterAfflictionCureTimerDelayCallback();
                    this.RefreshAfflictionStatusEffects();
                    return;
                }
            }
        }

        // Check Suppression effects
        if ArrayContains(effectTags, this.suppressionEffect.effectTag) {
            if this.suppressionEffect.requiresMatchingStackCount {
                let suppressionStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, effectID);
                if IsDefined(suppressionStatus) {
                    let suppressionStackCount: Uint32 = suppressionStatus.GetStackCount();
                    if suppressionStackCount >= this.GetAfflictionStacks() {
                        this.SuppressAffliction(this.suppressionEffect);
                    }
                }
            } else {
                this.SuppressAffliction(this.suppressionEffect);
            }
        }
    }

    private final func HasQualifyingSuppressionActiveStatusEffect() -> Bool {
        // We only care about catching active suppression effects that use their own effect durations.

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, this.suppressionEffect.effectTag) {
            if Equals(this.suppressionEffect.suppressionTimerMode, DFAfflictionEffectTimerMode.UseEffectDuration) {
                return true;
            }
        }

        return false;
    }

    public func OnStatusEffectRemoved(effectID: TweakDBID, effectTags: array<CName>) -> Void {
        if ArrayContains(effectTags, this.suppressionEffect.effectTag) {
            if Equals(this.suppressionEffect.suppressionTimerMode, DFAfflictionEffectTimerMode.UseEffectDuration) {
                this.RefreshAfflictionStatusEffects();
            }
        }
    }

    //
    //  System Methods
    //
    public func GetAfflictionTimerUpdateIntervalInGameTimeSeconds() -> Float {
        if RunGuard(this) { return 0.0; }

        return this.afflictionTimerUpdateIntervalInGameTimeSeconds;
    }

    public func GetAfflictionStacks() -> Uint32 {
        if RunGuard(this) { return 0u; }

        return this.currentAfflictionStacks;
    }

    public func IncrementAfflictionStacks(value: Uint32) -> Uint32 {
        if RunGuard(this) { return 0u; }

        if this.currentAfflictionStacks < this.GetMaxAfflictionStacks() {
            this.currentAfflictionStacks += value;
        }
        
        return this.currentAfflictionStacks;
    }

    public func SetAfflictionStacks(value: Uint32) -> Void {
        if RunGuard(this) { return; }

        if value >= 0u && value <= this.GetMaxAfflictionStacks() {
            this.currentAfflictionStacks = value;
        }
    }

    public func TryToApplyAfflictionStack() -> Void {
        if RunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState("TryToApplyAfflictionStack") { return; }

        if this.GetAfflictionStacks() < this.GetMaxAfflictionStacks() {
            this.IncrementAfflictionStacks(1u);
            this.RefreshAfflictionStatusEffects();
            this.CheckTutorial();
        }
    }

    private func RefreshAfflictionStatusEffects(opt skipApplyActions: Bool) -> Void {
        if RunGuard(this) { return; }
        
        let afflictionData: DFAfflictionUpdateDatum;
        afflictionData.stackCount = this.GetAfflictionStacks();
        afflictionData.cureDuration = this.GetCurrentAfflictionCureDurationInGameTimeSeconds();
        afflictionData.suppressionDuration = this.GetCurrentAfflictionSuppressionDurationInGameTimeSeconds();
        afflictionData.hasQualifyingSuppressionActiveStatusEffect = this.HasQualifyingSuppressionActiveStatusEffect();

        let isSuppressed: Bool = this.IsAfflictionSuppressed(afflictionData);
        let afflictionEffect: TweakDBID = this.GetAfflictionEffect();

        if this.GameStateService.IsValidGameState("RefreshAfflictionStatusEffects") {
            let internalStackCount: Uint32 = afflictionData.stackCount;
            if internalStackCount == 0u || isSuppressed {
                // The player should not have any stacks of the effect applied.
                if StatusEffectSystem.ObjectHasStatusEffect(this.player, afflictionEffect) {
				    StatusEffectHelper.RemoveStatusEffect(this.player, afflictionEffect);
                }
                if NotEquals(isSuppressed, this.lastSuppressed) {
                    this.DoPostAfflictionSuppressionActions();
                }
            } else if internalStackCount > 0u {
                // The player should have some number of stacks of the effect applied.
                // Due to the stack count being potentially out of date after just applying a status effect,
                // forcibly remove and reapply the effect with the correct stack count always.
                StatusEffectHelper.RemoveStatusEffect(this.player, afflictionEffect);

                let i = 0u;
                while i < afflictionData.stackCount {
                    StatusEffectHelper.ApplyStatusEffect(this.player, afflictionEffect);
                    i += 1u;
                }
                if !skipApplyActions {
                    this.DoPostAfflictionApplyActions();
                }
            }
        } else {
            if StatusEffectSystem.ObjectHasStatusEffect(this.player, afflictionEffect) {
                StatusEffectHelper.RemoveStatusEffect(this.player, afflictionEffect);
            }
        }

        this.lastSuppressed = isSuppressed;
    }

    public func IsAfflictionSuppressed(afflictionData: DFAfflictionUpdateDatum) -> Bool {
        if afflictionData.suppressionDuration > 0.0 {
            return true;

        } else if afflictionData.hasQualifyingSuppressionActiveStatusEffect {
            return true;
        }

        return false;
    }

    public func GetCurrentAfflictionSuppressionDurationInGameTimeSeconds() -> Float {
        return this.currentAfflictionSuppressionDuration;
    }

    public func SetCurrentAfflictionSuppressionDurationInGameTimeSeconds(value: Float) -> Void {
        if RunGuard(this) { return; }

        this.currentAfflictionSuppressionDuration = MaxF(value, 0.0);
    }

    public func GetCurrentAfflictionCureDurationInGameTimeSeconds() -> Float {
        return this.currentAfflictionCureDuration;
    }

    public func SetCurrentAfflictionCureDurationInGameTimeSeconds(value: Float) -> Void {
        if RunGuard(this) { return; }

        this.currentAfflictionCureDuration = MaxF(value, 0.0);
    }

    public func SuppressAffliction(suppressionEffect: DFAfflictionSuppressionEffect) -> Void {
        if RunGuard(this) { return; }

        if Equals(suppressionEffect.suppressionTimerMode, DFAfflictionEffectTimerMode.UseScriptManagedDuration) {
            // Ignore duplicate applications
            if this.currentAfflictionSuppressionDuration == 0.0 {
                this.currentAfflictionSuppressionDuration = suppressionEffect.suppressionDurationInGameTimeSeconds;
                this.RegisterAfflictionSuppressionTimerDelayCallback();
            }   
        }

        this.RefreshAfflictionStatusEffects();
    }

    public func CureAffliction(cureAmount: DFAfflictionCureAmount) -> Void {
        if Equals(cureAmount, DFAfflictionCureAmount.AllStacks) {
            this.SetAfflictionStacks(0u);
        } else if Equals(cureAmount, DFAfflictionCureAmount.SingleStack) {
            this.SetAfflictionStacks(this.GetAfflictionStacks() - 1u);
        }
        
        this.RefreshAfflictionStatusEffects();
        this.DoPostAfflictionCureActions();
    }

    public func OnTimeSkipStart() -> Void {
        this.UnregisterAllDelayCallbacks();
    }

    public func OnTimeSkipCancelled() -> Void {
        if this.GetCurrentAfflictionCureDurationInGameTimeSeconds() > 0.0 {
            this.RegisterAfflictionCureTimerDelayCallback();
        }

        if this.GetCurrentAfflictionSuppressionDurationInGameTimeSeconds() > 0.0 {
            this.RegisterAfflictionSuppressionTimerDelayCallback();
        }
    }

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipFinished");

		if this.GameStateService.IsValidGameState("DFAfflictionSystemBase:OnTimeSkipFinished", true) {
            this.OnTimeSkipFinishedActual(data.targetAfflictionValues);
            this.RefreshAfflictionStatusEffects(true);
		}

        if this.GetCurrentAfflictionCureDurationInGameTimeSeconds() > 0.0 {
            this.RegisterAfflictionCureTimerDelayCallback();
        } else {
            StatusEffectHelper.RemoveStatusEffect(this.player, this.cureEffect.effectID);
        }

        if this.GetCurrentAfflictionSuppressionDurationInGameTimeSeconds() > 0.0 {
            this.RegisterAfflictionSuppressionTimerDelayCallback();
        }
    }

    public final func OnAfflictionCureTimerDelayCallback(gameTimeSecondsToReduce: Float) -> Void {
        if this.currentAfflictionCureDuration > 0.0 {
			this.currentAfflictionCureDuration -= gameTimeSecondsToReduce;

			if this.currentAfflictionCureDuration <= 0.0 {
				this.currentAfflictionCureDuration = 0.0;
                
                // Hack - Trauma Treatment - Handle all timed cures as single stack cures
                this.CureAffliction(DFAfflictionCureAmount.SingleStack);
                StatusEffectHelper.RemoveStatusEffect(this.player, this.cureEffect.effectID);
			} else {
                this.RegisterAfflictionCureTimerDelayCallback();
            }
            DFLog(this.debugEnabled, this, "currentAfflictionCureDuration = " + ToString(this.currentAfflictionCureDuration));
		}
    }

    public final func OnAfflictionSuppressionTimerDelayCallback(gameTimeSecondsToReduce: Float) -> Void {
        if this.currentAfflictionSuppressionDuration > 0.0 {
			this.currentAfflictionSuppressionDuration -= gameTimeSecondsToReduce;

			if this.currentAfflictionSuppressionDuration <= 0.0 {
				this.currentAfflictionSuppressionDuration = 0.0;
                this.RefreshAfflictionStatusEffects();
			} else {
                this.RegisterAfflictionSuppressionTimerDelayCallback();
            }
            DFLog(this.debugEnabled, this, "currentAfflictionSuppressionDuration = " + ToString(this.currentAfflictionSuppressionDuration));
		}
    }

    //
    //  Registration
    //
    private final func RegisterAfflictionCureTimerDelayCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, AfflictionCureTimerDelayCallback.Create(this), this.afflictionCureTimerDelayID, this.GetAfflictionTimerUpdateIntervalInGameTimeSeconds() / this.Settings.timescale);
	}

    private final func RegisterAfflictionSuppressionTimerDelayCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, AfflictionSuppressionTimerDelayCallback.Create(this), this.afflictionSuppressionTimerDelayID, this.GetAfflictionTimerUpdateIntervalInGameTimeSeconds() / this.Settings.timescale);
	}

    //
    //  Unregistration
    //
    private final func UnregisterAfflictionCureTimerDelayCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.afflictionCureTimerDelayID);
	}

    private final func UnregisterAfflictionSuppressionTimerDelayCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.afflictionSuppressionTimerDelayID);
	}


    //
	//	Logging
	//
	private final func LogMissingOverrideError(funcName: String) -> Void {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}
}
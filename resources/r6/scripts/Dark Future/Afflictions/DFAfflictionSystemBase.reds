// -----------------------------------------------------------------------------
// DFAfflictionSystemBase
// -----------------------------------------------------------------------------
//
// - Base class for creating long-term affliction gameplay systems.
// - Afflictions have a single status effect that stack multiple times,
//   unlike other status effects in Dark Future (like Needs and Addictions).
// - Afflictions do not heal on their own, and have infinite durations.
//
// - Used by:
//   - DFInjuryAfflictionSystem
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
    private persistent let currentAfflictionStacks: Uint32 = 0u;
    private persistent let hasShownTutorial: Bool = false;

    private let MainSystem: ref<DFMainSystem>;
	private let GameStateService: ref<DFGameStateService>;
    private let NotificationService: ref<DFNotificationService>;

    private let cureEffect: TweakDBID;

    //
    //  DFSystem Required Methods
    //
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    private func DoStopActions() -> Void {}
    private func UnregisterAllDelayCallbacks() -> Void {}

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
        StatusEffectHelper.RemoveStatusEffect(this.player, this.GetAfflictionEffect());
    }

    private func DoPostResumeActions() -> Void {
        this.SetupData();
        this.RefreshAfflictionStatusEffects();
    }

    //
	//  Required Overrides
	//
    public func OnDamageReceivedEvent(evt: ref<gameDamageReceivedEvent>) -> Void {
        this.LogMissingOverrideError("OnDamageReceived");
	}

    public func GetMaxAfflictionStacks() -> Uint32 {
        this.LogMissingOverrideError("GetMaxAfflictionStacks");
        return 0u;
    }

    public func GetAfflictionEffect() -> TweakDBID {
        this.LogMissingOverrideError("GetAfflictionEffect");
        return t"";
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
        if !this.GameStateService.IsValidGameState("OnStatusEffectApplied", true) { return; }

        // Check Cure effects
        if Equals(effectID, this.cureEffect) {
            this.CureAffliction();
        }
    }

    //
    //  System Methods
    //
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

    public func ApplyAfflictionStack() -> Void {
        if RunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState("ApplyAfflictionStack") { return; }

        if this.GetAfflictionStacks() < this.GetMaxAfflictionStacks() {
            this.IncrementAfflictionStacks(1u);
            this.RefreshAfflictionStatusEffects();
            this.CheckTutorial();
        }
    }

    private func RefreshAfflictionStatusEffects() -> Void {
        if RunGuard(this) { return; }
        
        let afflictionData: DFAfflictionUpdateDatum;
        afflictionData.stackCount = this.GetAfflictionStacks();
        let afflictionEffect: TweakDBID = this.GetAfflictionEffect();

        if this.GameStateService.IsValidGameState("RefreshAfflictionStatusEffects") {
            let internalStackCount: Uint32 = afflictionData.stackCount;
            if internalStackCount == 0u {
                // The player should not have any stacks of the effect applied.
                if StatusEffectSystem.ObjectHasStatusEffect(this.player, afflictionEffect) {
				    StatusEffectHelper.RemoveStatusEffect(this.player, afflictionEffect);
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
            }
        } else {
            if StatusEffectSystem.ObjectHasStatusEffect(this.player, afflictionEffect) {
                StatusEffectHelper.RemoveStatusEffect(this.player, afflictionEffect);
            }
        }
    }

    public func CureAffliction() -> Void {
        this.SetAfflictionStacks(0u);
        this.RefreshAfflictionStatusEffects();
    }

    //
	//	Logging
	//
	private final func LogMissingOverrideError(funcName: String) -> Void {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}
}
// -----------------------------------------------------------------------------
// DFPlayerStateService
// -----------------------------------------------------------------------------
//
// - A service that handles general player-related state changes.
//
// - Also handles Fast Travel restrictions.
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.*
import DarkFuture.Utils.{
    RunGuard,
    HoursToGameTimeSeconds
}
import DarkFuture.Main.{ 
    DFAddictionDatum,
    DFMainSystem,
    DFTimeSkipData
}
import DarkFuture.Addictions.DFNicotineAddictionSystem
import DarkFuture.Needs.DFHydrationSystem
import DarkFuture.Needs.DFNerveSystem

enum DFOutOfBreathReason {
    LowHydrationNotification = 0,
    SprintingDashingWithLowHydration = 1,
    SprintingDashingAfterSmoking = 2
}

public struct DFPlayerDangerState {
    public let InCombat: Bool;
    public let BeingRevealed: Bool;
}

public class PlayerStateServiceOnDamageReceivedEvent extends CallbackSystemEvent {
    let data: ref<gameDamageReceivedEvent>;

    public final func GetData() -> ref<gameDamageReceivedEvent> {
        return this.data;
    }

    static func Create(data: ref<gameDamageReceivedEvent>) -> ref<PlayerStateServiceOnDamageReceivedEvent> {
        let self: ref<PlayerStateServiceOnDamageReceivedEvent> = new PlayerStateServiceOnDamageReceivedEvent();
        self.data = data;
        return self;
    }
}

public class AddictionTreatmentDurationUpdateDelayCallback extends DFDelayCallback {
    public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
		let self: ref<AddictionTreatmentDurationUpdateDelayCallback> = new AddictionTreatmentDurationUpdateDelayCallback();
        self.PlayerStateService = playerStateService;
        return self;
	}

	public func InvalidateDelayID() -> Void {
		this.PlayerStateService.addictionTreatmentDurationUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.PlayerStateService.OnAddictionTreatmentDurationUpdate(this.PlayerStateService.GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds());
	}
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent extends CallbackSystemEvent {
    public let data: Float;

    public func GetData() -> Float {
        return this.data;
    }

    static func Create(data: Float) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent> {
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent extends CallbackSystemEvent {
    public let data: DFAddictionDatum;

    public func GetData() -> DFAddictionDatum {
        return this.data;
    }

    static func Create(data: DFAddictionDatum) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent> {
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionPrimaryEffectAppliedEvent extends CallbackSystemEvent {
    public let effectID: TweakDBID;
    public let effectGameplayTags: array<CName>;

    public func GetEffectID() -> TweakDBID {
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        return this.effectGameplayTags;
    }

    static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectAppliedEvent> {
        let event = new PlayerStateServiceAddictionPrimaryEffectAppliedEvent();
        event.effectID = effectID;
        event.effectGameplayTags = effectGameplayTags;
        return event;
    }
}

public class PlayerStateServiceAddictionPrimaryEffectRemovedEvent extends CallbackSystemEvent {
    public let effectID: TweakDBID;
    public let effectGameplayTags: array<CName>;

    public func GetEffectID() -> TweakDBID {
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        return this.effectGameplayTags;
    }

    static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectRemovedEvent> {
        let event = new PlayerStateServiceAddictionPrimaryEffectRemovedEvent();
        event.effectID = effectID;
        event.effectGameplayTags = effectGameplayTags;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent extends CallbackSystemEvent {
    static func Create() -> ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent> {
        return new PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent();
    }
}

public class OutOfBreathStopCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
		let self = new OutOfBreathStopCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.PlayerStateService.outOfBreathStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.PlayerStateService.OnOutOfBreathStopCallback();
	}
}

public class OutOfBreathRecheckSprintingCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
		let self = new OutOfBreathRecheckSprintingCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.PlayerStateService.outOfBreathRecheckSprintingDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.PlayerStateService.OnOutOfBreathRecheckSprintingCallback();
	}
}

public class OutOfBreathRecheckDefaultCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
		let self = new OutOfBreathRecheckDefaultCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.PlayerStateService.outOfBreathRecheckDefaultDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.PlayerStateService.OnOutOfBreathRecheckDefaultCallback();
	}
}

public final class DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback extends DFNotificationCallback {
	public static func Create() -> ref<DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback> {
		let self: ref<DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback> = new DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback();

		return self;
	}

	public final func Callback() -> Void {
		DFPlayerStateService.Get().TryToPlayOutOfBreathEffectsFromHydrationNotification();
	}
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let nicotineAddictionSystem: ref<DFNicotineAddictionSystem> = DFNicotineAddictionSystem.Get();
    let effectID: TweakDBID = evt.staticData.GetID();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(playerStateService) {
        // DARK FUTURE ENABLED
        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectApplied(effectID, effectTags);

        } else if Equals(effectID, t"DarkFutureStatusEffect.AddictionTreatmentInhaler") {
            playerStateService.OnAddictionTreatmentDrugConsumed();
        }
    } else {
        // DARK FUTURE DISABLED
        // If Dark Future is disabled, don't allow certain player status effects to apply.
        if Equals(effectID, t"DarkFutureStatusEffect.AddictionTreatment") {
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.AddictionTreatment");
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.AddictionTreatmentInhaler");
        
        } else if Equals(effectID, t"DarkFutureStatusEffect.Sedation") {
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.Sedation");
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.SedationInhaler");
        
        } else if Equals(effectID, t"DarkFutureStatusEffect.Weakened") {
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.Weakened");

        }
    }

    // DARK FUTURE ENABLED / DISABLED
    // Update Stamina costs when Smoking effect is applied.
    if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
        playerStateService.UpdateStaminaCosts();

        // Update the effect duration based on installed cyberware.
		nicotineAddictionSystem.UpdateActiveNicotineEffectDuration(effectID);
        
    } else if Equals(effectID, t"DarkFutureStatusEffect.GlitterStaminaMovement") {
		playerStateService.ProcessGlitterConsumed();

	}

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let effectID: TweakDBID = evt.staticData.GetID();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(playerStateService) {
        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectRemoved(effectID, effectTags);
        }
    }

    // Run regardless of Dark Future enable state:
    //
    // Update Stamina costs when Smoking effect is removed.
    if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
        playerStateService.UpdateStaminaCosts();
    }

	return wrappedMethod(evt);
}

@wrapMethod(SprintEvents)
protected func OnUpdate(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	wrappedMethod(timeDelta, stateContext, scriptInterface);
	DFPlayerStateService.Get().ProcessSprintUpdate(stateContext, scriptInterface);
}

class DFPlayerStateServiceEventListeners extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFPlayerStateService> {
		return DFPlayerStateService.Get();
	}
}

public final class DFPlayerStateService extends DFSystem {
    private persistent let remainingAddictionTreatmentEffectDurationInGameTimeSeconds: Float = 0.0;
    public persistent let hasShownAddictionTutorial: Bool = false;
	public persistent let hasShownBasicNeedsTutorial: Bool = false;
	public persistent let hasShownNerveTutorial: Bool = false;

    private let BlackboardSystem: ref<BlackboardSystem>;
    private let PreventionSystem: ref<PreventionSystem>;
    private let StatPoolsSystem: ref<StatPoolsSystem>;
    private let MainSystem: ref<DFMainSystem>;
    private let HydrationSystem: ref<DFHydrationSystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let GameStateService: ref<DFGameStateService>;

    private let PSMBlackboard: ref<IBlackboard>;
    private let locomotionListener: ref<CallbackHandle>;

    private let playerInDanger: Bool = false;
    private let lastLocomotionState: Int32 = 0;

    private let addictionTreatmentDurationUpdateDelayID: DelayID;
    private let addictionTreatmentDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;

     // Low Hydration Stamina Costs
	private let playerHydrationPenalty02StaminaCostSprinting: Float = 0.035;
	private let playerHydrationPenalty02StaminaCostJumping: Float = 2.0;
	private let playerHydrationPenalty03StaminaCostSprinting: Float = 0.05;
	private let playerHydrationPenalty03StaminaCostJumping: Float = 4.0;
	private let playerHydrationPenalty04StaminaCostSprinting: Float = 0.075;
	private let playerHydrationPenalty04StaminaCostJumping: Float = 6.0;

    // Smoking Stamina Costs
    private let playerSmokingPenaltyStaminaCostSprinting: Float = 0.035;
    private let playerSmokingPenaltyStaminaCostJumping: Float = 2.0;

    // Out of Breath
    private let playingOutOfBreathFX: Bool = false;
    public let outOfBreathEffectQueued: Bool = false;

    private let outOfBreathRecheckSprintingDelayID: DelayID;
	private let outOfBreathRecheckDefaultDelayID: DelayID;
	private let outOfBreathStopDelayID: DelayID;

    private let outOfBreathRecheckSprintingDelayInterval: Float = 5.0;
	private let outOfBreathRecheckDefaultDelayInterval: Float = 0.35;
	private let outOfBreathStopDelayInterval: Float = 2.6;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFPlayerStateService> {
		let instance: ref<DFPlayerStateService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Services.DFPlayerStateService") as DFPlayerStateService;
		return instance;
	}

    public final static func Get() -> ref<DFPlayerStateService> {
        return DFPlayerStateService.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.PSMBlackboard = this.BlackboardSystem.GetLocalInstanced(attachedPlayer.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    }

    private func SetupData() -> Void {}
    
    private func RegisterListeners() -> Void {
        this.locomotionListener = this.PSMBlackboard.RegisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion, this, n"OnLocomotionStateChanged");
    }
    
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    
    private func UnregisterListeners() -> Void {
        this.PSMBlackboard.UnregisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion, this.locomotionListener);
		this.locomotionListener = null;
    }

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

    private func DoPostResumeActions() -> Void {
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
    }

    private func DoPostSuspendActions() -> Void {
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        this.RemoveAddictionTreatmentEffect(true);

        StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Sedation");
        StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Weakened");

        this.playerInDanger = false;
        this.outOfBreathEffectQueued = false;
		this.lastLocomotionState = 0;
        this.UpdateFastTravelState();
        this.ClearStaminaCosts();
		this.StopOutOfBreathEffects();
    }

    private func DoStopActions() -> Void {}

    private func GetSystems() -> Void {
        let gameInstance = GetGameInstance();
        this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
        this.PreventionSystem = this.player.GetPreventionSystem();
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
        this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
    }
    
    private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
        this.StopOutOfBreathEffects();
    }

    private func UnregisterAllDelayCallbacks() -> Void {
        this.UnregisterAddictionTreatmentDurationUpdateCallback();
		this.UnregisterOutOfBreathRecheckDefaultCallback();
		this.UnregisterOutOfBreathRecheckSprintCallback();
		this.UnregisterOutOfBreathStopCallback();
    }

    public func OnTimeSkipStart() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipStart");

		this.UnregisterAddictionTreatmentDurationUpdateCallback();
    }
    public func OnTimeSkipCancelled() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipCancelled");

		this.RegisterAddictionTreatmentDurationUpdateCallback();
    }
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipFinished");

		this.RegisterAddictionTreatmentDurationUpdateCallback();

		if this.GameStateService.IsValidGameState("DFAddictionSystemBase:OnTimeSkipFinished", true) {
            this.OnAddictionTreatmentDurationUpdateFromTimeSkip(data.targetAddictionValues);
		}
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        if ArrayContains(changedSettings, "fastTravelDisabled") {
            this.UpdateFastTravelState();
        }
    }

    //
    //  System-Specific Methods
    //
    protected cb func OnLocomotionStateChanged(value: Int32) -> Void {
		if RunGuard(this) { return; }
		
		if this.GameStateService.IsValidGameState("OnLocomotionStateChanged") {
			// 0 = Default, 2 = Sprinting, 7 = Dashing

			this.lastLocomotionState = value;

			// Out of breath effect
			if this.outOfBreathEffectQueued {
				if value == 0 {
					this.RegisterOutOfBreathRecheckDefaultCallback();
				}
			} else {
				if value == 2 {
					// Debounce VFX playback after starting to Sprint - require continuous sprinting before feeling exhausted
					this.RegisterOutOfBreathRecheckSprintCallback();
				} else if value == 7 {
					// Immediate playback after Dash
					this.outOfBreathEffectQueued = true;
				}
			}
		}
	}

    private final func UpdateFastTravelState() -> Void {
        let gameInstance = GetGameInstance();

        if this.Settings.mainSystemEnabled && this.Settings.fastTravelDisabled {
            // Used by Metro Gate scene condition
            GameInstance.GetQuestsSystem(gameInstance).SetFactStr("darkfuture_fasttravel_disabled", 1);

            // Used by DataTerms
            FastTravelSystem.AddFastTravelLock(n"DarkFuture", gameInstance);
            TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"DarkFutureUILabelMapFilterFastTravel");
            TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
        } else {
            // Used by Metro Gate scene condition
            GameInstance.GetQuestsSystem(gameInstance).SetFactStr("darkfuture_fasttravel_disabled", 0);

            // Used by DataTerms
            FastTravelSystem.RemoveFastTravelLock(n"DarkFuture", gameInstance);
            TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"UI-Menus-WorldMap-Filter-FastTravel");
            TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
        }
    }

    public final func GetPlayerDangerState() -> DFPlayerDangerState {
		let dangerState: DFPlayerDangerState;
        if this.GameStateService.IsValidGameState("GetPlayerDangerState", true) {
            dangerState.InCombat = this.player.IsInCombat();
            dangerState.BeingRevealed = this.player.IsBeingRevealed();
        }

        return dangerState;
	}

    public final func GetInDangerFromState(dangerState: DFPlayerDangerState) -> Bool {
		return dangerState.InCombat || dangerState.BeingRevealed;
	}

    public final func GetInDanger() -> Bool {
        let inDanger: Bool = this.GetInDangerFromState(this.GetPlayerDangerState());
        return inDanger;
    }

    //
    //  Stamina Costs
    //
    public final func ProcessSprintUpdate(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Void {
		// Interrupt the player's sprinting when Stamina runs out when Hydration is stage 2 or higher, or when impacted by the Smoking status effect.
		// Use caution; called roughly every frame while sprinting.

        let hasSmokingStatus: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking");
        let hasLowHydrationAndSystemRunning: Bool = (this.GameStateService.IsValidGameState("DFPlayerStateService:ProcessSprintUpdate") && this.HydrationSystem.GetNeedStage() >= 2);
        let staminaEmpty: Bool = this.StatPoolsSystem.GetStatPoolValue(Cast<StatsObjectID>(scriptInterface.executionOwner.GetEntityID()), gamedataStatPoolType.Stamina, true) <= 0.0;
		
        let shouldInterruptSprint: Bool = (hasSmokingStatus || hasLowHydrationAndSystemRunning) && staminaEmpty;
	
		if shouldInterruptSprint {
			stateContext.SetTemporaryBoolParameter(n"InterruptSprint", true, true);
    		stateContext.SetConditionBoolParameter(n"SprintToggled", false, true);
    		stateContext.SetConditionBoolParameter(n"SprintHoldCanStartWithoutNewInput", false, true);
		}
	}

    private final func UpdateStaminaCosts() {
		DFLog(this.debugEnabled, this, "UpdateStaminaCosts");

        let totalSprintCost: Float = 0.0;
        let totalJumpCost: Float = 0.0;

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNicotine") {
            totalSprintCost += this.playerSmokingPenaltyStaminaCostSprinting;
            totalJumpCost += this.playerSmokingPenaltyStaminaCostJumping;
        }

		let hydrationStage: Int32 = this.HydrationSystem.GetNeedStage();
		DFLog(this.debugEnabled, this, "    hydrationStage = " + ToString(hydrationStage));

		if hydrationStage < 2 || !this.GameStateService.IsValidGameState("UpdateStaminaCosts") {
			this.ClearStaminaCosts();
		} else if hydrationStage == 2 {
            totalSprintCost += this.playerHydrationPenalty02StaminaCostSprinting;
            totalJumpCost += this.playerHydrationPenalty02StaminaCostJumping;

		} else if hydrationStage == 3 {
            totalSprintCost += this.playerHydrationPenalty03StaminaCostSprinting;
            totalJumpCost += this.playerHydrationPenalty03StaminaCostJumping;

		} else if hydrationStage == 4 {
            totalSprintCost += this.playerHydrationPenalty04StaminaCostSprinting;
            totalJumpCost += this.playerHydrationPenalty04StaminaCostJumping;
		}

        if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != totalSprintCost {
            TweakDBManager.SetFlat(t"player.staminaCosts.sprint", totalSprintCost);
        }
        if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != totalJumpCost {
            TweakDBManager.SetFlat(t"player.staminaCosts.jump", totalJumpCost);
        }
	}

	private final func ClearStaminaCosts() -> Void {
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.sprint", 0.0);
		}
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.jump", 0.0);
		}
	}

    //
    //  Breathing Effects
    //
    private final func TryToPlayOutOfBreathEffectsFromSprinting() -> Void {
		if this.GameStateService.IsValidGameState("TryToPlayOutOfBreathEffects") {
			// Allow Nerve breathing FX to win over Out Of Breath FX.
			if this.NerveSystem.currentNerveBreathingFXStage != 0 {
				return;
			}
			
			let hydrationStage: Int32 = this.HydrationSystem.GetNeedStage();
            if hydrationStage >= 3 {
                this.StartOutOfBreathBreathingEffects(DFOutOfBreathReason.SprintingDashingWithLowHydration);
                this.RegisterOutOfBreathStopCallback();
            } else if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				this.StartOutOfBreathBreathingEffects(DFOutOfBreathReason.SprintingDashingAfterSmoking);
				this.RegisterOutOfBreathStopCallback();
			}
		}
	}

    private final func TryToPlayOutOfBreathEffectsFromHydrationNotification() -> Void {
		if this.GameStateService.IsValidGameState("TryToPlayOutOfBreathEffects") {
			// Allow Nerve breathing FX to win over Out Of Breath FX.
			if this.NerveSystem.currentNerveBreathingFXStage != 0 {
				return;
			}

            this.StartOutOfBreathBreathingEffects(DFOutOfBreathReason.LowHydrationNotification);
            this.RegisterOutOfBreathStopCallback();
		}
    }

    private final func StartOutOfBreathBreathingEffects(reason: DFOutOfBreathReason) -> Void {
		DFLog(this.debugEnabled, this, "StartOutOfBreathBreathingEffects reason = " + ToString(reason));

		if !this.playingOutOfBreathFX {
			this.playingOutOfBreathFX = true;

            // Play the camera wobble from low Hydration notifications and after sprinting or dashing with low Hydration.
			if (this.Settings.hydrationNeedVFXEnabled && Equals(reason, DFOutOfBreathReason.LowHydrationNotification)) || 
               (this.Settings.outOfBreathCameraEffectEnabled && Equals(reason, DFOutOfBreathReason.SprintingDashingWithLowHydration)) {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.BreathingHeavy");
			}

            // Play the sound effects if sprinting or dashing with low Hydration or after smoking.
			if Equals(reason, DFOutOfBreathReason.SprintingDashingWithLowHydration) ||
               Equals(reason, DFOutOfBreathReason.SprintingDashingAfterSmoking) {
				if this.Settings.outOfBreathEffectEnabled {
					let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
					evt.soundName = n"ono_v_breath_fast";
					this.player.QueueEvent(evt);
				}
			}
		}
	}

	private final func StopOutOfBreathEffects() -> Void {
		DFLog(this.debugEnabled, this, "StopOutOfBreathEffects");
		
		StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.BreathingHeavy");
		this.playingOutOfBreathFX = false;
	}

	public final func StopOutOfBreathSFXIfBreathingFXPlaying() -> Void {
		if this.playingOutOfBreathFX {
			this.StopOutOfBreathSFX();
		}
	}

	private final func StopOutOfBreathSFX() -> Void {
		DFLog(this.debugEnabled, this, "StopOutOfBreathSFX");

		// Only used when other breathing SFX need to stop this early, otherwise stops on its own
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
		evt.soundName = n"ono_v_breath_fast";
		this.player.QueueEvent(evt);
	}

    public final func OnOutOfBreathRecheckSprintingCallback() -> Void {
		if this.lastLocomotionState == 2 { // Still sprinting!
			DFLog(this.debugEnabled, this, "OnOutOfBreathRecheckSprintingCallback -- Still sprinting! Queuing breathing effect.");
			this.outOfBreathEffectQueued = true;
		}
	}

	public final func OnOutOfBreathRecheckDefaultCallback() -> Void {
		if this.lastLocomotionState == 0 { // Still default!
			DFLog(this.debugEnabled, this, "OnOutOfBreathRecheckDefaultCallback -- Still default! Try to play breathing effect.");
			this.outOfBreathEffectQueued = false;
			this.TryToPlayOutOfBreathEffectsFromSprinting();
		}
	}

	public final func OnOutOfBreathStopCallback() -> Void {
		this.StopOutOfBreathEffects();
	}

    private final func RegisterOutOfBreathStopCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathStopCallback.Create(this), this.outOfBreathStopDelayID, this.outOfBreathStopDelayInterval);
	}

    private final func RegisterOutOfBreathRecheckSprintCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckSprintingCallback.Create(this), this.outOfBreathRecheckSprintingDelayID, this.outOfBreathRecheckSprintingDelayInterval);
	}

	private final func RegisterOutOfBreathRecheckDefaultCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckDefaultCallback.Create(this), this.outOfBreathRecheckDefaultDelayID, this.outOfBreathRecheckDefaultDelayInterval);
	}

    private final func UnregisterOutOfBreathStopCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathStopDelayID);
	}

    private final func UnregisterOutOfBreathRecheckDefaultCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathRecheckDefaultDelayID);
	}

    private final func UnregisterOutOfBreathRecheckSprintCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathRecheckSprintingDelayID);
	}

    //
    //  Addiction Treatment
    //
    private final func RegisterAddictionTreatmentDurationUpdateCallback() -> Void {
        RegisterDFDelayCallback(this.DelaySystem, AddictionTreatmentDurationUpdateDelayCallback.Create(this), this.addictionTreatmentDurationUpdateDelayID, this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

	private final func UnregisterAddictionTreatmentDurationUpdateCallback() -> Void {
        UnregisterDFDelayCallback(this.DelaySystem, this.addictionTreatmentDurationUpdateDelayID);
	}

    public final func OnAddictionTreatmentDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds > 0.0 {
			this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

			if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
				this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
				this.RemoveAddictionTreatmentEffect();
			}
            DFLog(this.debugEnabled, this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));
		}

        this.DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce);
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public final func OnAddictionTreatmentDurationUpdateFromTimeSkip(addictionData: DFAddictionDatum) -> Void {
        let lastTreatmentDurationValue: Float = this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = addictionData.newAddictionTreatmentDuration;

        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        }

        if lastTreatmentDurationValue > 0.0 && this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.RemoveAddictionTreatmentEffect(true);
        }

        DFLog(this.debugEnabled, this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));
        this.DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData);
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public final func OnAddictionTreatmentDrugConsumed() -> Void {
		// Clear the Inhaler effect.
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatmentInhaler");

		// Set the duration to 12 hours.
		this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = HoursToGameTimeSeconds(12);

		// Refresh player-facing status effects.
		this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();

        // Update the Nerve limit.
        this.NerveSystem.UpdateNerveWithdrawalLimit();
	}

    private final func RemoveAddictionTreatmentEffect(opt noEvent: Bool) -> Void {
        // Refresh player-facing status effects.
        StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment");

        if !noEvent {
            this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();
        }
        
        // Update the Nerve limit.
        this.NerveSystem.UpdateNerveWithdrawalLimit();
	}

    private final func DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce: Float) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent.Create(gameTimeSecondsToReduce));
    }

    private final func DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData: DFAddictionDatum) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent.Create(addictionData));
    }

    private final func DispatchAddictionTreatmentEffectAppliedOrRemovedEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent.Create());
    }

    public final func GetRemainingAddictionTreatmentDurationInGameTimeSeconds() -> Float {
        return this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
    }

    public final func GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds() -> Float {
        return this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds;
    }

    public final func DispatchAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectAppliedEvent.Create(effectID, effectGameplayTags));
    }

    public final func DispatchAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectRemovedEvent.Create(effectID, effectGameplayTags));
    }

    //
    //  Glitter
    //
    public final func ProcessGlitterConsumed() -> Void {
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.GlitterSlowTime");
	}
}

//
//	Base Game Methods
//

//  PlayerPuppet - Let the Nerve System know when Combat state changes. (Counts as being "In Danger".)
//
@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {
	let result: Bool = wrappedMethod(newState);

	DFNerveSystem.Get().OnDangerStateChanged(DFPlayerStateService.Get().GetPlayerDangerState());

	return result;
}

//  PlayerPuppet - Let the Nerve System know when the player is being traced by a Quickhack that was uploaded undetected. (Counts as being "In Danger".)
//
@wrapMethod(PlayerPuppet)
public final func SetIsBeingRevealed(isBeingRevealed: Bool) -> Void {
	wrappedMethod(isBeingRevealed);

	DFNerveSystem.Get().OnDangerStateChanged(DFPlayerStateService.Get().GetPlayerDangerState());
}

//  GameObject - Let other systems know that a player OnDamageReceived event occurred. (Used by the Injury system.)
//
@wrapMethod(GameObject)
protected final func ProcessDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Void {
	wrappedMethod(evt);

	// If the target was the player, ignoring Pressure Wave attacks (i.e. fall damage)
	if evt.hitEvent.target.IsPlayer() && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.PressureWave) && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.Invalid) {
		GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceOnDamageReceivedEvent.Create(evt));
	}
}

//  FastTravelSystem - Ensure that calls to RemoveAllFastTravelLocks can't forcibly stomp on Dark Future's
//  Disable Fast Travel setting.
//
@wrapMethod(FastTravelSystem)
public final static func RemoveAllFastTravelLocks(game: GameInstance) -> Void {
    // While it seems this function is never called outside of debug contexts, as a failsafe, suppress
    // calls to this function if Dark Future has disabled Fast Travel.
    let settings: ref<DFSettings> = DFSettings.Get();

    if !settings.mainSystemEnabled || !settings.fastTravelDisabled {
        wrappedMethod(game);
    }
}

//  DataTermInkGameController - Continue to show the Location Name on DataTerm screens when Fast Travel
//  is disabled by Dark Future.
//
@wrapMethod(DataTermInkGameController)
private final func UpdatePointText() -> Void {
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.fastTravelDisabled {
        if this.m_point != null {
            this.m_districtText.SetLocalizedTextScript(this.m_point.GetDistrictDisplayName());
            this.m_pointText.SetLocalizedTextScript(this.m_point.GetPointDisplayName());
        }
    } else {
        wrappedMethod();
    }
}

//  FastTravelPointData - Remove Fast Travel points from being shown in the world when the setting is enabled.
//
@wrapMethod(FastTravelPointData)
public final const func ShouldShowMappinInWorld() -> Bool {
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.hideFastTravelMarkers {
        return false;
    } else {
        return wrappedMethod();
    }
}

//  WorldMapTooltipController - Display the word "Location" instead of "Fast Travel" on Fast Travel marker tooltips.
//
@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
    wrappedMethod(data, menu);
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.fastTravelDisabled {
        let fastTravelmappin: ref<FastTravelMappin>;
        let journalManager: ref<JournalManager> = menu.GetJournalManager();
        let player: wref<GameObject> = menu.GetPlayer();

        if Deref(data).controller != null && Deref(data).mappin != null && journalManager != null && player != null {
            fastTravelmappin = Deref(data).mappin as FastTravelMappin;
            if IsDefined(fastTravelmappin) {
                if fastTravelmappin.GetPointData().IsSubway() {
                    inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelMetro"));
                } else {
                    inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelDataTerm"));
                }
            }
        }
    }
}

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
    DFRunGuard,
    HoursToGameTimeSeconds,
    DFResourceUtils
}
import DarkFuture.Main.{ 
    DFAddictionDatum,
    DFMainSystem,
    DFTimeSkipData,
    DFAddictionUpdateDatum,
    MainSystemItemConsumedEvent
}
import DarkFuture.Addictions.{
    DFNicotineAddictionSystem,
    DFNarcoticAddictionSystem,
    DFAlcoholAddictionSystem,
    DFAddictionSystemBase
}
import DarkFuture.Needs.{
    DFHydrationSystem,
    DFNutritionSystem,
    DFEnergySystem,
    DFNerveSystem
}
import DarkFuture.Conditions.DFHumanityLossConditionSystem

enum DFOutOfBreathReason {
    LowHydrationNotification = 0,
    SprintingDashingWithLowHydration = 1,
    SprintingDashingAfterSmoking = 2
}

enum DFAddictionType {
    None = 0,
    Alcohol = 1,
    Nicotine = 2,
    Narcotic = 3
}

enum DFAddictionWithdrawalAnimSeverity {
    Low = 0,
    High = 1
}

public struct DFPlayerDangerState {
    public let InCombat: Bool;
    public let BeingRevealed: Bool;
}

public class PlayerStateServiceOnDamageReceivedEvent extends CallbackSystemEvent {
    let data: ref<gameDamageReceivedEvent>;

    public final func GetData() -> ref<gameDamageReceivedEvent> {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: ref<gameDamageReceivedEvent>) -> ref<PlayerStateServiceOnDamageReceivedEvent> {
        //DFProfile();
        let self: ref<PlayerStateServiceOnDamageReceivedEvent> = new PlayerStateServiceOnDamageReceivedEvent();
        self.data = data;
        return self;
    }
}

public class AddictionTreatmentDurationUpdateDelayCallback extends DFDelayCallback {
    public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self: ref<AddictionTreatmentDurationUpdateDelayCallback> = new AddictionTreatmentDurationUpdateDelayCallback();
        self.PlayerStateService = playerStateService;
        return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.PlayerStateService.addictionTreatmentDurationUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.PlayerStateService.OnAddictionTreatmentDurationUpdate(this.PlayerStateService.GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds());
	}
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent extends CallbackSystemEvent {
    public let data: Float;

    public func GetData() -> Float {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: Float) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent> {
        //DFProfile();
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent extends CallbackSystemEvent {
    public let data: DFAddictionDatum;

    public func GetData() -> DFAddictionDatum {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: DFAddictionDatum) -> ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent> {
        //DFProfile();
        let event = new PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionPrimaryEffectAppliedEvent extends CallbackSystemEvent {
    public let effectID: TweakDBID;
    public let effectGameplayTags: array<CName>;

    public func GetEffectID() -> TweakDBID {
        //DFProfile();
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        //DFProfile();
        return this.effectGameplayTags;
    }

    public static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectAppliedEvent> {
        //DFProfile();
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
        //DFProfile();
        return this.effectID;
    }

    public func GetEffectGameplayTags() -> array<CName> {
        //DFProfile();
        return this.effectGameplayTags;
    }

    public static func Create(effectID: TweakDBID, effectGameplayTags: array<CName>) -> ref<PlayerStateServiceAddictionPrimaryEffectRemovedEvent> {
        //DFProfile();
        let event = new PlayerStateServiceAddictionPrimaryEffectRemovedEvent();
        event.effectID = effectID;
        event.effectGameplayTags = effectGameplayTags;
        return event;
    }
}

public class PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent extends CallbackSystemEvent {
    public static func Create() -> ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent> {
        //DFProfile();
        return new PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent();
    }
}

public class OutOfBreathStopCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self = new OutOfBreathStopCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.PlayerStateService.outOfBreathStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.PlayerStateService.OnOutOfBreathStopCallback();
	}
}

public class OutOfBreathRecheckSprintingCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self = new OutOfBreathRecheckSprintingCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.PlayerStateService.outOfBreathRecheckSprintingDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.PlayerStateService.OnOutOfBreathRecheckSprintingCallback();
	}
}

public class OutOfBreathRecheckDefaultCallback extends DFDelayCallback {
	public let PlayerStateService: wref<DFPlayerStateService>;

	public static func Create(playerStateService: wref<DFPlayerStateService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self = new OutOfBreathRecheckDefaultCallback();
		self.PlayerStateService = playerStateService;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.PlayerStateService.outOfBreathRecheckDefaultDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.PlayerStateService.OnOutOfBreathRecheckDefaultCallback();
	}
}

public final class DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback extends DFNotificationCallback {
	public static func Create() -> ref<DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback> {
        //DFProfile();
		let self: ref<DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback> = new DFPlayerStateServiceOutOfBreathEffectsFromHydrationNotificationCallback();

		return self;
	}

	public final func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().TryToPlayOutOfBreathEffectsFromHydrationNotification();
	}
}

public class ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback extends DFDelayCallback {
    public let addictionData: DFAddictionDatum;

    public static func Create(addictionData: DFAddictionDatum) -> ref<DFDelayCallback> {
        //DFProfile();
        let self = new ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback();
		self.addictionData = addictionData;
        return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().contextuallyDelayedAddictionWithdrawalAnimationDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().TryToStartAddictionWithdrawalAnimation(this.addictionData);
	}
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    //DFProfile();
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let nicotineAddictionSystem: ref<DFNicotineAddictionSystem> = DFNicotineAddictionSystem.Get();
    let narcoticAddictionSystem: ref<DFNarcoticAddictionSystem> = DFNarcoticAddictionSystem.Get();
    let effectID: TweakDBID = evt.staticData.GetID();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(playerStateService) {
        // DARK FUTURE ENABLED

        // Addiction
        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectApplied(effectID, effectTags);

        // Stamina Costs
        } else if ArrayContains(effectTags, n"DarkFutureStaminaBooster") {
            playerStateService.UpdateStaminaCosts();
        
        /* DEPRECATED
        // Conditions
        } else if ArrayContains(effectTags, n"DarkFutureCondition") {
            this.DarkFutureRefreshConditionBuffBarIndicator();
        */
        }
    } else {
        // DARK FUTURE DISABLED
        // If Dark Future is disabled, don't allow certain player status effects to apply.

        if Equals(effectID, t"DarkFutureStatusEffect.AddictionTreatment") {
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.AddictionTreatment");
        
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
    }

    if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffectNarcotic") && !ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffectNarcoticNoDurationBuff") {
        narcoticAddictionSystem.UpdateActiveNarcoticEffectDuration(effectID);
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    //DFProfile();
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let effectID: TweakDBID = evt.staticData.GetID();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(playerStateService) {
        if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffect") {
            playerStateService.DispatchAddictionPrimaryEffectRemoved(effectID, effectTags);
        
        /* DEPRECATED
        } else if ArrayContains(effectTags, n"DarkFutureCondition") {
            this.DarkFutureRefreshConditionBuffBarIndicator();
        */
        }
    }

    // Run regardless of Dark Future enable state:
    //
    // Update Stamina costs when Smoking or Stamina Booster effect is removed.
    if ArrayContains(effectTags, n"DarkFutureAddictionPrimaryEffectNicotine") || ArrayContains(effectTags, n"DarkFutureStaminaBooster") {
        playerStateService.UpdateStaminaCosts();
    }

	return wrappedMethod(evt);
}

/* DEPRECATED
@addMethod(PlayerPuppet)
private final func DarkFutureRefreshConditionBuffBarIndicator() -> Void {
    //DFProfile();
    StatusEffectHelper.RemoveStatusEffectsWithTag(this, n"DarkFutureBuffBarConditionIndicator");

    let conditionEffects: array<ref<StatusEffect>>;
    StatusEffectHelper.GetAppliedEffectsWithTag(this, n"DarkFutureCondition", conditionEffects);
    let conditionEffectCount: Int32 = ArraySize(conditionEffects);

    if conditionEffectCount == 1 {
        StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.ConditionBuffBarIndicator");
    } else if conditionEffectCount == 2 {
        StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.ConditionBuffBarIndicator");
        StatusEffectHelper.ApplyStatusEffect(this, t"DarkFutureStatusEffect.ConditionBuffBarIndicator");
    }
}
*/

//
//  Stamina Costs
//
@addField(StaminaListener)
private let DF_SprintBlocked: Bool = false;

@wrapMethod(StaminaListener)
protected cb func OnStatPoolMinValueReached(value: Float) -> Bool {
    //DFProfile();
    // Interrupt the player's sprinting when Stamina runs out when Hydration is stage 2 or higher, or when impacted by the Smoking status effect.
    let r: Bool = wrappedMethod(value);

    if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.m_player, n"DarkFutureShouldInterruptSprintOnEmptyStamina") {
        this.DarkFutureSendPSMBoolParameter(n"InterruptSprint", true, gamestateMachineParameterAspect.Temporary);
        this.DarkFutureSendPSMBoolParameter(n"SprintHoldCanStartWithoutNewInput", true, gamestateMachineParameterAspect.Conditional);
        this.DarkFutureSendPSMBoolParameter(n"OnInterruptSprintFail_BlockSprintStartOnce", true, gamestateMachineParameterAspect.Conditional);

        this.DF_SprintBlocked = true;
        StatusEffectHelper.ApplyStatusEffect(this.m_player, t"DarkFutureStatusEffect.BlockSprint");
    }

    return r;
}

@wrapMethod(StaminaListener)
public func OnStatPoolValueChanged(oldValue: Float, newValue: Float, percToPoints: Float) -> Void {
    //DFProfile();
    wrappedMethod(oldValue, newValue, percToPoints);

    if this.DF_SprintBlocked && oldValue == 0.0 && newValue > 0.0 {
        this.DF_SprintBlocked = false;
        StatusEffectHelper.RemoveStatusEffect(this.m_player, t"DarkFutureStatusEffect.BlockSprint");
    }
}

@addMethod(StaminaListener)
protected final func DarkFutureSendPSMBoolParameter(id: CName, value: Bool, aspect: gamestateMachineParameterAspect) -> Void {
    //DFProfile();
    let psmEvent: ref<PSMPostponedParameterBool> = new PSMPostponedParameterBool();
    psmEvent.id = id;
    psmEvent.value = value;
    psmEvent.aspect = aspect;
    this.m_player.QueueEvent(psmEvent);
}

class DFPlayerStateServiceEventListeners extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFPlayerStateService> {
        //DFProfile();
		return DFPlayerStateService.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
		super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemItemConsumedEvent", this, n"OnMainSystemItemConsumedEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI());
    }
}

public final class DFPlayerStateService extends DFSystem {
    private persistent let remainingAddictionTreatmentEffectDurationInGameTimeSeconds: Float = 0.0;
    public persistent let hasShownAddictionTutorial: Bool = false;
	public persistent let hasShownBasicNeedsTutorial: Bool = false;
	public persistent let hasShownNerveTutorial: Bool = false;

    private let BlackboardSystem: ref<BlackboardSystem>;
    private let PreventionSystem: ref<PreventionSystem>;
    private let AudioSystem: ref<AudioSystem>;
    private let StatPoolsSystem: ref<StatPoolsSystem>;
    private let QuestsSystem: ref<QuestsSystem>;
    private let MainSystem: ref<DFMainSystem>;
    private let HydrationSystem: ref<DFHydrationSystem>;
    private let NutritionSystem: ref<DFNutritionSystem>;
    private let EnergySystem: ref<DFEnergySystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let GameStateService: ref<DFGameStateService>;
    private let NotificationService: ref<DFNotificationService>;
    private let AnimationService: ref<DFAnimationService>;
    private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;

    public let PSMBlackboard: ref<IBlackboard>;
    private let BlackboardDefs: ref<AllBlackboardDefinitions>;
    private let HUDProgressBarBlackboard: ref<IBlackboard>;
    private let locomotionListener: ref<CallbackHandle>;

    private const let criticalNeedFXThreshold: Float = 10.0;
    private let playingCriticalNeedFX: Bool = false;

    private let playerInDanger: Bool = false;
    private let lastLocomotionState: Int32 = 0;

    private const let addictionTreatmentEffectDurationInGameHours: Int32 = 12;
    public let addictionTreatmentDurationUpdateDelayID: DelayID;
    public let contextuallyDelayedAddictionWithdrawalAnimationDelayID: DelayID;
    private let addictionTreatmentDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;
    private let contextuallyDelayedAddictionWithdrawalAnimationDelayInterval: Float = 0.25;

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

    public let outOfBreathRecheckSprintingDelayID: DelayID;
	public let outOfBreathRecheckDefaultDelayID: DelayID;
	public let outOfBreathStopDelayID: DelayID;

    private let outOfBreathRecheckSprintingDelayInterval: Float = 5.0;
	private let outOfBreathRecheckDefaultDelayInterval: Float = 0.35;
	private let outOfBreathStopDelayInterval: Float = 2.6;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFPlayerStateService> {
        //DFProfile();
		let instance: ref<DFPlayerStateService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFPlayerStateService>()) as DFPlayerStateService;
		return instance;
	}

    public final static func Get() -> ref<DFPlayerStateService> {
        //DFProfile();
        return DFPlayerStateService.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.BlackboardDefs = GetAllBlackboardDefs();
        this.PSMBlackboard = this.BlackboardSystem.GetLocalInstanced(attachedPlayer.GetEntityID(), this.BlackboardDefs.PlayerStateMachine);
        this.HUDProgressBarBlackboard = this.BlackboardSystem.Get(this.BlackboardDefs.UI_HUDProgressBar);
    }

    public func SetupData() -> Void {}
    
    private func RegisterListeners() -> Void {
        //DFProfile();
        this.locomotionListener = this.PSMBlackboard.RegisterListenerInt(this.BlackboardDefs.PlayerStateMachine.Locomotion, this, n"OnLocomotionStateChanged");
    }
    
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    
    private func UnregisterListeners() -> Void {
        //DFProfile();
        this.PSMBlackboard.UnregisterListenerInt(this.BlackboardDefs.PlayerStateMachine.Locomotion, this.locomotionListener);
		this.locomotionListener = null;
    }

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

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
        this.SetAddictionTreatmentEffectDuration(this.addictionTreatmentEffectDurationInGameHours);
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        this.RefreshAddictionTreatmentEffect();

        StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Weakened");

        this.playerInDanger = false;
        this.outOfBreathEffectQueued = false;
		this.lastLocomotionState = 0;
        this.UpdateFastTravelState();
        this.ClearStaminaCosts();
		this.StopOutOfBreathEffects();
        this.StopCriticalNeedEffects(true);
    }

    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance = GetGameInstance();
        this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
        this.PreventionSystem = this.player.GetPreventionSystem();
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
        this.AudioSystem = GameInstance.GetAudioSystem(gameInstance);
        this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
        this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.AnimationService = DFAnimationService.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
    }
    
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.RegisterAddictionTreatmentDurationUpdateCallback();
        this.UpdateFastTravelState();
        this.StopOutOfBreathEffects();
        this.ShowIncompatibilityWarnings();
        this.SetAddictionTreatmentEffectDuration(this.addictionTreatmentEffectDurationInGameHours);
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterAddictionTreatmentDurationUpdateCallback();
		this.UnregisterOutOfBreathRecheckDefaultCallback();
		this.UnregisterOutOfBreathRecheckSprintCallback();
		this.UnregisterOutOfBreathStopCallback();
        this.UnregisterContextuallyDelayedAddictionWithdrawalAnimation();
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.UnregisterAddictionTreatmentDurationUpdateCallback();
    }

    public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

		this.RegisterAddictionTreatmentDurationUpdateCallback();

		if this.GameStateService.IsValidGameState(this, true) {
            this.OnAddictionTreatmentDurationUpdateFromTimeSkip(data.targetAddictionValues);
		}
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "fastTravelSettingV2") {
            this.UpdateFastTravelState();
            this.MainSystem.UpdateCodexEntries();
        }

        if ArrayContains(changedSettings, "basicNeedThresholdValue1") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue3") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue4") {

            DFMainSystem.Get().CheckForInvalidConfiguration();
        }

        if ArrayContains(changedSettings, "criticalNeedVFXEnabled") {
            this.UpdateCriticalNeedEffects();
        }
    }

    //
    //  System-Specific Methods
    //
    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState(this, true) { return; }
		DFLog(this, "OnItemConsumed");

		let itemTags: array<CName> = itemRecord.Tags();
		if ArrayContains(itemTags, n"DarkFutureConsumableAddictionTreatmentDrug") {
            this.OnAddictionTreatmentDrugConsumed();
        }
	}

    protected cb func OnLocomotionStateChanged(value: Int32) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
		
		if this.GameStateService.IsValidGameState(this) {
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
        //DFProfile();
        let gameInstance = GetGameInstance();

        if this.Settings.mainSystemEnabled {
            if Equals(this.Settings.fastTravelSettingV2, DFFastTravelSetting.Enabled) {
                GameInstance.GetQuestsSystem(gameInstance).SetFactStr("df_fact_metro_fast_travel_disabled", 0);
                TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"UI-Menus-WorldMap-Filter-FastTravel");
                TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
                
            } else if Equals(this.Settings.fastTravelSettingV2, DFFastTravelSetting.DisabledAllowMetro) {
                GameInstance.GetQuestsSystem(gameInstance).SetFactStr("df_fact_metro_fast_travel_disabled", 0);
                TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"DarkFutureUILabelMapFilterFastTravel");
                TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
                
            } else if Equals(this.Settings.fastTravelSettingV2, DFFastTravelSetting.Disabled) {
                GameInstance.GetQuestsSystem(gameInstance).SetFactStr("df_fact_metro_fast_travel_disabled", 1);
                TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"DarkFutureUILabelMapFilterFastTravel");
                TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
            }
        } else {
            GameInstance.GetQuestsSystem(gameInstance).SetFactStr("df_fact_metro_fast_travel_disabled", 0);
            TweakDBManager.SetFlat(t"WorldMap.FastTravelFilterGroup.filterName", n"UI-Menus-WorldMap-Filter-FastTravel");
            TweakDBManager.UpdateRecord(t"WorldMap.FastTravelFilterGroup");
        }
    }

    public final func GetPlayerDangerState() -> DFPlayerDangerState {
        //DFProfile();
		let dangerState: DFPlayerDangerState;
        if this.GameStateService.IsValidGameState(this, true) {
            dangerState.InCombat = this.player.IsInCombat();
            
            // Bug Fix - Due to a base game bug, the player character can sometimes be stuck in this.player.IsBeingRevealed() == true.
            // Instead, test if the Being Traced progress bar is on the screen.
            let progressBarIsActive = this.HUDProgressBarBlackboard.GetBool(this.BlackboardDefs.UI_HUDProgressBar.Active);
            let progressBarTypeIsReveal = Equals(FromVariant<SimpleMessageType>(this.HUDProgressBarBlackboard.GetVariant(this.BlackboardDefs.UI_HUDProgressBar.MessageType)), SimpleMessageType.Reveal);

            dangerState.BeingRevealed = progressBarIsActive && progressBarTypeIsReveal;
        }

        return dangerState;
	}

    public final func GetInDangerFromState(dangerState: DFPlayerDangerState) -> Bool {
        //DFProfile();
		return dangerState.InCombat || dangerState.BeingRevealed;
	}

    public final func GetInDanger() -> Bool {
        //DFProfile();
        let inDanger: Bool = this.GetInDangerFromState(this.GetPlayerDangerState());
        return inDanger;
    }

    public final func UpdateStaminaCosts() {
        //DFProfile();
		DFLog(this, "UpdateStaminaCosts");

        let totalSprintCost: Float = 0.0;
        let totalJumpCost: Float = 0.0;

        if !this.GameStateService.IsValidGameState(this) {
			this.ClearStaminaCosts();
        }

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNicotine") {
            totalSprintCost += this.playerSmokingPenaltyStaminaCostSprinting;
            totalJumpCost += this.playerSmokingPenaltyStaminaCostJumping;
        }

		let hydrationStage: Int32 = this.HydrationSystem.GetNeedStage();
        let hasStaminaBooster: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureStaminaBooster");
        
		DFLog(this, "    hydrationStage = " + ToString(hydrationStage));

		if !hasStaminaBooster {
            if hydrationStage == 2 {
                totalSprintCost += this.playerHydrationPenalty02StaminaCostSprinting;
                totalJumpCost += this.playerHydrationPenalty02StaminaCostJumping;

            } else if hydrationStage == 3 {
                totalSprintCost += this.playerHydrationPenalty03StaminaCostSprinting;
                totalJumpCost += this.playerHydrationPenalty03StaminaCostJumping;

            } else if hydrationStage == 4 {
                totalSprintCost += this.playerHydrationPenalty04StaminaCostSprinting;
                totalJumpCost += this.playerHydrationPenalty04StaminaCostJumping;
            }
        }

        if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != totalSprintCost {
            TweakDBManager.SetFlat(t"player.staminaCosts.sprint", totalSprintCost);
        }
        if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != totalJumpCost {
            TweakDBManager.SetFlat(t"player.staminaCosts.jump", totalJumpCost);
        }
	}

	private final func ClearStaminaCosts() -> Void {
        //DFProfile();
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.sprint", 0.0);
		}
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.jump", 0.0);
		}
	}

    public final func HasIncompatibleVFXApplied() -> Bool {
        //DFProfile();
        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury") || 
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"PreventFuryVFX") {
            return true;
        }

        return false;
    }

    //
    //  Breathing Effects
    //
    private final func TryToPlayOutOfBreathEffectsFromSprinting() -> Void {
        //DFProfile();
		if this.GameStateService.IsValidGameState(this) {
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

    public final func TryToPlayOutOfBreathEffectsFromHydrationNotification() -> Void {
        //DFProfile();
		if this.GameStateService.IsValidGameState(this) {
			// Allow Nerve breathing FX to win over Out Of Breath FX.
			if this.NerveSystem.currentNerveBreathingFXStage != 0 {
				return;
			}

            this.StartOutOfBreathBreathingEffects(DFOutOfBreathReason.LowHydrationNotification);
            this.RegisterOutOfBreathStopCallback();
		}
    }

    private final func StartOutOfBreathBreathingEffects(reason: DFOutOfBreathReason) -> Void {
        //DFProfile();
		DFLog(this, "StartOutOfBreathBreathingEffects reason = " + ToString(reason));

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
        //DFProfile();
		DFLog(this, "StopOutOfBreathEffects");
		
		StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.BreathingHeavy");
		this.playingOutOfBreathFX = false;
	}

	public final func StopOutOfBreathSFXIfBreathingFXPlaying() -> Void {
        //DFProfile();
		if this.playingOutOfBreathFX {
			this.StopOutOfBreathSFX();
		}
	}

	public final func StopOutOfBreathSFX() -> Void {
        //DFProfile();
		DFLog(this, "StopOutOfBreathSFX");

		// Only used when other breathing SFX need to stop this early, otherwise stops on its own
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
		evt.soundName = n"ono_v_breath_fast";
		this.player.QueueEvent(evt);
	}

    public final func OnOutOfBreathRecheckSprintingCallback() -> Void {
        //DFProfile();
		if this.lastLocomotionState == 2 { // Still sprinting!
			DFLog(this, "OnOutOfBreathRecheckSprintingCallback -- Still sprinting! Queuing breathing effect.");
			this.outOfBreathEffectQueued = true;
		}
	}

	public final func OnOutOfBreathRecheckDefaultCallback() -> Void {
        //DFProfile();
		if this.lastLocomotionState == 0 { // Still default!
			DFLog(this, "OnOutOfBreathRecheckDefaultCallback -- Still default! Try to play breathing effect.");
			this.outOfBreathEffectQueued = false;
			this.TryToPlayOutOfBreathEffectsFromSprinting();
		}
	}

	public final func OnOutOfBreathStopCallback() -> Void {
        //DFProfile();
		this.StopOutOfBreathEffects();
	}

    private final func RegisterOutOfBreathStopCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathStopCallback.Create(this), this.outOfBreathStopDelayID, this.outOfBreathStopDelayInterval);
	}

    private final func RegisterOutOfBreathRecheckSprintCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckSprintingCallback.Create(this), this.outOfBreathRecheckSprintingDelayID, this.outOfBreathRecheckSprintingDelayInterval);
	}

	private final func RegisterOutOfBreathRecheckDefaultCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckDefaultCallback.Create(this), this.outOfBreathRecheckDefaultDelayID, this.outOfBreathRecheckDefaultDelayInterval);
	}

    private final func UnregisterOutOfBreathStopCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathStopDelayID);
	}

    private final func UnregisterOutOfBreathRecheckDefaultCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathRecheckDefaultDelayID);
	}

    private final func UnregisterOutOfBreathRecheckSprintCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.outOfBreathRecheckSprintingDelayID);
	}

    //
    //  Addiction Treatment
    //
    private final func RegisterAddictionTreatmentDurationUpdateCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, AddictionTreatmentDurationUpdateDelayCallback.Create(this), this.addictionTreatmentDurationUpdateDelayID, this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

	private final func UnregisterAddictionTreatmentDurationUpdateCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.addictionTreatmentDurationUpdateDelayID);
	}

    public final func OnAddictionTreatmentDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
        if !this.GameStateService.IsInAnyMenu() {
            if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds > 0.0 {
                this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

                if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
                    this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
                    this.RefreshAddictionTreatmentEffect();
                    this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();
                    this.NerveSystem.ForceNeedMaxValueUpdate();
                }
                DFLog(this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));
            }

            this.DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce);
        }
        
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    public final func OnAddictionTreatmentDurationUpdateFromTimeSkip(addictionData: DFAddictionDatum) -> Void {
        //DFProfile();
        let lastTreatmentDurationValue: Float = this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = addictionData.newAddictionTreatmentDuration;

        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        }

        if lastTreatmentDurationValue > 0.0 && this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds <= 0.0 {
            this.RefreshAddictionTreatmentEffect();
            this.NerveSystem.ForceNeedMaxValueUpdate();
        }

        DFLog(this, "remainingAddictionTreatmentEffectDurationInGameTimeSeconds = " + ToString(this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds));

        this.DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData);
        this.RegisterContextuallyDelayedAddictionWithdrawalAnimation(addictionData);
        this.RegisterAddictionTreatmentDurationUpdateCallback();
    }

    private func RefreshAddictionTreatmentEffect() -> Void {
        //DFProfile();
		DFLog(this, "RefreshAddictionTreatmentEffect");
        let shouldApply: Bool = false;

        if this.GameStateService.IsValidGameState(this, true) {
            if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds > 0.0 {
                shouldApply = true;
            }
        }

        if shouldApply {
            if !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment") {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment");       
            }
        } else {
            if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment") {
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment");
            }
        }
    }

    public final func OnAddictionTreatmentDrugConsumed() -> Void {
        //DFProfile();
		// Set the duration.
		this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.addictionTreatmentEffectDurationInGameHours);

		// Refresh player-facing status effects.
		this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();

        // Update the Nerve limit.
        this.NerveSystem.ForceNeedMaxValueUpdate();
	}

    public final func TryToStartAddictionWithdrawalAnimation(addictionData: DFAddictionDatum) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "-----------");
        DFLog(this, "-----------");
        DFLog(this, "TryToStartAddictionWithdrawalAnimation");
        DFLog(this, "-----------");
        DFLog(this, "-----------");
		
		let gs: GameState = this.GameStateService.GetGameState(this);
		if Equals(gs, GameState.Valid) {
            DFLog(this, "    Game State is Valid, continuing.");
        } else if Equals(gs, GameState.TemporarilyInvalid) {
            DFLog(this, "    Game State is Temporarily Invalid, checking again.");
            this.RegisterContextuallyDelayedAddictionWithdrawalAnimation(addictionData);
            return;
        }

        // If the Game State is valid, but we're not in an allowed state to play animations, stop and do not retry.
        if !this.AnimationService.IsPlayerInAllowedStateForAddictionWithdrawalAnimation() {
            DFLog(this, "    Player is not in allowed state for withdrawal animation. Exiting!");
            return;
        }

        // Is the Addiction Treatment effect active? If so, stop and do not retry.
        if addictionData.newAddictionTreatmentDuration > 0.0 {
            DFLog(this, "    Player has an addiction treatment duration. Exiting!");
            return;
        }

        // Which addiction withdrawal is currently the most severe?
        let mostSevereAddiction: DFAddictionType = DFAddictionType.None;
        let mostSevereAddictionWithdrawalLevel: Int32 = 0;

        if this.Settings.withdrawalAnimationsEnabled {
            if addictionData.nicotine.withdrawalLevel > 0 && addictionData.nicotine.withdrawalLevel >= mostSevereAddictionWithdrawalLevel && addictionData.nicotine.isWithdrawalLevelWorsened {
                DFLog(this, "    Nicotine withdrawal worsened...");
                if addictionData.nicotine.withdrawalLevel == 2 || addictionData.nicotine.withdrawalLevel == 3 {
                    DFLog(this, "    Nicotine withdrawal = 2 or 3...");
                    if Equals(this.NicotineAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Nicotine Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Nicotine;
                        mostSevereAddictionWithdrawalLevel = addictionData.nicotine.withdrawalLevel;
                    }

                } else if addictionData.nicotine.withdrawalLevel == 4 {
                    DFLog(this, "    Nicotine withdrawal = 4...");
                    if Equals(this.NicotineAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Nicotine Withdrawal Stage 4 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Nicotine;
                        mostSevereAddictionWithdrawalLevel = addictionData.nicotine.withdrawalLevel;
                    }
                }
            }

            if addictionData.alcohol.withdrawalLevel > 0 && addictionData.alcohol.withdrawalLevel >= mostSevereAddictionWithdrawalLevel && addictionData.alcohol.isWithdrawalLevelWorsened {
                DFLog(this, "    Alcohol withdrawal worsened...");
                if addictionData.alcohol.withdrawalLevel == 2 || addictionData.alcohol.withdrawalLevel == 3 {
                    DFLog(this, "    Alcohol withdrawal = 2 or 3...");
                    if Equals(this.AlcoholAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Alcohol Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Alcohol;
                        mostSevereAddictionWithdrawalLevel = addictionData.alcohol.withdrawalLevel;
                    }

                } else if addictionData.alcohol.withdrawalLevel == 4 {
                    DFLog(this, "    Alcohol withdrawal = 4...");
                    if Equals(this.AlcoholAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Alcohol Withdrawal Stage 4 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Alcohol;
                        mostSevereAddictionWithdrawalLevel = addictionData.alcohol.withdrawalLevel;
                    }
                }
            }

            if addictionData.narcotic.withdrawalLevel > 0 && addictionData.narcotic.withdrawalLevel >= mostSevereAddictionWithdrawalLevel && addictionData.narcotic.isWithdrawalLevelWorsened {
                DFLog(this, "    Narcotic withdrawal worsened...");
                if addictionData.narcotic.withdrawalLevel == 2 || addictionData.narcotic.withdrawalLevel == 3 {
                    DFLog(this, "    Narcotic withdrawal = 2 or 3...");
                    if Equals(this.NarcoticAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Narcotic Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Narcotic;
                        mostSevereAddictionWithdrawalLevel = addictionData.narcotic.withdrawalLevel;
                    }

                } else if addictionData.narcotic.withdrawalLevel == 4 {
                    DFLog(this, "    Narcotic withdrawal = 4...");
                    if Equals(this.NarcoticAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRange(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Narcotic Withdrawal Stage 4 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Narcotic;
                        mostSevereAddictionWithdrawalLevel = addictionData.narcotic.withdrawalLevel;
                    }
                }
            }
        } else {
            DFLog(this, "    Withdrawal animations are disabled. Exiting!");
        }

        if NotEquals(mostSevereAddiction, DFAddictionType.None) {
            DFLog(this, "    We are going to play a Withdrawal Animation! mostSevereAddiction Type: " + ToString(mostSevereAddiction) + ", mostSevereAddictionWithdrawalLevel: " + ToString(mostSevereAddictionWithdrawalLevel));

            // Clear any existing audio notifications.
            this.NotificationService.ClearOutOfCombatAudioNotifications();

            // We selected an addiction type. Calculate the animation severity.
            let addictionWithdrawalAnimSeverity: DFAddictionWithdrawalAnimSeverity = mostSevereAddictionWithdrawalLevel == 4 ? DFAddictionWithdrawalAnimSeverity.High : DFAddictionWithdrawalAnimSeverity.Low;

            // Set first time playback and message data.
            if Equals(mostSevereAddiction, DFAddictionType.Nicotine) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.NicotineAddictionSystem, addictionWithdrawalAnimSeverity);

            } else if Equals(mostSevereAddiction, DFAddictionType.Alcohol) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.AlcoholAddictionSystem, addictionWithdrawalAnimSeverity);

            } else if Equals(mostSevereAddiction, DFAddictionType.Narcotic) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.NarcoticAddictionSystem, addictionWithdrawalAnimSeverity);
            }

            this.QuestsSystem.SetFact(n"df_fact_addiction_withdrawal_anim_severity", EnumInt<DFAddictionWithdrawalAnimSeverity>(addictionWithdrawalAnimSeverity));
            this.QuestsSystem.SetFact(n"df_fact_addiction_withdrawal_anim_type", EnumInt<DFAddictionType>(mostSevereAddiction));
            this.QuestsSystem.SetFact(n"df_fact_start_addiction_withdrawal_anim", 1);

        } else {
            DFLog(this, "    We did not pick a Withdrawal Animation.");

            if addictionData.nicotine.isWithdrawalLevelWorsened {
                DFLog(this, "    Nicotine withdrawal worsened, try to play fallback FX!");
                this.NicotineAddictionSystem.PlayWithdrawalAdvanceSFX();
            }

            if addictionData.alcohol.isWithdrawalLevelWorsened {
                DFLog(this, "    Alcohol withdrawal worsened, try to play fallback FX!");
                this.AlcoholAddictionSystem.PlayWithdrawalAdvanceSFX();
            }

            if addictionData.narcotic.isWithdrawalLevelWorsened {
                DFLog(this, "    Narcotic withdrawal worsened, try to play fallback FX!");
                this.NarcoticAddictionSystem.PlayWithdrawalAdvanceSFX();
            }
        }
    }

    private final func SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(addictionSystem: ref<DFAddictionSystemBase>, animSeverity: DFAddictionWithdrawalAnimSeverity) -> Void {
        //DFProfile();
        if Equals(animSeverity, DFAddictionWithdrawalAnimSeverity.Low) && Equals(addictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) {
            this.NotificationService.SetMessage(GetLocalizedTextByKey(addictionSystem.GetWithdrawalAnimationLowFirstTimeMessageKey()), SimpleMessageType.Negative);
            addictionSystem.SetHasEverPlayedTier1WithdrawalAnim(true);
        } else if Equals(animSeverity, DFAddictionWithdrawalAnimSeverity.High) && Equals(addictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) {
            this.NotificationService.SetMessage(GetLocalizedTextByKey(addictionSystem.GetWithdrawalAnimationHighFirstTimeMessageKey()), SimpleMessageType.Negative);
            addictionSystem.SetHasEverPlayedTier2WithdrawalAnim(true);
        }
    }

    private final func DispatchAddictionTreatmentDurationUpdateDoneEvent(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent.Create(gameTimeSecondsToReduce));
    }

    private final func DispatchAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent(addictionData: DFAddictionDatum) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent.Create(addictionData));
    }

    private final func DispatchAddictionTreatmentEffectAppliedOrRemovedEvent() -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent.Create());
    }

    public final func GetRemainingAddictionTreatmentDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds;
    }

    public final func GetAddictionTreatmentDurationUpdateIntervalInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.addictionTreatmentDurationUpdateIntervalInGameTimeSeconds;
    }

    public final func DispatchAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectAppliedEvent.Create(effectID, effectGameplayTags));
    }

    public final func DispatchAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionPrimaryEffectRemovedEvent.Create(effectID, effectGameplayTags));
    }

    //
    // Registration
    //
    private final func RegisterContextuallyDelayedAddictionWithdrawalAnimation(addictionData: DFAddictionDatum) -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback.Create(addictionData), this.contextuallyDelayedAddictionWithdrawalAnimationDelayID, this.contextuallyDelayedAddictionWithdrawalAnimationDelayInterval);
	}

    //
    // Unregistration
    //
    private final func UnregisterContextuallyDelayedAddictionWithdrawalAnimation() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedAddictionWithdrawalAnimationDelayID);
	}

    //
    // Critical Need Effects
    //
    private let updateCriticalNeedEffectsLock: RWLock;
    public final func UpdateCriticalNeedEffects() -> Void {
        RWLock.Acquire(this.updateCriticalNeedEffectsLock);
        if this.GameStateService.IsValidGameState(this, true) {
            let shouldPlayCriticalFX: Bool = false;
            let hydrationValue: Float = this.HydrationSystem.GetNeedValue();
            let nutritionValue: Float = this.NutritionSystem.GetNeedValue();
            let energyValue: Float = this.EnergySystem.GetNeedValue();
            let nerveValue: Float = this.NerveSystem.GetNeedValue();

            if this.Settings.hydrationLossIsFatal && hydrationValue <= this.criticalNeedFXThreshold && hydrationValue != -1.0 {
                shouldPlayCriticalFX = true;
            }

            if this.Settings.nutritionLossIsFatal && nutritionValue <= this.criticalNeedFXThreshold && nutritionValue != -1.0 {
                shouldPlayCriticalFX = true;
            }

            if this.Settings.energyLossIsFatal && energyValue <= this.criticalNeedFXThreshold && energyValue != -1.0 {
                shouldPlayCriticalFX = true;
            }

            if this.Settings.nerveLossIsFatal && nerveValue <= this.criticalNeedFXThreshold && nerveValue != -1.0 {
                shouldPlayCriticalFX = true;
            }


            if shouldPlayCriticalFX {
                this.PlayCriticalNeedEffects();
            } else {
                if this.playingCriticalNeedFX {
                    this.StopCriticalNeedEffects();
                }
            }
        } else {
            if this.playingCriticalNeedFX {
                this.StopCriticalNeedEffects();
            }
        }
        RWLock.Release(this.updateCriticalNeedEffectsLock);
    }

    public final func PlayCriticalNeedEffects() -> Void {
		//DFProfile();
		if !this.playingCriticalNeedFX {
			this.playingCriticalNeedFX = true;
			this.AudioSystem.NotifyGameTone(n"InLowHealth");
			this.PlayCriticalNeedVFX();
		}
	}

	public final func StopCriticalNeedEffects(opt force: Bool) -> Void {
		//DFProfile();
		if this.playingCriticalNeedFX || force {
			this.playingCriticalNeedFX = false;
			this.AudioSystem.NotifyGameTone(n"InNormalHealth");
			this.StopCriticalNeedVFX();
		}
	}

    private final func PlayCriticalNeedVFX() -> Void {
		//DFProfile();
		if this.Settings.criticalNeedVFXEnabled {
			GameObjectEffectHelper.StartEffectEvent(this.player, n"cool_perk_focused_state_fullscreen", false, null, false);
		}
	}

	private final func StopCriticalNeedVFX() -> Void {
		//DFProfile();
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"cool_perk_focused_state_fullscreen");
	}

    //
    // Compatibility
    //
    // Wannabe Edgerunner Compatibility
    @if(ModuleExists("Edgerunning.System"))
    private func DFIsWannabeEdgerunnerInstalled() -> Bool {
        return true;
    }

    @if(!ModuleExists("Edgerunning.System"))
    private func DFIsWannabeEdgerunnerInstalled() -> Bool {
        return false;
    }

    private final func ShowIncompatibilityWarnings() -> Void {
        //DFProfile();

        // Invalid Configuration Checks
		if this.DFIsWannabeEdgerunnerInstalled() && this.Settings.humanityLossCyberpsychosisEnabled {
			this.ShowWannabeEdgerunnerWarning();
		}
    }

    public final func ShowWannabeEdgerunnerWarning() -> Void {
		//DFProfile();
        if DFRunGuard(this) { return; }

		let warning: DFTutorial;
		warning.title = GetLocalizedTextByKey(n"DarkFutureWarningWannabeEdgerunnerTitle");
		warning.message = GetLocalizedTextByKey(n"DarkFutureWarningWannabeEdgerunner");
		warning.iconID = t"";
		this.NotificationService.QueueTutorial(warning);
	}

    public final func SetAddictionTreatmentEffectDuration(newDurationInGameTimeHours: Int32) -> Void {
        // Set the default duration for this consumable.
        this.addictionTreatmentEffectDurationInGameHours = newDurationInGameTimeHours;

        // Update UI records.
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AddictionTreatment_UIData.intValues", [newDurationInGameTimeHours]);
        TweakDBManager.SetFlat(t"DarkFutureItem.AddictionTreatmentDrugOnEquip_UIData.intValues", [-40, newDurationInGameTimeHours]);
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AddictionTreatment_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureItem.AddictionTreatmentDrugOnEquip_UIData");

        // Update the existing duration, if it is greater than the new value.
        if this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds > HoursToGameTimeSeconds(newDurationInGameTimeHours) {
            this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = HoursToGameTimeSeconds(newDurationInGameTimeHours);
        }
    }
}

//
//	Base Game Methods
//

//  PlayerPuppet - Let the Nerve System and Bar know when Combat state changes. (Counts as being "In Danger".)
//
// TODOLOCK
@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {
    //DFProfile();
	let result: Bool = wrappedMethod(newState);

    this.DFReportDangerStateChanged();

	return result;
}

@addMethod(PlayerPuppet)
public final func DFReportDangerStateChanged() -> Void {
    //DFProfile();
    let gameInstance = GetGameInstance();
    
    let dangerState = DFPlayerStateService.GetInstance(gameInstance).GetPlayerDangerState();
	DFNerveSystem.GetInstance(gameInstance).OnDangerStateChanged(dangerState);
    DFHumanityLossConditionSystem.GetInstance(gameInstance).OnDangerStateChanged(dangerState);
}

//  HUDProgressBarController - Let the Nerve System and Bar know when the player is being traced by a Quickhack that was uploaded undetected. (Counts as being "In Danger".)
//
// TODOLOCK
@wrapMethod(HUDProgressBarController)
public final func UpdateProgressBarActive(active: Bool) -> Void {
    //DFProfile();
	wrappedMethod(active);

	this.DFReportDangerStateChanged();
}

@addMethod(HUDProgressBarController)
public final func DFReportDangerStateChanged() -> Void {
    //DFProfile();
    let gameInstance = GetGameInstance();
    
    let dangerState = DFPlayerStateService.GetInstance(gameInstance).GetPlayerDangerState();
	DFNerveSystem.GetInstance(gameInstance).OnDangerStateChanged(dangerState);
    DFHumanityLossConditionSystem.GetInstance(gameInstance).OnDangerStateChanged(dangerState);
}

//  GameObject - Let other systems know that a player OnDamageReceived event occurred. (Used by the Injury system.)
//
// TODOLOCK
@wrapMethod(GameObject)
protected final func ProcessDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Void {
    //DFProfile();
	wrappedMethod(evt);

	// If the target was the player, ignoring Pressure Wave attacks (i.e. fall damage)
	if evt.hitEvent.target.IsPlayer() && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.PressureWave) && NotEquals(evt.hitEvent.attackData.GetAttackType(), gamedataAttackType.Invalid) {
		GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceOnDamageReceivedEvent.Create(evt));
	}
}

//
//  FAST TRAVEL
//

//  DataTermInkGameController - Continue to show the Location Name on DataTerm screens when Fast Travel
//  is disabled by Dark Future.
//
@wrapMethod(DataTermInkGameController)
private final func UpdatePointText() -> Void {
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && NotEquals(settings.fastTravelSettingV2, DFFastTravelSetting.Enabled) {
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
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && settings.hideFastTravelMarkers {
        if Equals(settings.fastTravelSettingV2, DFFastTravelSetting.Enabled) {
            return wrappedMethod();
        } else if Equals(settings.fastTravelSettingV2, DFFastTravelSetting.DisabledAllowMetro) {
            if this.IsSubway() {
                return wrappedMethod();
            } else {
                return false;
            }
        } else if Equals(settings.fastTravelSettingV2, DFFastTravelSetting.Disabled) {
            return false;
        }
    } else {
        return wrappedMethod();
    }
}

//  WorldMapTooltipController - Display the word "Location" instead of "Fast Travel" on Fast Travel marker tooltips.
//
@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
    //DFProfile();
    wrappedMethod(data, menu);
    let settings: ref<DFSettings> = DFSettings.Get();

    if settings.mainSystemEnabled && NotEquals(settings.fastTravelSettingV2, DFFastTravelSetting.Enabled) {
        let fastTravelmappin: ref<FastTravelMappin>;
        let journalManager: ref<JournalManager> = menu.GetJournalManager();
        let player: wref<GameObject> = menu.GetPlayer();

        if Deref(data).controller != null && Deref(data).mappin != null && journalManager != null && player != null {
            fastTravelmappin = Deref(data).mappin as FastTravelMappin;
            if IsDefined(fastTravelmappin) {
                if fastTravelmappin.GetPointData().IsSubway() {
                    if Equals(settings.fastTravelSettingV2, DFFastTravelSetting.Disabled) {
                        inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelMetro"));
                    }
                } else {
                    inkTextRef.SetText(this.m_descText, GetLocalizedTextByKey(n"DarkFutureUILabelMapTooltipFastTravelDataTerm"));
                }
            }
        }
    }
}

//  BaseWorldMapMappinController - Hide DataTerm mappins when using the Fast Travel World Map if Fast Travel Setting is Disabled (Allow Metro)
//                                 (Under this scenario, the only possible way to access the Fast Travel World Map is from a Metro Gate.)
//
@wrapMethod(BaseWorldMapMappinController)
private final func PlayHideShowAnim() -> Void {
    let Settings: ref<DFSettings> = DFSettings.Get();

    if Settings.mainSystemEnabled && Equals(this.m_mappin.GetVariant(), gamedataMappinVariant.FastTravelVariant) && this.isFastTravelEnabled && Equals(Settings.fastTravelSettingV2, DFFastTravelSetting.DisabledAllowMetro) {
        let rootWidget: wref<inkWidget> = this.GetRootWidget();
        this.PlayFadeAnimation(0.0);
        rootWidget.SetInteractive(false);
    } else {
        wrappedMethod();
    }
}

//  DataTermControllerPS - Clean up potential null data returned by action getter.
//
@wrapMethod(DataTermControllerPS)
public func GetActions(out actions: [ref<DeviceAction>], context: GetActionsContext) -> Bool {
    let r: Bool = wrappedMethod(actions, context);

    // Clean up any null entries returned by ActionOpenWorldMap().
    ArrayRemove(actions, null);

    return r;
}

//  DataTermControllerPS - Return a null Action from the DataTerm if Fast Travel Setting is Disabled (Allow Metro)
//
@wrapMethod(DataTermControllerPS)
protected final func ActionOpenWorldMap() -> ref<OpenWorldMapDeviceAction> {
    let Settings: ref<DFSettings> = DFSettings.Get();
    if Settings.mainSystemEnabled && 
    (Equals(Settings.fastTravelSettingV2, DFFastTravelSetting.DisabledAllowMetro) || Equals(Settings.fastTravelSettingV2, DFFastTravelSetting.Disabled)) && 
    NotEquals(this.GetFastravelDeviceType(), EFastTravelDeviceType.SubwayGate) {
        return null;   
    } else {
        return wrappedMethod();
    }
}
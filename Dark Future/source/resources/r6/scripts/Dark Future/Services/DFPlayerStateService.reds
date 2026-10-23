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
    DFResourceUtils,
    RandRangeInclusive
}
import DarkFuture.Main.{ 
    DFAddictionDatum,
    DFMainSystem,
    DFTimeSkipData,
    DFAddictionUpdateDatum,
    MainSystemItemConsumedEvent,
    DFTimeSkipType,
    DFNeedsDatum,
    DFHumanityLossDatum,
    DFAddictionProxyEffectType
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
    DFNerveSystem,
    DFChangeNeedValueProps,
    DFNeedChangeUIFlags
}
import DarkFuture.Conditions.{
    DFHumanityLossConditionSystem,
    DFBiocorruptionConditionSystem
}
import DarkFuture.Gameplay.DFInteractionSystem

enum DFOutOfBreathReason {
    LowHydrationNotification = 0,
    SprintingDashingWithLowHydration = 1,
    SprintingDashingAfterSmoking = 2
}

public enum DFAddictionType {
    None = 0,
    Alcohol = 1,
    Nicotine = 2,
    Narcotic = 3
}

public struct DFManagedEffect {
    public persistent let type: DFManagedEffectType;
    public persistent let activeEffectEnergyChanges: array<Float>;
    public persistent let toleranceEffectCount: Int32;
    public persistent let effectMode: DFManagedEffectMode;
}

public struct DFManagedEffectDefinition {
    public let type: DFManagedEffectType;
    public let itemRecordTag: CName;
    public let timedActiveEffectID: TweakDBID;
    public let lastingActiveEffectID: TweakDBID;
    public let timedToleranceEffectID: TweakDBID;
    public let lastingToleranceEffectID: TweakDBID;
    public let maxStacks: Int32;
    public let maxStacksPerAddictionStage: array<Int32>;
    public let toleranceStacksPerAddictionStage: array<Int32>;
    public let timedAdditionalDebuffID: TweakDBID;
    public let lastingAdditionalDebuffID: TweakDBID;
    public let contributesToEuphoria: Bool;
}

public struct DFManagedEffectItemDefinition {
    public let itemRecordTag: CName;
    public let energyChangeWhileActive: Float;
    public let nerveChangeWhenApplied: Float;
    public let stackCountDef: DFManagedEffectStackCountDef;
    public let excessStackDef: DFManagedEffectExcessStackDef;
}

public struct DFManagedEffectExcessStackDef {
    public let excessStackItemActionType: DFManagedEffectExcessStackItemActionType;
}

public struct DFManagedEffectStackCountDef {
    public let mode: DFManagedEffectStackCountMode;
    public let countToApply: Int32;
    public let countToApplyMax: Int32;
}

public struct DFManagedEffectPipelineResult {
    public let type: DFManagedEffectType;
    public let managedEffectStateIndex: Int32;
    public let addictionSystem: ref<DFAddictionSystemBase>;
    public let managedEffectItemDef: DFManagedEffectItemDefinition;
    public let toleranceStacksToApply: Int32;
    public let activeStacksToApply: Int32;
    public let triggerExcessStackEffect: Bool;
}

public enum DFManagedEffectStackCountMode {
    Specific = 0,
    Random = 1
}

public enum DFManagedEffectType {
    None = 0,
    Caffeine = 1,
    Alcohol = 2,
    Nicotine = 3,
    Narcotic = 4
}

public enum DFManagedEffectMode {
    Timed = 0,
    Lasting = 1
}

public enum DFManagedEffectExcessStackItemActionType {
    None = 0,
    Alcohol = 1,
    Narcotic = 2
}

public enum DFManagedEffectVFXIntensity {
    Off = 0,
    Low = 1,
    LowToHigh = 2,
    High = 3,
    HighToLow = 4,
    AnyToHigh = 5,
    AnyToLow = 6
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

public class PlayerStateEffectsDurationUpdateDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new PlayerStateEffectsDurationUpdateDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().playerStateEffectsDurationUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
        let pss: ref<DFPlayerStateService> = DFPlayerStateService.Get();
		pss.OnPlayerStateEffectsDurationUpdate(pss.GetPlayerStateEffectsDurationUpdateIntervalInGameTimeSeconds());
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
        let event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent> = new PlayerStateServiceAddictionTreatmentDurationUpdateDoneEvent();
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
        let event: ref<PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent> = new PlayerStateServiceAddictionTreatmentDurationUpdateFromTimeSkipDoneEvent();
        event.data = data;
        return event;
    }
}

public class PlayerStateServiceAddictionManagedEffectAppliedEvent extends CallbackSystemEvent {
    public let type: DFManagedEffectType;
    public let stackCount: Int32;
    public let activeEffectApplied: Bool;

    public func GetType() -> DFManagedEffectType {
        //DFProfile();
        return this.type;
    }

    public func GetStackCount() -> Int32 {
        //DFProfile();
        return this.stackCount;
    }

    public func GetActiveEffectApplied() -> Bool {
        //DFProfile();
        return this.activeEffectApplied;
    }

    public static func Create(type: DFManagedEffectType, stackCount: Int32, activeEffectApplied: Bool) -> ref<PlayerStateServiceAddictionManagedEffectAppliedEvent> {
        //DFProfile();
        let event: ref<PlayerStateServiceAddictionManagedEffectAppliedEvent> = new PlayerStateServiceAddictionManagedEffectAppliedEvent();
        event.type = type;
        event.stackCount = stackCount;
        event.activeEffectApplied = activeEffectApplied;
        return event;
    }
}

public class PlayerStateServiceAddictionManagedEffectRemovedEvent extends CallbackSystemEvent {
    public let type: DFManagedEffectType;

    public func GetType() -> DFManagedEffectType {
        //DFProfile();
        return this.type;
    }

    public static func Create(type: DFManagedEffectType) -> ref<PlayerStateServiceAddictionManagedEffectRemovedEvent> {
        //DFProfile();
        let event: ref<PlayerStateServiceAddictionManagedEffectRemovedEvent> = new PlayerStateServiceAddictionManagedEffectRemovedEvent();
        event.type = type;
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
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new OutOfBreathStopCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().outOfBreathStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().OnOutOfBreathStopCallback();
	}
}

public class OutOfBreathRecheckSprintingCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new OutOfBreathRecheckSprintingCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().outOfBreathRecheckSprintingDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().OnOutOfBreathRecheckSprintingCallback();
	}
}

public class OutOfBreathRecheckDefaultCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new OutOfBreathRecheckDefaultCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().outOfBreathRecheckDefaultDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().OnOutOfBreathRecheckDefaultCallback();
	}
}

public class ManagedEffectReconciliationDebounceDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new ManagedEffectReconciliationDebounceDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().managedEffectReconciliationDebounceDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().OnManagedEffectReconciliationDebounceCallback();
	}
}

public class ManagedEffectVFXRecheckDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new ManagedEffectVFXRecheckDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().managedEffectVFXRecheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFPlayerStateService.Get().OnManagedEffectVFXRecheckCallback();
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

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    //DFProfile();
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let nicotineAddictionSystem: ref<DFNicotineAddictionSystem> = DFNicotineAddictionSystem.Get();
    let effectID: TweakDBID = evt.staticData.GetID();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(playerStateService) {
        // DARK FUTURE ENABLED
        
        // Addiction
        if ArrayContains(effectTags, n"DarkFutureAddictionProxyEffectAlcohol") {
            playerStateService.HandleAddictionProxyEffectApplied(DFAddictionProxyEffectType.Alcohol, evt.staticData.GetID(), evt.stackCount);

        // Stamina Costs
        } else if ArrayContains(effectTags, n"DarkFutureStaminaBooster") {
            playerStateService.UpdateStaminaCosts();
        }

    } else {
        // TODO
        // DARK FUTURE DISABLED
        // If Dark Future is disabled, don't allow certain player status effects to apply.

        if Equals(effectID, t"DarkFutureStatusEffect.AddictionTreatment") {
            StatusEffectHelper.RemoveStatusEffect(playerStateService.player, t"DarkFutureStatusEffect.AddictionTreatment");
        }
    }

    // DARK FUTURE ENABLED / DISABLED
    // Update Stamina costs when Smoking effect is applied.
    if ArrayContains(effectTags, n"DarkFutureSmokingDebuff") {
        playerStateService.UpdateStaminaCosts();

        // Update the effect duration based on installed cyberware.
		nicotineAddictionSystem.UpdateActiveNicotineDebuffEffectDuration(effectID);
    }

    if ArrayContains(effectTags, n"DarkFutureLegacyBlackLaceEffect") {
        // The only way this could have been applied is through the Dum Dum scene. Get rid of it.
        StatusEffectHelper.RemoveStatusEffectsWithTag(this, n"DarkFutureLegacyBlackLaceEffect");
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    //DFProfile();
    let playerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    // DARK FUTURE ENABLED / DISABLED
    // Update Stamina costs when Smoking Debuff or Stamina Booster effect is removed.
    if ArrayContains(effectTags, n"DarkFutureStaminaBooster") || ArrayContains(effectTags, n"DarkFutureSmokingDebuff") {
        playerStateService.UpdateStaminaCosts();
    }

	return wrappedMethod(evt);
}

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

//
//  Managed Effects
//
@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();

	if IsSystemEnabledAndRunning(PlayerStateService) {
		if evt.staticData.GameplayTagsContains(n"DarkFutureManagedEffect") {
			PlayerStateService.OnManagedEffectRemoved(evt);
		}
	}
	
	return wrappedMethod(evt);
}

class DFPlayerStateServiceEventListeners extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFPlayerStateService> {
        //DFProfile();
		return DFPlayerStateService.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
		super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<MainSystemItemConsumedEvent>(), this, n"OnMainSystemItemConsumedEvent", true);
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
    private persistent let playerInOverdose: Bool = false;
    private persistent let managedEffectsState: array<DFManagedEffect>;

    private let managedEffectDefinitions: array<DFManagedEffectDefinition>;
    private let managedEffectItemDefinitions: array<DFManagedEffectItemDefinition>;
    private let isReconcilingStatusEffects: Bool;
    private let repeatStatusEffectReconciliationOnComplete: Bool;

    private let currentManagedEffectVFXIntensity: DFManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.Off;
    private let currentAlcoholVFXSeverityHigh: Bool = false;
    private let currentNarcoticVFXSeverityHigh: Bool = false;

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
    private let CyberwareService: ref<DFCyberwareService>;
    private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
    private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;
    private let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;

    public let PSMBlackboard: ref<IBlackboard>;
    private let BlackboardDefs: ref<AllBlackboardDefinitions>;
    private let HUDProgressBarBlackboard: ref<IBlackboard>;
    private let locomotionListener: ref<CallbackHandle>;

    private const let criticalNeedFXThreshold: Float = 10.0;
    private let playingCriticalNeedFX: Bool = false;

    private let playerInDanger: Bool = false;
    private let lastLocomotionState: Int32 = 0;

    private const let addictionTreatmentEffectDurationInGameHours: Int32 = 12;
    public let playerStateEffectsDurationUpdateDelayID: DelayID;
    private let playerStateEffectsDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;

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
    public let managedEffectReconciliationDebounceDelayID: DelayID;
    public let managedEffectVFXRecheckDelayID: DelayID;

    private let outOfBreathRecheckSprintingDelayInterval: Float = 5.0;
	private let outOfBreathRecheckDefaultDelayInterval: Float = 0.35;
	private let outOfBreathStopDelayInterval: Float = 2.6;
    private let managedEffectReconciliationDebounceDelayInterval: Float = 0.25;
    private let managedEffectVFXRecheckDelayInterval_High_NormalTimed: Float = 25.0;
    private let managedEffectVFXRecheckDelayInterval_High_NormalLasting: Float = 25.0;
    private let managedEffectVFXRecheckDelayInterval_Low_NormalTimed: Float = 60.0;
    private let managedEffectVFXRecheckDelayInterval_Low_NormalLasting: Float = 240.0;
    private let managedEffectVFXRecheckDelayInterval_Low_NormalVariance: Float = 12.0;
    private let managedEffectVFXRecheckDelayInterval_Transition: Float = 4.0;

    // Vehicle Speed
    private let activePlayerVehicleSpeedListener: ref<CallbackHandle>;
    private let lastActivePlayerVehicleSpeed: Int32 = 0;
    private let lastActivePlayerVehicle: ref<VehicleObject>;
    private const let playerVehicleSpeedImpairedDrivingThreshold: Int32 = 40;
    public const let impairedDrivingEnergyThreshold: Int32 = 4;
    public let wasAboveImpairedDrivingSpeedThreshold: Bool = false;

    // VFX
    private let alcoholMotionBlurEffect: CName = n"status_drunk_level_1";
    private let chomaticAbberationLowEffect: CName = n"status_drunk_level_2";
    private let alcoholWaveEffect: CName = n"status_drunk_level_3";
    private let narcoticsBloomLowColorEffect: CName = n"status_drugged_low";
    private let chromaticAbberationHighEffect: CName = n"status_drugged_medium";
    private let narcoticsBloomHighColorEffect: CName = n"status_drugged_heavy";

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

    public func SetupData() -> Void {
        //
        // Item Definitions
        //

        // Caffeine
        //
        let caffeineItemExcessStackDef: DFManagedEffectExcessStackDef;
        caffeineItemExcessStackDef.excessStackItemActionType = DFManagedEffectExcessStackItemActionType.None;

        let caffeine1StackCountDef: DFManagedEffectStackCountDef;
        caffeine1StackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        caffeine1StackCountDef.countToApply = 1;

        let caffeine2StackCountDef: DFManagedEffectStackCountDef;
        caffeine2StackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        caffeine2StackCountDef.countToApply = 2;

        let caffeine3StackCountDef: DFManagedEffectStackCountDef;
        caffeine3StackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        caffeine3StackCountDef.countToApply = 3;

        let caffeine1ItemDef: DFManagedEffectItemDefinition;
        caffeine1ItemDef.itemRecordTag = n"DarkFutureManagedConsumableCaffeine1Count";
        caffeine1ItemDef.energyChangeWhileActive = 10.0;
        caffeine1ItemDef.excessStackDef = caffeineItemExcessStackDef;
        caffeine1ItemDef.stackCountDef = caffeine1StackCountDef;

        let caffeine2ItemDef: DFManagedEffectItemDefinition;
        caffeine2ItemDef.itemRecordTag = n"DarkFutureManagedConsumableCaffeine2Count";
        caffeine2ItemDef.energyChangeWhileActive = 10.0;
        caffeine2ItemDef.excessStackDef = caffeineItemExcessStackDef;
        caffeine2ItemDef.stackCountDef = caffeine2StackCountDef;

        let caffeine3ItemDef: DFManagedEffectItemDefinition;
        caffeine3ItemDef.itemRecordTag = n"DarkFutureManagedConsumableCaffeine3Count";
        caffeine3ItemDef.energyChangeWhileActive = 10.0;
        caffeine3ItemDef.excessStackDef = caffeineItemExcessStackDef;
        caffeine3ItemDef.stackCountDef = caffeine3StackCountDef;

        // Alcohol
        //
        let alcoholItemExcessStackDef: DFManagedEffectExcessStackDef;
        alcoholItemExcessStackDef.excessStackItemActionType = DFManagedEffectExcessStackItemActionType.Alcohol;

        let beerStackCountDef: DFManagedEffectStackCountDef;
        beerStackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        beerStackCountDef.countToApply = 1;

        let wineCocktailStackCountDef: DFManagedEffectStackCountDef;
        wineCocktailStackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        wineCocktailStackCountDef.countToApply = 2;

        let liquorStackCountDef: DFManagedEffectStackCountDef;
        liquorStackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        liquorStackCountDef.countToApply = 3;

        let beerTier1ItemDef: DFManagedEffectItemDefinition;
        beerTier1ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholBeerTier1";
        beerTier1ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        beerTier1ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier1Rev4;
        beerTier1ItemDef.excessStackDef = alcoholItemExcessStackDef;
        beerTier1ItemDef.stackCountDef = beerStackCountDef;

        let beerTier2ItemDef: DFManagedEffectItemDefinition;
        beerTier2ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholBeerTier2";
        beerTier2ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        beerTier2ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier2Rev4;
        beerTier2ItemDef.excessStackDef = alcoholItemExcessStackDef;
        beerTier2ItemDef.stackCountDef = beerStackCountDef;

        let beerTier3ItemDef: DFManagedEffectItemDefinition;
        beerTier3ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholBeerTier3";
        beerTier3ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        beerTier3ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier3Rev4;
        beerTier3ItemDef.excessStackDef = alcoholItemExcessStackDef;
        beerTier3ItemDef.stackCountDef = beerStackCountDef;

        let wineCocktailTier1ItemDef: DFManagedEffectItemDefinition;
        wineCocktailTier1ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholWineCocktailTier1";
        wineCocktailTier1ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        wineCocktailTier1ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier1Rev4;
        wineCocktailTier1ItemDef.excessStackDef = alcoholItemExcessStackDef;
        wineCocktailTier1ItemDef.stackCountDef = wineCocktailStackCountDef;

        let wineCocktailTier2ItemDef: DFManagedEffectItemDefinition;
        wineCocktailTier2ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholWineCocktailTier2";
        wineCocktailTier2ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        wineCocktailTier2ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier2Rev4;
        wineCocktailTier2ItemDef.excessStackDef = alcoholItemExcessStackDef;
        wineCocktailTier2ItemDef.stackCountDef = wineCocktailStackCountDef;

        let wineCocktailTier3ItemDef: DFManagedEffectItemDefinition;
        wineCocktailTier3ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholWineCocktailTier3";
        wineCocktailTier3ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        wineCocktailTier3ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier3Rev4;
        wineCocktailTier3ItemDef.excessStackDef = alcoholItemExcessStackDef;
        wineCocktailTier3ItemDef.stackCountDef = wineCocktailStackCountDef;

        let liquorTier1ItemDef: DFManagedEffectItemDefinition;
        liquorTier1ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholLiquorTier1";
        liquorTier1ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        liquorTier1ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier1Rev4;
        liquorTier1ItemDef.excessStackDef = alcoholItemExcessStackDef;
        liquorTier1ItemDef.stackCountDef = liquorStackCountDef;

        let liquorTier2ItemDef: DFManagedEffectItemDefinition;
        liquorTier2ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholLiquorTier2";
        liquorTier2ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        liquorTier2ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier2Rev4;
        liquorTier2ItemDef.excessStackDef = alcoholItemExcessStackDef;
        liquorTier2ItemDef.stackCountDef = liquorStackCountDef;

        let liquorTier3ItemDef: DFManagedEffectItemDefinition;
        liquorTier3ItemDef.itemRecordTag = n"DarkFutureManagedConsumableAlcoholLiquorTier3";
        liquorTier3ItemDef.energyChangeWhileActive = -this.Settings.energyAlcoholTier1;
        liquorTier3ItemDef.nerveChangeWhenApplied = this.Settings.nerveAlcoholTier3Rev4;
        liquorTier3ItemDef.excessStackDef = alcoholItemExcessStackDef;
        liquorTier3ItemDef.stackCountDef = liquorStackCountDef;

        // Nicotine
        //
        let nicotineItemExcessStackDef: DFManagedEffectExcessStackDef;
        nicotineItemExcessStackDef.excessStackItemActionType = DFManagedEffectExcessStackItemActionType.None;

        let nicotineStackCountDef: DFManagedEffectStackCountDef;
        nicotineStackCountDef.mode = DFManagedEffectStackCountMode.Specific;
        nicotineStackCountDef.countToApply = 1;

        let nicotineItemDef: DFManagedEffectItemDefinition;
        nicotineItemDef.itemRecordTag = n"DarkFutureManagedConsumableNicotine";
        nicotineItemDef.energyChangeWhileActive = this.Settings.energyNicotineTier1;
        nicotineItemDef.nerveChangeWhenApplied = this.Settings.nerveCigarettesRev3;
        nicotineItemDef.excessStackDef = nicotineItemExcessStackDef;
        nicotineItemDef.stackCountDef = nicotineStackCountDef;

        // Narcotics
        //
        let narcoticItemExcessStackDef: DFManagedEffectExcessStackDef;
        narcoticItemExcessStackDef.excessStackItemActionType = DFManagedEffectExcessStackItemActionType.Narcotic;

        let mrWhiteyStackCountDef: DFManagedEffectStackCountDef;
        mrWhiteyStackCountDef.mode = DFManagedEffectStackCountMode.Random;
        mrWhiteyStackCountDef.countToApply = 1;
        mrWhiteyStackCountDef.countToApplyMax = 4;

        let narcoticPillStackCountDef: DFManagedEffectStackCountDef;
        narcoticPillStackCountDef.mode = DFManagedEffectStackCountMode.Random;
        narcoticPillStackCountDef.countToApply = 2;
        narcoticPillStackCountDef.countToApplyMax = 4;

        let glitterStackCountDef: DFManagedEffectStackCountDef;
        glitterStackCountDef.mode = DFManagedEffectStackCountMode.Random;
        glitterStackCountDef.countToApply = 3;
        glitterStackCountDef.countToApplyMax = 6;

        let blackLaceV0StackCountDef: DFManagedEffectStackCountDef;
        blackLaceV0StackCountDef.mode = DFManagedEffectStackCountMode.Random;
        blackLaceV0StackCountDef.countToApply = 4;
        blackLaceV0StackCountDef.countToApplyMax = 6;

        // TODO: Known issue, stack count at runtime is incorrect
        let blackLaceV1StackCountDef: DFManagedEffectStackCountDef;
        blackLaceV1StackCountDef.mode = DFManagedEffectStackCountMode.Random;
        blackLaceV1StackCountDef.countToApply = 5;
        blackLaceV1StackCountDef.countToApplyMax = 7;

        let mrWhiteyItemDef: DFManagedEffectItemDefinition;
        mrWhiteyItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticMrWhitey";
        mrWhiteyItemDef.energyChangeWhileActive = this.Settings.energyNarcoticTier1;
        mrWhiteyItemDef.nerveChangeWhenApplied = this.Settings.nerveNarcoticsRev2;
        mrWhiteyItemDef.excessStackDef = narcoticItemExcessStackDef;
        mrWhiteyItemDef.stackCountDef = mrWhiteyStackCountDef;

        let narcoticPillItemDef: DFManagedEffectItemDefinition;
        narcoticPillItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticNarcoticPill";
        narcoticPillItemDef.energyChangeWhileActive = this.Settings.energyNarcoticTier1;
        narcoticPillItemDef.nerveChangeWhenApplied = this.Settings.nerveNarcoticsRev2;
        narcoticPillItemDef.excessStackDef = narcoticItemExcessStackDef;
        narcoticPillItemDef.stackCountDef = narcoticPillStackCountDef;

        let glitterItemDef: DFManagedEffectItemDefinition;
        glitterItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticGlitter";
        glitterItemDef.energyChangeWhileActive = this.Settings.energyNarcoticTier1;
        glitterItemDef.nerveChangeWhenApplied = this.Settings.nerveNarcoticsRev2;
        glitterItemDef.excessStackDef = narcoticItemExcessStackDef;
        glitterItemDef.stackCountDef = glitterStackCountDef;

        let blackLaceV0ItemDef: DFManagedEffectItemDefinition;
        blackLaceV0ItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticBlackLaceV0";
        blackLaceV0ItemDef.energyChangeWhileActive = this.Settings.energyNarcoticTier1;
        blackLaceV0ItemDef.nerveChangeWhenApplied = this.Settings.nerveNarcoticsRev2;
        blackLaceV0ItemDef.excessStackDef = narcoticItemExcessStackDef;
        blackLaceV0ItemDef.stackCountDef = blackLaceV0StackCountDef;

        let blackLaceV1ItemDef: DFManagedEffectItemDefinition;
        blackLaceV1ItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticBlackLaceV1";
        blackLaceV1ItemDef.energyChangeWhileActive = this.Settings.energyNarcoticTier1;
        blackLaceV1ItemDef.nerveChangeWhenApplied = this.Settings.nerveNarcoticsRev2;
        blackLaceV1ItemDef.excessStackDef = narcoticItemExcessStackDef;
        blackLaceV1ItemDef.stackCountDef = blackLaceV1StackCountDef;

        let compat_juiceItemDef: DFManagedEffectItemDefinition;
        compat_juiceItemDef.itemRecordTag = n"DarkFutureManagedConsumableNarcoticCompatibilityJuice";
        compat_juiceItemDef.energyChangeWhileActive = blackLaceV0ItemDef.energyChangeWhileActive;
        compat_juiceItemDef.nerveChangeWhenApplied = blackLaceV0ItemDef.nerveChangeWhenApplied;
        compat_juiceItemDef.excessStackDef = blackLaceV0ItemDef.excessStackDef;
        compat_juiceItemDef.stackCountDef = blackLaceV0ItemDef.stackCountDef;

        ArrayPush(this.managedEffectItemDefinitions, caffeine1ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, caffeine2ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, caffeine3ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, beerTier1ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, beerTier2ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, beerTier3ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, wineCocktailTier1ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, wineCocktailTier2ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, wineCocktailTier3ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, liquorTier1ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, liquorTier2ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, liquorTier3ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, nicotineItemDef);
        ArrayPush(this.managedEffectItemDefinitions, mrWhiteyItemDef);
        ArrayPush(this.managedEffectItemDefinitions, narcoticPillItemDef);
        ArrayPush(this.managedEffectItemDefinitions, glitterItemDef);
        ArrayPush(this.managedEffectItemDefinitions, blackLaceV0ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, blackLaceV1ItemDef);
        ArrayPush(this.managedEffectItemDefinitions, compat_juiceItemDef);

        
        //
        // Managed Effect Definitions
        //
        let caffeineEffectDef: DFManagedEffectDefinition;
        caffeineEffectDef.type = DFManagedEffectType.Caffeine;
        caffeineEffectDef.itemRecordTag = n"DarkFutureManagedConsumableCaffeine";
        caffeineEffectDef.timedActiveEffectID = t"DarkFutureStatusEffect.CaffeinatedEffect";
        caffeineEffectDef.lastingActiveEffectID = t"DarkFutureStatusEffect.CaffeinatedEffectLasting";
        caffeineEffectDef.timedToleranceEffectID = t"";
        caffeineEffectDef.lastingToleranceEffectID = t"";
        caffeineEffectDef.maxStacks = 3;
        caffeineEffectDef.maxStacksPerAddictionStage = [];
        caffeineEffectDef.toleranceStacksPerAddictionStage = [];
        caffeineEffectDef.contributesToEuphoria = false;

        let alcoholEffectDef: DFManagedEffectDefinition;
        alcoholEffectDef.type = DFManagedEffectType.Alcohol;
        alcoholEffectDef.itemRecordTag = n"DarkFutureManagedConsumableAlcohol";
        alcoholEffectDef.timedActiveEffectID = t"DarkFutureStatusEffect.Alcohol";
        alcoholEffectDef.lastingActiveEffectID = t"DarkFutureStatusEffect.AlcoholLasting";
        alcoholEffectDef.timedToleranceEffectID = t"DarkFutureStatusEffect.AlcoholTolerance";
        alcoholEffectDef.lastingToleranceEffectID = t"DarkFutureStatusEffect.AlcoholToleranceLasting";
        alcoholEffectDef.maxStacks = 12;
        alcoholEffectDef.maxStacksPerAddictionStage = [4, 6, 8, 10, 12];
        alcoholEffectDef.toleranceStacksPerAddictionStage = [0, 1, 2, 4, 6];
        alcoholEffectDef.contributesToEuphoria = true;

        let nicotineEffectDef: DFManagedEffectDefinition;
        nicotineEffectDef.type = DFManagedEffectType.Nicotine;
        nicotineEffectDef.itemRecordTag = n"DarkFutureManagedConsumableNicotine";
        nicotineEffectDef.timedActiveEffectID = t"DarkFutureStatusEffect.Smoking";
        nicotineEffectDef.lastingActiveEffectID = t"DarkFutureStatusEffect.SmokingLasting";
        nicotineEffectDef.timedToleranceEffectID = t"DarkFutureStatusEffect.NicotineTolerance";
        nicotineEffectDef.lastingToleranceEffectID = t"DarkFutureStatusEffect.NicotineToleranceLasting";
        nicotineEffectDef.timedAdditionalDebuffID = t"DarkFutureStatusEffect.SmokingDebuff";
        nicotineEffectDef.lastingAdditionalDebuffID = t"DarkFutureStatusEffect.SmokingDebuffLasting";
        nicotineEffectDef.maxStacks = 5;
        nicotineEffectDef.maxStacksPerAddictionStage = [2, 3, 4, 5, 5];
        nicotineEffectDef.toleranceStacksPerAddictionStage = [0, 1, 1, 2, 2];
        nicotineEffectDef.contributesToEuphoria = false;

        let narcoticEffectDef: DFManagedEffectDefinition;
        narcoticEffectDef.type = DFManagedEffectType.Narcotic;
        narcoticEffectDef.itemRecordTag = n"DarkFutureManagedConsumableNarcotic";
        narcoticEffectDef.timedActiveEffectID = t"DarkFutureStatusEffect.Narcotic";
        narcoticEffectDef.lastingActiveEffectID = t"DarkFutureStatusEffect.NarcoticLasting";
        narcoticEffectDef.timedToleranceEffectID = t"DarkFutureStatusEffect.NarcoticTolerance";
        narcoticEffectDef.lastingToleranceEffectID = t"DarkFutureStatusEffect.NarcoticToleranceLasting";
        narcoticEffectDef.maxStacks = 11;
        narcoticEffectDef.maxStacksPerAddictionStage = [4, 5, 7, 9, 11];
        narcoticEffectDef.toleranceStacksPerAddictionStage = [0, 1, 3, 4, 5];
        narcoticEffectDef.contributesToEuphoria = true;

        ArrayPush(this.managedEffectDefinitions, caffeineEffectDef);
        ArrayPush(this.managedEffectDefinitions, alcoholEffectDef);
        ArrayPush(this.managedEffectDefinitions, nicotineEffectDef);
        ArrayPush(this.managedEffectDefinitions, narcoticEffectDef);

        //
        // Managed Effect State
        //
        if ArraySize(this.managedEffectsState) == 0 {
            let caffeineManagedEffect: DFManagedEffect;
            caffeineManagedEffect.type = DFManagedEffectType.Caffeine;
            ArrayPush(this.managedEffectsState, caffeineManagedEffect);

            let alcoholManagedEffect: DFManagedEffect;
            alcoholManagedEffect.type = DFManagedEffectType.Alcohol;
            ArrayPush(this.managedEffectsState, alcoholManagedEffect);

            let nicotineManagedEffect: DFManagedEffect;
            nicotineManagedEffect.type = DFManagedEffectType.Nicotine;
            ArrayPush(this.managedEffectsState, nicotineManagedEffect);

            let narcoticManagedEffect: DFManagedEffect;
            narcoticManagedEffect.type = DFManagedEffectType.Narcotic;
            ArrayPush(this.managedEffectsState, narcoticManagedEffect);
        }

        this.PrintManagedEffectsState();
    }
    
    private func RegisterListeners() -> Void {
        //DFProfile();
        this.locomotionListener = this.PSMBlackboard.RegisterListenerInt(this.BlackboardDefs.PlayerStateMachine.Locomotion, this, n"OnLocomotionStateChanged");
    }
    
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    
    private func UnregisterListeners() -> Void {
        //DFProfile();
        this.PSMBlackboard.UnregisterListenerInt(this.BlackboardDefs.PlayerStateMachine.Locomotion, this.locomotionListener);
		this.locomotionListener = null;

        if IsDefined(this.lastActivePlayerVehicle) {
            this.UnregisterForVehicleSpeedChange(this.lastActivePlayerVehicle);
        }
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
        this.RegisterPlayerStateEffectsDurationUpdateCallback();
        this.UpdateFastTravelState();
        this.SetAddictionTreatmentEffectDuration(this.addictionTreatmentEffectDurationInGameHours);
        this.UpdateManagedEffectVFX(true);
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.remainingAddictionTreatmentEffectDurationInGameTimeSeconds = 0.0;
        this.RefreshAddictionTreatmentEffect();
        this.ClearAllManagedEffects();

        this.playerInDanger = false;
        this.outOfBreathEffectQueued = false;
		this.lastLocomotionState = 0;
        this.UpdateFastTravelState();
        this.ClearStaminaCosts();
		this.StopOutOfBreathEffects();
        this.StopCriticalNeedEffects(true);
        this.StopManagedEffectVFX();
    }

    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance: GameInstance = GetGameInstance();
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
        this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
        this.HumanityLossConditionSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
        this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
    }
    
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.RegisterPlayerStateEffectsDurationUpdateCallback();
        this.UpdateFastTravelState();
        this.StopOutOfBreathEffects();
        this.ShowIncompatibilityWarnings();
        this.SetAddictionTreatmentEffectDuration(this.addictionTreatmentEffectDurationInGameHours);
        this.RegisterForVehicleSpeedChange();
        this.UpdateManagedEffectVFX();

        this.PrintManagedEffectsState();
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterPlayerStateEffectsDurationUpdateCallback();
		this.UnregisterOutOfBreathRecheckDefaultCallback();
		this.UnregisterOutOfBreathRecheckSprintCallback();
		this.UnregisterOutOfBreathStopCallback();
        this.UnregisterManagedEffectReconciliationDebounceDelayCallback();
        this.UnregisterManagedEffectVFXRecheckDelayCallback();
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.UnregisterPlayerStateEffectsDurationUpdateCallback();
    }

    public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.RegisterPlayerStateEffectsDurationUpdateCallback();
    }

    public func OnTimeSkipBegin() -> Void {}

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

        this.ClearAllManagedEffects(true);
		this.RegisterPlayerStateEffectsDurationUpdateCallback();

        if this.GameStateService.IsValidGameState(this, true) {
            this.OnPlayerStateEffectsDurationUpdateFromTimeSkip(data.targetAddictionValues, data.timeSkipType);
        }
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "fastTravelSettingV2") {
            this.UpdateFastTravelState();
            this.MainSystem.UpdateCodexEntries();
        }

        if ArrayContains(changedSettings, "basicNeedThresholdValue1V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue2V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue3V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue4V2") {

            DFMainSystem.Get().CheckForInvalidConfiguration();
        }

        if ArrayContains(changedSettings, "criticalNeedVFXEnabled") {
            this.UpdateCriticalNeedEffects();
        }
    }

    //
    //  System-Specific Methods
    //
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
        let gameInstance: GameInstance = GetGameInstance();

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
            let progressBarIsActive: Bool = this.HUDProgressBarBlackboard.GetBool(this.BlackboardDefs.UI_HUDProgressBar.Active);
            let progressBarTypeIsReveal: Bool = Equals(FromVariant<SimpleMessageType>(this.HUDProgressBarBlackboard.GetVariant(this.BlackboardDefs.UI_HUDProgressBar.MessageType)), SimpleMessageType.Reveal);

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

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmokingDebuff") {
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

    public final func GetInOverdose() -> Bool {
        return this.playerInOverdose;
    }

    public final func SetOverdoseState(inOverdose: Bool) -> Void {
        this.playerInOverdose = inOverdose;
        this.UpdateCriticalNeedEffects();
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

            // Play the camera wobble from low Hydration notifications, and after sprinting or dashing with low Hydration.
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
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathStopCallback.Create(), this.outOfBreathStopDelayID, this.outOfBreathStopDelayInterval);
	}

    private final func RegisterOutOfBreathRecheckSprintCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckSprintingCallback.Create(), this.outOfBreathRecheckSprintingDelayID, this.outOfBreathRecheckSprintingDelayInterval);
	}

	private final func RegisterOutOfBreathRecheckDefaultCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, OutOfBreathRecheckDefaultCallback.Create(), this.outOfBreathRecheckDefaultDelayID, this.outOfBreathRecheckDefaultDelayInterval);
	}

    private final func RegisterManagedEffectReconciliationDebounceDelayCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ManagedEffectReconciliationDebounceDelayCallback.Create(), this.managedEffectReconciliationDebounceDelayID, this.managedEffectReconciliationDebounceDelayInterval);
	}

    private final func RegisterManagedEffectVFXRecheckDelayCallback(useLastingDuration: Bool) -> Void {
        //DFProfile();
        let interval: Float;
        if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.LowToHigh) || 
           Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.HighToLow) ||
           Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToLow) ||
           Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
              interval = this.managedEffectVFXRecheckDelayInterval_Transition;
        
        } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.High) {
            if useLastingDuration {
                interval = this.managedEffectVFXRecheckDelayInterval_High_NormalLasting + RandRangeF(0.0, this.managedEffectVFXRecheckDelayInterval_Low_NormalVariance);
            } else {
                interval = this.managedEffectVFXRecheckDelayInterval_High_NormalTimed + RandRangeF(0.0, this.managedEffectVFXRecheckDelayInterval_Low_NormalVariance);
            }
        
        } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Low) {
            if useLastingDuration {
                interval = this.managedEffectVFXRecheckDelayInterval_Low_NormalLasting + RandRangeF(0.0, this.managedEffectVFXRecheckDelayInterval_Low_NormalVariance);
            } else {
                interval = this.managedEffectVFXRecheckDelayInterval_Low_NormalTimed + RandRangeF(0.0, this.managedEffectVFXRecheckDelayInterval_Low_NormalVariance);
            }
        }
        DFLog(this, "    Registering for an interval of " + ToString(interval) + "sec");

		RegisterDFDelayCallback(this.DelaySystem, ManagedEffectVFXRecheckDelayCallback.Create(), this.managedEffectVFXRecheckDelayID, interval, true);
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

    private final func UnregisterManagedEffectReconciliationDebounceDelayCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.managedEffectReconciliationDebounceDelayID);
	}

    private final func UnregisterManagedEffectVFXRecheckDelayCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.managedEffectVFXRecheckDelayID);
	}

    //
    //  Player State Effects
    //
    private final func RegisterPlayerStateEffectsDurationUpdateCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, PlayerStateEffectsDurationUpdateDelayCallback.Create(), this.playerStateEffectsDurationUpdateDelayID, this.playerStateEffectsDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

	private final func UnregisterPlayerStateEffectsDurationUpdateCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.playerStateEffectsDurationUpdateDelayID);
	}

    public final func OnPlayerStateEffectsDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
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
        
        this.RegisterPlayerStateEffectsDurationUpdateCallback();
    }

    public final func OnPlayerStateEffectsDurationUpdateFromTimeSkip(addictionData: DFAddictionDatum, timeSkipType: DFTimeSkipType) -> Void {
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
        this.AnimationService.TryToQueueAddictionWithdrawalAnimation(addictionData, timeSkipType);

        this.RegisterPlayerStateEffectsDurationUpdateCallback();
    }

    private func RefreshAddictionTreatmentEffect() -> Void {
        //DFProfile();
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
        this.RefreshAddictionTreatmentEffect();
		this.DispatchAddictionTreatmentEffectAppliedOrRemovedEvent();

        // Update the Nerve limit.
        this.NerveSystem.ForceNeedMaxValueUpdate();
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

    public final func GetPlayerStateEffectsDurationUpdateIntervalInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.playerStateEffectsDurationUpdateIntervalInGameTimeSeconds;
    }

    public final func DispatchAddictionManagedEffectApplied(type: DFManagedEffectType, stackCount: Int32, activeEffectApplied: Bool) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionManagedEffectAppliedEvent.Create(type, stackCount, activeEffectApplied));
    }

    public final func DispatchAddictionManagedEffectRemoved(type: DFManagedEffectType) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(PlayerStateServiceAddictionManagedEffectRemovedEvent.Create(type));
    }

    public final func HasEuphoria() -> Bool {
        return this.NerveSystem.GetOverchargeValue() > 0.0;
    }

    //
    // Critical Need Effects
    //
    private let updateCriticalNeedEffectsLock: RWLock;
    public final func UpdateCriticalNeedEffects() -> Void {
        RWLock.Acquire(this.updateCriticalNeedEffectsLock);
        if this.GameStateService.IsValidGameState(this, true) {
            let shouldPlayCriticalFX: Bool = false;
            let nerveValue: Float = this.NerveSystem.GetNeedValue();

            if this.Settings.nerveLossIsFatal && nerveValue <= this.criticalNeedFXThreshold && nerveValue != -1.0 {
                shouldPlayCriticalFX = true;
            }

            if this.GetInOverdose() && nerveValue != -1.0 {
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
    // Vehicle Speed
    //
    public final func TryToRegisterForVehicleSpeedChange(veh: ref<VehicleObject>) -> Void {
        this.lastActivePlayerVehicle = veh;

        if this.GameStateService.IsValidGameState(this) && IsSystemEnabledAndRunning(this) && !veh.IsQuest() {
            this.RegisterForVehicleSpeedChange();
        }
    }

    private final func RegisterForVehicleSpeedChange() -> Void {
        if IsDefined(this.lastActivePlayerVehicle) {
            let vehicleBlackboard: ref<IBlackboard> = this.lastActivePlayerVehicle.GetBlackboard();
            if IsDefined(vehicleBlackboard) {
                this.activePlayerVehicleSpeedListener = vehicleBlackboard.RegisterListenerFloat(GetAllBlackboardDefs().Vehicle.SpeedValue, this, n"OnActivePlayerVehicleSpeedValueChanged");
            }
        }
    }
    
    public final func UnregisterForVehicleSpeedChange(veh: ref<VehicleObject>) -> Void {
        let vehicleBlackboard: ref<IBlackboard> = veh.GetBlackboard();
        if IsDefined(vehicleBlackboard) {
            vehicleBlackboard.UnregisterListenerFloat(GetAllBlackboardDefs().Vehicle.SpeedValue, this.activePlayerVehicleSpeedListener);
            this.activePlayerVehicleSpeedListener = null;
            this.lastActivePlayerVehicleSpeed = 0;
            this.lastActivePlayerVehicle = null;
        }
    }

    // TODO - Cleanup
    private let testVeer: Bool = false;
    private cb func OnActivePlayerVehicleSpeedValueChanged(rawSpeed: Float) -> Bool {
        //DFProfile();
        //DFLog(this, "rawSpeed: " + ToString(rawSpeed));
        let velocity: Float = AbsF(rawSpeed);
        let multiplier: Float = GameInstance.GetStatsDataSystem(GetGameInstance()).GetValueFromCurve(n"vehicle_ui", velocity, n"speed_to_multiplier");
        let speedValue: Int32 = RoundMath(velocity * multiplier);

        // Make other systems aware of the speed value change.
        this.HumanityLossConditionSystem.OnActivePlayerVehicleSpeedValueChanged(speedValue, this.lastActivePlayerVehicleSpeed);

        this.lastActivePlayerVehicleSpeed = speedValue;
    }

    //
    // Managed Effects
    //
    public final func GetManagedEffectsState() -> array<DFManagedEffect> {
        return this.managedEffectsState;
    }

    public final func GetManagedEffectsStateAtIndex(idx: Int32) -> DFManagedEffect {
        return this.managedEffectsState[idx];
    }

    public final func GetManagedEffectByType(type: DFManagedEffectType) -> DFManagedEffect {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                return managedEffect;
                break;
            }
        }
    }

    public final func GetManagedEffectDefinitionByType(type: DFManagedEffectType) -> DFManagedEffectDefinition {
        for def in this.managedEffectDefinitions {
            if Equals(type, def.type) {
                return def;
                break;
            }
        }
    }

    public final func HandleAddictionProxyEffectApplied(type: DFAddictionProxyEffectType, id: TweakDBID, stackCount: Uint32) {
        // Handle this as if an item of that type had been consumed.
        StatusEffectHelper.RemoveStatusEffect(this.player, id, stackCount);

        if Equals(type, DFAddictionProxyEffectType.Alcohol) {
            this.HandleManagedConsumable(TweakDBInterface.GetItemRecord(t"Items.LowQualityAlcohol1"), true);
        }
    }

    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState(this, true) { return; }
		DFLog(this, "OnItemConsumed");

		let itemTags: array<CName> = itemRecord.Tags();
		if ArrayContains(itemTags, n"DarkFutureConsumableAddictionTreatmentDrug") {
            this.OnAddictionTreatmentDrugConsumed();
        
        } else if ArrayContains(itemTags, n"DarkFutureManagedConsumable") {
            this.HandleManagedConsumable(itemRecord, animateUI);
        }
	}

    public final func GetItemManagedEffectStateIndex(itemRecord: ref<Item_Record>) -> Int32 {
        let itemTags: array<CName> = itemRecord.Tags();
        
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            let def: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(this.managedEffectsState[i].type);
            if ArrayContains(itemTags, def.itemRecordTag) {
                return i;
                break;
            }
            i += 1;
        }

        return -1;
    }

    public final func GetItemManagedEffectDefinition(itemRecord: ref<Item_Record>) -> DFManagedEffectItemDefinition {
        let itemTags: array<CName> = itemRecord.Tags();

        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectItemDefinitions) {
            if ArrayContains(itemTags, this.managedEffectItemDefinitions[i].itemRecordTag) {
                return this.managedEffectItemDefinitions[i];
                break;
            }
            i += 1;
        }

        let invalidDef: DFManagedEffectItemDefinition;
        return invalidDef;
    }

    public final func ManagedConsumablePipeline(itemRecord: ref<Item_Record>, opt overrideWithMaxStackApplication: Bool) -> DFManagedEffectPipelineResult {
        let pipelineResult: DFManagedEffectPipelineResult;

        // Find this item's managed effect in state.
        let managedEffectStateIdx: Int32 = this.GetItemManagedEffectStateIndex(itemRecord);
        pipelineResult.managedEffectStateIndex = managedEffectStateIdx;

        let managedEffect: DFManagedEffect = this.managedEffectsState[managedEffectStateIdx];
        let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(managedEffect.type);
        if managedEffectStateIdx == -1 { return pipelineResult; }

        pipelineResult.type = managedEffect.type;

        // Find this item's managed effect item definition.
        let managedEffectItemDef: DFManagedEffectItemDefinition = this.GetItemManagedEffectDefinition(itemRecord);
        pipelineResult.managedEffectItemDef = managedEffectItemDef;
        if Equals(managedEffectItemDef.itemRecordTag, n"") { return pipelineResult; }

        // Determine the max stacks that can be applied, and the tolerance at this addiction stage (if applicable).
        let maxStacksAllowed: Int32;
        let toleranceStacksAtThisStage: Int32;
        let addictionSystem: ref<DFAddictionSystemBase> = this.GetAddictionSystemFromManagedEffectType(managedEffect.type);
        pipelineResult.addictionSystem = addictionSystem;

        if IsDefined(addictionSystem) && IsSystemEnabledAndRunning(addictionSystem) {
            let addictionStage: Int32 = addictionSystem.GetAddictionStage();
            maxStacksAllowed = managedEffectDef.maxStacksPerAddictionStage[addictionStage];
            toleranceStacksAtThisStage = managedEffectDef.toleranceStacksPerAddictionStage[addictionStage];
            DFLog(this, "maxStacksAllowed: " + ToString(maxStacksAllowed) + ", toleranceStacksAtThisStage: " + ToString(toleranceStacksAtThisStage));
        
        } else {
            maxStacksAllowed = managedEffectDef.maxStacks;
        }

        // How many are already applied?
        let currentlyAppliedTotalStackCount: Int32 = Cast<Int32>(this.GetManagedEffectTotalStacksByType(managedEffect.type));
        let currentlyAppliedToleranceCount :Int32 = Cast<Int32>(this.GetManagedEffectToleranceStacksByType(managedEffect.type));

        let toleranceRemaining: Int32 = Max(toleranceStacksAtThisStage - currentlyAppliedToleranceCount, 0);
        DFLog(this, "currentlyAppliedTotalStackCount: " + ToString(currentlyAppliedTotalStackCount) + ", toleranceRemaining: " + ToString(toleranceRemaining));

        // If there is room, apply stacks. If it would exceed the max, trigger a negative side effect.

        // Special case handling - Return a result that would max out this application.
        if overrideWithMaxStackApplication {
            let maxActiveStacks: Int32 = maxStacksAllowed - toleranceStacksAtThisStage;
            let activeRemaining: Int32 = maxActiveStacks - Cast<Int32>(this.GetManagedEffectActiveStacksByType(managedEffect.type));

            pipelineResult.toleranceStacksToApply = toleranceRemaining;
            pipelineResult.activeStacksToApply = activeRemaining;
            pipelineResult.triggerExcessStackEffect = false;
            return pipelineResult;
        }
        
        // How many stacks would this item apply?
        let stacksToApplyBeforeTolerance: Int32 = 0;
        if Equals(managedEffectItemDef.stackCountDef.mode, DFManagedEffectStackCountMode.Specific) {
            stacksToApplyBeforeTolerance = managedEffectItemDef.stackCountDef.countToApply;
        
        } else if Equals(managedEffectItemDef.stackCountDef.mode, DFManagedEffectStackCountMode.Random) {
            stacksToApplyBeforeTolerance = RandRangeInclusive(managedEffectItemDef.stackCountDef.countToApply, managedEffectItemDef.stackCountDef.countToApplyMax);
        }

        DFLog(this, "stacksToApplyBeforeTolerance: " + ToString(stacksToApplyBeforeTolerance));

        if stacksToApplyBeforeTolerance > 0 {
            // Apply the effect.
            // Tolerance takes away from the stacks to apply.
            let stacksToApplyAfterTolerance: Int32 = Max(stacksToApplyBeforeTolerance - toleranceRemaining, 0);
            let stacksToApplyAfterToleranceUnclamped: Int32 = stacksToApplyBeforeTolerance - toleranceRemaining;
            let toleranceStacksToApply: Int32 = stacksToApplyBeforeTolerance - stacksToApplyAfterTolerance;

            DFLog(this, "stacksToApply (after Tolerance): " + ToString(stacksToApplyAfterTolerance));

            if toleranceStacksToApply > 0 {
                pipelineResult.toleranceStacksToApply = toleranceStacksToApply;
                currentlyAppliedTotalStackCount += toleranceStacksToApply;
            }

            let stacksToApplyAfterActive: Int32 = 0;
            let stacksAvailable: Int32 = maxStacksAllowed - currentlyAppliedTotalStackCount;
            if stacksToApplyAfterToleranceUnclamped > 0 {
                stacksToApplyAfterActive = Max(stacksToApplyAfterToleranceUnclamped - stacksAvailable, 0);
                let activeStacksToApply: Int32 = stacksToApplyAfterToleranceUnclamped - stacksToApplyAfterActive;
                
                if activeStacksToApply > 0 {
                    pipelineResult.activeStacksToApply = activeStacksToApply;
                }
            }

            DFLog(this, "stacksToApply (after Active): " + ToString(stacksToApplyAfterActive));

            // Cyberware bonus.
            if Equals(managedEffect.type, DFManagedEffectType.Narcotic) && stacksAvailable > 0 {
                stacksToApplyAfterActive -= this.CyberwareService.GetNarcoticExcessStacksAllowedBonus();
            }

            if stacksToApplyAfterActive > 0 {
                pipelineResult.triggerExcessStackEffect = true;
            }
        }

        return pipelineResult;
    }

    public final func HandleManagedConsumable(itemRecord: ref<Item_Record>, animateUI: Bool, opt suppressExcessStackEffect: Bool, opt overridePipeline: DFManagedEffectPipelineResult) -> Void {
        let pipelineResult: DFManagedEffectPipelineResult;

        if !IsDefined(itemRecord) { return; }
        
        if IsDefined(overridePipeline.addictionSystem) {
            // Allows injecting custom results for special circumstances (like the Dum Dum Black Lace inhaler scene.)
            pipelineResult = overridePipeline;
        } else {
            pipelineResult = this.ManagedConsumablePipeline(itemRecord);
        }

        if pipelineResult.managedEffectStateIndex == -1 || Equals(pipelineResult.managedEffectItemDef.itemRecordTag, n"") { return; }

        let totalStacksApplied: Int32 = 0;
        let type: DFManagedEffectType = this.managedEffectsState[pipelineResult.managedEffectStateIndex].type;

        if pipelineResult.toleranceStacksToApply > 0 {
            // Mutate state.
            this.managedEffectsState[pipelineResult.managedEffectStateIndex].toleranceEffectCount += pipelineResult.toleranceStacksToApply;
            totalStacksApplied += pipelineResult.toleranceStacksToApply;
        }

        if pipelineResult.activeStacksToApply > 0 && NotEquals(pipelineResult.managedEffectItemDef.itemRecordTag, n"") {
            // Mutate state.
            this.ApplyManagedEffectStacks(type, pipelineResult.managedEffectItemDef, pipelineResult.managedEffectStateIndex, pipelineResult.activeStacksToApply, animateUI);
            totalStacksApplied += pipelineResult.activeStacksToApply;
        }

        if totalStacksApplied > 0 {
            // If anything was applied, let the Addiction System know.
            this.DispatchAddictionManagedEffectApplied(type, totalStacksApplied, pipelineResult.activeStacksToApply > 0);

            // If at least one stack was applied, apply any additional debuff status effects now.
            // They are not added or removed in the same way during status effect reconciliation.
            let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(type);
            if Equals(this.managedEffectsState[pipelineResult.managedEffectStateIndex].effectMode, DFManagedEffectMode.Timed) {
                if NotEquals(managedEffectDef.timedAdditionalDebuffID, t"") {
                    StatusEffectHelper.ApplyStatusEffect(this.player, managedEffectDef.timedAdditionalDebuffID);
                }
            } else if Equals(this.managedEffectsState[pipelineResult.managedEffectStateIndex].effectMode, DFManagedEffectMode.Lasting) {
                if NotEquals(managedEffectDef.lastingAdditionalDebuffID, t"") {
                    StatusEffectHelper.ApplyStatusEffect(this.player, managedEffectDef.lastingAdditionalDebuffID);
                }
            }
        }

        if pipelineResult.triggerExcessStackEffect && !suppressExcessStackEffect {
            this.TriggerExcessStackEffect(pipelineResult.managedEffectItemDef.excessStackDef, pipelineResult.addictionSystem);
        }

        this.PrintManagedEffectsState();
        this.ReconcileManagedStatusEffects();
    }

    private final func PrintManagedEffectsState() -> Void {
        DFLog(this, "===========================================================");
        DFLog(this, "New Managed Effects State");
        DFLog(this, "===========================================================");
        for managedEffect in this.managedEffectsState {
            DFLog(this, "    -");
            DFLog(this, "    Type: " + ToString(managedEffect.type));
            DFLog(this, "    -------------------------------------------------------");
            DFLog(this, "    effectMode: " + ToString(managedEffect.effectMode));
            DFLog(this, "    activeEffectEnergyChanges: " + ToString(managedEffect.activeEffectEnergyChanges));
            DFLog(this, "    toleranceEffectCount: " + ToString(managedEffect.toleranceEffectCount));
        }
    }

    private final func ApplyManagedEffectStacks(type: DFManagedEffectType, itemDef: DFManagedEffectItemDefinition, stateIdx: Int32, stacksToApply: Int32, animateUI: Bool) -> Void {
        let j: Int32 = 0;
        while j < stacksToApply {
            let energyToChange: Float = itemDef.energyChangeWhileActive;

            // Cyberware bonus.
            if Equals(type, DFManagedEffectType.Alcohol) {
                energyToChange += this.CyberwareService.GetAlcoholEnergyLossBonus();
            }
            
            // Handle if the Energy change would exceed the min or the max.
            let energyValue: Float = this.EnergySystem.GetNeedValue();
            if energyValue + energyToChange > 100.0 {
                energyToChange = 100.0 - energyValue;
            } else if energyValue + energyToChange < 0.0 {
                energyToChange = -energyValue;
            }

            // Actually change Needs.
            let props: DFChangeNeedValueProps;
            let uiFlags: DFNeedChangeUIFlags;
            uiFlags.forceMomentaryUIDisplay = true;
            uiFlags.instantUIChange = !animateUI;
            uiFlags.forceBright = true;
            uiFlags.momentaryDisplayIgnoresSceneTier = true;
            props.uiFlags = uiFlags;
            this.EnergySystem.ChangeNeedValue(energyToChange, props);

            let nerveToChange: Float = itemDef.nerveChangeWhenApplied;
            if nerveToChange > 0.0 {
                this.NerveSystem.ChangeNeedValue(nerveToChange, props);
            }

            // Mutate state.
            ArrayPush(this.managedEffectsState[stateIdx].activeEffectEnergyChanges, energyToChange);

            j += 1;
        }

        this.UpdateManagedEffectVFX(true);
    }

    private final func TriggerExcessStackEffect(excessStackDef: DFManagedEffectExcessStackDef, addictionSystem: ref<DFAddictionSystemBase>) -> Void {
        if Equals(excessStackDef.excessStackItemActionType, DFManagedEffectExcessStackItemActionType.None) {
            let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
            notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
            notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureMaxStacksNotification");
            notificationEvent.m_overrideCurrentNotification = true;
        
            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
        
        } else if IsDefined(addictionSystem) && IsSystemEnabledAndRunning(addictionSystem) {
            if Equals(excessStackDef.excessStackItemActionType, DFManagedEffectExcessStackItemActionType.Alcohol) {
                this.TriggerAlcoholExcessStackEffect();
                
            } else if Equals(excessStackDef.excessStackItemActionType, DFManagedEffectExcessStackItemActionType.Narcotic) {
                this.TriggerNarcoticExcessStackEffect();
            }

        } else {
            return;
        }
    }

    private final func TriggerAlcoholExcessStackEffect() -> Void {
        // Hydration and Nutrition loss, vomiting.
        this.AnimationService.TryToQueueCrashAnimation(DFCrashAnimMode.ForceVomit);

        let changeNeedValueProps: DFChangeNeedValueProps;

        let uiFlags: DFNeedChangeUIFlags;
        uiFlags.forceMomentaryUIDisplay = true;
        uiFlags.instantUIChange = true;
        uiFlags.forceBright = true;

        changeNeedValueProps.uiFlags = uiFlags;

        this.NutritionSystem.ChangeNeedValue(-30.0, changeNeedValueProps);
        this.HydrationSystem.ChangeNeedValue(-30.0, changeNeedValueProps);
    }

    private final func TriggerNarcoticExcessStackEffect() -> Void {
        // Overdose.
        if this.GameStateService.IsInAnyMenu() {
            let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
            notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
            notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureOverdoseAppliedNotification");
            notificationEvent.m_overrideCurrentNotification = true;
        
            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
        }

        this.NerveSystem.SetOverdoseBehavior(true, this.GetManagedEffectTotalStacksByType(DFManagedEffectType.Narcotic));
    }

    private final func ReconcileManagedStatusEffects() -> Void {
        // Ensures that the State and the actual applied Status Effects match.
        // Also performs the swap between Timed and Lasting effects.
        if this.isReconcilingStatusEffects { 
            this.repeatStatusEffectReconciliationOnComplete = true;
            return;
        }

        this.isReconcilingStatusEffects = true;

        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(this.managedEffectsState[i].type);
            let stateActiveEffectCount: Int32 = ArraySize(this.managedEffectsState[i].activeEffectEnergyChanges);
            let stateToleranceEffectCount: Int32 = this.managedEffectsState[i].toleranceEffectCount;

            let realActiveEffectCount: Int32 = 0;
            let realToleranceEffectCount: Int32 = 0;

            let activeEffectID: TweakDBID;
            let toleranceEffectID: TweakDBID;
            if Equals(this.managedEffectsState[i].effectMode, DFManagedEffectMode.Timed) {
                activeEffectID = managedEffectDef.timedActiveEffectID;
                toleranceEffectID = managedEffectDef.timedToleranceEffectID;

            } else if Equals(this.managedEffectsState[i].effectMode, DFManagedEffectMode.Lasting) {
                activeEffectID = managedEffectDef.lastingActiveEffectID;
                toleranceEffectID = managedEffectDef.lastingToleranceEffectID;
            }

            // Clear any real effects of an incorrect mode.
            if Equals(this.managedEffectsState[i].effectMode, DFManagedEffectMode.Timed) {
                let lastingActiveEffectStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, managedEffectDef.lastingActiveEffectID);
                if IsDefined(lastingActiveEffectStatus) {
                    StatusEffectHelper.RemoveStatusEffect(this.player, managedEffectDef.lastingActiveEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }

                let lastingToleranceEffectStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, managedEffectDef.lastingToleranceEffectID);
                if IsDefined(lastingToleranceEffectStatus) {
                    StatusEffectHelper.RemoveStatusEffect(this.player, managedEffectDef.lastingToleranceEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }

            } else if Equals(this.managedEffectsState[i].effectMode, DFManagedEffectMode.Lasting) {
                let timedActiveEffectStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, managedEffectDef.timedActiveEffectID);
                if IsDefined(timedActiveEffectStatus) {
                    StatusEffectHelper.RemoveStatusEffect(this.player, managedEffectDef.timedActiveEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }

                let timedToleranceEffectStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, managedEffectDef.timedToleranceEffectID);
                if IsDefined(timedToleranceEffectStatus) {
                    StatusEffectHelper.RemoveStatusEffect(this.player, managedEffectDef.timedToleranceEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }
            }

            // Store the counts for the correct and applied active effects.
            let realActiveEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, activeEffectID);
            if IsDefined(realActiveEffect) {
                realActiveEffectCount = Cast<Int32>(realActiveEffect.GetStackCount());
            }

            let realToleranceEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, toleranceEffectID);
            if IsDefined(realToleranceEffect) {
                realToleranceEffectCount = Cast<Int32>(realToleranceEffect.GetStackCount());
            }

            if stateActiveEffectCount > 0 {
                // If State Active Effect count is greater than 0, Tolerance effects should not be active.
                if realToleranceEffectCount > 0 {
                    // Nuke them.
                    StatusEffectHelper.RemoveStatusEffect(this.player, toleranceEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }

                // Ensure that the number of State Active Effects and real Active Effects match.
                if stateActiveEffectCount != realActiveEffectCount {
                    if realActiveEffectCount > 0 {
                        // Nuke them.
                        StatusEffectHelper.RemoveStatusEffect(this.player, activeEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                    }

                    // Re-apply all.
                    let j: Int32 = 0;
                    while j < ArraySize(this.managedEffectsState[i].activeEffectEnergyChanges) {
                        StatusEffectHelper.ApplyStatusEffect(this.player, activeEffectID);
                        j += 1;
                    }
                }

            } else {
                // If State Active Effect Count is 0, we should not have any Active effects.
                if realActiveEffectCount > 0 {
                    // Nuke them.
                    StatusEffectHelper.RemoveStatusEffect(this.player, activeEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                }

                if stateToleranceEffectCount != realToleranceEffectCount {
                    if realToleranceEffectCount > 0 {
                        // Nuke them.
                        StatusEffectHelper.RemoveStatusEffect(this.player, toleranceEffectID, Cast<Uint32>(managedEffectDef.maxStacks));
                    }
                    
                    // Re-apply all.
                    let j: Int32 = 0;
                    while j < this.managedEffectsState[i].toleranceEffectCount {
                        StatusEffectHelper.ApplyStatusEffect(this.player, toleranceEffectID);
                        j += 1;
                    }
                }
            }

            i += 1;
        }

        this.RegisterManagedEffectReconciliationDebounceDelayCallback();
    }

    public final func SwitchManagedEffectModeOfType(mode: DFManagedEffectMode, type: DFManagedEffectType, opt skipStatusEffectReconcile: Bool) -> Void {
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            if Equals(type, this.managedEffectsState[i].type) {
                this.managedEffectsState[i].effectMode = mode;
                break;
            }
            i += 1;
        }

        if !skipStatusEffectReconcile {
            this.ReconcileManagedStatusEffects();
        }
    }

    public final func GetAddictionSystemFromManagedEffectType(type: DFManagedEffectType) -> ref<DFAddictionSystemBase> {
        if Equals(type, DFManagedEffectType.Alcohol) {
            return this.AlcoholAddictionSystem;

        } else if Equals(type, DFManagedEffectType.Nicotine) {
            return this.NicotineAddictionSystem;

        } else if Equals(type, DFManagedEffectType.Narcotic) {
            return this.NarcoticAddictionSystem;
        
        } else {
            return null;
        }
    }

    public final func SetManagedEffectToleranceCountToMaxByType(type: DFManagedEffectType) -> Void {
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            if Equals(type, this.managedEffectsState[i].type) {
                this.managedEffectsState[i].toleranceEffectCount = Cast<Int32>(this.GetManagedEffectToleranceStacksAtThisAddictionStageByType(type));
                break;
            }
            i += 1;
        }

        this.ReconcileManagedStatusEffects();
    }

    public final func OnManagedEffectRemoved(evt: ref<RemoveStatusEffect>) -> Void {
        if DFRunGuard(this) { return; }
        if this.isReconcilingStatusEffects { return; }
		if this.EnergySystem.isSkippingTime { return; }

        let realStatusEffect: ref<StatusEffect_Record> = evt.staticData;
		let realStatusID: TweakDBID = realStatusEffect.GetID();

        this.OnManagedEffectRemovedImpl(realStatusID);
    }

    private final func OnManagedEffectRemovedImpl(statusEffectID: TweakDBID) {
        let stateIdx: Int32 = -1;
        let wasActiveEffect: Bool = false;
        let type: DFManagedEffectType;
        
        // Match this status effect to a Managed Effect.
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(this.managedEffectsState[i].type);
            if Equals(statusEffectID, managedEffectDef.timedActiveEffectID) {
                DFLog(this, "Effect removed was a Timed Active Effect.");
                stateIdx = i;
                type = managedEffectDef.type;
                wasActiveEffect = true;
                break;
            } else if Equals(statusEffectID, managedEffectDef.lastingActiveEffectID) {
                DFLog(this, "Effect removed was a Lasting Active Effect.");
                stateIdx = i;
                type = managedEffectDef.type;
                wasActiveEffect = true;
                break;
            } else if Equals(statusEffectID, managedEffectDef.timedToleranceEffectID) ||
                      Equals(statusEffectID, managedEffectDef.lastingToleranceEffectID) {
                DFLog(this, "Effect removed was a Tolerance Effect.");
                stateIdx = i;
                type = managedEffectDef.type;
                break;
            }

            i += 1;
        }

        if stateIdx == -1 { return; }
        
        let stackCount: Int32 = 0;
        let status: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, statusEffectID);
        if IsDefined(status) {
            stackCount = Cast<Int32>(status.GetStackCount());
            DFLog(this, "The remaining stack count of this effect is now: " + ToString(stackCount));
        }

        if wasActiveEffect {
            let delta: Int32 = ArraySize(this.managedEffectsState[stateIdx].activeEffectEnergyChanges) - stackCount;
            DFLog(this, "Delta between applied count and state count is: " + ToString(delta));
            let j: Int32 = 0;
            while j < delta {
                let energyToChange: Float = ArrayPop(this.managedEffectsState[stateIdx].activeEffectEnergyChanges);

				let changeNeedValueProps: DFChangeNeedValueProps;

				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.instantUIChange = false;
				uiFlags.forceBright = true;

				changeNeedValueProps.uiFlags = uiFlags;

				if this.BiocorruptionConditionSystem.GetHasEuphoria() && energyToChange > 0.0 {
					// If under Euphoria, instead of removing the amount, add it to the delayed need loss pool.
					// TODO - Make sure timeskip also does this
                    // TODO - Euphoria should be utilizing Lasting effects, verify
					this.EnergySystem.currentDelayedNeedLoss -= energyToChange;
                    DFLog(this, "Adding " + ToString(energyToChange) + " Energy change to the delayed need loss pool.");
				} else {
                    DFLog(this, "Changing Energy by: " + ToString(-energyToChange));
					this.EnergySystem.ChangeNeedValue(-energyToChange, changeNeedValueProps);
				}
                j += 1;
            }

            if ArraySize(this.managedEffectsState[stateIdx].activeEffectEnergyChanges) == 0 {
                // Mutate state.
                this.managedEffectsState[stateIdx].toleranceEffectCount = 0;
                DFLog(this, "Because the stack count was 0, cleared the Tolerance effect count in state.");
            }
        } else {
            // Mutate state.
            this.managedEffectsState[stateIdx].toleranceEffectCount = stackCount;
            DFLog(this, "Updated tolerance stack count in state.");
        }

        this.PrintManagedEffectsState();
        this.DispatchAddictionManagedEffectRemoved(type);
        this.UpdateManagedEffectVFX(true);
	}

    public final func ClearAllManagedEffects(opt fromTimeskip: Bool) -> Void {
		//DFProfile();
        let energyToChange: Float;
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            DFLog(this, "Checking managedEffectsState " + ToString(i));
            if !fromTimeskip || Equals(this.managedEffectsState[i].effectMode, DFManagedEffectMode.Timed) {
                let shouldNotifyAddictionSystem: Bool = false;
                for activeEffectEnergyChange in this.managedEffectsState[i].activeEffectEnergyChanges {
                    energyToChange += -activeEffectEnergyChange;
                    shouldNotifyAddictionSystem = true;
                }

                // Mutate state.
                ArrayClear(this.managedEffectsState[i].activeEffectEnergyChanges);
                this.managedEffectsState[i].toleranceEffectCount = 0;

                if shouldNotifyAddictionSystem {
                    this.DispatchAddictionManagedEffectRemoved(this.managedEffectsState[i].type);
                }
            }

            i += 1;
        }

        this.PrintManagedEffectsState();

        if !fromTimeskip {
            let props: DFChangeNeedValueProps;
            let uiFlags: DFNeedChangeUIFlags;
            uiFlags.forceMomentaryUIDisplay = true;
            uiFlags.instantUIChange = false;
            uiFlags.forceBright = true;
            uiFlags.momentaryDisplayIgnoresSceneTier = true;
            props.uiFlags = uiFlags;
            this.EnergySystem.ChangeNeedValue(energyToChange, props);
        }

        this.ReconcileManagedStatusEffects();
        this.UpdateManagedEffectVFX(true);
	}

    public final func ClearManagedEffectOfTypeAndReturnEnergyToChange(type: DFManagedEffectType) -> Float {
        let energyToChange: Float;
        let i: Int32 = 0;
        while i < ArraySize(this.managedEffectsState) {
            if Equals(this.managedEffectsState[i].type, type) {
                let shouldMutateState: Bool = false;
                for activeEffectEnergyChange in this.managedEffectsState[i].activeEffectEnergyChanges {
                    energyToChange += -activeEffectEnergyChange;
                    shouldMutateState = true;
                }

                if shouldMutateState {
                    // Mutate state.
                    ArrayClear(this.managedEffectsState[i].activeEffectEnergyChanges);
                    this.managedEffectsState[i].toleranceEffectCount = 0;
                    this.DispatchAddictionManagedEffectRemoved(type);
                }
                break;
            }

            i += 1;
        }

        this.PrintManagedEffectsState();
        this.ReconcileManagedStatusEffects();
        this.UpdateManagedEffectVFX(true);
        return energyToChange;
    }

    public final func GetManagedEffectTotalStacksByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                return Cast<Uint32>(ArraySize(managedEffect.activeEffectEnergyChanges)) + Cast<Uint32>(managedEffect.toleranceEffectCount);
                break;
            }
        }
    }

    public final func GetManagedEffectActiveStacksByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                return Cast<Uint32>(ArraySize(managedEffect.activeEffectEnergyChanges));
                break;
            }
        }
    }

    public final func GetAllManagedEffectEuphoriaActiveStacks() -> Uint32 {
        let stacks: Uint32;
        
        for managedEffect in this.managedEffectsState {
            let def: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(managedEffect.type);
            if def.contributesToEuphoria {
                stacks += Cast<Uint32>(ArraySize(managedEffect.activeEffectEnergyChanges));
            }
        }

        return stacks;
    }

    public final func GetManagedEffectToleranceStacksByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                return Cast<Uint32>(managedEffect.toleranceEffectCount);
                break;
            }
        }
    }

    public final func GetManagedEffectItemDefinitionByTag(itemRecordTag: CName) -> DFManagedEffectItemDefinition {
        for def in this.managedEffectItemDefinitions {
            if Equals(def.itemRecordTag, itemRecordTag) {
                return def;
                break;
            }
        }
    }

    public final func GetManagedEffectMaxStacksByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                let addictionSystem: ref<DFAddictionSystemBase> = this.GetAddictionSystemFromManagedEffectType(type);
                let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(managedEffect.type);
                
                if !IsDefined(addictionSystem) {
                    return Cast<Uint32>(managedEffectDef.maxStacks);

                } else {
                    return Cast<Uint32>(managedEffectDef.maxStacksPerAddictionStage[addictionSystem.GetAddictionStage()]);
                }
                break;        
            }
        }
    }

    public final func GetManagedEffectToleranceStacksAtThisAddictionStageByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(managedEffect.type);
                return Cast<Uint32>(managedEffectDef.toleranceStacksPerAddictionStage[this.GetAddictionSystemFromManagedEffectType(type).GetAddictionStage()]);
                break;
            }
        }
    }

    public final func GetManagedEffectActiveStacksAtThisAddictionStageByType(type: DFManagedEffectType) -> Uint32 {
        for managedEffect in this.managedEffectsState {
            if Equals(type, managedEffect.type) {
                let managedEffectDef: DFManagedEffectDefinition = this.GetManagedEffectDefinitionByType(managedEffect.type);
                let addictionSystem: ref<DFAddictionSystemBase> = this.GetAddictionSystemFromManagedEffectType(type);
                if IsDefined(addictionSystem) {
                    let addictionStage: Int32 = addictionSystem.GetAddictionStage();
                    let toleranceStacks: Int32 = managedEffectDef.toleranceStacksPerAddictionStage[addictionStage];
                    return Cast<Uint32>(managedEffectDef.maxStacksPerAddictionStage[addictionStage] - toleranceStacks);
                } else {
                    return Cast<Uint32>(managedEffectDef.maxStacks);
                }
                
                break;
            }
        }
    }

    public final func OnManagedEffectReconciliationDebounceCallback() -> Void {
        this.isReconcilingStatusEffects = false;

        if this.repeatStatusEffectReconciliationOnComplete {
            this.repeatStatusEffectReconciliationOnComplete = false;
            this.ReconcileManagedStatusEffects();
        }
    }

    public final func OnManagedEffectVFXRecheckCallback() -> Void {
        this.UpdateManagedEffectVFX();
    }

    public final func UpdateManagedEffectVFX(opt fromStateChange: Bool) -> Void {
        DFLog(this, "UpdateManagedEffectVFX fromStateChange: " + ToString(fromStateChange));
        let shouldConsumableEffectBeActive: Bool = false;
        let isAnyEffectLasting: Bool = false;
        let forceRegistration: Bool = false;
        let transitionedStates: Bool = false;
        let lastVFXIntensity: DFManagedEffectVFXIntensity = this.currentManagedEffectVFXIntensity;
        let lastAlcoholVFXSeverityHigh: Bool = this.currentAlcoholVFXSeverityHigh;
        let lastNarcoticVFXSeverityHigh: Bool = this.currentNarcoticVFXSeverityHigh;

        let alcoholActiveStackCount: Uint32 = this.GetManagedEffectActiveStacksByType(DFManagedEffectType.Alcohol);
        let narcoticActiveStackCount: Uint32 = this.GetManagedEffectActiveStacksByType(DFManagedEffectType.Narcotic);

        if alcoholActiveStackCount > 0u {
            DFLog(this, "    Should be active! (Alcohol)");
            shouldConsumableEffectBeActive = true;
            
            let managedEffect: DFManagedEffect = this.GetManagedEffectByType(DFManagedEffectType.Alcohol);
            if Equals(managedEffect.effectMode, DFManagedEffectMode.Lasting) {
                isAnyEffectLasting = true;
            }

            if alcoholActiveStackCount > 2u {
                this.currentAlcoholVFXSeverityHigh = true;
            } else {
                this.currentAlcoholVFXSeverityHigh = false;
            }
        }

        if narcoticActiveStackCount > 0u {
            DFLog(this, "    Should be active! (Narcotic)");
            shouldConsumableEffectBeActive = true;

            let managedEffect: DFManagedEffect = this.GetManagedEffectByType(DFManagedEffectType.Narcotic);
            if Equals(managedEffect.effectMode, DFManagedEffectMode.Lasting) {
                isAnyEffectLasting = true;
            }

            if narcoticActiveStackCount > 2u {
                this.currentNarcoticVFXSeverityHigh = true;
            } else {
                this.currentNarcoticVFXSeverityHigh = false;
            }
        }
        
        let alcoholChangedSeverities: Bool = NotEquals(lastAlcoholVFXSeverityHigh, this.currentAlcoholVFXSeverityHigh);
        let narcoticChangedSeverities: Bool = NotEquals(lastNarcoticVFXSeverityHigh, this.currentNarcoticVFXSeverityHigh);

        if shouldConsumableEffectBeActive && (!fromStateChange || Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Off)) {
            if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Off) {
                DFLog(this, "    Switching from OFF to ANY->HIGH");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.AnyToHigh;
                forceRegistration = true;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Low) {
                DFLog(this, "    Switching from LOW to LOW->HIGH");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.LowToHigh;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.LowToHigh) {
                DFLog(this, "    Switching from LOW->HIGH to HIGH");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.High;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.High) {
                DFLog(this, "    Switching from HIGH to HIGH->LOW");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.HighToLow;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.HighToLow) {
                DFLog(this, "    Switching from HIGH->LOW to LOW");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.Low;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToLow) {
                DFLog(this, "    Switching from ANY->LOW to LOW");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.Low;
                transitionedStates = true;

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
                DFLog(this, "    Switching from ANY->HIGH to HIGH");
                this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.High;
                transitionedStates = true;

            }
        } else if shouldConsumableEffectBeActive {
            DFLog(this, "    Keeping existing intensity!");
            if alcoholChangedSeverities {
                DFLog(this, "    Alcohol changed severities!");
                if this.currentAlcoholVFXSeverityHigh {
                    DFLog(this, "    Switching from ANY to ANY->HIGH");
                    this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.AnyToHigh;
                    forceRegistration = true;
                    transitionedStates = true;
                } else if NotEquals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
                    DFLog(this, "    Switching from LOW / HIGH->LOW to ANY->LOW");
                    this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.AnyToLow;
                    forceRegistration = true;
                    transitionedStates = true;
                } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
                    DFLog(this, "    Currently switching to higher intensity, ignore.");
                }

            } else if narcoticChangedSeverities {
                DFLog(this, "    Narcotic changed severities!");
                if this.currentNarcoticVFXSeverityHigh {
                    DFLog(this, "    Switching from ANY to ANY->HIGH");
                    this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.AnyToHigh;
                    forceRegistration = true;
                    transitionedStates = true;
                } else if NotEquals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
                    DFLog(this, "    Switching from LOW / HIGH->LOW to ANY->LOW");
                    this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.AnyToLow;
                    forceRegistration = true;
                    transitionedStates = true;
                } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {
                    DFLog(this, "    Currently switching to higher intensity, ignore.");
                }

            } else {
                DFLog(this, "    Ignore request.");
            }

        } else {
            // Should not be active; set to Off.
            DFLog(this, "    Switching to OFF");
            this.currentManagedEffectVFXIntensity = DFManagedEffectVFXIntensity.Off;
        }

        if NotEquals(lastVFXIntensity, DFManagedEffectVFXIntensity.Off) && Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Off) {
            // Stop any effects.
            DFLog(this, "    Stopping VFX!");
            this.StopManagedEffectVFX();
        
        } else if transitionedStates {
            // Switch to the new intensity.
            if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.High) {
                if alcoholActiveStackCount == 0u {
                    GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholMotionBlurEffect);
                    GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 0.00);

                } else if alcoholActiveStackCount <= 2u {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.alcoholMotionBlurEffect, false, null, true);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 2.00);

                } else {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.alcoholMotionBlurEffect, false, null, true);
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.alcoholWaveEffect);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 3.00);
                }

                if narcoticActiveStackCount == 0u {
                    GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomLowColorEffect);
                    GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 0.00);

                } else if narcoticActiveStackCount <= 2u {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.narcoticsBloomLowColorEffect, false, null, true);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 2.00);
                } else {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.narcoticsBloomHighColorEffect, false, null, true);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 3.00);
                }

                if narcoticActiveStackCount >= 3u || alcoholActiveStackCount >= 3u {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.chromaticAbberationHighEffect, false, null, true);
                } else if narcoticActiveStackCount >= 1u || alcoholActiveStackCount >= 1u {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.chomaticAbberationLowEffect, false, null, true);
                }
            
            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.HighToLow) {
                
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholWaveEffect);
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomHighColorEffect);
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomLowColorEffect);
            
            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.Low) {
                if alcoholActiveStackCount == 0u {
                    GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholMotionBlurEffect);
                    GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 0.00);

                } else if alcoholActiveStackCount <= 2u {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.alcoholMotionBlurEffect, false, null, true);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 1.00);
                } else {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.alcoholMotionBlurEffect, false, null, true);
					GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 2.00);
                }

                if narcoticActiveStackCount == 0u {
                    GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomLowColorEffect);
                    GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomHighColorEffect);
                    GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 0.00);
                } else {
                    GameObjectEffectHelper.StartEffectEvent(this.player, this.narcoticsBloomLowColorEffect, false, null, true);
                    GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 1.00);
                }
            
            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.LowToHigh) {
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomHighColorEffect);
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomLowColorEffect);

            } else if Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToLow) || Equals(this.currentManagedEffectVFXIntensity, DFManagedEffectVFXIntensity.AnyToHigh) {

                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholWaveEffect);
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.chomaticAbberationLowEffect);
                GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.chromaticAbberationHighEffect);

            }
        }

        if shouldConsumableEffectBeActive && (!fromStateChange || alcoholChangedSeverities || narcoticChangedSeverities || forceRegistration) {
            this.RegisterManagedEffectVFXRecheckDelayCallback(isAnyEffectLasting);
        } else {
            DFLog(this, "    Ignored re-registration.");
        }
    }

    private final func StopManagedEffectVFX() -> Void {
        this.UnregisterManagedEffectVFXRecheckDelayCallback();
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholMotionBlurEffect);
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.alcoholWaveEffect);
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomLowColorEffect);
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.narcoticsBloomHighColorEffect);
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.chomaticAbberationLowEffect);
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, this.chromaticAbberationHighEffect);
		GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drunk_level", 0.00);
        GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 0.00);
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
    let gameInstance: GameInstance = GetGameInstance();
    
    let dangerState: DFPlayerDangerState = DFPlayerStateService.GetInstance(gameInstance).GetPlayerDangerState();
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
    let gameInstance: GameInstance = GetGameInstance();
    
    let dangerState: DFPlayerDangerState = DFPlayerStateService.GetInstance(gameInstance).GetPlayerDangerState();
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

// VehicleObject - Register for vehicle speed changes on mount.
//
@wrapMethod(VehicleObject)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
	//DFProfile();
	let r: Bool = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() && VehicleComponent.IsDriverSlot(evt.request.lowLevelMountingInfo.slotId.id) {		
		DFPlayerStateService.Get().TryToRegisterForVehicleSpeedChange(this);
	}

	return r;
}

// VehicleObject - Unregister for vehicle speed changes on unmount.
//
@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	//DFProfile();
	let r: Bool = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		DFPlayerStateService.Get().UnregisterForVehicleSpeedChange(this);
	}
	
	return r;
}

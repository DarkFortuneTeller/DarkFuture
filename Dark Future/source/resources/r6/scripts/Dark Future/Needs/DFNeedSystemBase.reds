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
import DarkFuture.Utils.DFRunGuard
import DarkFuture.Main.{
    DFMainSystem,
    DFTimeSkipData,
    DFNeedChangeDatum,
    DFBiocorruptionDatum,
    MainSystemItemConsumedEvent
}
import DarkFuture.Addictions.{
    DFAlcoholAddictionSystem,
    DFNicotineAddictionSystem,
    DFNarcoticAddictionSystem
}
import DarkFuture.Conditions.{
    DFBiocorruptionConditionSystem,
    BiocorruptionApplyDelayedNeedLossEvent,
    DFBiocorruptionDelayedNeedLossDatum
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
    DFTutorial,
    DFNotification,
    DFAudioCue

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
    public persistent let value: Float;
    public persistent let forceMomentaryUIDisplay: Bool;
    public persistent let isSoftCapRestrictedChange: Bool;
    public persistent let effectToApplyAfterValueChange: TweakDBID;
    public persistent let isFromBlackout: Bool;
    public persistent let finalChangeInEuphoriaDepletion: Bool;
    public persistent let isFromTimeskip: Bool;
    public persistent let isMaxValueUpdate: Bool;
    public persistent let skipFX: Bool;
    public persistent let targetValueMode: Bool;
    public persistent let targetDelayedValue: Float;
    public persistent let skipSevereNeedMessage: Bool;
    public persistent let highestCrashStackCountOnTimeskip: Uint32;
    public persistent let biocorruptionData: DFBiocorruptionDatum;
}

public struct DFNeedValueChangedEventDatum {
    public let needType: DFNeedType;
    public let change: Float;
    public let newValue: Float;
    public let isMaxValueUpdate: Bool;
    public let fromDanger: Bool;
}

public struct DFChangeNeedValueProps {
    public let uiFlags: DFNeedChangeUIFlags;
    public let suppressRecoveryNotification: Bool;
    public let isMaxValueUpdate: Bool;
    public let maxOverride: Float;
    public let isSoftCapRestrictedChange: Bool;
    public let fromDanger: Bool;
    public let doNotUpdateUIIfNoChange: Bool;
    public let skipFX: Bool;
    public let delayPercent: Float;
    public let finalChangeInEuphoriaDepletion: Bool;
    public let isFromTimeskip: Bool;
    public let targetValueMode: Bool;
    public let targetDelayedValue: Float;
    public let skipSevereNeedMessage: Bool;
    public let highestCrashStackCountOnTimeskip: Uint32;
    public let biocorruptionData: DFBiocorruptionDatum;
}

public struct DFNeedChangeWithRecoverLimit {
    public let change: Float;
    public let delayedLoss: Float;
    public let showLock: Bool;
}

public enum DFItemBenefitRestrictedNotificationType {
    None = 0,
    MaxStacks = 1
}

public class NeedUpdateDelayCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<NeedUpdateDelayCallback> = new NeedUpdateDelayCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.updateDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnUpdate();
    }
}

public class NeedStageChangeFXStartDelayCallback extends DFDelayCallback {
    public let NeedSystemBase: wref<DFNeedSystemBase>;
    public let needStage: Int32;
    public let suppressRecoveryNotification: Bool;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>, needStage: Int32, suppressRecoveryNotification: Bool) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<NeedStageChangeFXStartDelayCallback> = new NeedStageChangeFXStartDelayCallback();
        self.NeedSystemBase = needSystemBase;
        self.needStage = needStage;
        self.suppressRecoveryNotification = suppressRecoveryNotification;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.needStageChangeFXStartDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnNeedStageChangeFXStart(this.needStage, this.suppressRecoveryNotification);
    }
}

public class InsufficientNeedFXStopDelayCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<InsufficientNeedFXStopDelayCallback> = new InsufficientNeedFXStopDelayCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.insufficientNeedFXStopDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnInsufficientNeedFXStop();
    }
}

public class InsufficientNeedRepeatFXDelayCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<InsufficientNeedRepeatFXDelayCallback> = new InsufficientNeedRepeatFXDelayCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.insufficientNeedRepeatFXDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnInsufficientNeedRepeatFX();
    }
}

public class ContextuallyDelayedNeedValueChangeDelayCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<ContextuallyDelayedNeedValueChangeDelayCallback> = new ContextuallyDelayedNeedValueChangeDelayCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.contextuallyDelayedNeedValueChangeDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.TryToApplyContextuallyDelayedNeedValueChange();
    }
}

public class SceneTierChangedCheckFXCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<SceneTierChangedCheckFXCallback> = new SceneTierChangedCheckFXCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.sceneTierChangedCheckFXDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnSceneTierChangedCheckFXCallback();
    }
}

public class StatusEffectRefreshDebounceCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<StatusEffectRefreshDebounceCallback> = new StatusEffectRefreshDebounceCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.statusEffectRefreshDebounceDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.RefreshNeedStatusEffects();
    }
}

public class UpdateNeedsHUDUIEvent extends CallbackSystemEvent {
    private let data: DFNeedHUDUIUpdate;

    public func GetData() -> DFNeedHUDUIUpdate {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: DFNeedHUDUIUpdate) -> ref<UpdateNeedsHUDUIEvent> {
        //DFProfile();
        let event: ref<UpdateNeedsHUDUIEvent> = new UpdateNeedsHUDUIEvent();
        event.data = data;
        return event;
    }
}

public class DFNeedValueChangedEvent extends CallbackSystemEvent {
    private let data: DFNeedValueChangedEventDatum;

    public func GetData() -> DFNeedValueChangedEventDatum {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: DFNeedValueChangedEventDatum) -> ref<DFNeedValueChangedEvent> {
        //DFProfile();
        let event: ref<DFNeedValueChangedEvent> = new DFNeedValueChangedEvent();
        event.data = data;
        return event;
    }
}

public class PlayerDeathCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<PlayerDeathCallback> = new PlayerDeathCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.playerDeathDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnPlayerDeathCallback();
    }
}

public class PostPlayerDeathCallback extends DFDelayCallback {
    public let NeedSystemBase: ref<DFNeedSystemBase>;

    public static func Create(needSystemBase: ref<DFNeedSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<PostPlayerDeathCallback> = new PostPlayerDeathCallback();
        self.NeedSystemBase = needSystemBase;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.NeedSystemBase.postPlayerDeathDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.NeedSystemBase.OnPostPlayerDeathCallback();
    }
}

public abstract class DFNeedSystemEventListener extends DFSystemEventListener {
    //
    // Required Overrides
    //
    private func GetSystemInstance() -> wref<DFNeedSystemBase> {
        //DFProfile();
        DFLogNoSystem(DFSystemlessDebugEnabled(), this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
        return null;
    }

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<MainSystemItemConsumedEvent>(), this, n"OnMainSystemItemConsumedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceSceneTierChangedEvent>(), this, n"OnGameStateServiceSceneTierChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceFuryChangedEvent>(), this, n"OnGameStateServiceFuryChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFGameStateServiceCyberspaceChangedEvent>(), this, n"OnGameStateServiceCyberspaceChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<HUDSystemUpdateUIRequestEvent>(), this, n"OnHUDSystemUpdateUIRequestEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<BiocorruptionApplyDelayedNeedLossEvent>(), this, n"OnBiocorruptionApplyDelayedNeedLossEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI());
    }

    private cb func OnGameStateServiceSceneTierChangedEvent(event: ref<DFGameStateServiceSceneTierChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnSceneTierChanged(event.GetData());
    }

    private cb func OnGameStateServiceFuryChangedEvent(event: ref<DFGameStateServiceFuryChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnFuryStateChanged(event.GetData());
    }

    private cb func OnGameStateServiceCyberspaceChangedEvent(event: ref<DFGameStateServiceCyberspaceChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnCyberspaceChanged(event.GetData());
    }

    private cb func OnHUDSystemUpdateUIRequestEvent(event: ref<HUDSystemUpdateUIRequestEvent>) {
        //DFProfile();
        this.GetSystemInstance().UpdateNeedHUDUI();
    }

    private cb func OnBiocorruptionApplyDelayedNeedLossEvent(event: ref<BiocorruptionApplyDelayedNeedLossEvent>) {
        //DFProfile();
        this.GetSystemInstance().ApplyDelayedNeedLoss(event.data);
    }
}

public abstract class DFNeedSystemBase extends DFSystem {
    public persistent let needValue: Float = 100.0;
    public persistent let needValueOvercharge: Float = 0.0;
    public persistent let currentDelayedNeedLoss: Float = 0.0;
    private persistent let queuedContextuallyDelayedNeedValueChange: array<DFQueuedNeedValueChange>;
    
    private let MainSystem: ref<DFMainSystem>;
    private let InteractionSystem: ref<DFInteractionSystem>;
    public let GameStateService: ref<DFGameStateService>;
    public let NotificationService: ref<DFNotificationService>;
    public let CyberwareService: ref<DFCyberwareService>;
    public let PlayerStateService: ref<DFPlayerStateService>;
    public let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    public let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    public let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
    public let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem>;

    public let needStageThresholdDeficits: array<Float>;
    public let needStageStatusEffects: array<TweakDBID>;
    
    public let updateDelayID: DelayID;
    public let contextuallyDelayedNeedValueChangeDelayID: DelayID;
    public let needStageChangeFXStartDelayID: DelayID;
    public let insufficientNeedRepeatFXDelayID: DelayID;
    public let sceneTierChangedCheckFXDelayID: DelayID;
    public let insufficientNeedFXStopDelayID: DelayID;
    public let statusEffectRefreshDebounceDelayID: DelayID;
    public let playerDeathDelayID: DelayID;
    public let postPlayerDeathDelayID: DelayID;

    public const let updateIntervalInGameTimeSeconds: Float = 300.0;
    private const let contextuallyDelayedNeedValueChangeDelayInterval: Float = 0.25;
    private const let needStageChangeFXStartDelayInterval: Float = 0.1;
    private const let insufficientNeedRepeatFXStage3DelayInterval: Float = 240.0;
    private const let insufficientNeedRepeatFXStage4DelayInterval: Float = 120.0;
    private const let sceneTierChangedCheckFXDelayInterval: Float = 2.0;
    private const let statusEffectRefreshDebounceDelayInterval: Float = 0.5;
    private const let playerDeathDelayInterval: Float = 2.0;
    private const let postPlayerDeathDelayInterval: Float = 8.0;
    private const let basicNeedPostDeathRestoreAmount: Float = 10.0;
    public const let criticalNeedThreshold: Float = 10.0;
    public const let extremelyCriticalNeedThreshold: Float = 5.0;
    public const let maxOvercharge: Float = 50.0;
    public const let sleepingReduceMetabolismMult: Float = 0.4;
    
    public let needMax: Float = 100.0;
    public let lastNeedStage: Int32 = 0;
    public let lastValueForCriticalNeedCheck: Float = 100.0;
    public let inDeathState: Bool = false;
    public let blackoutNeedChangePending: Bool = false;   // Used by DFNeedSystemEnergy

    //
    //  DFSystem Required Methods
    //
    public func SetupData() -> Void {
        //DFProfile();
        this.needStageThresholdDeficits = [
            100.0 - this.Settings.basicNeedThresholdValue1V2,
            100.0 - this.Settings.basicNeedThresholdValue2V2,
            100.0 - this.Settings.basicNeedThresholdValue3V2,
            100.0 - this.Settings.basicNeedThresholdValue4V2,
            100.0
        ];
    }

    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.SuspendFX();

        // Failsafe
        if this.needValue < 10.0 {
            this.needValue = 10.0;
        }
        this.lastNeedStage = 0;
        this.lastValueForCriticalNeedCheck = 100.0;

        this.ResetContextuallyDelayedNeedValueChange();
        StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetNeedStageStatusEffectTag());
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.SetupData();
        this.ResetContextuallyDelayedNeedValueChange();
        this.lastNeedStage = this.GetNeedStage();
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
        this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        this.CheckForCriticalNeed();
        this.ReevaluateSystem();
        this.ForceNeedMaxValueUpdate();
    }
    
    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance: GameInstance = GetGameInstance();
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
        this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    private func RegisterAllRequiredDelayCallbacks() -> Void {
        //DFProfile();
        this.RegisterUpdateCallback();
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.ResetContextuallyDelayedNeedValueChange();
        this.lastNeedStage = this.GetNeedStage();
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
        this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        this.CheckForCriticalNeed();
        this.ForceNeedMaxValueUpdate();
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterUpdateCallback();
        this.UnregisterAllNeedFXCallbacks();
        this.UnregisterContextuallyDelayedNeedValueChange();
        this.UnregisterSceneTierChangedCheckFXCallback();
        this.UnregisterStatusEffectRefreshDebounceCallback();
        this.UnregisterPlayerDeathCallback();
    }

    public final func OnPlayerDeath() -> Void {
        //DFProfile();
        this.SuspendFX();
        super.OnPlayerDeath();
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipStart");

        this.UnregisterUpdateCallback();
        this.UnregisterAllNeedFXCallbacks();
    }

    public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipCancelled");

        this.RegisterUpdateCallback();

        if this.GameStateService.IsValidGameState(this, true) {
            this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        }
    }

    public func OnTimeSkipBegin() -> Void {}

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipFinished");

        this.RegisterUpdateCallback();

        if this.GameStateService.IsValidGameState(this, true) {
            this.OnTimeSkipFinishedActual(data);
            this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        }
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds") || 
           ArrayContains(changedSettings, "needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds") {
            this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        }

        if ArrayContains(changedSettings, "basicNeedThresholdValue1V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue2V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue3V2") ||
           ArrayContains(changedSettings, "basicNeedThresholdValue4V2") {

            this.SetupData();
            this.ReevaluateSystem();
        }
    }

    //
    //  Required Overrides
    //
    private func OnUpdateActual() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("OnUpdateActual");
    }

    private func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("OnTimeSkipFinishedActual");
    }

    private func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("OnItemConsumedActual");
    }

    private func GetNeedHUDBarType() -> DFHUDBarType {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedHUDBarType");
        return DFHUDBarType.None;
    }

    private func GetNeedType() -> DFNeedType {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedType");
        return DFNeedType.None;
    }

    private func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("QueueNeedStageNotification");
    }

    private func GetSevereNeedMessageKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetSevereNeedMessageKey");
        return n"";
    }

    private func GetSevereNeedCombinedContextKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetSevereNeedCombinedContextKey");
        return n"";
    }

    private func GetNeedStageStatusEffectTag() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedStageStatusEffectTag");
        return n"";
    }

    private func GetTutorialTitleKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetTutorialTitleKey");
        return n"";
    }

    private func GetTutorialMessageKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetTutorialMessageKey");
        return n"";
    }

    private func GetHasShownTutorialForNeed() -> Bool {
        //DFProfile();
        this.LogMissingOverrideError("GetHasShownTutorialForNeed");
        return false;
    }

    private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("SetHasShownTutorialForNeed");
    }

    private func GetBonusEffectTDBID() -> TweakDBID {
        //DFProfile();
        this.LogMissingOverrideError("GetBonusEffectTDBID");
    }

    private func GetNeedDeathSettingValue() -> Bool {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedDeathSettingValue");
    }

    private func GetNeedSoftCapValue() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedSoftCapValue");
    }

    public func GetNeedMaxAfterItemUse(itemRecord: wref<Item_Record>) -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetNeedMaxAfterItemUse");
    }

    public func GetCalculatedNeedMax() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetCalculatedNeedMax");
    }

    private func HandleOverchargeDepleted() -> Void {}

    public func ApplyDelayedNeedLoss(data: DFBiocorruptionDelayedNeedLossDatum) -> Void {}

    //
    //  RunGuard Protected Methods
    //
    public func OnUpdate() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnUpdate");

        if this.GameStateService.IsValidGameState(this) && !this.GameStateService.IsInAnyMenu() {
            this.OnUpdateActual();
        }

        this.RegisterUpdateCallback();
    }

    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnItemConsumed");

        if this.GameStateService.IsValidGameState(this, true) {
            this.OnItemConsumedActual(itemRecord, animateUI);
        }
    }

    public func OnSceneTierChanged(value: GameplayTier) -> Void {
        //DFProfile();
        if DFRunGuard(this, true) { return; }
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
        //DFProfile();
        if DFRunGuard(this, true) { return; }
        DFLog(this, "OnFuryStateChanged value = " + ToString(value));

        this.ReevaluateSystem();

        if Equals(value, true) {
            this.SuspendFX();
        } else {
            this.ReapplyFX();
        }
    }

    public func OnCyberspaceChanged(value: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this, true) { return; }
        DFLog(this, "OnCyberspaceChanged value = " + ToString(value));

        this.ReevaluateSystem();

        if Equals(value, true) {
            this.SuspendFX();
        } else {
            this.ReapplyFX();
        }
    }

    public final func GetNeedValue() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return -1.0; }

        return this.needValue;
    }

    public final func GetOverchargeValue() -> Float {
        //DFProfile();
        // NOTE - Don't guard this with RunGuard - Biocorruption needs to query this value
        // on startup before the Nerve system is initialized.

        return this.needValueOvercharge;
    }

    public final func GetAccumulatedDelayedNeedLoss() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return 0.0; }

        return this.currentDelayedNeedLoss;
    }

    public final func GetNeedMax() -> Float {
        //DFProfile();
        if DFRunGuard(this) { return -1.0; }

        return this.needMax;
    }

    //
    //  RunGuard Protected Methods
    //
    public func ChangeNeedValue(amount: Float, opt changeValueProps: DFChangeNeedValueProps) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "ChangeNeedValue: amount = " + ToString(amount) + ", changeValueProps = " + ToString(changeValueProps));

        let needMax: Float = changeValueProps.maxOverride > 0.0 ? changeValueProps.maxOverride : this.GetCalculatedNeedMax();
        let oldValue: Float = this.needValue;
        let oldOvercharge: Float = this.needValueOvercharge;
        let softCap: Float = this.GetNeedSoftCapValue();
        let newValue: Float;

        if changeValueProps.targetValueMode {
            // In this mode, attempt to change the value to the specific value noted. Used by Time Skip.

            // Delayed Needs
            this.currentDelayedNeedLoss = changeValueProps.targetDelayedValue;

            // Overcharge
            if amount > 100.0 {
                this.needValueOvercharge = amount - 100.0;
                amount = 100.0;
            } else {
                this.needValueOvercharge = 0.0;
            }

            // Value Change
            newValue = ClampF(amount, 0.0, needMax);
            
            if IsDefined(this as DFNerveSystem) && changeValueProps.isFromTimeskip {
                this.BiocorruptionConditionSystem.UpdateBiocorruptionDataFromTimeskipSerializedWithNerveUpdate(changeValueProps.biocorruptionData);
                this.BiocorruptionConditionSystem.RefreshEuphoria();
                this.BiocorruptionConditionSystem.RefreshCrashStatusEffectAndUpdateLimit(true);
                
                if oldOvercharge > 0.0 && this.needValueOvercharge == 0.0 {
                    // If this would cause the player to experience Withdrawal symptoms, update that now.
                    this.AlcoholAddictionSystem.ReevaluateSystem();
                    this.NicotineAddictionSystem.ReevaluateSystem();
                    this.NarcoticAddictionSystem.ReevaluateSystem();
                }
            }

            // Re-check the Need Max; due to Overcharge, it could be different now.
            needMax = changeValueProps.maxOverride > 0.0 ? changeValueProps.maxOverride : this.GetCalculatedNeedMax();

        } else if amount > 0.0 && changeValueProps.isSoftCapRestrictedChange {
            if oldValue < softCap {
                // Clamp to the lowest cap. This will either increase the value (up to the soft cap), or lower it (to the max).
                let lowestCap: Float = MinF(softCap, needMax);
                newValue = ClampF(this.needValue + amount, 0.0, lowestCap);
            } else {
                // We are increasing, this is a soft cap restricted change, and we are already at or above the soft cap. Clamp to only the max while retaining the current value.
                newValue = ClampF(this.needValue, 0.0, needMax);
            }
            
        } else {
            // We are not increasing, or we are increasing, but this is not a soft cap restricted change. Change the value clamped to the max.

            if amount < 0.0 {
                // Decreasing.
                // First, handle Delayed Needs.
                if changeValueProps.delayPercent > 0.0 {
                    let delayedAmount: Float = amount * changeValueProps.delayPercent;
                    this.currentDelayedNeedLoss += delayedAmount;
                    amount -= delayedAmount;
                }
                    
                // Next, take what we can from the Overcharge amount.
                let lastOvercharge: Float = this.needValueOvercharge;
                let remainderAmount: Float = amount + this.needValueOvercharge;

                if remainderAmount < 0.0 {
                    this.needValueOvercharge = 0.0;
                    amount += lastOvercharge;
                } else {
                    this.needValueOvercharge += amount;
                    amount = 0.0;
                }

                // Finally, for what remains, change the Need Value.
                newValue = ClampF(this.needValue + amount, 0.0, needMax);

                // Trigger any handling when Overcharge reaches 0.
                if oldOvercharge > 0.0 && this.needValueOvercharge == 0.0 {
                    this.HandleOverchargeDepleted();
                }
            
            } else {
                // Increasing.
                newValue = ClampF(this.needValue + amount, 0.0, needMax);
            }
        }
            
        let change: Float = newValue - oldValue;
        this.needValue = newValue;

        this.needMax = needMax;

        if changeValueProps.doNotUpdateUIIfNoChange && oldValue == newValue && oldOvercharge == this.needValueOvercharge {
            // Skip the HUD UI update. Allows the bar to fade out.

        } else if amount > 0.0 && changeValueProps.isSoftCapRestrictedChange && newValue >= softCap {
            // We are restoring the Need from a soft cap restricted change, and are at the soft cap. Full bright the UI and display the lock (if softCap below 100) regardless of flag settings.
            this.UpdateNeedHUDUI(true, changeValueProps.uiFlags.instantUIChange, true, true, true, softCap < 100.0);

        } else {
            let uiFlags: DFNeedChangeUIFlags = changeValueProps.uiFlags;
            this.UpdateNeedHUDUI(uiFlags.forceMomentaryUIDisplay, uiFlags.instantUIChange, uiFlags.forceBright, uiFlags.momentaryDisplayIgnoresSceneTier, changeValueProps.isSoftCapRestrictedChange, false);
        }

        let stage: Int32 = this.GetNeedStage();
        if NotEquals(stage, this.lastNeedStage) {
            DFLog(this, "ChangeNeedValue: Last Need stage (" + ToString(this.lastNeedStage) + ") != current stage (" + ToString(stage) + "). Refreshing status effects and FX.");
            this.RegisterStatusEffectRefreshDebounceCallback();

            if !changeValueProps.skipFX {
                this.UpdateNeedFX(changeValueProps.suppressRecoveryNotification);
            }
        }

        if stage > this.lastNeedStage && this.lastNeedStage < 4 && stage == 4 {
            let isEnergy: Bool = IsDefined(this as DFEnergySystem);
            if isEnergy && this.needValue == 0.0 {
                // Special Case - If suddenly losing enough Energy to Blackout from a higher Need Stage, don't queue a message.
            } else if changeValueProps.skipSevereNeedMessage {
                // Special case - If crashing or waking up from blacking out, don't queue a message.
            } else {
                this.QueueSevereNeedMessage();
            }
        }

        this.CheckForCriticalNeed();
        this.TryToShowTutorial();
        
        this.lastNeedStage = stage;

        // TODOFUTURE: Removing this check crashes the game. Investigate.
        if !changeValueProps.isMaxValueUpdate {
            this.DispatchNeedValueChangedEvent(change, newValue, changeValueProps.isMaxValueUpdate, changeValueProps.fromDanger);
        }

        DFLog(this, "ChangeNeedValue: change: " + ToString(change) + ", newValue = " + ToString(newValue) + ", overcharge = " + ToString(this.needValueOvercharge));
    }

    //
    //  System-Specific Methods
    //
    public final func GetNeedStage() -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return -1; }

        return this.GetNeedStageImpl(this.needValue);
    }

    public final func GetNeedStageAtValue(needValue: Float) -> Int32 {
        //DFProfile();
        if DFRunGuard(this) { return -1; }

        return this.GetNeedStageImpl(needValue);
    }

    public final func GetClampedNeedChangeFromData(needChange: DFNeedChangeDatum) -> Float {
        //DFProfile();
        if needChange.value != 0.0 {
            let currentValue: Float = this.GetNeedValue();
            let needNewValue: Float = currentValue + needChange.value;
            let isIncreasing: Bool = needChange.value > 0.0;

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

    public final func QueueContextuallyDelayedNeedValueChange(queuedNeedValueChangeProps: DFQueuedNeedValueChange) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "QueueContextuallyDelayedNeedValueChange needValueChange: " + ToString(queuedNeedValueChangeProps));
        ArrayPush(this.queuedContextuallyDelayedNeedValueChange, queuedNeedValueChangeProps);
        this.RegisterContextuallyDelayedNeedValueChange();
    }

    public final func GetQueuedContextuallyDelayedNeedValueChanges() -> array<DFQueuedNeedValueChange> {
        //DFProfile();
        return this.queuedContextuallyDelayedNeedValueChange;
    }

    public final func TryToApplyContextuallyDelayedNeedValueChange() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "TryToApplyContextuallyDelayedNeedValueChange");
        
        let gs: GameState = this.GameStateService.GetGameState(this);

        if Equals(gs, GameState.Valid) {
            while ArraySize(this.queuedContextuallyDelayedNeedValueChange) > 0 {
                let queuedChange: DFQueuedNeedValueChange = ArrayPop(this.queuedContextuallyDelayedNeedValueChange);
                
                let changeNeedValueProps: DFChangeNeedValueProps;
                
                let uiFlags: DFNeedChangeUIFlags;
                uiFlags.forceMomentaryUIDisplay = queuedChange.forceMomentaryUIDisplay;
                uiFlags.instantUIChange = false;
                uiFlags.forceBright = true;

                changeNeedValueProps.uiFlags = uiFlags;
                changeNeedValueProps.isSoftCapRestrictedChange = queuedChange.isSoftCapRestrictedChange;
                changeNeedValueProps.finalChangeInEuphoriaDepletion = queuedChange.finalChangeInEuphoriaDepletion;
                changeNeedValueProps.isFromTimeskip = queuedChange.isFromTimeskip;
                changeNeedValueProps.isMaxValueUpdate = queuedChange.isMaxValueUpdate;
                changeNeedValueProps.skipFX = queuedChange.skipFX;
                changeNeedValueProps.targetValueMode = queuedChange.targetValueMode;
                changeNeedValueProps.skipSevereNeedMessage = queuedChange.skipSevereNeedMessage;
                changeNeedValueProps.highestCrashStackCountOnTimeskip = queuedChange.highestCrashStackCountOnTimeskip;
                changeNeedValueProps.biocorruptionData = queuedChange.biocorruptionData;
                
                this.ChangeNeedValue(queuedChange.value, changeNeedValueProps);

                // For consumable bonuses, like Well Fed and Sated
                if NotEquals(queuedChange.effectToApplyAfterValueChange, t"") && this.GetNeedStage() == 0 {
                    StatusEffectHelper.ApplyStatusEffect(this.player, queuedChange.effectToApplyAfterValueChange);
                }

                if queuedChange.isFromBlackout {
                    // Energy: Now that the Need has been changed, clearing this flag allows a Blackout to occur again.
                    this.blackoutNeedChangePending = false;
                }
            }
            this.ResetContextuallyDelayedNeedValueChange();

        // If Game State only Temporarily Invalid, try again later. Otherwise, throw away this request.
        } else if Equals(gs, GameState.TemporarilyInvalid) {
            this.RegisterContextuallyDelayedNeedValueChange();
        }
    }

    public final func OnSceneTierChangedCheckFXCallback() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        if !this.InteractionSystem.ShouldAllowFX() {
            this.SuspendFX();
        }
    }

    //
    //  Private Methods
    //

    //  Status Effects
    //
    private final func GetNeedStageImpl(needValue: Float) -> Int32 {
        //DFProfile();
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

    public func ReevaluateSystem() -> Void {
        //DFProfile();
        this.RegisterStatusEffectRefreshDebounceCallback();
        this.UpdateNeedHUDUI();
    }

    // NO LONGER CALLED DIRECTLY; use RegisterStatusEffectRefreshDebounceCallback() instead.
    public func RefreshNeedStatusEffects() -> Void {
        //DFProfile();
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

    public func GetCalculatedBasicNeedMaxInProvidedState(crashStacks: Int32, crashSuppressionStacks: Int32, hasEuphoria: Bool) -> Float {
        //DFProfile();
        let needTarget: Float = 100.0;

        if hasEuphoria {
            return needTarget;
        }

        let debuffStacks: Float = MaxF(Cast<Float>(crashStacks - crashSuppressionStacks), 0.0);

        needTarget -= 5.0 * debuffStacks;

        return needTarget;
    }

    public final func ForceNeedMaxValueUpdate(opt skipFXForThisUpdate: Bool, opt forceDisplay: Bool) -> Void {
        //DFProfile();
        let uiFlags: DFNeedChangeUIFlags;
        if forceDisplay {
            uiFlags.forceMomentaryUIDisplay = true;
            uiFlags.momentaryDisplayIgnoresSceneTier = true;
        }

        let changeNeedValueProps: DFChangeNeedValueProps;
        changeNeedValueProps.isMaxValueUpdate = true;
        changeNeedValueProps.skipFX = skipFXForThisUpdate;
        changeNeedValueProps.uiFlags = uiFlags;

        this.ChangeNeedValue(0.0, changeNeedValueProps);

        
    }

    public final func ForceNeedMaxValueUpdateDelayed(opt skipFXForThisUpdate: Bool, opt forceDisplay: Bool) -> Void {
        //DFProfile();
        let props: DFQueuedNeedValueChange;
        props.value = 0.0;
        props.isMaxValueUpdate = true;
        props.skipFX = skipFXForThisUpdate;

        this.QueueContextuallyDelayedNeedValueChange(props);
    }

    //  UI
    //
    public final func UpdateNeedHUDUI(opt forceMomentaryDisplay: Bool, opt instantUIChange: Bool, opt forceBright: Bool, opt momentaryDisplayIgnoresSceneTier: Bool, opt isSoftCapRestrictedChange: Bool, opt showLock: Bool) -> Void {
        //DFProfile();
        let update: DFNeedHUDUIUpdate;
        update.bar = this.GetNeedHUDBarType();
        update.newValue = this.needValue;
        update.newLimitValue = this.GetNeedMax();
        update.newOverchargeValue = this.needValueOvercharge;
        update.forceMomentaryDisplay = forceMomentaryDisplay;
        update.instant = instantUIChange;
        update.forceBright = forceBright;
        update.momentaryDisplayIgnoresSceneTier = momentaryDisplayIgnoresSceneTier;
        update.isSoftCapRestrictedChange = isSoftCapRestrictedChange;
        update.showLock = showLock;

        DFLog(this, "UpdateNeedHUDUI newValue: " + ToString(update.newValue) + ", forceMomentaryDisplay: " + ToString(update.forceMomentaryDisplay) + ", instant: " + ToString(update.instant) + ", forceBright: " + ToString(update.forceBright));

        GameInstance.GetCallbackSystem().DispatchEvent(UpdateNeedsHUDUIEvent.Create(update));
    }

    public final func TryToShowTutorial() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

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
    public func SuspendFX() -> Void {
        //DFProfile();
        this.UnregisterAllNeedFXCallbacks();
        this.PlayerStateService.UpdateCriticalNeedEffects();
    }

    public func ReapplyFX() -> Void {
        //DFProfile();
        if this.InteractionSystem.ShouldAllowFX() {
            this.UpdateNeedFX();
            this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
        }

        this.PlayerStateService.UpdateCriticalNeedEffects();
    }

    public func UpdateNeedFX(opt suppressRecoveryNotification: Bool) -> Void {
        //DFProfile();
        DFLog(this, "UpdateNeedFX");

        let currentStage: Int32 = this.GetNeedStage();
        
        if NotEquals(currentStage, this.lastNeedStage) && (currentStage > this.lastNeedStage || currentStage == 0) {
            this.RegisterNeedStageChangeFXStartCallback(currentStage, suppressRecoveryNotification);
        }

        this.UpdateInsufficientNeedRepeatFXCallback(currentStage);
    }

    public final func UpdateInsufficientNeedRepeatFXCallback(stageToCheck: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        
        DFLog(this, "UpdateInsufficientNeedRepeatFXCallback stageToCheck = " + ToString(stageToCheck));

        this.UnregisterInsufficientNeedRepeatFXCallback();

        if stageToCheck == 3 {
            this.RegisterInsufficientNeedFXRepeatStage3Callback();
        } else if stageToCheck == 4 {
            this.RegisterInsufficientNeedFXRepeatStage4Callback();
        }
    }

    private final func ResetContextuallyDelayedNeedValueChange() -> Void {
        //DFProfile();
        DFLog(this, "ResetContextuallyDelayedNeedValueChange");

        ArrayClear(this.queuedContextuallyDelayedNeedValueChange);
    }

    public final func QueueSevereNeedMessage(opt allowInCombat: Bool) -> Void {
        //DFProfile();
        DFLog(this, "QueueSevereNeedMessage");
        if !this.Settings.needMessagesEnabled { return; }

        let message: DFMessage;
        message.key = this.GetSevereNeedMessageKey();
        message.type = SimpleMessageType.Negative;
        message.context = DFMessageContext.Need;
        message.combinedContextKey = this.GetSevereNeedCombinedContextKey();

        let notification: DFNotification;
        notification.message = message;
        notification.allowPlaybackInCombat = allowInCombat;

        this.NotificationService.QueueNotification(notification);
    }

    private final func GetRandomRepeatCallbackOffsetTime() -> Float {
        //DFProfile();
        return RandRangeF(-20.0, 20.0);
    }

    //
    //  Basic Need Death
    //
    public func CheckForCriticalNeed() -> Void {
        //DFProfile();
        if this.inDeathState { return; }
        if !this.GetNeedDeathSettingValue() { return; }

        if this.GameStateService.IsValidGameState(this) {
            if this.GetNeedValue() <= 0.0 && this.GetNeedDeathSettingValue() {
                // Kill the player.
                this.QueuePlayerDeath();
            }
        }
        
        this.PlayerStateService.UpdateCriticalNeedEffects();

        if this.GameStateService.IsValidGameState(this, true) {
            // TODOFUTURE - Blink the bar, make more visually apparent
            let currentValue: Float = this.GetNeedValue();

            if currentValue <= this.extremelyCriticalNeedThreshold && this.lastValueForCriticalNeedCheck > this.extremelyCriticalNeedThreshold {
                this.QueueExtremelyCriticalNeedSFX();
                this.QueueExtremelyCriticalNeedWarningNotification();
            } else if currentValue <= this.criticalNeedThreshold && this.lastValueForCriticalNeedCheck > this.criticalNeedThreshold {
                this.QueueCriticalNeedSFX();
                this.QueueCriticalNeedWarningNotification();
            }
            
            this.lastValueForCriticalNeedCheck = currentValue;
        }
    }

    public final func QueueCriticalNeedWarningNotification() -> Void {
        //DFProfile();
        if this.GameStateService.IsValidGameState(this, true) {
            let message: DFMessage;
            message.key = n"DarkFutureCriticalNeedHighNotification";
            message.type = SimpleMessageType.Negative;
            message.context = DFMessageContext.CriticalNeed;

            let notification: DFNotification;
            notification.message = message;
            notification.allowPlaybackInCombat = true;

            this.NotificationService.QueueNotification(notification);
        }
    }

    public final func QueueExtremelyCriticalNeedWarningNotification() -> Void {
        //DFProfile();
        if this.GameStateService.IsValidGameState(this, true) {
            let message: DFMessage;
            message.key = n"DarkFutureCriticalNeedLowNotification";
            message.type = SimpleMessageType.Negative;
            message.context = DFMessageContext.CriticalNeed;

            let notification: DFNotification;
            notification.message = message;
            notification.allowPlaybackInCombat = true;

            this.NotificationService.QueueNotification(notification);
        }
    }

    public final func QueueCriticalNeedSFX() -> Void {
        //DFProfile();
        if this.Settings.needNegativeSFXEnabled && !this.PlayerStateService.GetInOverdose() {
            let notification: DFNotification;
            notification.sfx = DFAudioCue(n"ono_v_knock_down", 0);
            this.NotificationService.QueueNotification(notification);
        }
    }

    public final func QueueExtremelyCriticalNeedSFX() -> Void {
        //DFProfile();
        if this.Settings.needNegativeSFXEnabled && !this.PlayerStateService.GetInOverdose() {
            let notification: DFNotification;
            notification.sfx = DFAudioCue(n"ono_v_death_short", 0);
            this.NotificationService.QueueNotification(notification);
        }
    }

    public func QueuePlayerDeath() -> Void {
        //DFProfile();
        // :(
        
        this.inDeathState = true;
        this.PlayerStateService.PlayCriticalNeedEffects();
        this.PlayerStateService.StopOutOfBreathSFX();

        this.QueueCriticalNeedSFXDeath();
        this.RegisterPlayerDeathCallback();
    }

    public final func QueueCriticalNeedSFXDeath() -> Void {
        //DFProfile();
        let notification: DFNotification;
        notification.sfx = DFAudioCue(n"ono_v_death_long", -10);
        this.NotificationService.QueueNotification(notification);
    }

    public final func OnPlayerDeathCallback() -> Void {
        //DFProfile();
        // This kills the player.
        StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.HeartAttack");

        // Register for post-death recovery. (Santa Muerte Compatibility)
        this.RegisterPostPlayerDeathCallback();
    }

    public func OnPostPlayerDeathCallback() -> Void {
        //DFProfile();
        StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.HeartAttack");
        this.inDeathState = false;
        
        // Restore a modest amount of the Basic Need.
        let changeNeedValueProps: DFChangeNeedValueProps;
        let uiFlags: DFNeedChangeUIFlags;
        uiFlags.forceMomentaryUIDisplay = true;
        changeNeedValueProps.uiFlags = uiFlags;

        if this.GetNeedValue() < this.basicNeedPostDeathRestoreAmount {
            this.ChangeNeedValue(this.basicNeedPostDeathRestoreAmount - this.GetNeedValue(), changeNeedValueProps);
        }
    }

    public final func DisplayItemBenefitRestrictedNotification(type: DFItemBenefitRestrictedNotificationType) -> Void {
        //DFProfile();
        let notificationTitle: String;

        if Equals(type, DFItemBenefitRestrictedNotificationType.MaxStacks) {
            notificationTitle = GetLocalizedTextByKey(n"DarkFutureMaxStacksNotification");
        }

        let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
        notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        notificationEvent.m_title = notificationTitle;
        notificationEvent.m_overrideCurrentNotification = true;
        
        GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
    }

    //  Registration
    //
    public final func RegisterUpdateCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, NeedUpdateDelayCallback.Create(this), this.updateDelayID, this.updateIntervalInGameTimeSeconds / this.Settings.timescale);
    }

    private final func RegisterNeedStageChangeFXStartCallback(needStage: Int32, suppressRecoveryNotification: Bool) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, NeedStageChangeFXStartDelayCallback.Create(this, needStage, suppressRecoveryNotification), this.needStageChangeFXStartDelayID, this.needStageChangeFXStartDelayInterval);
    }

    private final func RegisterInsufficientNeedFXRepeatStage3Callback() -> Void {
        //DFProfile();
        // Don't play this repeated FX if the value is capped and the player is idling at the current maximum.
        if this.GetNeedValue() < this.GetNeedMax() {
            RegisterDFDelayCallback(this.DelaySystem, InsufficientNeedRepeatFXDelayCallback.Create(this), this.insufficientNeedRepeatFXDelayID, this.Settings.needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds + this.GetRandomRepeatCallbackOffsetTime());
        }
    }

    private final func RegisterInsufficientNeedFXRepeatStage4Callback() -> Void {
        //DFProfile();
        // Don't play this repeated FX if the value is capped and the player is idling at the current maximum.
        if this.GetNeedValue() < this.GetNeedMax() {
            RegisterDFDelayCallback(this.DelaySystem, InsufficientNeedRepeatFXDelayCallback.Create(this), this.insufficientNeedRepeatFXDelayID, this.Settings.needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds + this.GetRandomRepeatCallbackOffsetTime());
        }
    }

    private final func RegisterContextuallyDelayedNeedValueChange() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedNeedValueChangeDelayCallback.Create(this), this.contextuallyDelayedNeedValueChangeDelayID, this.contextuallyDelayedNeedValueChangeDelayInterval);
    }

    private final func RegisterSceneTierChangedCheckFXCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, SceneTierChangedCheckFXCallback.Create(this), this.sceneTierChangedCheckFXDelayID, this.sceneTierChangedCheckFXDelayInterval);
    }

    public final func RegisterStatusEffectRefreshDebounceCallback() -> Void {
        //DFProfile();
        // Allow restart to cancel previous requests. Applying Status Effects is async to the rest of the system, this helps prevent these requests
        // from stacking up and resulting in multiple effects when only one should apply.
        RegisterDFDelayCallback(this.DelaySystem, StatusEffectRefreshDebounceCallback.Create(this), this.statusEffectRefreshDebounceDelayID, this.statusEffectRefreshDebounceDelayInterval, true);
    }

    public final func RegisterPlayerDeathCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, PlayerDeathCallback.Create(this), this.playerDeathDelayID, this.playerDeathDelayInterval);
    }

    public final func RegisterPostPlayerDeathCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, PostPlayerDeathCallback.Create(this), this.postPlayerDeathDelayID, this.postPlayerDeathDelayInterval);
    }

    //  Unregistration
    //
    public final func UnregisterUpdateCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.updateDelayID);
    }

    public final func UnregisterAllNeedFXCallbacks() -> Void {
        //DFProfile();
        DFLog(this, "UnregisterAllNeedFXCallbacks");

        this.UnregisterNeedStageChangeFXStartCallback();
        this.UnregisterInsufficientNeedRepeatFXCallback();
    }

    private final func UnregisterNeedStageChangeFXStartCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.needStageChangeFXStartDelayID);
    }

    private final func UnregisterInsufficientNeedRepeatFXCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.insufficientNeedRepeatFXDelayID);
    }

    private final func UnregisterContextuallyDelayedNeedValueChange() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedNeedValueChangeDelayID);
    }

    private final func UnregisterSceneTierChangedCheckFXCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.sceneTierChangedCheckFXDelayID);
    }

    public final func UnregisterStatusEffectRefreshDebounceCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.statusEffectRefreshDebounceDelayID);
    }

    private final func UnregisterPlayerDeathCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.playerDeathDelayID);
    }

    //  Callback Handlers
    //
    public final func OnNeedStageChangeFXStart(needStage: Int32, suppressRecoveryNotification: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnNeedStageChangeFXStart");

        this.QueueNeedStageNotification(needStage, suppressRecoveryNotification);
        this.UpdateInsufficientNeedRepeatFXCallback(needStage);
    }

    public func OnInsufficientNeedFXStop() {
        //DFProfile();
        // Override
    }

    public final func OnInsufficientNeedRepeatFX() -> Void {
        //DFProfile();
        DFLog(this, "OnInsufficientNeedRepeatFX");
        let needStage: Int32 = this.GetNeedStage();

        if this.Settings.needNegativeEffectsRepeatEnabled {
            this.QueueNeedStageNotification(needStage);
        }

        this.UpdateInsufficientNeedRepeatFXCallback(needStage);
    }

    //
    //  Events for Dark Future Add-Ons and Mods
    //
    public final func DispatchNeedValueChangedEvent(change: Float, newValue: Float, isMaxValueUpdate: Bool, opt fromDanger: Bool) -> Void {
        //DFProfile();
        let data: DFNeedValueChangedEventDatum = DFNeedValueChangedEventDatum(this.GetNeedType(), change, newValue, isMaxValueUpdate, fromDanger);
        GameInstance.GetCallbackSystem().DispatchEvent(DFNeedValueChangedEvent.Create(data));
    }
}
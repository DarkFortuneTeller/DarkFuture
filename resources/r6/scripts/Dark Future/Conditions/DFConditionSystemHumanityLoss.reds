// -----------------------------------------------------------------------------
// DFHumanityLossConditionSystem
// -----------------------------------------------------------------------------
//
// - Humanity Loss Condition system.
// - Humanity Loss occurs after losing enough cumulative Nerve.
// - May cause Cyberpsychosis.
// - Cured through activities in the world and Endotrisine.
//

module DarkFuture.Conditions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Main.{
    DFMainSystem,
    DFHumanityLossDatum,
    DFTimeSkipData,
    MainSystemItemConsumedEvent
}
import DarkFuture.Utils.{
    HoursToGameTimeSeconds,
    DFRunGuard,
    IsCoinFlipSuccessful,
    DFFactListener,
    CreateDFFactListener,
    CreateDFActionFactListener,
    UnregisterAllDFFactListeners,
    DFFactListenerCanRun,
    IsPlayerInBadlands,
    DFGeneralVoiceLine
}
import DarkFuture.Needs.{
    DFNeedType,
    DFNeedValueChangedEvent,
    DFNeedValueChangedEventDatum,
    DFNerveSystem
}
import DarkFuture.Services.{
    DFCyberwareService,
    DFGameStateService,
    DFNotificationService,
    DFPlayerStateService,
    DFTutorial,
    DFNotification,
    DFMessage,
    DFMessageContext,
    DFPlayerDangerState,
    DFVisualEffect,
    DFNotificationCallback,
    DFAudioCue,
    DFFactNameValue
}
import DarkFuture.Settings.DFSettings
import DarkFuture.UI.{
    DFConditionDisplayData,
    DFConditionType,
    DFConditionArea,
    DFAreaDisplayData,
    DFConditionEffectDisplayData
}

public struct DFCyberpsychosisChanceData {
    public let chance: Float;
    public let reason: String;
}

public enum DFHumanityLossRestorationActivityType {
    LifePathCorpoFreshStart = 0,
    LifePathNomad = 1,
    LifePathStreetKid = 2,
    Charity = 3,
    Dance = 4,
    Intimacy = 5,
    ConfessionBooth = 6,
    Rollercoaster = 7,
    Meditation = 8,
    Speed = 9
}

public enum DFHumanityLossRestoreChoiceType {
    StreetKid = 1,
    Nomad = 2,
    CorpoFreshStart = 3,
    Speed = 4,
    ConfessionBooth = 5
}

public enum DFHumanityLossRestorationType {
    RepeatableMinor = 0,
    RepeatableMajor = 1,
    RepeatablePivotal = 2,
    OneTimeEventMinor = 3,
    OneTimeEventMajor = 4,
    OneTimeEventPivotal = 5
}

public enum DFHumanityLossCostType {
    RepeatableRelicMalfunction = 0,
    OneTimeEventMinor = 1,
    OneTimeEventMajor = 2,
    OneTimeEventPivotal = 3
}

@wrapMethod(ScriptedPuppet)
protected func RewardKiller(killer: wref<GameObject>, killType: gameKillType, isAnyDamageNonlethal: Bool) -> Void {
    //DFProfile();
    wrappedMethod(killer, killType, isAnyDamageNonlethal);

    if IsDefined(killer as PlayerPuppet) {
        let charRecord: wref<Character_Record> = this.GetRecord();
        let faction: gamedataAffiliation = charRecord.Affiliation().Type();
        let isMaxTac: Bool = charRecord.TagsContains(n"MaxTac_Prevention") || charRecord.TagsContains(n"q305_maxtac");
        let isPreventionOrCrowd: Bool = this.IsPrevention() || this.IsCharacterCivilian() || this.IsCrowd();
        DFHumanityLossConditionSystem.Get().OnNeutralization(faction, isPreventionOrCrowd, isMaxTac);
    };
}

@addField(PlayerPuppet)
private let DarkFutureSetLastKnownCyberpsychosisStackCountLock: RWLock;

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    //DFProfile();
    let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();
    let humanityLossSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();

    if IsSystemEnabledAndRunning(nerveSystem) && IsSystemEnabledAndRunning(humanityLossSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();
        if Equals(effectID, t"DarkFutureStatusEffect.CyberpsychosisApplicationDone") {
            
            let cyberpsychosisStackCountApplied: Uint32 = StatusEffectHelper.GetStatusEffectByID(this, t"DarkFutureStatusEffect.Cyberpsychosis").GetStackCount();

            RWLock.Acquire(this.DarkFutureSetLastKnownCyberpsychosisStackCountLock);
            humanityLossSystem.SetLastKnownCyberpsychosisStackCount(cyberpsychosisStackCountApplied);
            RWLock.Release(this.DarkFutureSetLastKnownCyberpsychosisStackCountLock);

            humanityLossSystem.RegisterConditionFXRepeatCallback();
            humanityLossSystem.CheckCyberpsychosisTutorial();

            DFLogNoSystem(true, this, "PlayerPuppet: OnStatusEffectApplied: Received CyberpsychosisApplicationDone, updating Nerve limit.");
            nerveSystem.OnCyberpsychosisUpdated(true);
        }
    }

    return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    //DFProfile();
    let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();
    let humanityLossSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();

    if IsSystemEnabledAndRunning(nerveSystem) && IsSystemEnabledAndRunning(humanityLossSystem) {
        let effectID: TweakDBID = evt.staticData.GetID();
        if Equals(effectID, t"DarkFutureStatusEffect.Cyberpsychosis") {
            let humanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();

            RWLock.Acquire(this.DarkFutureSetLastKnownCyberpsychosisStackCountLock);

            let cyberpsychosisStackCountApplied: Uint32 = StatusEffectHelper.GetStatusEffectByID(this, t"DarkFutureStatusEffect.Cyberpsychosis").GetStackCount();
            let lastKnownCyberpsychosisStackCount: Uint32 = humanityLossConditionSystem.GetLastKnownCyberpsychosisStackCount();
            DFLogNoSystem(true, this, "PlayerPuppet: OnStatusEffectRemoved: One or more stacks of Cyberpsychosis removed, updating Nerve limit. Event stackCount = " + ToString(evt.stackCount) + ", cyberpsychosisStackCountApplied: " + ToString(cyberpsychosisStackCountApplied) + ", isFinalRemoval: " + ToString(evt.isFinalRemoval) + ", lastKnownCyberpsychosisStackCount: " + ToString(lastKnownCyberpsychosisStackCount));

            if humanityLossConditionSystem.ignoreFirstNeutralizationForCyberpsychosisEffectPlayback {
                humanityLossConditionSystem.ignoreFirstNeutralizationForCyberpsychosisEffectPlayback = false;

            } else if cyberpsychosisStackCountApplied > 0u &&
                    FloorF(Cast<Float>(cyberpsychosisStackCountApplied) / 5.0) < FloorF(Cast<Float>(lastKnownCyberpsychosisStackCount) / 5.0) {
                humanityLossConditionSystem.TryToPlayCyberpsychosisEffectsPeriodicKill();
            
            } else if cyberpsychosisStackCountApplied == 0u && evt.isFinalRemoval {
                if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"DarkFutureImmunosuppressant") {
                    humanityLossConditionSystem.TryToPlayCyberpsychosisEffectsExitFromKill();
                }
            }

            if cyberpsychosisStackCountApplied != lastKnownCyberpsychosisStackCount {
                nerveSystem.OnCyberpsychosisUpdated(false);
            }
            humanityLossConditionSystem.SetLastKnownCyberpsychosisStackCount(cyberpsychosisStackCountApplied);

            RWLock.Release(this.DarkFutureSetLastKnownCyberpsychosisStackCountLock);
        }
    }

    return wrappedMethod(evt);
}

public class HumanityLossDurationUpdateDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new HumanityLossDurationUpdateDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFHumanityLossConditionSystem.Get().humanityLossDurationUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFHumanityLossConditionSystem.Get().OnHumanityLossDurationUpdate(DFHumanityLossConditionSystem.Get().GetHumanityLossDurationUpdateIntervalInGameTimeSeconds());
	}
}

public class RelicMalfunctionHumanityLossDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
		return new RelicMalfunctionHumanityLossDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFHumanityLossConditionSystem.Get().relicMalfunctionHumanityLossDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFHumanityLossConditionSystem.Get().OnRelicMalfunction();
	}
}

public class CyberpsychosisFXStopDelayCallback extends DFDelayCallback {
	public let HumanityLossSystem: ref<DFHumanityLossConditionSystem>;

	public static func Create(humanityLossSystem: ref<DFHumanityLossConditionSystem>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self = new CyberpsychosisFXStopDelayCallback();
		self.HumanityLossSystem = humanityLossSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.HumanityLossSystem.cyberpsychosisFXStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.HumanityLossSystem.OnCyberpsychosisFXStop();
	}
}

public final class DFCyberpsychosisVFXStopCallback extends DFNotificationCallback {
    let delay: Float;

	public static func Create(delay: Float) -> ref<DFCyberpsychosisVFXStopCallback> {
        //DFProfile();
        let self = new DFCyberpsychosisVFXStopCallback();
        self.delay = delay;
        return self;
	}

	public final func Callback() -> Void {
        //DFProfile();
		let HumanityLossSystem: wref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();
		RegisterDFDelayCallback(HumanityLossSystem.DelaySystem, CyberpsychosisFXStopDelayCallback.Create(HumanityLossSystem), HumanityLossSystem.cyberpsychosisFXStopDelayID, this.delay);
	}
}

class DFHumanityLossConditionSystemEventListener extends DFConditionSystemEventListener {
	private func GetSystemInstance() -> wref<DFHumanityLossConditionSystem> {
        //DFProfile();
		return DFHumanityLossConditionSystem.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Needs.DFNeedValueChangedEvent", this, n"OnNeedValueChangedEvent", true);
    }

	private cb func OnNeedValueChangedEvent(event: ref<DFNeedValueChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnNeedValueChanged(event.GetData());
	}
}

public class DFHumanityLossConditionSystem extends DFConditionSystemBase {
    private let QuestsSystem: ref<QuestsSystem>;
    private let AutoDriveSystem: ref<AutoDriveSystem>;
    private let StatusEffectSystem: ref<StatusEffectSystem>;
    private let CyberwareService: ref<DFCyberwareService>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let PlayerStateService: ref<DFPlayerStateService>;

    private let UINotificationsBlackboardDef: ref<UI_NotificationsDef>;
    private let UINotificationsBlackboard: ref<IBlackboard>;

    public let humanityLossDurationUpdateDelayID: DelayID;
    public let relicMalfunctionHumanityLossDelayID: DelayID;
    private let humanityLossDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;
    private let relicMalfunctionHumanityLossInterval: Float = 4.0;

    private persistent let oneTimeSetupDone: Bool = false;
    private persistent let remainingEndotrisineEffectDurationInGameTimeSeconds: Float = 0.0;

    private persistent let timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds: Float = 0.0;
    private persistent let lastKnownCyberpsychosisStackCount: Uint32 = 0u;
    private persistent let hasShownCyberpsychosisTutorial: Bool = false;

    public persistent let lastDayRestored_LifePath: Int32;
    public persistent let lastDayRestored_Dance: Int32;
    public persistent let lastDayRestored_Intimacy: Int32;
    public persistent let lastDayRestored_Charity: Int32;
    public persistent let lastDayRestored_ConfessionBooth: Int32;
    public persistent let lastDayRestored_Rollercoaster: Int32;
    public persistent let lastDayRestored_Meditation: Int32;
    public persistent let lastDayRestored_Speed: Int32;

    private persistent let onceOnlyDFFactListenersFired: array<CName>;

    private const let endotrisineEffectDurationInGameHours: Int32 = 24;

    public const let humanityLossRestoration_EndotrisineAdditiveMultiplier: Float = 1.0;

    public const let cyberpsychosisChancePerCyberwareCapacityPointExceeded: Float = 0.5;
    public const let cyberwareCapacityHumanityLossMult: Float = 0.3;
    private const let cyberpsychosisWantedLevelBonusThreshold: Int32 = 5;
    private const let cyberpsychosisMinConditionLevel: Int32 = 2;

    private let conditionNerveSoftCaps: array<Float>;
    private let conditionCyberpsychosisStacksPerLevel: array<Uint32>;

    public let ignoreFirstNeutralizationForCyberpsychosisEffectPlayback: Bool = false;
    public let cyberpsychosisFXStopDelayID: DelayID;
    public let cyberpsychosisFXStopDelayInterval: Float = 2.0;

    // ==== Quest Fact Listeners
    //
    private let factListenerRegistry: array<DFFactListener>;
    private let setTherapyCyberpsychosisEnabledActionFactListener: DFFactListener;
    private let showHumanityLossTutorialActionFactListener: DFFactListener;
    private let humanityLossRestoreChoiceActivatedActionFactListener: DFFactListener;
    private let speedVoicelineGetInBadlandsActionFactListener: DFFactListener;

    private let warningMessageListener: ref<CallbackHandle>;
    private let activePlayerVehicleSpeedListener: ref<CallbackHandle>;
    private let lastHumanityLossRestorationChoiceType: Int32 = 0;
    private let lastAutoDriveDistrictEnumName: String = "";
    private let lastActivePlayerVehicleSpeed: Int32 = 0;
    private let lastActivePlayerVehicle: ref<VehicleObject>;
    private const let playerVehicleSpeedHumanityLossRestoreThreshold: Int32 = 140; // MPH

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHumanityLossConditionSystem> {
        //DFProfile();
		let instance: ref<DFHumanityLossConditionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFHumanityLossConditionSystem>()) as DFHumanityLossConditionSystem;
		return instance;
	}

    public final static func Get() -> ref<DFHumanityLossConditionSystem> {
        //DFProfile();
        return DFHumanityLossConditionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "humanityLossCyberpsychosisEnabled") {
            if !this.Settings.humanityLossConditionEnabled {
                this.ClearCyberpsychosisAndReturnIfStacksRemoved();
                this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = 0.0;
            }

            this.UpdateEdgerunnerPerkDescription();
            this.UpdateHumanityLossStatusDescriptions();
            DFMainSystem.Get().UpdateCodexEntries();
        }

        if ArrayContains(changedSettings, "humanityLossFuryAcceleratedPrevention") {
            this.UpdateEdgerunnerPerkDescription();
        }

        if ArrayContains(changedSettings, "cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds") {
			this.UpdateConditionRepeatFXCallback(this.ShouldRepeatFX());
		}

        if ArrayContains(changedSettings, "cyberpsychosisSFXEnabled") {
            this.UpdateSettingsFacts();
        }
    }

    public final func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        return this.Settings.humanityLossConditionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "humanityLossConditionEnabled";
    }

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        super.DoPostResumeActions();
        this.RegisterHumanityLossDurationUpdateCallback();
        this.UpdateConditionRepeatFXCallback(this.ShouldRepeatFX());
        this.UpdateEdgerunnerPerkDescription();
        this.UpdateSettingsFacts();
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        super.DoPostSuspendActions();
        
        this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = 0.0;
        this.remainingEndotrisineEffectDurationInGameTimeSeconds = 0.0;
        
        this.RefreshEndotrisineStatusEffect();
        this.ClearCyberpsychosisAndReturnIfStacksRemoved();
        this.UpdateEdgerunnerPerkDescription();
    }

    public func GetSystems() -> Void {
        //DFProfile();
        super.GetSystems();
        let gameInstance = GetGameInstance();
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.AutoDriveSystem = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<AutoDriveSystem>()) as AutoDriveSystem;
        this.StatusEffectSystem = GameInstance.GetStatusEffectSystem(gameInstance);
        this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
    }

	public func SetupData() -> Void {
        //DFProfile();
        this.conditionNerveSoftCaps = [100.0, 80.0, 60.0, 40.0, 20.0];
		this.conditionStatusEffects = [
			t"DarkFutureStatusEffect.HumanityLoss01",
			t"DarkFutureStatusEffect.HumanityLoss02",
			t"DarkFutureStatusEffect.HumanityLoss03",
			t"DarkFutureStatusEffect.HumanityLoss04"
		];
        this.conditionCyberpsychosisStacksPerLevel = [0u, 25u, 50u, 75u];
        this.UpdateEdgerunnerPerkDescription();
        this.UpdateHumanityLossStatusDescriptions();
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.UnregisterHumanityLossDurationUpdateCallback();
    }

    public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.RegisterHumanityLossDurationUpdateCallback();
        this.UpdateConditionRepeatFXCallback(this.ShouldRepeatFX());
    }

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

		this.RegisterHumanityLossDurationUpdateCallback();
        this.UpdateConditionRepeatFXCallback(this.ShouldRepeatFX());

        if this.GameStateService.IsValidGameState(this, true) {
            this.OnHumanityLossDurationUpdateFromTimeSkip(data.targetHumanityLossValues);
        }
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        super.InitSpecific(attachedPlayer);

        this.RegisterHumanityLossDurationUpdateCallback();
        this.UpdateConditionRepeatFXCallback(this.ShouldRepeatFX());
        this.UpdateSettingsFacts();
        this.RegisterForVehicleSpeedChange();

        if !this.oneTimeSetupDone {
            this.lastDayRestored_LifePath = -9999;
            this.lastDayRestored_Dance = -9999;
            this.lastDayRestored_Intimacy = -9999;
            this.lastDayRestored_Charity = -9999;
            this.lastDayRestored_ConfessionBooth = -9999;
            this.lastDayRestored_Rollercoaster = -9999;
            this.oneTimeSetupDone = true;
        }
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterHumanityLossDurationUpdateCallback();
        this.UnregisterForRelicMalfunctionHumanityLoss();
    }

    private func RegisterListeners() -> Void {
        this.setTherapyCyberpsychosisEnabledActionFactListener = CreateDFActionFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"df_fact_action_set_therapy_cyberpsychosis_enabled", n"OnSetTherapyCyberpsychosisEnabledActionFactChanged");
        this.showHumanityLossTutorialActionFactListener = CreateDFActionFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"df_fact_action_show_humanity_loss_tutorial", n"OnTherapyShowHumanityLossTutorialActionFactChanged");
        this.humanityLossRestoreChoiceActivatedActionFactListener = CreateDFActionFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"df_fact_humanityloss_restore_choice_activated", n"OnHumanityLossRestoreChoiceActivatedFactChanged");
        this.speedVoicelineGetInBadlandsActionFactListener = CreateDFActionFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"df_fact_action_speed_voiceline_get_in_badlands", n"OnSpeedVoicelineGetInBadlandsFactChanged");

        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"ue_metro_player_stand_door", n"OnMetroPlayerStandDoorFactChanged");
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"ue_metro_player_window_left", n"OnMetroPlayerWindowLeftFactChanged");
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"ue_metro_player_window_right", n"OnMetroPlayerWindowRightFactChanged");
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"homeless_paid", n"OnHomelessPaidFactChanged");

        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"q101_enable_activities_flat", n"OnAct2StartFactChanged", true);              // Start of Act 2
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq021_randy_saved", n"OnSQ021RandySavedFactChanged", true);                  // The Hunt (Randy Saved)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq021_randy_kaputt", n"OnSQ021RandyKaputtFactChanged", true);                // The Hunt (Randy Dead)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq027_done", n"OnSQ027DoneFactChanged", true);                               // Queen of the Highway Complete
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq028_kerry_relationship", n"OnSQ028KerryRelationshipFactChanged", true);    // Boat Drinks (Started Relationship)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq028_kerry_friend", n"OnSQ028KerryFriendFactChanged", true);                // Boat Drinks (Started Friendship)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq030_romance", n"OnSQ030RomanceFactChanged", true);                         // Pyramid Song (Started Relationship)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"sq030_friendship", n"OnSQ030FriendshipFactChanged", true);                   // Pyramid Song (Started Relationship)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"default_jackie_phone_dead", n"OnQ005VCallsJackieDeadFactChanged", true);     // V calls Jackie after his death
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"q105_03a_lie_down", n"OnQ105DollLieDownFactChanged", true);                  // Automatic Love (Lied Down With Doll)
        CreateDFFactListener(this.QuestsSystem, this, this.factListenerRegistry, n"q305_medal_given_away", n"OnQ305MedalGivenAwayFactChanged", true);           // Gave away NUSA Medal to homeless person

        this.UINotificationsBlackboardDef = GetAllBlackboardDefs().UI_Notifications;
        this.UINotificationsBlackboard = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(this.UINotificationsBlackboardDef);
        this.warningMessageListener = this.UINotificationsBlackboard.RegisterListenerVariant(this.UINotificationsBlackboardDef.WarningMessage, this, n"OnWarningMessage");
    }

	private func UnregisterListeners() -> Void {
        UnregisterAllDFFactListeners(this.QuestsSystem, this.factListenerRegistry);

        if IsDefined(this.UINotificationsBlackboard) {
            this.UINotificationsBlackboard.UnregisterDelayedListener(this.UINotificationsBlackboardDef.WarningMessage, this.warningMessageListener);
        }

        if IsDefined(this.lastActivePlayerVehicle) {
            this.UnregisterForVehicleSpeedChange(this.lastActivePlayerVehicle);
        }
    }

    //
    //  Required Overrides
    //

    // Nerve Loss Accumulator Event
    //
	public final func OnNeedValueChanged(evt: DFNeedValueChangedEventDatum) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnNeedValueChanged: evt: " + ToString(evt));
        if this.GameStateService.IsValidGameState(this) && 
          Equals(evt.needType, DFNeedType.Nerve) && 
          !evt.isMaxValueUpdate &&
          evt.change < 0.0 &&
          evt.fromDanger {
            this.AccumulateNerveLoss(evt.change);
        }
	}

    public final func GetMaxConditionLevel() -> Uint32 {
        //DFProfile();
        return 4u;
    }

    public func GetConditionCureItemTag() -> CName {
        //DFProfile();
        return n"";
    }

    public func GetConditionSecondaryCureItemTag() -> CName {
        //DFProfile();
        return n"DarkFutureConsumableImmunosuppressantDrug";
    }

    private final func DoSecondaryConditionCure() -> Void {
        //DFProfile();
        // Remove all stacks of Cyberpsychosis.
        let cyberpsychosisRemoved: Bool = this.ClearCyberpsychosisAndReturnIfStacksRemoved();

        if cyberpsychosisRemoved {
            // Wrap-up effects.
            this.TryToPlayCyberpsychosisEffectsExitFromImmunosuppressant();
        }
	}

    private final func GetTutorialTitleKey() -> CName {
        //DFProfile();
		return n"DarkFutureTutorialHumanityLossTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
        //DFProfile();
		return n"DarkFutureTutorialHumanityLoss";
	}

    private final func GetConditionCureItemAmountRestored() -> Float {
        //DFProfile();
        // Not used.
        return 0.0;
    }

    private final func GetCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureHumanityLossCuredNotification";
    }

    private final func GetAllCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureHumanityLossAllCuredNotification";
    }

    public final func GetConditionDisplayData(index: Int32) -> ref<DFConditionDisplayData> {
        //DFProfile();
        let data: ref<DFConditionDisplayData> = new DFConditionDisplayData();
        data.condition = DFConditionType.HumanityLoss;
        data.index = index;

        data.localizedName = GetLocalizedTextByKey(n"DarkFutureConditionHumanityLoss");
        data.level = Cast<Int32>(this.GetConditionLevel());
        data.unlockedLevel = Cast<Int32>(this.GetConditionLevel());
        data.maxLevel = Cast<Int32>(this.GetMaxConditionLevel());
        data.expPoints = Cast<Int32>(this.accumulatedPercentTowardNextLevel);
        // Condition Progress ranges from 0 to 100. -1 indicates to StatsProgressController that the Max Level has been reached.
        data.maxExpPoints = (this.GetConditionLevel() == this.GetMaxConditionLevel() && data.expPoints == 100) ? -1 : 100;

        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.HumanityLoss, DFConditionArea.HumanityLoss_Area_01));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.HumanityLoss, DFConditionArea.HumanityLoss_Area_02));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.HumanityLoss, DFConditionArea.HumanityLoss_Area_03));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.HumanityLoss, DFConditionArea.HumanityLoss_Area_04));

        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(1, n"DarkFutureHumanityLoss01Name", n"DarkFutureConditionHumanityLoss01Desc"));

        if this.Settings.humanityLossCyberpsychosisEnabled {
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(2, n"DarkFutureHumanityLoss02Name", n"DarkFutureConditionHumanityLoss02Desc"));
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(3, n"DarkFutureHumanityLoss03Name", n"DarkFutureConditionHumanityLoss03Desc"));
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureHumanityLoss04Name", n"DarkFutureConditionHumanityLoss04Desc"));
        } else {
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(2, n"DarkFutureHumanityLoss02Name", n"DarkFutureConditionHumanityLoss02NoCyberpsychosisDesc"));
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(3, n"DarkFutureHumanityLoss03Name", n"DarkFutureConditionHumanityLoss03NoCyberpsychosisDesc"));
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureHumanityLoss04Name", n"DarkFutureConditionHumanityLoss04NoCyberpsychosisDesc"));
        }
        

        return data;
    }

    private final func QueueConditionMessage(level: Uint32) -> Void {
        //DFProfile();
        let conditionLevelUpMessage: DFMessage;
        conditionLevelUpMessage.type = SimpleMessageType.Negative;
        conditionLevelUpMessage.key = StringToName("DarkFutureMagicMessageStringConditionHumanityLoss" + IntToString(Cast<Int32>(level)));
        conditionLevelUpMessage.context = DFMessageContext.HumanityLossCondition;
        conditionLevelUpMessage.passKeyAsString = true;

        let notification: DFNotification;
        notification.message = conditionLevelUpMessage;
        notification.allowPlaybackInCombat = false;

        this.NotificationService.QueueNotification(notification);
    }

    private final func GetConditionStatusEffectTag() -> CName {
        //DFProfile();
		return n"DarkFutureConditionHumanityLoss";
	}

    private final func ShouldRepeatFX() -> Bool {
        //DFProfile();
		return this.GetCyberpsychosisStacksApplied() > 0u;
	}

    public final func OnConditionRepeatFX() -> Void {
        //DFProfile();
		// Used for Cyberpsychosis.
        let shouldPlay: Bool = this.ShouldRepeatFX();

        if shouldPlay && !this.player.IsInCombat() {
            this.TryToPlayCyberpsychosisEffectsRepeatFX();
        }

		this.UpdateConditionRepeatFXCallback(shouldPlay);
	}

    public final func GetConditionProgressionNotificationType() -> CName {
        //DFProfile();
		return n"DarkFutureHumanityLoss";
	}

    public final func GetConditionProgressionNotificationTitleKey() -> CName {
        //DFProfile();
		return n"DarkFutureConditionHumanityLoss";
	}

    //
    //  System-Specific Functions
    //

    // Overrides base implementation
    public final func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        super.OnItemConsumed(itemRecord, animateUI);

        let itemTags: array<CName> = itemRecord.Tags();
		if ArrayContains(itemTags, n"DarkFutureConsumableEndotrisineDrug") {
            this.OnEndotrisineDrugConsumed();
        }
	}

    public final func OnEndotrisineDrugConsumed() -> Void {
        //DFProfile();
		// Set the duration.
		this.remainingEndotrisineEffectDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.endotrisineEffectDurationInGameHours);

		// Refresh player-facing status effects.
		this.RefreshEndotrisineStatusEffect();
	}

    // Overrides base implementation
    public final func CheckTutorial() -> Void {
        // Start the therapy text questphase instead of displaying a tutorial immediately.
        if this.QuestsSystem.GetFact(n"df_fact_start_therapy_text") == 0 {
            this.QuestsSystem.SetFact(n"df_fact_start_therapy_text", 1);
        }
    }

    private func RefreshEndotrisineStatusEffect() -> Void {
        //DFProfile();
		DFLog(this, "RefreshEndotrisineStatusEffect");
        let shouldApply: Bool = false;

        if this.GameStateService.IsValidGameState(this, true) {
            if this.remainingEndotrisineEffectDurationInGameTimeSeconds > 0.0 {
                shouldApply = true;
            }
        }

        if shouldApply {
            if !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.Endotrisine") {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Endotrisine");       
            }
        } else {
            if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.Endotrisine") {
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Endotrisine");
            }
        }
    }

    private final func CheckHumanityLossTutorial() -> Void {
        super.CheckTutorial();
    }

    private final func UpdateSettingsFacts() -> Void {
        //DFProfile();
		let factValue: Int32 = this.Settings.cyberpsychosisSFXEnabled ? 1 : 0;
		this.QuestsSystem.SetFact(n"df_fact_setting_cyberpsychosis_sfx_enabled", factValue);
	}

    private final func UpdateEdgerunnerPerkDescription() -> Void {
        //DFProfile();
        if this.Settings.humanityLossConditionEnabled && this.Settings.humanityLossCyberpsychosisEnabled {
            TweakDBManager.SetFlat(t"NewPerks.Tech_Master_Perk_3.loc_desc_key", GetLocalizedTextByKey(n"DarkFutureTechMasterPerk3UpdatedCyberpsychosisDesc"));
        
        } else {
            TweakDBManager.SetFlat(t"NewPerks.Tech_Master_Perk_3.loc_desc_key", GetLocalizedTextByKey(n"DarkFutureTechMasterPerk3UpdatedDesc"));
        }
        
        TweakDBManager.UpdateRecord(t"NewPerks.Tech_Master_Perk_3");
    }

    private final func UpdateHumanityLossStatusDescriptions() -> Void {
        //DFProfile();
        if this.Settings.humanityLossCyberpsychosisEnabled {
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss02_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss02Desc"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss03_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss03Desc"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss04_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss04Desc"));
        } else {
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss02_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss02NoCyberpsychosisDesc"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss03_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss03NoCyberpsychosisDesc"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HumanityLoss04_UIData.description", GetLocalizedTextByKey(n"DarkFutureHumanityLoss04NoCyberpsychosisDesc"));
        }
        
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.HumanityLoss02_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.HumanityLoss03_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.HumanityLoss04_UIData");
    }

    private final func GetCyberpsychosisMinConditionLevel() -> Int32 {
        //DFProfile();
        return this.cyberpsychosisMinConditionLevel;
    }

    public final func GetCyberpsychosisChance(opt menuPointsExceeded: Int32) -> DFCyberpsychosisChanceData {
        //DFProfile();
        let pointsExceeded: Float;
        if menuPointsExceeded > 0 {
            pointsExceeded = Cast<Float>(menuPointsExceeded);
        } else {
            pointsExceeded = this.CyberwareService.GetPointsOfCyberwareCapacityExceeded();
        }
        
        let chanceData: DFCyberpsychosisChanceData;

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureImmunosuppressant") {
            chanceData.chance = 0.0;
            chanceData.reason = GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonImmunosuppressant");
        } else if this.GetTimeUntilNextCyberpsychosisAllowed() > 0.0 {
            chanceData.chance = 0.0;
            chanceData.reason = GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonCooldown");
        } else if Cast<Int32>(this.GetConditionLevel()) < this.GetCyberpsychosisMinConditionLevel() {
            chanceData.chance = 0.0;
            chanceData.reason = GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonHumanityLoss");
        } else {
            chanceData.chance = pointsExceeded * this.cyberpsychosisChancePerCyberwareCapacityPointExceeded;
            // TEST chanceData.chance = 100.0;
        }

        return chanceData;
    }

    private final func RollForCyberpsychosisSuccessful() -> Bool {
        //DFProfile();
        let chanceToGoCyberpsychoData: DFCyberpsychosisChanceData = this.GetCyberpsychosisChance();
        let chanceToGoCyberpsycho: Float = chanceToGoCyberpsychoData.chance;

        let randomRoll: Float = RandRangeF(0.0, 100.0);
        if chanceToGoCyberpsycho > 0.0 && randomRoll <= chanceToGoCyberpsycho {
            DFLog(this, "=========== CYBERPSYCHOSIS ROLL: SUCCESS");
            DFLog(this, "    Cyberpsychosis Chance: " + ToString(chanceToGoCyberpsycho) + ", Roll: " + ToString(randomRoll));
            return true;
        } else {
            DFLog(this, "=========== CYBERPSYCHOSIS ROLL: FAIL");
            DFLog(this, "    Cyberpsychosis Chance: " + ToString(chanceToGoCyberpsycho) + ", Roll: " + ToString(randomRoll));
            return false;
        }
    }

    public final func OnDangerStateChanged(dangerState: DFPlayerDangerState) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
        if !this.GameStateService.IsValidGameState(this) { return; }

        if this.Settings.humanityLossCyberpsychosisEnabled {
            // If we've entered combat...
            if dangerState.InCombat {
                let conditionLevel: Int32 = Cast<Int32>(this.GetConditionLevel());
                // Roll to see if this event will result in Cyberpsychosis application.
                if this.RollForCyberpsychosisSuccessful() {
                    let conditionLevelIndex: Int32 = Max(conditionLevel - 1, 0);
                    let cyberpsychosisMaxStacksToApply: Uint32 = this.conditionCyberpsychosisStacksPerLevel[conditionLevelIndex];

                    if cyberpsychosisMaxStacksToApply > 0u {
                        let cyberpsychosisStackCountApplied: Uint32 = this.GetCyberpsychosisStacksApplied();
                        if cyberpsychosisStackCountApplied < cyberpsychosisMaxStacksToApply {
                            this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = HoursToGameTimeSeconds(24);
                            this.ignoreFirstNeutralizationForCyberpsychosisEffectPlayback = true;
                            let cyberpsychosisStacksToApply: Uint32 = cyberpsychosisMaxStacksToApply - cyberpsychosisStackCountApplied;
                            DFLog(this, "Applying " + ToString(cyberpsychosisStacksToApply) + " stacks of Cyberpsychosis!");

                            this.TryToPlayCyberpsychosisEffectsEnter();
                            
                            // Unfortunately, it appears that we can't apply multiple stacks of a status effect at once.
                            // Apply them one at a time.
                            while cyberpsychosisStacksToApply > 0u {
                                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Cyberpsychosis");
                                cyberpsychosisStacksToApply -= 1u;
                            }

                            // As a workaround optimization, signal that we have completed adding Cyberpsychosis effects.
                            StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.CyberpsychosisApplicationDone");
                        }
                    }                        
                }
            }
        }
    }

    public final func TryToPlayCyberpsychosisEffectsEnter() -> Void {
        //DFProfile();
        DFLog(this, "!!!!!! Playing Cyberpsychosis Enter FX");

        let cyberpsychosisEffect: DFNotification;
        cyberpsychosisEffect.allowPlaybackInCombat = true;

        let cyberpsychosisMessage: DFMessage;
        cyberpsychosisMessage.key = n"DarkFutureCyberpsychosisNotification0";
        cyberpsychosisMessage.type = SimpleMessageType.Negative;
        cyberpsychosisMessage.context = DFMessageContext.Cyberpsychosis;
        cyberpsychosisMessage.allowPlaybackInCombat = true;
        cyberpsychosisMessage.duration = 1.25;
        cyberpsychosisEffect.message = cyberpsychosisMessage;

        if this.Settings.cyberpsychosisVFXEnabled {
            let vfx: DFVisualEffect;
            let vfxStopCallback: ref<DFCyberpsychosisVFXStopCallback> = DFCyberpsychosisVFXStopCallback.Create(1.125);
            vfx.visualEffect = n"hacking_glitch_heavy";
            vfx.stopCallback = vfxStopCallback;
            cyberpsychosisEffect.vfx = vfx;

            // Auxiliary Effects - Red Screen
            let cyberpsychosisStartEffectRedScreen: DFNotification;
            let cyberpsychosisStartEffectVfxRedScreen: DFVisualEffect;
            cyberpsychosisStartEffectVfxRedScreen.visualEffect = n"perk_edgerunner";
            cyberpsychosisStartEffectRedScreen.vfx = cyberpsychosisStartEffectVfxRedScreen;
            cyberpsychosisStartEffectRedScreen.allowPlaybackInCombat = true;
            cyberpsychosisStartEffectRedScreen.preventVFXIfIncompatibleVFXApplied = true;
            this.NotificationService.QueueNotification(cyberpsychosisStartEffectRedScreen, true);
            
            // Auxiliary Effects - Slow Time
            StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.CyberpsychosisSlowTime");
        }

        if this.Settings.cyberpsychosisSFXEnabled {
            if !this.HasBaseGameFuryModeActive() {
                cyberpsychosisEffect.sfx = DFAudioCue(n"ono_v_laughs_hard", -5);
            }
        }
        
        // Play immediately.
        this.NotificationService.QueueNotification(cyberpsychosisEffect, true);
    }

    public final func TryToPlayCyberpsychosisEffectsPeriodicKill() -> Void {
        //DFProfile();
        DFLog(this, "!!!!!! Playing Cyberpsychosis Periodic Kill FX");
        let shouldPlay: Bool = false;

        let cyberpsychosisEffect: DFNotification;
        cyberpsychosisEffect.allowPlaybackInCombat = true;

        if this.Settings.cyberpsychosisVFXEnabled {
            let vfx: DFVisualEffect;
            let vfxStopCallback: ref<DFCyberpsychosisVFXStopCallback> = DFCyberpsychosisVFXStopCallback.Create(2.0);
            vfx.visualEffect = n"hacking_glitch_low";
            vfx.stopCallback = vfxStopCallback;
            cyberpsychosisEffect.vfx = vfx;
            shouldPlay = true;
        }

        if this.Settings.cyberpsychosisSFXEnabled {
            if !this.HasBaseGameFuryModeActive() {
                cyberpsychosisEffect.sfx = DFAudioCue(n"ono_v_laughs_hard", -5);
                shouldPlay = true;
            }
        }

        if shouldPlay {
            this.NotificationService.QueueNotification(cyberpsychosisEffect);
        }
    }

    public final func TryToPlayCyberpsychosisEffectsRepeatFX() -> Void {
        //DFProfile();
        DFLog(this, "!!!!!! Playing Cyberpsychosis Non-Combat FX");
        if this.Settings.cyberpsychosisEffectsRepeatEnabled {
            let shouldPlay: Bool = false;

            let cyberpsychosisEffect: DFNotification;
            cyberpsychosisEffect.allowPlaybackInCombat = false;
            cyberpsychosisEffect.preventVFXIfIncompatibleVFXApplied = true;

            if this.Settings.cyberpsychosisVFXEnabled {
                let vfx: DFVisualEffect;
                let vfxStopCallback: ref<DFCyberpsychosisVFXStopCallback> = DFCyberpsychosisVFXStopCallback.Create(2.0);
                vfx.visualEffect = n"hacking_glitch_low";
                vfx.stopCallback = vfxStopCallback;
                cyberpsychosisEffect.vfx = vfx;
                shouldPlay = true;
            }

            if this.Settings.cyberpsychosisSFXEnabled {
                if IsCoinFlipSuccessful() {
                    let sfx: DFAudioCue = DFAudioCue(n"ono_v_laughs_soft", -4);
                    cyberpsychosisEffect.sfx = sfx;
                    shouldPlay = true;
                }
            }
            
            if shouldPlay {
                this.NotificationService.QueueNotification(cyberpsychosisEffect);
            }
        }
    }

    public final func TryToPlayCyberpsychosisEffectsExitFromKill() -> Void {
        //DFProfile();
        DFLog(this, "!!!!!! Playing Cyberpsychosis Exit from Kill FX");

        let cyberpsychosisEffect: DFNotification;
        cyberpsychosisEffect.allowPlaybackInCombat = false;

        if this.Settings.cyberpsychosisVFXEnabled {
            // Player "blacks out" after combat ends.
            let vfx: DFVisualEffect;
            let vfxStopCallback: ref<DFCyberpsychosisVFXStopCallback> = DFCyberpsychosisVFXStopCallback.Create(1.5);
            vfx.visualEffect = n"blackout_organic";
            vfx.stopCallback = vfxStopCallback;
            cyberpsychosisEffect.vfx = vfx;
            cyberpsychosisEffect.preventVFXIfIncompatibleVFXApplied = true;
        }

        // "Confused" voice lines, completion message
        cyberpsychosisEffect.audioSceneFact = DFFactNameValue(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.CyberpsychosisExitFromKill));

        // Play immediately.
        this.NotificationService.QueueNotification(cyberpsychosisEffect, true);
    }

    public final func TryToPlayCyberpsychosisEffectsExitFromImmunosuppressant() -> Void {
        //DFProfile();
        DFLog(this, "!!!!!! Playing Cyberpsychosis Exit from Immunosuppressant FX");

        let cyberpsychosisEffect: DFNotification;
        cyberpsychosisEffect.allowPlaybackInCombat = false;

        if this.Settings.cyberpsychosisVFXEnabled {
            // Player "blacks out" after combat ends.
            let vfx: DFVisualEffect;
            let vfxStopCallback: ref<DFCyberpsychosisVFXStopCallback> = DFCyberpsychosisVFXStopCallback.Create(1.5);
            vfx.visualEffect = n"blackout_organic";
            vfx.stopCallback = vfxStopCallback;
            cyberpsychosisEffect.vfx = vfx;
            cyberpsychosisEffect.preventVFXIfIncompatibleVFXApplied = true;
        }

        // "Groggy" voice lines, completion message
        cyberpsychosisEffect.audioSceneFact = DFFactNameValue(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.CyberpsychosisExitFromImmunosuppressant));

        // Give the Immunosuppressant consumable animation an opportunity to play; don't play immediately.
        this.NotificationService.QueueNotification(cyberpsychosisEffect);
    }

    public final func GetCyberpsychosisStacksApplied() -> Uint32 {
        //DFProfile();
        return StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.Cyberpsychosis").GetStackCount();
    }

    public final func OnNeutralization(faction: gamedataAffiliation, isPreventionOrCrowd: Bool, isMaxTac: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this, true) { return; }
        if !this.GameStateService.IsValidGameState(this, true) { return; }

        if this.Settings.humanityLossCyberpsychosisEnabled {
            // See also: DFNeedSystemNerve::OnStatusEffectRemoved()
            let cyberpsychosisStackCountApplied: Uint32 = this.GetCyberpsychosisStacksApplied();
            if cyberpsychosisStackCountApplied > 0u {
                let neutralizedNPCStackValue: Uint32;

                if isMaxTac {
                    neutralizedNPCStackValue = 20u;
                } else if isPreventionOrCrowd {
                    neutralizedNPCStackValue = 1u;
                } else {
                    neutralizedNPCStackValue = 2u;
                }

                let stacksToRemove: Uint32 = cyberpsychosisStackCountApplied > neutralizedNPCStackValue ? neutralizedNPCStackValue : cyberpsychosisStackCountApplied;
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Cyberpsychosis", stacksToRemove);
            }
        }
    }

    private final func GetCyberpsychosisNCPDBonusStackValue() -> Uint32 {
        //DFProfile();
        let bonusStacks: Uint32 = 0u;
        let wantedLevel: Int32 = this.QuestsSystem.GetFact(n"wanted_level");
        if wantedLevel >= this.cyberpsychosisWantedLevelBonusThreshold {
            bonusStacks += 1u;
        }

        return bonusStacks;
    }

    public final func SetLastKnownCyberpsychosisStackCount(count: Uint32) -> Void {
        //DFProfile();
        this.lastKnownCyberpsychosisStackCount = count;
    }

    public final func GetLastKnownCyberpsychosisStackCount() -> Uint32 {
        //DFProfile();
        return this.lastKnownCyberpsychosisStackCount;
    }

    public final func GetConditionNerveSoftCaps() -> array<Float> {
        //DFProfile();
        return this.conditionNerveSoftCaps;
    }

    public final func GetCurrentNerveSoftCapFromHumanityLoss() -> Float {
        //DFProfile();
        return this.conditionNerveSoftCaps[Cast<Int32>(this.currentConditionLevel)];
    }

    public final func GetNerveSoftCapFromHumanityLossAtLevel(level: Uint32) -> Float {
        //DFProfile();
        return this.conditionNerveSoftCaps[Cast<Int32>(level)];
    }

    private final func HandleIncreaseHumanityLossDirect(amount: Float) -> Void {
        if this.GetConditionLevel() <= this.GetMaxConditionLevel() {
            DFLog(this, "&&&&&&&&&& HandleIncreaseHumanityLossDirect: amount: " + ToString(amount));
            this.accumulatedPercentTowardNextLevel += amount;
            DFLog(this, "&&&&&&&&&& HandleIncreaseHumanityLossDirect: accumulatedPercentTowardNextLevel: " + ToString(this.accumulatedPercentTowardNextLevel));

            if this.accumulatedPercentTowardNextLevel >= 100.0 {
                if this.GetConditionLevel() < this.GetMaxConditionLevel() {
                    this.accumulatedPercentTowardNextLevel -= 100.0;
                    this.lastDisplayedProgressionNotificationValue = 0;
                    this.queueAllFutureProgressionNotifications = false;
                    this.ApplyConditionLevel();
                } else {
                    this.accumulatedPercentTowardNextLevel = 100.0;
                }
            }

            this.queueAllFutureProgressionNotifications = true;
            this.QueueConditionProgressionNotification(this.lastDisplayedProgressionNotificationValue, true);
        }
    }

    public final func AccumulateNerveLoss(change: Float) -> Void {
        //DFProfile();
        if this.GetConditionLevel() <= this.GetMaxConditionLevel() {
            let percent: Float = (change * -1.0);
            let lossPct: Float = this.Settings.humanityLossNerveLossAccumulationRate / 100.0;
            if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureImmunosuppressant") {
                lossPct += lossPct * (this.GetTotalCyberwareCapacityHumanityLossMult() / 100.0);
            }
            DFLog(this, "&&&&&&&&&& AccumulateNerveLoss: lossPct: " + ToString(lossPct));
            let previousPct: Float = this.accumulatedPercentTowardNextLevel;
            this.accumulatedPercentTowardNextLevel += (percent * lossPct);
            DFLog(this, "&&&&&&&&&& AccumulateNerveLoss: accumulatedPercentTowardNextLevel: " + ToString(this.accumulatedPercentTowardNextLevel));

            if this.accumulatedPercentTowardNextLevel >= 100.0 {
                if this.GetConditionLevel() < this.GetMaxConditionLevel() {
                    this.accumulatedPercentTowardNextLevel -= 100.0;
                    this.lastDisplayedProgressionNotificationValue = 0;
                    this.queueAllFutureProgressionNotifications = false;
                    this.ApplyConditionLevel();
                } else {
                    this.accumulatedPercentTowardNextLevel = 100.0;
                }
            }

            // Only send the notification at 20% increments.
            let shouldQueue: Bool = false;
            if this.accumulatedPercentTowardNextLevel % 20.0 < previousPct % 20.0 && (this.accumulatedPercentTowardNextLevel > previousPct) {
                shouldQueue = true;
                this.queueAllFutureProgressionNotifications = true;
            } else if this.queueAllFutureProgressionNotifications {
                shouldQueue = true;
            }
            
            if shouldQueue {
                this.QueueConditionProgressionNotification(this.lastDisplayedProgressionNotificationValue, true);
            }
        }
    }

    public final func GetTotalCyberwareCapacityHumanityLossMult() -> Float {
        return this.CyberwareService.GetPointsOfCyberwareCapacityAllocated() * this.cyberwareCapacityHumanityLossMult;
    }

    private final func HasBaseGameFuryModeActive() -> Bool {
        //DFProfile();
        return StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury");
    }

    public final func ShouldRapidlyEscalateWantedLevel() -> Bool {
        //DFProfile();
        if DFRunGuard(this, true) { return false; }
        if !this.GameStateService.IsValidGameState(this, true) { return false; }

        if this.Settings.humanityLossFuryAcceleratedPrevention {
            return this.HasBaseGameFuryModeActive();
        } else {
            return false;
        }
    }

    private final func ClearCyberpsychosisAndReturnIfStacksRemoved() -> Bool {
        //DFProfile();
        let cyberpsychosisStackCountApplied: Uint32 = this.GetCyberpsychosisStacksApplied();
        if cyberpsychosisStackCountApplied > 0u {
            StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Cyberpsychosis", cyberpsychosisStackCountApplied);
            return true;
        } else {
            return false;
        }
    }

    //
    //  Callback Handlers
    //
	public final func OnCyberpsychosisFXStop() {
        //DFProfile();
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"blackout_organic");
        GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"perk_edgerunner");
        GameObjectEffectHelper.StopEffectEvent(this.player, n"hacking_glitch_low");
        GameObjectEffectHelper.StopEffectEvent(this.player, n"hacking_glitch_heavy");
    }

    //
    //  Updates
    //
    private final func RegisterHumanityLossDurationUpdateCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, HumanityLossDurationUpdateDelayCallback.Create(), this.humanityLossDurationUpdateDelayID, this.humanityLossDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
	}

	private final func UnregisterHumanityLossDurationUpdateCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.humanityLossDurationUpdateDelayID);
	}

    // See: DFBaseGameUIOverrides
    public final func RegisterForRelicMalfunctionHumanityLoss() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, RelicMalfunctionHumanityLossDelayCallback.Create(), this.relicMalfunctionHumanityLossDelayID, this.relicMalfunctionHumanityLossInterval);
    }

    public final func TryToRegisterForVehicleSpeedChange(veh: ref<VehicleObject>) -> Void {
        this.lastActivePlayerVehicle = veh;

        if IsSystemEnabledAndRunning(this) {
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

    private final func UnregisterForRelicMalfunctionHumanityLoss() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.relicMalfunctionHumanityLossDelayID);
	}

    public final func GetTimeUntilNextCyberpsychosisAllowed() -> Float {
        //DFProfile();
        return this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds;
    }

    public final func GetRemainingEndotrisineDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.remainingEndotrisineEffectDurationInGameTimeSeconds;
    }

    public final func IsEndotrisineActive() -> Bool {
        return this.remainingEndotrisineEffectDurationInGameTimeSeconds > 0.0;
    }

    public final func OnHumanityLossDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
        if !this.GameStateService.IsInAnyMenu() {
            if this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds > 0.0 {
                this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

                if this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds <= 0.0 {
                    this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = 0.0;
                }
                DFLog(this, "timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = " + ToString(this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds));
            }

            if this.remainingEndotrisineEffectDurationInGameTimeSeconds > 0.0 {
                this.remainingEndotrisineEffectDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

                if this.remainingEndotrisineEffectDurationInGameTimeSeconds <= 0.0 {
                    this.remainingEndotrisineEffectDurationInGameTimeSeconds = 0.0;
                    this.RefreshEndotrisineStatusEffect();
                }
                DFLog(this, "remainingEndotrisineEffectDurationInGameTimeSeconds = " + ToString(this.remainingEndotrisineEffectDurationInGameTimeSeconds));
            }
        }
        
        this.RegisterHumanityLossDurationUpdateCallback();
    }

    public final func OnHumanityLossDurationUpdateFromTimeSkip(humanityLossDatum: DFHumanityLossDatum) -> Void {
        //DFProfile();
        this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = humanityLossDatum.newTimeUntilNextCyberpsychosisAllowed;
        DFLog(this, "timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds = " + ToString(this.timeUntilNextCyberpsychosisAllowedDurationInGameTimeSeconds));

        let lastEndotrisineDurationValue: Float = this.remainingEndotrisineEffectDurationInGameTimeSeconds;
        this.remainingEndotrisineEffectDurationInGameTimeSeconds = humanityLossDatum.newEndotrisineDuration;
        if this.remainingEndotrisineEffectDurationInGameTimeSeconds <= 0.0 {
            this.remainingEndotrisineEffectDurationInGameTimeSeconds = 0.0;
        }
        if lastEndotrisineDurationValue > 0.0 && this.remainingEndotrisineEffectDurationInGameTimeSeconds <= 0.0 {
            this.RefreshEndotrisineStatusEffect();
        }
        DFLog(this, "remainingEndotrisineEffectDurationInGameTimeSeconds = " + ToString(this.remainingEndotrisineEffectDurationInGameTimeSeconds));
        
        this.RegisterHumanityLossDurationUpdateCallback();
    }

    public final func GetHumanityLossDurationUpdateIntervalInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.humanityLossDurationUpdateIntervalInGameTimeSeconds;
    }

    public final func CheckCyberpsychosisTutorial() -> Void {
        //DFProfile();
        if this.Settings.tutorialsEnabled && !this.hasShownCyberpsychosisTutorial {
            this.hasShownCyberpsychosisTutorial = true;

            let tutorial: DFTutorial;
            tutorial.title = GetLocalizedTextByKey(n"DarkFutureTutorialCyberpsychosisTitle");
            tutorial.message = GetLocalizedTextByKey(n"DarkFutureTutorialCyberpsychosis");
            tutorial.iconID = t"";
            this.NotificationService.QueueTutorial(tutorial);
        }
    }

    //
    //  Humanity Loss Cost and Restoration
    //
    private final func GetShowTimedHumanityLossRestoreChoiceFactAction() -> CName {
        return n"df_fact_action_show_timed_humanityloss_restore_choice";
    }

    public final func IncreaseHumanityLoss(costType: DFHumanityLossCostType) -> Void {
        if DFRunGuard(this) { return; }

        if Equals(costType, DFHumanityLossCostType.RepeatableRelicMalfunction) {
            this.HandleIncreaseHumanityLossDirect(this.Settings.humanityLossCostAmountRelicMalfunction);

        } else if Equals(costType, DFHumanityLossCostType.OneTimeEventMinor) {
            this.HandleIncreaseHumanityLossDirect(this.Settings.humanityLossCostAmountOneTimeMinor);

        } else if Equals(costType, DFHumanityLossCostType.OneTimeEventMajor) {
            this.HandleIncreaseHumanityLossDirect(this.Settings.humanityLossCostAmountOneTimeMajor);

        } else if Equals(costType, DFHumanityLossCostType.OneTimeEventPivotal) {
            this.HandleIncreaseHumanityLossDirect(this.Settings.humanityLossCostAmountOneTimePivotal);
        }
    }

    public final func RestoreHumanityLoss(restoreType: DFHumanityLossRestorationType) -> Void {
        if DFRunGuard(this) { return; }

        let bonusMult: Float = this.IsEndotrisineActive() ? this.humanityLossRestoration_EndotrisineAdditiveMultiplier : 1.0;
        if Equals(restoreType, DFHumanityLossRestorationType.RepeatableMinor) {
            if this.IsEndotrisineActive() {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatableMinor + (this.Settings.humanityLossRegenerationAmountRepeatableMinor * bonusMult));
            } else {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatableMinor);
            }
        } else if Equals(restoreType, DFHumanityLossRestorationType.RepeatableMajor) {
            if this.IsEndotrisineActive() {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatableMajor + (this.Settings.humanityLossRegenerationAmountRepeatableMajor * bonusMult));
            } else {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatableMajor);
            }
        
        } else if Equals(restoreType, DFHumanityLossRestorationType.RepeatablePivotal) {
            if this.IsEndotrisineActive() {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatablePivotal + (this.Settings.humanityLossRegenerationAmountRepeatablePivotal * bonusMult));
            } else {
                this.RestoreCondition(this.Settings.humanityLossRegenerationAmountRepeatablePivotal);
            }

        } else if Equals(restoreType, DFHumanityLossRestorationType.OneTimeEventMinor) {
            this.RestoreCondition(this.Settings.humanityLossRegenerationAmountOneTimeMinor);

        } else if Equals(restoreType, DFHumanityLossRestorationType.OneTimeEventMajor) {
            this.RestoreCondition(this.Settings.humanityLossRegenerationAmountOneTimeMajor);

        } else if Equals(restoreType, DFHumanityLossRestorationType.OneTimeEventPivotal) {
            this.RestoreCondition(this.Settings.humanityLossRegenerationAmountOneTimePivotal);
        }
    }

    public final func CanRestoreHumanityLossFromActivity(activity: DFHumanityLossRestorationActivityType) -> Bool {
        let today: Int32 = GetGameInstance().GetGameTime().Days();
        if Equals(activity, DFHumanityLossRestorationActivityType.LifePathCorpoFreshStart) || Equals(activity, DFHumanityLossRestorationActivityType.LifePathNomad) || Equals(activity, DFHumanityLossRestorationActivityType.LifePathStreetKid) {
            return today > this.lastDayRestored_LifePath;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Charity) {
            return today > this.lastDayRestored_Charity;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Dance) {
            return today > this.lastDayRestored_Dance;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Intimacy) {
            return today > this.lastDayRestored_Intimacy;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Meditation) {
            return today > this.lastDayRestored_Meditation;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.ConfessionBooth) {
            return today > this.lastDayRestored_ConfessionBooth;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Rollercoaster) {
            return today > this.lastDayRestored_Rollercoaster;
        } else if Equals(activity, DFHumanityLossRestorationActivityType.Speed) {
            return today > this.lastDayRestored_Speed;
        }
    }

    public final func TryToDisplayHumanityLossRestorationChoice(type: DFHumanityLossRestorationActivityType) -> Void {
        if Equals(type, DFHumanityLossRestorationActivityType.LifePathStreetKid) && this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.LifePathStreetKid) {
            this.lastHumanityLossRestorationChoiceType = EnumInt(DFHumanityLossRestoreChoiceType.StreetKid);
            this.QuestsSystem.SetFact(this.GetShowTimedHumanityLossRestoreChoiceFactAction(), EnumInt(DFHumanityLossRestoreChoiceType.StreetKid));

        } else if Equals(type, DFHumanityLossRestorationActivityType.LifePathNomad) && this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.LifePathNomad) {
            this.lastHumanityLossRestorationChoiceType = EnumInt(DFHumanityLossRestoreChoiceType.Nomad);
            this.QuestsSystem.SetFact(this.GetShowTimedHumanityLossRestoreChoiceFactAction(), EnumInt(DFHumanityLossRestoreChoiceType.Nomad));

        } else if Equals(type, DFHumanityLossRestorationActivityType.LifePathCorpoFreshStart) && this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.LifePathCorpoFreshStart) {
            this.lastHumanityLossRestorationChoiceType = EnumInt(DFHumanityLossRestoreChoiceType.CorpoFreshStart);
            this.QuestsSystem.SetFact(this.GetShowTimedHumanityLossRestoreChoiceFactAction(), EnumInt(DFHumanityLossRestoreChoiceType.CorpoFreshStart));

        } else if Equals(type, DFHumanityLossRestorationActivityType.Speed) && this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Speed) {
            this.lastHumanityLossRestorationChoiceType = EnumInt(DFHumanityLossRestoreChoiceType.Speed);
            this.QuestsSystem.SetFact(this.GetShowTimedHumanityLossRestoreChoiceFactAction(), EnumInt(DFHumanityLossRestoreChoiceType.Speed));
        
        } else if Equals(type, DFHumanityLossRestorationActivityType.ConfessionBooth) && this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.ConfessionBooth) {
            this.lastHumanityLossRestorationChoiceType = EnumInt(DFHumanityLossRestoreChoiceType.ConfessionBooth);
            this.QuestsSystem.SetFact(this.GetShowTimedHumanityLossRestoreChoiceFactAction(), EnumInt(DFHumanityLossRestoreChoiceType.ConfessionBooth));
        }
    }

    private final func CheckShouldShowStreetKidLifePathHumanityLossRestoreChoice() -> Void {
        let playerControlledObject: ref<GameObject> = GameInstance.GetPlayerSystem(GetGameInstance()).GetLocalPlayerControlledGameObject();
		let lifePath: gamedataLifePath = PlayerDevelopmentSystem.GetInstance(playerControlledObject).GetLifePath(playerControlledObject);

		// Street Kid
		if Equals(lifePath, gamedataLifePath.StreetKid) {
            this.TryToDisplayHumanityLossRestorationChoice(DFHumanityLossRestorationActivityType.LifePathStreetKid);
		}
    }

	public final func CheckShouldShowNomadLifePathHumanityLossRestoreChoice() -> Void {
		let playerControlledObject: ref<GameObject> = GameInstance.GetPlayerSystem(GetGameInstance()).GetLocalPlayerControlledGameObject();
		let lifePath: gamedataLifePath = PlayerDevelopmentSystem.GetInstance(playerControlledObject).GetLifePath(playerControlledObject);

		// Nomad
		if Equals(lifePath, gamedataLifePath.Nomad) {
			// Badlands
			let thisDistrict: String = this.player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord().ParentDistrict().EnumName();
			if Equals(thisDistrict, "Badlands") || Equals(thisDistrict, "NorthBadlands") || Equals(thisDistrict, "SouthBadlands") {
				this.TryToDisplayHumanityLossRestorationChoice(DFHumanityLossRestorationActivityType.LifePathNomad);
			}
		}
	}

    public final func CheckShouldShowCorpoFreshStartLifePathHumanityLossRestoreChoice(opt fromDistrictChange: Bool) -> Void {
        let FreshStartLifePathRecord = TweakDBInterface.GetLifePathRecord(t"LifePaths.NewStart");
        let FreshStartLifePathType: gamedataLifePath;
        if IsDefined(FreshStartLifePathRecord) {
            FreshStartLifePathType = FreshStartLifePathRecord.Type();
        } else {
            FreshStartLifePathType = gamedataLifePath.Invalid;
        }
        
        let playerControlledObject: ref<GameObject> = GameInstance.GetPlayerSystem(GetGameInstance()).GetLocalPlayerControlledGameObject();
        let lifePath: gamedataLifePath = PlayerDevelopmentSystem.GetInstance(playerControlledObject).GetLifePath(playerControlledObject);

        // Corpo / Fresh Start
        if Equals(lifePath, gamedataLifePath.Corporate) || (NotEquals(FreshStartLifePathType, gamedataLifePath.Invalid) && Equals(lifePath, FreshStartLifePathType)) {
            // AutoDrive
            if this.AutoDriveSystem.GetAutodriveEnabled() && !this.AutoDriveSystem.GetAutodriveIsDelamain() {
                // City Center

                let thisDistrict: String = this.player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord().ParentDistrict().EnumName();
                if Equals(thisDistrict, "CityCenter") {
                    if fromDistrictChange && Equals(this.lastAutoDriveDistrictEnumName, "CityCenter") {
                        // Suppress duplicate district events in same session.
                    } else {
                        this.TryToDisplayHumanityLossRestorationChoice(DFHumanityLossRestorationActivityType.LifePathCorpoFreshStart);
                    }
                }
                this.lastAutoDriveDistrictEnumName = thisDistrict;
            }
        }
    }

    public final func TryToRestoreHumanityLossFromCharity() -> Void {
        //DFProfile();
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Charity) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMinor);
            this.lastDayRestored_Charity = GetGameInstance().GetGameTime().Days();
        }
    }

    public final func TryToRestoreHumanityLossFromDance() -> Void {
        //DFProfile();
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Dance) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMinor);
            this.lastDayRestored_Dance = GetGameInstance().GetGameTime().Days();
        }
    }

    public final func TryToRestoreHumanityLossFromIntimacy() -> Void {
        //DFProfile();
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Intimacy) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatablePivotal);
            this.lastDayRestored_Intimacy = GetGameInstance().GetGameTime().Days();
        }
    }

    public final func TryToRestoreHumanityLossFromMeditation() -> Void {
        //DFProfile();
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Meditation) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMinor);
            this.lastDayRestored_Meditation = GetGameInstance().GetGameTime().Days();
        }
    }

    public final func TryToRestoreHumanityLossFromRollercoaster() -> Void {
        //DFProfile();
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.Rollercoaster) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMajor);
            this.lastDayRestored_Rollercoaster = GetGameInstance().GetGameTime().Days();
        }
    }

    public final func TryToRestoreHumanityLossFromConfessionBooth() -> Void {
        if this.CanRestoreHumanityLossFromActivity(DFHumanityLossRestorationActivityType.ConfessionBooth) {
            if this.Settings.humanityLossRegenerationSFXEnabled {
                this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreConfessionBooth));
            }
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMinor);
            this.lastDayRestored_ConfessionBooth = GetGameInstance().GetGameTime().Days();
        }
    }

    //
    //  DFFactListener Callbacks
    //

    private final func OnSetTherapyCyberpsychosisEnabledActionFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            let cyberpsychosisSettingValue: Int32 = this.Settings.humanityLossCyberpsychosisEnabled ? 1 : 0;
            this.QuestsSystem.SetFact(n"df_fact_therapy_cyberpsychosis_enabled", cyberpsychosisSettingValue);
            this.QuestsSystem.SetFact(this.setTherapyCyberpsychosisEnabledActionFactListener.fact, 0);
        }
    }

    private final func OnTherapyShowHumanityLossTutorialActionFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.CheckHumanityLossTutorial();
            this.QuestsSystem.SetFact(this.showHumanityLossTutorialActionFactListener.fact, 0);
        }
    }

    private final func OnHumanityLossRestoreChoiceActivatedFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            // Streetkid
            if this.lastHumanityLossRestorationChoiceType == EnumInt(DFHumanityLossRestoreChoiceType.StreetKid) {
                if Equals(value, 1) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreStreetKid));
                    }
                    this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatablePivotal);
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                } else if Equals(value, 2) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCancel));
                    }
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                }

            // Nomad
            } else if this.lastHumanityLossRestorationChoiceType == EnumInt(DFHumanityLossRestoreChoiceType.Nomad) {
                if Equals(value, 1) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreNomad));
                    }
                    this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatablePivotal);
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                } else if Equals(value, 2) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCancel));
                    }
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                }

            // Corpo / Fresh Start
            } else if this.lastHumanityLossRestorationChoiceType == EnumInt(DFHumanityLossRestoreChoiceType.CorpoFreshStart) {
                if Equals(value, 1) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCorpoFreshStart));
                    }
                    this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatablePivotal);
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                } else if Equals(value, 2) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCancel));
                    }
                    this.lastDayRestored_LifePath = GetGameInstance().GetGameTime().Days();
                }
            
            // Speed
            } else if this.lastHumanityLossRestorationChoiceType == EnumInt(DFHumanityLossRestoreChoiceType.Speed) {
                if Equals(value, 1) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreSpeed));
                    }
                    this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMajor);
                    this.lastDayRestored_Speed = GetGameInstance().GetGameTime().Days();
                } else if Equals(value, 2) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCancel));
                    }
                    this.lastDayRestored_Speed = GetGameInstance().GetGameTime().Days();
                }
            
            // Confession Booth
            /*} else if this.lastHumanityLossRestorationChoiceType == EnumInt(DFHumanityLossRestoreChoiceType.ConfessionBooth) {
                if Equals(value, 1) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreConfessionBooth));
                    }
                    this.RestoreHumanityLoss(DFHumanityLossRestorationType.RepeatableMinor);
                    this.lastDayRestored_ConfessionBooth = GetGameInstance().GetGameTime().Days();
                } else if Equals(value, 2) {
                    if this.Settings.humanityLossRegenerationSFXEnabled {
                        this.QuestsSystem.SetFact(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.HumanityLossRestoreCancel));
                    }
                    this.lastDayRestored_ConfessionBooth = GetGameInstance().GetGameTime().Days();
                }
            */
            }
            
            this.QuestsSystem.SetFact(this.humanityLossRestoreChoiceActivatedActionFactListener.fact, 0);
        }
    }

    private final func OnSpeedVoicelineGetInBadlandsFactChanged(value: Int32) -> Void {
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            if IsPlayerInBadlands(this.player) {
                this.QuestsSystem.SetFact(n"df_fact_speed_voiceline_is_in_badlands", 1);
            } else {
                this.QuestsSystem.SetFact(n"df_fact_speed_voiceline_is_in_badlands", 0);
            }
            
            this.QuestsSystem.SetFact(this.speedVoicelineGetInBadlandsActionFactListener.fact, 0);
        }
    }

    private final func OnMetroPlayerStandDoorFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.CheckShouldShowStreetKidLifePathHumanityLossRestoreChoice();
        }
    }

    private final func OnMetroPlayerWindowLeftFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.CheckShouldShowStreetKidLifePathHumanityLossRestoreChoice();
        }
    }

    private final func OnMetroPlayerWindowRightFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.CheckShouldShowStreetKidLifePathHumanityLossRestoreChoice();
        }
    }

    private final func OnHomelessPaidFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.TryToRestoreHumanityLossFromCharity();
        }
    }

    private final func OnAct2StartFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventPivotal);
        }
    }

    private final func OnSQ021RandySavedFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventMinor);
        }
    }

    private final func OnSQ021RandyKaputtFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.IncreaseHumanityLoss(DFHumanityLossCostType.OneTimeEventMajor);
        }
    }

    private final func OnSQ027DoneFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    private final func OnSQ028KerryRelationshipFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    private final func OnSQ028KerryFriendFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    private final func OnSQ030RomanceFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    private final func OnSQ030FriendshipFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    // V calls Jackie after his death
    private final func OnQ005VCallsJackieDeadFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventPivotal);
        }
    }

    // V lies down with Angel or Skye during "Automatic Love"
    private final func OnQ105DollLieDownFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventPivotal);
        }
    }

    // V gives away the NUSA Medal to a homeless person
    private final func OnQ305MedalGivenAwayFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFFactListenerCanRun(value, this.factListenerRegistry, this.onceOnlyDFFactListenersFired) {
            this.RestoreHumanityLoss(DFHumanityLossRestorationType.OneTimeEventMajor);
        }
    }

    private cb func OnWarningMessage(value: Variant) -> Bool {
        //DFProfile();
        let warningMessage: SimpleScreenMessage = FromVariant<SimpleScreenMessage>(value);
        if warningMessage.isShown && Equals(warningMessage.type, SimpleMessageType.Relic) && Equals(GetLocalizedText(warningMessage.message), GetLocalizedTextByKey(n"UI-QuestNotifications-sq032_sickness_warning")) {
            this.RegisterForRelicMalfunctionHumanityLoss();
        }
    }

    private cb func OnActivePlayerVehicleSpeedValueChanged(rawSpeed: Float) -> Bool {
        //DFProfile();
        let velocity: Float = AbsF(rawSpeed);
        let multiplier: Float = GameInstance.GetStatsDataSystem(GetGameInstance()).GetValueFromCurve(n"vehicle_ui", velocity, n"speed_to_multiplier");
        let speedValue: Int32 = RoundMath(velocity * multiplier);
        if this.lastActivePlayerVehicleSpeed < this.playerVehicleSpeedHumanityLossRestoreThreshold && speedValue >= this.playerVehicleSpeedHumanityLossRestoreThreshold {
            this.TryToDisplayHumanityLossRestorationChoice(DFHumanityLossRestorationActivityType.Speed);
        }

        this.lastActivePlayerVehicleSpeed = speedValue;
    }

    // Increase Humanity Loss on Relic Malfunction
    public final func OnRelicMalfunction() -> Void {
        //DFProfile();
        this.IncreaseHumanityLoss(DFHumanityLossCostType.RepeatableRelicMalfunction);
    }

    public final func OnConfessionBothUsed() -> Void {
        //DFProfile();
        //this.TryToDisplayHumanityLossRestorationChoice(DFHumanityLossRestorationActivityType.ConfessionBooth);
        this.TryToRestoreHumanityLossFromConfessionBooth();
    }
}

// PreventionSystem - Increase the crime value of illegal neutralizations performed while Fury is active.
//
@wrapMethod(PreventionSystem)
private final func CalculateCrimeScoreForNPC(request: ref<PreventionDamageRequest>) -> Void {
    //DFProfile();
    wrappedMethod(request);

    let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();
    if request.isTargetKilled && this.GetHeatStageAsInt() < 5u && HumanityLossConditionSystem.ShouldRapidlyEscalateWantedLevel() {
        // Increase the Heat resulting from these kills.
        if request.isTargetPrevention {
            this.m_totalCrimeScore += (this.m_preventionDataTable.HeatKillPolice() * this.m_crimeScoreMultiplierByQuest) * 0.5;
        } else {
            this.m_totalCrimeScore += (this.m_preventionDataTable.HeatKillCiv() * this.m_crimeScoreMultiplierByQuest) * 0.5;
        }
    }
}

// AutoDriveSystem - Corpo / Fresh Start Lifepath Humanity Restoration
//
@wrapMethod(AutoDriveSystem)
private final func OnAutodriveToggled(enabled: Bool, isDelamain: Bool) -> Void {
    wrappedMethod(enabled, isDelamain);

    if !enabled || isDelamain {
        return;
    }
    DFHumanityLossConditionSystem.Get().CheckShouldShowCorpoFreshStartLifePathHumanityLossRestoreChoice();
}

@wrapMethod(PreventionSystem)
private final func OnDistrictAreaEntered(request: ref<DistrictEnteredEvent>) -> Void {
    wrappedMethod(request);
    DFHumanityLossConditionSystem.Get().CheckShouldShowCorpoFreshStartLifePathHumanityLossRestoreChoice(true);
}

// ConfessionalInkGameController - Humanity Loss Restore on Confessional Booth
//
@wrapMethod(ConfessionalInkGameController)
protected cb func OnVideoFinished(target: wref<inkVideo>) -> Bool {
    if this.m_isConfessing {
        DFHumanityLossConditionSystem.Get().OnConfessionBothUsed();
    }
    wrappedMethod(target);
}

@wrapMethod(VehicleObject)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() && VehicleComponent.IsDriverSlot(evt.request.lowLevelMountingInfo.slotId.id) {		
		DFHumanityLossConditionSystem.Get().TryToRegisterForVehicleSpeedChange(this);
	}

	return r;
}

@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		DFHumanityLossConditionSystem.Get().UnregisterForVehicleSpeedChange(this);
	}
	
	return r;
}
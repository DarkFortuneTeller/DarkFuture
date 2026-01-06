// -----------------------------------------------------------------------------
// DFGameStateService
// -----------------------------------------------------------------------------
//
// - A service that allows querying whether or not the game's current state is 
//   "valid" for the purposes of Dark Future in order to avoid intrusion into
//   cinematic moments, and other cases where we want to suspend the behavior
//   of the mod (while playing as Johnny Silverhand, while in the Edgerunner Fury
//   state, so on).
//
// - To obtain whether or not the current game state is valid, use IsValidGameState().
// - To obtain the specific game state, use GetGameState().
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Settings.*
import DarkFuture.Main.{
    DFMainSystem,
    DFTimeSkipData
}
import DarkFuture.UI.{
	DFHUDBarType
}

public enum GameState {
    Valid = 0,
    Invalid = 1,
    TemporarilyInvalid = 2
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    //DFProfile();
    let gameStateService: ref<DFGameStateService> = DFGameStateService.Get();

    if IsSystemEnabledAndRunning(gameStateService) {
        let effectTags: array<CName> = evt.staticData.GameplayTags();
        if ArrayContains(effectTags, n"InFury") || gameStateService.IsWannabeEdgerunnerPsychosisEffect(evt.staticData.GetID()) {
            gameStateService.OnFuryStateChanged(true);
        }

        if ArrayContains(effectTags, n"CyberspacePresence") {
            gameStateService.OnCyberspaceStateChanged(true);
        }
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    //DFProfile();
    let gameStateService: ref<DFGameStateService> = DFGameStateService.Get();

    if IsSystemEnabledAndRunning(gameStateService) {
        let effectTags: array<CName> = evt.staticData.GameplayTags();
        if ArrayContains(effectTags, n"InFury") || gameStateService.IsWannabeEdgerunnerPsychosisEffect(evt.staticData.GetID()) {
            if !gameStateService.PlayerHasAnyFuryEffect() {
                gameStateService.OnFuryStateChanged(false);
            }
        }

        if ArrayContains(effectTags, n"CyberspacePresence") {
            gameStateService.OnCyberspaceStateChanged(false);
        }
    }

	return wrappedMethod(evt);
}

public class DFGameStateServiceFuryChangedEvent extends CallbackSystemEvent {
    private let data: Bool;

    public func GetData() -> Bool {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: Bool) -> ref<DFGameStateServiceFuryChangedEvent> {
        //DFProfile();
        let event = new DFGameStateServiceFuryChangedEvent();
        event.data = data;
        return event;
    }
}

public class DFGameStateServiceCyberspaceChangedEvent extends CallbackSystemEvent {
    private let data: Bool;

    public func GetData() -> Bool {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: Bool) -> ref<DFGameStateServiceCyberspaceChangedEvent> {
        //DFProfile();
        let event = new DFGameStateServiceCyberspaceChangedEvent();
        event.data = data;
        return event;
    }
}

public class DFGameStateServiceSceneTierChangedEvent extends CallbackSystemEvent {
    private let data: GameplayTier;

    public func GetData() -> GameplayTier {
        //DFProfile();
        return this.data;
    }

    public static func Create(data: GameplayTier) -> ref<DFGameStateServiceSceneTierChangedEvent> {
        //DFProfile();
        let event = new DFGameStateServiceSceneTierChangedEvent();
        event.data = data;
        return event;
    }
}

class DFGameStateServiceEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFGameStateService> {
        //DFProfile();
		return DFGameStateService.Get();
	}
}

public final class DFGameStateService extends DFSystem {
    // DO NOT DELETE - Used for inferring Legacy 1.x to 2.0 Upgrade
    public persistent let hasShownActivationMessage: Bool = false;

    private let BlackboardSystem: ref<BlackboardSystem>;
    private let QuestsSystem: ref<QuestsSystem>;
    private let NotificationService: ref<DFNotificationService>;

    private let UISystemBlackboard: ref<IBlackboard>;
    private let UISystemDef: ref<UI_SystemDef>;
    private let playerStateMachineBlackboard: ref<IBlackboard>;
    private let playerSMDef: ref<PlayerStateMachineDef>;

    private let gameplayTierChangeListener: ref<CallbackHandle>;
    private let menuUpdateListener: ref<CallbackHandle>;
    private let baseGameIntroMissionFactListener: Uint32;
    private let baseGameQ101ShowerMissionFactListener: Uint32;
    private let phantomLibertyIntroFactListener: Uint32;
    private let baseGamePointOfNoReturnFactListener: Uint32;

    private let gameplayTier: GameplayTier = GameplayTier.Tier1_FullGameplay;
    private let baseGameIntroMissionDone: Bool = false;
    private let baseGameQ101ShowerDone: Bool = false;
    private let phantomLibertyIntroDone: Bool = false;
    private let baseGamePointOfNoReturnDone: Bool = false;
    private let isInMenu: Bool = false;
    private let isReplacer: Bool = false;
    private let isInSleepCinematic: Bool = false;
    private let isSleepingInVehicle: Bool = false;
    public let isInFury: Bool = false;
    private let isInCyberspace: Bool = false;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFGameStateService> {
        //DFProfile();
		let instance: ref<DFGameStateService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFGameStateService>()) as DFGameStateService;
		return instance;
	}

    public final static func Get() -> ref<DFGameStateService> {
        //DFProfile();
        return DFGameStateService.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    public func UnregisterAllDelayCallbacks() -> Void {}
    public func SetupData() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.gameplayTier = GameplayTier.Tier1_FullGameplay;
        this.baseGameIntroMissionDone = false;
        this.baseGameQ101ShowerDone = false;
        this.phantomLibertyIntroDone = false;
        this.isReplacer = false;
        this.isInSleepCinematic = false;
        this.isSleepingInVehicle = false;
        this.isInFury = false;
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.OnSceneTierChange(this.player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier));
        this.OnBaseGameIntroMissionFactChanged(this.QuestsSystem.GetFact(n"q001_01_go_to_sleep_done"));
        this.OnBaseGameQ101ShowerMissionFactChanged(this.QuestsSystem.GetFact(n"q101_enable_activities_flat"));
        this.OnPhantomLibertyIntroFactChanged(this.QuestsSystem.GetFact(n"q301_00_done"));
        this.OnReplacerChanged(this.player.IsReplacer());
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"), true);
        this.OnCyberspaceStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"), true);
        this.isInSleepCinematic = false;
        this.isSleepingInVehicle = false;
    }

    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance = GetGameInstance();
        this.BlackboardSystem = GameInstance.GetBlackboardSystem(gameInstance);
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        let allBlackboards: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();
        this.playerStateMachineBlackboard = this.BlackboardSystem.GetLocalInstanced(attachedPlayer.GetEntityID(), allBlackboards.PlayerStateMachine);
        this.UISystemBlackboard = this.BlackboardSystem.Get(allBlackboards.UI_System);
        this.playerSMDef = allBlackboards.PlayerStateMachine;
        this.UISystemDef = allBlackboards.UI_System;
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
        this.gameplayTierChangeListener = this.playerStateMachineBlackboard.RegisterListenerInt(this.playerSMDef.SceneTier, this, n"OnSceneTierChange", true);
        this.menuUpdateListener = this.UISystemBlackboard.RegisterListenerBool(this.UISystemDef.IsInMenu, this, n"OnMenuUpdate");
        this.baseGameIntroMissionFactListener = this.QuestsSystem.RegisterListener(n"q001_01_go_to_sleep_done", this, n"OnBaseGameIntroMissionFactChanged");
        this.baseGameQ101ShowerMissionFactListener = this.QuestsSystem.RegisterListener(n"q101_enable_activities_flat", this, n"OnBaseGameQ101ShowerMissionFactChanged");
        this.baseGamePointOfNoReturnFactListener = this.QuestsSystem.RegisterListener(n"q115_point_of_no_return", this, n"OnBaseGamePointOfNoReturnFactChanged");
        this.phantomLibertyIntroFactListener = this.QuestsSystem.RegisterListener(n"q301_00_done", this, n"OnPhantomLibertyIntroFactChanged");
    }

    private func UnregisterListeners() -> Void {
        //DFProfile();
        this.player.GetPlayerStateMachineBlackboard().UnregisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier, this.gameplayTierChangeListener);
        this.gameplayTierChangeListener = null;

        this.UISystemBlackboard.UnregisterListenerBool(this.UISystemDef.IsInMenu, this.menuUpdateListener);
        this.menuUpdateListener = null;

        this.QuestsSystem.UnregisterListener(n"q001_01_go_to_sleep_done", this.baseGameIntroMissionFactListener);
        this.baseGameIntroMissionFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"q101_enable_activities_flat", this.baseGameQ101ShowerMissionFactListener);
        this.baseGameQ101ShowerMissionFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"q115_point_of_no_return", this.baseGamePointOfNoReturnFactListener);
        this.baseGamePointOfNoReturnFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"q301_00_done", this.phantomLibertyIntroFactListener);
        this.phantomLibertyIntroFactListener = 0u;
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.OnBaseGameIntroMissionFactChanged(this.QuestsSystem.GetFact(n"q001_01_go_to_sleep_done"));
        this.OnBaseGameQ101ShowerMissionFactChanged(this.QuestsSystem.GetFact(n"q101_enable_activities_flat"));
        this.OnPhantomLibertyIntroFactChanged(this.QuestsSystem.GetFact(n"q301_00_done"));
        this.OnReplacerChanged(this.player.IsReplacer());
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

    //
    //  System-Specific Methods
    //
    public final func SetInSleepCinematic(value: Bool) -> Void {
        //DFProfile();
        this.isInSleepCinematic = value;
    }

    public final func SetSleepingInVehicle(value: Bool) -> Void {
        //DFProfile();
        this.isSleepingInVehicle = value;

        // Work-around: Fake a SceneTierChanged event to force reevaluation of any systems that might have failed
        // against a game state check while the vehicle sleeping sequence was running.
        this.OnSceneTierChange(this.player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier));
    }

    public final func GetSleepingInVehicle() -> Bool {
		//DFProfile();
		return this.isSleepingInVehicle;
	}

    protected cb func OnSceneTierChange(value: Int32) -> Void {
        //DFProfile();
        DFLog(this, "+++++++++++++++");
        DFLog(this, "+++++++++++++++ OnSceneTierChange value = " + ToString(value));
        DFLog(this, "+++++++++++++++");

        if NotEquals(IntEnum<GameplayTier>(value), GameplayTier.Undefined) {
            this.gameplayTier = IntEnum<GameplayTier>(value);
            GameInstance.GetCallbackSystem().DispatchEvent(DFGameStateServiceSceneTierChangedEvent.Create(this.gameplayTier));
        }
    }

    protected cb func OnMenuUpdate(value: Bool) -> Void {
        //DFProfile();
        this.isInMenu = value;
    }

    private final func OnBaseGameIntroMissionFactChanged(value: Int32) -> Void {
        //DFProfile();
        DFLog(this, "OnBaseGameIntroMissionFactChanged value = " + ToString(value));
        this.baseGameIntroMissionDone = value == 1 ? true : false;
    }

    private final func OnBaseGameQ101ShowerMissionFactChanged(value: Int32) -> Void {
        //DFProfile();
        DFLog(this, "OnBaseGameQ101ShowerMissionFactChanged value = " + ToString(value));
        this.baseGameQ101ShowerDone = value == 1 ? true : false;
    }

    private final func OnBaseGamePointOfNoReturnFactChanged(value: Int32) -> Void {
        //DFProfile();
        DFLog(this, "OnBaseGamePointOfNoReturnFactChanged value = " + ToString(value));
        this.baseGamePointOfNoReturnDone = value == 1 ? true : false;
    }

    private final func OnPhantomLibertyIntroFactChanged(value: Int32) -> Void {
        //DFProfile();
        DFLog(this, "OnPhantomLibertyIntroFactChanged value = " + ToString(value));
        this.phantomLibertyIntroDone = value == 1 ? true : false;
    }

    private final func OnReplacerChanged(value: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnReplacerChange value = " + ToString(value));
        this.isReplacer = value;
    }

    public final func OnFuryStateChanged(value: Bool, opt noEvent: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnFuryStateChanged value = " + ToString(value));
        this.isInFury = value;

        if !noEvent {
            GameInstance.GetCallbackSystem().DispatchEvent(DFGameStateServiceFuryChangedEvent.Create(value));
        }
    }

    public final func OnCyberspaceStateChanged(value: Bool, opt noEvent: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnCyberspaceStateChanged value = " + ToString(value));
        this.isInCyberspace = value;

        if !noEvent {
            GameInstance.GetCallbackSystem().DispatchEvent(DFGameStateServiceCyberspaceChangedEvent.Create(value));
        }
    }

    public final func GetGameState(caller: ref<IScriptable>, opt ignoreTemporarilyInvalid: Bool, opt allowLimitedGameplay: Bool) -> GameState {
        //DFProfile();
        let callerName: String = NameToString(caller.GetClassName());

        if !this.Settings.mainSystemEnabled {
            DFLog(this, "GetGameState() returned Invalid for caller " + callerName + ": this.Settings.mainSystemEnabled=" + ToString(this.Settings.mainSystemEnabled));
            return GameState.Invalid;
        }
        
        if !this.baseGameIntroMissionDone && !this.baseGameQ101ShowerDone && !this.phantomLibertyIntroDone {
            DFLog(this, "GetGameState() returned Invalid for caller " + callerName + ": this.baseGameIntroMissionDone=" + ToString(this.baseGameIntroMissionDone) + ", this.baseGameQ101ShowerDone=" + ToString(this.baseGameQ101ShowerDone) + ", this.phantomLibertyIntroDone=" + ToString(this.phantomLibertyIntroDone));
            return GameState.Invalid;
        }

        if this.baseGamePointOfNoReturnDone {
            DFLog(this, "GetGameState() returned Invalid for caller " + callerName + ": this.baseGamePointOfNoReturnDone=" + ToString(this.baseGamePointOfNoReturnDone));
            return GameState.Invalid;
        }

        if this.isReplacer {
            DFLog(this, "GetGameState() returned Invalid for caller " + callerName + ": this.isReplacer=" + ToString(this.isReplacer));
            return GameState.Invalid;
        }

        if this.isInCyberspace {
            DFLog(this, "GetGameState() returned Invalid for caller " + callerName + ": this.isInCyberspace=" + ToString(this.isInCyberspace));
            return GameState.Invalid;
        }

        if !ignoreTemporarilyInvalid && (this.isInSleepCinematic || this.isSleepingInVehicle) {
            DFLog(this, "GetGameState() returned Temporarily Invalid for caller " + callerName + ": this.isInSleepCinematic=" + ToString(this.isInSleepCinematic) + ", this.isSleepingInVehicle=" + ToString(this.isSleepingInVehicle));
            return GameState.TemporarilyInvalid;
        }

        if !ignoreTemporarilyInvalid && this.isInFury {
            DFLog(this, "GetGameState() returned Temporarily Invalid for caller " + callerName + ": this.isInFury=" + ToString(this.isInFury));
            return GameState.TemporarilyInvalid;
        }

        let gameplayTierValue: Int32 = EnumInt<GameplayTier>(this.gameplayTier);
        let highestAllowableTier: Int32 = ignoreTemporarilyInvalid ? 5 : (allowLimitedGameplay ? 3 : 2);
        if gameplayTierValue > highestAllowableTier {
            DFLog(this, "GetGameState() returned Temporarily Invalid for caller " + callerName + ": this.gameplayTierValue=" + ToString(gameplayTierValue) + ", highest allowable tier=" + ToString(highestAllowableTier));
            return GameState.TemporarilyInvalid;
        }

        return GameState.Valid;
    }

    public final func IsValidGameState(caller: ref<IScriptable>, opt ignoreTemporarilyInvalid: Bool, opt allowLimitedGameplay: Bool) -> Bool {
        //DFProfile();
        return Equals(this.GetGameState(caller, ignoreTemporarilyInvalid, allowLimitedGameplay), GameState.Valid);
    }

    public final func PlayerHasAnyFuryEffect() -> Bool {
        //DFProfile();
        return StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury") || 
                (this.Settings.compatibilityWannabeEdgerunner && 
                    (
                        StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.NewPsychosisEffectNormalFx") ||
                        StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.NewPsychosisEffectLightFx")
                    )
                );
    }

    public final func IsInAnyMenu() -> Bool {
        //DFProfile();
        return this.isInMenu;
    }

    //
	//	Wannabe Edgerunner
	//
    public final func IsWannabeEdgerunnerPsychosisEffect(id: TweakDBID) -> Bool {
        //DFProfile();
        if this.Settings.compatibilityWannabeEdgerunner {
            if Equals(id, t"BaseStatusEffect.NewPsychosisEffectNormalFx") || Equals(id, t"BaseStatusEffect.NewPsychosisEffectLightFx") {
                return true;
            }
        }

        return false;
    }
}

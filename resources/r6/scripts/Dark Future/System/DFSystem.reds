// -----------------------------------------------------------------------------
// DFSystem
// -----------------------------------------------------------------------------
//
// - Base class for nearly all Dark Future ScriptableSystems.
// - Provides a common interface for handling system startup, shutdown,
//   querying required systems, registering for callbacks and listeners, etc.
//

module DarkFuture.System

import DarkFuture.Logging.*
import DarkFuture.Main.{
    MainSystemPlayerDeathEvent,
    MainSystemTimeSkipStartEvent,
    MainSystemTimeSkipCancelledEvent,
    MainSystemTimeSkipFinishedEvent,
    DFTimeSkipData
}
import DarkFuture.Settings.{
    DFSettings,
    SettingChangedEvent
}

public enum DFSystemState {
    Uninitialized = 0,
    Suspended = 1,
    Running = 2
}


public func IsSystemEnabledAndRunning(system: ref<DFSystem>) -> Bool {
    //DFProfile();
    if !DFSettings.Get().mainSystemEnabled { return false; }

    return system.GetSystemToggleSettingValue() && Equals(system.state, DFSystemState.Running);
}

public abstract class DFSystemEventListener extends ScriptableService {
	//
	// Required Overrides
	//
	private func GetSystemInstance() -> wref<DFSystem> {
        //DFProfile();
		DFLogNoSystem(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	public cb func OnLoad() {
        //DFProfile();
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemPlayerDeathEvent", this, n"OnMainSystemPlayerDeathEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipStartEvent", this, n"OnMainSystemTimeSkipStartEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipCancelledEvent", this, n"OnMainSystemTimeSkipCancelledEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipFinishedEvent", this, n"OnMainSystemTimeSkipFinishedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Settings.SettingChangedEvent", this, n"OnSettingChangedEvent", true);
    }

	private cb func OnMainSystemPlayerDeathEvent(event: ref<MainSystemPlayerDeathEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnPlayerDeath();
    }

	private cb func OnMainSystemTimeSkipStartEvent(event: ref<MainSystemTimeSkipStartEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnTimeSkipStart();
    }

	private cb func OnMainSystemTimeSkipCancelledEvent(event: ref<MainSystemTimeSkipCancelledEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnTimeSkipCancelled();
    }

	private cb func OnMainSystemTimeSkipFinishedEvent(event: ref<MainSystemTimeSkipFinishedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnTimeSkipFinished(event.GetData());
    }

    private cb func OnSettingChangedEvent(event: ref<SettingChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnSettingChanged(event.GetData());
    }
}

public abstract class DFSystem extends ScriptableSystem {
    public let state: DFSystemState = DFSystemState.Uninitialized;
    public let debugEnabled: Bool = false;
    public let player: ref<PlayerPuppet>;
    public let Settings: ref<DFSettings>;
    public let DelaySystem: ref<DelaySystem>;

    public func Init(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.player = attachedPlayer;
		this.DoInitActions(attachedPlayer);
        this.InitSpecific(attachedPlayer);
        
        // Now that all data has been set correctly, if this system should be
        // toggled off, suspend it.
        if Equals(this.GetSystemToggleSettingValue(), false) {
            this.Suspend();
        }
    }

    private func DoInitActions(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.SetupDebugLogging();
		DFLog(this, "Init");

        this.GetRequiredSystems();
		this.GetSystems();
		this.GetBlackboards(attachedPlayer);
        this.SetupData();
		this.RegisterListeners();
        this.RegisterAllRequiredDelayCallbacks();

        this.state = DFSystemState.Running;
        DFLog(this, "INIT - Current State: " + ToString(this.state));
    }

    public func Suspend() -> Void {
        //DFProfile();
        DFLog(this, "SUSPEND - Current State: " + ToString(this.state));
        if Equals(this.state, DFSystemState.Running) {
            this.state = DFSystemState.Suspended;
            this.UnregisterAllDelayCallbacks();
            this.DoPostSuspendActions();
        }
        DFLog(this, "SUSPEND - Current State: " + ToString(this.state));
    }

    public func Resume() -> Void {
        //DFProfile();
        DFLog(this, "RESUME - Current State: " + ToString(this.state));
        if Equals(this.state, DFSystemState.Suspended) {
            this.state = DFSystemState.Running;
            this.RegisterAllRequiredDelayCallbacks();
            this.DoPostResumeActions();
        }
        DFLog(this, "RESUME - Current State: " + ToString(this.state));
    }

    public func Stop() -> Void {
        //DFProfile();
        this.UnregisterListeners();
        this.UnregisterAllDelayCallbacks();

        this.state = DFSystemState.Uninitialized;
    }

    public func OnPlayerDeath() -> Void {
        //DFProfile();
        this.Stop();
	}

    private func GetRequiredSystems() -> Void {
        //DFProfile();
        let gameInstance = GetGameInstance();
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
    }

    public func OnSettingChanged(changedSettings: array<String>) -> Void {
        //DFProfile();
        // Check for specific system toggle
        if this.Settings.mainSystemEnabled {
            if ArrayContains(changedSettings, this.GetSystemToggleSettingString()) {
                if Equals(this.GetSystemToggleSettingValue(), true) {
                    this.Resume();
                } else {
                    this.Suspend();
                }
            }
        }
        
        this.OnSettingChangedSpecific(changedSettings);
    }

    //
    //  Required Overrides
    //
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("InitSpecific");
    }

    public func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        this.LogMissingOverrideError("GetSystemToggleSettingValue");
        return false;
    }

    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        this.LogMissingOverrideError("GetSystemToggleSettingString");
        return "INVALID";
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("DoPostSuspendActions");
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("DoPostResumeActions");
    }

    private func SetupDebugLogging() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("SetupDebugLogging");
	}

    public func GetSystems() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("GetSystems");
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.LogMissingOverrideError("GetBlackboards");
    }

    public func SetupData() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("SetupData");
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("RegisterListeners");
	}

    private func UnregisterListeners() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("UnregisterListeners");
	}

    private func RegisterAllRequiredDelayCallbacks() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("RegisterAllRequiredDelayCallbacks");
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.LogMissingOverrideError("UnregisterAllDelayCallbacks");
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("OnTimeSkipStart");
	}

	public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("OnTimeSkipCancelled");
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
		this.LogMissingOverrideError("OnTimeSkipFinished");
	}

    public func OnSettingChangedSpecific(changedSettings: array<String>) {
        //DFProfile();
        this.LogMissingOverrideError("OnSettingChangedSpecific");
    }

    //
	//	Logging
	//
    public final func IsDebugEnabled() -> Bool {
        //DFProfile();
        return this.debugEnabled;
    }

	public final func LogMissingOverrideError(funcName: String) -> Void {
        //DFProfile();
		DFLog(this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}
}

/* Required Override Template

//
//  DFSystem Required Methods
//
private func SetupDebugLogging() -> Void {}
public func GetSystemToggleSettingValue() -> Bool {}
private func GetSystemToggleSettingString() -> String {}
public func DoPostSuspendActions() -> Void {}
public func DoPostResumeActions() -> Void {}
public func GetSystems() -> Void {}
private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
public func SetupData() -> Void {}
private func RegisterListeners() -> Void {}
private func RegisterAllRequiredDelayCallbacks() -> Void {}
public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
private func UnregisterListeners() -> Void {}
public func UnregisterAllDelayCallbacks() -> Void {}
public func OnTimeSkipStart() -> Void {}
public func OnTimeSkipCancelled() -> Void {}
public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

*/
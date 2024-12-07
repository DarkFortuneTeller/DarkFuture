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

enum DFSystemState {
    Uninitialized = 0,
    Suspended = 1,
    Running = 2
}


public final static func IsSystemEnabledAndRunning(system: ref<DFSystem>) -> Bool {
    if !DFSettings.Get().mainSystemEnabled { return false; }

    return system.GetSystemToggleSettingValue() && Equals(system.state, DFSystemState.Running);
}

public abstract class DFSystemEventListener extends ScriptableService {
	//
	// Required Overrides
	//
	private func GetSystemInstance() -> wref<DFSystem> {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	private cb func OnLoad() {
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemPlayerDeathEvent", this, n"OnMainSystemPlayerDeathEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipStartEvent", this, n"OnMainSystemTimeSkipStartEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipCancelledEvent", this, n"OnMainSystemTimeSkipCancelledEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemTimeSkipFinishedEvent", this, n"OnMainSystemTimeSkipFinishedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Settings.SettingChangedEvent", this, n"OnSettingChangedEvent", true);
    }

	private cb func OnMainSystemPlayerDeathEvent(event: ref<MainSystemPlayerDeathEvent>) {
        this.GetSystemInstance().OnPlayerDeath();
    }

	private cb func OnMainSystemTimeSkipStartEvent(event: ref<MainSystemTimeSkipStartEvent>) {
        this.GetSystemInstance().OnTimeSkipStart();
    }

	private cb func OnMainSystemTimeSkipCancelledEvent(event: ref<MainSystemTimeSkipCancelledEvent>) {
        this.GetSystemInstance().OnTimeSkipCancelled();
    }

	private cb func OnMainSystemTimeSkipFinishedEvent(event: ref<MainSystemTimeSkipFinishedEvent>) {
        this.GetSystemInstance().OnTimeSkipFinished(event.GetData());
    }

    private cb func OnSettingChangedEvent(event: ref<SettingChangedEvent>) {
		this.GetSystemInstance().OnSettingChanged(event.GetData());
    }
}

public abstract class DFSystem extends ScriptableSystem {
    public let state: DFSystemState = DFSystemState.Uninitialized;
    private let debugEnabled: Bool = false;
    private let player: ref<PlayerPuppet>;
    private let Settings: ref<DFSettings>;
    private let DelaySystem: ref<DelaySystem>;

    public func Init(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.player = attachedPlayer;
		this.DoInitActions(attachedPlayer);
        this.InitSpecific(attachedPlayer);
    }

    private func DoInitActions(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.SetupDebugLogging();
		DFLog(this.debugEnabled, this, "Init");

        this.GetRequiredSystems();
		this.GetSystems();
		this.GetBlackboards(attachedPlayer);
        this.SetupData();
		this.RegisterListeners();
        this.RegisterAllRequiredDelayCallbacks();

        this.state = DFSystemState.Running;
        DFLog(this.debugEnabled, this, "INIT - Current State: " + ToString(this.state));
    }

    public func Suspend() -> Void {
        DFLog(this.debugEnabled, this, "SUSPEND - Current State: " + ToString(this.state));
        if Equals(this.state, DFSystemState.Running) {
            this.state = DFSystemState.Suspended;
            this.UnregisterAllDelayCallbacks();
            this.DoPostSuspendActions();
        }
    }

    public func Resume() -> Void {
        DFLog(this.debugEnabled, this, "RESUME - Current State: " + ToString(this.state));
        if Equals(this.state, DFSystemState.Suspended) {
            this.state = DFSystemState.Running;
            this.RegisterAllRequiredDelayCallbacks();
            this.DoPostResumeActions();
        }
    }

    public func Stop() -> Void {
        this.UnregisterListeners();
        this.UnregisterAllDelayCallbacks();
        this.DoStopActions();

        this.state = DFSystemState.Uninitialized;
    }

    public func OnPlayerDeath() -> Void {
        this.Stop();
	}

    private func GetRequiredSystems() -> Void {
        let gameInstance = GetGameInstance();
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
    }

    public func OnSettingChanged(changedSettings: array<String>) -> Void {
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
    private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.LogMissingOverrideError("InitSpecific");
    }

    private func GetSystemToggleSettingValue() -> Bool {
        this.LogMissingOverrideError("GetSystemToggleSettingValue");
        return false;
    }

    private func GetSystemToggleSettingString() -> String {
        this.LogMissingOverrideError("GetSystemToggleSettingString");
        return "INVALID";
    }

    private func DoPostSuspendActions() -> Void {
        this.LogMissingOverrideError("DoPostSuspendActions");
    }

    private func DoPostResumeActions() -> Void {
        this.LogMissingOverrideError("DoPostResumeActions");
    }

    private func SetupDebugLogging() -> Void {
		this.LogMissingOverrideError("SetupDebugLogging");
	}

    private func GetSystems() -> Void {
        this.LogMissingOverrideError("GetSystems");
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.LogMissingOverrideError("GetBlackboards");
    }

    private func SetupData() -> Void {
        this.LogMissingOverrideError("SetupData");
    }

    private func RegisterListeners() -> Void {
		this.LogMissingOverrideError("RegisterListeners");
	}

    private func UnregisterListeners() -> Void {
		this.LogMissingOverrideError("UnregisterListeners");
	}

    private func RegisterAllRequiredDelayCallbacks() -> Void {
        this.LogMissingOverrideError("RegisterAllRequiredDelayCallbacks");
    }

    private func UnregisterAllDelayCallbacks() -> Void {
        this.LogMissingOverrideError("UnregisterAllDelayCallbacks");
    }

    private func DoStopActions() -> Void {
        this.LogMissingOverrideError("DoStopActions");
    }

    public func OnTimeSkipStart() -> Void {
		this.LogMissingOverrideError("OnTimeSkipStart");
	}

	public func OnTimeSkipCancelled() -> Void {
		this.LogMissingOverrideError("OnTimeSkipCancelled");
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		this.LogMissingOverrideError("OnTimeSkipFinished");
	}

    public func OnSettingChangedSpecific(changedSettings: array<String>) {
        this.LogMissingOverrideError("OnSettingChangedSpecific");
    }

    //
	//	Logging
	//
	private final func LogMissingOverrideError(funcName: String) -> Void {
		DFLog(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR " + funcName + "()", DFLogLevel.Error);
	}
}

/* Required Override Template

//
//  DFSystem Required Methods
//
private func SetupDebugLogging() -> Void {}
private func GetSystemToggleSettingValue() -> Bool {}
private func GetSystemToggleSettingString() -> String {}
private func DoPostSuspendActions() -> Void {}
private func DoPostResumeActions() -> Void {}
private func DoStopActions() -> Void {}
private func GetSystems() -> Void {}
private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
private func SetupData() -> Void {}
private func RegisterListeners() -> Void {}
private func RegisterAllRequiredDelayCallbacks() -> Void {}
private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
private func UnregisterListeners() -> Void {}
private func UnregisterAllDelayCallbacks() -> Void {}
public func OnTimeSkipStart() -> Void {}
public func OnTimeSkipCancelled() -> Void {}
public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

*/
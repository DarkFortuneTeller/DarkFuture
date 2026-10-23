// -----------------------------------------------------------------------------
// DFImpairedDrivingSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles impaired driving.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
    DFRunGuard,
    RandRangeInclusive
}
import DarkFuture.Settings.DFSettings
import DarkFuture.Main.{
    DFTimeSkipData
}
import DarkFuture.Needs.{
    DFEnergySystem,
    DFNeedValueChangedEvent,
    DFNeedValueChangedEventDatum,
    DFNeedType
}
import DarkFuture.Services.{
    DFGameStateService,
    DFNotificationService,
    DFNotification,
    DFNotificationCallback,
    DFVisualEffect,
    DFBarUIDisplay,
    DFPlayerStateService,
    DFManagedEffectType
}
import DarkFuture.UI.DFHUDBarType

@wrapMethod(VehicleObject)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {		
	    DFImpairedDrivingSystem.Get().HandlePlayerMountedVehicle(this);
	}

	return r;
}

@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		DFImpairedDrivingSystem.Get().HandlePlayerUnmountedVehicle();
	}
	
	return r;
}

@wrapMethod(AutoDriveSystem)
private final func OnAutodriveToggled(enabled: Bool, isDelamain: Bool) -> Void {
    wrappedMethod(enabled, isDelamain);

    DFImpairedDrivingSystem.Get().HandleAutoDriveToggled(enabled);
}

public enum DFImpairedDrivingMode {
    Off = 0,
    LowIntensity = 1,
    HighIntensity = 2
}

public enum DFImpairedDrivingDebugFactID {
	Invalid = 0,
	StartUp = 1,
	ImpairedDrivingActionReceived = 2,
	ControlLossEnabled = 3,
	ControlLossDisabled = 4
}

public enum DFImpairedDrivingVFXDebugFactID {
	Invalid = 0,
	StartUp = 1,
	VFXSceneEnd = 2
}

public enum DFImpairedDrivingAction {
    None = 0,
    EnableControlLoss = 1,
    DisableControlLoss = 2,
    StartVFXScene = 3
}

public enum DFImpairedDrivingVFXCommand {
    None = 0,
    LowDuration = 1,
    HighDuration = 2,
    LowDurationDrunk = 3,
    HighDurationDrunk = 4
}

public class ControlLossInitialDelay extends DFDelayCallback {
	public let ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>;

	public static func Create(ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ControlLossInitialDelay> = new ControlLossInitialDelay();
		self.ImpairedDrivingSystem = ImpairedDrivingSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.controlLossInitialDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.OnControlLossInitialDelayFinished();
	}
}

public class ControlLossPreStartDelay extends DFDelayCallback {
	public let ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>;

	public static func Create(ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ControlLossPreStartDelay> = new ControlLossPreStartDelay();
		self.ImpairedDrivingSystem = ImpairedDrivingSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.controlLossPreStartDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.OnControlLossPreStart();
	}
}

public class ControlLossStartDelay extends DFDelayCallback {
	public let ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>;
    public let controlLossDuration: Float;

	public static func Create(ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>, controlLossDuration: Float) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ControlLossStartDelay> = new ControlLossStartDelay();
		self.ImpairedDrivingSystem = ImpairedDrivingSystem;
        self.controlLossDuration = controlLossDuration;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.controlLossStartDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.OnControlLossStart(this.controlLossDuration);
	}
}

public class ControlLossFinishDelay extends DFDelayCallback {
	public let ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>;

	public static func Create(ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<ControlLossFinishDelay> = new ControlLossFinishDelay();
		self.ImpairedDrivingSystem = ImpairedDrivingSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.controlLossFinishDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.ImpairedDrivingSystem.OnControlLossFinish();
	}
}

class DFImpairedDrivingSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFImpairedDrivingSystem> {
        //DFProfile();
		return DFImpairedDrivingSystem.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFNeedValueChangedEvent>(), this, n"OnNeedValueChangedEvent", true);
    }

	private cb func OnNeedValueChangedEvent(event: ref<DFNeedValueChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnNeedValueChanged(event.GetData());
	}
}

public final class DFImpairedDrivingSystem extends DFSystem {
    public let controlLossBehaviorInProgress: Bool = false;
    public let controlLossHappeningNow: Bool = false;

    private let AutoDriveSystem: ref<AutoDriveSystem>;
    private let QuestsSystem: ref<QuestsSystem>;
    private let EnergySystem: ref<DFEnergySystem>;
    private let GameStateService: ref<DFGameStateService>;
    private let NotificationService: ref<DFNotificationService>;
    private let PlayerStateService: ref<DFPlayerStateService>;

    public let controlLossInitialDelayID: DelayID;
    public let controlLossPreStartDelayID: DelayID;
    public let controlLossStartDelayID: DelayID;
    public let controlLossFinishDelayID: DelayID;

    private const let energyStageControlLossThresholdLowIntensity: Int32 = 3;
    private const let energyStageControlLossThresholdHighIntensity: Int32 = 4;

    private const let controlLossInitialStartDelay: Float = 20.0;
    private const let controlLossInitialStartDelayVariance: Float = 10.0;

    private const let controlLossPreStartDuration: Float = 0.7;

    private const let controlLossBaseStartDelayLowIntensity: Float = 40.0;
    private const let controlLossBaseStartDelayHighIntensity: Float = 20.0;
    private const let controlLossStartDelayVariance: Float = 12.0;
    private const let controlLossDuration_Short: Float = 1.6;
    private const let controlLossDuration_VeryLong: Float = 3.4;

    public const let impairedDrivingSpeedThresholdInMph: Int32 = 42;

    private let factListenerImpairedDrivingDebugID: Uint32;
    private let factListenerImpairedDrivingVFXDebugID: Uint32;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFImpairedDrivingSystem> {
        //DFProfile();
		let instance: ref<DFImpairedDrivingSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFImpairedDrivingSystem>()) as DFImpairedDrivingSystem;
		return instance;
	}

	public final static func Get() -> ref<DFImpairedDrivingSystem> {
        //DFProfile();
		return DFImpairedDrivingSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func SetupDebugLogging() -> Void {
        this.debugEnabled = false;
    }

    public func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.impairedDrivingEnabled;
    }

    private func GetSystemToggleSettingString() -> String {
        return "impairedDrivingEnabled";
    }

    public func DoPostSuspendActions() -> Void {
        this.StopControlLossBehavior();
    }

    public func DoPostResumeActions() -> Void {
        this.TryToStartControlLossBehavior();
    }
    
    public func GetSystems() -> Void {
        let gameInstance = GetGameInstance();

        this.AutoDriveSystem = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<AutoDriveSystem>()) as AutoDriveSystem;
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    public func SetupData() -> Void {}
    
    private func RegisterListeners() -> Void {
        //DFProfile();
        this.factListenerImpairedDrivingDebugID = GameInstance.GetQuestsSystem(GetGameInstance()).RegisterListener(this.GetImpairedDrivingDebugFact(), this, n"OnImpairedDrivingDebugFactSet");
        this.factListenerImpairedDrivingVFXDebugID = GameInstance.GetQuestsSystem(GetGameInstance()).RegisterListener(this.GetImpairedDrivingDebugVFXFact(), this, n"OnImpairedDrivingVFXDebugFactSet");
    }
    
    private func RegisterAllRequiredDelayCallbacks() -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.StopControlLossBehavior();
        this.TryToStartControlLossBehavior();
    }

    private func UnregisterListeners() -> Void {
        //DFProfile();
        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetImpairedDrivingDebugFact(), this.factListenerImpairedDrivingDebugID);
        this.factListenerImpairedDrivingDebugID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetImpairedDrivingDebugVFXFact(), this.factListenerImpairedDrivingVFXDebugID);
        this.factListenerImpairedDrivingVFXDebugID = 0u;
    }
    
    public func UnregisterAllDelayCallbacks() -> Void {
        this.UnregisterForControlLossInitialDelay();
        this.UnregisterForControlLossPreStart();
        this.UnregisterForControlLossStart();
        this.UnregisterForControlLossFinish();
    }
    
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipBegin() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    //
    //  System-Specific Methods
    //
    private final func GetImpairedDrivingActionFact() -> CName {
        return n"df_fact_action_impaired_driving";
    }

    private final func GetImpairedDrivingVFXCommandFact() -> CName {
        return n"df_fact_impaired_driving_vfx_command";
    }

    private final func GetImpairedDrivingDebugFact() -> CName {
        return n"df_fact_debug_impaired_driving";
    }

    private final func GetImpairedDrivingDebugVFXFact() -> CName {
        return n"df_fact_debug_impaired_driving_vfx";
    }

    //  Impaired Driving can start or stop after:
    //      Player loads game (while mounted)
    //      Player mounts vehicle
    //      Energy value changes
    //      AutoDrive is toggled
    //
    //  Impaired Driving Handlers (Also see: InitSpecific())
    //
    public final func HandlePlayerMountedVehicle(vehObj: ref<VehicleObject>) -> Void {
        if DFRunGuard(this) { return; }

        this.TryToStartControlLossBehavior();
        this.ShowImpairedDrivingTutorialPopup();
    }

    public final func HandleAutoDriveToggled(enabled: Bool) -> Void {
        if DFRunGuard(this) { return; }

        if enabled {
            this.StopControlLossBehavior();
        } else {
            this.TryToStartControlLossBehavior();
        }
    }

    public final func OnNeedValueChanged(evt: DFNeedValueChangedEventDatum) -> Void {
        if DFRunGuard(this) { return; }

        if Equals(evt.needType, DFNeedType.Energy) {
            if this.EnergySystem.GetNeedStageAtValue(evt.newValue) >= this.energyStageControlLossThresholdLowIntensity {
                this.TryToStartControlLossBehavior();
            } else {
                this.StopControlLossBehavior();
            }
        }
	}

    public final func HandlePlayerUnmountedVehicle() -> Void {
        if DFRunGuard(this) { return; }

        this.StopControlLossBehavior();
    }
    //
    //  Impaired Driving Handlers End
    //

    private final func TryToStartControlLossBehavior() -> Void {
        if DFRunGuard(this) { 
            DFLog(this, "Failed to start: RunGuard");
            return;
        }
        if !this.GameStateService.IsValidGameState(this) {
            DFLog(this, "Failed to start: Invalid GameState");
            return;
        }
        if this.controlLossBehaviorInProgress {
            DFLog(this, "Failed to start: Control Loss already in progress");
            return;
        }

        let gameInstance = GetGameInstance();
        let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(gameInstance, this.player, vehicleObj);

        if IsDefined(vehicleObj) && !vehicleObj.IsQuest() && VehicleComponent.IsDriver(gameInstance, this.player) {
            let mode: DFImpairedDrivingMode = this.GetModeBasedOnCurrentScenario();
            if NotEquals(mode, DFImpairedDrivingMode.Off) {
                // TODOFUTURE
                //this.QuestsSystem.SetFact(n"df_fact_action_try_to_show_impaired_driving_tutorial", 1);
                this.StartControlLossBehavior();
            } else {
                DFLog(this, "Failed to start: Resolved mode is Off");
            }
        } else {
            DFLog(this, "Failed to start: Not mounted to vehicle, vehicle was quest vehicle, or player not driver");
        }
    }

    private final func ApplyControlLoss() -> Void {
        DFLog(this, "~~~~~~~~~   APPLY CONTROL LOSS");
        this.controlLossHappeningNow = true;
        this.QuestsSystem.SetFact(this.GetImpairedDrivingActionFact(), EnumInt(DFImpairedDrivingAction.EnableControlLoss));
    }

    private final func ApplyControlLossVFX(intensity: DFImpairedDrivingVFXCommand) -> Void {
        let notification: DFNotification;
        notification.needsUI = DFBarUIDisplay(DFHUDBarType.Energy, true, false, false, false);
		this.NotificationService.QueueNotification(notification);

        this.QuestsSystem.SetFact(this.GetImpairedDrivingVFXCommandFact(), EnumInt<DFImpairedDrivingVFXCommand>(intensity));
    }

    private final func RestoreControl() -> Void {
        DFLog(this, "~~~~~~~~~   RESTORE CONTROL");
        this.controlLossHappeningNow = false;
        this.QuestsSystem.SetFact(this.GetImpairedDrivingActionFact(), EnumInt(DFImpairedDrivingAction.DisableControlLoss));
    }

    private final func StartControlLossBehavior() -> Void {
        //DFProfile();
        DFLog(this, "~~~~~~~~~ Starting Control Loss Behavior");
        this.controlLossBehaviorInProgress = true;
        let initialDelay: Float = this.controlLossInitialStartDelay + RandRangeF(0.0, this.controlLossInitialStartDelayVariance);
        this.RegisterForControlLossInitialDelay(initialDelay);

        // Start the VFX Scene.
        this.QuestsSystem.SetFact(this.GetImpairedDrivingActionFact(), EnumInt(DFImpairedDrivingAction.StartVFXScene));
    }

    private final func StopControlLossBehavior() -> Void {
        //DFProfile();
        DFLog(this, "~~~~~~~~~ Stopping Control Loss Behavior");
        this.controlLossBehaviorInProgress = false;
        this.UnregisterForControlLossInitialDelay();
        this.UnregisterForControlLossPreStart();
        this.UnregisterForControlLossStart();
        this.UnregisterForControlLossFinish();
        this.RestoreControl();
    }

    public final func OnControlLossInitialDelayFinished() -> Void {
        this.OnControlLossPreStart();
    }

    public final func OnControlLossPreStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        let mode: DFImpairedDrivingMode = this.GetModeBasedOnCurrentScenario();
        let alcoholStackCount: Uint32 = this.PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Alcohol);
        DFLog(this, "~~~~~~~~~ Resolved mode: " + ToString(mode));

        if NotEquals(mode, DFImpairedDrivingMode.Off) {
            let controlLossDuration: Float;
            let vfxCommand: DFImpairedDrivingVFXCommand;
            let roll: Int32 = RandRangeInclusive(1, 10);
            if roll <= 4 && Equals(mode, DFImpairedDrivingMode.HighIntensity) {
                DFLog(this, "~~~~~~~~~ Selected VERY LONG DURATION");
                controlLossDuration = this.controlLossDuration_VeryLong;

                if alcoholStackCount >= 3u {
                    vfxCommand = DFImpairedDrivingVFXCommand.HighDurationDrunk;
                } else {
                    vfxCommand = DFImpairedDrivingVFXCommand.HighDuration;
                }
                
            } else {
                DFLog(this, "~~~~~~~~~ Selected SHORT DURATION");
                controlLossDuration = this.controlLossDuration_Short;

                if alcoholStackCount >= 3u {
                    vfxCommand = DFImpairedDrivingVFXCommand.LowDurationDrunk;
                } else {
                    vfxCommand = DFImpairedDrivingVFXCommand.LowDuration;
                }
            }

            if this.GetIsPlayerVehicleSpeedOverThreshold() {
                this.ApplyControlLossVFX(vfxCommand);
            }
            
            this.RegisterForControlLossStart(controlLossDuration);

        } else {
            DFLog(this, "~~~~~~~~~ HALTING - Mode is Off");
            this.StopControlLossBehavior();
        }
    }

    public final func OnControlLossStart(controlLossDuration: Float) -> Void {
        if this.GetIsPlayerVehicleSpeedOverThreshold() {
            this.ApplyControlLoss();
        }

        this.RegisterForControlLossFinish(controlLossDuration);
    }

    public final func OnControlLossFinish() -> Void {
        //DFProfile();
        this.RestoreControl();

        let mode: DFImpairedDrivingMode = this.GetModeBasedOnCurrentScenario();
        DFLog(this, "~~~~~~~~~ Resolved mode: " + ToString(mode));

        if NotEquals(mode, DFImpairedDrivingMode.Off) {
            let delay: Float;
            if Equals(mode, DFImpairedDrivingMode.LowIntensity) {
                delay = this.controlLossBaseStartDelayLowIntensity + RandRangeF(0.0, this.controlLossStartDelayVariance);
            } else if Equals(mode, DFImpairedDrivingMode.HighIntensity) {
                delay = this.controlLossBaseStartDelayHighIntensity + RandRangeF(0.0, this.controlLossStartDelayVariance);
            }

            DFLog(this, "~~~~~~~~~ Delay: " + ToString(delay));
            this.RegisterForControlLossPreStart(delay);
        } else {
            DFLog(this, "~~~~~~~~~ HALTING - Mode is Off");
            this.StopControlLossBehavior();
        }
    }

    private final func GetIsPlayerVehicleSpeedOverThreshold() -> Bool {
        let gameInstance = GetGameInstance();
        let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(gameInstance, this.player, vehicleObj);

        if IsDefined(vehicleObj) && !vehicleObj.IsQuest() && VehicleComponent.IsDriver(gameInstance, this.player) {
            let rawSpeed: Float = vehicleObj.GetCurrentSpeed();
            let velocity: Float = AbsF(rawSpeed);
            let multiplier: Float = GameInstance.GetStatsDataSystem(GetGameInstance()).GetValueFromCurve(n"vehicle_ui", velocity, n"speed_to_multiplier");
            let speedValue: Int32 = RoundMath(velocity * multiplier);
            if speedValue < this.impairedDrivingSpeedThresholdInMph {
                DFLog(this, "~~~~~~~~~ IGNORING - Speed Too Low");
                return false;
            }
        } else {
            DFLog(this, "~~~~~~~~~ IGNORING - Vehicle State Invalid");
            return false;
        }

        return true;
    }

    private final func GetModeBasedOnCurrentScenario() -> DFImpairedDrivingMode {
        if this.player.IsInCombat() {
            return DFImpairedDrivingMode.Off;
        }
        
        if this.AutoDriveSystem.GetAutodriveEnabled() {
            return DFImpairedDrivingMode.Off;
        }

        let energyStage: Int32 = this.EnergySystem.GetNeedStage();

        if energyStage == this.energyStageControlLossThresholdLowIntensity {
            return DFImpairedDrivingMode.LowIntensity;
        } else if energyStage == this.energyStageControlLossThresholdHighIntensity {
            return DFImpairedDrivingMode.HighIntensity;
        }

        return DFImpairedDrivingMode.Off;
    }

    private final func RegisterForControlLossInitialDelay(delay: Float) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, ControlLossInitialDelay.Create(this), this.controlLossInitialDelayID, delay);
    }

    private final func RegisterForControlLossPreStart(delay: Float) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, ControlLossPreStartDelay.Create(this), this.controlLossPreStartDelayID, delay);
    }

    private final func RegisterForControlLossStart(controlLossDuration: Float) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, ControlLossStartDelay.Create(this, controlLossDuration), this.controlLossStartDelayID, this.controlLossPreStartDuration);
    }

    private final func RegisterForControlLossFinish(delay: Float) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, ControlLossFinishDelay.Create(this), this.controlLossFinishDelayID, delay);
    }

    private final func UnregisterForControlLossInitialDelay() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.controlLossInitialDelayID);
    }

    private final func UnregisterForControlLossPreStart() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.controlLossPreStartDelayID);
    }

    private final func UnregisterForControlLossStart() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.controlLossStartDelayID);
    }

    private final func UnregisterForControlLossFinish() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.controlLossFinishDelayID);
    }

    //
	//  Debug
	//
	private final func OnImpairedDrivingDebugFactSet(value: Int32) -> Void {
		//DFLogNoSystem(DFSystemlessDebugEnabled(), this, "~~~~~~~~~ Fact: " + ToString(IntEnum<DFImpairedDrivingDebugFactID>(value)));
	}

    private final func OnImpairedDrivingVFXDebugFactSet(value: Int32) -> Void {
		DFLogNoSystem(DFSystemlessDebugEnabled(), this, "~~~~~~~~~ Fact: Value: " + ToString(value) + ", ID: " + ToString(IntEnum<DFImpairedDrivingVFXDebugFactID>(value)));
	}

    //
    //  Tutorial
    //
    private final func ShowImpairedDrivingTutorialPopup() -> Void {

    }
}
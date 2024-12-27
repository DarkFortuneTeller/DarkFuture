// -----------------------------------------------------------------------------
// DFVehicleSleepSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles sleeping in vehicles.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Services.{
	DFNotificationService,
	DFTutorial
}
import DarkFuture.Settings.{
    DFSettings,
    SettingChangedEvent,
	DFRoadDetectionToleranceSetting
}

public enum DFCanPlayerSleepInVehicleResult {
	No_SystemDisabled = 0,
	No_Generic = 1,
	No_Moving = 2,
	No_InRoad = 3,
	Yes = 4
}

public enum EnhancedVehicleSystemCompatPowerBehaviorDriver {
	DoNothing = 0,
	TurnOff = 1,
	TurnOn = 2
}

public enum EnhancedVehicleSystemCompatPowerBehaviorPassenger {
	DoNothing = 0,
	SameAsDriver = 1
}

//
//	Input Event Registration
//
@addField(PlayerPuppet)
private let m_DarkFutureInputListener: ref<DarkFutureInputListener>;

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    let r: Bool = wrappedMethod();

    this.UnregisterInputListener(this.m_DarkFutureInputListener);
    this.m_DarkFutureInputListener = null;

	return r;
}

public class DarkFutureInputListener {
	protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
		if Equals(ListenerAction.GetName(action), n"DFVehicleSleepAction") && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_HOLD_COMPLETE) {
			DFVehicleSleepSystem.Get().SleepInVehicle();
		}

		return true;
	}
}

@addField(InputContextTransitionEvents)
private let m_oldSleepInVehicleAllowedState: Bool = false;

@addField(InputContextTransitionEvents)
private let m_newSleepInVehicleAllowedState: Bool = false;

@addField(InputContextTransitionEvents)
private let sleepInVehicleShowInputHintDebounceDelayID: DelayID;

@addField(InputContextTransitionEvents)
private let sleepInVehicleShowInputHintDebounceDelayInterval: Float = 0.3;

@addField(InputContextTransitionEvents)
private let sleepInVehicleInputHintToShow: Bool = false;

@addMethod(InputContextTransitionEvents)
protected final func DarkFutureForceRefreshInputHints(stateContext: ref<StateContext>) -> Void {
    stateContext.SetTemporaryBoolParameter(n"ForceRefreshInputHints", true, true);
}

@wrapMethod(VehicleDriverContextEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(VehicleDriverCombatContextEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(VehiclePassengerContextEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(stateContext, scriptInterface);
}

@addMethod(InputContextTransitionEvents)
protected final func DarkFutureReconcileInputHints(stateContext: ref<StateContext>) -> Void {
	let DFVSS = DFVehicleSleepSystem.Get();
	this.m_newSleepInVehicleAllowedState = DFVSS.ShouldShowSleepInVehicleInputHint();

    if NotEquals(this.m_oldSleepInVehicleAllowedState, this.m_newSleepInVehicleAllowedState) {
		this.m_oldSleepInVehicleAllowedState = this.m_newSleepInVehicleAllowedState;
		this.RegisterSleepInVehicleShowInputHintDebounceDelay(stateContext);
    }
}

@addMethod(InputContextTransitionEvents)
protected final func RegisterSleepInVehicleShowInputHintDebounceDelay(stateContext: ref<StateContext>) -> Void {
	RegisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), SleepInVehicleShowInputHintDebounceDelay.Create(this, stateContext), this.sleepInVehicleShowInputHintDebounceDelayID, this.sleepInVehicleShowInputHintDebounceDelayInterval, true);
}

@addMethod(InputContextTransitionEvents)
protected final func OnSleepInVehicleShowInputHintDebounceCallback(stateContext: ref<StateContext>) -> Void {
	this.DarkFutureForceRefreshInputHints(stateContext);
}

@wrapMethod(VehicleDriverContextEvents)
protected final func OnUpdate(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(timeDelta, stateContext, scriptInterface);
}

@wrapMethod(VehiclePassengerContextEvents)
protected final func OnUpdate(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(timeDelta, stateContext, scriptInterface);
}

@wrapMethod(VehicleDriverCombatContextEvents)
protected final func OnUpdate(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    this.DarkFutureReconcileInputHints(stateContext);
    wrappedMethod(timeDelta, stateContext, scriptInterface);
}

@wrapMethod(VehicleObject)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {		
		this.HandleDarkFutureVehicleMounted();
	}

	return r;
}

@addMethod(VehicleObject)
private final func HandleDarkFutureVehicleMounted() -> Void {
	let DFVSS: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	DFVSS.SetPreventionStrategyPreCheckRequestsOnMount();
	DFVSS.RegisterVehicleSleepActionListener();
}

@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		if IsDefined(mountChild) && mountChild.IsPlayer() {
			let DFVSS: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
			DFVSS.SetPreventionStrategyPreCheckRequestsOnMount();
			DFVSS.UnregisterVehicleSleepActionListener();
		}
	}
	
	return r;
}

@wrapMethod(VehicleComponent)
protected cb func OnVehicleFinishedMountingEvent(evt: ref<VehicleFinishedMountingEvent>) -> Bool {
	let r = wrappedMethod(evt);

	let mountChild: wref<GameObject> = evt.character;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		DFVehicleSleepSystem.Get().TryToShowTutorial();
	}
	
	return r;
}

@addMethod(InputContextTransitionEvents)
private final func DarkFutureEvaluateVehicleSleepInputHint(show: Bool, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>, source: CName) -> Void {
	if DFSettings.Get().showSleepingInVehiclesInputHint && show {
		this.ShowInputHint(scriptInterface, n"DFVehicleSleepAction", source, GetLocalizedTextByKey(n"DarkFutureInputHintSleepVehicle"), inkInputHintHoldIndicationType.Hold, true, 127);
	} else {
		this.RemoveInputHint(scriptInterface, n"DFVehicleSleepAction", source);
	}
}

@wrapMethod(InputContextTransitionEvents)
protected final const func ShowVehicleDriverInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	let VehicleSleepSystem: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	this.DarkFutureEvaluateVehicleSleepInputHint(VehicleSleepSystem.ShouldShowSleepInVehicleInputHint(), stateContext, scriptInterface, n"VehicleDriver");

	wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(InputContextTransitionEvents)
protected final const func ShowVehiclePassengerInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {	
	let VehicleSleepSystem: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	this.DarkFutureEvaluateVehicleSleepInputHint(VehicleSleepSystem.ShouldShowSleepInVehicleInputHint(), stateContext, scriptInterface, n"VehiclePassenger");
  
  	wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(VehicleEventsTransition)
protected final func HandleCameraInput(scriptInterface: ref<StateGameScriptInterface>) -> Void {
	if IsSystemEnabledAndRunning(DFVehicleSleepSystem.Get()) {
		if scriptInterface.IsActionJustTapped(n"ToggleVehCamera") && !this.IsVehicleCameraChangeBlocked(scriptInterface) {
			this.RequestToggleVehicleCamera(scriptInterface);
		};
	} else {
		wrappedMethod(scriptInterface);
	}
}

@replaceMethod(PreventionSystem)
private final func UpdateStrategyPreCheckRequests() -> Void {
	// Setting Strategy Pre-Check Requests allows GetNearestRoadFromPlayerInfo() to return valid road data,
	// which is necessary to determine the player's distance from a road or highway.
	//
	// These pre-check requests are ordinarily set when Heat is >= 1, and cleared when the player's Heat Stage is 0,
	// presumably for efficiency's sake, they likely have a computation cost associated with them. That said,
	// the game doesn't appear to have issues when these are set for long periods in practice. The player could
	// also remain Wanted for long periods, so I assume this was done as good optimization practice (especially
	// for consoles) and not due to a hard technical requirement.
	//
	// We should set Strategy Pre-Check Requests when the player is mounted to a vehicle or when being
	// pursued by the NCPD. It should only be cleared if the player is not being chased AND the player
	// is not mounted to a vehicle.

    let preCheckRequests: array<ref<BaseStrategyRequest>>;
	let vehicleObj: wref<VehicleObject>;
	VehicleComponent.GetVehicle(GetGameInstance(), this.m_player, vehicleObj);

    let isChasingPlayer: Bool = this.IsChasingPlayer();
    if !isChasingPlayer && !IsDefined(vehicleObj) {
    	GameInstance.GetPreventionSpawnSystem(this.GetGame()).ClearStrategyPreCheckRequests();
    };
    
	if this.IsChasingPlayer() || IsDefined(vehicleObj) || !IsFinal() {
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.DriveTowardsPlayer));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.DriveAwayFromPlayer));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.PatrolNearby));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.InterceptAtNextIntersection));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.GetToPlayerFromAnywhere));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.InitialSearch));
		ArrayPush(preCheckRequests, this.CreateStrategyRequest(vehiclePoliceStrategy.SearchFromAnywhere));
		GameInstance.GetPreventionSpawnSystem(this.GetGame()).SetStrategyPreCheckRequests(preCheckRequests);
    };
}

//
// Registration
//
public class SleepInVehicleCameraChangeDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleCameraChangeDelay> = new SleepInVehicleCameraChangeDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleCameraChangeDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.SleepInVehicleStage2();
	}
}

public class SleepInVehicleEnginePowerChangeDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleEnginePowerChangeDelay> = new SleepInVehicleEnginePowerChangeDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleEnginePowerChangeDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.SleepInVehicleStage3();
	}
}

public class SleepInVehicleEnginePowerChangeWakeUpDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleEnginePowerChangeWakeUpDelay> = new SleepInVehicleEnginePowerChangeWakeUpDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleEnginePowerChangeWakeUpFPPDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.OnSleepInVehicleEnginePowerChangeWakeUpFPPCallback();
	}
}

public class SleepInVehicleVFXDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleVFXDelay> = new SleepInVehicleVFXDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleVFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.SleepInVehicleStage4();
	}
}

public class SleepInVehicleShowTimeSkipDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleShowTimeSkipDelay> = new SleepInVehicleShowTimeSkipDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleShowTimeSkipDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.OnSleepInVehicleShowTimeSkipCallback();
	}
}

public class SleepInVehicleFadeUpDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleFadeUpDelay> = new SleepInVehicleFadeUpDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleFadeUpDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.OnSleepInVehicleFadeUpCallback();
	}
}

public class SleepInVehicleFinishDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleFinishDelay> = new SleepInVehicleFinishDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSleepSystem.sleepInVehicleFinishDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSleepSystem.SleepInVehicleStage5();
	}
}

public class SleepInVehicleShowInputHintDebounceDelay extends DFDelayCallback {
	public let InputContextTransitionEvents: wref<InputContextTransitionEvents>;
	public let StateContext: wref<StateContext>;

	public static func Create(InputContextTransitionEvents: wref<InputContextTransitionEvents>, StateContext: wref<StateContext>) -> ref<DFDelayCallback> {
		let self: ref<SleepInVehicleShowInputHintDebounceDelay> = new SleepInVehicleShowInputHintDebounceDelay();
		self.InputContextTransitionEvents = InputContextTransitionEvents;
		self.StateContext = StateContext;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.InputContextTransitionEvents.sleepInVehicleShowInputHintDebounceDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.InputContextTransitionEvents.OnSleepInVehicleShowInputHintDebounceCallback(this.StateContext);
	}
}

//
// Classes
//
class DFVehicleSleepSystemEventListener extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFVehicleSleepSystem> {
		return DFVehicleSleepSystem.Get();
	}
}

public final class DFVehicleSleepSystem extends DFSystem {
	private persistent let hasShownVehicleSleepTutorial: Bool = false;

	private const let roadDetectionTolerance_Curb: Float = 3.1;
	private const let roadDetectionTolerance_Roadside: Float = 4.1;
	private const let roadDetectionTolerance_Secluded: Float = 12.0;

	private let PreventionSpawnSystem: ref<PreventionSpawnSystem>;
	private let RandomEncounterSystem: ref<DFRandomEncounterSystem>;
	private let NotificationService: ref<DFNotificationService>;

	private let isSleepingInVehicle: Bool = false;
	private let shouldRestoreRadioAfterSleep: Bool = false;

	private let sleepInVehicleCameraChangeDelayID: DelayID;
	private let sleepInVehicleEnginePowerChangeDelayID: DelayID;
	private let sleepInVehicleVFXDelayID: DelayID;
	private let sleepInVehicleShowTimeSkipDelayID: DelayID;
	private let sleepInVehicleFadeUpDelayID: DelayID;
	private let sleepInVehicleEnginePowerChangeWakeUpFPPDelayID: DelayID;
	private let sleepInVehicleFinishDelayID: DelayID;

	private let sleepInVehicleCameraChangeDelayInterval: Float = 1.0;
	private let sleepInVehicleEnginePowerChangeDelayInterval: Float = 1.5;
	private let sleepInVehicleVFXDelayInterval: Float = 1.0;
	private let sleepInVehicleShowTimeSkipDelayInterval: Float = 2.5;
	private let sleepInVehicleFadeUpDelayInterval: Float = 3.2;
	private let sleepInVehicleEnginePowerChangeWakeUpFPPDelayInterval: Float = 2.1;
	private let sleepInVehicleFinishDelayInterval: Float = 3.0;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFVehicleSleepSystem> {
		let instance: ref<DFVehicleSleepSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Gameplay.DFVehicleSleepSystem") as DFVehicleSleepSystem;
		return instance;
	}

    public final static func Get() -> ref<DFVehicleSleepSystem> {
        return DFVehicleSleepSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private func SetupData() -> Void {}

	private final func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.allowSleepingInVehicles;
    }

    private final func GetSystemToggleSettingString() -> String {
        return "allowSleepingInVehicles";
    }

	private func DoPostSuspendActions() -> Void {}
	private func DoPostResumeActions() -> Void {}
	private func DoStopActions() -> Void {}

	private func GetSystems() -> Void {
		let gameInstance = GetGameInstance();
		this.PreventionSpawnSystem = GameInstance.GetPreventionSpawnSystem(gameInstance);
		this.RandomEncounterSystem = DFRandomEncounterSystem.GetInstance(gameInstance);
		this.NotificationService = DFNotificationService.GetInstance(gameInstance);
	}

	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	
	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), attachedPlayer, vehicleObj);
		if IsDefined(vehicleObj) {
			// The player loaded a save game or started Dark Future while mounted to a vehicle.
			vehicleObj.HandleDarkFutureVehicleMounted();
		}
	}
	
	private func UnregisterListeners() -> Void {}
	private func UnregisterAllDelayCallbacks() -> Void {}
	public func OnTimeSkipStart() -> Void {}

	public func OnTimeSkipCancelled() -> Void {
		if this.isSleepingInVehicle {
			this.RandomEncounterSystem.ClearRandomEncounter();
			this.RegisterSleepInVehicleFadeUp();
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		if this.isSleepingInVehicle {
			let spawnedEncounter: Bool = this.RandomEncounterSystem.TryToSpawnRandomEncounterAroundPlayer();

			if spawnedEncounter {
				this.ExitSleepFast();
			} else {
				this.RegisterSleepInVehicleFadeUp();
			}
		}
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

	//
	//	System-Specific Methods
	//
	public final func GetSleepingInVehicle() -> Bool {
		return this.isSleepingInVehicle;
	}

	public final func RegisterVehicleSleepActionListener() -> Void {
		this.player.m_DarkFutureInputListener = new DarkFutureInputListener();
    	this.player.RegisterInputListener(this.player.m_DarkFutureInputListener);
	}

	public final func UnregisterVehicleSleepActionListener() -> Void {
		this.player.UnregisterInputListener(this, n"DFVehicleSleepAction");
		this.player.m_DarkFutureInputListener = null;
	}

	private func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialSleepingInVehiclesTitle";
	}

	private func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialSleepingInVehicles";
	}

	private func GetHasShownTutorial() -> Bool {
		return this.hasShownVehicleSleepTutorial;
	}

	private func SetHasShownTutorial(hasShownVehicleSleepTutorial: Bool) -> Void {
		this.hasShownVehicleSleepTutorial = hasShownVehicleSleepTutorial;
	}

	public final func ShouldShowSleepInVehicleInputHint() -> Bool {
		// If Dark Future is not running or this feature is disabled, bail out early.
		if !IsSystemEnabledAndRunning(this) { return false; }

		let blockSleepInVehicleInputHint: Bool = false;

		let psmVehicle: gamePSMVehicle;
		let securityData: SecurityAreaData;
		let timeSystem: ref<TimeSystem>;

		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
		let vehiclePS: wref<VehicleComponentPS> = vehicleObj.GetVehiclePS();
		let vehicle: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();
		let isBike = vehicleObj == (vehicleObj as BikeObject);

		let gameInstance = GetGameInstance();
		let tier: Int32 = this.player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.HighLevel);
		let psmBlackboard: ref<IBlackboard> = this.player.GetPlayerStateMachineBlackboard();
		
		let variantData: Variant = psmBlackboard.GetVariant(GetAllBlackboardDefs().PlayerStateMachine.SecurityZoneData);
		if IsDefined(variantData) {
			securityData = FromVariant<SecurityAreaData>(variantData);
		};

		psmVehicle = IntEnum<gamePSMVehicle>(psmBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Vehicle));

		blockSleepInVehicleInputHint = 
			/* Default Time Skip Conditions */
			psmBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 || 						// Combat
			StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoTimeSkip") || 						// Time Skip disabled
			timeSystem.IsPausedState() || 																		// Game paused
			Equals(psmVehicle, gamePSMVehicle.Transition) ||													// Transitioning into / out of vehicle
			(tier >= 3 && tier <= 5) || 																		// Scene tier
			securityData.securityAreaType > ESecurityAreaType.SAFE || 											// Unsafe area
			GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive() ||									// Phone call
			psmBlackboard.GetBool(GetAllBlackboardDefs().PlayerStateMachine.IsInLoreAnimationScene) || 			// Lore animation (?)
			this.player.GetPreventionSystem().IsChasingPlayer() || 												// Pursued by NCPD
			HubMenuUtility.IsPlayerHardwareDisabled(this.player) ||												// Player Cyberware disabled

			/* Vehicle Sleeping Specific Conditions */
			this.IsPlayerSleepingInVehicle() ||																	// Already sleeping in vehicle
			this.IsPlayerInRoad() ||																			// In the middle of a road or highway
			isBike ||																							// Motorcycle
			vehicle.m_damageLevel == 3 ||																		// Impending vehicle destruction
			vehiclePS.GetIsSubmerged() ||																		// Vehicle in water
			vehicleObj.IsFlippedOver() ||																		// Vehicle flipped over
			vehicleObj.IsQuest() ||																				// Quest vehicle
			GameInstance.GetRacingSystem(gameInstance).IsRaceInProgress();										// Race in progress

		return !blockSleepInVehicleInputHint;
	}

	public final func CanPlayerSleepInVehicle() -> DFCanPlayerSleepInVehicleResult {
		// Vehicle Sleeping specific variant of CanPlayerTimeSkip(), with stronger typing.
		
		// If Dark Future is not running or this feature is disabled, bail out early.
		if !IsSystemEnabledAndRunning(this) { return DFCanPlayerSleepInVehicleResult.No_SystemDisabled; }

		let blockSleepInVehicleGenericReason: Bool = false;
		let blockSleepInVehicleMovingReason: Bool = false;
		let blockSleepInVehicleInRoadReason: Bool = false;

		let psmVehicle: gamePSMVehicle;
		let securityData: SecurityAreaData;
		let timeSystem: ref<TimeSystem>;

		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
		let vehiclePS: wref<VehicleComponentPS> = vehicleObj.GetVehiclePS();
		let vehicle: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();
		let isBike = vehicleObj == (vehicleObj as BikeObject);

		let gameInstance = GetGameInstance();
		let vehicleSpeed: Float = VehicleComponent.GetOwnerVehicleSpeed(gameInstance, this.player);
		let tier: Int32 = this.player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.HighLevel);
		let psmBlackboard: ref<IBlackboard> = this.player.GetPlayerStateMachineBlackboard();
		
		let variantData: Variant = psmBlackboard.GetVariant(GetAllBlackboardDefs().PlayerStateMachine.SecurityZoneData);
		if IsDefined(variantData) {
			securityData = FromVariant<SecurityAreaData>(variantData);
		};

		psmVehicle = IntEnum<gamePSMVehicle>(psmBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Vehicle));

		blockSleepInVehicleGenericReason = 
			/* Generic "Action Blocked" conditions */
			psmBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 || 						// Combat
			StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoTimeSkip") || 						// Time Skip disabled
			timeSystem.IsPausedState() || 																		// Game paused
			Equals(psmVehicle, gamePSMVehicle.Transition) ||													// Transitioning into / out of vehicle
			(tier >= 3 && tier <= 5) || 																		// Scene tier
			securityData.securityAreaType > ESecurityAreaType.SAFE || 											// Unsafe area
			GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive() ||									// Phone call
			psmBlackboard.GetBool(GetAllBlackboardDefs().PlayerStateMachine.IsInLoreAnimationScene) || 			// Lore animation (?)
			this.player.GetPreventionSystem().IsChasingPlayer() || 												// Pursued by NCPD
			HubMenuUtility.IsPlayerHardwareDisabled(this.player) ||												// Player Cyberware disabled
			this.isSleepingInVehicle ||																			// Already sleeping in vehicle
			isBike ||																							// Motorcycle
			vehicle.m_damageLevel == 3 ||																		// Impending vehicle destruction
			vehiclePS.GetIsSubmerged() ||																		// Vehicle in water
			vehicleObj.IsFlippedOver() ||																		// Vehicle flipped over
			vehicleObj.IsQuest() ||																				// Quest vehicle
			GameInstance.GetRacingSystem(gameInstance).IsRaceInProgress();										// Race in progress

		blockSleepInVehicleMovingReason = (vehicleSpeed > 0.1 || vehicleSpeed < -0.1);							// Vehicle moving
		blockSleepInVehicleInRoadReason = this.IsPlayerInRoad();												// In the middle of a road or highway

		if blockSleepInVehicleGenericReason {
			return DFCanPlayerSleepInVehicleResult.No_Generic;
		} else if blockSleepInVehicleInRoadReason {
			return DFCanPlayerSleepInVehicleResult.No_InRoad;
		} else if blockSleepInVehicleMovingReason {
			return DFCanPlayerSleepInVehicleResult.No_Moving;
		}
		
		return DFCanPlayerSleepInVehicleResult.Yes;
	}

	public final func SleepInVehicle() -> Void {
		let canSleep: DFCanPlayerSleepInVehicleResult = this.CanPlayerSleepInVehicle();

		if Equals(canSleep, DFCanPlayerSleepInVehicleResult.Yes) {
			this.isSleepingInVehicle = true;

			// Pre-calculate any random encounters.
			this.RandomEncounterSystem.SetupRandomEncounterOnSleep();

			let pocketRadio: ref<PocketRadio> = this.player.GetPocketRadio();
			if pocketRadio.IsActive() {
				this.shouldRestoreRadioAfterSleep = true;
				this.SendRadioEvent(false, false, -1);
			}

			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureGameplayRestriction.SleepInVehicle");
			

			let vehicleObj: wref<VehicleObject>;
			VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
			let perspective: vehicleCameraPerspective = vehicleObj.GetCameraManager().GetActivePerspective();

			if this.Settings.forceFPPWhenSleepingInVehicle && NotEquals(perspective, vehicleCameraPerspective.FPP) {
				// Switch to FPP and wait for camera to finish moving.
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureGameplayRestriction.SleepInVehicleFPP");
				this.RegisterSleepInVehicleCameraChangeDelay();
			} else {
				// Continue.
				this.SleepInVehicleStage2();
			}
		} else {
			this.ShowActionBlockedNotification(canSleep);
		}
	}

	public final func SleepInVehicleStage2() -> Void {
		let enginePowerChangeMade: Bool = false;

		// EVS Compatibility - Optionally change vehicle state.
		if VehicleComponent.IsDriver(GetGameInstance(), this.player) || Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger, EnhancedVehicleSystemCompatPowerBehaviorPassenger.SameAsDriver) {
			if Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorOnSleep, EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOff) {
				enginePowerChangeMade = this.TryToToggleEngineAndPowerStateViaEVS(false);
			} else if Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorOnSleep, EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOn) {
				enginePowerChangeMade = this.TryToToggleEngineAndPowerStateViaEVS(true);
			}
		}

		if enginePowerChangeMade {
			this.RegisterSleepInVehicleEnginePowerChangeDelay();
		} else {
			this.SleepInVehicleStage3();
		}
	}

	public final func SleepInVehicleStage3() -> Void {
		// SFX
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"q001_sc_01_v_wakes_up";
		this.player.QueueEvent(evt);
		
		this.RegisterSleepInVehicleVFXDelay();
	}

	public final func SleepInVehicleStage4() -> Void {
		// VFX
		GameObjectEffectHelper.StartEffectEvent(this.player, n"eyes_closing_slow", false, null, false);

		this.RegisterSleepInVehicleShowTimeSkip();
	}

	public final func OnSleepInVehicleShowTimeSkipCallback() -> Void {
		// As a sanity check, make sure a combat encounter hasn't broken out right before sleeping.
		// If so, bail out.
		let canSleep: Bool = !this.player.IsInCombat();
		if canSleep {
			// Show the time skip wheel, and tell the system that you are sleeping in a vehicle.
			let menuEvent: ref<inkMenuInstance_SpawnEvent> = new inkMenuInstance_SpawnEvent();
			menuEvent.Init(n"OnOpenTimeSkip");
			GameInstance.GetUISystem(GetGameInstance()).QueueEvent(menuEvent);
		
		} else {
			this.ExitSleepFast();
		}

		// TimeSkip Cancel or Finish will register for Fade Up.
	}

	public final func OnSleepInVehicleFadeUpCallback() -> Void {
		// Fade up from black
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"eyes_closing_slow");
		GameObjectEffectHelper.StartEffectEvent(this.player, n"waking_up", false, null, true);

		this.RegisterSleepInVehicleEnginePowerChangeWakeUpFPPDelay();
	}

	public final func OnSleepInVehicleEnginePowerChangeWakeUpFPPCallback(opt fast: Bool) -> Void {
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
		let perspective: vehicleCameraPerspective = vehicleObj.GetCameraManager().GetActivePerspective();

		let enginePowerChangeMade: Bool = false;
		if VehicleComponent.IsDriver(GetGameInstance(), this.player) || Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger, EnhancedVehicleSystemCompatPowerBehaviorPassenger.SameAsDriver) {
			if Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorOnWake, EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOff) {
				enginePowerChangeMade = this.TryToToggleEngineAndPowerStateViaEVS(false);
			} else if Equals(this.Settings.compatibilityEnhancedVehicleSystemPowerBehaviorOnWake, EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOn) {
				enginePowerChangeMade = this.TryToToggleEngineAndPowerStateViaEVS(true);
			}
		}

		// If in FPP, and EVS caused a vehicle state change, wait for that to occur before continuing.
		if Equals(perspective, vehicleCameraPerspective.FPP) && enginePowerChangeMade && !fast {
			this.RegisterSleepInVehicleFinish();
		} else {
			this.SleepInVehicleStage5();
		}
	}

	public final func SleepInVehicleStage5() -> Void {
		if this.shouldRestoreRadioAfterSleep {
			this.shouldRestoreRadioAfterSleep = false;
			this.SendRadioEvent(true, false, 0);
		}
		
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureGameplayRestriction.SleepInVehicle");
		StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureGameplayRestriction.SleepInVehicleFPP");
		this.isSleepingInVehicle = false;
	}

	private final func ExitSleepFast() -> Void {
		// For use when combat occurs.
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"eyes_closing_slow");
		this.OnSleepInVehicleEnginePowerChangeWakeUpFPPCallback(true);
	}

	public final func TryToShowTutorial() -> Void {
        if RunGuard(this) { return; }

        if this.Settings.tutorialsEnabled && !this.GetHasShownTutorial() {
			this.SetHasShownTutorial(true);
			let tutorial: DFTutorial;
			tutorial.title = GetLocalizedTextByKey(this.GetTutorialTitleKey());
			tutorial.message = GetLocalizedTextByKey(this.GetTutorialMessageKey());
			tutorial.iconID = t"";
			this.NotificationService.QueueTutorial(tutorial);
		}
	}

	private final func ShowActionBlockedNotification(reason: DFCanPlayerSleepInVehicleResult) -> Void {
		let UISystem = GameInstance.GetUISystem(GetGameInstance());
		let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
		UISystem.QueueEvent(new UIInGameNotificationRemoveEvent());
		if Equals(reason, DFCanPlayerSleepInVehicleResult.No_Generic) {
			notificationEvent.m_notificationType = UIInGameNotificationType.ActionRestriction;
		} else if Equals(reason, DFCanPlayerSleepInVehicleResult.No_Moving) {
			notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        	notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureSleepingInVehicleErrorMoving");
		} else if Equals(reason, DFCanPlayerSleepInVehicleResult.No_InRoad) {
			if Equals(this.Settings.sleepingInVehiclesRoadDetectionToleranceSetting, DFRoadDetectionToleranceSetting.Secluded) {
				notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        		notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureSleepingInVehicleErrorInRoadFar");
			} else {
				notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        		notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureSleepingInVehicleErrorInRoad");
			}
		}

		UISystem.QueueEvent(notificationEvent);
	}

	//
	//	Registration
	//
	private final func RegisterSleepInVehicleCameraChangeDelay() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleCameraChangeDelay.Create(this), this.sleepInVehicleCameraChangeDelayID, this.sleepInVehicleCameraChangeDelayInterval);
	}

	private final func RegisterSleepInVehicleEnginePowerChangeDelay() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleEnginePowerChangeDelay.Create(this), this.sleepInVehicleEnginePowerChangeDelayID, this.sleepInVehicleEnginePowerChangeDelayInterval);
	}

	private final func RegisterSleepInVehicleVFXDelay() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleVFXDelay.Create(this), this.sleepInVehicleVFXDelayID, this.sleepInVehicleVFXDelayInterval);
	}

	private final func RegisterSleepInVehicleShowTimeSkip() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleShowTimeSkipDelay.Create(this), this.sleepInVehicleShowTimeSkipDelayID, this.sleepInVehicleShowTimeSkipDelayInterval);
	}

	private final func RegisterSleepInVehicleFadeUp() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleFadeUpDelay.Create(this), this.sleepInVehicleFadeUpDelayID, this.sleepInVehicleFadeUpDelayInterval);
	}

	private final func RegisterSleepInVehicleEnginePowerChangeWakeUpFPPDelay() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleEnginePowerChangeWakeUpDelay.Create(this), this.sleepInVehicleEnginePowerChangeWakeUpFPPDelayID, this.sleepInVehicleEnginePowerChangeWakeUpFPPDelayInterval);
	}

	private final func RegisterSleepInVehicleFinish() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleFinishDelay.Create(this), this.sleepInVehicleFinishDelayID, this.sleepInVehicleFinishDelayInterval);
	}

	public final func SetPreventionStrategyPreCheckRequestsOnMount() -> Void {
		this.player.GetPreventionSystem().UpdateStrategyPreCheckRequests();
	}

	private final func IsPlayerSleepingInVehicle() -> Bool {
		return this.isSleepingInVehicle;
	}

	private final func GetRoadDetectionToleranceFromSetting(setting: DFRoadDetectionToleranceSetting) -> Float {
		switch setting {
			case DFRoadDetectionToleranceSetting.Curb:
				return this.roadDetectionTolerance_Curb;
				break;
			case DFRoadDetectionToleranceSetting.Roadside:
				return this.roadDetectionTolerance_Roadside;
				break;
			case DFRoadDetectionToleranceSetting.Secluded:
				return this.roadDetectionTolerance_Secluded;
				break;
		}
	}

	private final func IsPlayerInRoad() -> Bool {
		let roadInfo: NearestRoadFromPlayerInfo;
		this.PreventionSpawnSystem.GetNearestRoadFromPlayerInfo(roadInfo);

		return roadInfo.pathLength < this.GetRoadDetectionToleranceFromSetting(this.Settings.sleepingInVehiclesRoadDetectionToleranceSetting);
	}

	public final func SendRadioEvent(toggle: Bool, setStation: Bool, stationIndex: Int32) -> Void {
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);

		if IsDefined(vehicleObj) {
			let vehRadioEvent: ref<VehicleRadioEvent> = new VehicleRadioEvent();
			vehRadioEvent.toggle = toggle;
			vehRadioEvent.setStation = setStation;
			vehRadioEvent.station = stationIndex >= 0 ? EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(stationIndex)) : -1;
			this.player.QueueEventForEntityID(vehicleObj.GetEntityID(), vehRadioEvent);
			this.player.QueueEvent(vehRadioEvent);
		}
	}

	@if(!ModuleExists("Hgyi56.Enhanced_Vehicle_System"))
	private final func TryToToggleEngineAndPowerStateViaEVS(toggle: Bool) -> Bool {
		return false;
	}

	@if(ModuleExists("Hgyi56.Enhanced_Vehicle_System"))
	private final func TryToToggleEngineAndPowerStateViaEVS(toggle: Bool) -> Bool {
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
		let vehicle: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();

		vehicle.hgyi56_EVS_TogglePowerState(toggle);
		vehicle.hgyi56_EVS_ToggleEngineState(toggle);
		return true;
	}
}

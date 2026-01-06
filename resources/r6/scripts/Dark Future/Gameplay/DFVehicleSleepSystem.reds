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
import DarkFuture.Utils.DFRunGuard
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Services.{
	DFNotificationService,
	DFTutorial,
	DFGameStateService
}
import DarkFuture.Settings.{
    DFSettings,
    SettingChangedEvent
}
import DarkFuture.Conditions.{
	DFHumanityLossConditionSystem,
	DFHumanityLossRestorationActivityType
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
public let m_DarkFutureInputListener: ref<DarkFutureInputListener>;

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
	//DFProfile();
    let r: Bool = wrappedMethod();

    this.UnregisterInputListener(this.m_DarkFutureInputListener);
    this.m_DarkFutureInputListener = null;

	return r;
}

public class DarkFutureInputListener {
	protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
		if Equals(ListenerAction.GetName(action), n"DFVehicleSleepAction") && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_HOLD_COMPLETE) {
			//DFProfile();
			DFVehicleSleepSystem.Get().SleepInVehicle();
		}
	}
}

@wrapMethod(VehicleObject)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {		
		this.HandleDarkFutureVehicleMounted();
	}

	return r;
}

@addMethod(VehicleObject)
public final func HandleDarkFutureVehicleMounted() -> Void {
	//DFProfile();
	let DFVSS: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	DFVSS.RegisterVehicleSleepActionListener();
}

@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		let DFVSS: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
		DFVSS.UnregisterVehicleSleepActionListener();
	}
	
	return r;
}

@wrapMethod(VehicleComponent)
protected cb func OnVehicleFinishedMountingEvent(evt: ref<VehicleFinishedMountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: wref<GameObject> = evt.character;
	if IsDefined(mountChild) && mountChild.IsPlayer() {
		let DFVSS: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
		if Equals(DFVSS.CanPlayerSleepInVehicle(true), DFCanPlayerSleepInVehicleResult.Yes) {
			DFVSS.TryToShowTutorial();
		}
	}
	
	return r;
}

@addMethod(InputContextTransitionEvents)
private final func DarkFutureEvaluateVehicleSleepInputHint(show: Bool, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>, source: CName) -> Void {
	//DFProfile();
	if DFSettings.Get().showSleepingInVehiclesInputHint && show {
		this.ShowInputHint(scriptInterface, n"DFVehicleSleepAction", source, GetLocalizedTextByKey(n"DarkFutureInputHintSleepVehicle"), inkInputHintHoldIndicationType.Hold, true, 127);
	} else {
		this.RemoveInputHint(scriptInterface, n"DFVehicleSleepAction", source);
	}
}

@wrapMethod(InputContextTransitionEvents)
protected final const func ShowVehicleDriverInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	//DFProfile();
	//let VehicleSleepSystem: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	this.DarkFutureEvaluateVehicleSleepInputHint(true, stateContext, scriptInterface, n"VehicleDriver");

	wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(InputContextTransitionEvents)
protected final const func RemoveVehicleDriverInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	//DFProfile();
	this.DarkFutureEvaluateVehicleSleepInputHint(false, stateContext, scriptInterface, n"VehicleDriver");

	wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(InputContextTransitionEvents)
protected final const func ShowVehiclePassengerInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {	
	//DFProfile();
	//let VehicleSleepSystem: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	this.DarkFutureEvaluateVehicleSleepInputHint(true, stateContext, scriptInterface, n"VehiclePassenger");
  
  	wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(InputContextTransitionEvents)
protected final const func RemoveVehiclePassengerInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	//DFProfile();
	//let VehicleSleepSystem: ref<DFVehicleSleepSystem> = DFVehicleSleepSystem.Get();
	this.DarkFutureEvaluateVehicleSleepInputHint(false, stateContext, scriptInterface, n"VehiclePassenger");
  
  	wrappedMethod(stateContext, scriptInterface);
}

@replaceMethod(VehicleEventsTransition)
protected final func HandleCameraInput(scriptInterface: ref<StateGameScriptInterface>) -> Void {
	// Dark Future 2.0 - Optimize this function (called every frame) to always have new input behavior regardless of system state.
	if scriptInterface.IsActionJustTapped(n"ToggleVehCamera") && !this.IsVehicleCameraChangeBlocked(scriptInterface) {
		this.RequestToggleVehicleCamera(scriptInterface);
	};
	if scriptInterface.IsActionJustHeld(n"HoldCinematicCamera") && !this.IsVehicleCameraChangeBlocked(scriptInterface) {
		this.RequestVehicleCinematicCamera(scriptInterface);
	};
}

//
// Registration
//
public class SleepInVehicleEnginePowerChangeDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<SleepInVehicleEnginePowerChangeDelay> = new SleepInVehicleEnginePowerChangeDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.DFVehicleSleepSystem.sleepInVehicleEnginePowerChangeDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.DFVehicleSleepSystem.SleepInVehicleStartQuestPhase();
	}
}

public class SleepInVehicleFinishDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create(DFVehicleSleepSystem: wref<DFVehicleSleepSystem>) -> ref<DFDelayCallback> {
		//DFProfile();
		let self: ref<SleepInVehicleFinishDelay> = new SleepInVehicleFinishDelay();
		self.DFVehicleSleepSystem = DFVehicleSleepSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		this.DFVehicleSleepSystem.sleepInVehicleFinishDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		this.DFVehicleSleepSystem.SleepInVehicleFinish();
	}
}

//
// Classes
//
class DFVehicleSleepSystemEventListener extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFVehicleSleepSystem> {
		//DFProfile();
		return DFVehicleSleepSystem.Get();
	}
}

public final class DFVehicleSleepSystem extends DFSystem {
	private persistent let hasShownVehicleSleepTutorial: Bool = false;

	private let QuestsSystem: ref<QuestsSystem>;
	private let AutoDriveSystem: ref<AutoDriveSystem>;
	private let RandomEncounterSystem: ref<DFRandomEncounterSystem>;
	private let GameStateService: ref<DFGameStateService>;
	private let NotificationService: ref<DFNotificationService>;
	
	private let shouldRestoreRadioAfterSleep: Bool = false;

	public let sleepInVehicleEnginePowerChangeDelayID: DelayID;
	public let sleepInVehicleFinishDelayID: DelayID;

	private let sleepInVehicleEnginePowerChangeDelayInterval: Float = 1.5;
	private let sleepInVehicleEnginePowerChangeFinishDelayInterval: Float = 3.0;

	private let sleepInVehicleActionListener: Uint32;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFVehicleSleepSystem> {
		//DFProfile();
		let instance: ref<DFVehicleSleepSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFVehicleSleepSystem>()) as DFVehicleSleepSystem;
		return instance;
	}

    public final static func Get() -> ref<DFVehicleSleepSystem> {
		//DFProfile();
        return DFVehicleSleepSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public func SetupData() -> Void {}

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

	public func DoPostSuspendActions() -> Void {}

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		this.UpdateSettingsFacts();
	}

	private func DoStopActions() -> Void {}

	public func GetSystems() -> Void {
		//DFProfile();
		let gameInstance = GetGameInstance();
		this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
		this.AutoDriveSystem = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<AutoDriveSystem>()) as AutoDriveSystem;
		this.RandomEncounterSystem = DFRandomEncounterSystem.GetInstance(gameInstance);
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
		this.NotificationService = DFNotificationService.GetInstance(gameInstance);
	}

	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

	private func RegisterListeners() -> Void {
		//DFProfile();
		this.sleepInVehicleActionListener = this.QuestsSystem.RegisterListener(n"df_fact_action_sleep_in_vehicle", this, n"OnSleepInVehicleActionFactChanged");
	}
	
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	
	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), attachedPlayer, vehicleObj);
		if IsDefined(vehicleObj) {
			// The player loaded a save game or started Dark Future while mounted to a vehicle.
			vehicleObj.HandleDarkFutureVehicleMounted();
		}
		this.UpdateSettingsFacts();
	}
	
	private func UnregisterListeners() -> Void {
		//DFProfile();
		this.QuestsSystem.UnregisterListener(n"df_fact_action_sleep_in_vehicle", this.sleepInVehicleActionListener);
        this.sleepInVehicleActionListener = 0u;
	}

	public func UnregisterAllDelayCallbacks() -> Void {}
	public func OnTimeSkipStart() -> Void {}

	public func OnTimeSkipCancelled() -> Void {
		//DFProfile();
		if this.GameStateService.GetSleepingInVehicle() {
			this.RandomEncounterSystem.ClearRandomEncounter();
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		//DFProfile();
		if this.GameStateService.GetSleepingInVehicle() {
			let encounterSpawned: Bool = this.RandomEncounterSystem.TryToSpawnRandomEncounterAroundPlayer();
			if !encounterSpawned {
				DFHumanityLossConditionSystem.Get().CheckShouldShowNomadLifePathHumanityLossRestoreChoice();
			}
		}
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		//DFProfile();
		if ArrayContains(changedSettings, "forceFPPWhenSleepingInVehicle") {
			this.UpdateSettingsFacts();
		}
	}

	//
	//	System-Specific Methods
	//
	private final func UpdateSettingsFacts() -> Void {
		//DFProfile();
		let factValue: Int32 = this.Settings.forceFPPWhenSleepingInVehicle ? 1 : 0;
		this.QuestsSystem.SetFact(n"df_fact_setting_force_fpp_when_sleeping_in_vehicle", factValue);
	}

	public final func RegisterVehicleSleepActionListener() -> Void {
		//DFProfile();
		this.player.m_DarkFutureInputListener = new DarkFutureInputListener();
    	this.player.RegisterInputListener(this.player.m_DarkFutureInputListener);
	}

	public final func UnregisterVehicleSleepActionListener() -> Void {
		//DFProfile();
		this.player.UnregisterInputListener(this, n"DFVehicleSleepAction");
		this.player.m_DarkFutureInputListener = null;
	}

	private func GetTutorialTitleKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialSleepingInVehiclesTitle";
	}

	private func GetTutorialMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialSleepingInVehicles";
	}

	private func GetHasShownTutorial() -> Bool {
		//DFProfile();
		return this.hasShownVehicleSleepTutorial;
	}

	private func SetHasShownTutorial(hasShownVehicleSleepTutorial: Bool) -> Void {
		//DFProfile();
		this.hasShownVehicleSleepTutorial = hasShownVehicleSleepTutorial;
	}

	private final func IsAnyPhoneStateActive() -> Bool {
		let lastPhoneCallInformation: PhoneCallInformation;
		let blackboardSystem: ref<BlackboardSystem> = GameInstance.GetBlackboardSystem(GetGameInstance());
		let infoVariant: Variant = blackboardSystem.Get(GetAllBlackboardDefs().UI_ComDevice).GetVariant(GetAllBlackboardDefs().UI_ComDevice.PhoneCallInformation);
		if IsDefined(infoVariant) {
			lastPhoneCallInformation = FromVariant<PhoneCallInformation>(infoVariant);
			return Equals(lastPhoneCallInformation.callPhase, questPhoneCallPhase.StartCall) || Equals(lastPhoneCallInformation.callPhase, questPhoneCallPhase.IncomingCall) || Equals(lastPhoneCallInformation.callMode, questPhoneCallMode.Audio);
		};
		return false;
	}

	public final func ShouldShowSleepInVehicleInputHint() -> Bool {
		//DFProfile();
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
			this.player.IsInCombat() || 																		// Combat
			StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoTimeSkip") || 						// Time Skip disabled
			timeSystem.IsPausedState() || 																		// Game paused
			Equals(psmVehicle, gamePSMVehicle.Transition) ||													// Transitioning into / out of vehicle
			(tier >= 3 && tier <= 5) || 																		// Scene tier
			securityData.securityAreaType > ESecurityAreaType.SAFE || 											// Unsafe area
			this.IsAnyPhoneStateActive() ||																		// Phone call
			psmBlackboard.GetBool(GetAllBlackboardDefs().PlayerStateMachine.IsInLoreAnimationScene) || 			// Lore animation (?)
			this.player.GetPreventionSystem().IsChasingPlayer() || 												// Pursued by NCPD
			HubMenuUtility.IsPlayerHardwareDisabled(this.player) ||												// Player Cyberware disabled

			/* Vehicle Sleeping Specific Conditions */
			this.GameStateService.GetSleepingInVehicle() ||														// Already sleeping in vehicle
			this.IsPlayerInRoad() ||																			// In the middle of a road or highway
			isBike ||																							// Motorcycle
			vehicle.m_damageLevel == 3 ||																		// Impending vehicle destruction
			vehiclePS.GetIsSubmerged() ||																		// Vehicle in water
			vehicleObj.IsFlippedOver() ||																		// Vehicle flipped over
			vehicleObj.IsQuest() ||																				// Quest vehicle
			GameInstance.GetRacingSystem(gameInstance).IsRaceInProgress() ||									// Race in progress
			vehicleObj.IsAutoDriveModeEnabled();																// AutoDrive

		return !blockSleepInVehicleInputHint;
	}

	public final func CanPlayerSleepInVehicle(opt genericOnly: Bool) -> DFCanPlayerSleepInVehicleResult {
		//DFProfile();
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
			this.player.IsInCombat() ||													 						// Combat
			StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoTimeSkip") || 						// Time Skip disabled
			timeSystem.IsPausedState() || 																		// Game paused
			Equals(psmVehicle, gamePSMVehicle.Transition) ||													// Transitioning into / out of vehicle
			(tier >= 3 && tier <= 5) || 																		// Scene tier
			securityData.securityAreaType > ESecurityAreaType.SAFE || 											// Unsafe area
			this.IsAnyPhoneStateActive() ||																		// Phone call
			psmBlackboard.GetBool(GetAllBlackboardDefs().PlayerStateMachine.IsInLoreAnimationScene) || 			// Lore animation (?)
			this.player.GetPreventionSystem().IsChasingPlayer() || 												// Pursued by NCPD
			HubMenuUtility.IsPlayerHardwareDisabled(this.player) ||												// Player Cyberware disabled
			this.GameStateService.GetSleepingInVehicle() ||														// Already sleeping in vehicle
			isBike ||																							// Motorcycle
			vehicle.m_damageLevel == 3 ||																		// Impending vehicle destruction
			vehiclePS.GetIsSubmerged() ||																		// Vehicle in water
			vehicleObj.IsFlippedOver() ||																		// Vehicle flipped over
			vehicleObj.IsQuest() ||																				// Quest vehicle
			GameInstance.GetRacingSystem(gameInstance).IsRaceInProgress() ||									// Race in progress
			vehicleObj.IsAutoDriveModeEnabled();																// AutoDrive active

		blockSleepInVehicleMovingReason = (vehicleSpeed > 0.1 || vehicleSpeed < -0.1);							// Vehicle moving
		blockSleepInVehicleInRoadReason = this.IsPlayerInRoad();												// In the middle of a road or highway

		if blockSleepInVehicleGenericReason {
			return DFCanPlayerSleepInVehicleResult.No_Generic;
		} else if !genericOnly && blockSleepInVehicleInRoadReason {
			return DFCanPlayerSleepInVehicleResult.No_InRoad;
		} else if !genericOnly && blockSleepInVehicleMovingReason {
			return DFCanPlayerSleepInVehicleResult.No_Moving;
		}
		
		return DFCanPlayerSleepInVehicleResult.Yes;
	}

	public final func SleepInVehicle() -> Void {
		//DFProfile();
		let canSleep: DFCanPlayerSleepInVehicleResult = this.CanPlayerSleepInVehicle();

		if Equals(canSleep, DFCanPlayerSleepInVehicleResult.Yes) {
			this.GameStateService.SetSleepingInVehicle(true);

			// Pre-calculate any random encounters.
			this.RandomEncounterSystem.SetupRandomEncounterOnSleep();

			let pocketRadio: ref<PocketRadio> = this.player.GetPocketRadio();
			if pocketRadio.IsActive() {
				this.shouldRestoreRadioAfterSleep = true;
				this.SendRadioEvent(false, false, -1);
			}

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
				this.SleepInVehicleStartQuestPhase();
			}
		} else {
			this.ShowActionBlockedNotification(canSleep);
		}
	}

	public final func SleepInVehicleStartQuestPhase() -> Void {
		//DFProfile();
		// Quest Phase and Scene Graph
		GameInstance.GetQuestsSystem(GetGameInstance()).SetFact(n"df_fact_action_sleep_in_vehicle", 1);
	}

	public final func OnSleepInVehicleActionFactChanged(value: Int32) -> Void {
		//DFProfile();
		if value == 0 {
			this.SleepInVehicleAfterQuestPhase();
		}
	}

	public final func SleepInVehicleAfterQuestPhase() -> Void {
		//DFProfile();
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
		if Equals(perspective, vehicleCameraPerspective.FPP) && enginePowerChangeMade {
			this.RegisterSleepInVehicleFinish();
		} else {
			this.SleepInVehicleFinish();
		}
	}

	public final func SleepInVehicleFinish() -> Void {
		//DFProfile();
		if this.shouldRestoreRadioAfterSleep {
			this.shouldRestoreRadioAfterSleep = false;
			this.SendRadioEvent(true, false, 0);
		}
		
		this.GameStateService.SetSleepingInVehicle(false);
	}

	public final func TryToShowTutorial() -> Void {
		//DFProfile();
        if DFRunGuard(this) { return; }

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
		//DFProfile();
		let UISystem = GameInstance.GetUISystem(GetGameInstance());
		let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
		UISystem.QueueEvent(new UIInGameNotificationRemoveEvent());
		if Equals(reason, DFCanPlayerSleepInVehicleResult.No_Generic) {
			notificationEvent.m_notificationType = UIInGameNotificationType.ActionRestriction;
		} else if Equals(reason, DFCanPlayerSleepInVehicleResult.No_Moving) {
			notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        	notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureSleepingInVehicleErrorMoving");
		} else if Equals(reason, DFCanPlayerSleepInVehicleResult.No_InRoad) {
			notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
        	notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureSleepingInVehicleErrorInRoad");
		}

		UISystem.QueueEvent(notificationEvent);
	}

	//
	//	Registration
	//
	private final func RegisterSleepInVehicleEnginePowerChangeDelay() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleEnginePowerChangeDelay.Create(this), this.sleepInVehicleEnginePowerChangeDelayID, this.sleepInVehicleEnginePowerChangeDelayInterval);
	}

	private final func RegisterSleepInVehicleFinish() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, SleepInVehicleFinishDelay.Create(this), this.sleepInVehicleFinishDelayID, this.sleepInVehicleEnginePowerChangeFinishDelayInterval);
	}

	private final func IsPlayerInRoad() -> Bool {		
		//DFProfile();
		return NotEquals(this.AutoDriveSystem.CheckCurrentLaneValidity(), gameAutodriveLaneValidityResult.NotOnRoad);
	}

	public final func SendRadioEvent(toggle: Bool, setStation: Bool, stationIndex: Int32) -> Void {
		//DFProfile();
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
		//DFProfile();
		return false;
	}

	@if(ModuleExists("Hgyi56.Enhanced_Vehicle_System"))
	private final func TryToToggleEngineAndPowerStateViaEVS(toggle: Bool) -> Bool {
		//DFProfile();
		let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(GetGameInstance(), this.player, vehicleObj);
		let vehicle: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();

		vehicle.hgyi56_EVS_TogglePowerState(toggle);
		vehicle.hgyi56_EVS_ToggleEngineState(toggle);
		return true;
	}
}

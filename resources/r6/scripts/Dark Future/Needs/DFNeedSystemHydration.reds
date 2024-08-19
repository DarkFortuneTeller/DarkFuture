// -----------------------------------------------------------------------------
// DFHydrationSystem
// -----------------------------------------------------------------------------
//
// - Hydration Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.RunGuard
import DarkFuture.Main.{
	DFNeedsDatum, 
	DFTimeSkipData
}
import DarkFuture.Services.{
	DFCyberwareService,
	DFGameStateService,
	DFNotificationCallback,
	DFNotification,
	DFAudioCue,
	DFUIDisplay,
	DFNotificationService
}
import DarkFuture.UI.DFHUDBarType
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let effectID: TweakDBID = evt.staticData.GetID();
	if Equals(effectID, t"BaseStatusEffect.Sated") {
        DFHydrationSystem.Get().RegisterBonusEffectCheckCallback();
	}

	return wrappedMethod(evt);
}

@wrapMethod(SprintEvents)
protected func OnUpdate(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	wrappedMethod(timeDelta, stateContext, scriptInterface);
	DFHydrationSystem.Get().ProcessSprintUpdate(stateContext, scriptInterface);
}

public class HydrationBreathingStopCallback extends DFDelayCallback {
	public let HydrationSystem: wref<DFHydrationSystem>;

	public static func Create(hydrationSystem: wref<DFHydrationSystem>) -> ref<DFDelayCallback> {
		let self = new HydrationBreathingStopCallback();
		self.HydrationSystem = hydrationSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.HydrationSystem.hydrationBreathingStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.HydrationSystem.OnHydrationBreathingStopCallback();
	}
}

public class HydrationRecheckSprintingCallback extends DFDelayCallback {
	public let HydrationSystem: wref<DFHydrationSystem>;

	public static func Create(hydrationSystem: wref<DFHydrationSystem>) -> ref<DFDelayCallback> {
		let self = new HydrationRecheckSprintingCallback();
		self.HydrationSystem = hydrationSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.HydrationSystem.hydrationRecheckSprintingDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.HydrationSystem.OnHydrationRecheckSprintingCallback();
	}
}

public class HydrationRecheckDefaultCallback extends DFDelayCallback {
	public let HydrationSystem: wref<DFHydrationSystem>;

	public static func Create(hydrationSystem: wref<DFHydrationSystem>) -> ref<DFDelayCallback> {
		let self = new HydrationRecheckDefaultCallback();
		self.HydrationSystem = hydrationSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.HydrationSystem.hydrationRecheckDefaultDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.HydrationSystem.OnHydrationRecheckDefaultCallback();
	}
}

public final class DFHydrationSystemBreathingEffectsCallback extends DFNotificationCallback {
	public static func Create() -> ref<DFHydrationSystemBreathingEffectsCallback> {
		let self: ref<DFHydrationSystemBreathingEffectsCallback> = new DFHydrationSystemBreathingEffectsCallback();

		return self;
	}

	public final func Callback() -> Void {
		DFHydrationSystem.Get().TryToPlayHydrationBreathingEffects(true);
	}
}

class DFHydrationSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFHydrationSystem.Get();
	}
}

public final class DFHydrationSystem extends DFNeedSystemBase {
	private let locomotionListener: ref<CallbackHandle>;

    public let hydrationBreathingEffectQueued: Bool = false;

	private let StatPoolsSystem: ref<StatPoolsSystem>;
	private let NerveSystem: ref<DFNerveSystem>;

    // Boosters
	private let boosterStaminaHydrationChangeBonusMult: Float = 0.2;
	private let boosterStaminaBlackMarketHydrationChangeBonusMult: Float = 0.3;

    private let hydrationRecheckSprintingDelayID: DelayID;
	private let hydrationRecheckDefaultDelayID: DelayID;
	private let hydrationBreathingStopDelayID: DelayID;

    private let hydrationRecheckSprintingDelayInterval: Float = 5.0;
	private let hydrationRecheckDefaultDelayInterval: Float = 0.35;
	private let hydrationBreathingStopDelayInterval: Float = 2.6;

    private let playingHydrationBreathingFX: Bool = false;

    // Hydration Exertion
	private let playerExertionLevelThisCycle: Int32 = 0;
	private let playerExertionHydrationChangeSprintingMult: Float = 0.5; // 1.5x
	private let playerExertionHydrationChangeDashingMult: Float = 1.0;   // 2.0x

    // Low Hydration Stamina Costs
	private let playerHydrationPenalty02StaminaCostSprinting: Float = 0.035;
	private let playerHydrationPenalty02StaminaCostJumping: Float = 2.0;
	private let playerHydrationPenalty03StaminaCostSprinting: Float = 0.05;
	private let playerHydrationPenalty03StaminaCostJumping: Float = 4.0;
	private let playerHydrationPenalty04StaminaCostSprinting: Float = 0.075;
	private let playerHydrationPenalty04StaminaCostJumping: Float = 6.0;

	// State Memory
	private let lastLocomotionState: Int32 = 0;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHydrationSystem> {
		let instance: ref<DFHydrationSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Needs.DFHydrationSystem") as DFHydrationSystem;
		return instance;
	}

	public final static func Get() -> ref<DFHydrationSystem> {
		return DFHydrationSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	private func GetSystems() -> Void {
		super.GetSystems();

		let gameInstance = GetGameInstance();
		this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
		this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
	}

	private func SetupData() -> Void {
		this.needStageThresholdDeficits = [15.0, 25.0, 50.0, 75.0, 100.0];
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.HydrationPenalty_01",
			t"DarkFutureStatusEffect.HydrationPenalty_02",
			t"DarkFutureStatusEffect.HydrationPenalty_03",
			t"DarkFutureStatusEffect.HydrationPenalty_04"
		];
	}

	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		super.InitSpecific(attachedPlayer);
		this.StopHydrationBreathingEffects();
	}

	private func UnregisterAllDelayCallbacks() -> Void {
		super.UnregisterAllDelayCallbacks();
		this.UnregisterHydrationRecheckDefaultCallback();
		this.UnregisterHydrationRecheckSprintCallback();
		this.UnregisterHydrationBreathingStopCallback();
	}

	private final func RegisterListeners() -> Void {
		this.locomotionListener = this.PSMBlackboard.RegisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion, this, n"OnLocomotionStateChanged");
	}

	private func UnregisterListeners() -> Void {
		this.PSMBlackboard.UnregisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion, this.locomotionListener);
		this.locomotionListener = null;
	}

	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.hydrationBreathingEffectQueued = false;
		this.playerExertionLevelThisCycle = 0;
		this.lastLocomotionState = 0;
		this.StopHydrationBreathingEffects();
		this.ClearHydrationStaminaCosts();
	}

	private func DoPostResumeActions() -> Void {
		super.DoPostResumeActions();
		this.SetHydrationStaminaCosts();
	}

	//
	//  Required Overrides
	//
	private final func SuspendFX() -> Void {
		super.SuspendFX();
		this.StopHydrationBreathingEffects();
	}

	private final func OnUpdateActual() -> Void {
		DFLog(this.debugEnabled, this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetHydrationChange());
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		DFLog(this.debugEnabled, this, "OnTimeSkipFinishedActual");

		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.hydration.value - this.GetNeedValue());
	}

	private final func OnItemConsumedActual(itemData: wref<gameItemData>) {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemData);

		if consumableNeedsData.hydration.value != 0.0 {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = true;
			uiFlags.forceBright = true;
			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.hydration), uiFlags);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Hydration;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this.debugEnabled, this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
		
		let notification: DFNotification;
		if stage >= 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_effort_short", 10);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Hydration, true, false);
			notification.callback = DFHydrationSystemBreathingEffectsCallback.Create();
			this.NotificationService.QueueNotification(notification);
		} else if stage == 2 || stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_curious", 20);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Hydration, false, true);
			this.NotificationService.QueueNotification(notification);
		} else if stage == 0 {
			if this.Settings.needPositiveSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_inhale_post_drink", 30);
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		return n"DarkFutureHydrationNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		return n"DarkFutureNeedHydration";
	}

	public final func CheckIfBonusEffectsValid() -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState("CheckIfBonusEffectsValid", true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.Sated") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.Sated");
				}
			}
		}
	}

	private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialHydrationTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialHydration";
	}

	//
	//	Overrides
	//
	private final func RefreshNeedStatusEffects() -> Void {
		super.RefreshNeedStatusEffects();

		// Set effects that can't be applied via a Status Effect.
		this.SetHydrationStaminaCosts();
	}

	private final func SuspendFX() -> Void {
		super.SuspendFX();
		this.StopHydrationBreathingEffects();
	}

	//
	//	RunGuard Protected Methods
	//
	protected cb func OnLocomotionStateChanged(value: Int32) -> Void {
		if RunGuard(this) { return; }
		
		if this.GameStateService.IsValidGameState("OnLocomotionStateChanged") {
			// 0 = Default, 2 = Sprinting, 7 = Dashing

			this.lastLocomotionState = value;

			// Exertion tracking
			if value == 2 && this.playerExertionLevelThisCycle < 1 {
				this.playerExertionLevelThisCycle = 1;
			} else if value == 7 && this.playerExertionLevelThisCycle < 2 {
				this.playerExertionLevelThisCycle = 2;
			}

			// Hydration breathing effect
			if this.hydrationBreathingEffectQueued {
				if value == 0 {
					this.RegisterHydrationRecheckDefaultCallback();
				}
			} else {
				if value == 2 {
					// Debounce VFX playback after starting to Sprint - require continuous sprinting before feeling exhausted
					this.RegisterHydrationRecheckSprintCallback();
				} else if value == 7 {
					// Immediate playback after Dash
					this.hydrationBreathingEffectQueued = true;
				}
			}
		}
	}

	public final func ProcessSprintUpdate(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Void {
		if RunGuard(this) { return; }

		// Interrupt the player's sprinting when Stamina runs out when Hydration is stage 2 or higher.
		// Use caution; called roughly every frame while sprinting.

		if this.GameStateService.IsValidGameState("DFHydrationSystem:ProcessSprintUpdate") {
			let shouldInterruptSprint: Bool = this.GetNeedStage() >= 2 && this.StatPoolsSystem.GetStatPoolValue(Cast<StatsObjectID>(scriptInterface.executionOwner.GetEntityID()), gamedataStatPoolType.Stamina, true) <= 0.0;

			if shouldInterruptSprint {
				stateContext.SetTemporaryBoolParameter(n"InterruptSprint", true, true);
    			stateContext.SetConditionBoolParameter(n"SprintToggled", false, true);
    			stateContext.SetConditionBoolParameter(n"SprintHoldCanStartWithoutNewInput", false, true);
			}
		}
	}

	//
	//  System-Specific Methods
	//
	private final func GetHydrationChange(opt ignoreExertion: Bool) -> Float {
		// Subtract 100 points every 18 in-game hours.

		// (Points to Lose) / ((Target In-Game Hours * 60 In-Game Minutes) / In-Game Update Interval (5 Minutes))
		let value: Float = (100.0 / ((18.0 * 60.0) / 5.0) * -1.0) * (this.Settings.hydrationLossRatePct / 100.0);

		if ignoreExertion {
			return value;
		}

		// Increase the amount depending on the level of exertion this cycle.
		if this.playerExertionLevelThisCycle == 1 { // Sprinting
			this.playerExertionLevelThisCycle = 0;
			return value * (1.0 + (this.playerExertionHydrationChangeSprintingMult * (this.CyberwareService.GetExertionHydrationChangeBonusMult() - this.GetStaminaBoosterHydrationChangeBonusMult())));
		
		} else if this.playerExertionLevelThisCycle == 2 { // Dodging and Dashing
			this.playerExertionLevelThisCycle = 0;
			return value * (1.0 + (this.playerExertionHydrationChangeDashingMult * (this.CyberwareService.GetExertionHydrationChangeBonusMult() - this.GetStaminaBoosterHydrationChangeBonusMult())));
		
		} else { // playerExertionLevelThisCycle == 0, Walking
			return value;
		}
	}

    private final func SetHydrationStaminaCosts() {
		DFLog(this.debugEnabled, this, "SetHydrationStaminaCosts");

		let hydrationStage: Int32 = this.GetNeedStage();
		DFLog(this.debugEnabled, this, "    hydrationStage = " + ToString(hydrationStage));

		if hydrationStage < 2 || !this.GameStateService.IsValidGameState("SetHydrationStaminaCosts") {
			this.ClearHydrationStaminaCosts();
		} else if hydrationStage == 2 {
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != this.playerHydrationPenalty02StaminaCostSprinting {
				TweakDBManager.SetFlat(t"player.staminaCosts.sprint", this.playerHydrationPenalty02StaminaCostSprinting);
			}
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != this.playerHydrationPenalty02StaminaCostJumping {
				TweakDBManager.SetFlat(t"player.staminaCosts.jump", this.playerHydrationPenalty02StaminaCostJumping);
			}
		} else if hydrationStage == 3 {
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != this.playerHydrationPenalty03StaminaCostSprinting {
				TweakDBManager.SetFlat(t"player.staminaCosts.sprint", this.playerHydrationPenalty03StaminaCostSprinting);
			}
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != this.playerHydrationPenalty03StaminaCostJumping {
				TweakDBManager.SetFlat(t"player.staminaCosts.jump", this.playerHydrationPenalty03StaminaCostJumping);
			}
		} else if hydrationStage == 4 {
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != this.playerHydrationPenalty04StaminaCostSprinting {
				TweakDBManager.SetFlat(t"player.staminaCosts.sprint", this.playerHydrationPenalty04StaminaCostSprinting);
			}
			if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != this.playerHydrationPenalty04StaminaCostJumping {
				TweakDBManager.SetFlat(t"player.staminaCosts.jump", this.playerHydrationPenalty04StaminaCostJumping);
			}
		}
	}

	private final func ClearHydrationStaminaCosts() -> Void {
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.sprint")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.sprint", 0.0);
		}
		if FromVariant<Float>(TweakDBInterface.GetFlat(t"player.staminaCosts.jump")) != 0.0 {
			TweakDBManager.SetFlat(t"player.staminaCosts.jump", 0.0);
		}
	}

	private final func GetStaminaBoosterHydrationChangeBonusMult() -> Float {
		let value: Float = 0.0;

		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.StaminaBooster") {
			return this.boosterStaminaHydrationChangeBonusMult;
		} else if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.Blackmarket_StaminaBooster") {
			return this.boosterStaminaBlackMarketHydrationChangeBonusMult;
		}

		return value;
	}

    private final func TryToPlayHydrationBreathingEffects(opt noAudio: Bool) -> Void {
		DFLog(this.debugEnabled, this, "TryToPlayHydrationBreathingEffects noAudio = " + ToString(noAudio));

		if this.GameStateService.IsValidGameState("TryToPlayHydrationBreathingEffects") {
			// Allow Nerve breathing FX to win over Hydration Breathing FX.
			if this.NerveSystem.currentNerveBreathingFXStage != 0 {
				return;
			}
			
			let hydrationStage = this.GetNeedStage();
			if hydrationStage >= 3 {
				this.StartHydrationBreathingEffects(noAudio);
				this.RegisterHydrationBreathingStopCallback();
			}
		}
	}

    private final func StartHydrationBreathingEffects(opt noAudio: Bool) -> Void {
		DFLog(this.debugEnabled, this, "StartHydrationBreathingEffects noAudio = " + ToString(noAudio));

		if !this.playingHydrationBreathingFX {
			this.playingHydrationBreathingFX = true;

			if (this.Settings.hydrationNeedVFXEnabled && noAudio) || (this.Settings.lowHydrationCameraEffectEnabled && !noAudio) {
				// if noAudio == true, this event came from a low need notification.
				// if noAudio == false, this event came from sprinting or dashing.
				StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.BreathingHeavy");
			}

			if !noAudio {
				// Player was sprinting.
				if this.Settings.lowHydrationBreathingEffectEnabled {
					let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
					evt.soundName = n"ono_v_breath_fast";
					this.player.QueueEvent(evt);
				}
			}
		}
	}

	private final func StopHydrationBreathingEffects() -> Void {
		DFLog(this.debugEnabled, this, "StopHydrationBreathingEffects");
		
		StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.BreathingHeavy");
		this.playingHydrationBreathingFX = false;
	}

	public final func StopHydrationBreathingSFXIfBreathingFXPlaying() -> Void {
		if this.playingHydrationBreathingFX {
			this.StopHydrationBreathingSFX();
		}
	}

	private final func StopHydrationBreathingSFX() -> Void {
		DFLog(this.debugEnabled, this, "StopHydrationBreathingSFX");

		// Only used when other breathing SFX need to stop this early, otherwise stops on its own
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
		evt.soundName = n"ono_v_breath_fast";
		this.player.QueueEvent(evt);
	}

    public final func OnHydrationRecheckSprintingCallback() -> Void {
		if this.lastLocomotionState == 2 { // Still sprinting!
			DFLog(this.debugEnabled, this, "OnHydrationRecheckSprintingCallback -- Still sprinting! Queuing breathing effect.");
			this.hydrationBreathingEffectQueued = true;
		}
	}

	public final func OnHydrationRecheckDefaultCallback() -> Void {
		if this.lastLocomotionState == 0 { // Still default!
			DFLog(this.debugEnabled, this, "OnHydrationRecheckSprintingCallback -- Still default! Playing breathing effect.");
			this.hydrationBreathingEffectQueued = false;
			this.TryToPlayHydrationBreathingEffects();
		}
	}

	public final func OnHydrationBreathingStopCallback() -> Void {
		this.StopHydrationBreathingEffects();
	}

	//
	//	Registration
	//
    private final func RegisterHydrationRecheckSprintCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, HydrationRecheckSprintingCallback.Create(this), this.hydrationRecheckSprintingDelayID, this.hydrationRecheckSprintingDelayInterval);
	}

	private final func RegisterHydrationRecheckDefaultCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, HydrationRecheckDefaultCallback.Create(this), this.hydrationRecheckDefaultDelayID, this.hydrationRecheckDefaultDelayInterval);
	}

	private final func RegisterHydrationBreathingStopCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, HydrationBreathingStopCallback.Create(this), this.hydrationBreathingStopDelayID, this.hydrationBreathingStopDelayInterval);
	}

	//
	//	Unregistration
	//
	private final func UnregisterHydrationRecheckDefaultCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.hydrationRecheckDefaultDelayID);
	}

    private final func UnregisterHydrationRecheckSprintCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.hydrationRecheckSprintingDelayID);
	}
	
	private final func UnregisterHydrationBreathingStopCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.hydrationBreathingStopDelayID);
	}
}
// -----------------------------------------------------------------------------
// DFNerveSystem
// -----------------------------------------------------------------------------
//
// - Nerve Basic Need system.
//

module DarkFuture.Needs

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
	RunGuard,
	Int32ToFloat
}
import DarkFuture.Main.{
	DFNeedsDatum, 
	DFAfflictionUpdateDatum,
	DFTimeSkipData
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
import DarkFuture.Afflictions.DFTraumaAfflictionSystem
import DarkFuture.Services.{
	DFCyberwareService,
	DFPlayerStateService,
	DFPlayerDangerState,
	DFGameStateService,
	DFNotificationService,
	DFAudioCue,
	DFVisualEffect,
	DFUIDisplay,
	DFMessage,
	DFMessageContext,
	DFNotification,
	DFNotificationCallback
}
import DarkFuture.UI.{
	DFHUDSystem,
	DFHUDBarType
}
import DarkFuture.Settings.DFSettings

enum DFNerveSystemUpdateMode {
	Time = 0,
	Danger = 1,
	Withdrawal = 2,
	Regen = 3,
	Suspended = 4
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
	let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();

	if IsSystemEnabledAndRunning(nerveSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();
		if Equals(effectID, t"BaseStatusEffect.VehicleKnockdown") {
			nerveSystem.OnVehicleKnockdown();

		} else if DFGameStateService.Get().IsValidGameState("OnStatusEffectRemoved") && Equals(effectID, t"BaseStatusEffect.FocusedCoolPerkSE") {
			nerveSystem.UpdateWeaponShake();
		}
	}
    
	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();

	if IsSystemEnabledAndRunning(nerveSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();
		if DFGameStateService.Get().IsValidGameState("OnStatusEffectRemoved") && Equals(effectID, t"BaseStatusEffect.FocusedCoolPerkSE") {
			nerveSystem.UpdateWeaponShake();
		}
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnUpperBodyStateChange(newState: Int32) -> Bool {
	let result: Bool = wrappedMethod(newState);
	let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();

	if IsSystemEnabledAndRunning(nerveSystem) {
		// Aim Events
		if IsDefined(this.m_equippedRightHandWeapon) {
			nerveSystem.OnUpperBodyStateChange();
		}
	}

	return result;
}

@wrapMethod(NPCPuppet)
protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
	let val: Bool = wrappedMethod(evt);

	DFNerveSystem.Get().CheckFuryNerveOnKill(evt);

	return val;
}

public class PlayerDeathCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new PlayerDeathCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().playerDeathDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnPlayerDeathCallback();
	}
}

public class NerveRegenCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new NerveRegenCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().nerveRegenDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnUpdateFromNerveRegen();
	}
}

public class DangerUpdateDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new DangerUpdateDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().dangerUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnUpdateFromDanger();
	}
}

public class WithdrawalUpdateDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new WithdrawalUpdateDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().withdrawalUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnUpdateFromWithdrawal();
	}
}

public class NerveBreathingDangerTransitionCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new NerveBreathingDangerTransitionCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().nerveBreathingDangerTransitionDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnNerveBreathingDangerTransitionCallback();
	}
}

class DFNerveSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		return DFNerveSystem.Get();
	}
}

public final class DFNerveSystem extends DFNeedSystemBase {
	private let AudioSystem: ref<AudioSystem>;
	private let StatPoolsSystem: ref<StatPoolsSystem>;
	private let HUDSystem: ref<DFHUDSystem>;
	private let HydrationSystem: ref<DFHydrationSystem>;
	private let NutritionSystem: ref<DFNutritionSystem>;
	private let EnergySystem: ref<DFEnergySystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
	private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
	private let TraumaSystem: ref<DFTraumaAfflictionSystem>;

	private let baseAlcoholNerveValueChangeAmount: Float = 5.0;
	private let nerveAmountOnVehicleKnockdown: Float = 2.0;
	private let nerveLossInCombatOrTrace: Float = 0.25;
	private let nerveLossHeat: Float = 0.1;
	private let nerveLossInWithdrawal: Float = 0.5;
	private let nerveRegenAmountRapid: Float = 1.0;
	private let nerveRegenAmountSlow: Float = 0.05;
	private let criticalNerveRegenTarget: Float = 10.0;
	private let criticalNerveFXThreshold: Float = 10.0;
	private let extremelyCriticalNerveFXThreshold: Float = 5.0;
	private let playingCriticalNerveFX: Bool = false;
	private let nauseaNeedStageThreshold: Int32 = 3;
	private let nerveRecoverAmountSleeping: Float = 0.1166675;
	
	private let nerveRestoreInFuryOnKill: Float = 2.0;
	private let nerveRestoreFinisherOnKill: Float = 2.0;
	private let nerveCalmMindBonusFactor: Float = 0.5;

    private let boosterMemoryTraceNerveLossBonusMult: Float = 0.35;
	private let boosterMemoryBlackMarketTraceNerveLossBonusMult: Float = 0.50;

	private let currentNerveBreathingFXStage: Int32 = 0;

	private let dangerUpdateDelayID: DelayID;
	private let withdrawalUpdateDelayID: DelayID;
	private let nerveBreathingDangerTransitionDelayID: DelayID;
	private let nerveRegenDelayID: DelayID;
	private let playerDeathDelayID: DelayID;

	private let updateMode: DFNerveSystemUpdateMode = DFNerveSystemUpdateMode.Time;

	private let dangerUpdateDelayInterval: Float = 5.0;
	private let withdrawalUpdateDelayInterval: Float = 5.0;
	private let nerveBreathingDangerTransitionDelayInterval: Float = 10.0;
	private let nerveRegenDelayInterval: Float = 0.25;
	private let playerDeathDelayInterval: Float = 2.0;

	private let lastDangerState: DFPlayerDangerState;

	private let lastNerveForCriticalFXCheck: Float = 100.0;
	private let cyberwareSecondHeartNerveRestoreAmount: Float = 30.0;

	// Regen
	private let currentNerveRegenTarget: Float = 10.0; // Default: criticalNerveRegenTarget
	private let currentNerveWithdrawalTarget: Float = 100.0;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNerveSystem> {
		let instance: ref<DFNerveSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Needs.DFNerveSystem") as DFNerveSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNerveSystem> {
		return DFNerveSystem.GetInstance(GetGameInstance());
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
		this.AudioSystem = GameInstance.GetAudioSystem(gameInstance);
		this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
		this.HUDSystem = DFHUDSystem.GetInstance(gameInstance);
		this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
		this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
		this.TraumaSystem = DFTraumaAfflictionSystem.GetInstance(gameInstance);
	}

	private func SetupData() -> Void {
		this.needStageThresholdDeficits = [15.0, 25.0, 50.0, 75.0, 100.0];
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.NervePenalty_01",
			t"DarkFutureStatusEffect.NervePenalty_02",
			t"DarkFutureStatusEffect.NervePenalty_03",
			t"DarkFutureStatusEffect.NervePenalty_04"
		];
	}

	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		super.InitSpecific(attachedPlayer);
		this.CheckForCriticalNerve();
		this.UpdateNerveWithdrawalTarget();
	}

	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.StopCriticalNerveEffects(true);
		this.StopNerveBreathingEffects();
		this.lastDangerState = new DFPlayerDangerState(false, false, false);
		this.lastNerveForCriticalFXCheck = 100.0;
		this.currentNerveRegenTarget = this.criticalNerveRegenTarget;
		this.currentNerveWithdrawalTarget = 100.0;
	}

	private func DoPostResumeActions() -> Void {
		super.DoPostResumeActions();
		this.CheckForCriticalNerve();
		this.UpdateNerveWithdrawalTarget();
	}

	public final func OnTimeSkipStart() -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipStart");

		this.SetUpdateMode(DFNerveSystemUpdateMode.Suspended);
		this.UnregisterAllNeedFXCallbacks();
	}

	public final func OnTimeSkipCancelled() -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipCancelled");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState("DFNeedSystemBase:OnTimeSkipCancelled", true) {
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipFinished");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState("DFNeedSystemBase:OnTimeSkipFinished", true) {
			this.OnTimeSkipFinishedActual(data);
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	private func UnregisterAllDelayCallbacks() -> Void {
		super.UnregisterAllDelayCallbacks();

		this.UnregisterDangerUpdateCallback();
		this.UnregisterWithdrawalUpdateCallback();
		this.UnregisterNerveBreathingDangerTransitionCallback();
		this.UnregisterNerveRegenCallback();
		this.UnregisterPlayerDeathCallback();
	}


	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		super.OnSettingChangedSpecific(changedSettings);

		if ArrayContains(changedSettings, "nerveWeaponSwayEnabled") {
			if this.Settings.nerveWeaponSwayEnabled {
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_02.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_02_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_02_WeaponHandlingPackage",
						t"DarkFutureStatusEffect.NervePenalty_02_SwayPackage"
					]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_03.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_03_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_03_WeaponHandlingPackage",
						t"DarkFutureStatusEffect.NervePenalty_03_SwayPackage"
					]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_04.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_04_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_04_WeaponHandlingPackage",
						t"DarkFutureStatusEffect.NervePenalty_04_SwayPackage"
					]);
			} else {
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_02.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_02_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_02_WeaponHandlingPackage"
					]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_03.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_03_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_03_WeaponHandlingPackage"
					]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NervePenalty_04.packages",
					[
						t"DarkFutureStatusEffect.NervePenalty_04_StatsPackage",
						t"DarkFutureStatusEffect.NervePenalty_04_WeaponHandlingPackage"
					]);
			}

			TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NervePenalty_02");
			TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NervePenalty_03");
			TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NervePenalty_04");
		}
	}

    //
	//  Required Overrides
	//
    private final func OnUpdateActual() -> Void {
		DFLog(this.debugEnabled, this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetNerveChangeFromTimeInProvidedState(this.GetNeedValue(), this.HydrationSystem.GetNeedStage(), this.NutritionSystem.GetNeedStage(), this.EnergySystem.GetNeedStage()));
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		DFLog(this.debugEnabled, this, "OnTimeSkipFinishedActual");

		this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nerve.value - this.GetNeedValue());
	}

	private final func OnItemConsumedActual(itemData: wref<gameItemData>) {
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemData);

		if consumableNeedsData.nerve.value != 0.0 {
			// Alcohol is also partially handled in ProcessAddictiveItemOrWorkspotUsed().
			// Narcotics are handled in ProcessNarcoticsNerveChangeOffsetEffectRemoved().

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = true;
			uiFlags.forceBright = true;

			let suppressRecoveryNotification: Bool = itemData.HasTag(n"DarkFutureConsumableAddictiveNicotine");

			this.ChangeNeedValue(this.GetClampedNeedChangeFromData(consumableNeedsData.nerve), uiFlags, false, suppressRecoveryNotification);
		}
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Nerve;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this.debugEnabled, this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;

		if stage == 4 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = new DFVisualEffect(n"hacking_interference_shot", null);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Nerve, true, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = new DFVisualEffect(n"stagger_effect", null);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Nerve, true, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 2 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_exhale_01", 20);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = new DFVisualEffect(n"stagger_effect", null);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Nerve, false, true);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_exhale_01", 20);
			}

			notification.ui = new DFUIDisplay(DFHUDBarType.Nerve, false, true);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 0 && !suppressRecoveryNotification {
			if this.Settings.needPositiveSFXEnabled {
				notification.sfx = new DFAudioCue(n"ono_v_music_start", 30);
			}

			// Don't show the UI when recovering if it is the result of
			// a nerve regen interaction.
			if this.GetNerveRegenTarget() == 0.0 {
				notification.ui = new DFUIDisplay(DFHUDBarType.Nerve, false, true);
			}
			this.NotificationService.QueueNotification(notification);
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		return n"DarkFutureNerveNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		return n"DarkFutureNeedNerve";
	}

	public final func CheckIfBonusEffectsValid() -> Void {
        if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState("CheckIfBonusEffectsValid", true) {
			if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"HousingStatusEffect.Refreshed") {
				if this.GetNeedStage() > 0 {
					StatusEffectHelper.RemoveStatusEffect(this.player, t"HousingStatusEffect.Refreshed");
				}
			}
		}
	}

	private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialNerveTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialNerve";
	}

	//
	//	Overrides
	//
	private final func ReapplyFX() -> Void {
		super.ReapplyFX();
		this.TryToTransitionNerveBreathingEffects();
		this.CheckForCriticalNerve();
	}

	private final func SuspendFX() -> Void {
        super.SuspendFX();
        this.StopNerveBreathingEffects();
		this.StopCriticalNerveEffects(true);
    }

	public final func OnSceneTierChanged(value: GameplayTier) -> Void {
		if RunGuard(this, true) { return; }
		super.OnSceneTierChanged(value);

		// When transitioning back to a playable Gameplay Tier, remove any interaction-based
		// Nerve Regen target.
		if this.GetNerveRegenTarget() > 0.0 && (Equals(value, GameplayTier.Tier1_FullGameplay) || Equals(value, GameplayTier.Tier2_StagedGameplay)) {
			this.SetNerveRegenTarget(this.criticalNerveRegenTarget);
		}
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeNeedValue(amount: Float, opt uiFlags: DFNeedChangeUIFlags, opt forceTraumaAccumulation: Bool, opt suppressRecoveryNotification: Bool) -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "ChangeNeedValue: amount = " + ToString(amount) + ", uiFlags = " + ToString(uiFlags) + ", forceTraumaAccumulation = " + ToString(forceTraumaAccumulation));

		this.TraumaSystem.AccumulateNerveLoss(amount, forceTraumaAccumulation);

		let needMax: Float = this.GetCalculatedNeedMax();
		this.needValue = ClampF(this.needValue + amount, 0.0, needMax);
		this.needMax = needMax;
		this.UpdateNeedHUDUI(uiFlags.forceMomentaryUIDisplay, uiFlags.instantUIChange, uiFlags.forceBright, uiFlags.momentaryDisplayIgnoresSceneTier);

		let stage: Int32 = this.GetNeedStage();
		if NotEquals(stage, this.lastNeedStage) {
			DFLog(this.debugEnabled, this, "ChangeNeedValue: Last Need stage (" + ToString(this.lastNeedStage) + ") != current stage (" + ToString(stage) + "). Refreshing status effects and FX.");
			this.RefreshNeedStatusEffects();
			this.UpdateNeedFX(suppressRecoveryNotification);
		}

		if stage > this.lastNeedStage && this.lastNeedStage < 4 && stage == 4 {
			this.QueueSevereNeedMessage();
		}

		this.CheckForCriticalNerve();
		this.CheckIfBonusEffectsValid();
		this.TryToShowTutorial();
		
		this.lastNeedStage = stage;
		DFLog(this.debugEnabled, this, "ChangeNeedValue: New needValue = " + ToString(this.needValue));
	}

    //
    //  System-Specific Methods
    //
	public final func SetUpdateMode(mode: DFNerveSystemUpdateMode) -> Void {
		if RunGuard(this) { return; }
		
		DFLog(this.debugEnabled, this, "---- SetUpdateMode ----");
		this.updateMode = mode;

		if Equals(mode, DFNerveSystemUpdateMode.Time) {
			DFLog(this.debugEnabled, this, "     Setting mode: Time");
			this.RegisterUpdateCallback();
		} else {
			this.UnregisterUpdateCallback();
		}
		
		if Equals(mode, DFNerveSystemUpdateMode.Danger) {
			DFLog(this.debugEnabled, this, "     Setting mode: Danger");
			this.RegisterDangerUpdateCallback();
		} else {
			this.UnregisterDangerUpdateCallback();
		}

		if Equals(mode, DFNerveSystemUpdateMode.Withdrawal) {
			DFLog(this.debugEnabled, this, "     Setting mode: Withdrawal");
			this.RegisterWithdrawalUpdateCallback();
		} else {
			this.UnregisterWithdrawalUpdateCallback();
		}

		if Equals(mode, DFNerveSystemUpdateMode.Regen) {
			DFLog(this.debugEnabled, this, "     Setting mode: Regen");
			this.RegisterNerveRegenCallback();
		} else {
			this.UnregisterNerveRegenCallback();
		}

		if Equals(mode, DFNerveSystemUpdateMode.Suspended) {
			DFLog(this.debugEnabled, this, "     Setting mode: Suspended");
		}
	}

	public final func ApplyBaseAlcoholNerveValueChange() -> Void {
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		this.ChangeNeedValue(this.baseAlcoholNerveValueChangeAmount, uiFlags);
	}

	public final func CheckFuryNerveOnKill(evt: ref<gameDeathEvent>) -> Void {
		if IsDefined(evt.instigator) {
			let playerGO: wref<GameObject> = this.player;
			if this.GameStateService.isInFury && Equals(evt.instigator, playerGO) {
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.instantUIChange = true;
				this.ChangeNeedValue(this.nerveRestoreInFuryOnKill, uiFlags);
			}
		}
	}

	public final func AutoSetUpdateMode() -> Void {
		if RunGuard(this) { return; }

		DFLog(this.debugEnabled, this, "---- AutoSetUpdateMode ----");
		let inDanger: Bool = this.PlayerStateService.GetInDanger();
		let inWithdrawal: Bool = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() == 0.0 && this.GetNerveWithdrawalTarget() != 100.0;
		let regenTarget: Float = this.GetNerveRegenTarget();
		let regen: Bool = this.GetNeedValue() < regenTarget && (Equals(regenTarget, 100.0) || (this.HydrationSystem.GetNeedStage() < 4 && this.NutritionSystem.GetNeedStage() < 4 && this.EnergySystem.GetNeedStage() < 4));

		DFLog(this.debugEnabled, this, "     inDanger: " + ToString(inDanger));
		DFLog(this.debugEnabled, this, "     inWithdrawal: " + ToString(inWithdrawal));
		DFLog(this.debugEnabled, this, "     regen: " + ToString(regen));

		if inDanger {
			DFLog(this.debugEnabled, this, "     Setting mode: Danger");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Danger);

		} else if regen {
			DFLog(this.debugEnabled, this, "     Setting mode: Regen");
			DFLog(this.debugEnabled, this, "     Setting mode: Target: " + regenTarget);
			this.SetUpdateMode(DFNerveSystemUpdateMode.Regen);

		} else if inWithdrawal && this.GetNerveWithdrawalTarget() < this.GetNeedValue() {
			DFLog(this.debugEnabled, this, "     Setting mode: Withdrawal (GetNerveWithdrawalTarget = " + ToString(this.GetNerveWithdrawalTarget()) + ")");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Withdrawal);

		} else {
			DFLog(this.debugEnabled, this, "     Setting mode: Time");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Time);
		}
	}

	public final func GetNerveChangeFromTimeInProvidedState(nerveValue: Float, hydrationStage: Int32, nutritionStage: Int32, energyStage: Int32) -> Float {
		// If we're in danger, skip updating from time.
		if this.PlayerStateService.GetInDanger() {
			return 0.0;
		}

		let needsFactorPerDay: Int32 = 0;
		if nutritionStage >= 2 {
			needsFactorPerDay += (nutritionStage - 1);
		}
		if hydrationStage >= 2 {
			needsFactorPerDay += (hydrationStage - 1);
		}
		if energyStage >= 2 {
			needsFactorPerDay += (energyStage - 1);
		}

		if needsFactorPerDay > 0 {
			// Deplete
			// (Points to Lose based on Needs Factor) / Hours in Day / Updates per Hour
			return (((Int32ToFloat(needsFactorPerDay) * 5.0) / 24.0) / 12.0) * -1.0;
		} else {
			// Recover
			// Amount to recover per Day / Hours in Day / Updates per Hour
			return (((20.0) / 24.0) / 12.0);
		}

		// Not depleting.
		return 0.0;
	}

    public final func GetNerveChangeFromDanger() -> Float {
		if this.lastDangerState.InCombat {
			let baseNerveLossInCombat: Float = ((this.nerveLossInCombatOrTrace * (this.Settings.nerveLossRateInDangerPct / 100.0)) * (1.0 - this.CyberwareService.GetNerveCostFromStressBonusMult())) * -1.0;
			// Does the player have Adrenaline and the Calm Mind perk?
			if PlayerDevelopmentSystem.GetData(this.player).IsNewPerkBoughtAnyLevel(gamedataNewPerkType.Body_Central_Perk_3_1) && 
				this.StatPoolsSystem.GetStatPoolValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatPoolType.Overshield, false) > 0.00 {
				return baseNerveLossInCombat * this.nerveCalmMindBonusFactor;
			} else {
				return baseNerveLossInCombat;
			}
		
		} else if this.lastDangerState.BeingRevealed {
			return ((this.nerveLossInCombatOrTrace * (this.Settings.nerveLossRateInDangerPct / 100.0)) * (1.0 - (this.CyberwareService.GetNerveCostFromStressBonusMult() + this.GetMemoryBoosterTraceNerveLossBonusMult()))) * -1.0;

		} else if this.lastDangerState.HasHeat {
			return ((this.nerveLossHeat * (this.Settings.nerveLossRateHeatPct / 100.0)) * (1.0 - this.CyberwareService.GetNerveCostFromStressBonusMult())) * -1.0;
		
		} else {
			// Failsafe - Not in danger, but this function was called anyway.
			return 0.0;
		}
	}

	public final func GetNerveChangeFromWithdrawal() -> Float {
		if this.GetNerveWithdrawalTarget() != 100.0 {
			return (this.nerveLossInWithdrawal * -1.0) * (this.Settings.nerveLossRateInWithdrawalPct / 100.0);
		} else {
			// Failsafe - Not in withdrawal, but this function was called anyway.
			return 0.0;
		}	
	}

	public final func GetNerveRegenTarget() -> Float {
		return this.currentNerveRegenTarget;
	}

	public final func GetNerveWithdrawalTarget() -> Float {
		return this.currentNerveWithdrawalTarget;
	}

	public final func ShouldRegenDueToCriticalNerve() -> Bool {
		if this.GetNeedValue() < this.criticalNerveRegenTarget &&
			!this.PlayerStateService.GetInDanger() &&
			this.HydrationSystem.GetNeedStage() < 4 &&
			this.NutritionSystem.GetNeedStage() < 4 &&
			this.EnergySystem.GetNeedStage() < 4 {
				return true;
			}

		return false;
	}

	public final func SetNerveRegenTarget(target: Float) -> Void {
		this.currentNerveRegenTarget = ClampF(target, this.criticalNerveRegenTarget, this.GetCalculatedNeedMax());
		this.AutoSetUpdateMode();
	}

	public final func UpdateNerveWithdrawalTarget() -> Void {
		this.currentNerveWithdrawalTarget = this.GetNerveWithdrawalTargetFromProvidedState(
												this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds(), 
												this.AlcoholAddictionSystem.GetWithdrawalLevel(),
												this.NicotineAddictionSystem.GetWithdrawalLevel(),
												this.NarcoticAddictionSystem.GetWithdrawalLevel());
		this.AutoSetUpdateMode();
	}

	public final func GetNerveWithdrawalTargetFromProvidedState(addictionTreatmentDuration: Float, alcoholWithdrawalLevel: Int32, nicotineWithdrawalLevel: Int32, narcoticWithdrawalLevel: Int32) -> Float {
		let withdrawalTarget: Float = 100.0;

		if addictionTreatmentDuration > 0.0 {
			return withdrawalTarget;
		}
		
		let alcoholNerveTargets: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveTargets();
		let nicotineNerveTargets: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveTargets();
		let narcoticNerveTargets: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveTargets();

		let alcoholWithdrawalTarget = alcoholNerveTargets[alcoholWithdrawalLevel];
		let nicotineWithdrawalTarget = nicotineNerveTargets[nicotineWithdrawalLevel];
		let narcoticWithdrawalTarget = narcoticNerveTargets[narcoticWithdrawalLevel];

		withdrawalTarget = alcoholWithdrawalTarget < withdrawalTarget ? alcoholWithdrawalTarget : withdrawalTarget;
		withdrawalTarget = nicotineWithdrawalTarget < withdrawalTarget ? nicotineWithdrawalTarget : withdrawalTarget;
		withdrawalTarget = narcoticWithdrawalTarget < withdrawalTarget ? narcoticWithdrawalTarget : withdrawalTarget;

		return withdrawalTarget;
	}

	public final func GetNauseaNeedStageThreshold() -> Int32 {
		return this.nauseaNeedStageThreshold;
	}

	public final func GetHasNausea() -> Bool {
		return this.GetNeedStage() >= this.GetNauseaNeedStageThreshold();
	}

    private final func GetMemoryBoosterTraceNerveLossBonusMult() -> Float {
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.MemoryBooster") {
			return this.boosterMemoryTraceNerveLossBonusMult;
		} else if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.Blackmarket_MemoryBooster") {
			return this.boosterMemoryBlackMarketTraceNerveLossBonusMult;
		} else {
			return 0.0;
		}
	}

    public final func OnDangerStateChanged(dangerState: DFPlayerDangerState) -> Void {
		if RunGuard(this, true) { return; }

		let inDanger: Bool = this.PlayerStateService.GetInDangerFromState(dangerState);
		DFLog(this.debugEnabled, this, "OnDangerStateChanged dangerState = " + ToString(dangerState));

        if inDanger {
            DFLog(this.debugEnabled, this, "Starting danger updates");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Danger);

			// Don't immediately transition if exiting combat but still in high-anxiety situation
			if !dangerState.InCombat && this.lastDangerState.InCombat {
				this.RegisterNerveBreathingDangerTransitionCallback();
			} else {
				this.TryToTransitionNerveBreathingEffects();
			}
			
        } else {
            DFLog(this.debugEnabled, this, "Stopping danger updates");
			this.AutoSetUpdateMode();
			this.RegisterNerveBreathingDangerTransitionCallback();
        }

		this.HUDSystem.RefreshHUDUIVisibility();

        this.lastDangerState = dangerState;
    }

	private final func GetCalculatedNeedMaxInProvidedState(traumaData: DFAfflictionUpdateDatum) -> Float {
		let needMax: Float = 100.0;

		if this.TraumaSystem.IsAfflictionSuppressed(traumaData) {
			return needMax;
		}
		
		let penaltyPerStack: Float = 10.0;
		return needMax - (penaltyPerStack * Cast<Float>(traumaData.stackCount));
	}

	private final func GetCalculatedNeedMax() -> Float {
		let traumaData: DFAfflictionUpdateDatum;
		traumaData.stackCount = this.TraumaSystem.GetAfflictionStacks();
		traumaData.cureDuration = this.TraumaSystem.GetCurrentAfflictionCureDurationInGameTimeSeconds();
		traumaData.suppressionDuration = this.TraumaSystem.GetCurrentAfflictionSuppressionDurationInGameTimeSeconds();
		traumaData.hasQualifyingSuppressionActiveStatusEffect = this.TraumaSystem.HasQualifyingSuppressionActiveStatusEffect();
		return this.GetCalculatedNeedMaxInProvidedState(traumaData);
	}

	private final func TryToTransitionNerveBreathingEffects() -> Void {
		// Called due to an aim event, a delayed danger transition callback, or due to critically low Nerve.

		let needStage: Int32 = this.GetNeedStage();
		let needValue: Float = this.GetNeedValue();
		let inDanger: Bool = this.PlayerStateService.GetInDangerFromState(this.lastDangerState);

		DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects needStage = " + ToString(needStage) + ", inDanger = " + ToString(inDanger));
		
		if needStage < 3 {
			if this.currentNerveBreathingFXStage != 0 {
				DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects: Stopping breathing FX (Nerve Stage < 3)");
				this.StopNerveBreathingEffects();
			}
		} else { // needStage >= 3
			DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects this.player.m_isAiming = " + ToString(this.player.m_isAiming));
			if inDanger || this.player.m_isAiming || (needValue <= this.criticalNerveFXThreshold && needValue > 0.0) {
				if this.lastDangerState.InCombat || needValue <= this.extremelyCriticalNerveFXThreshold {
					if this.currentNerveBreathingFXStage != 2 {
						DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects: Starting high breathing FX (Nerve Stage >= 3, inDanger = true)");
						this.TransitionToNerveHighBreathingEffect();
					}
				} else {
					if this.currentNerveBreathingFXStage != 1 {
						DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects: Starting low breathing FX (Nerve Stage >= 3, inDanger = true)");
						this.TransitionToNerveLowBreathingEffect();
					}
				}
			} else {
				if this.currentNerveBreathingFXStage == 2 && needValue > 0.0 {
					DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects: Starting low breathing FX (Nerve Stage >= 3, inDanger = false)");
					this.TransitionToNerveLowBreathingEffect();

					// Register for another update to try to decay all the way down
					this.RegisterNerveBreathingDangerTransitionCallback();
				} else if this.currentNerveBreathingFXStage != 0 {
					DFLog(this.debugEnabled, this, "TryToTransitionNerveBreathingEffects: Stopping breathing FX (Nerve Stage >= 3, inDanger = false)");
					this.StopNerveBreathingEffects();
				}
			}
		}
	}

	private final func StopNerveBreathingEffects() -> Void {
		this.StopNerveBreathingLowEffect();
		this.StopNerveBreathingHighEffect();

		this.currentNerveBreathingFXStage = 0;
	}

	private final func TransitionToNerveLowBreathingEffect() -> Void {
		this.currentNerveBreathingFXStage = 1;

		// If Hydration Breathing FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.HydrationSystem.StopHydrationBreathingSFXIfBreathingFXPlaying();

		this.StopNerveBreathingHighEffect();
		this.PlayNerveBreathingLowEffect();
	}

	private final func TransitionToNerveHighBreathingEffect() -> Void {
		this.currentNerveBreathingFXStage = 2;

		// If Hydration Breathing FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.HydrationSystem.StopHydrationBreathingSFXIfBreathingFXPlaying();

		this.StopNerveBreathingLowEffect();
		this.PlayNerveBreathingHighEffect();
	}

	private final func StopNerveBreathingLowEffect() -> Void {
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"q201_sc_03_v_scared_loop_stop";
		this.player.QueueEvent(evt);
	}

	private final func StopNerveBreathingHighEffect() -> Void {
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
		evt.soundName = n"q201_sc_03_v_scared_fast_loop";
		this.player.QueueEvent(evt);
	}

	private final func PlayNerveBreathingLowEffect() -> Void {
		if this.Settings.lowNerveBreathingEffectEnabled {
			let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = n"q201_sc_03_v_scared_loop";
			this.player.QueueEvent(evt);
		}
	}

	private final func PlayNerveBreathingHighEffect() -> Void {
		if this.Settings.lowNerveBreathingEffectEnabled {
			let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = n"q201_sc_03_v_scared_fast_loop";
			this.player.QueueEvent(evt);
		}
	}

	private final func CheckForCriticalNerve() -> Void {
		let currentNerve: Float = this.GetNeedValue();
		
		if this.GameStateService.IsValidGameState("CheckForCriticalNerve") {
			if currentNerve <= 0.0 {
				if this.CyberwareService.GetHasSecondHeart() && !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.SecondHeartCooldown") {
					// Is the player's max Nerve greater than 0, does the player have a Second Heart, and is it not on a cooldown?

					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;
					this.ChangeNeedValue(this.cyberwareSecondHeartNerveRestoreAmount, uiFlags);

					StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SecondHeartNerveRestore");

				} else if this.Settings.nerveLossIsFatal {
					// Kill the player.
					this.QueuePlayerDeath();
				}
			}
		}

		if this.GameStateService.IsValidGameState("CheckForCriticalNerve", true) {
			if currentNerve > 0.0 {
				if currentNerve <= this.criticalNerveFXThreshold {
					this.PlayCriticalNerveEffects();
					this.TryToTransitionNerveBreathingEffects();
				} else {
					if this.playingCriticalNerveFX {
						this.StopCriticalNerveEffects();
						this.TryToTransitionNerveBreathingEffects();
					}
				}
			}

			if this.GetNerveRegenTarget() == 0.0 {
				if currentNerve <= this.extremelyCriticalNerveFXThreshold && this.lastNerveForCriticalFXCheck > this.extremelyCriticalNerveFXThreshold {
					this.QueueExtremelyCriticalNerveSFX();
					this.TryToTransitionNerveBreathingEffects();
					this.QueueExtremelyCriticalNerveWarningNotification();
				} else if currentNerve <= this.criticalNerveFXThreshold && this.lastNerveForCriticalFXCheck > this.criticalNerveFXThreshold {
					this.QueueCriticalNerveSFX();
					this.TryToTransitionNerveBreathingEffects();
					this.QueueCriticalNerveWarningNotification();
				}
			}
			
			this.lastNerveForCriticalFXCheck = currentNerve;
		}
	}

	private final func QueueCriticalNerveWarningNotification() -> Void {
		if this.GameStateService.IsValidGameState("QueueCriticalNerveWarningNotification", true) {
			let message: DFMessage;
			message.key = n"DarkFutureCriticalNerveHighNotification";
			message.type = SimpleMessageType.Negative;
			message.context = DFMessageContext.Need;

			this.NotificationService.QueueMessage(message);
		}
	}

	private final func QueueExtremelyCriticalNerveWarningNotification() -> Void {
		if this.GameStateService.IsValidGameState("QueueExtremelyCriticalNerveWarningNotification", true) {
			let message: DFMessage;
			message.key = n"DarkFutureCriticalNerveLowNotification";
			message.type = SimpleMessageType.Negative;
			message.context = DFMessageContext.Need;

			this.NotificationService.QueueMessage(message);
		}
	}

	private final func QueuePlayerDeath() -> Void {
		// :(
		
		this.PlayCriticalNerveEffects();
		this.TryToTransitionNerveBreathingEffects();
		this.HydrationSystem.StopHydrationBreathingSFX();

		this.QueueCriticalNerveSFXDeath();
		this.RegisterPlayerDeathCallback();
	}

	private final func PlayCriticalNerveEffects() -> Void {
		if !this.playingCriticalNerveFX {
			this.playingCriticalNerveFX = true;
			this.AudioSystem.NotifyGameTone(n"InLowHealth");
			this.PlayCriticalNerveVFX();
		}
		
	}

	private final func StopCriticalNerveEffects(opt force: Bool) -> Void {
		if this.playingCriticalNerveFX || force {
			this.playingCriticalNerveFX = false;
			this.AudioSystem.NotifyGameTone(n"InNormalHealth");
			this.StopCriticalNerveVFX();
		}
	}

	private final func QueueCriticalNerveSFX() -> Void {
		if this.Settings.needNegativeSFXEnabled {
			let notification: DFNotification;
			notification.sfx = new DFAudioCue(n"ono_v_knock_down", 0);
			this.NotificationService.QueueNotification(notification);
		}
	}

	private final func QueueExtremelyCriticalNerveSFX() -> Void {
		if this.Settings.needNegativeSFXEnabled {
			let notification: DFNotification;
			notification.sfx = new DFAudioCue(n"ono_v_death_short", 0);
			this.NotificationService.QueueNotification(notification);
		}
	}

	private final func QueueCriticalNerveSFXDeath() -> Void {
		let notification: DFNotification;
		notification.sfx = new DFAudioCue(n"ono_v_death_long", -10);
		this.NotificationService.QueueNotification(notification);
	}

	private final func PlayCriticalNerveVFX() -> Void {
		if this.Settings.criticalNerveVFXEnabled {
			GameObjectEffectHelper.StartEffectEvent(this.player, n"cool_perk_focused_state_fullscreen", false, null, true);
		}
	}

	private final func StopCriticalNerveVFX() -> Void {
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"cool_perk_focused_state_fullscreen");
	}

	public final func OnUpperBodyStateChange() -> Void {
		if this.GameStateService.IsValidGameState("OnUpperBodyStateChange", true) {
			this.TryToTransitionNerveBreathingEffects();
			this.UpdateWeaponShake();
		}
	}

	public final func OnPlayerDeathCallback() -> Void {
		// This kills the player.
		StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.HeartAttack");
	}

	public final func OnUpdateFromNerveRegen() -> Void {
		// Allow Nerve to regenerate slowly in real-time.
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		if this.GetNerveRegenTarget() < 100.0 {
			this.ChangeNeedValue(this.nerveRegenAmountSlow, uiFlags);
		} else {
			this.ChangeNeedValue(this.nerveRegenAmountRapid, uiFlags);
		}
		
		this.AutoSetUpdateMode();
	}

	public final func OnNerveBreathingDangerTransitionCallback() -> Void {
		this.TryToTransitionNerveBreathingEffects();
	}

	public final func OnUpdateFromDanger() -> Void {
		if this.GameStateService.IsValidGameState("OnUpdateFromDanger") {
			this.ChangeNeedValue(this.GetNerveChangeFromDanger());

			// Registration managed by calls to SetUpdateMode() / AutoSetUpdateMode()
			this.RegisterDangerUpdateCallback();
		}
	}

	public final func OnUpdateFromWithdrawal() -> Void {
		if this.GameStateService.IsValidGameState("OnUpdateFromWithdrawal") {
			let withdrawalTarget: Float = this.GetNerveWithdrawalTarget();
			let needValue: Float = this.GetNeedValue();
			if withdrawalTarget != 100.0 && needValue > withdrawalTarget {
				let amount: Float = this.GetNerveChangeFromWithdrawal();
				let keepUpdating: Bool = true;

				if needValue - amount < withdrawalTarget {
					amount = needValue - withdrawalTarget;
					keepUpdating = false;
				}
				this.ChangeNeedValue(amount);
				
				if keepUpdating {
					this.RegisterWithdrawalUpdateCallback();
				} else {
					this.AutoSetUpdateMode();
				}
			} else {
				this.AutoSetUpdateMode();
			}
		}
	}

	public final func OnVehicleKnockdown() -> Void {
		if this.GameStateService.IsValidGameState("OnVehicleKnockdown") {
			DFLog(this.debugEnabled, this, "OnVehicleKnockdown");

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			this.ChangeNeedValue(-(this.nerveAmountOnVehicleKnockdown), uiFlags, true);
		}
	}

	//
	//	Weapon Effects
	//
	public final func UpdateWeaponShake() -> Void {
		let hasFocusActive: Bool = StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.FocusedCoolPerkSE");
		let hasNervesOfTungstenSteel: Bool = PlayerDevelopmentSystem.GetData(this.player).IsNewPerkBoughtAnyLevel(gamedataNewPerkType.Cool_Master_Perk_1);
		let ignoreWeaponShake: Bool = hasFocusActive && hasNervesOfTungstenSteel;
		
		if this.player.m_isAiming && !ignoreWeaponShake {
			let needStage: Int32 = this.GetNeedStage();
			if needStage == 2 {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_02_WeaponEffects");
			} else if needStage == 3 {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_03_WeaponEffects");
			} else if needStage == 4 {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_04_WeaponEffects");
			}
		} else {
			StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_02_WeaponEffects");
			StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_03_WeaponEffects");
			StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.NervePenalty_04_WeaponEffects");
		}
	}

	//
	//	Registration
	//
	private final func RegisterDangerUpdateCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, DangerUpdateDelayCallback.Create(), this.dangerUpdateDelayID, this.dangerUpdateDelayInterval);
	}

	private final func RegisterWithdrawalUpdateCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, WithdrawalUpdateDelayCallback.Create(), this.withdrawalUpdateDelayID, this.withdrawalUpdateDelayInterval);
	}

	private final func RegisterNerveBreathingDangerTransitionCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NerveBreathingDangerTransitionCallback.Create(), this.nerveBreathingDangerTransitionDelayID, this.nerveBreathingDangerTransitionDelayInterval);
	}

	private final func RegisterNerveRegenCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NerveRegenCallback.Create(), this.nerveRegenDelayID, this.nerveRegenDelayInterval);
	}

	private final func RegisterPlayerDeathCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, PlayerDeathCallback.Create(), this.playerDeathDelayID, this.playerDeathDelayInterval);
	}

	//
	//	Unregistration
	//
	private final func UnregisterDangerUpdateCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.dangerUpdateDelayID);
	}

	private final func UnregisterWithdrawalUpdateCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.withdrawalUpdateDelayID);
	}

	private final func UnregisterNerveBreathingDangerTransitionCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.nerveBreathingDangerTransitionDelayID);
	}

	private final func UnregisterNerveRegenCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.nerveRegenDelayID);
	}

	private final func UnregisterPlayerDeathCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.playerDeathDelayID);
	}
}
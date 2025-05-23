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
	DFNeedChangeDatum,
	DFTimeSkipData
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
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
	DFHUDBarType,
	DFNeedsHUDBar
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

		} else if DFGameStateService.Get().IsValidGameState(this) && Equals(effectID, t"BaseStatusEffect.FocusedCoolPerkSE") {
			nerveSystem.UpdateWeaponShake();

		} else if Equals(effectID, t"HousingStatusEffect.Refreshed") {
        	nerveSystem.RegisterBonusEffectCheckCallback();

		}
	}
    
	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();

	if IsSystemEnabledAndRunning(nerveSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();
		if DFGameStateService.Get().IsValidGameState(this) && Equals(effectID, t"BaseStatusEffect.FocusedCoolPerkSE") {
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

public class PostPlayerDeathCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new PostPlayerDeathCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNerveSystem.Get().postPlayerDeathDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNerveSystem.Get().OnPostPlayerDeathCallback();
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

	private let nerveAmountOnVehicleKnockdown: Float = 2.0;
	private let nerveLossInDanger: Float = 0.25;
	private let nerveRegenAmountRapid: Float = 1.0;
	private let nerveRegenAmountSlow: Float = 0.05;
	private let criticalNerveRegenTarget: Float = 10.0;
	private let criticalNerveFXThreshold: Float = 10.0;
	private let extremelyCriticalNerveFXThreshold: Float = 5.0;
	private let playingCriticalNerveFX: Bool = false;
	private let nauseaNeedStageThreshold: Int32 = 4;
	private let insomniaNeedStageThreshold: Int32 = 3;
	private let nerveRecoverAmountSleeping: Float = 0.083333334;
	private let nerveRecoverAmountSleepingMax: Float = 100.0;
	
	private let nerveRestoreInFuryOnKill: Float = 1.0;
	private let sedatedNerveLossBonusMult: Float = 0.35;
    private let boosterMemoryTraceNerveLossBonusMult: Float = 0.25;
	private let boosterMemoryBlackMarketTraceNerveLossBonusMult: Float = 0.35;

	private let currentNerveBreathingFXStage: Int32 = 0;

	private let dangerUpdateDelayID: DelayID;
	private let withdrawalUpdateDelayID: DelayID;
	private let nerveBreathingDangerTransitionDelayID: DelayID;
	private let nerveRegenDelayID: DelayID;
	private let playerDeathDelayID: DelayID;
	private let postPlayerDeathDelayID: DelayID;

	private let updateMode: DFNerveSystemUpdateMode = DFNerveSystemUpdateMode.Time;

	private let dangerUpdateDelayInterval: Float = 5.0;
	private let withdrawalUpdateDelayInterval: Float = 5.0;
	private let nerveBreathingDangerTransitionDelayInterval: Float = 10.0;
	private let nerveRegenDelayInterval: Float = 0.25;
	private let playerDeathDelayInterval: Float = 2.0;
	private let postPlayerDeathDelayInterval: Float = 8.0;

	private let inDeathState: Bool = false;

	private let lastDangerState: DFPlayerDangerState;

	private let lastNerveForCriticalFXCheck: Float = 100.0;
	private let cyberwareSecondHeartNerveRestoreAmount: Float = 10.0;

	// Regen
	private let currentNerveRegenTarget: Float = 10.0; // Default: criticalNerveRegenTarget
	private let currentNerveWithdrawalLimit: Float = 100.0;

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
		this.UpdateNerveWithdrawalLimit();
	}

	private func DoPostSuspendActions() -> Void {
		super.DoPostSuspendActions();
		this.StopCriticalNerveEffects(true);
		this.StopNerveBreathingEffects();
		this.lastDangerState = new DFPlayerDangerState(false, false);
		this.lastNerveForCriticalFXCheck = 100.0;
		this.currentNerveRegenTarget = this.criticalNerveRegenTarget;
		this.currentNerveWithdrawalLimit = 100.0;
	}

	private func DoPostResumeActions() -> Void {
		super.DoPostResumeActions();
		this.CheckForCriticalNerve();
		this.UpdateNerveWithdrawalLimit();
	}

	public final func OnTimeSkipStart() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.SetUpdateMode(DFNerveSystemUpdateMode.Suspended);
		this.UnregisterAllNeedFXCallbacks();
	}

	public final func OnTimeSkipCancelled() -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState(this, true) {
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState(this, true) {
			this.OnTimeSkipFinishedActual(data);
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	private func UnregisterAllDelayCallbacks() -> Void {
		super.UnregisterAllDelayCallbacks();

		this.UnregisterDangerUpdateCallback();
		this.UnregisterNerveBreathingDangerTransitionCallback();
		this.UnregisterNerveRegenCallback();
		this.UnregisterPlayerDeathCallback();
	}

    //
	//  Required Overrides
	//
    private final func OnUpdateActual() -> Void {
		DFLog(this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetNerveChangeFromTimeInProvidedState(this.GetNeedValue(), this.HydrationSystem.GetNeedStage(), this.NutritionSystem.GetNeedStage(), this.EnergySystem.GetNeedStage()));
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		DFLog(this, "OnTimeSkipFinishedActual");

		let currentValue: Float = this.GetNeedValue();

		if currentValue < data.targetNeedValues.nerve.ceiling {
			this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nerve.value - currentValue);
		} else {
			this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nerve.value - data.targetNeedValues.nerve.ceiling);
		}
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		if itemRecord.TagsContains(n"DarkFutureConsumableNerveNoCombat") && this.player.IsInCombat() {
			return;
		}

		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);
		if consumableNeedsData.nerve.value != 0.0 {
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;
			let isNicotine: Bool = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNicotine");
			
			let clampedValue: Float = this.GetClampedNeedChangeFromData(consumableNeedsData.nerve);
			this.ChangeNeedValue(clampedValue, uiFlags, isNicotine, this.GetNerveLimitAfterItemUse(itemRecord));

			// If Nerve is increasing, and this is a narcotic, play a sound effect.
			if clampedValue >= 1.0 && itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNarcotic") && this.Settings.narcoticsSFXEnabled {
				let notification: DFNotification;
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_laughs_soft", 10);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_laughs_hard", 10);
				}
				this.NotificationService.QueueNotification(notification);
			}
		}
	}

	public final func GetNerveLimitAfterItemUse(itemRecord: wref<Item_Record>) -> Float {
		let updatedNerveMax: Float = 100.0;

		if IsDefined(itemRecord) {
			// If currently affected by Addiction Treatment, the max is always 100.0.
			let addictionTreatmentDuration: Float = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();
			if addictionTreatmentDuration > 0.0 {
				return 100.0;
			}

			if itemRecord.TagsContains(n"DarkFutureConsumableAddictionTreatmentDrug") {
				return 100.0;
			}

			let alcoholWithdrawalLevel: Int32 = this.AlcoholAddictionSystem.GetWithdrawalLevel();
			if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcohol") {
				let alcoholStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"BaseStatusEffect.Drunk");
				let newAlcoholStackCount: Uint32;
				if IsDefined(alcoholStatus) {
					newAlcoholStackCount = alcoholStatus.GetStackCount() + 1u;
				} else {
					newAlcoholStackCount = 1u;
				}
				let minStacksPerStage: array<Uint32> = this.AlcoholAddictionSystem.GetAddictionMinStacksPerStage();
				if newAlcoholStackCount >= minStacksPerStage[this.AlcoholAddictionSystem.GetAddictionStage()] {
					alcoholWithdrawalLevel = 0;
				}
			}
			let nicotineWithdrawalLevel: Int32 = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNicotine") ? 0 : this.NicotineAddictionSystem.GetWithdrawalLevel();
			let narcoticWithdrawalLevel: Int32 = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNarcotic") ? 0 : this.NarcoticAddictionSystem.GetWithdrawalLevel();

			let alcoholLimits: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveLimits();
			let nicotineLimits: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveLimits();
			let narcoticLimits: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveLimits();

			let newAlcoholLimit: Float = alcoholLimits[alcoholWithdrawalLevel];
			let newNicotineLimit: Float = nicotineLimits[nicotineWithdrawalLevel];
			let newNarcoticLimit: Float = narcoticLimits[narcoticWithdrawalLevel];

			updatedNerveMax = newAlcoholLimit < updatedNerveMax ? newAlcoholLimit : updatedNerveMax;
			updatedNerveMax = newNicotineLimit < updatedNerveMax ? newNicotineLimit : updatedNerveMax;
			updatedNerveMax = newNarcoticLimit < updatedNerveMax ? newNarcoticLimit : updatedNerveMax;
		}

		return updatedNerveMax;
	}

	public final func GetNerveLimitAfterAlcoholUse() -> Float {
		// This function helps work around a race condition when consuming alcohol and satisfying an alcohol addiction.
		// Due to this, some Nerve that would be restored when satisfying the addiction would be "thrown away" otherwise.
		// Predict what the Nerve limit would be if specifically one alcohol item were consumed and use that result
		// as a Nerve Max Override in the ChangeNeedValue() function call in ApplyBaseAlcoholNerveValueChange().

		let updatedNerveMax: Float = 100.0;

		// If currently affected by Addiction Treatment, the max is always 100.0.
		let addictionTreatmentDuration: Float = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();
		if addictionTreatmentDuration > 0.0 {
			return 100.0;
		}

		let alcoholWithdrawalLevel: Int32 = this.AlcoholAddictionSystem.GetWithdrawalLevel();
		let alcoholStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"BaseStatusEffect.Drunk");
		let newAlcoholStackCount: Uint32;
		if IsDefined(alcoholStatus) {
			// By the time this function is checked, the new alcohol stack has already applied. Take the stack
			// count directly.
			newAlcoholStackCount = alcoholStatus.GetStackCount();
		} else {
			newAlcoholStackCount = 1u;
		}
		let minStacksPerStage: array<Uint32> = this.AlcoholAddictionSystem.GetAddictionMinStacksPerStage();
		if newAlcoholStackCount >= minStacksPerStage[this.AlcoholAddictionSystem.GetAddictionStage()] {
			alcoholWithdrawalLevel = 0;
		}

		let nicotineWithdrawalLevel: Int32 = this.NicotineAddictionSystem.GetWithdrawalLevel();
		let narcoticWithdrawalLevel: Int32 = this.NarcoticAddictionSystem.GetWithdrawalLevel();

		let alcoholLimits: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveLimits();
		let nicotineLimits: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveLimits();
		let narcoticLimits: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveLimits();

		let newAlcoholLimit: Float = alcoholLimits[alcoholWithdrawalLevel];
		let newNicotineLimit: Float = nicotineLimits[nicotineWithdrawalLevel];
		let newNarcoticLimit: Float = narcoticLimits[narcoticWithdrawalLevel];

		updatedNerveMax = newAlcoholLimit < updatedNerveMax ? newAlcoholLimit : updatedNerveMax;
		updatedNerveMax = newNicotineLimit < updatedNerveMax ? newNicotineLimit : updatedNerveMax;
		updatedNerveMax = newNarcoticLimit < updatedNerveMax ? newNarcoticLimit : updatedNerveMax;

		return updatedNerveMax;
	}

	private final func GetNeedHUDBarType() -> DFHUDBarType {
		return DFHUDBarType.Nerve;
	}

	private final func GetNeedType() -> DFNeedType {
		return DFNeedType.Nerve;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;

		// Allow Nerve notifications to play during combat.
		notification.allowPlaybackInCombat = true;

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
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = new DFAudioCue(n"ono_v_music_start", 30);
				} else {
					notification.sfx = new DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				}
				
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
		DFLog(this, "CheckIfBonusEffectsValid");

		if this.GameStateService.IsValidGameState(this, true) {
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

	private func GetHasShownTutorialForNeed() -> Bool {
		return this.PlayerStateService.hasShownNerveTutorial;
	}

	private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		this.PlayerStateService.hasShownNerveTutorial = hasShownTutorial;
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
	public final func ChangeNeedValue(amount: Float, opt uiFlags: DFNeedChangeUIFlags, opt suppressRecoveryNotification: Bool, opt maxOverride: Float) -> Void {
		if RunGuard(this) { return; }
		DFLog(this, "ChangeNeedValue: amount = " + ToString(amount) + ", uiFlags = " + ToString(uiFlags));

		let needMax: Float = maxOverride > 0.0 ? maxOverride : this.GetCalculatedNeedMax();
		this.needValue = ClampF(this.needValue + amount, 0.0, needMax);
		this.needMax = needMax;
		this.UpdateNeedHUDUI(uiFlags.forceMomentaryUIDisplay, uiFlags.instantUIChange, uiFlags.forceBright, uiFlags.momentaryDisplayIgnoresSceneTier);

		let stage: Int32 = this.GetNeedStage();
		if NotEquals(stage, this.lastNeedStage) {
			DFLog(this, "ChangeNeedValue: Last Need stage (" + ToString(this.lastNeedStage) + ") != current stage (" + ToString(stage) + "). Refreshing status effects and FX.");
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

		this.DispatchNeedValueChangedEvent(this.needValue);
		DFLog(this, "ChangeNeedValue: New needValue = " + ToString(this.needValue));
	}

    //
    //  System-Specific Methods
    //
	public final func SetUpdateMode(mode: DFNerveSystemUpdateMode) -> Void {
		if RunGuard(this) { return; }
		
		DFLog(this, "---- SetUpdateMode ----");
		this.updateMode = mode;

		if Equals(mode, DFNerveSystemUpdateMode.Time) {
			DFLog(this, "     Setting mode: Time");
			this.RegisterUpdateCallback();
		} else {
			this.UnregisterUpdateCallback();
		}
		
		if Equals(mode, DFNerveSystemUpdateMode.Danger) {
			DFLog(this, "     Setting mode: Danger");
			this.RegisterDangerUpdateCallback();
		} else {
			this.UnregisterDangerUpdateCallback();
		}

		if Equals(mode, DFNerveSystemUpdateMode.Regen) {
			DFLog(this, "     Setting mode: Regen");
			this.RegisterNerveRegenCallback();
		} else {
			this.UnregisterNerveRegenCallback();
		}

		if Equals(mode, DFNerveSystemUpdateMode.Suspended) {
			DFLog(this, "     Setting mode: Suspended");
		}
	}

	public final func ApplyBaseAlcoholNerveValueChange() -> Void {
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		this.ChangeNeedValue(this.Settings.nerveAlcoholTier1, uiFlags, false, this.GetNerveLimitAfterAlcoholUse());
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

		DFLog(this, "---- AutoSetUpdateMode ----");
		let inDanger: Bool = this.PlayerStateService.GetInDanger();
		let regenTarget: Float = this.GetNerveRegenTarget();
		let regen: Bool = this.GetNeedValue() < regenTarget && (Equals(regenTarget, this.GetNeedMax()) || (this.HydrationSystem.GetNeedStage() < 4 && this.NutritionSystem.GetNeedStage() < 4 && this.EnergySystem.GetNeedStage() < 4));

		DFLog(this, "inDanger: " + ToString(inDanger));
		DFLog(this, "regenTarget: " + ToString(regenTarget));
		DFLog(this, "regen: " + ToString(regen));

		if inDanger {
			DFLog(this, "     Setting mode: Danger");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Danger);

		} else if regen {
			DFLog(this, "     Setting mode: Regen");
			DFLog(this, "     Setting mode: Target: " + regenTarget);
			this.SetUpdateMode(DFNerveSystemUpdateMode.Regen);

		} else {
			DFLog(this, "     Setting mode: Time");
			this.SetUpdateMode(DFNerveSystemUpdateMode.Time);
		}

		DFHUDSystem.Get().nerveBar.SetInDanger(inDanger);
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
		}

		// Not depleting.
		return 0.0;
	}

    public final func GetNerveChangeFromDanger() -> Float {
		let baseNerveLossInDanger: Float;
		let nerveLossBonusMult: Float = 1.0;

		if this.lastDangerState.InCombat {
			baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateInCombatPct / 100.0)) * -1.0;
			nerveLossBonusMult -= this.GetSedationNerveLossBonusMult();

		} else if this.lastDangerState.BeingRevealed {
			baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateWhenTracedPct / 100.0)) * -1.0;
			nerveLossBonusMult -= this.GetMemoryBoosterTraceNerveLossBonusMult();

		}

		if this.lastDangerState.InCombat || this.lastDangerState.BeingRevealed {
			let totalNerveLossBonusMult: Float = MaxF(nerveLossBonusMult, 0.0);
			let totalNerveLoss: Float = baseNerveLossInDanger * totalNerveLossBonusMult;
			DFLog(this, "GetNerveChangeFromDanger() totalNerveLossBonusMult:" + ToString(totalNerveLossBonusMult) + ", totalNerveLoss:" + ToString(totalNerveLoss));

			return totalNerveLoss;
		
		} else {
			// Failsafe - Not in danger, but this function was called anyway.
			return 0.0;
		}
	}

	public final func GetNerveRegenTarget() -> Float {
		return this.currentNerveRegenTarget;
	}

	public final func GetNerveWithdrawalLimit() -> Float {
		return this.currentNerveWithdrawalLimit;
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

	public final func UpdateNerveWithdrawalLimit() -> Void {
		this.currentNerveWithdrawalLimit = this.GetNerveWithdrawalLimitFromProvidedState(
												this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds(), 
												this.AlcoholAddictionSystem.GetWithdrawalLevel(),
												this.NicotineAddictionSystem.GetWithdrawalLevel(),
												this.NarcoticAddictionSystem.GetWithdrawalLevel());
		this.ForceNeedMaxValueUpdate();
	}

	private final func ForceNeedMaxValueUpdate() -> Void {
		this.ChangeNeedValue(0.0);
	}

	public final func GetNerveWithdrawalLimitFromProvidedState(addictionTreatmentDuration: Float, alcoholWithdrawalLevel: Int32, nicotineWithdrawalLevel: Int32, narcoticWithdrawalLevel: Int32) -> Float {
		let withdrawalTarget: Float = 100.0;

		if addictionTreatmentDuration > 0.0 {
			return withdrawalTarget;
		}
		
		let alcoholNerveTargets: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveLimits();
		let nicotineNerveTargets: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveLimits();
		let narcoticNerveTargets: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveLimits();

		let alcoholWithdrawalTarget = alcoholNerveTargets[alcoholWithdrawalLevel];
		let nicotineWithdrawalTarget = nicotineNerveTargets[nicotineWithdrawalLevel];
		let narcoticWithdrawalTarget = narcoticNerveTargets[narcoticWithdrawalLevel];

		withdrawalTarget = alcoholWithdrawalTarget < withdrawalTarget ? alcoholWithdrawalTarget : withdrawalTarget;
		withdrawalTarget = nicotineWithdrawalTarget < withdrawalTarget ? nicotineWithdrawalTarget : withdrawalTarget;
		withdrawalTarget = narcoticWithdrawalTarget < withdrawalTarget ? narcoticWithdrawalTarget : withdrawalTarget;

		return withdrawalTarget;
	}

	public final func GetHasNausea() -> Bool {
		return this.GetNeedStage() >= this.nauseaNeedStageThreshold;
	}

    private final func GetMemoryBoosterTraceNerveLossBonusMult() -> Float {
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.Blackmarket_MemoryBooster") {
			return this.boosterMemoryBlackMarketTraceNerveLossBonusMult;
		} else if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.MemoryBooster") {
			return this.boosterMemoryTraceNerveLossBonusMult; 
		} else {
			return 0.0;
		}
	}

	private final func GetSedationNerveLossBonusMult() -> Float {
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.Sedation") {
			return this.sedatedNerveLossBonusMult;
		} else {
			return 0.0;
		}
	}

    public final func OnDangerStateChanged(dangerState: DFPlayerDangerState) -> Void {
		if RunGuard(this, true) { return; }

		let inDanger: Bool = this.PlayerStateService.GetInDangerFromState(dangerState);
		DFLog(this, "OnDangerStateChanged dangerState = " + ToString(dangerState));

        if inDanger {
            DFLog(this, "Starting danger updates");

			// Don't immediately transition if exiting combat but still in high-anxiety situation
			if !dangerState.InCombat && this.lastDangerState.InCombat {
				this.RegisterNerveBreathingDangerTransitionCallback();
			} else {
				this.TryToTransitionNerveBreathingEffects();
			}
			
        } else {
			this.RegisterNerveBreathingDangerTransitionCallback();
        }

		this.AutoSetUpdateMode();
		this.HUDSystem.RefreshHUDUIVisibility();
        this.lastDangerState = dangerState;
    }

	private final func GetCalculatedNeedMaxInProvidedState(addictionTreatmentDuration: Float, alcoholWithdrawalLevel: Int32, nicotineWithdrawalLevel: Int32, narcoticWithdrawalLevel: Int32) -> Float {
		let needMax: Float = 100.0;

		if addictionTreatmentDuration > 0.0 {
			return needMax;
		}
		
		let alcoholNerveLimits: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveLimits();
		let nicotineNerveLimits: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveLimits();
		let narcoticNerveLimits: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveLimits();

		let alcoholWithdrawalLimit = alcoholNerveLimits[alcoholWithdrawalLevel];
		let nicotineWithdrawalLimit = nicotineNerveLimits[nicotineWithdrawalLevel];
		let narcoticWithdrawalLimit = narcoticNerveLimits[narcoticWithdrawalLevel];

		needMax = alcoholWithdrawalLimit < needMax ? alcoholWithdrawalLimit : needMax;
		needMax = nicotineWithdrawalLimit < needMax ? nicotineWithdrawalLimit : needMax;
		needMax = narcoticWithdrawalLimit < needMax ? narcoticWithdrawalLimit : needMax;

		return needMax;
	}

	private final func GetCalculatedNeedMax() -> Float {
		let addictionTreatmentDuration: Float = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();
		let alcoholWithdrawalLevel: Int32 = this.AlcoholAddictionSystem.GetWithdrawalLevel();
		let nicotineWithdrawalLevel: Int32 = this.NicotineAddictionSystem.GetWithdrawalLevel();
		let narcoticWithdrawalLevel: Int32 = this.NarcoticAddictionSystem.GetWithdrawalLevel();

		return this.GetCalculatedNeedMaxInProvidedState(addictionTreatmentDuration, alcoholWithdrawalLevel, nicotineWithdrawalLevel, narcoticWithdrawalLevel);
	}

	private final func TryToTransitionNerveBreathingEffects() -> Void {
		// Called due to an aim event, a delayed danger transition callback, or due to critically low Nerve.

		let needStage: Int32 = this.GetNeedStage();
		let needValue: Float = this.GetNeedValue();
		let inDanger: Bool = this.PlayerStateService.GetInDangerFromState(this.lastDangerState);

		DFLog(this, "TryToTransitionNerveBreathingEffects needStage = " + ToString(needStage) + ", inDanger = " + ToString(inDanger));
		
		if needStage < 3 {
			if this.currentNerveBreathingFXStage != 0 {
				DFLog(this, "TryToTransitionNerveBreathingEffects: Stopping breathing FX (Nerve Stage < 3)");
				this.StopNerveBreathingEffects();
			}
		} else { // needStage >= 3
			DFLog(this, "TryToTransitionNerveBreathingEffects this.player.m_isAiming = " + ToString(this.player.m_isAiming));
			if inDanger || this.player.m_isAiming || (needValue <= this.criticalNerveFXThreshold && needValue > 0.0) {
				if this.lastDangerState.InCombat || needValue <= this.extremelyCriticalNerveFXThreshold {
					if this.currentNerveBreathingFXStage != 2 {
						DFLog(this, "TryToTransitionNerveBreathingEffects: Starting high breathing FX (Nerve Stage >= 3, inDanger = true)");
						this.TransitionToNerveHighBreathingEffect();
					}
				} else {
					if this.currentNerveBreathingFXStage != 1 {
						DFLog(this, "TryToTransitionNerveBreathingEffects: Starting low breathing FX (Nerve Stage >= 3, inDanger = true)");
						this.TransitionToNerveLowBreathingEffect();
					}
				}
			} else {
				if this.currentNerveBreathingFXStage == 2 && needValue > 0.0 {
					DFLog(this, "TryToTransitionNerveBreathingEffects: Starting low breathing FX (Nerve Stage >= 3, inDanger = false)");
					this.TransitionToNerveLowBreathingEffect();

					// Register for another update to try to decay all the way down
					this.RegisterNerveBreathingDangerTransitionCallback();
				} else if this.currentNerveBreathingFXStage != 0 {
					DFLog(this, "TryToTransitionNerveBreathingEffects: Stopping breathing FX (Nerve Stage >= 3, inDanger = false)");
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

		// If Out Of Breath FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.PlayerStateService.StopOutOfBreathSFXIfBreathingFXPlaying();

		this.StopNerveBreathingHighEffect();
		this.PlayNerveBreathingLowEffect();
	}

	private final func TransitionToNerveHighBreathingEffect() -> Void {
		this.currentNerveBreathingFXStage = 2;

		// If Out Of Breath FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.PlayerStateService.StopOutOfBreathSFXIfBreathingFXPlaying();

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
		if this.inDeathState { return; }

		let currentNerve: Float = this.GetNeedValue();
		
		if this.GameStateService.IsValidGameState(this) {
			if currentNerve <= 0.0 && this.Settings.nerveLossIsFatal {
				if this.CyberwareService.GetHasSecondHeart() && !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.SecondHeartCooldown") {
					// Is the player's max Nerve greater than 0, does the player have a Second Heart, and is it not on a cooldown?

					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;
					this.ChangeNeedValue(this.cyberwareSecondHeartNerveRestoreAmount, uiFlags);

					StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SecondHeartNerveRestore");

				} else {
					// Kill the player.
					this.QueuePlayerDeath();
				}
			}
		}

		if this.GameStateService.IsValidGameState(this, true, true) {
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
		if this.GameStateService.IsValidGameState(this, true) {
			let message: DFMessage;
			message.key = n"DarkFutureCriticalNerveHighNotification";
			message.type = SimpleMessageType.Negative;
			message.context = DFMessageContext.Need;

			this.NotificationService.QueueMessage(message);
		}
	}

	private final func QueueExtremelyCriticalNerveWarningNotification() -> Void {
		if this.GameStateService.IsValidGameState(this, true) {
			let message: DFMessage;
			message.key = n"DarkFutureCriticalNerveLowNotification";
			message.type = SimpleMessageType.Negative;
			message.context = DFMessageContext.Need;

			this.NotificationService.QueueMessage(message);
		}
	}

	private final func QueuePlayerDeath() -> Void {
		// :(
		
		this.inDeathState = true;
		this.PlayCriticalNerveEffects();
		this.TryToTransitionNerveBreathingEffects();
		this.PlayerStateService.StopOutOfBreathSFX();

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
		if this.GameStateService.IsValidGameState(this, true) {
			this.TryToTransitionNerveBreathingEffects();
			this.UpdateWeaponShake();
		}
	}

	public final func OnPlayerDeathCallback() -> Void {
		// This kills the player.
		StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.HeartAttack");

		// Register for post-death recovery. (Santa Muerte Compatibility)
		this.RegisterPostPlayerDeathCallback();
	}

	public final func OnPostPlayerDeathCallback() -> Void {
		StatusEffectHelper.RemoveStatusEffect(this.player, t"BaseStatusEffect.HeartAttack");
		this.inDeathState = false;
		this.TryToTransitionNerveBreathingEffects();
		
		// Restore a modest amount of Nerve.
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		if this.GetNeedValue() < this.cyberwareSecondHeartNerveRestoreAmount {
			this.ChangeNeedValue(this.cyberwareSecondHeartNerveRestoreAmount - this.GetNeedValue(), uiFlags);
		}
	}

	public final func OnUpdateFromNerveRegen() -> Void {
		// Allow Nerve to regenerate slowly in real-time.
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		if this.GetNerveRegenTarget() < this.GetNeedMax() {
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
		if this.GameStateService.IsValidGameState(this) {
			this.ChangeNeedValue(this.GetNerveChangeFromDanger());
		}

		this.AutoSetUpdateMode();
	}

	public final func OnVehicleKnockdown() -> Void {
		if this.GameStateService.IsValidGameState(this) {
			DFLog(this, "OnVehicleKnockdown");

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			this.ChangeNeedValue(-(this.nerveAmountOnVehicleKnockdown), uiFlags);
		}
	}

	//
	//	Weapon Effects
	//
	public final func UpdateWeaponShake() -> Void {
		let hasFocusActive: Bool = StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.FocusedCoolPerkSE");
		let hasNervesOfTungstenSteel: Bool = PlayerDevelopmentSystem.GetData(this.player).IsNewPerkBoughtAnyLevel(gamedataNewPerkType.Cool_Master_Perk_1);
		let ignoreWeaponShake: Bool = !this.Settings.nerveWeaponSwayEnabled || (hasFocusActive && hasNervesOfTungstenSteel);
		
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

	private final func RegisterNerveBreathingDangerTransitionCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NerveBreathingDangerTransitionCallback.Create(), this.nerveBreathingDangerTransitionDelayID, this.nerveBreathingDangerTransitionDelayInterval);
	}

	private final func RegisterNerveRegenCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, NerveRegenCallback.Create(), this.nerveRegenDelayID, this.nerveRegenDelayInterval);
	}

	private final func RegisterPlayerDeathCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, PlayerDeathCallback.Create(), this.playerDeathDelayID, this.playerDeathDelayInterval);
	}

	private final func RegisterPostPlayerDeathCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, PostPlayerDeathCallback.Create(), this.postPlayerDeathDelayID, this.postPlayerDeathDelayInterval);
	}

	//
	//	Unregistration
	//
	private final func UnregisterDangerUpdateCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.dangerUpdateDelayID);
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
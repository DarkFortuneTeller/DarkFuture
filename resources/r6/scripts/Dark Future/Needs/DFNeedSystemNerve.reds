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
	DFRunGuard,
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
import DarkFuture.Conditions.DFHumanityLossConditionSystem
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
	DFNotificationCallback,
	GameState,
	DFFactNameValue
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
	//DFProfile();
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
	//DFProfile();
    let nerveSystem: ref<DFNerveSystem> = DFNerveSystem.Get();

	if IsSystemEnabledAndRunning(nerveSystem) {
		let effectID: TweakDBID = evt.staticData.GetID();

		if DFGameStateService.Get().IsValidGameState(this) && Equals(effectID, t"BaseStatusEffect.FocusedCoolPerkSE") {
			nerveSystem.UpdateWeaponShake();
		}
    }

	return wrappedMethod(evt);
}

// TODOLOCK
@wrapMethod(PlayerPuppet)
protected cb func OnUpperBodyStateChange(newState: Int32) -> Bool {
	//DFProfile();
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
	//DFProfile();
	let val: Bool = wrappedMethod(evt);

	DFNerveSystem.Get().CheckFuryNerveOnKill(evt);

	return val;
}

public class NerveRegenCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new NerveRegenCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFNerveSystem.Get().nerveRegenDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFNerveSystem.Get().OnUpdateFromNerveRegen();
	}
}

public class DangerUpdateDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new DangerUpdateDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFNerveSystem.Get().dangerUpdateDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFNerveSystem.Get().OnUpdateFromDanger();
	}
}

public class NerveBreathingDangerTransitionCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new NerveBreathingDangerTransitionCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFNerveSystem.Get().nerveBreathingDangerTransitionDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFNerveSystem.Get().OnNerveBreathingDangerTransitionCallback();
	}
}

public class RemoveNarcoticFXCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new RemoveNarcoticFXCallback();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFNerveSystem.Get().removeNarcoticFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
		DFNerveSystem.Get().OnRemoveNarcoticFX();
	}
}

class DFNerveSystemEventListener extends DFNeedSystemEventListener {
	private func GetSystemInstance() -> wref<DFNeedSystemBase> {
		//DFProfile();
		return DFNerveSystem.Get();
	}
}

public final class DFNerveSystem extends DFNeedSystemBase {
	private let StatPoolsSystem: ref<StatPoolsSystem>;
	private let HUDSystem: ref<DFHUDSystem>;
	private let HydrationSystem: ref<DFHydrationSystem>;
	private let NutritionSystem: ref<DFNutritionSystem>;
	private let EnergySystem: ref<DFEnergySystem>;
	private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
	private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
	private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
	private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;

	private const let nerveAmountOnVehicleKnockdown: Float = 2.0;
	private const let nerveLossInDanger: Float = 0.25;
	private const let nerveRegenAmountRapid: Float = 1.0;
	private const let nerveRegenAmountSlow: Float = 0.05;
	private const let criticalNerveRegenTarget: Float = 10.0;
	private const let minDelayedNerveResult: Float = 10.0;
	private const let nauseaNeedStageThreshold: Int32 = 4;
	public const let insomniaNeedStageThreshold: Int32 = 3;
	public const let nerveRecoverAmountSleeping: Float = 0.083333334;
	public const let nerveRecoverAmountSleepingMax: Float = 100.0;
	private const let nerveRestoreInFuryOnKill: Float = 1.0;
	private const let boosterMemoryTraceNerveLossBonusMult: Float = 0.25;
	private const let boosterMemoryBlackMarketTraceNerveLossBonusMult: Float = 0.35;
	private const let nervePercentToDeferPerHumanityLossLevel: Float = 0.25;

	private let currentDangerDelayedNerveLoss: Float = 0.0;
	public let currentNerveBreathingFXStage: Int32 = 0;

	public let dangerUpdateDelayID: DelayID;
	public let nerveBreathingDangerTransitionDelayID: DelayID;
	public let nerveRegenDelayID: DelayID;
	public let removeNarcoticFXDelayID: DelayID;
	public let softCapMetFeedbackDelayID: DelayID;

	private let updateMode: DFNerveSystemUpdateMode = DFNerveSystemUpdateMode.Time;

	private let dangerUpdateDelayInterval: Float = 5.0;
	private let withdrawalUpdateDelayInterval: Float = 5.0;
	private let nerveBreathingDangerTransitionDelayInterval: Float = 10.0;
	private let nerveRegenDelayInterval: Float = 0.25;
	private let removeNarcoticFXDelayInterval: Float = 60.0;
	private let softCapMetFeedbackDelayInterval: Float = 1.0;

	private let lastDangerState: DFPlayerDangerState;

	// Regen
	private let currentNerveRegenTarget: Float = 10.0; // Default: criticalNerveRegenTarget

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNerveSystem> {
		//DFProfile();
		let instance: ref<DFNerveSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNerveSystem>()) as DFNerveSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNerveSystem> {
		//DFProfile();
		return DFNerveSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
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

	public func GetSystems() -> Void {
		//DFProfile();
		super.GetSystems();

		let gameInstance = GetGameInstance();
		this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
		this.HUDSystem = DFHUDSystem.GetInstance(gameInstance);
		this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
		this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
		this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
		this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
		this.HumanityLossConditionSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
	}

	public final func SetupData() -> Void {
		//DFProfile();
		super.SetupData();
		this.needStageStatusEffects = [
			t"DarkFutureStatusEffect.NervePenalty_01",
			t"DarkFutureStatusEffect.NervePenalty_02",
			t"DarkFutureStatusEffect.NervePenalty_03",
			t"DarkFutureStatusEffect.NervePenalty_04"
		];
	}

	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		super.InitSpecific(attachedPlayer);
		this.ForceNeedMaxValueUpdate();
	}

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		super.DoPostSuspendActions();
		this.StopNerveBreathingEffects();
		this.StopNarcoticFX();
		this.lastDangerState = DFPlayerDangerState(false, false);
		this.currentNerveRegenTarget = this.criticalNerveRegenTarget;
	}

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		super.DoPostResumeActions();
		this.ForceNeedMaxValueUpdate();
	}

	public final func OnTimeSkipStart() -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipStart");

		this.SetUpdateMode(DFNerveSystemUpdateMode.Suspended);
		this.UnregisterAllNeedFXCallbacks();
	}

	public final func OnTimeSkipCancelled() -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipCancelled");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState(this, true) {
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "OnTimeSkipFinished");

		this.AutoSetUpdateMode();

		if this.GameStateService.IsValidGameState(this, true) {
			this.OnTimeSkipFinishedActual(data);
			this.UpdateInsufficientNeedRepeatFXCallback(this.GetNeedStage());
		}
	}

	public func UnregisterAllDelayCallbacks() -> Void {
		//DFProfile();
		super.UnregisterAllDelayCallbacks();

		this.UnregisterDangerUpdateCallback();
		this.UnregisterNerveBreathingDangerTransitionCallback();
		this.UnregisterRemoveNarcoticFXCallbacks();
		this.UnregisterNerveRegenCallback();
	}

    //
	//  Required Overrides
	//
    private final func OnUpdateActual() -> Void {
		//DFProfile();
		DFLog(this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetNerveChangeFromTimeInProvidedState(this.GetNeedValue(), this.HydrationSystem.GetNeedStage(), this.NutritionSystem.GetNeedStage(), this.EnergySystem.GetNeedStage()));
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		//DFProfile();
		DFLog(this, "OnTimeSkipFinishedActual");

		let currentValue: Float = this.GetNeedValue();

		if currentValue < data.targetNeedValues.nerve.ceiling {
			this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nerve.value - currentValue);
		} else {
			this.QueueContextuallyDelayedNeedValueChange(data.targetNeedValues.nerve.value - data.targetNeedValues.nerve.ceiling);
		}
	}

	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		if itemRecord.TagsContains(n"DarkFutureConsumableNerveNoCombat") && this.player.IsInCombat() {
			return;
		}

		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);
		if consumableNeedsData.nerve.value != 0.0 {
			let changeNeedValueProps: DFChangeNeedValueProps;

			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			uiFlags.instantUIChange = !animateUI;
			uiFlags.forceBright = true;
			uiFlags.momentaryDisplayIgnoresSceneTier = true;
			let isNicotine: Bool = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNicotine");

			changeNeedValueProps.uiFlags = uiFlags;
			changeNeedValueProps.suppressRecoveryNotification = isNicotine;
			changeNeedValueProps.maxOverride = this.GetNeedMaxAfterItemUse(itemRecord);
			
			let clampedValue: Float = this.GetClampedNeedChangeFromData(consumableNeedsData.nerve);
			this.ChangeNeedValue(clampedValue, changeNeedValueProps);

			// If Nerve is increasing, and this is a narcotic, play a sound effect.
			if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNarcotic") {
				this.StartNarcoticFX();
				this.RegisterRemoveNarcoticFXInitialCallback();

				if clampedValue >= 1.0 && this.Settings.narcoticsSFXEnabled {
					let notification: DFNotification;
					notification.sfx = DFAudioCue(n"ono_v_laughs_soft", 10);
					this.NotificationService.QueueNotification(notification);
				}
			}
		}
	}
	
	private final func StartNarcoticFX() -> Void {
		//DFProfile();
		GameObjectEffectHelper.StartEffectEvent(this.player, n"status_drugged_heavy", false, null, true);
		GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 3.00);
		
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"vfx_fullscreen_drugged_start";
		this.player.QueueEvent(evt);
	}

    public final func OnRemoveNarcoticFX() -> Void {
		//DFProfile();
		this.StopNarcoticFX();
	}

    public final func StopNarcoticFX() -> Void {
		//DFProfile();
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"status_drugged_heavy");
		GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 0.00);

		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"vfx_fullscreen_drugged_stop";
		this.player.QueueEvent(evt);
	}

	public final func GetNeedMaxAfterItemUse(itemRecord: wref<Item_Record>) -> Float {
		//DFProfile();
		let needMax: Float = 100.0;

		if IsDefined(itemRecord) {			
			let alcoholWithdrawalLevel: Int32 = this.AlcoholAddictionSystem.GetWithdrawalLevel();
			if itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcohol") {
				let alcoholStatus: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"BaseStatusEffect.Drunk");
				let stacksToAdd: Uint32 = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveAlcoholStrong") ? 3u : 1u;
				let newAlcoholStackCount: Uint32;
				if IsDefined(alcoholStatus) {
					newAlcoholStackCount = alcoholStatus.GetStackCount() + stacksToAdd;
				} else {
					newAlcoholStackCount = stacksToAdd;
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

			let newCyberpsychosisLimit: Float;
			if itemRecord.TagsContains(n"DarkFutureConsumableImmunosuppressantDrug") {
				newCyberpsychosisLimit = 100.0;
			} else {
				newCyberpsychosisLimit = 100.0 - Cast<Float>(StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.Cyberpsychosis").GetStackCount());
			}

			// If currently affected by Addiction Treatment, the max for addiction-related limits is always 100.
			let addictionTreatmentDuration: Float = this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds();
			if addictionTreatmentDuration > 0.0 || itemRecord.TagsContains(n"DarkFutureConsumableAddictionTreatmentDrug") {
				newAlcoholLimit = 100.0;
				newNicotineLimit = 100.0;
				newNarcoticLimit = 100.0;
			}

			needMax = newAlcoholLimit < needMax ? newAlcoholLimit : needMax;
			needMax = newNicotineLimit < needMax ? newNicotineLimit : needMax;
			needMax = newNarcoticLimit < needMax ? newNarcoticLimit : needMax;
			needMax = newCyberpsychosisLimit < needMax ? newCyberpsychosisLimit : needMax;
		}

		return needMax;
	}

	public final func GetNerveLimitAfterAlcoholUse() -> Float {
		//DFProfile();
		// This function helps work around a race condition when consuming alcohol and satisfying an alcohol addiction.
		// Due to this, some Nerve that would be restored when satisfying the addiction would be "thrown away" otherwise.
		// Predict what the Nerve limit would be if specifically one alcohol item were consumed and use that result
		// as a Nerve Max Override in the ChangeNeedValue() function call in ApplyBaseAlcoholNerveValueChange().

		// If Strong Alcohol, this function will be called for each application of BaseStatusEffect.Drunk, making it unnecessary
		// to try to anticipate the application of more than one stack application.

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
		//DFProfile();
		return DFHUDBarType.Nerve;
	}

	private final func GetNeedType() -> DFNeedType {
		//DFProfile();
		return DFNeedType.Nerve;
	}

	private final func QueueNeedStageNotification(stage: Int32, opt suppressRecoveryNotification: Bool) -> Void {
		//DFProfile();
		DFLog(this, "QueueNeedStageNotification stage = " + ToString(stage) + ", suppressRecoveryNotification = " + ToString(suppressRecoveryNotification));
        
		let notification: DFNotification;

		// Allow Nerve notifications to play during combat.
		notification.allowPlaybackInCombat = true;

		if stage == 4 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"hacking_interference_shot", null);
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Nerve, true, false, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 3 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"stagger_effect", null);
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Nerve, true, false, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 2 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_exhale_01", 20);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"stagger_effect", null);
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 1 {
			if this.Settings.needNegativeSFXEnabled {
				notification.sfx = DFAudioCue(n"ono_v_exhale_01", 20);
			}

			notification.ui = DFUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 0 && !suppressRecoveryNotification {
			if this.Settings.needPositiveSFXEnabled {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_music_start", 30);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				}
				
			}

			// Don't show the UI when recovering if it is the result of
			// a nerve regen interaction.
			if this.GetNerveRegenTarget() == 0.0 {
				notification.ui = DFUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
			}
			this.NotificationService.QueueNotification(notification);
		}
	}

	private final func GetSevereNeedMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureNerveNotificationSevere";
	}

	private final func GetSevereNeedCombinedContextKey() -> CName {
		//DFProfile();
		return n"DarkFutureMultipleNotification";
	}

	private final func GetNeedStageStatusEffectTag() -> CName {
		//DFProfile();
		return n"DarkFutureNeedNerve";
	}

	private final func GetTutorialTitleKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialNerveTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureTutorialNerve";
	}

	private func GetHasShownTutorialForNeed() -> Bool {
		//DFProfile();
		return this.PlayerStateService.hasShownNerveTutorial;
	}

	private func SetHasShownTutorialForNeed(hasShownTutorial: Bool) -> Void {
		//DFProfile();
		this.PlayerStateService.hasShownNerveTutorial = hasShownTutorial;
	}

	private final func GetBonusEffectTDBID() -> TweakDBID {
		//DFProfile();
		return t"HousingStatusEffect.Refreshed";
	}

	private final func GetNeedDeathSettingValue() -> Bool {
		return this.Settings.nerveLossIsFatal;
	}

	//
	//	Overrides
	//
	public final func ReapplyFX() -> Void {
		//DFProfile();
		super.ReapplyFX();
		this.TryToTransitionNerveBreathingEffects();
	}

	public final func SuspendFX() -> Void {
		//DFProfile();
        super.SuspendFX();
        this.StopNerveBreathingEffects();
    }

	public final func OnSceneTierChanged(value: GameplayTier) -> Void {
		//DFProfile();
		if DFRunGuard(this, true) { return; }
		super.OnSceneTierChanged(value);
		
		if Equals(value, GameplayTier.Tier1_FullGameplay) || Equals(value, GameplayTier.Tier2_StagedGameplay) {
			// When transitioning back to a playable Gameplay Tier, remove any interaction-based
			// Nerve Regen target. Hide the lock.
			if this.GetNerveRegenTarget() > 0.0 {
				this.SetNerveRegenTarget(this.criticalNerveRegenTarget);
			}

			DFHUDSystem.Get().nerveBar.SetHideLock();
		}
	}

    //
	//	RunGuard Protected Methods
	//
	public final func ChangeNeedValue(amount: Float, opt changeValueProps: DFChangeNeedValueProps) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "ChangeNeedValue: amount = " + ToString(amount) + ", changeValueProps = " + ToString(changeValueProps));

		let needMax: Float = changeValueProps.maxOverride > 0.0 ? changeValueProps.maxOverride : this.GetCalculatedNeedMax();
		let oldValue: Float = this.needValue;
		let softCap: Float = this.HumanityLossConditionSystem.GetCurrentNerveSoftCapFromHumanityLoss();
		let newValue: Float;

		if amount > 0.0 && changeValueProps.isSoftCapRestrictedChange {
			if oldValue < softCap {
				// Clamp to the lowest cap. This will either increase the value (up to the soft cap), or lower it (to the max).
				let lowestCap: Float = MinF(softCap, needMax);
				newValue = ClampF(this.needValue + amount, 0.0, lowestCap);
			} else {
				// We are increasing, this is a soft cap restricted change, and we are already at or above the soft cap. Clamp to only the max while retaining the current value.
				newValue = ClampF(this.needValue, 0.0, needMax);
			}
			
		} else {
			// We are not increasing, or we are increasing, but this is not a soft cap restricted change. Change the value clamped to the max.
			newValue = ClampF(this.needValue + amount, 0.0, needMax);
		}
			
		let change: Float = newValue - oldValue;
		this.needValue = newValue;

		this.needMax = needMax;

		if changeValueProps.doNotUpdateUIIfNoChange && oldValue == newValue {
			// Skip the HUD UI update. Allows the bar to fade out.

		} else if amount > 0.0 && changeValueProps.isSoftCapRestrictedChange && newValue >= softCap {
			// We are restoring Nerve from an activity, and are at the soft cap. Full bright the UI and display the lock (if softCap below 100) regardless of flag settings.
			let uiFlags = changeValueProps.uiFlags;
			this.UpdateNeedHUDUI(true, uiFlags.instantUIChange, true, true, true, softCap < 100.0);

		} else {
			let uiFlags = changeValueProps.uiFlags;
			this.UpdateNeedHUDUI(uiFlags.forceMomentaryUIDisplay, uiFlags.instantUIChange, uiFlags.forceBright, uiFlags.momentaryDisplayIgnoresSceneTier, changeValueProps.isSoftCapRestrictedChange, false);
		}

		let stage: Int32 = this.GetNeedStage();
		if NotEquals(stage, this.lastNeedStage) {
			DFLog(this, "ChangeNeedValue: Last Need stage (" + ToString(this.lastNeedStage) + ") != current stage (" + ToString(stage) + "). Refreshing status effects and FX.");
			this.RegisterStatusEffectRefreshDebounceCallback();

			if !changeValueProps.skipFX {
				this.UpdateNeedFX(changeValueProps.suppressRecoveryNotification);
			}
		}

		if stage > this.lastNeedStage && this.lastNeedStage < 4 && stage == 4 {
			this.QueueSevereNeedMessage();
		}

		this.CheckForCriticalNeed();
		this.CheckIfBonusEffectsValid();
		this.TryToShowTutorial();
		
		this.lastNeedStage = stage;

		// TODOFUTURE: Removing this check crashes the game. Investigate.
		if !changeValueProps.isMaxValueUpdate {
			this.DispatchNeedValueChangedEvent(change, newValue, changeValueProps.isMaxValueUpdate, changeValueProps.fromDanger);
		}
		DFLog(this, "ChangeNeedValue: change: " + ToString(change) + ", newValue = " + ToString(newValue));
	}

    //
    //  System-Specific Methods
    //
	public final func SetUpdateMode(mode: DFNerveSystemUpdateMode) -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }
		
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
		//DFProfile();
		let changeNeedValueProps: DFChangeNeedValueProps;

		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		changeNeedValueProps.uiFlags = uiFlags;
		changeNeedValueProps.suppressRecoveryNotification = false;
		changeNeedValueProps.maxOverride = this.GetNerveLimitAfterAlcoholUse();

		this.ChangeNeedValue(this.Settings.nerveAlcoholTier1Rev2, changeNeedValueProps);
	}

	public final func CheckFuryNerveOnKill(evt: ref<gameDeathEvent>) -> Void {
		//DFProfile();
		if IsDefined(evt.instigator) {
			let playerGO: wref<GameObject> = this.player;
			if this.GameStateService.isInFury && Equals(evt.instigator, playerGO) {
				let changeNeedValueProps: DFChangeNeedValueProps;

				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.instantUIChange = true;

				changeNeedValueProps.uiFlags = uiFlags;

				this.ChangeNeedValue(this.nerveRestoreInFuryOnKill, changeNeedValueProps);
			}
		}
	}

	public final func AutoSetUpdateMode() -> Void {
		//DFProfile();
		if DFRunGuard(this) { return; }

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
		//DFProfile();
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

		let amountToChange: Float = 0.0;
		if needsFactorPerDay > 0 {
			// Try to deplete based on needs factors.
			// (Points to Lose based on Needs Factor) / Hours in Day / Updates per Hour
			amountToChange = (((Int32ToFloat(needsFactorPerDay) * 5.0) / 24.0) / 12.0) * -1.0;
		}

		// Return the amount to change. (May be 0)
		return amountToChange;
	}

    public final func GetNerveChangeFromDangerAndAccumulateDelayedAmount() -> Float {
		//DFProfile();
		let baseNerveLossInDanger: Float;
		let nerveLossBonusMult: Float = 1.0;

		if this.lastDangerState.InCombat || this.lastDangerState.BeingRevealed {
			if this.lastDangerState.InCombat {
				baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateInCombatPct / 100.0)) * -1.0;

			} else if this.lastDangerState.BeingRevealed {
				baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateWhenTracedPct / 100.0)) * -1.0;
				nerveLossBonusMult -= this.GetMemoryBoosterTraceNerveLossBonusMult();
			}

			let totalNerveLossBonusMult: Float = MaxF(nerveLossBonusMult, 0.0);
			let nerveLossInDangerWithBonus: Float = baseNerveLossInDanger * totalNerveLossBonusMult;

			let delayedPercentage: Float = this.nervePercentToDeferPerHumanityLossLevel * Cast<Float>(this.HumanityLossConditionSystem.GetConditionLevel());
			let delayedAmount: Float = nerveLossInDangerWithBonus * delayedPercentage;

			let totalNerveLoss: Float = nerveLossInDangerWithBonus - delayedAmount;
			this.currentDangerDelayedNerveLoss += delayedAmount;
			DFLog(this, "GetNerveChangeFromDangerAndAccumulateDelayedAmount() totalNerveLoss: " + ToString(totalNerveLoss) + ", delayedAmount: " + ToString(delayedAmount));

			return totalNerveLoss;
		
		} else {
			// Failsafe - Not in danger, but this function was called anyway.
			return 0.0;
		}
	}

	public final func GetNerveRegenTarget() -> Float {
		//DFProfile();
		return this.currentNerveRegenTarget;
	}

	public final func SetNerveRegenTarget(target: Float) -> Void {
		//DFProfile();
		this.currentNerveRegenTarget = ClampF(target, this.criticalNerveRegenTarget, this.GetCalculatedNeedMax());
		this.AutoSetUpdateMode();
	}

	public final func ForceNeedMaxValueUpdate(opt skipFXForThisUpdate: Bool) -> Void {
		//DFProfile();
		let changeNeedValueProps: DFChangeNeedValueProps;
		changeNeedValueProps.isMaxValueUpdate = true;
		changeNeedValueProps.skipFX = skipFXForThisUpdate;

		this.ChangeNeedValue(0.0, changeNeedValueProps);
	}

	public final func GetHasNausea() -> Bool {
		//DFProfile();
		return this.GetNeedStage() >= this.nauseaNeedStageThreshold;
	}

    private final func GetMemoryBoosterTraceNerveLossBonusMult() -> Float {
		//DFProfile();
		if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.Blackmarket_MemoryBooster") {
			return this.boosterMemoryBlackMarketTraceNerveLossBonusMult;
		} else if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.MemoryBooster") {
			return this.boosterMemoryTraceNerveLossBonusMult; 
		} else {
			return 0.0;
		}
	}

    public final func OnDangerStateChanged(dangerState: DFPlayerDangerState) -> Void {
		//DFProfile();
		if DFRunGuard(this, true) { return; }

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

			// Humanity Loss - Apply any delayed Nerve loss
			if this.currentDangerDelayedNerveLoss != 0.0 {
				// Failsafe - Don't allow this to drop Nerve below a certain value
				let currentNeedValue: Float = this.GetNeedValue();
				let deltaToMinThreshold: Float = currentNeedValue - this.minDelayedNerveResult;
				if currentNeedValue > this.minDelayedNerveResult {
					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;
					uiFlags.forceBright = true;

					let changeValueProps: DFChangeNeedValueProps;
					changeValueProps.fromDanger = true;
					changeValueProps.uiFlags = uiFlags;
					
					if deltaToMinThreshold >= AbsF(this.currentDangerDelayedNerveLoss) {
						this.ChangeNeedValue(this.currentDangerDelayedNerveLoss, changeValueProps);
					} else {
						this.ChangeNeedValue(-deltaToMinThreshold, changeValueProps);
					}
				}
				this.currentDangerDelayedNerveLoss = 0.0;
			}
        }

		this.AutoSetUpdateMode();
		this.HUDSystem.RefreshHUDUIVisibility();
        this.lastDangerState = dangerState;
    }

	public final func GetCalculatedNeedMaxInProvidedState(addictionTreatmentDuration: Float, alcoholWithdrawalLevel: Int32, nicotineWithdrawalLevel: Int32, narcoticWithdrawalLevel: Int32) -> Float {
		//DFProfile();
		let nerveTarget: Float = 100.0;
		
		let alcoholNerveTargets: array<Float> = this.AlcoholAddictionSystem.GetAddictionNerveLimits();
		let nicotineNerveTargets: array<Float> = this.NicotineAddictionSystem.GetAddictionNerveLimits();
		let narcoticNerveTargets: array<Float> = this.NarcoticAddictionSystem.GetAddictionNerveLimits();

		let alcoholNerveTarget = alcoholNerveTargets[alcoholWithdrawalLevel];
		let nicotineNerveTarget = nicotineNerveTargets[nicotineWithdrawalLevel];
		let narcoticNerveTarget = narcoticNerveTargets[narcoticWithdrawalLevel];
		let cyberpsychoNerveTarget: Float = Cast<Float>(100u - StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.Cyberpsychosis").GetStackCount());

		if Equals(addictionTreatmentDuration, 0.0) {
			nerveTarget = alcoholNerveTarget < nerveTarget ? alcoholNerveTarget : nerveTarget;
			nerveTarget = nicotineNerveTarget < nerveTarget ? nicotineNerveTarget : nerveTarget;
			nerveTarget = narcoticNerveTarget < nerveTarget ? narcoticNerveTarget : nerveTarget;
		}

		nerveTarget = cyberpsychoNerveTarget < nerveTarget ? cyberpsychoNerveTarget : nerveTarget;

		return nerveTarget;
	}

	private final func GetCalculatedNeedMax() -> Float {
		//DFProfile();
		return this.GetCalculatedNeedMaxInProvidedState(
					this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds(),
					this.AlcoholAddictionSystem.GetWithdrawalLevel(),
					this.NicotineAddictionSystem.GetWithdrawalLevel(),
					this.NarcoticAddictionSystem.GetWithdrawalLevel());
	}

	private final func TryToTransitionNerveBreathingEffects() -> Void {
		//DFProfile();
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
			if inDanger || this.player.m_isAiming || (needValue <= this.criticalNeedThreshold && needValue > 0.0) {
				if this.lastDangerState.InCombat || needValue <= this.extremelyCriticalNeedThreshold {
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

	public final func CheckForCriticalNeed() -> Void {
		//DFProfile();
		if this.inDeathState { return; }

		let currentNerve: Float = this.GetNeedValue();
		
		if this.GameStateService.IsValidGameState(this) {
			if currentNerve <= 0.0 && this.GetNeedDeathSettingValue() {
				if this.CyberwareService.GetHasSecondHeart() && !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.SecondHeartCooldown") {
					// Is the player's max Nerve greater than 0, does the player have a Second Heart, and is it not on a cooldown?
					let changeNeedValueProps: DFChangeNeedValueProps;

					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;

					changeNeedValueProps.uiFlags = uiFlags;

					this.ChangeNeedValue(this.CyberwareService.GetSecondHeartNerveRestoreAmount(), changeNeedValueProps);
					StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SecondHeartNerveRestore");

				} else {
					// Kill the player.
					this.QueuePlayerDeath();
				}
			}
		}

		this.PlayerStateService.UpdateCriticalNeedEffects();

		if this.GameStateService.IsValidGameState(this, true) {
			if currentNerve > 0.0 {
				if currentNerve <= this.criticalNeedThreshold {
					this.TryToTransitionNerveBreathingEffects();
				} else {
					this.TryToTransitionNerveBreathingEffects();
				}
			}

			// TODOFUTURE - Blink the bar, make more visually apparent
			if NotEquals(this.updateMode, DFNerveSystemUpdateMode.Regen) {
				if currentNerve <= this.extremelyCriticalNeedThreshold && this.lastValueForCriticalNeedCheck > this.extremelyCriticalNeedThreshold {
					this.QueueExtremelyCriticalNeedSFX();
					this.TryToTransitionNerveBreathingEffects();
					this.QueueExtremelyCriticalNeedWarningNotification();
				} else if currentNerve <= this.criticalNeedThreshold && this.lastValueForCriticalNeedCheck > this.criticalNeedThreshold {
					this.QueueCriticalNeedSFX();
					this.TryToTransitionNerveBreathingEffects();
					this.QueueCriticalNeedWarningNotification();
				}
			}
			
			this.lastValueForCriticalNeedCheck = currentNerve;
		}
	}

	public final func QueuePlayerDeath() -> Void {
		// :(

		this.TryToTransitionNerveBreathingEffects();
		super.QueuePlayerDeath();
	}

	public final func OnPostPlayerDeathCallback() -> Void {
		this.TryToTransitionNerveBreathingEffects();
		super.OnPostPlayerDeathCallback();
	}

	private final func StopNerveBreathingEffects() -> Void {
		//DFProfile();
		this.StopNerveBreathingLowEffect();
		this.StopNerveBreathingHighEffect();

		this.currentNerveBreathingFXStage = 0;
	}

	private final func TransitionToNerveLowBreathingEffect() -> Void {
		//DFProfile();
		this.currentNerveBreathingFXStage = 1;

		// If Out Of Breath FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.PlayerStateService.StopOutOfBreathSFXIfBreathingFXPlaying();

		this.StopNerveBreathingHighEffect();
		this.PlayNerveBreathingLowEffect();
	}

	private final func TransitionToNerveHighBreathingEffect() -> Void {
		//DFProfile();
		this.currentNerveBreathingFXStage = 2;

		// If Out Of Breath FX playing, stop the SFX only, allow the camera effect to decay out as normal
		this.PlayerStateService.StopOutOfBreathSFXIfBreathingFXPlaying();

		this.StopNerveBreathingLowEffect();
		this.PlayNerveBreathingHighEffect();
	}

	private final func StopNerveBreathingLowEffect() -> Void {
		//DFProfile();
		let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"q201_sc_03_v_scared_loop_stop";
		this.player.QueueEvent(evt);
	}

	private final func StopNerveBreathingHighEffect() -> Void {
		//DFProfile();
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
		evt.soundName = n"q201_sc_03_v_scared_fast_loop";
		this.player.QueueEvent(evt);
	}

	private final func PlayNerveBreathingLowEffect() -> Void {
		//DFProfile();
		if this.Settings.lowNerveBreathingEffectEnabled {
			let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = n"q201_sc_03_v_scared_loop";
			this.player.QueueEvent(evt);
		}
	}

	private final func PlayNerveBreathingHighEffect() -> Void {
		//DFProfile();
		if this.Settings.lowNerveBreathingEffectEnabled {
			let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = n"q201_sc_03_v_scared_fast_loop";
			this.player.QueueEvent(evt);
		}
	}

	public final func OnUpperBodyStateChange() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this, true) {
			this.TryToTransitionNerveBreathingEffects();
			this.UpdateWeaponShake();
		}
	}

	public final func OnUpdateFromNerveRegen() -> Void {
		//DFProfile();
		// Allow Nerve to regenerate slowly in real-time.
		let changeNeedValueProps: DFChangeNeedValueProps;
		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;
		changeNeedValueProps.uiFlags = uiFlags;

		if this.GetNerveRegenTarget() < this.GetNeedMax() {
			this.ChangeNeedValue(this.nerveRegenAmountSlow, changeNeedValueProps);
		} else {
			// All rapid real-time Nerve increases are implicitly soft-cap restricted.
			changeNeedValueProps.isSoftCapRestrictedChange = true;
			this.ChangeNeedValue(this.nerveRegenAmountRapid, changeNeedValueProps);
		}
		
		this.AutoSetUpdateMode();
	}

	public final func OnNerveBreathingDangerTransitionCallback() -> Void {
		//DFProfile();
		this.TryToTransitionNerveBreathingEffects();
	}

	public final func OnUpdateFromDanger() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this) {
			let changeValueProps: DFChangeNeedValueProps;
			changeValueProps.fromDanger = true;

			this.ChangeNeedValue(this.GetNerveChangeFromDangerAndAccumulateDelayedAmount(), changeValueProps);
		}

		this.AutoSetUpdateMode();
	}

	public final func OnVehicleKnockdown() -> Void {
		//DFProfile();
		if this.GameStateService.IsValidGameState(this) {
			DFLog(this, "OnVehicleKnockdown");

			let changeNeedValueProps: DFChangeNeedValueProps;
			let uiFlags: DFNeedChangeUIFlags;
			uiFlags.forceMomentaryUIDisplay = true;
			changeNeedValueProps.uiFlags = uiFlags;
			changeNeedValueProps.fromDanger = false;

			this.ChangeNeedValue(-(this.nerveAmountOnVehicleKnockdown), changeNeedValueProps);
		}
	}

	public final func OnCyberpsychosisUpdated(cyberpsychosisApplied: Bool) -> Void {
		//DFProfile();
		this.ForceNeedMaxValueUpdate(cyberpsychosisApplied);
		DFLog(this, "CyberpsychosisStacks stat value: " + ToString(GameInstance.GetStatsSystem(GetGameInstance()).GetStatValue(Cast<StatsObjectID>(this.player.GetEntityID()), IntEnum<gamedataStatType>(EnumValueFromName(n"gamedataStatType", n"DarkFutureCyberpsychosisStacks")))));
	}

	//
	//	Weapon Effects
	//
	public final func UpdateWeaponShake() -> Void {
		//DFProfile();
		let hasFocusActive: Bool = StatusEffectSystem.ObjectHasStatusEffect(this.player, t"BaseStatusEffect.FocusedCoolPerkSE");
		let hasNervesOfTungstenSteel: Bool = PlayerDevelopmentSystem.GetData(this.player).IsNewPerkBoughtAnyLevel(gamedataNewPerkType.Cool_Master_Perk_1);
		let inFury: Bool = this.GameStateService.PlayerHasAnyFuryEffect();
		let ignoreWeaponShake: Bool = !this.Settings.nerveWeaponSwayEnabled || (hasFocusActive && hasNervesOfTungstenSteel) || inFury;
		
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
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, DangerUpdateDelayCallback.Create(), this.dangerUpdateDelayID, this.dangerUpdateDelayInterval);
	}

	private final func RegisterNerveBreathingDangerTransitionCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, NerveBreathingDangerTransitionCallback.Create(), this.nerveBreathingDangerTransitionDelayID, this.nerveBreathingDangerTransitionDelayInterval);
	}

	private final func RegisterNerveRegenCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, NerveRegenCallback.Create(), this.nerveRegenDelayID, this.nerveRegenDelayInterval);
	}
	
    private final func RegisterRemoveNarcoticFXInitialCallback() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, RemoveNarcoticFXCallback.Create(), this.removeNarcoticFXDelayID, this.removeNarcoticFXDelayInterval);
	}

	//
	//	Unregistration
	//
	private final func UnregisterDangerUpdateCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.dangerUpdateDelayID);
	}

	private final func UnregisterNerveBreathingDangerTransitionCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.nerveBreathingDangerTransitionDelayID);
	}

	private final func UnregisterNerveRegenCallback() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.nerveRegenDelayID);
	}

	private final func UnregisterRemoveNarcoticFXCallbacks() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.removeNarcoticFXDelayID);
	}
}
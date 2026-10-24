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
	Int32ToFloat,
	DFGeneralVoiceLine
}
import DarkFuture.Main.{
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFBiocorruptionDatum,
	DFTimeSkipData,
	DFTimeSkipType,
	DFNerveChangePreview
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem,
	DFAddictionSystemBase
}
import DarkFuture.Conditions.{
	DFHumanityLossConditionSystem,
	DFBiocorruptionConditionSystem,
	DFEuphoriaBlockedReason
}
import DarkFuture.Services.{
	DFCyberwareService,
	DFPlayerStateService,
	DFPlayerDangerState,
	DFGameStateService,
	DFNotificationService,
	DFAudioCue,
	DFVisualEffect,
	DFBarUIDisplay,
	DFMessage,
	DFMessageContext,
	DFNotification,
	DFNotificationCallback,
	GameState,
	DFFactNameValue,
	DFManagedEffectItemDefinition,
	DFManagedEffectStackCountMode,
	DFManagedEffectType,
	DFManagedEffect,
	DFManagedEffectDefinition,
	DFManagedEffectStackCountDef,
	DFManagedEffectPipelineResult
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

		} else if Equals(effectID, t"DarkFutureStatusEffect.Overdose") {
			let overdoseEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this, t"DarkFutureStatusEffect.Overdose");
			let overdoseStackCount: Uint32 = IsDefined(overdoseEffect) ? overdoseEffect.GetStackCount() : 0u;
			if overdoseStackCount > 0u || evt.stackCount == 1u {
				let props: DFChangeNeedValueProps;
				let uiFlags: DFNeedChangeUIFlags;
				uiFlags.instantUIChange = true;
				uiFlags.forceMomentaryUIDisplay = true;
				uiFlags.momentaryDisplayIgnoresSceneTier = true;
				props.uiFlags = uiFlags;
				let nerveLoss: Float = -nerveSystem.nerveLossOnOverdoseStack;
				nerveSystem.ChangeNeedValue(nerveLoss, props);
			}

			// Re-query the effect after CheckForCriticalNeed(), which may have
			// removed all Overdose stacks. Stop Overdose behavior if so.
			overdoseEffect = StatusEffectHelper.GetStatusEffectByID(this, t"DarkFutureStatusEffect.Overdose");
			if !IsDefined(overdoseEffect) || overdoseEffect.GetStackCount() == 0u {
				nerveSystem.SetOverdoseBehavior(false);
			}
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
	private let HumanityLossConditionSystem: ref<DFHumanityLossConditionSystem>;

	private const let nerveAmountOnVehicleKnockdown: Float = 2.0;
	private const let nerveLossInDanger: Float = 0.25;
	public const let nerveLossOnOverdoseStack: Float = 20.0;
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

	public let currentNerveBreathingFXStage: Int32 = 0;

	public let dangerUpdateDelayID: DelayID;
	public let nerveBreathingDangerTransitionDelayID: DelayID;
	public let nerveRegenDelayID: DelayID;
	public let removeNarcoticFXDelayID: DelayID;

	private let updateMode: DFNerveSystemUpdateMode = DFNerveSystemUpdateMode.Time;

	private let dangerUpdateDelayInterval: Float = 5.0;
	private let withdrawalUpdateDelayInterval: Float = 5.0;
	private let nerveBreathingDangerTransitionDelayInterval: Float = 10.0;
	private let nerveRegenDelayInterval: Float = 0.25;
	private let removeNarcoticFXDelayInterval: Float = 60.0;

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

		let gameInstance: GameInstance = GetGameInstance();
		this.StatPoolsSystem = GameInstance.GetStatPoolsSystem(gameInstance);
		this.HUDSystem = DFHUDSystem.GetInstance(gameInstance);
		this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
		this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
		this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
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

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		super.DoPostSuspendActions();
		this.StopNerveBreathingEffects();
		this.StopNarcoticFX();
		this.lastDangerState = DFPlayerDangerState(false, false);
		this.currentNerveRegenTarget = this.criticalNerveRegenTarget;
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

	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		super.InitSpecific(attachedPlayer);

		// Biocorruption - If not running, remove Euphoria.
		if !this.Settings.biocorruptionConditionEnabled || !this.Settings.addictionEnabled {
			this.BiocorruptionConditionSystem.RemoveEuphoriaIfApplied();
		}
	}

    //
	//  Required Overrides
	//
    private final func OnUpdateActual() -> Void {
		//DFProfile();
		DFLog(this, "OnUpdateActual");
		this.ChangeNeedValue(this.GetNerveChangeFromTimeInProvidedState(this.GetNeedValue(), this.GetOverchargeValue(), this.HydrationSystem.GetNeedStage(), this.NutritionSystem.GetNeedStage(), this.EnergySystem.GetNeedStage()));
	}

	private final func OnTimeSkipFinishedActual(data: DFTimeSkipData) -> Void {
		//DFProfile();
		DFLog(this, "OnTimeSkipFinishedActual");

		let queuedChange: DFQueuedNeedValueChange;
		queuedChange.value = data.targetNeedValues.nerve.value + data.targetNeedValues.nerve.overcharge;
		queuedChange.isFromTimeskip = true;
		queuedChange.targetValueMode = true;
		queuedChange.skipSevereNeedMessage = data.skipSevereNeedMessage;
		queuedChange.biocorruptionData = data.targetBiocorruptionValues;
		
		this.QueueContextuallyDelayedNeedValueChange(queuedChange);
	}

	private final func HandleOverchargeDepleted() -> Void {
		//DFProfile();
		this.BiocorruptionConditionSystem.ApplyCrashAfterEuphoria();
	}

	// TODO - THIS ISN'T CALLED!!!!! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	public final func OnStacksOfEnergyManagementEffectAppliedFromItem(itemRecord: wref<Item_Record>, animateUI: Bool, stacksApplied: Uint32) -> Void {
		//DFProfile();
		// Dark Future 3.0 - All consumables that restore Nerve are now stack-restricted and follow the same underlying
		// logic as Energy Management effects. As the Energy System now manages whether or not these stacks should apply,
		// the Energy System passes this data to the Nerve System to restore Nerve. (Less clean than I would like, but for now
		// this is the most straight-forward approach.)
		let isNarcotic: Bool = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNarcotic");
		let isNicotine: Bool = itemRecord.TagsContains(n"DarkFutureConsumableAddictiveNicotine");
		let consumableNeedsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);
		let itemNerve: DFNeedChangeDatum = consumableNeedsData.nerve;

		if stacksApplied > 0u {
			itemNerve.value *= Cast<Float>(stacksApplied);
		} else {
			// Beneficial to Nerve, but at max stacks; don't provide a benefit.
			return;
		}

		let changeNeedValueProps: DFChangeNeedValueProps;

		let uiFlags: DFNeedChangeUIFlags;
		uiFlags.forceMomentaryUIDisplay = true;
		uiFlags.instantUIChange = !animateUI;
		uiFlags.forceBright = true;
		uiFlags.momentaryDisplayIgnoresSceneTier = true;

		changeNeedValueProps.uiFlags = uiFlags;
		changeNeedValueProps.suppressRecoveryNotification = isNicotine;
		changeNeedValueProps.maxOverride = this.GetNeedMaxAfterItemUse(itemRecord);
		
		let clampedValue: Float = this.GetClampedNeedChangeFromData(itemNerve);
		this.ChangeNeedValue(clampedValue, changeNeedValueProps);

		// If Nerve is increasing, and this is a narcotic, and we are not overdosing, play a sound effect.
		if isNarcotic {
			this.StartNarcoticFX();
			this.RegisterRemoveNarcoticFXInitialCallback();

			// TODO - Laugh still occurs, check stack count instead
			// NOTE - Sound now moved to random chance during Euphoria
			/*if clampedValue >= 1.0 && this.Settings.narcoticsSFXEnabled && !this.PlayerStateService.GetInOverdose() {
				let notification: DFNotification;
				notification.sfx = DFAudioCue(n"ono_v_laughs_soft", 10, false);
				this.NotificationService.QueueNotification(notification);
			}*/
		}
	}

	// Dark Future 3.0 - Only used by Emergency Cardioregulator.
	//
	private final func OnItemConsumedActual(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		
		if itemRecord.TagsContains(n"DarkFutureConsumableOverdoseCureDrug") {
			// Remove all stacks of Narcotics.
			let energyToChange: Float = DFPlayerStateService.Get().ClearManagedEffectOfTypeAndReturnEnergyToChange(DFManagedEffectType.Narcotic);

			// Stop the overdose.
			let overdose: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.Overdose");
			if IsDefined(overdose) {
				StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Overdose", 10u);

				// Play a fallback audio event if Consumable Animations are disabled.
				if !this.Settings.consumableAnimationsEnabled {
					let notification: DFNotification;
					notification.sfx = DFAudioCue(n"q101_sc_03_v_gasp", 0);
					this.NotificationService.QueueNotification(notification);
				}
			}

			// Apply the Energy change.
			this.EnergySystem.ChangeNeedValue(energyToChange);
		}
	}

	public final func GetItemNerveChangePreviewAmount(itemRecord: wref<Item_Record>) -> DFNerveChangePreview {
		//DFProfile();
		let r: DFNerveChangePreview;
		let pipelineResult: DFManagedEffectPipelineResult = this.PlayerStateService.ManagedConsumablePipeline(itemRecord);
		if pipelineResult.managedEffectStateIndex == -1 || Equals(pipelineResult.managedEffectItemDef.itemRecordTag, n"") { return r; }
		
		// If the stack count granted is random, we can't know the effect on the player's Nerve.
		if Equals(pipelineResult.managedEffectItemDef.stackCountDef.mode, DFManagedEffectStackCountMode.Random) { 
			r.indeterminate = true;
			return r;
		}
		
		// If no active effect applied, bail.
		if pipelineResult.activeStacksToApply == 0 { return r; }

		r.change = Cast<Float>(pipelineResult.activeStacksToApply) * pipelineResult.managedEffectItemDef.nerveChangeWhenApplied;

		return r;
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

		if !IsDefined(itemRecord) {return this.needMax; }
		
		let managedEffectStateIdx: Int32 = this.PlayerStateService.GetItemManagedEffectStateIndex(itemRecord);
		if managedEffectStateIdx == -1 { return this.needMax; }

		let pipelineResult: DFManagedEffectPipelineResult = this.PlayerStateService.ManagedConsumablePipeline(itemRecord);

		let managedEffectItemDef: DFManagedEffectItemDefinition = this.PlayerStateService.GetItemManagedEffectDefinition(itemRecord);
        if Equals(managedEffectItemDef.itemRecordTag, n"") { return this.needMax; }

		// Core question this answers is: What is the withdrawal level of each of the player's addictions once this item is consumed?
		let nicotineWithdrawalLevel: Int32 = this.NicotineAddictionSystem.GetWithdrawalLevel();
		let alcoholWithdrawalLevel: Int32 = this.AlcoholAddictionSystem.GetWithdrawalLevel();
		let narcoticWithdrawalLevel: Int32 = this.NarcoticAddictionSystem.GetWithdrawalLevel();

		// Only change Withdrawal levels if the stack count mode is specific. If it is random, it's undetermined.
		let managedEffect: DFManagedEffect = this.PlayerStateService.GetManagedEffectsStateAtIndex(managedEffectStateIdx);
		let theAddictionSystem: ref<DFAddictionSystemBase> = this.PlayerStateService.GetAddictionSystemFromManagedEffectType(managedEffect.type);
		if IsDefined(theAddictionSystem) && Equals(managedEffectItemDef.stackCountDef.mode, DFManagedEffectStackCountMode.Specific) {
			if pipelineResult.activeStacksToApply > 0 {
				if Equals(managedEffect.type, DFManagedEffectType.Alcohol) { alcoholWithdrawalLevel = 0; } 
				else if Equals(managedEffect.type, DFManagedEffectType.Nicotine) { nicotineWithdrawalLevel = 0; } 
				else if Equals(managedEffect.type, DFManagedEffectType.Narcotic) { narcoticWithdrawalLevel = 0; }
			}
		}

		let alcoholLimits: array<Float> = this.AlcoholAddictionSystem.GetAddictionNeedLimits();
		let nicotineLimits: array<Float> = this.NicotineAddictionSystem.GetAddictionNeedLimits();
		let narcoticLimits: array<Float> = this.NarcoticAddictionSystem.GetAddictionNeedLimits();

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

		return needMax;
	}

	public final func GetCalculatedNeedMax() -> Float {
		//DFProfile();
		let max: Float = this.GetCalculatedNerveMaxInProvidedState(
					this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds(),
					this.AlcoholAddictionSystem.GetWithdrawalLevel(),
					this.NicotineAddictionSystem.GetWithdrawalLevel(),
					this.NarcoticAddictionSystem.GetWithdrawalLevel(),
					this.BiocorruptionConditionSystem.GetHasEuphoria());
		
		DFLog(this, "Nerve System Need Max: " + ToString(max));
		return max;
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
		let notOverdosing: Bool = !this.PlayerStateService.GetInOverdose();

		// Allow Nerve notifications to play during combat.
		notification.allowPlaybackInCombat = true;

		if stage == 4 {
			if this.Settings.needNegativeSFXEnabled && notOverdosing {
				notification.sfx = DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"hacking_interference_shot", null);
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Nerve, true, false, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 3 {
			if this.Settings.needNegativeSFXEnabled && notOverdosing {
				notification.sfx = DFAudioCue(n"ono_v_fear_panic_scream", 10);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"stagger_effect", null);
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Nerve, true, false, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 2 {
			if this.Settings.needNegativeSFXEnabled && notOverdosing {
				notification.sfx = DFAudioCue(n"ono_v_exhale_01", 20);
			}

			if this.Settings.nerveNeedVFXEnabled {
				notification.vfx = DFVisualEffect(n"stagger_effect", null);
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 1 {
			if this.Settings.needNegativeSFXEnabled && notOverdosing {
				notification.sfx = DFAudioCue(n"ono_v_exhale_01", 20);
			}

			notification.needsUI = DFBarUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
			this.NotificationService.QueueNotification(notification);

		} else if stage == 0 && !suppressRecoveryNotification {
			if this.Settings.needPositiveSFXEnabled && notOverdosing {
				if Equals(this.player.GetResolvedGenderName(), n"Female") {
					notification.sfx = DFAudioCue(n"ono_v_music_start", 30);
				} else {
					notification.sfx = DFAudioCue(n"ono_v_pre_insert_splinter", 30);
				}
				
			}

			// Don't show the UI when recovering if it is the result of
			// a nerve regen interaction.
			if this.GetNerveRegenTarget() == 0.0 {
				notification.needsUI = DFBarUIDisplay(DFHUDBarType.Nerve, false, true, false, false);
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
		//DFProfile();
		return this.Settings.nerveLossIsFatal;
	}

	private final func GetNeedSoftCapValue() -> Float {
		//DFProfile();
		return this.HumanityLossConditionSystem.GetCurrentNerveSoftCapFromHumanityLoss();
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
		let danger: Bool = this.PlayerStateService.GetInDanger();
		let regenTarget: Float = this.GetNerveRegenTarget();
		let regen: Bool = this.GetNeedValue() < regenTarget && (Equals(regenTarget, this.GetNeedMax()) || (this.HydrationSystem.GetNeedStage() < 4 && this.NutritionSystem.GetNeedStage() < 4 && this.EnergySystem.GetNeedStage() < 4));

		DFLog(this, "danger: " + ToString(danger));
		DFLog(this, "regenTarget: " + ToString(regenTarget));
		DFLog(this, "regen: " + ToString(regen));

		if danger {
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

		DFHUDSystem.Get().nerveBar.SetInDanger(danger);
	}

	public final func GetNerveChangeFromTimeInProvidedState(nerveValue: Float, overchargeValue: Float, hydrationStage: Int32, nutritionStage: Int32, energyStage: Int32) -> Float {
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
		
		if overchargeValue > 0.0 {
			// Deplete Overcharge over time.
			// (Points to Lose) / Hours in Day / Updates per Hour
			let updateIntervalInRealTimeSeconds: Float = this.updateIntervalInGameTimeSeconds / this.Settings.timescale;
			let targetMaxEuphoriaDurationInRealTimeSeconds: Float = 3600.0; // 60 real-time minutes
			let targetTotalUpdateCount: Float = targetMaxEuphoriaDurationInRealTimeSeconds / updateIntervalInRealTimeSeconds;
			let amountToLosePerUpdate: Float = this.maxOvercharge / targetTotalUpdateCount;

			if amountToLosePerUpdate > overchargeValue {
				amountToChange = overchargeValue * -1.0;
			} else {
				amountToChange = amountToLosePerUpdate * -1.0;
			}

		} else if needsFactorPerDay > 0 {
			// Try to deplete based on needs factors.
			// (Points to Lose based on Needs Factor) / Hours in Day / Updates per Hour
			amountToChange = (((Int32ToFloat(needsFactorPerDay) * 5.0) / 24.0) / 12.0) * -1.0;
		}

		// Return the amount to change. (May be 0)
		return amountToChange;
	}

    public final func GetNerveChangeFromDanger() -> Float {
		//DFProfile();
		let baseNerveLossInDanger: Float;
		let nerveLossBonusMult: Float = 1.0;

		if this.lastDangerState.InCombat || this.lastDangerState.BeingRevealed {
			if this.lastDangerState.InCombat {
				baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateInCombatPct / 100.0)) * -1.0;

			} else if this.lastDangerState.BeingRevealed {
				baseNerveLossInDanger = (this.nerveLossInDanger * (this.Settings.nerveLossRateWhenTracedPct / 100.0)) * -1.0;
				// TODO - CONVERT TO COMPOSED
				nerveLossBonusMult -= this.GetMemoryBoosterTraceNerveLossBonusMult();
			}

			let totalNerveLossBonusMult: Float = MaxF(nerveLossBonusMult, 0.0);
			let nerveLossInDangerWithBonus: Float = baseNerveLossInDanger * totalNerveLossBonusMult;
		
			DFLog(this, "GetNerveChangeFromDanger() nerveLossInDangerWithBonus: " + ToString(nerveLossInDangerWithBonus));

			return nerveLossInDangerWithBonus;
		
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

	// TODO - Cyberpsychosis?
	public func GetCalculatedNerveMaxInProvidedState(addictionTreatmentDuration: Float, alcoholWithdrawalLevel: Int32, nicotineWithdrawalLevel: Int32, narcoticWithdrawalLevel: Int32, hasEuphoria: Bool) -> Float {
		//DFProfile();
		let needTarget: Float = 100.0;

		if hasEuphoria {
			return needTarget;
		}
		
		let alcoholNeedTargets: array<Float> = this.AlcoholAddictionSystem.GetAddictionNeedLimits();
		let nicotineNeedTargets: array<Float> = this.NicotineAddictionSystem.GetAddictionNeedLimits();
		let narcoticNeedTargets: array<Float> = this.NarcoticAddictionSystem.GetAddictionNeedLimits();

		let alcoholNeedTarget: Float = alcoholNeedTargets[alcoholWithdrawalLevel];
		let nicotineNeedTarget: Float = nicotineNeedTargets[nicotineWithdrawalLevel];
		let narcoticNeedTarget: Float = narcoticNeedTargets[narcoticWithdrawalLevel];

		if Equals(addictionTreatmentDuration, 0.0) {
			needTarget = alcoholNeedTarget < needTarget ? alcoholNeedTarget : needTarget;
			needTarget = nicotineNeedTarget < needTarget ? nicotineNeedTarget : needTarget;
			needTarget = narcoticNeedTarget < needTarget ? narcoticNeedTarget : needTarget;
		}

		//DFLog(this, "alcoholNeedTarget = " + ToString(alcoholNeedTarget));
		//DFLog(this, "nicotineNeedTarget = " + ToString(nicotineNeedTarget));
		//DFLog(this, "narcoticNeedTarget = " + ToString(narcoticNeedTarget));
		//DFLog(this, "needTarget = " + ToString(needTarget));

		return needTarget;
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
			if this.currentDelayedNeedLoss != 0.0 {
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
					
					if deltaToMinThreshold >= AbsF(this.GetAccumulatedDelayedNeedLoss()) {
						this.ChangeNeedValue(this.GetAccumulatedDelayedNeedLoss(), changeValueProps);
					} else {
						this.ChangeNeedValue(-deltaToMinThreshold, changeValueProps);
					}
				}
				this.currentDelayedNeedLoss = 0.0;
			}
        }

		this.AutoSetUpdateMode();
		this.HUDSystem.RefreshHUDUIVisibility();
        this.lastDangerState = dangerState;
    }

	private final func TryToTransitionNerveBreathingEffects() -> Void {
		//DFProfile();
		// Called due to an aim event, a delayed danger transition callback, critically low Nerve, or an Overdose.

		let needStage: Int32 = this.GetNeedStage();
		let needValue: Float = this.GetNeedValue();
		let inDanger: Bool = this.PlayerStateService.GetInDangerFromState(this.lastDangerState);
		let inOverdose: Bool = this.PlayerStateService.GetInOverdose();

		DFLog(this, "TryToTransitionNerveBreathingEffects needStage = " + ToString(needStage) + ", inDanger = " + ToString(inDanger));
		
		if inOverdose {
			DFLog(this, "TryToTransitionNerveBreathingEffects: Starting high breathing FX (In Overdose)");
			this.StopNerveBreathingEffects();

		} else if needStage < 3 {
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

					let overdose: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"DarkFutureStatusEffect.Overdose");
					if IsDefined(overdose) {
						StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Overdose", 11u);
						let notification: DFNotification;
						notification.sfx = DFAudioCue(n"q101_sc_03_v_gasp", 0);
						this.NotificationService.QueueNotification(notification);
					}
					
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
		//DFProfile();
		// :(

		this.TryToTransitionNerveBreathingEffects();
		super.QueuePlayerDeath();
	}

	public final func OnPostPlayerDeathCallback() -> Void {
		//DFProfile();
		this.TryToTransitionNerveBreathingEffects();
		this.StopOverdoseSFX();
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
			changeValueProps.delayPercent = this.nervePercentToDeferPerHumanityLossLevel * Cast<Float>(this.HumanityLossConditionSystem.GetConditionLevel());

			this.ChangeNeedValue(this.GetNerveChangeFromDanger(), changeValueProps);
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
		this.BiocorruptionConditionSystem.RefreshEuphoria();

		DFLog(this, "CyberpsychosisStacks stat value: " + ToString(GameInstance.GetStatsSystem(GetGameInstance()).GetStatValue(Cast<StatsObjectID>(this.player.GetEntityID()), DFEnum_gamedataStatType(n"DarkFutureCyberpsychosisStacks"))));
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
	//	Overdose
	//
	public final func SetOverdoseBehavior(inOverdose: Bool, opt flatlineStacks: Uint32) -> Void {
		//DFProfile();
		let wasInOverdose: Bool = this.PlayerStateService.GetInOverdose();
		let transitionedStates: Bool = false;

		if !wasInOverdose && inOverdose {
			transitionedStates = true;

			if flatlineStacks > 5u {
				let notification: DFNotification;
				notification.allowPlaybackInCombat = true;
				
				let message: DFMessage;
				message.key = n"DarkFutureOverdoseNotification";
				message.type = SimpleMessageType.Negative;
				message.context = DFMessageContext.Overdose;

				notification.message = message;
				notification.audioSceneFact = DFFactNameValue(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.Overdose));
				this.NotificationService.QueueNotification(notification);
			}

			let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
			evt.soundName = n"q101_sc_03_heart_loop";
			this.player.QueueEvent(evt);

			let i: Uint32 = 0u;
			while i < flatlineStacks {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Overdose");
				i += 1u;	
			}

		} else if wasInOverdose && !inOverdose {
			transitionedStates = true;

			this.StopOverdoseSFX();
		}

		if transitionedStates {
			this.PlayerStateService.SetOverdoseState(inOverdose);
			this.TryToTransitionNerveBreathingEffects();
		}
	}

	private final func StopOverdoseSFX() -> Void {
		//DFProfile();
		// Stop the heartbeat SFX.
		let evt: ref<SoundStopEvent> = new SoundStopEvent();
        evt.soundName = n"q101_sc_03_heart_loop";
        this.player.QueueEvent(evt);
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
// -----------------------------------------------------------------------------
// DFNarcoticAddictionSystem
// -----------------------------------------------------------------------------
//
// - Narcotic Addiction gameplay system.
//

module DarkFuture.Addictions

import DarkFuture.Logging.*
import DarkFuture.DelayHelper.*
import DarkFuture.System.*
import DarkFuture.Utils.HoursToGameTimeSeconds
import DarkFuture.Main.{
	DFAddictionDatum,
	DFAddictionUpdateDatum
}
import DarkFuture.Services.{
	DFCyberwareService,
	DFGameStateService,
	DFNotificationService,
	DFAudioCue,
	DFNotification,
	DFMessage,
	DFMessageContext
}
import DarkFuture.Needs.{
	DFEnergySystem,
	DFNerveSystem,
	DFNeedChangeUIFlags
}
import DarkFuture.Gameplay.DFInteractionSystem
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
	let narcoticSystem: ref<DFNarcoticAddictionSystem> = DFNarcoticAddictionSystem.Get();

	if IsSystemEnabledAndRunning(narcoticSystem) {
		let effectTags: array<CName> = evt.staticData.GameplayTags();
		if ArrayContains(effectTags, n"DarkFutureNerveChangeOffset") {
			narcoticSystem.ProcessNarcoticsNerveChangeOffsetEffectRemoved();
		}
	}
    
	return wrappedMethod(evt);
}

public struct DFNarcoticsNerveChangeRange {
	public let min: Float;
	public let max: Float;
}

public class RemoveNarcoticFXCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new RemoveNarcoticFXCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFNarcoticAddictionSystem.Get().removeNarcoticFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFNarcoticAddictionSystem.Get().OnRemoveNarcoticFX();
	}
}

class DFNarcoticAddictionSystemEventListener extends DFAddictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
		return DFNarcoticAddictionSystem.Get();
	}
}

public class DFNarcoticAddictionSystem extends DFAddictionSystemBase {
    private let InteractionSystem: ref<DFInteractionSystem>;
    private let CyberwareService: ref<DFCyberwareService>;
    private let EnergySystem: ref<DFEnergySystem>;

    private let removeNarcoticFXDelayID: DelayID;
    private let removeNarcoticFXDelayInterval: Float = 60.0;

	private let narcoticAddictionMaxStage: Int32 = 4;
	private let narcoticAddictionStageAdvanceAmounts: array<Float>;
	private let narcoticAddictionNerveTargets: array<Float>;
	private let narcoticAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let narcoticAddictionMildWithdrawalDurationInGameTimeSeconds: Float;
	private let narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds: Float;

    // Narcotics Consumable Nerve Change
	private let nerveChangeFromNarcoticsQueue: array<DFNarcoticsNerveChangeRange>;
	private let nerveChangeFromNarcoticsMinTier1: Float = 20.0; // Apply sign at runtime
	private let nerveChangeFromNarcoticsMaxTier1: Float = 20.0;
	private let nerveChangeFromNarcoticsMinTier2: Float = 30.0; // Apply sign at runtime
	private let nerveChangeFromNarcoticsMaxTier2: Float = 30.0;
	private let nerveChangeFromNarcoticsMinTier3: Float = 50.0; // Apply sign at runtime
	private let nerveChangeFromNarcoticsMaxTier3: Float = 50.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNarcoticAddictionSystem> {
		let instance: ref<DFNarcoticAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Addictions.DFNarcoticAddictionSystem") as DFNarcoticAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNarcoticAddictionSystem> {
		return DFNarcoticAddictionSystem.GetInstance(GetGameInstance());
	}

	//
    //  DFSystem Required Methods
    //
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private func GetSystemToggleSettingValue() -> Bool {
		return this.Settings.narcoticAddictionEnabled;
	}

	private func GetSystemToggleSettingString() -> String {
		return "narcoticAddictionEnabled";
	}

	private func DoPostSuspendActions() -> Void {
        super.DoPostSuspendActions();
		this.StopNarcoticFX();
    }

	private func UnregisterAllDelayCallbacks() -> Void {
		this.UnregisterRemoveNarcoticFXCallbacks();
	}
	
	private final func GetSystems() -> Void {
        super.GetSystems();

        let gameInstance = GetGameInstance();
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
        this.CyberwareService = DFCyberwareService.GetInstance(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
    }

    private final func SetupData() -> Void {
		this.narcoticAddictionMildWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.narcoticAddictionMildWithdrawalDurationInGameTimeHours);
		this.narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.narcoticAddictionSevereWithdrawalDurationInGameTimeHours);
		this.narcoticAddictionStageAdvanceAmounts = [
			this.Settings.narcoticAddictionMinAmountStage1,
			this.Settings.narcoticAddictionMinAmountStage2,
			this.Settings.narcoticAddictionMinAmountStage3,
			this.Settings.narcoticAddictionMinAmountStage4,
			-1.0
		];
		this.narcoticAddictionNerveTargets = [100.0, 80.0, 60.0, 40.0, 20.0, 80.0];
		this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage = [
			0.0,
			this.Settings.narcoticAddictionBackoffDurationStage1,
			this.Settings.narcoticAddictionBackoffDurationStage2,
			this.Settings.narcoticAddictionBackoffDurationStage3,
			this.Settings.narcoticAddictionBackoffDurationStage4
		];
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		if ArrayContains(changedSettings, "narcoticAddictionMildWithdrawalDurationInGameTimeHours") {
			this.narcoticAddictionMildWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.narcoticAddictionMildWithdrawalDurationInGameTimeHours);
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				if (withdrawalLevel == 1 || withdrawalLevel == 2 || withdrawalLevel == 5) && this.remainingWithdrawalDurationInGameTimeSeconds > this.narcoticAddictionMildWithdrawalDurationInGameTimeSeconds {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.narcoticAddictionMildWithdrawalDurationInGameTimeSeconds;
				}
			}
		}

		if ArrayContains(changedSettings, "narcoticAddictionSevereWithdrawalDurationInGameTimeHours") {
			this.narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.narcoticAddictionSevereWithdrawalDurationInGameTimeHours);
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				if (withdrawalLevel == 3 || withdrawalLevel == 4) && this.remainingWithdrawalDurationInGameTimeSeconds > this.narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds;
				}
			}
		}

		if ArrayContains(changedSettings, "narcoticAddictionMinAmountStage1") || 
			ArrayContains(changedSettings, "narcoticAddictionMinAmountStage2") || 
			ArrayContains(changedSettings, "narcoticAddictionMinAmountStage3") || 
			ArrayContains(changedSettings, "narcoticAddictionMinAmountStage4") {
			
				this.narcoticAddictionStageAdvanceAmounts = [
					this.Settings.narcoticAddictionMinAmountStage1,
					this.Settings.narcoticAddictionMinAmountStage2,
					this.Settings.narcoticAddictionMinAmountStage3,
					this.Settings.narcoticAddictionMinAmountStage4,
					-1.0
				];

				if IsSystemEnabledAndRunning(this) {
					this.TryToAdvanceAddiction(0.0);
				}
		}

		if ArrayContains(changedSettings, "narcoticAddictionBackoffDurationStage1") || 
			ArrayContains(changedSettings, "narcoticAddictionBackoffDurationStage2") || 
			ArrayContains(changedSettings, "narcoticAddictionBackoffDurationStage3") || 
			ArrayContains(changedSettings, "narcoticAddictionBackoffDurationStage4") {

				this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage = [
					0.0,
					this.Settings.narcoticAddictionBackoffDurationStage1,
					this.Settings.narcoticAddictionBackoffDurationStage2,
					this.Settings.narcoticAddictionBackoffDurationStage3,
					this.Settings.narcoticAddictionBackoffDurationStage4
				];

				if IsSystemEnabledAndRunning(this) {
					if this.remainingBackoffDurationInGameTimeSeconds > this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] {
						this.remainingBackoffDurationInGameTimeSeconds = (this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] * this.Settings.timescale) * 60.0;
					}
				}
		}
	}

    //
    //  Required Overrides
    //
	private final func OnTimeSkipFinishedActual(addictionData: DFAddictionDatum) -> Void {
		this.SetAddictionAmount(addictionData.narcotic.addictionAmount);
		this.SetAddictionStage(addictionData.narcotic.addictionStage);
		this.SetWithdrawalLevel(addictionData.narcotic.withdrawalLevel);
		this.SetRemainingBackoffDurationInGameTimeSeconds(addictionData.narcotic.remainingBackoffDuration);
		this.SetRemainingWithdrawalDurationInGameTimeSeconds(addictionData.narcotic.remainingWithdrawalDuration);
	}

    private final func GetDefaultEffectDuration() -> Float {
        // Not Used
        return 0.0;
    }

	private final func GetEffectDuration() -> Float {
        // Not Used
        return 0.0;
    }

	public func ResetEffectDuration() -> Void {
        // Not Used
    }

	private final func GetAddictionMaxStage() -> Int32 {
        return this.narcoticAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
        return this.Settings.narcoticAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
        // Not Used
        return 0.0;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        return this.narcoticAddictionStageAdvanceAmounts;
    }

	private final func GetAddictionNerveTargets() -> array<Float> {
        return this.narcoticAddictionNerveTargets;
    }

	private final func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
        return this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	private final func GetAddictionAmountLossPerDay() -> Float {
        return this.Settings.narcoticAddictionLossPerDay;
    }

	private final func GetAddictionMinStacksPerStage() -> array<Uint32> {
        // Unused
		return [];
    }

	private final func GetAddictionMildWithdrawalDurationInGameTimeSeconds() -> Float {
        return this.narcoticAddictionMildWithdrawalDurationInGameTimeSeconds;
    }

	private final func GetAddictionSevereWithdrawalDurationInGameTimeSeconds() -> Float {
        return this.narcoticAddictionSevereWithdrawalDurationInGameTimeSeconds;
    }

    private final func DoPostAddictionCureActions() -> Void {
        // None
    }

	private final func DoPostAddictionAdvanceActions() -> Void {
        // None
    }

    private final func PlayWithdrawalAdvanceSFX() -> Void {
		if this.Settings.addictionSFXEnabled {
			let notification: DFNotification;
			notification.sfx = new DFAudioCue(n"ono_v_fall", 10);
			this.NotificationService.QueueNotification(notification);
		}
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
        return n"AddictionWithdrawalNarcotic";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
        return t"DarkFutureStatusEffect.NarcoticWithdrawal_";
    }

	private final func GetAddictionPrimaryStatusEffectTag() -> CName {
        return n"DarkFutureAddictionPrimaryEffectNarcotic";
    }

    private final func QueueAddictionNotification(stage: Int32) -> Void {
		if this.GameStateService.IsValidGameState("QueueNarcoticAddictionNotification", true) {
			let messageKey: CName;
			let messageType: SimpleMessageType;
			switch stage {
				case 4:
					messageKey = n"DarkFutureAddictionNotificationNarcotic04";
					messageType = SimpleMessageType.Negative;
					break;
				case 3:
					messageKey = n"DarkFutureAddictionNotificationNarcotic03";
					messageType = SimpleMessageType.Negative;
					break;
				case 2:
					messageKey = n"DarkFutureAddictionNotificationNarcotic02";
					messageType = SimpleMessageType.Negative;
					break;
				case 1:
					messageKey = n"DarkFutureAddictionNotificationNarcotic01";
					messageType = SimpleMessageType.Negative;
					break;
				case 0:
					messageKey = n"DarkFutureAddictionNotificationNarcoticCured";
					messageType = SimpleMessageType.Neutral;
					break;
			}

			let message: DFMessage;
			message.key = messageKey;
			message.type = messageType;
			message.context = DFMessageContext.NarcoticAddiction;

			if this.Settings.addictionMessagesEnabled || Equals(message.type, SimpleMessageType.Neutral) {
				this.NotificationService.QueueMessage(message);
			}
		}
    }

	private final func AddictionPrimaryEffectAppliedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			// Clear any active withdrawal effects or backoff durations.
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"AddictionWithdrawalNarcotic") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"AddictionWithdrawalNarcotic");
			}
			this.SetWithdrawalLevel(0);
			this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);
			this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
			this.NerveSystem.UpdateNeedHUDUI();

			// Try to advance the player's addiction.
			if ArrayContains(effectGameplayTags, n"DarkFutureAddictionNarcoticWeak") {
				this.TryToAdvanceAddiction(this.GetAddictionAmountOnUseLow());
			} else if ArrayContains(effectGameplayTags, n"DarkFutureAddictionNarcoticStrong") {
				this.TryToAdvanceAddiction(this.GetAddictionAmountOnUseHigh());
			}

			if ArrayContains(effectGameplayTags, n"DarkFutureConsumableNarcoticRandomNerveChange") {
				let nerveChangeRange: DFNarcoticsNerveChangeRange;

				if Equals(this.InteractionSystem.GetLastAttemptedChoiceCaption(), "[Take inhaler]") {
					// q003 - Dum Dum inhaler scene
					nerveChangeRange.min = 20.0;
					nerveChangeRange.max = 20.0;
					ArrayPush(this.nerveChangeFromNarcoticsQueue, nerveChangeRange);
				} else {
					if ArrayContains(effectGameplayTags, n"DarkFutureConsumableNarcoticRandomNerveChangeTier1") {
						nerveChangeRange.min = -1.0 * this.nerveChangeFromNarcoticsMinTier1;
						nerveChangeRange.max = this.nerveChangeFromNarcoticsMaxTier1;
						ArrayPush(this.nerveChangeFromNarcoticsQueue, nerveChangeRange);
					} else if ArrayContains(effectGameplayTags, n"DarkFutureConsumableNarcoticRandomNerveChangeTier2") {
						nerveChangeRange.min = -1.0 * this.nerveChangeFromNarcoticsMinTier2;
						nerveChangeRange.max = this.nerveChangeFromNarcoticsMaxTier2;
						ArrayPush(this.nerveChangeFromNarcoticsQueue, nerveChangeRange);
					} else if ArrayContains(effectGameplayTags, n"DarkFutureConsumableNarcoticRandomNerveChangeTier3") {
						nerveChangeRange.min = -1.0 * this.nerveChangeFromNarcoticsMinTier3;
						nerveChangeRange.max = this.nerveChangeFromNarcoticsMaxTier3;
						ArrayPush(this.nerveChangeFromNarcoticsQueue, nerveChangeRange);
					}
				}
				
				DFLog(this.debugEnabled, this, "nerveChangeFromNarcoticsQueue = " + ToString(this.nerveChangeFromNarcoticsQueue));

				// Add a stack of the Nerve Change Offset effect.
				StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.NerveChangeOffset");
			}
		}
    }

	private func AddictionPrimaryEffectRemovedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			DFLog(this.debugEnabled, this, "ProcessNarcoticPrimaryEffectRemoved");
			// Does the player have the Narcotic Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNarcotic") {
				this.StopNarcoticFX();
                
                if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
    }

    //
    //  System-Specific Methods
    //
    private final func GetAddictionAmountOnUseLow() -> Float {
        return this.Settings.narcoticAddictionAmountOnUseLow;
    }

    private final func GetAddictionAmountOnUseHigh() -> Float {
        return this.Settings.narcoticAddictionAmountOnUseHigh;
    }

    public final func ProcessNarcoticsNerveChangeOffsetEffectRemoved() -> Void {
		if ArraySize(this.nerveChangeFromNarcoticsQueue) > 0 {
            DFLog(this.debugEnabled, this, "ProcessNarcoticsNerveChangeOffsetEffectRemoved Queue Before: " + ToString(this.nerveChangeFromNarcoticsQueue));
			let nerveChangeRange: DFNarcoticsNerveChangeRange = ArrayPop(this.nerveChangeFromNarcoticsQueue);
            DFLog(this.debugEnabled, this, "ProcessNarcoticsNerveChangeOffsetEffectRemoved Queue After: " + ToString(this.nerveChangeFromNarcoticsQueue));
			let nerveChange: Float = RandRangeF(nerveChangeRange.min, nerveChangeRange.max);
			DFLog(this.debugEnabled, this, "Random nerveChange = " + ToString(nerveChange));

			if nerveChange < 0.0 {
				nerveChange *= this.CyberwareService.GetNerveLossFromNarcoticsBonusMult();
			} else {
				if this.Settings.narcoticsSFXEnabled {
					let notification: DFNotification;
					notification.sfx = new DFAudioCue(n"ono_v_laughs_soft", 10);
					this.NotificationService.QueueNotification(notification);
				}   
			}

			this.StartNarcoticFX(nerveChange);
			this.RegisterRemoveNarcoticFXInitialCallback();

            let uiFlags: DFNeedChangeUIFlags;
            uiFlags.forceMomentaryUIDisplay = true;

			this.NerveSystem.ChangeNeedValue(nerveChange, uiFlags, false, true);
		}
	}

    private final func StartNarcoticFX(nerveChange: Float) -> Void {
		GameObjectEffectHelper.StartEffectEvent(this.player, n"status_drugged_heavy", false, null, true);
		GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 3.00);

		if nerveChange < 0.0 {
			GameObjectEffectHelper.StartEffectEvent(this.player, n"stagger_effect", false, null, true);
		}
	}

    public final func OnRemoveNarcoticFX() -> Void {
		this.StopNarcoticFX();
	}

    private final func StopNarcoticFX() -> Void {
		GameObjectEffectHelper.BreakEffectLoopEvent(this.player, n"status_drugged_heavy");
		GameObject.SetAudioParameter(this.player, n"vfx_fullscreen_drugged_level", 0.00);
	}

    //
    //  Registration
    //
    private final func RegisterRemoveNarcoticFXInitialCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, RemoveNarcoticFXCallback.Create(), this.removeNarcoticFXDelayID, this.removeNarcoticFXDelayInterval);
	}

    //
    //  Unregistration
    //
    private final func UnregisterRemoveNarcoticFXCallbacks() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.removeNarcoticFXDelayID);
	}
}
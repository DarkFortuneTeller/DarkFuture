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
import DarkFuture.Utils.{
	HoursToGameTimeSeconds,
	GameTimeSecondsToHours,
	RunGuard
}
import DarkFuture.Main.{
	DFAddictionDatum,
	DFAddictionUpdateDatum,
	DFTempEnergyItemType
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
    private let EnergySystem: ref<DFEnergySystem>;

	private let narcoticDefaultEffectDuration: Float = 300.0;

    private let removeNarcoticFXDelayID: DelayID;
    private let removeNarcoticFXDelayInterval: Float = 60.0;

	private let narcoticAddictionMaxStage: Int32 = 4;
	private let narcoticAddictionStageAdvanceAmounts: array<Float>;
	private let narcoticAddictionNerveLimits: array<Float>;
	private let narcoticAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let narcoticAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;

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
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
    }

    private final func SetupData() -> Void {
		this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds = [
			0.0,
			HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage1WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage2WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage3WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage4WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.narcoticAddictionCessationDurationInGameTimeHours)
		];
		this.narcoticAddictionStageAdvanceAmounts = [
			this.Settings.narcoticAddictionMinAmountStage1,
			this.Settings.narcoticAddictionMinAmountStage2,
			this.Settings.narcoticAddictionMinAmountStage3,
			this.Settings.narcoticAddictionMinAmountStage4,
			-1.0
		];
		this.narcoticAddictionNerveLimits = [100.0, 80.0, 60.0, 40.0, 20.0, 80.0];
		this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage = [
			0.0,
			this.Settings.narcoticAddictionBackoffDurationStage1,
			this.Settings.narcoticAddictionBackoffDurationStage2,
			this.Settings.narcoticAddictionBackoffDurationStage3,
			this.Settings.narcoticAddictionBackoffDurationStage4
		];
		this.UpdateNarcoticWithdrawalEffectDisplayData();
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		if ArrayContains(changedSettings, "narcoticAddictionStage1WithdrawalDurationInGameTimeHours") ||
		   ArrayContains(changedSettings, "narcoticAddictionStage2WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "narcoticAddictionStage3WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "narcoticAddictionStage4WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "narcoticAddictionCessationDurationInGameTimeHours") {
			this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds = [
				0.0,
				HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage1WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage2WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage3WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.narcoticAddictionStage4WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.narcoticAddictionCessationDurationInGameTimeHours)
			];
			this.UpdateNarcoticWithdrawalEffectDisplayData();
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				let addictionStage: Int32 = this.GetAddictionStage();
				if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSeconds > this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
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
	private final func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
		return addictionData.narcotic;
	}

    private final func GetDefaultEffectDuration() -> Float {
        return this.narcoticDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
        let durationOverride: Float = this.CyberwareService.GetNarcoticsEffectDurationOverride();
		if durationOverride > 0.0 {
			return durationOverride;
		} else {
			return this.GetDefaultEffectDuration();
		}
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

	private final func GetAddictionNerveLimits() -> array<Float> {
        return this.narcoticAddictionNerveLimits;
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

	private func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
        return this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds;
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
		if this.GameStateService.IsValidGameState(this, true) {
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

	public final func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			// Addiction-Specific - Only continue if system running.
			if RunGuard(this) { return; }

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

			if IsSystemEnabledAndRunning(this.NerveSystem) && ArrayContains(effectGameplayTags, n"DarkFutureAddictionNarcoticStrong") {
				if Equals(this.InteractionSystem.GetLastAttemptedChoiceCaption(), GetLocalizedTextByKey(this.InteractionSystem.locKey_Interaction_Q003TakeInhaler)) {
					this.EnergySystem.TryToApplyEnergizedStacks(3u, DFTempEnergyItemType.Stimulant, true, false);
					
					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;
					uiFlags.instantUIChange = false;
					uiFlags.forceBright = true;
					uiFlags.momentaryDisplayIgnoresSceneTier = true;
					this.NerveSystem.ChangeNeedValue(this.Settings.nerveStrongNarcoticsRev2, uiFlags);
				}
			}
		}
    }

	public final func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		// Addiction-Specific - Only continue if system running.
		if RunGuard(this) { return; }

        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			DFLog(this, "ProcessNarcoticPrimaryEffectRemoved");
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

	private final func UpdateActiveNarcoticEffectDuration(effectID: TweakDBID) -> Void {
		if NotEquals(this.GetEffectDuration(), this.GetDefaultEffectDuration()) {
			GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.GetEffectDuration());
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

	private final func UpdateNarcoticWithdrawalEffectDisplayData() -> Void {
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[5]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[1]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[1]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[2]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[2]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[3]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[3]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNerveLimits[4]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_Cessation_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticWithdrawal_04_NoProgression_UIData");
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
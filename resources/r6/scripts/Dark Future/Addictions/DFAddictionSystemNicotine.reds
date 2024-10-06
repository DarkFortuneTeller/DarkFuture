// -----------------------------------------------------------------------------
// DFNicotineAddictionSystem
// -----------------------------------------------------------------------------
//
// - Nicotine Addiction gameplay system.
//

module DarkFuture.Addictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.{
	HoursToGameTimeSeconds,
	GameTimeSecondsToHours,
	RunGuard
}
import DarkFuture.Main.{
	DFAddictionDatum,
	DFAddictionUpdateDatum
}
import DarkFuture.Services.{
	DFGameStateService,
	DFNotificationService,
	DFCyberwareService,
	DFAudioCue,
	DFNotification,
	DFMessage,
	DFMessageContext
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Settings.DFSettings

class DFNicotineAddictionSystemEventListener extends DFAddictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
		return DFNicotineAddictionSystem.Get();
	}
}

public class DFNicotineAddictionSystem extends DFAddictionSystemBase {
    private let nicotineDefaultEffectDuration: Float = 300.0;

	private let nicotineAddictionMaxStage: Int32 = 4;
	private let nicotineAddictionStageAdvanceAmounts: array<Float>;
	private let nicotineAddictionNerveLimits: array<Float>;
	private let nicotineAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let nicotineAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNicotineAddictionSystem> {
		let instance: ref<DFNicotineAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Addictions.DFNicotineAddictionSystem") as DFNicotineAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNicotineAddictionSystem> {
		return DFNicotineAddictionSystem.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private func GetSystemToggleSettingValue() -> Bool {
		return this.Settings.nicotineAddictionEnabled;
	}

	private func GetSystemToggleSettingString() -> String {
		return "nicotineAddictionEnabled";
	}

    private final func SetupData() -> Void {
		this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds = [
			0.0,
			HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage1WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage2WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage3WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage4WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.nicotineAddictionCessationDurationInGameTimeHours)
		];
		this.nicotineAddictionStageAdvanceAmounts = [
			this.Settings.nicotineAddictionMinAmountStage1,
			this.Settings.nicotineAddictionMinAmountStage2,
			this.Settings.nicotineAddictionMinAmountStage3,
			this.Settings.nicotineAddictionMinAmountStage4,
			-1.0
		];
		this.nicotineAddictionNerveLimits = [100.0, 80.0, 70.0, 60.0, 50.0, 80.0];
		this.UpdateNicotineWithdrawalEffectDisplayData();
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		if ArrayContains(changedSettings, "nicotineAddictionStage1WithdrawalDurationInGameTimeHours") ||
		   ArrayContains(changedSettings, "nicotineAddictionStage2WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "nicotineAddictionStage3WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "nicotineAddictionStage4WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "nicotineAddictionCessationDurationInGameTimeHours") {
			this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds = [
				0.0,
				HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage1WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage2WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage3WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.nicotineAddictionStage4WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.nicotineAddictionCessationDurationInGameTimeHours)
			];
			this.UpdateNicotineWithdrawalEffectDisplayData();
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				let addictionStage: Int32 = this.GetAddictionStage();
				if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSeconds > this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
				}
			}
		}

		if ArrayContains(changedSettings, "nicotineAddictionMinAmountStage1") || 
			ArrayContains(changedSettings, "nicotineAddictionMinAmountStage2") || 
			ArrayContains(changedSettings, "nicotineAddictionMinAmountStage3") || 
			ArrayContains(changedSettings, "nicotineAddictionMinAmountStage4") {
			
				this.nicotineAddictionStageAdvanceAmounts = [
					this.Settings.nicotineAddictionMinAmountStage1,
					this.Settings.nicotineAddictionMinAmountStage2,
					this.Settings.nicotineAddictionMinAmountStage3,
					this.Settings.nicotineAddictionMinAmountStage4,
					-1.0
				];

				if IsSystemEnabledAndRunning(this) {
					this.TryToAdvanceAddiction(0.0);
				}
		}

		if ArrayContains(changedSettings, "nicotineAddictionBackoffDurationStage1") || 
			ArrayContains(changedSettings, "nicotineAddictionBackoffDurationStage2") || 
			ArrayContains(changedSettings, "nicotineAddictionBackoffDurationStage3") || 
			ArrayContains(changedSettings, "nicotineAddictionBackoffDurationStage4") {

				this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage = [
					0.0,
					this.Settings.nicotineAddictionBackoffDurationStage1,
					this.Settings.nicotineAddictionBackoffDurationStage2,
					this.Settings.nicotineAddictionBackoffDurationStage3,
					this.Settings.nicotineAddictionBackoffDurationStage4
				];

				if IsSystemEnabledAndRunning(this) {
					if this.remainingBackoffDurationInGameTimeSeconds > this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] {
						this.remainingBackoffDurationInGameTimeSeconds = (this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] * this.Settings.timescale) * 60.0;
					}
				}
		}
	}

    //
    //  Required Overrides
    //
	private final func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
		return addictionData.nicotine;
	}

    private final func GetDefaultEffectDuration() -> Float {
        return this.nicotineDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
		let durationOverride: Float = this.CyberwareService.GetNicotineEffectDurationOverride();
		if durationOverride > 0.0 {
			return durationOverride;
		} else {
			return this.GetDefaultEffectDuration();
		}
    }

	private final func GetAddictionMaxStage() -> Int32 {
        return this.nicotineAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
        return this.Settings.nicotineAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
        return this.Settings.nicotineAddictionAmountOnUse;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        return this.nicotineAddictionStageAdvanceAmounts;
    }

	private final func GetAddictionNerveLimits() -> array<Float> {
        return this.nicotineAddictionNerveLimits;
    }

	private final func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
        return this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	private final func GetAddictionAmountLossPerDay() -> Float {
        return this.Settings.nicotineAddictionLossPerDay;
    }

	private final func GetAddictionMinStacksPerStage() -> array<Uint32> {
		// Unused
		return [];
    }

	private func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
        return this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds;
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

			let random: Int32 = RandRange(1, 100);
			if random >= 50 {
				if this.GetAddictionStage() <= 2 {
					notification.sfx = new DFAudioCue(n"g_sc_v_sickness_cough_light", 10);
				} else {
					random = RandRange(1, 100);
					if random > 25 {
						notification.sfx = new DFAudioCue(n"g_sc_v_sickness_cough_hard", 10);
					} else {
						notification.sfx = new DFAudioCue(n"g_sc_v_sickness_cough_light", 10);
					}
				}
			} else {
				notification.sfx = new DFAudioCue(n"ono_v_bump", 10);
			}

			this.NotificationService.QueueNotification(notification);
		}
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
        return n"AddictionWithdrawalNicotine";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
        return t"DarkFutureStatusEffect.NicotineWithdrawal_";
    }

	private final func GetAddictionPrimaryStatusEffectTag() -> CName {
        return n"DarkFutureAddictionPrimaryEffectNicotine";
    }

    private final func QueueAddictionNotification(stage: Int32) -> Void {
		if this.GameStateService.IsValidGameState("QueueNicotineAddictionNotification", true) {
			let messageKey: CName;
			let messageType: SimpleMessageType;
			switch stage {
				case 4:
					messageKey = n"DarkFutureAddictionNotificationNicotine04";
					messageType = SimpleMessageType.Negative;
					break;
				case 3:
					messageKey = n"DarkFutureAddictionNotificationNicotine03";
					messageType = SimpleMessageType.Negative;
					break;
				case 2:
					messageKey = n"DarkFutureAddictionNotificationNicotine02";
					messageType = SimpleMessageType.Negative;
					break;
				case 1:
					messageKey = n"DarkFutureAddictionNotificationNicotine01";
					messageType = SimpleMessageType.Negative;
					break;
				case 0:
					messageKey = n"DarkFutureAddictionNotificationNicotineCured";
					messageType = SimpleMessageType.Neutral;
					break;
			}

			let message: DFMessage;
			message.key = messageKey;
			message.type = messageType;
			message.context = DFMessageContext.NicotineAddiction;

			if this.Settings.addictionMessagesEnabled || Equals(message.type, SimpleMessageType.Neutral) {
				this.NotificationService.QueueMessage(message);
			}
		}
    }

	public final func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
			// Addiction-Specific - Only continue if system running.
			if RunGuard(this) { return; }

			// Clear any active withdrawal effects or backoff durations.
			if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"AddictionWithdrawalNicotine") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"AddictionWithdrawalNicotine");
			}
			this.SetWithdrawalLevel(0);
			this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);
			this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
			this.NerveSystem.UpdateNeedHUDUI();

			// Try to advance the player's addiction.
			this.TryToAdvanceAddiction(this.GetAddictionAmountOnUse());
		}
    }

	public final func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		// Addiction-Specific - Only continue if system running.
		if RunGuard(this) { return; }

        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
			DFLog(this.debugEnabled, this, "ProcessNicotinePrimaryEffectRemoved");
			// Does the player have the Nicotine Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNicotine") {
				if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
    }

    //
    //  System-Specific Methods
    //
	private final func UpdateActiveNicotineEffectDuration(effectID: TweakDBID) -> Void {
		if NotEquals(this.GetEffectDuration(), this.GetDefaultEffectDuration()) {
			GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.GetEffectDuration());
		}
	}

	public final func SetNicotineAddictionBackoffDurations() -> Void {
		let cyberwareModifier: Float = (this.GetDefaultEffectDuration() / 60.0) - (this.GetEffectDuration() / 60.0);
		let stage1BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage1 + cyberwareModifier;
		let stage2BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage2 + cyberwareModifier;
		let stage3BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage3 + cyberwareModifier;
		let stage4BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage4 + cyberwareModifier;
		this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage = [0.0, stage1BackoffDuration, stage2BackoffDuration, stage3BackoffDuration, stage4BackoffDuration];
	}

	private final func UpdateNicotineWithdrawalEffectDisplayData() -> Void {
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[5]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[1]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[1]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[2]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[2]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[3]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[3]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNerveLimits[4]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_Cessation_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_01_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_01_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_02_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_02_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_03_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_03_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_04_NoProgression_UIData");
	}
}
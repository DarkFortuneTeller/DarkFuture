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
	DFRunGuard
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
		//DFProfile();
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
		//DFProfile();
		let instance: ref<DFNicotineAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNicotineAddictionSystem>()) as DFNicotineAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNicotineAddictionSystem> {
		//DFProfile();
		return DFNicotineAddictionSystem.GetInstance(GetGameInstance());
	}

	//
	//	DFSystem Required Methods
	//
	private final func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
		return this.Settings.nicotineAddictionEnabled;
	}

	private func GetSystemToggleSettingString() -> String {
		//DFProfile();
		return "nicotineAddictionEnabled";
	}

    public final func SetupData() -> Void {
		//DFProfile();
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
		//DFProfile();
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
		//DFProfile();
		return addictionData.nicotine;
	}

    public final func GetDefaultEffectDuration() -> Float {
		//DFProfile();
        return this.nicotineDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
		//DFProfile();
		let durationOverride: Float = this.CyberwareService.GetNicotineEffectDurationOverride();
		if durationOverride > 0.0 {
			return durationOverride;
		} else {
			return this.GetDefaultEffectDuration();
		}
    }

	private final func GetAddictionMaxStage() -> Int32 {
		//DFProfile();
        return this.nicotineAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
		//DFProfile();
        return this.Settings.nicotineAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
		//DFProfile();
        return this.Settings.nicotineAddictionAmountOnUse;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
		//DFProfile();
        return this.nicotineAddictionStageAdvanceAmounts;
    }

	public final func GetAddictionNerveLimits() -> array<Float> {
		//DFProfile();
        return this.nicotineAddictionNerveLimits;
    }

	public func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
		//DFProfile();
        return this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	public final func GetAddictionAmountLossPerDay() -> Float {
		//DFProfile();
        return this.Settings.nicotineAddictionLossPerDay;
    }

	public final func GetAddictionMinStacksPerStage() -> array<Uint32> {
		//DFProfile();
		// Unused
		return [];
    }

	public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
		//DFProfile();
        return this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds;
    }

    private final func DoPostAddictionCureActions() -> Void {
		//DFProfile();
        // None
    }

	private final func DoPostAddictionAdvanceActions() -> Void {
		//DFProfile();
        // None
    }

    public final func PlayWithdrawalAdvanceSFX() -> Void {
		//DFProfile();
		if this.Settings.addictionSFXEnabled {
			let notification: DFNotification;

			let random: Int32 = RandRange(1, 100);
			if random >= 50 {
				if this.GetAddictionStage() <= 2 {
					notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_light", 5);
				} else {
					random = RandRange(1, 100);
					if random > 25 {
						notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_hard", 5);
					} else {
						notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_light", 5);
					}
				}
			} else {
				notification.sfx = DFAudioCue(n"ono_v_bump", 5);
			}

			this.NotificationService.QueueNotification(notification);
		}
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
		//DFProfile();
        return n"AddictionWithdrawalNicotine";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
		//DFProfile();
        return t"DarkFutureStatusEffect.NicotineWithdrawal_";
    }

	public final func GetAddictionPrimaryStatusEffectTag() -> CName {
		//DFProfile();
        return n"DarkFutureAddictionPrimaryEffectNicotine";
    }

	public final func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		//DFProfile();
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
			// Addiction-Specific - Only continue if system running.
			if DFRunGuard(this) { return; }

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
		//DFProfile();
		// Addiction-Specific - Only continue if system running.
		if DFRunGuard(this) { return; }

        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNicotine") {
			DFLog(this, "ProcessNicotinePrimaryEffectRemoved");
			// Does the player have the Nicotine Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNicotine") {
				if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
    }

	public final func GetWithdrawalAnimationLowFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationNicotineLow";
	}

    public final func GetWithdrawalAnimationHighFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationNicotineHigh";
	}

	private final func GetAddictionNotificationMessageKeyStage1() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNicotine01";
	}

    private final func GetAddictionNotificationMessageKeyStage2() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNicotine02";
	}

    private final func GetAddictionNotificationMessageKeyStage3() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNicotine03";
	}

    private final func GetAddictionNotificationMessageKeyStage4() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNicotine04";
	}

    private final func GetAddictionNotificationMessageKeyCured() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNicotineCured";
	}

	private final func GetAddictionNotificationMessageContext() -> DFMessageContext {
		//DFProfile();
		return DFMessageContext.NicotineAddiction;
	}

	private final func GetAddictionTherapyResponseIndexFact() -> CName {
		//DFProfile();
		return n"df_fact_therapy_nicotine_response";
	}

	private final func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
		return n"df_fact_action_set_therapy_addiction_nicotine_state_index";
    }

    //
    //  System-Specific Methods
    //
	public final func UpdateActiveNicotineEffectDuration(effectID: TweakDBID) -> Void {
		//DFProfile();
		if NotEquals(this.GetEffectDuration(), this.GetDefaultEffectDuration()) {
			GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.GetEffectDuration());
		}
	}

	public final func SetNicotineAddictionBackoffDurations() -> Void {
		//DFProfile();
		let cyberwareModifier: Float = (this.GetDefaultEffectDuration() / 60.0) - (this.GetEffectDuration() / 60.0);
		let stage1BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage1 + cyberwareModifier;
		let stage2BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage2 + cyberwareModifier;
		let stage3BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage3 + cyberwareModifier;
		let stage4BackoffDuration: Float = this.Settings.nicotineAddictionBackoffDurationStage4 + cyberwareModifier;
		this.nicotineAddictionBackoffDurationsInRealTimeMinutesByStage = [0.0, stage1BackoffDuration, stage2BackoffDuration, stage3BackoffDuration, stage4BackoffDuration];
	}

	private final func UpdateNicotineWithdrawalEffectDisplayData() -> Void {
		//DFProfile();
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
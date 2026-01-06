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
	DFRunGuard
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
	DFNeedChangeUIFlags,
	DFChangeNeedValueProps
}
import DarkFuture.Gameplay.DFInteractionSystem
import DarkFuture.Settings.DFSettings

class DFNarcoticAddictionSystemEventListener extends DFAddictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
		//DFProfile();
		return DFNarcoticAddictionSystem.Get();
	}
}

public class DFNarcoticAddictionSystem extends DFAddictionSystemBase {
    private let InteractionSystem: ref<DFInteractionSystem>;
    private let EnergySystem: ref<DFEnergySystem>;

	private let narcoticDefaultEffectDuration: Float = 300.0;

	private let narcoticAddictionMaxStage: Int32 = 4;
	private let narcoticAddictionStageAdvanceAmounts: array<Float>;
	private let narcoticAddictionNerveLimits: array<Float>;
	private let narcoticAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let narcoticAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNarcoticAddictionSystem> {
		//DFProfile();
		let instance: ref<DFNarcoticAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNarcoticAddictionSystem>()) as DFNarcoticAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFNarcoticAddictionSystem> {
		//DFProfile();
		return DFNarcoticAddictionSystem.GetInstance(GetGameInstance());
	}

	//
    //  DFSystem Required Methods
    //
	private final func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
		return this.Settings.narcoticAddictionEnabled;
	}

	private func GetSystemToggleSettingString() -> String {
		//DFProfile();
		return "narcoticAddictionEnabled";
	}

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
        super.DoPostSuspendActions();
    }

	public func UnregisterAllDelayCallbacks() -> Void {}
	
	public final func GetSystems() -> Void {
		//DFProfile();
        super.GetSystems();

        let gameInstance = GetGameInstance();
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
    }

    public final func SetupData() -> Void {
		//DFProfile();
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
		//DFProfile();
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
		//DFProfile();
		return addictionData.narcotic;
	}

    public final func GetDefaultEffectDuration() -> Float {
		//DFProfile();
        return this.narcoticDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
		//DFProfile();
        let durationOverride: Float = this.CyberwareService.GetNarcoticsEffectDurationOverride();
		if durationOverride > 0.0 {
			return durationOverride;
		} else {
			return this.GetDefaultEffectDuration();
		}
    }

	private final func GetAddictionMaxStage() -> Int32 {
		//DFProfile();
        return this.narcoticAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
		//DFProfile();
        return this.Settings.narcoticAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
		//DFProfile();
        // Not Used
        return 0.0;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
		//DFProfile();
        return this.narcoticAddictionStageAdvanceAmounts;
    }

	public final func GetAddictionNerveLimits() -> array<Float> {
		//DFProfile();
        return this.narcoticAddictionNerveLimits;
    }

	public func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
		//DFProfile();
        return this.narcoticAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	public final func GetAddictionAmountLossPerDay() -> Float {
		//DFProfile();
        return this.Settings.narcoticAddictionLossPerDay;
    }

	public final func GetAddictionMinStacksPerStage() -> array<Uint32> {
		//DFProfile();
        // Unused
		return [];
    }

	public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
		//DFProfile();
        return this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds;
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
			notification.sfx = DFAudioCue(n"ono_v_fall", 5);
			this.NotificationService.QueueNotification(notification);
		}
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
		//DFProfile();
        return n"AddictionWithdrawalNarcotic";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
		//DFProfile();
        return t"DarkFutureStatusEffect.NarcoticWithdrawal_";
    }

	public final func GetAddictionPrimaryStatusEffectTag() -> CName {
		//DFProfile();
        return n"DarkFutureAddictionPrimaryEffectNarcotic";
    }

	public final func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		//DFProfile();
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			// Addiction-Specific - Only continue if system running.
			if DFRunGuard(this) { return; }

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
					
					let changeNeedValueProps: DFChangeNeedValueProps;

					let uiFlags: DFNeedChangeUIFlags;
					uiFlags.forceMomentaryUIDisplay = true;
					uiFlags.instantUIChange = false;
					uiFlags.forceBright = true;
					uiFlags.momentaryDisplayIgnoresSceneTier = true;

					changeNeedValueProps.uiFlags = uiFlags;
					this.NerveSystem.ChangeNeedValue(this.Settings.nerveStrongNarcoticsRev2, changeNeedValueProps);
				}
			}
		}
    }

	public final func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		//DFProfile();
		// Addiction-Specific - Only continue if system running.
		if DFRunGuard(this) { return; }

        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectNarcotic") {
			DFLog(this, "ProcessNarcoticPrimaryEffectRemoved");
			// Does the player have the Narcotic Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectNarcotic") {
                if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
    }

	public final func GetWithdrawalAnimationLowFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationNarcoticLow";
	}

    public final func GetWithdrawalAnimationHighFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationNarcoticHigh";
	}

	private final func GetAddictionNotificationMessageKeyStage1() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNarcotic01";
	}

    private final func GetAddictionNotificationMessageKeyStage2() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNarcotic02";
	}

    private final func GetAddictionNotificationMessageKeyStage3() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNarcotic03";
	}

    private final func GetAddictionNotificationMessageKeyStage4() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNarcotic04";
	}

    private final func GetAddictionNotificationMessageKeyCured() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationNarcoticCured";
	}

	private final func GetAddictionNotificationMessageContext() -> DFMessageContext {
		//DFProfile();
		return DFMessageContext.NarcoticAddiction;
	}

	private final func GetAddictionTherapyResponseIndexFact() -> CName {
		//DFProfile();
		return n"df_fact_therapy_narcotics_response";
	}

	private final func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
		return n"df_fact_action_set_therapy_addiction_narcotics_state_index";
    }

    //
    //  System-Specific Methods
    //
    private final func GetAddictionAmountOnUseLow() -> Float {
		//DFProfile();
        return this.Settings.narcoticAddictionAmountOnUseLow;
    }

    private final func GetAddictionAmountOnUseHigh() -> Float {
		//DFProfile();
        return this.Settings.narcoticAddictionAmountOnUseHigh;
    }

	public final func UpdateActiveNarcoticEffectDuration(effectID: TweakDBID) -> Void {
		//DFProfile();
		if NotEquals(this.GetEffectDuration(), this.GetDefaultEffectDuration()) {
			GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.GetEffectDuration());
		}
	}

	private final func UpdateNarcoticWithdrawalEffectDisplayData() -> Void {
		//DFProfile();
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
}
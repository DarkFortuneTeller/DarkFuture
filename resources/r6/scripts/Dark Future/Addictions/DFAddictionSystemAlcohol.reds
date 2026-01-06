// -----------------------------------------------------------------------------
// DFAlcoholAddictionSystem
// -----------------------------------------------------------------------------
//
// - Alcohol Addiction gameplay system.
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
	DFAddictionUpdateDatum,
	MainSystemItemConsumedEvent
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
import DarkFuture.Addictions.DFAddictionSystemBase
import DarkFuture.Settings.DFSettings

class DFAlcoholAddictionSystemEventListener extends DFAddictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
		//DFProfile();
		return DFAlcoholAddictionSystem.Get();
	}

	public cb func OnLoad() {
		//DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemItemConsumedEvent", this, n"OnMainSystemItemConsumedEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
		//DFProfile();
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI());
    }
}

public class DFAlcoholAddictionSystem extends DFAddictionSystemBase {
	private let alcoholDefaultEffectDuration: Float = 30.0;
	private let alcoholAddictionMaxStage: Int32 = 4;
	private let alcoholAddictionStageAdvanceAmounts: array<Float>;
	private let alcoholAddictionNerveLimits: array<Float>;
	private let alcoholAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let alcoholAddictionMinStacksPerStage: array<Uint32>;
	private let alcoholAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;
	private let painTolerantMinStackCount: Uint32 = 4u;

    //
    //  System Methods
    //
    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFAlcoholAddictionSystem> {
		//DFProfile();
		let instance: ref<DFAlcoholAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFAlcoholAddictionSystem>()) as DFAlcoholAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFAlcoholAddictionSystem> {
		//DFProfile();
		return DFAlcoholAddictionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
	private final func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

	public final func GetSystemToggleSettingValue() -> Bool {
		//DFProfile();
		return this.Settings.alcoholAddictionEnabled;
	}

	private final func GetSystemToggleSettingString() -> String {
		//DFProfile();
		return "alcoholAddictionEnabled";
	}

    public final func SetupData() -> Void {
		//DFProfile();
		this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds = [
			0.0,
			HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage1WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage2WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage3WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage4WithdrawalDurationInGameTimeHours),
			HoursToGameTimeSeconds(this.Settings.alcoholAddictionCessationDurationInGameTimeHours)
		];
		this.alcoholAddictionStageAdvanceAmounts = [
			this.Settings.alcoholAddictionMinAmountStage1,
			this.Settings.alcoholAddictionMinAmountStage2,
			this.Settings.alcoholAddictionMinAmountStage3,
			this.Settings.alcoholAddictionMinAmountStage4,
			-1.0
		];
		this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage = [
			0.0,
			this.Settings.alcoholAddictionBackoffDurationStage1,
			this.Settings.alcoholAddictionBackoffDurationStage2,
			this.Settings.alcoholAddictionBackoffDurationStage3,
			this.Settings.alcoholAddictionBackoffDurationStage4
		];
		this.alcoholAddictionMinStacksPerStage = [0u, 2u, 3u, 4u, 4u];
		this.alcoholAddictionNerveLimits = [100.0, 70.0, 55.0, 40.0, 25.0, 80.0];
		this.UpdateAlcoholWithdrawalEffectDisplayData();
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		//DFProfile();
		if ArrayContains(changedSettings, "alcoholAddictionStage1WithdrawalDurationInGameTimeHours") ||
		   ArrayContains(changedSettings, "alcoholAddictionStage2WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "alcoholAddictionStage3WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "alcoholAddictionStage4WithdrawalDurationInGameTimeHours") || 
		   ArrayContains(changedSettings, "alcoholAddictionCessationDurationInGameTimeHours") {
			this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds = [
				0.0,
				HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage1WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage2WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage3WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.alcoholAddictionStage4WithdrawalDurationInGameTimeHours),
				HoursToGameTimeSeconds(this.Settings.alcoholAddictionCessationDurationInGameTimeHours)
			];
			this.UpdateAlcoholWithdrawalEffectDisplayData();
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				let addictionStage: Int32 = this.GetAddictionStage();
				if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSeconds > this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
				}
			}
		}

		if ArrayContains(changedSettings, "alcoholAddictionMinAmountStage1") || 
			ArrayContains(changedSettings, "alcoholAddictionMinAmountStage2") || 
			ArrayContains(changedSettings, "alcoholAddictionMinAmountStage3") || 
			ArrayContains(changedSettings, "alcoholAddictionMinAmountStage4") {
			
				this.alcoholAddictionStageAdvanceAmounts = [
					this.Settings.alcoholAddictionMinAmountStage1,
					this.Settings.alcoholAddictionMinAmountStage2,
					this.Settings.alcoholAddictionMinAmountStage3,
					this.Settings.alcoholAddictionMinAmountStage4,
					-1.0
				];

				if IsSystemEnabledAndRunning(this) {
					this.TryToAdvanceAddiction(0.0);
				}
		}

		if ArrayContains(changedSettings, "alcoholAddictionBackoffDurationStage1") || 
			ArrayContains(changedSettings, "alcoholAddictionBackoffDurationStage2") || 
			ArrayContains(changedSettings, "alcoholAddictionBackoffDurationStage3") || 
			ArrayContains(changedSettings, "alcoholAddictionBackoffDurationStage4") {

				this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage = [
					0.0,
					this.Settings.alcoholAddictionBackoffDurationStage1,
					this.Settings.alcoholAddictionBackoffDurationStage2,
					this.Settings.alcoholAddictionBackoffDurationStage3,
					this.Settings.alcoholAddictionBackoffDurationStage4
				];

				if IsSystemEnabledAndRunning(this) {
					if this.remainingBackoffDurationInGameTimeSeconds > this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] {
						this.remainingBackoffDurationInGameTimeSeconds = (this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage[this.GetAddictionStage()] * this.Settings.timescale) * 60.0;
					}
				}
		}
	}

	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		super.InitSpecific(attachedPlayer);
		this.UpdateAlcoholWithdrawalEffectDisplayData();
	}

	//
	// Required Overrides
	//
	private final func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
		//DFProfile();
		return addictionData.alcohol;
	}

    public final func GetDefaultEffectDuration() -> Float {
		//DFProfile();
        return this.alcoholDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
		//DFProfile();
        // Not Used
		return 0.0;
    }

	private final func GetAddictionMaxStage() -> Int32 {
		//DFProfile();
        return this.alcoholAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
		//DFProfile();
        return this.Settings.alcoholAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
		//DFProfile();
        return this.Settings.alcoholAddictionAmountOnUsePerStack;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
		//DFProfile();
        return this.alcoholAddictionStageAdvanceAmounts;
    }

	public final func GetAddictionNerveLimits() -> array<Float> {
		//DFProfile();
        return this.alcoholAddictionNerveLimits;
    }

	public func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
		//DFProfile();
        return this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	public final func GetAddictionAmountLossPerDay() -> Float {
		//DFProfile();
        return this.Settings.alcoholAddictionLossPerDay;
    }

	public final func GetAddictionMinStacksPerStage() -> array<Uint32> {
		//DFProfile();
        return this.alcoholAddictionMinStacksPerStage;
    }

	public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
		//DFProfile();
        return this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds;
    }

    private final func DoPostAddictionCureActions() -> Void {
		//DFProfile();
        this.UpdateAlcoholWithdrawalEffectDisplayData();
    }

	private final func DoPostAddictionAdvanceActions() -> Void {
		//DFProfile();
        this.UpdateAlcoholWithdrawalEffectDisplayData();
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
        return n"AddictionWithdrawalAlcohol";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
		//DFProfile();
        return t"DarkFutureStatusEffect.AlcoholWithdrawal_";
    }

	public final func GetAddictionPrimaryStatusEffectTag() -> CName {
		//DFProfile();
        return n"DarkFutureAddictionPrimaryEffectAlcohol";
    }

	public final func OnAddictionPrimaryEffectApplied(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		//DFProfile();
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectAlcohol") {
			// Apply a base amount of Nerve restoration. Used by [Drink] dialogue choices.
			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now
			// (ignoring the Scene Tier for UI display purposes) instead of a queued change.
			this.NerveSystem.ApplyBaseAlcoholNerveValueChange();
			
			let alcoholEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"BaseStatusEffect.Drunk");
			if IsDefined(alcoholEffect) {
				let alcoholStackCount: Uint32 = alcoholEffect.GetStackCount();

				// Pain Tolerant Status
				if IsSystemEnabledAndRunning(this.NerveSystem) {
					if this.CyberwareService.GetAlcoholPainTolerantRequiredStacksOverride() > 0u {
						if alcoholStackCount >= this.CyberwareService.GetAlcoholPainTolerantRequiredStacksOverride() {
							StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.PainTolerant");
						}
					} else {
						if alcoholStackCount >= this.painTolerantMinStackCount {
							StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.PainTolerant");
						}
					}
				}

				// Addiction-Specific - Only continue if system running.
				if DFRunGuard(this) { return; }

				let addictionMinStacksPerStage: array<Uint32> = this.GetAddictionMinStacksPerStage();
				let addictionMinStackCount: Uint32 = addictionMinStacksPerStage[this.GetAddictionStage()];

				DFLog(this, "Alcohol: Current Stack Count " + ToString(alcoholStackCount) + ", Min Stack Count " + ToString(addictionMinStackCount));
				if alcoholStackCount >= addictionMinStackCount {
					if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"AddictionWithdrawalAlcohol") {
						StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"AddictionWithdrawalAlcohol");
					}
					this.SetWithdrawalLevel(0);
					this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);
					this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
					this.NerveSystem.UpdateNeedHUDUI();
				}

				// Try to advance the player's addiction.
				this.TryToAdvanceAddiction(this.GetAddictionAmountOnUse());
			}
		}
    }

	public final func OnAddictionPrimaryEffectRemoved(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		//DFProfile();
		// Addiction-Specific - Only continue if system running.
		if DFRunGuard(this) { return; }

		if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectAlcohol") {
			DFLog(this, "ProcessAlcoholPrimaryEffectRemoved");
			// Does the player have the Alcohol Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectAlcohol") {
				if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			}
		}
	}

	public final func GetWithdrawalAnimationLowFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationAlcoholLow";
	}

    public final func GetWithdrawalAnimationHighFirstTimeMessageKey() -> CName {
		//DFProfile();
		return n"DarkFutureWithdrawalNotificationAlcoholHigh";
	}

	private final func GetAddictionNotificationMessageKeyStage1() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationAlcohol01";
	}

    private final func GetAddictionNotificationMessageKeyStage2() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationAlcohol02";
	}

    private final func GetAddictionNotificationMessageKeyStage3() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationAlcohol03";
	}

    private final func GetAddictionNotificationMessageKeyStage4() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationAlcohol04";
	}

    private final func GetAddictionNotificationMessageKeyCured() -> CName {
		//DFProfile();
		return n"DarkFutureAddictionNotificationAlcoholCured";
	}

	private final func GetAddictionNotificationMessageContext() -> DFMessageContext {
		//DFProfile();
		return DFMessageContext.AlcoholAddiction;
	}

	private final func GetAddictionTherapyResponseIndexFact() -> CName {
		//DFProfile();
		return n"df_fact_therapy_alcohol_response";
	}

	private final func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
		return n"df_fact_action_set_therapy_addiction_alcohol_state_index";
    }

    //
    //  System-Specific Methods
    //
	public final func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
		//DFProfile();
		// Not RunGuard protected; this should occur regardless of run status.
		let itemTags: array<CName> = itemRecord.Tags();
		if ArrayContains(itemTags, n"DarkFutureConsumableAddictiveAlcoholStrong") {
			let i: Int32 = 0;
			while i < 2 {
				StatusEffectHelper.ApplyStatusEffect(this.player, t"BaseStatusEffect.Drunk");
				i += 1;
			}
		}
	}

    private final func UpdateAlcoholWithdrawalEffectDisplayData() -> Void {
		//DFProfile();
		let addictionStage: Int32 = this.GetAddictionStage();

		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[5]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[1]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[1]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[2]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[2]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[3]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[3]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNerveLimits[4]), Cast<Int32>(this.alcoholAddictionMinStacksPerStage[addictionStage]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData");
	}
}

//
//	Base Game Methods
//

//	PlayerPuppet - Scale the tiered Drunk effect up to 4 stacks.
//
@replaceMethod(PlayerPuppet)
private final func ProcessTieredDrunkEffect(evt: ref<StatusEffectEvent>) -> Void {
	//DFProfile();
	let stackCount: Int32;
    let drunkID: TweakDBID = t"BaseStatusEffect.Drunk";
    if evt.staticData.GetID() == drunkID {
		stackCount = Cast<Int32>(StatusEffectHelper.GetStatusEffectByID(this, drunkID).GetStackCount());
		GameObjectEffectHelper.BreakEffectLoopEvent(this, n"status_drunk_level_1");
		GameObjectEffectHelper.BreakEffectLoopEvent(this, n"status_drunk_level_2");
		GameObjectEffectHelper.BreakEffectLoopEvent(this, n"status_drunk_level_3");
		GameObjectEffectHelper.BreakEffectLoopEvent(this, n"status_drugged_low");
		GameObject.SetAudioParameter(this, n"vfx_fullscreen_drunk_level", 0.00);

		switch stackCount {
			case 1:
				GameObjectEffectHelper.StartEffectEvent(this, n"status_drunk_level_1");
				GameObject.SetAudioParameter(this, n"vfx_fullscreen_drunk_level", 1.00);
				break;
			case 2:
				GameObjectEffectHelper.StartEffectEvent(this, n"status_drugged_low");
				GameObject.SetAudioParameter(this, n"vfx_fullscreen_drunk_level", 2.00);
				break;
			case 3:
				GameObjectEffectHelper.StartEffectEvent(this, n"status_drunk_level_2");
				GameObject.SetAudioParameter(this, n"vfx_fullscreen_drunk_level", 2.00);
				break;
			case 5:
			case 4:
				GameObjectEffectHelper.StartEffectEvent(this, n"status_drunk_level_3");
				GameObject.SetAudioParameter(this, n"vfx_fullscreen_drunk_level", 3.00);
		};
    };
}
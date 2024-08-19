// -----------------------------------------------------------------------------
// DFAlcoholAddictionSystem
// -----------------------------------------------------------------------------
//
// - Alcohol Addiction gameplay system.
//

module DarkFuture.Addictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.HoursToGameTimeSeconds
import DarkFuture.Main.{
	DFAddictionDatum,
	DFAddictionUpdateDatum
}
import DarkFuture.Services.{
	DFGameStateService,
	DFNotificationService,
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
		return DFAlcoholAddictionSystem.Get();
	}
}

public class DFAlcoholAddictionSystem extends DFAddictionSystemBase {
    private let alcoholDefaultEffectDuration: Float = 30.0;
	private let alcoholEffectDuration: Float = 30.0;

	private let alcoholAddictionMaxStage: Int32 = 4;
	private let alcoholAddictionStageAdvanceAmounts: array<Float>;
	private let alcoholAddictionNerveTargets: array<Float>;
	private let alcoholAddictionBackoffDurationsInRealTimeMinutesByStage: array<Float>;
	private let alcoholAddictionMinStacksPerStage: array<Uint32>;
	private let alcoholAddictionMildWithdrawalDurationInGameTimeSeconds: Float;
	private let alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds: Float;

    //
    //  System Methods
    //
    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFAlcoholAddictionSystem> {
		let instance: ref<DFAlcoholAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Addictions.DFAlcoholAddictionSystem") as DFAlcoholAddictionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFAlcoholAddictionSystem> {
		return DFAlcoholAddictionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
	private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private func GetSystemToggleSettingValue() -> Bool {
		return this.Settings.alcoholAddictionEnabled;
	}

	private func GetSystemToggleSettingString() -> String {
		return "alcoholAddictionEnabled";
	}

    private final func SetupData() -> Void {
		this.alcoholAddictionMildWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.alcoholAddictionMildWithdrawalDurationInGameTimeHours);
		this.alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.alcoholAddictionSevereWithdrawalDurationInGameTimeHours);
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
		this.alcoholAddictionMinStacksPerStage = [0u, 2u, 2u, 3u, 4u];
		this.alcoholAddictionNerveTargets = [100.0, 70.0, 55.0, 40.0, 25.0, 80.0];
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		if ArrayContains(changedSettings, "alcoholAddictionMildWithdrawalDurationInGameTimeHours") {
			this.alcoholAddictionMildWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.alcoholAddictionMildWithdrawalDurationInGameTimeHours);
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				if (withdrawalLevel == 1 || withdrawalLevel == 2 || withdrawalLevel == 5) && this.remainingWithdrawalDurationInGameTimeSeconds > this.alcoholAddictionMildWithdrawalDurationInGameTimeSeconds {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.alcoholAddictionMildWithdrawalDurationInGameTimeSeconds;
				}
			}
		}

		if ArrayContains(changedSettings, "alcoholAddictionSevereWithdrawalDurationInGameTimeHours") {
			this.alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.alcoholAddictionSevereWithdrawalDurationInGameTimeHours);
			
			if IsSystemEnabledAndRunning(this) {
				let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
				if (withdrawalLevel == 3 || withdrawalLevel == 4) && this.remainingWithdrawalDurationInGameTimeSeconds > this.alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds {
					this.remainingWithdrawalDurationInGameTimeSeconds = this.alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds;
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

	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		super.InitSpecific(attachedPlayer);
		this.UpdateAlcoholWithdrawalEffectMinStackCounts();
	}

	//
	// Required Overrides
	//
	private final func OnTimeSkipFinishedActual(addictionData: DFAddictionDatum) -> Void {
		this.SetAddictionAmount(addictionData.alcohol.addictionAmount);
		this.SetAddictionStage(addictionData.alcohol.addictionStage);
		this.SetWithdrawalLevel(addictionData.alcohol.withdrawalLevel);
		this.SetRemainingBackoffDurationInGameTimeSeconds(addictionData.alcohol.remainingBackoffDuration);
		this.SetRemainingWithdrawalDurationInGameTimeSeconds(addictionData.alcohol.remainingWithdrawalDuration);
	}

    private final func GetDefaultEffectDuration() -> Float {
        return this.alcoholDefaultEffectDuration;
    }

	private final func GetEffectDuration() -> Float {
        return this.alcoholEffectDuration;
    }

	public func ResetEffectDuration() -> Void {
        this.alcoholEffectDuration = this.alcoholDefaultEffectDuration;
    }

	private final func GetAddictionMaxStage() -> Int32 {
        return this.alcoholAddictionMaxStage;
    }

	private final func GetAddictionProgressionChance() -> Float {
        return this.Settings.alcoholAddictionProgressChance;
    }

	private final func GetAddictionAmountOnUse() -> Float {
        return this.Settings.alcoholAddictionAmountOnUse;
    }

	private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        return this.alcoholAddictionStageAdvanceAmounts;
    }

	private final func GetAddictionNerveTargets() -> array<Float> {
        return this.alcoholAddictionNerveTargets;
    }

	private final func GetAddictionBackoffDurationsInRealTimeMinutesByStage() -> array<Float> {
        return this.alcoholAddictionBackoffDurationsInRealTimeMinutesByStage;
    }

	private final func GetAddictionAmountLossPerDay() -> Float {
        return this.Settings.alcoholAddictionLossPerDay;
    }

	private final func GetAddictionMinStacksPerStage() -> array<Uint32> {
        return this.alcoholAddictionMinStacksPerStage;
    }

	private final func GetAddictionMildWithdrawalDurationInGameTimeSeconds() -> Float {
        return this.alcoholAddictionMildWithdrawalDurationInGameTimeSeconds;
    }

	private final func GetAddictionSevereWithdrawalDurationInGameTimeSeconds() -> Float {
        return this.alcoholAddictionSevereWithdrawalDurationInGameTimeSeconds;
    }

    private final func DoPostAddictionCureActions() -> Void {
        this.UpdateAlcoholWithdrawalEffectMinStackCounts();
    }

	private final func DoPostAddictionAdvanceActions() -> Void {
        this.UpdateAlcoholWithdrawalEffectMinStackCounts();
    }

    private final func PlayWithdrawalAdvanceSFX() -> Void {
		if this.Settings.addictionSFXEnabled {
			let notification: DFNotification;
			notification.sfx = new DFAudioCue(n"ono_v_bump", 10);
			this.NotificationService.QueueNotification(notification);
		}
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
        return n"AddictionWithdrawalAlcohol";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
        return t"DarkFutureStatusEffect.AlcoholWithdrawal_";
    }

	private final func GetAddictionPrimaryStatusEffectTag() -> CName {
        return n"DarkFutureAddictionPrimaryEffectAlcohol";
    }

    private final func QueueAddictionNotification(stage: Int32) -> Void {
		if this.GameStateService.IsValidGameState("QueueAlcoholAddictionNotification", true) {
			let messageKey: CName;
			let messageType: SimpleMessageType;
			switch stage {
				case 4:
					messageKey = n"DarkFutureAddictionNotificationAlcohol04";
					messageType = SimpleMessageType.Negative;
					break;
				case 3:
					messageKey = n"DarkFutureAddictionNotificationAlcohol03";
					messageType = SimpleMessageType.Negative;
					break;
				case 2:
					messageKey = n"DarkFutureAddictionNotificationAlcohol02";
					messageType = SimpleMessageType.Negative;
					break;
				case 1:
					messageKey = n"DarkFutureAddictionNotificationAlcohol01";
					messageType = SimpleMessageType.Negative;
					break;
				case 0:
					messageKey = n"DarkFutureAddictionNotificationAlcoholCured";
					messageType = SimpleMessageType.Neutral;
					break;
			}

			let message: DFMessage;
			message.key = messageKey;
			message.type = messageType;
			message.context = DFMessageContext.AlcoholAddiction;

			if this.Settings.addictionMessagesEnabled || Equals(message.type, SimpleMessageType.Neutral) {
				this.NotificationService.QueueMessage(message);
			}	
		}
    }

	private final func AddictionPrimaryEffectAppliedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
        if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectAlcohol") {
			// Apply a base amount of Nerve restoration. Used by [Drink] dialogue choices.
			// We want the Nerve bar to provide immediate feedback, so directly change Nerve now
			// (ignoring the Scene Tier for UI display purposes) instead of a queued change.
			this.NerveSystem.ApplyBaseAlcoholNerveValueChange();
			
			// Clear any active withdrawal effects or backoff durations.
			// If the number of active alcohol stacks meets or exceeds the minimum number of stacks at this addiction stage...
			let alcoholEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.player, t"BaseStatusEffect.Drunk");
			if IsDefined(alcoholEffect) {
				let alcoholStackCount: Uint32 = alcoholEffect.GetStackCount();
				let addictionMinStacksPerStage: array<Uint32> = this.GetAddictionMinStacksPerStage();
				let minStackCount: Uint32 = addictionMinStacksPerStage[this.GetAddictionStage()];

				DFLog(this.debugEnabled, this, "Alcohol: Current Stack Count " + ToString(alcoholStackCount) + ", Min Stack Count " + ToString(minStackCount));
				if alcoholStackCount >= minStackCount {
					if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"AddictionWithdrawalAlcohol") {
						StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"AddictionWithdrawalAlcohol");
					}
					this.SetWithdrawalLevel(0);
					this.SetRemainingWithdrawalDurationInGameTimeSeconds(0.0);
					this.SetRemainingBackoffDurationInGameTimeSeconds(0.0);
					this.NerveSystem.UpdateNeedHUDUI();
				}
			}

			// Update the effect duration based on installed cyberware.
			this.UpdateActiveAlcoholEffectDuration(effectID);

			// Try to advance the player's addiction.
			this.TryToAdvanceAddiction(this.GetAddictionAmountOnUse());
		}
    }

	private func AddictionPrimaryEffectRemovedActual(effectID: TweakDBID, effectGameplayTags: array<CName>) -> Void {
		if ArrayContains(effectGameplayTags, n"DarkFutureAddictionPrimaryEffectAlcohol") {
			DFLog(this.debugEnabled, this, "ProcessAlcoholPrimaryEffectRemoved");
			// Does the player have the Alcohol Addiction Primary Effect? If not, the primary effect expired, and we should try to start
			// a backoff effect if the player is currently addicted.

			if !StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureAddictionPrimaryEffectAlcohol") {
				if this.GetAddictionStage() > 0 {
					this.StartBackoffDuration();
				}
			} else {
				// A stack of alcohol expired, update the duration of the remaining stack
				this.UpdateActiveAlcoholEffectDuration(effectID);
			}
		}
	}

	//
	//	Overrides
	//
	private final func ReevaluateSystem() -> Void {
		super.ReevaluateSystem();
		this.UpdateAlcoholWithdrawalEffectMinStackCounts();
	}

    //
    //  System-Specific Methods
    //
	private final func UpdateActiveAlcoholEffectDuration(effectID: TweakDBID) -> Void {
		if NotEquals(this.alcoholEffectDuration, this.alcoholDefaultEffectDuration) {
			GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.alcoholEffectDuration);
		}
	}

    private final func UpdateAlcoholWithdrawalEffectMinStackCounts() -> Void {
		let addictionStage: Int32 = this.GetAddictionStage();

		switch addictionStage {
			case 4:
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData.intValues", [80, 4, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData.intValues", [70, 4, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData.intValues", [70, 4, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData.intValues", [55, 4, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData.intValues", [55, 4, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData.intValues", [40, 4, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData.intValues", [40, 4, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData.intValues", [25, 4, 48]);
				break;
			case 3:
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData.intValues", [80, 3, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData.intValues", [70, 3, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData.intValues", [70, 3, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData.intValues", [55, 3, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData.intValues", [55, 3, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData.intValues", [40, 3, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData.intValues", [40, 3, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData.intValues", [25, 3, 48]);
				break;
			case 2:
			case 1:
			case 0:
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData.intValues", [80, 2, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData.intValues", [70, 2, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData.intValues", [70, 2, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData.intValues", [55, 2, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData.intValues", [55, 2, 24]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData.intValues", [40, 2, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData.intValues", [40, 2, 48]);
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData.intValues", [25, 2, 48]);
				break;
		}

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
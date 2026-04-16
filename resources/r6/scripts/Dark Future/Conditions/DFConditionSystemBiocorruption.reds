// -----------------------------------------------------------------------------
// DFBiocorruptionConditionSystem
// -----------------------------------------------------------------------------
//
// - Biocorruption Condition system.
// - Biocorruption progresses when progressing Addictions.
// - Cured when Addictions are cured.
//

module DarkFuture.Conditions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Main.{
    DFTimeSkipData
}
import DarkFuture.Addictions.{
    DFAlcoholAddictionSystem,
    DFNicotineAddictionSystem,
    DFNarcoticAddictionSystem,
    DFAddictionValueChangedEvent,
    DFAddictionValueChangedEventDatum,
    DFAddictionEventType
}
import DarkFuture.Utils.{
    DFRunGuard,
    HoursToGameTimeSeconds
}
import DarkFuture.Services.{
    DFGameStateService,
    DFNotificationService,
    DFTutorial,
    DFNotification,
    PlayerStateServiceOnDamageReceivedEvent,
    DFProgressionNotification,
    DFMessage,
    DFMessageContext
}
import DarkFuture.Settings.DFSettings
import DarkFuture.UI.{
    DFConditionDisplayData,
    DFConditionType,
    DFConditionArea,
    DFAreaDisplayData,
    DFConditionEffectDisplayData,
    DFHUDSegmentedIndicatorSegmentType
}
import DarkFuture.Gameplay.DFAddictionTimeSkipIterationStateDatum

public class DFBiocorruptionBonusExpirationEvent extends Event {
    public static func Create() -> ref<DFBiocorruptionBonusExpirationEvent> {
        return new DFBiocorruptionBonusExpirationEvent();
    }
}

public class BiocorruptionConditionSystemApplyDelayedNeedLossEvent extends CallbackSystemEvent {
    public static func Create() -> ref<BiocorruptionConditionSystemApplyDelayedNeedLossEvent> {
        //DFProfile();
        return new BiocorruptionConditionSystemApplyDelayedNeedLossEvent();
    }
}

@addMethod(PlayerPuppet)
private cb func OnDarkFutureBiocorruptionBonusExpiration(evt: ref<DFBiocorruptionBonusExpirationEvent>) -> Bool {
    DFBiocorruptionConditionSystem.Get().OnBonusExpiration();
}

public enum DFBiocorruptionConditionState {
    None = 0,
    Bonus = 1,
    Crash = 2
}

class DFBiocorruptionConditionSystemEventListener extends DFConditionSystemEventListener {
	private func GetSystemInstance() -> wref<DFBiocorruptionConditionSystem> {
        //DFProfile();
		return DFBiocorruptionConditionSystem.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DFAddictionValueChangedEvent>(), this, n"OnAddictionValueChangedEvent", true);
    }

    private cb func OnAddictionValueChangedEvent(event: ref<DFAddictionValueChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnAddictionValueChanged(event.GetData());
	}
}

public class DFBiocorruptionConditionSystem extends DFConditionSystemBase {
    private persistent let lastState: DFBiocorruptionConditionState = DFBiocorruptionConditionState.None;
    public persistent let lastBonusTime: GameTime;

    private const let conditionProgressPerAddictionStage: Float = 0.42;

    private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;

    private let conditionBasicNeedSoftCaps: array<Float>;

    private let bonusExpirationListener: Uint32;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFBiocorruptionConditionSystem> {
        //DFProfile();
		let instance: ref<DFBiocorruptionConditionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFBiocorruptionConditionSystem>()) as DFBiocorruptionConditionSystem;
		return instance;
	}

    public final static func Get() -> ref<DFBiocorruptionConditionSystem> {
        //DFProfile();
        return DFBiocorruptionConditionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    public final func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        return this.Settings.biocorruptionConditionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "biocorruptionConditionEnabled";
    }

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = true;
    }

    public func GetSystems() -> Void {
        //DFProfile();
        super.GetSystems();

        let gameInstance = GetGameInstance();
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
    }

    private func RegisterListeners() -> Void {
        if this.lastBonusTime.Days() > 0 {
            this.RegisterNextBonusTimeout(this.lastBonusTime);
        }
    }

    private func UnregisterListeners() -> Void {
        this.UnregisterNextBonusTimeout();
    }

	public func SetupData() -> Void {
        //DFProfile();
        this.conditionBasicNeedSoftCaps = [100.0, 85.0, 75.0, 50.0, 25.0];

        if Equals(this.player.GetResolvedGenderName(), n"Female") {
            this.conditionStatusEffects = [
                t"DarkFutureStatusEffect.Biocorruption01",
                t"DarkFutureStatusEffect.Biocorruption02",
                t"DarkFutureStatusEffect.Biocorruption03",
                t"DarkFutureStatusEffect.Biocorruption04Female"
		    ];
        } else {
            this.conditionStatusEffects = [
                t"DarkFutureStatusEffect.Biocorruption01",
                t"DarkFutureStatusEffect.Biocorruption02",
                t"DarkFutureStatusEffect.Biocorruption03",
                t"DarkFutureStatusEffect.Biocorruption04Male"
		    ];
        }
    }

    //
    //  Required Overrides
    //
    public final func GetMaxConditionLevel() -> Uint32 {
        //DFProfile();
        return 4u;
    }

    public final func GetConditionCureItemTag() -> CName {
        //DFProfile();
        return n"";
    }

    public final func GetConditionSecondaryCureItemTag() -> CName {
        //DFProfile();
        return n"";
    }

    private final func DoSecondaryConditionCure() -> Void {
        //DFProfile();
		return;
	}

    private final func GetTutorialTitleKey() -> CName {
        //DFProfile();
		//return n"DarkFutureTutorialInjuryTitle";
        return n"";
	}

	private final func GetTutorialMessageKey() -> CName {
        //DFProfile();
		//return n"DarkFutureTutorialInjury";
        return n"";
	}

    private final func GetConditionCureItemAmountRestored() -> Float {
        //DFProfile();
        return 0.0;
    }

    private final func GetCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"";
    }

    private final func GetAllCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"";
    }

    public final func GetConditionDisplayData(index: Int32) -> ref<DFConditionDisplayData> {
        //DFProfile();
        let data: ref<DFConditionDisplayData> = new DFConditionDisplayData();
        data.condition = DFConditionType.Biocorruption;
        data.index = index;

        data.localizedName = GetLocalizedTextByKey(n"DarkFutureConditionBiocorruption");
        data.level = Cast<Int32>(this.GetConditionLevel());
        data.unlockedLevel = Cast<Int32>(this.GetConditionLevel());
        data.maxLevel = Cast<Int32>(this.GetMaxConditionLevel());
        data.expPoints = Cast<Int32>(this.accumulatedPercentTowardNextLevel);
        // Condition Progress ranges from 0 to 100. -1 indicates to StatsProgressController that the Max Level has been reached.
        data.maxExpPoints = (this.GetConditionLevel() == this.GetMaxConditionLevel() && data.expPoints == 100) ? -1 : 100;

        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Biocorruption, DFConditionArea.Biocorruption_Area_01));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Biocorruption, DFConditionArea.Biocorruption_Area_02));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Biocorruption, DFConditionArea.Biocorruption_Area_03));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Biocorruption, DFConditionArea.Biocorruption_Area_04));

        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(1, n"DarkFutureBiocorruption01Name", n"DarkFutureConditionBiocorruption01Desc"));
        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(2, n"DarkFutureBiocorruption02Name", n"DarkFutureConditionBiocorruption02Desc"));
        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(3, n"DarkFutureBiocorruption03Name", n"DarkFutureConditionBiocorruption03Desc"));
        if Equals(this.player.GetResolvedGenderName(), n"Female") {
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureBiocorruption04FemaleName", n"DarkFutureConditionBiocorruption04DescFemale"));
        } else {
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureBiocorruption04MaleName", n"DarkFutureConditionBiocorruption04DescMale"));
        }
        
        return data;
    }

    private final func QueueConditionMessage(level: Uint32) -> Void {
        //DFProfile();
        let conditionLevelUpMessage: DFMessage;
        conditionLevelUpMessage.type = SimpleMessageType.Negative;
        conditionLevelUpMessage.key = StringToName("DarkFutureMagicMessageStringConditionBiocorruption" + IntToString(Cast<Int32>(level)));
        conditionLevelUpMessage.context = DFMessageContext.BiocorruptionCondition;
        conditionLevelUpMessage.passKeyAsString = true;

        let notification: DFNotification;
        notification.message = conditionLevelUpMessage;
        notification.allowPlaybackInCombat = false;

        this.NotificationService.QueueNotification(notification);
    }

    private final func GetConditionStatusEffectTag() -> CName {
        //DFProfile();
		return n"DarkFutureConditionBiocorruption";
	}

    private final func ShouldRepeatFX() -> Bool {
        //DFProfile();
		// Not used.
        return false;
	}

    public final func OnConditionRepeatFX() -> Void {
        //DFProfile();
		// Not used.
        return;
	}

    public final func GetConditionProgressionNotificationType() -> CName {
        //DFProfile();
		return n"DarkFutureBiocorruption";
	}

    public final func GetConditionProgressionNotificationTitleKey() -> CName {
        //DFProfile();
		return n"DarkFutureConditionBiocorruption";
	}

    public final func GetHUDSegmentedIndicatorSegmentType() -> DFHUDSegmentedIndicatorSegmentType {
        //DFProfile();
        return DFHUDSegmentedIndicatorSegmentType.Biocorruption;
    }

    //
    //  System-Specific Functions
    //
    public final func GetCurrentBasicNeedSoftCapFromBiocorruption() -> Float {
        //DFProfile();
        return this.conditionBasicNeedSoftCaps[Cast<Int32>(this.currentConditionLevel)];
    }

    public final func GetBasicNeedSoftCapFromBiocorruptionAtLevel(level: Uint32) -> Float {
        //DFProfile();
        return this.conditionBasicNeedSoftCaps[Cast<Int32>(level)];
    }

    // Addiction Progress Accumulator Event
    //
	public final func OnAddictionValueChanged(evt: DFAddictionValueChangedEventDatum) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnAddictionValueChanged: evt: " + ToString(evt));
        if this.GameStateService.IsValidGameState(this, true) {
            // Recalculate current Biocorruption.
            let previousPct: Float = this.accumulatedPercentTowardNextLevel;
            let previousLevel: Uint32 = this.GetConditionLevel();
            let previousTotalProgress: Float = RoundTo((previousPct / 100.0) + Cast<Float>(previousLevel), 4);
            DFLog(this, "previousTotalProgress: " + ToString(previousTotalProgress));

            let alcoholAddictionStage: Int32 = this.AlcoholAddictionSystem.GetAddictionStage();
            let nicotineAddictionStage: Int32 = this.NicotineAddictionSystem.GetAddictionStage();
            let narcoticAddictionStage: Int32 = this.NarcoticAddictionSystem.GetAddictionStage();

            let sumOfAllAddictionStages: Float = Cast<Float>(alcoholAddictionStage + nicotineAddictionStage + narcoticAddictionStage);
            DFLog(this, "sumOfAllAddictionStages: " + ToString(sumOfAllAddictionStages));
            let conditionProgressFromStages: Float = sumOfAllAddictionStages * this.conditionProgressPerAddictionStage;
            DFLog(this, "conditionProgressFromStages: " + ToString(conditionProgressFromStages));

            let alcoholAddictionAmount: Float = this.AlcoholAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
            let nicotineAddictionAmount: Float = this.NicotineAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
            let narcoticAddictionAmount: Float = this.NarcoticAddictionSystem.GetAddictionAmountAsPercentageToNextStage();

            DFLog(this, "alcoholAddictionAmount: " + ToString(alcoholAddictionAmount));
            DFLog(this, "nicotineAddictionAmount: " + ToString(nicotineAddictionAmount));
            DFLog(this, "narcoticAddictionAmount: " + ToString(narcoticAddictionAmount));

            let sumOfAllAddictionAmounts: Float = alcoholAddictionAmount + nicotineAddictionAmount + narcoticAddictionAmount;
            let conditionProgressFromAmounts: Float = sumOfAllAddictionAmounts * this.conditionProgressPerAddictionStage;
            
            let totalConditionProgress: Float = RoundTo(MinF(conditionProgressFromStages + conditionProgressFromAmounts, 5.0), 4);

            DFLog(this, "totalConditionProgress: " + ToString(totalConditionProgress));

            if totalConditionProgress < previousTotalProgress {
                let amountToRestore: Float = (previousTotalProgress - totalConditionProgress) * 100.0;
                DFLog(this, "Going down. Amount to restore: " + ToString(amountToRestore));
                this.RestoreCondition(amountToRestore, true);

            } else if totalConditionProgress > previousTotalProgress {
                // Going up.
                DFLog(this, "Going up.");
                if FloorF(totalConditionProgress) > FloorF(previousTotalProgress) {
                    DFLog(this, "...to a new level.");
                    if this.GetConditionLevel() < this.GetMaxConditionLevel() {
                        // Increment whole level.
                        this.accumulatedPercentTowardNextLevel = (totalConditionProgress % 1.0) * 100.0;
                        this.lastDisplayedProgressionNotificationValue = 0;
                        this.queueAllFutureProgressionNotifications = false;
                        this.ApplyConditionLevel();

                    } else {
                        DFLog(this, "   ...but we're at max level!");
                        this.accumulatedPercentTowardNextLevel = 100.0;
                    }
                } else {
                    this.accumulatedPercentTowardNextLevel = (totalConditionProgress % 1.0) * 100.0;
                    DFLog(this, "...incrementing. accumulatedPercentTowardNextLevel: " + ToString(this.accumulatedPercentTowardNextLevel));
                }

                // Only send the notification at 20% increments.
                let shouldQueue: Bool = false;
                if this.accumulatedPercentTowardNextLevel % 20.0 < previousPct % 20.0 && (this.accumulatedPercentTowardNextLevel > previousPct) {
                    shouldQueue = true;
                    this.queueAllFutureProgressionNotifications = true;
                } else if this.queueAllFutureProgressionNotifications {
                    shouldQueue = true;
                }
                
                if shouldQueue {
                    this.QueueConditionProgressionNotification(this.lastDisplayedProgressionNotificationValue, true);
                }
            }

            this.UpdateBiocorruptionState();
            this.RefreshConditionStatusEffects();
        }
	}

    public final func GetCalculatedBiocorruptionLevelInProvidedState(alcoholStage: Int32, nicotineStage: Int32, narcoticStage: Int32, alcoholAmountAsPercentage: Float, nicotineAmountAsPercentage: Float, narcoticAmountAsPercentage: Float) -> Uint32 {
        let sumOfAllAddictionStages: Float = Cast<Float>(alcoholStage + nicotineStage + narcoticStage);
        let conditionProgressFromStages: Float = sumOfAllAddictionStages * this.conditionProgressPerAddictionStage;
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - conditionProgressFromStages: " + ToString(conditionProgressFromStages));
        
        let sumOfAllAddictionAmounts: Float = alcoholAmountAsPercentage + nicotineAmountAsPercentage + narcoticAmountAsPercentage;
        let conditionProgressFromAmounts: Float = sumOfAllAddictionAmounts * this.conditionProgressPerAddictionStage;
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - conditionProgressFromAmounts: " + ToString(conditionProgressFromAmounts));
        
        let totalConditionProgress: Float = MinF(conditionProgressFromStages + conditionProgressFromAmounts, 5.0);
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - totalConditionProgress: " + ToString(Cast<Uint32>(FloorF(totalConditionProgress))));
        return Cast<Uint32>(FloorF(totalConditionProgress));
    }

    //
    //  Updates
    //

    // TODO: Is UpdateBiocorruptionState called when a real-time Withdrawal is applied?
    public final func UpdateBiocorruptionState() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "~~~~~~ UpdateBiocorruptionState");
        if this.GameStateService.IsValidGameState(this, true) {
            let thisState: DFBiocorruptionConditionState;

            if this.GetConditionLevel() > 0u {
                let hasAlcoholWithdrawal: Bool = this.AlcoholAddictionSystem.GetWithdrawalLevel() >= 2;
                let hasNicotineWithdrawal: Bool = this.NicotineAddictionSystem.GetWithdrawalLevel() >= 2;
                let hasNarcoticWithdrawal: Bool = this.NarcoticAddictionSystem.GetWithdrawalLevel() >= 2;

                if !hasAlcoholWithdrawal && !hasNicotineWithdrawal && !hasNarcoticWithdrawal {
                    thisState = DFBiocorruptionConditionState.Bonus;
                } else {
                    thisState = DFBiocorruptionConditionState.Crash;
                }
            } else {
                thisState = DFBiocorruptionConditionState.None;
            }

            if NotEquals(this.lastState, DFBiocorruptionConditionState.Bonus) && Equals(thisState, DFBiocorruptionConditionState.Bonus) {
                DFLog(this, "~~~~~~ Transitioned to Bonus State!");
                this.lastBonusTime = GetGameInstance().GetGameTime();
                this.RegisterNextBonusTimeout(this.lastBonusTime);
            } else if NotEquals(this.lastState, DFBiocorruptionConditionState.Crash) && Equals(thisState, DFBiocorruptionConditionState.Crash) {
                DFLog(this, "~~~~~~ Transitioned to Crash State!");
                this.UnregisterNextBonusTimeout();
                this.DispatchApplyDelayedNeedLossEvent();
            }

            this.lastState = thisState;
        }
    }

    public final func GetCurrentBiocorruptionState() -> DFBiocorruptionConditionState {
        return this.lastState;
    }

    public final func GetBiocorruptionStateInProvidedState(addictionAlcohol: DFAddictionTimeSkipIterationStateDatum, addictionNicotine: DFAddictionTimeSkipIterationStateDatum, addictionNarcotic: DFAddictionTimeSkipIterationStateDatum) -> DFBiocorruptionConditionState {
        let level: Uint32 = this.GetCalculatedBiocorruptionLevelInProvidedState(addictionAlcohol.addictionStage, addictionNicotine.addictionStage, addictionNarcotic.addictionStage, addictionAlcohol.addictionAmountAsPercentage, addictionNicotine.addictionAmountAsPercentage, addictionNarcotic.addictionAmountAsPercentage);
        
        if level > 0u {
            let hasAlcoholWithdrawal: Bool = addictionAlcohol.withdrawalLevel >= 2;
            let hasNicotineWithdrawal: Bool = addictionNicotine.withdrawalLevel >= 2;
            let hasNarcoticWithdrawal: Bool = addictionNarcotic.withdrawalLevel >= 2;

            if !hasAlcoholWithdrawal && !hasNicotineWithdrawal && !hasNarcoticWithdrawal {
                return DFBiocorruptionConditionState.Bonus;
            } else {
                return DFBiocorruptionConditionState.Crash;
            }
        } else {
            return DFBiocorruptionConditionState.None;
        }
    }

    private final func RegisterNextBonusTimeout(time: GameTime) -> Void {
        // Update at this time tomorrow.
        DFLog(this, "~~~~~~~~~~~~~~~~~~ BIOCORRUPTION REGISTERING FOR BONUS TIMEOUT ~~~~~~~~~~~~~~~~~~");
        // TODO - This is dynamic now based on Biocorruption.
        let dayTomorrow: Int32 = time.Days() + 1;
        let thisTimeTomorrow: GameTime = GameTime.MakeGameTime(dayTomorrow, time.Hours());
        this.bonusExpirationListener = GameInstance.GetTimeSystem(GetGameInstance()).RegisterListener(this.player, DFBiocorruptionBonusExpirationEvent.Create(), thisTimeTomorrow, 0);
    }

    private final func UnregisterNextBonusTimeout() -> Void {
        DFLog(this, "~~~~~~~~~~~~~~~~~~ BIOCORRUPTION UNREGISTERING FOR BONUS TIMEOUT ~~~~~~~~~~~~~~~~~~");
        GameInstance.GetTimeSystem(GetGameInstance()).UnregisterListener(this.bonusExpirationListener);
        this.bonusExpirationListener = 0u;
    }

    public final func OnBonusExpiration() -> Void {
        DFLog(this, "~~~~~~~~~~~~~~~~~~ BIOCORRUPTION BONUS EXPIRED ~~~~~~~~~~~~~~~~~~");
        this.DispatchApplyDelayedNeedLossEvent();
    }

    public final func DispatchApplyDelayedNeedLossEvent() -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(BiocorruptionConditionSystemApplyDelayedNeedLossEvent.Create());
    }
}


/*

    Biocorruption makes highs better and withdrawals worse. High highs, low lows.

    Biocorruption 1
    


    Addictive Consumable rework
        Alcohol - No longer has debuffs of its own, temporarily adds Armor, instead temporarily subtracts Energy
        Narcotics - Temporarily adds Energy and combat stats / stamina regen, temporarily subtracts...
        Nicotine - Temporarily adds... and subtracts stamina regen

        Nicotine - Restores Nerve over time (30 sec)

        Alcohol:
        Adds up to X stacks of Euphoria.
        Restores X Nerve/sec for each stack of Euphoria applied.

        Nerve: Restoration, Protection, Regeneration

        Composed:
            Status effect gained when Nourished, Hydrated, Rested, and Refreshed are applied
            1h effect
            Biocorruption must be 0
            Nerve slowly replenishes over time, -50% Humanity Loss

        Hung Over:
            Nutrition, Hydration, and Energy limited to 75

        Cigarettes: Restoration
            +10 Nerve, +1 additional Nerve for each stack of Alcohol applied
            Sprinting and Jumping consume Stamina
        
        Alcohol: Regeneration
            Nerve
            Armor
            If Energy falls to 0, suffer Blackout.
            After Blackout, if Alcohol was applied 6 or more times, applies the Hung Over status.
            
            Synergy with Narcotics, Cigarettes (Energy, Efficacy)

        Narcotics: Protection
            Nerve in / outside of combat
            Stamina drain due to Smoking and low Hydration is cancelled
            Energy (Synergy with Alcohol)

*/
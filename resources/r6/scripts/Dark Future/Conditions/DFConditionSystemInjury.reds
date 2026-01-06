// -----------------------------------------------------------------------------
// DFInjuryConditionSystem
// -----------------------------------------------------------------------------
//
// - Injury Condition system.
// - Injury occurs after taking enough cumulative damage.
// - Cured by Trauma Kit (was Health Booster).
//

module DarkFuture.Conditions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.DFRunGuard
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
    DFConditionEffectDisplayData
}


class DFInjuryConditionSystemEventListener extends DFConditionSystemEventListener {
	private func GetSystemInstance() -> wref<DFInjuryConditionSystem> {
        //DFProfile();
		return DFInjuryConditionSystem.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.PlayerStateServiceOnDamageReceivedEvent", this, n"OnPlayerStateServiceDamageReceivedEvent", true);
    }

    private cb func OnPlayerStateServiceDamageReceivedEvent(event: ref<PlayerStateServiceOnDamageReceivedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnDamageReceivedEvent(event.GetData());
    }
}

public class DFInjuryConditionSystem extends DFConditionSystemBase {
    private let StatsSystem: ref<StatsSystem>;

    public const let armorInjuryMult: Float = 0.06;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFInjuryConditionSystem> {
        //DFProfile();
		let instance: ref<DFInjuryConditionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFInjuryConditionSystem>()) as DFInjuryConditionSystem;
		return instance;
	}

    public final static func Get() -> ref<DFInjuryConditionSystem> {
        //DFProfile();
        return DFInjuryConditionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    public final func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        return this.Settings.injuryConditionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "injuryConditionEnabled";
    }

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func GetSystems() -> Void {
        //DFProfile();
        super.GetSystems();
        
		this.StatsSystem = GameInstance.GetStatsSystem(GetGameInstance());
    }

	public func SetupData() -> Void {
        //DFProfile();
		this.conditionStatusEffects = [
			t"DarkFutureStatusEffect.Injury01",
			t"DarkFutureStatusEffect.Injury02",
			t"DarkFutureStatusEffect.Injury03",
			t"DarkFutureStatusEffect.Injury04"
		];
    }

    //
    //  Required Overrides
    //
	public final func OnDamageReceivedEvent(evt: ref<gameDamageReceivedEvent>) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        if this.GameStateService.IsValidGameState(this) {
            // Get the percentage of Health lost
            let healthLost: Float = evt.totalDamageReceived;
            let totalHealth: Float = GameInstance.GetStatPoolsSystem(GetGameInstance()).GetStatPoolMaxPointValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatPoolType.Health);
            let healthLostPct: Float = healthLost / totalHealth;

            this.AccumulateHealthLoss(healthLostPct);
        }
	}

    public final func GetMaxConditionLevel() -> Uint32 {
        //DFProfile();
        return 4u;
    }

    public final func GetConditionCureItemTag() -> CName {
        //DFProfile();
        return n"DarkFutureInjuryCure";
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
		return n"DarkFutureTutorialInjuryTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
        //DFProfile();
		return n"DarkFutureTutorialInjury";
	}

    private final func GetConditionCureItemAmountRestored() -> Float {
        //DFProfile();
        return 100.0;
    }

    private final func GetCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureInjuryCuredNotification";
    }

    private final func GetAllCuredNotificationMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureInjuryAllCuredNotification";
    }

    public final func GetConditionDisplayData(index: Int32) -> ref<DFConditionDisplayData> {
        //DFProfile();
        let data: ref<DFConditionDisplayData> = new DFConditionDisplayData();
        data.condition = DFConditionType.Injury;
        data.index = index;

        data.localizedName = GetLocalizedTextByKey(n"DarkFutureConditionInjury");
        data.level = Cast<Int32>(this.GetConditionLevel());
        data.unlockedLevel = Cast<Int32>(this.GetConditionLevel());
        data.maxLevel = Cast<Int32>(this.GetMaxConditionLevel());
        data.expPoints = Cast<Int32>(this.accumulatedPercentTowardNextLevel);
        // Condition Progress ranges from 0 to 100. -1 indicates to StatsProgressController that the Max Level has been reached.
        data.maxExpPoints = (this.GetConditionLevel() == this.GetMaxConditionLevel() && data.expPoints == 100) ? -1 : 100;

        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Injury, DFConditionArea.Injury_Area_01));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Injury, DFConditionArea.Injury_Area_02));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Injury, DFConditionArea.Injury_Area_03));
        ArrayPush(data.areas, this.CreateAreaDisplayData(DFConditionType.Injury, DFConditionArea.Injury_Area_04));

        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(1, n"DarkFutureInjury01Name", n"DarkFutureConditionInjury01Desc"));
        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(2, n"DarkFutureInjury02Name", n"DarkFutureConditionInjury02Desc"));
        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(3, n"DarkFutureInjury03Name", n"DarkFutureConditionInjury03Desc"));
        ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureInjury04Name", n"DarkFutureConditionInjury04Desc"));

        return data;
    }

    private final func QueueConditionMessage(level: Uint32) -> Void {
        //DFProfile();
        let conditionLevelUpMessage: DFMessage;
        conditionLevelUpMessage.type = SimpleMessageType.Negative;
        conditionLevelUpMessage.key = StringToName("DarkFutureMagicMessageStringConditionInjury" + IntToString(Cast<Int32>(level)));
        conditionLevelUpMessage.context = DFMessageContext.InjuryCondition;
        conditionLevelUpMessage.passKeyAsString = true;

        let notification: DFNotification;
        notification.message = conditionLevelUpMessage;
        notification.allowPlaybackInCombat = false;

        this.NotificationService.QueueNotification(notification);
    }

    private final func GetConditionStatusEffectTag() -> CName {
        //DFProfile();
		return n"DarkFutureConditionInjury";
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
		return n"DarkFutureInjury";
	}

    public final func GetConditionProgressionNotificationTitleKey() -> CName {
        //DFProfile();
		return n"DarkFutureConditionInjury";
	}

    //
    //  System-Specific Functions
    //
    public final func GetCurrentPlayerArmorExact() -> Float {
        return this.StatsSystem.GetStatValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatType.Armor);
    }

    public final func GetArmorInjuryMult() -> Float {
        return this.GetCurrentPlayerArmorExact() * this.armorInjuryMult;
    }

    public final func AccumulateHealthLoss(change: Float) -> Void {
        //DFProfile();
        let percent: Float = change * 100.0;
        if this.GetConditionLevel() <= this.GetMaxConditionLevel() && percent > 0.0 {
            let armorMult: Float = ClampF(1.0 - (this.GetArmorInjuryMult() / 100.0), 0.0, 1.0);
            let lossPct: Float = (this.Settings.injuryHealthLossAccumulationRateRev3 / 100.0) * armorMult;
            let previousPct: Float = this.accumulatedPercentTowardNextLevel;
            this.accumulatedPercentTowardNextLevel += (percent * lossPct);
            DFLog(this, "&&&&&&&&&& AccumulateHealthLoss: " + ToString(this.accumulatedPercentTowardNextLevel));
            DFLog(this, "&&&&&&&&&& armorMult: " + ToString(armorMult) + ", lossPct: " + ToString(lossPct) + ", accumulatedPercentTowardNextLevel: " + ToString(this.accumulatedPercentTowardNextLevel));

            if this.accumulatedPercentTowardNextLevel >= 100.0 {
                if this.GetConditionLevel() < this.GetMaxConditionLevel() {
                    this.accumulatedPercentTowardNextLevel -= 100.0;
                    this.lastDisplayedProgressionNotificationValue = 0;
                    this.queueAllFutureProgressionNotifications = false;
                    this.ApplyConditionLevel();
                } else {
                    this.accumulatedPercentTowardNextLevel = 100.0;
                }
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
    }
}
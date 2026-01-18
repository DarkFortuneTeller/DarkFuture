/*
// -----------------------------------------------------------------------------
// DFBiocorruptionConditionSystem
// -----------------------------------------------------------------------------
//
// - Biocorruption Condition system.
// - Biocorruption progresses when Basic Needs are not met, when consuming low-quality
//   food and drinks, and consuming alcohol, nicotine, or narcotics.
// - Cured over time, more rapidly through the use of certain cyberware.
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


class DFBiocorruptionConditionSystemEventListener extends DFConditionSystemEventListener {
	private func GetSystemInstance() -> wref<DFBiocorruptionConditionSystem> {
        //DFProfile();
		return DFBiocorruptionConditionSystem.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();
    }
}

public class DFBiocorruptionConditionSystem extends DFConditionSystemBase {
    private let StatsSystem: ref<StatsSystem>;

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
        // TODO
        return true;
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
        
		this.StatsSystem = GameInstance.GetStatsSystem(GetGameInstance());
    }

	public func SetupData() -> Void {
        //DFProfile();
		this.conditionStatusEffects = [
			t"DarkFutureStatusEffect.Biocorruption01",
			t"DarkFutureStatusEffect.Biocorruption02",
			t"DarkFutureStatusEffect.Biocorruption03",
			t"DarkFutureStatusEffect.Biocorruption04"
		];
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
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureBiocorruption04FemaleName", n"DarkFutureConditionBiocorruption04Desc"));
        } else {
            ArrayPush(data.conditionEffectsData, this.CreateConditionEffectDisplayData(4, n"DarkFutureBiocorruption04MaleName", n"DarkFutureConditionBiocorruption04Desc"));
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

    //
    //  System-Specific Functions
    //
    
}
*/
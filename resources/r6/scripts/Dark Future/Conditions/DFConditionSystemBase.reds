// -----------------------------------------------------------------------------
// DFConditionSystemBase
// -----------------------------------------------------------------------------
//
// - Base class for creating long-term condition gameplay systems.
// - Conditions are more difficult to restore than Basic Needs.
//
// - Used by:
//   - DFInjuryConditionSystem
//   - DFHumanityLossConditionSystem
//

module DarkFuture.Conditions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Main.{
    DFMainSystem,
    DFTimeSkipData,
    MainSystemItemConsumedEvent
}
import DarkFuture.Settings.DFSettings
import DarkFuture.Utils.DFRunGuard
import DarkFuture.Gameplay.{
    DFInteractionSystem
}
import DarkFuture.Services.{
	DFGameStateService,
    DFNotificationService,
	DFGameStateServiceSceneTierChangedEvent,
	DFGameStateServiceFuryChangedEvent,
    DFGameStateServiceCyberspaceChangedEvent,
    DFTutorial,
    DFMessage,
    DFMessageContext,
    DFNotification,
    DFProgressionNotification
}
import DarkFuture.Needs.{
    DFNeedValueChangedEventDatum
}
import DarkFuture.UI.{
    DFConditionDisplayData,
    DFAreaDisplayData,
    DFConditionType,
    DFConditionArea,
    DFConditionEffectDisplayData
}

public class ConditionRepeatFXDelayCallback extends DFDelayCallback {
	public let ConditionSystemBase: ref<DFConditionSystemBase>;

	public static func Create(conditionSystemBase: ref<DFConditionSystemBase>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self = new ConditionRepeatFXDelayCallback();
		self.ConditionSystemBase = conditionSystemBase;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.ConditionSystemBase.conditionRepeatFXDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.ConditionSystemBase.OnConditionRepeatFX();
	}
}

public abstract class DFConditionSystemEventListener extends DFSystemEventListener {
	//
	// Required Overrides
	//
	private func GetSystemInstance() -> wref<DFConditionSystemBase> {
        //DFProfile();
		DFLogNoSystem(true, this, "MISSING REQUIRED METHOD OVERRIDE FOR GetSystemInstance()", DFLogLevel.Error);
		return null;
	}

	public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemItemConsumedEvent", this, n"OnMainSystemItemConsumedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceSceneTierChangedEvent", this, n"OnGameStateServiceSceneTierChangedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceFuryChangedEvent", this, n"OnGameStateServiceFuryChangedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DFGameStateServiceCyberspaceChangedEvent", this, n"OnGameStateServiceCyberspaceChangedEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI());
    }

	private cb func OnGameStateServiceSceneTierChangedEvent(event: ref<DFGameStateServiceSceneTierChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnSceneTierChanged(event.GetData());
	}

	private cb func OnGameStateServiceFuryChangedEvent(event: ref<DFGameStateServiceFuryChangedEvent>) {
        //DFProfile();
		this.GetSystemInstance().OnFuryStateChanged(event.GetData());
	}

    private cb func OnGameStateServiceCyberspaceChangedEvent(event: ref<DFGameStateServiceCyberspaceChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnCyberspaceChanged(event.GetData());
    }
}

public abstract class DFConditionSystemBase extends DFSystem {
    public persistent let accumulatedPercentTowardNextLevel: Float = 0.0;   // 0.0 - 100.0
    public persistent let currentConditionLevel: Uint32 = 0u;
    public persistent let hasShownTutorial: Bool = false;
    public persistent let lastDisplayedProgressionNotificationValue: Int32 = 0;

    public let conditionRepeatFXDelayID: DelayID;

    private let InteractionSystem: ref<DFInteractionSystem>;
	public let GameStateService: ref<DFGameStateService>;
    public let NotificationService: ref<DFNotificationService>;

    public let conditionStatusEffects: array<TweakDBID>;
    
    public let queueAllFutureProgressionNotifications: Bool = false;

    //
    //  DFSystem Required Methods
    //
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func UnregisterAllDelayCallbacks() -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.OnFuryStateChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"InFury"));
        this.OnCyberspaceChanged(StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"CyberspacePresence"));
    }

    public func GetSystems() -> Void {
        //DFProfile();
		let gameInstance = GetGameInstance();
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.currentConditionLevel = 0u;
        this.accumulatedPercentTowardNextLevel = 0.0;

        for effect in this.conditionStatusEffects {
            StatusEffectHelper.RemoveStatusEffect(this.player, effect);
        }

        this.SuspendFX();
        DFMainSystem.Get().UpdateCodexEntries();
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        this.SetupData();
        this.RefreshConditionStatusEffects();
        DFMainSystem.Get().UpdateCodexEntries();
    }

    public final func OnPlayerDeath() -> Void {
        //DFProfile();
		this.SuspendFX();
		super.OnPlayerDeath();
	}

    //
	//  Required Overrides
	//
    public func GetMaxConditionLevel() -> Uint32 {
        //DFProfile();
        this.LogMissingOverrideError("GetMaxConditionLevel");
        return 0u;
    }

    public func GetConditionCureItemTag() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetConditionCureItemTag");
        return n"";
    }

    public func GetConditionSecondaryCureItemTag() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetConditionSecondaryCureItemTag");
        return n"";
    }

    private func GetTutorialTitleKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetTutorialTitleKey");
		return n"";
	}

	private func GetTutorialMessageKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetTutorialMessageKey");
		return n"";
	}

    private func GetConditionCureItemAmountRestored() -> Float {
        //DFProfile();
        this.LogMissingOverrideError("GetConditionCureItemAmountRestored");
        return 0.0;
    }

    private func GetConditionDisplayData(index: Int32) -> ref<DFConditionDisplayData> {
        //DFProfile();
        this.LogMissingOverrideError("GetConditionDisplayData");
        return new DFConditionDisplayData();
    }

    private func QueueConditionMessage(level: Uint32) -> Void {
        //DFProfile();
		this.LogMissingOverrideError("QueueConditionMessage");
	}

    private func GetConditionStatusEffectTag() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetConditionStatusEffectTag");
		return n"";
	}

    private func DoSecondaryConditionCure() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("DoSecondaryConditionCure");
	}

    private func GetCuredNotificationMessageKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetCuredNotificationMessageKey");
        return n"";
    }

    private func GetAllCuredNotificationMessageKey() -> CName {
        //DFProfile();
        this.LogMissingOverrideError("GetAllCuredNotificationMessageKey");
        return n"";
    }

    private func ShouldRepeatFX() -> Bool {
        //DFProfile();
		this.LogMissingOverrideError("ShouldRepeatFX");
        return false;
	}

    public func OnConditionRepeatFX() -> Void {
        //DFProfile();
		this.LogMissingOverrideError("OnConditionRepeatFX");
        return;
	}

    public func GetConditionProgressionNotificationType() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetConditionProgressionNotificationType");
        return n"";
	}

    public func GetConditionProgressionNotificationTitleKey() -> CName {
        //DFProfile();
		this.LogMissingOverrideError("GetConditionProgressionNotificationTitleKey");
        return n"";
	}
    
	//
	//	RunGuard Protected Methods
	//
    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState(this, true) { return; }
		DFLog(this, "OnItemConsumed");

		let itemTags: array<CName> = itemRecord.Tags();
		if ArrayContains(itemTags, this.GetConditionCureItemTag()) {
            this.RestoreCondition(this.GetConditionCureItemAmountRestored());
            
        } else if ArrayContains(itemTags, this.GetConditionSecondaryCureItemTag()) {
            this.DoSecondaryConditionCure();
        }
	}

	public func OnSceneTierChanged(value: GameplayTier) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnSceneTierChanged value = " + ToString(value));

        this.RefreshConditionStatusEffects();
	}

	public func OnFuryStateChanged(value: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnFuryStateChanged value = " + ToString(value));

        this.RefreshConditionStatusEffects();
	}

    public func OnCyberspaceChanged(value: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this, true) { return; }
		DFLog(this, "OnCyberspaceChanged value = " + ToString(value));

		this.RefreshConditionStatusEffects();
	}

    //
    //  System Methods
    //
    public func DecrementPercentTowardNextLevel(amount: Float) -> Void {
        //DFProfile();
        let newPercent: Float = this.accumulatedPercentTowardNextLevel - amount;

        // Trim off bottom percent.
        if newPercent > 0.0 && newPercent < 1.0 {
            newPercent = 0.0;
        }

        if newPercent < 0.0 {
            if this.GetConditionLevel() > 0u {
                this.SetConditionLevel(this.GetConditionLevel() - 1u);
                newPercent = 100.0 + newPercent;
            } else {
                newPercent = 0.0;
            }
        }
        this.accumulatedPercentTowardNextLevel = newPercent;
    }

    public func GetConditionLevel() -> Uint32 {
        //DFProfile();
        if DFRunGuard(this) { return 0u; }

        return this.currentConditionLevel;
    }

    public func IncrementConditionLevel(value: Uint32) -> Uint32 {
        //DFProfile();
        if DFRunGuard(this) { return 0u; }

        if this.currentConditionLevel < this.GetMaxConditionLevel() {
            this.currentConditionLevel += value;
        }
        
        return this.currentConditionLevel;
    }

    public func SetConditionLevel(value: Uint32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        if value >= 0u && value <= this.GetMaxConditionLevel() {
            this.currentConditionLevel = value;
        }
    }

    public func ApplyConditionLevel() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        if !this.GameStateService.IsValidGameState(this, true) { return; }

        let currentLevel: Uint32 = this.GetConditionLevel();
        if currentLevel < this.GetMaxConditionLevel() {
            this.IncrementConditionLevel(1u);
            this.RefreshConditionStatusEffects();
            this.CheckTutorial();
            this.QueueConditionMessage(currentLevel + 1u);
        }
    }

    public func RefreshConditionStatusEffects() -> Void {
        //DFProfile();
		DFLog(this, "RefreshConditionStatusEffects -- Removing all Status Effects and re-applying");

		// Remove the status effects associated with this Condition.
		StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, this.GetConditionStatusEffectTag());

        let currentLevel: Uint32 = this.GetConditionLevel();

        if currentLevel > 0u && this.GameStateService.IsValidGameState(this) {
            DFLog(this, "        Applying status effect " + TDBID.ToStringDEBUG(this.conditionStatusEffects[Cast<Int32>(currentLevel - 1u)]));
			StatusEffectHelper.ApplyStatusEffect(this.player, this.conditionStatusEffects[Cast<Int32>(currentLevel - 1u)]);
        }
    }

    public final func RestoreCondition(amount: Float) -> Void {
        //DFProfile();
        let originalValue: Int32 = Cast<Int32>(this.accumulatedPercentTowardNextLevel);
        this.DecrementPercentTowardNextLevel(amount);
        this.RefreshConditionStatusEffects();
        this.QueueConditionProgressionNotification(originalValue, false, Cast<Int32>(-1.0 * amount));

        let notificationTitle: String;
        let conditionLevelAfter: Uint32 = this.GetConditionLevel();
        let conditionAmountAfter: Float = this.accumulatedPercentTowardNextLevel;
        let allCured: Bool = false;

        if conditionLevelAfter == 0u && conditionAmountAfter == 0.0 {
            allCured = true;
            notificationTitle = GetLocalizedTextByKey(this.GetAllCuredNotificationMessageKey());
        } else {
            notificationTitle = GetLocalizedTextByKey(this.GetCuredNotificationMessageKey());
        }

        if PlayerPuppet.GetSceneTier(this.player) > 2 || allCured || this.GameStateService.IsInAnyMenu() {
            let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
            notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
            notificationEvent.m_title = notificationTitle;
            notificationEvent.m_overrideCurrentNotification = true;
            
            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);
        }
    }

    public func SetLastDisplayedProgressionNotificationValue(value: Int32) -> Void {
        //DFProfile();
        this.lastDisplayedProgressionNotificationValue = value;
        this.queueAllFutureProgressionNotifications = false;
    }

    public func CreateAreaDisplayData(conditionType: DFConditionType, area: DFConditionArea) -> ref<DFAreaDisplayData> {
        //DFProfile();
        let displayData = new DFAreaDisplayData();
        displayData.locked = false;
        displayData.condition = conditionType;
        displayData.area = area;
        return displayData;
    }

    public func CreateConditionEffectDisplayData(level: Int32, titleKey: CName, descriptionKey: CName) -> ref<DFConditionEffectDisplayData> {
        //DFProfile();
        let displayData: ref<DFConditionEffectDisplayData> = new DFConditionEffectDisplayData();
        displayData.level = level;
        displayData.effectName = GetLocalizedTextByKey(titleKey);
        displayData.description = GetLocalizedTextByKey(descriptionKey);
        return displayData;
    }

    public final func QueueConditionProgressionNotification(lastValue: Int32, increasing: Bool, opt actualDelta: Int32) {
        let notification: DFProgressionNotification;
        notification.value = Cast<Int32>(this.accumulatedPercentTowardNextLevel);
        
        if increasing {
            let maybeDelta: Int32 = notification.value - lastValue;
            notification.barDelta = maybeDelta > 0 ? maybeDelta : (100 - lastValue) + notification.value;
        } else {
            let maybeDelta: Int32 = notification.value - lastValue;
            notification.barDelta = maybeDelta > 0 ? notification.value - 100 : maybeDelta;
        }
        notification.actualDelta = actualDelta != 0 ? actualDelta : notification.barDelta;
        notification.remainingPointsToLevelUp = 100 - notification.value;
        notification.currentLevel = Cast<Int32>(this.GetConditionLevel());
        notification.isLevelMaxed = this.GetConditionLevel() >= this.GetMaxConditionLevel();
        notification.type = IntEnum<gamedataProficiencyType>(EnumValueFromName(n"gamedataProficiencyType", this.GetConditionProgressionNotificationType()));
        notification.titleKey = this.GetConditionProgressionNotificationTitleKey();

        let pn: DFNotification;
        pn.progression = notification;
        pn.allowPlaybackInCombat = false;
        this.NotificationService.QueueNotification(pn);
    }

    public func CheckTutorial() -> Void {
        //DFProfile();
        if this.Settings.tutorialsEnabled && !this.hasShownTutorial {
            this.hasShownTutorial = true;

            let tutorial: DFTutorial;
            tutorial.title = GetLocalizedTextByKey(this.GetTutorialTitleKey());
            tutorial.message = GetLocalizedTextByKey(this.GetTutorialMessageKey());
            tutorial.iconID = t"";
            this.NotificationService.QueueTutorial(tutorial);
        }
    }

    //
    //  Repeat FX
    //
    public func SuspendFX() -> Void {
        //DFProfile();
		this.UnregisterAllConditionFXCallbacks();
	}

    private final func GetRandomRepeatCallbackOffsetTime() -> Float {
        //DFProfile();
		return RandRangeF(-20.0, 20.0);
	}

    public final func UpdateConditionRepeatFXCallback(shouldReregister: Bool) -> Void {
        //DFProfile();
		if DFRunGuard(this) { return; }
		DFLog(this, "shouldReregister = " + ToString(shouldReregister));

		this.UnregisterConditionRepeatFXCallback();

		if shouldReregister {
			this.RegisterConditionFXRepeatCallback();
		}
	}

    public final func RegisterConditionFXRepeatCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ConditionRepeatFXDelayCallback.Create(this), this.conditionRepeatFXDelayID, this.Settings.cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds + this.GetRandomRepeatCallbackOffsetTime());
	}

    public final func UnregisterAllConditionFXCallbacks() -> Void {
        //DFProfile();
		this.UnregisterConditionRepeatFXCallback();
	}

    private final func UnregisterConditionRepeatFXCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.conditionRepeatFXDelayID);
	}
}
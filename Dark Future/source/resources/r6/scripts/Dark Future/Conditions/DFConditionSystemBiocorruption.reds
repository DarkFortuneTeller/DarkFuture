// -----------------------------------------------------------------------------
// DFBiocorruptionConditionSystem
// -----------------------------------------------------------------------------
//
// - Biocorruption Condition system.
// - Biocorruption progresses when progressing Addictions.
// - Cured when Addictions are cured.
//

/*
 Crash POIs:
 MARKED UP: El Pinche Pollo                     (Trigger: $/mod/worldbuildergroup_df_poi_elpinchepollo/#worldbuildergroup_df_poi_elpinchepollo_df_poi_elpinchepollo_interior)
 MARKED UP: Heavy Hearts
 WON'T DO: Bartender in Stadium
 MARKED UP: The Moth
 MARKED UP: 7th Hell
 MARKED UP: Empathy
 MARKED UP / TR : Cambridge Winery (Hometown Deli)    (Trigger: #cct_cpz_food_01_interior_area)
 MARKED UP: Sunset Motel
 MARKED UP: El Coyote Cojo                      (Trigger: #coyote_tr_inside_area)
 MARKED UP: Dicky Twister
 MARKED UP / TR : Lizzie's                            (Trigger: #tr_lizzies_club_interior)
 MARKED UP / TR : Ho-Oh Bar                           (Trigger: #kab_07_interior_area)
 MARKED UP / TR : Afterlife
 MARKED UP / TR : Riot
 MARKED UP: Totentanz
 MARKED UP: Yagami Market
 MARKED UP: Tyger Claws Casino
 MARKED UP: Clouds
 MARKED UP: Red Dirt
 Au Cabanon - Inventory Incorrect
*/

module DarkFuture.Conditions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Main.{
    DFTimeSkipData,
    DFTimeSkipType,
    DFBiocorruptionDatum
}
import DarkFuture.Needs.{
    DFChangeNeedValueProps,
    DFNeedChangeUIFlags,
    DFEnergySystem,
    DFNerveSystem,
    DFHydrationSystem,
    DFNutritionSystem,
    DFQueuedNeedValueChange
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
    HoursToGameTimeSeconds,
    DFGeneralVoiceLine
}
import DarkFuture.Services.{
    DFGameStateService,
    DFNotificationService,
    DFTutorial,
    DFNotification,
    DFPlayerStateService,
    PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent,
    DFProgressionNotification,
    DFMessage,
    DFMessageContext,
    DFFactNameValue,
    DFAnimationService,
    DFCrashAnimMode,
    DFManagedEffectMode,
    DFManagedEffectType
}
import DarkFuture.Settings.{
    DFSettings,
    DFCrashAnimSetting
}
import DarkFuture.UI.{
    DFConditionDisplayData,
    DFConditionType,
    DFConditionArea,
    DFAreaDisplayData,
    DFConditionEffectDisplayData,
    DFHUDSegmentedIndicatorSegmentType
}
import DarkFuture.Gameplay.DFAddictionTimeSkipIterationStateDatum

public enum DFEuphoriaBlockedReason {
    None = 0,
    AddictionTreatment = 1,
    Cyberpsychosis = 2,
    Overdose = 3,
    Withdrawal = 4
}

public struct DFBiocorruptionDelayedNeedLossDatum {
    let depleteHydration: Bool;
    let depleteNutrition: Bool;
    let depleteEnergy: Bool;
    let fromQuest: Bool;
}

public enum DFQueuedCrashType {
    None = 0,
    FromTime = 1,
    FromTimeskip = 2
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    //DFProfile();
    let biocorruptionCondition: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(biocorruptionCondition) {
        if ArrayContains(effectTags, n"DarkFutureHangoverTreatment") {
            biocorruptionCondition.RefreshCrashStatusEffectAndUpdateLimit();
        }
    }
    
    return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    //DFProfile();
    let biocorruptionCondition: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();
    let effectTags: array<CName> = evt.staticData.GameplayTags();

    if IsSystemEnabledAndRunning(biocorruptionCondition) {
        if ArrayContains(effectTags, n"DarkFutureHangoverTreatment") {
            biocorruptionCondition.RefreshCrashStatusEffectAndUpdateLimit();
        }
    }
    
    return wrappedMethod(evt);
}

public class BiocorruptionDurationUpdateDelayCallback extends DFDelayCallback {
    public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
        return new BiocorruptionDurationUpdateDelayCallback();
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        DFBiocorruptionConditionSystem.Get().biocorruptionDurationUpdateDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        DFBiocorruptionConditionSystem.Get().OnBiocorruptionDurationUpdate(DFBiocorruptionConditionSystem.Get().GetBiocorruptionDurationUpdateIntervalInGameTimeSeconds());
    }
}

public class BiocorruptionApplyDelayedNeedLossEvent extends CallbackSystemEvent {
    public let data: DFBiocorruptionDelayedNeedLossDatum;

    public static func Create(data: DFBiocorruptionDelayedNeedLossDatum) -> ref<BiocorruptionApplyDelayedNeedLossEvent> {
        //DFProfile();
        let self: ref<BiocorruptionApplyDelayedNeedLossEvent> = new BiocorruptionApplyDelayedNeedLossEvent();
        self.data = data;
        return self;
    }
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
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent>(), this, n"OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent", true);
    }

    private cb func OnAddictionValueChangedEvent(event: ref<DFAddictionValueChangedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionValueChanged(event.GetData());
    }

    private cb func OnPlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent(event: ref<PlayerStateServiceAddictionTreatmentEffectAppliedOrRemovedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnAddictionTreatmentEffectAppliedOrRemoved();
    }
}

public class DFBiocorruptionConditionSystem extends DFConditionSystemBase {
    private persistent let queuedCrashType: DFQueuedCrashType = DFQueuedCrashType.None;
    private persistent let remainingCrashStackDurationInGameTimeSeconds: Float = 0.0;
    private persistent let remainingDurationUntilRestlessInGameTimeSeconds: Float = 0.0;
    private persistent let lastKnownCrashStackCount: Uint32 = 0u;
    private persistent let hasShownCrashTutorial: Bool = false;

    public let biocorruptionDurationUpdateDelayID: DelayID;
    public let biocorruptionDurationUpdateIntervalInGameTimeSeconds: Float = 300.0;

    private const let conditionProgressPerNicotineAddictionStage: Float = 0.21;
    private const let conditionProgressPerAlcoholAddictionStage: Float = 0.42;
    private const let conditionProgressPerNarcoticAddictionStage: Float = 0.6225;
    private const let maxCrashStackCount: Uint32 = 16u;
    public const let crashStackVomitThreshold: Uint32 = 8u;

    private let QuestsSystem: ref<QuestsSystem>;
    private let EnergySystem: ref<DFEnergySystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let HydrationSystem: ref<DFHydrationSystem>;
    private let NutritionSystem: ref<DFNutritionSystem>;
    private let HumanityLossSystem: ref<DFHumanityLossConditionSystem>;
    private let PlayerStateService: ref<DFPlayerStateService>;
    private let AnimationService: ref<DFAnimationService>;
    private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;

    public let requiredBuildupForEuphoriaPerBiocorruptionLevel: array<Uint32>;
    private let euphoriaPerBiocorruptionLevel: array<Float>;
    public let crashStacksAfterEuphoriaPerBiocorruptionLevel: array<Uint32>;
    public let durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds: array<Float>;

    private let FactListenerShowBiocorruptionTutorial: Uint32;
    private let factListenerOnCrashEvent: Uint32;
    private let factListenerOnShowCrashTutorialActionFactSet: Uint32;

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
    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "addictionEnabled") {
            if !this.Settings.addictionEnabled && this.GetSystemToggleSettingValue() {
                this.Suspend();
            } else if this.Settings.addictionEnabled && this.GetSystemToggleSettingValue() {
                this.Resume();
            }
        }
        
        if ArrayContains(changedSettings, "humanityLossCyberpsychosisEnabled") || ArrayContains(changedSettings, "humanityLossConditionEnabled") {
            this.RefreshEuphoria();
        }
    }

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
        this.debugEnabled = false;
    }

    public func GetSystems() -> Void {
        //DFProfile();
        super.GetSystems();
            
        let gameInstance: GameInstance = GetGameInstance();
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
        this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
        this.HumanityLossSystem = DFHumanityLossConditionSystem.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.AnimationService = DFAnimationService.GetInstance(gameInstance);
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
        this.FactListenerShowBiocorruptionTutorial = GameInstance.GetQuestsSystem(GetGameInstance()).RegisterListener(this.GetShowBiocorruptionTutorialActionFact(), this, n"OnDinoTextShowBiocorruptionTutorialActionFactChanged");
        this.factListenerOnCrashEvent = GameInstance.GetQuestsSystem(GetGameInstance()).RegisterListener(this.GetOnCrashEventFact(), this, n"OnCrashEventFactSet");
        this.factListenerOnShowCrashTutorialActionFactSet = GameInstance.GetQuestsSystem(GetGameInstance()).RegisterListener(this.GetShowCrashTutorialActionFact(), this, n"OnDinoTextShowBiocorruptionCrashTutorialActionFactChanged");
    }
    
    private func UnregisterListeners() -> Void {
        //DFProfile();
        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetShowBiocorruptionTutorialActionFact(), this.FactListenerShowBiocorruptionTutorial);
        this.FactListenerShowBiocorruptionTutorial = 0u;
        
        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetOnCrashEventFact(), this.factListenerOnCrashEvent);
        this.factListenerOnCrashEvent = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetShowCrashTutorialActionFact(), this.factListenerOnShowCrashTutorialActionFactSet);
        this.factListenerOnShowCrashTutorialActionFactSet = 0u;
    }

    public func SetupData() -> Void {
        //DFProfile();
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

        this.euphoriaPerBiocorruptionLevel = [
            0.0,
            20.0,
            30.0,
            40.0,
            50.0
        ];

        this.crashStacksAfterEuphoriaPerBiocorruptionLevel = [
            0u,
            4u,
            6u,
            8u,
            10u
        ];

        this.requiredBuildupForEuphoriaPerBiocorruptionLevel = [
            99u,
            5u,
            7u,
            9u,
            11u
        ];

        this.durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds = [
            0.0,
            HoursToGameTimeSeconds(48),
            HoursToGameTimeSeconds(36),
            HoursToGameTimeSeconds(30),
            HoursToGameTimeSeconds(24)
        ];
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        super.InitSpecific(attachedPlayer);
        this.RegisterBiocorruptionDurationUpdateCallback();
        this.RefreshEuphoria();
        this.RefreshCrashStatusEffectAndUpdateLimit();
        this.RefreshRestlessStatusEffect();
        this.UpdateUIDescriptions();

        if !this.Settings.addictionEnabled && this.GetSystemToggleSettingValue() {
            this.Suspend();
        }
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        super.DoPostSuspendActions();
        this.RemoveEuphoriaIfApplied();
        this.remainingCrashStackDurationInGameTimeSeconds = 0.0;
        this.lastKnownCrashStackCount = 0u;
        this.RefreshCrashStatusEffectAndUpdateLimit();
        this.remainingDurationUntilRestlessInGameTimeSeconds = 0.0;
        this.RefreshRestlessStatusEffect();
        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Alcohol);
        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Narcotic);

        this.UpdateUIDescriptions();
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        super.DoPostResumeActions();
        // We need to "catch up" on Condition progress based on current Addiction amount.
        let evt: DFAddictionValueChangedEventDatum;
        this.OnAddictionValueChanged(evt);

        this.RegisterBiocorruptionDurationUpdateCallback();
        this.RefreshEuphoria();
        this.RefreshCrashStatusEffectAndUpdateLimit();
        this.RefreshRestlessStatusEffect();
        this.UpdateUIDescriptions();
    }

    public func OnTimeSkipStart() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipStart");

        this.UnregisterBiocorruptionDurationUpdateCallback();
    }

    public func OnTimeSkipCancelled() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipCancelled");

        this.RegisterBiocorruptionDurationUpdateCallback();
    }

    public func OnTimeSkipBegin() -> Void {}

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {
        //DFProfile();
        super.OnTimeSkipFinished(data);

        if DFRunGuard(this) { return; }
        DFLog(this, "OnTimeSkipFinished");

        this.RegisterBiocorruptionDurationUpdateCallback();

        /*if this.GameStateService.IsValidGameState(this, true) {
            if NotEquals(data.timeSkipType, DFTimeSkipType.Blackout) {
                this.OnBiocorruptionDurationUpdateFromTimeskip(data.targetBiocorruptionValues);
            }
        }*/
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
        return n"DarkFutureTutorialBiocorruptionTitle";
    }

    private final func GetTutorialMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureTutorialBiocorruption";
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
        if !this.Settings.conditionMessagesEnabled { return; }
        
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

    // Overrides base implementation
    public final func CheckTutorial() -> Void {
        //DFProfile();
        // Start the text message chain with Dino instead of displaying a tutorial immediately.
        if this.QuestsSystem.GetFact(n"df_fact_start_biocorruption_dino_text") == 0 {
            this.QuestsSystem.SetFact(n"df_fact_start_biocorruption_dino_text", 1);
        }
    }

    private final func CheckBiocorruptionTutorial() -> Void {
        //DFProfile();
        super.CheckTutorial();
    }

    private final func OnDinoTextShowBiocorruptionTutorialActionFactChanged(value: Int32) -> Void {
        //DFProfile();
        if value == 1 {
            this.CheckBiocorruptionTutorial();
            this.QuestsSystem.SetFact(this.GetShowBiocorruptionTutorialActionFact(), 0);
            
        }
    }

    private final func OnDinoTextShowBiocorruptionCrashTutorialActionFactChanged(value: Int32) -> Void {
        //DFProfile();
        if value == 1 {
            this.ShowBiocorruptionCrashTutorial();
            this.QuestsSystem.SetFact(this.GetShowCrashTutorialActionFact(), 0);
        }
    }

    public func ShowBiocorruptionCrashTutorial() -> Void {
        //DFProfile();
        if this.Settings.tutorialsEnabled && !this.hasShownCrashTutorial {
            this.hasShownCrashTutorial = true;

            let tutorial: DFTutorial;
            tutorial.title = GetLocalizedTextByKey(n"DarkFutureTutorialBiocorruptionCrashTitle");
            tutorial.message = GetLocalizedTextByKey(n"DarkFutureTutorialBiocorruptionCrash");
            tutorial.iconID = t"";
            this.NotificationService.QueueTutorial(tutorial);
        }
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

            let nicotineAddictionStage: Float = Cast<Float>(this.NicotineAddictionSystem.GetAddictionStage());
            let alcoholAddictionStage: Float = Cast<Float>(this.AlcoholAddictionSystem.GetAddictionStage());
            let narcoticAddictionStage: Float = Cast<Float>(this.NarcoticAddictionSystem.GetAddictionStage());

            let conditionProgressFromStages: Float = (nicotineAddictionStage * this.conditionProgressPerNicotineAddictionStage) + (alcoholAddictionStage * this.conditionProgressPerAlcoholAddictionStage) + (narcoticAddictionStage * this.conditionProgressPerNarcoticAddictionStage);
            DFLog(this, "conditionProgressFromStages: " + ToString(conditionProgressFromStages));

            let nicotineAddictionAmount: Float = this.NicotineAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
            let alcoholAddictionAmount: Float = this.AlcoholAddictionSystem.GetAddictionAmountAsPercentageToNextStage();
            let narcoticAddictionAmount: Float = this.NarcoticAddictionSystem.GetAddictionAmountAsPercentageToNextStage();

            DFLog(this, "alcoholAddictionAmount: " + ToString(alcoholAddictionAmount));
            DFLog(this, "nicotineAddictionAmount: " + ToString(nicotineAddictionAmount));
            DFLog(this, "narcoticAddictionAmount: " + ToString(narcoticAddictionAmount));

            let conditionProgressFromAmounts: Float = (nicotineAddictionAmount * this.conditionProgressPerNicotineAddictionStage) + (alcoholAddictionAmount * this.conditionProgressPerAlcoholAddictionStage) + (narcoticAddictionAmount * this.conditionProgressPerNarcoticAddictionStage);
            
            let totalConditionProgress: Float = RoundTo(MinF(conditionProgressFromStages + conditionProgressFromAmounts, 5.0), 4);

            DFLog(this, "totalConditionProgress: " + ToString(totalConditionProgress));

            if totalConditionProgress < previousTotalProgress {
                // Going down.
                let amountToRestore: Float = (previousTotalProgress - totalConditionProgress) * 100.0;
                DFLog(this, "Going down. Amount to restore: " + ToString(amountToRestore));
                this.RestoreCondition(amountToRestore, true);

                if previousLevel > 0u && this.GetConditionLevel() == 0u {
                    // We went down a level; if decreasing to 0, update Euphoria and Restless. (May apply Crash.)
                    this.RefreshEuphoria();
                    this.RefreshRestlessStatusEffect();
                }

            } else if totalConditionProgress > previousTotalProgress {
                // Going up.
                DFLog(this, "Going up.");
                if FloorF(totalConditionProgress) > FloorF(previousTotalProgress) {
                    DFLog(this, "...to a higher level.");
                    let levelsToIncrease: Int32 = FloorF(totalConditionProgress) - FloorF(previousTotalProgress);

                    let i: Int32 = 0;
                    while i < levelsToIncrease {
                        if this.GetConditionLevel() < this.GetMaxConditionLevel() {
                            // Increment whole level.
                            this.accumulatedPercentTowardNextLevel = (totalConditionProgress % 1.0) * 100.0;
                            this.lastDisplayedProgressionNotificationValue = 0;
                            this.queueAllFutureProgressionNotifications = false;
                            this.ApplyConditionLevel();

                            if this.GameStateService.IsInAnyMenu() {
                                let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
                                notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
                                notificationEvent.m_title = GetLocalizedTextByKey(n"DarkFutureConditionBiocorruptionProgressMenuNotification");
                                notificationEvent.m_overrideCurrentNotification = true;
                
                                GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);    
                            }

                            // We went up a level.
                            if previousLevel == 0u {
                                // If increasing from 0, update Euphoria based on what's currently applied and start the Restless timer.
                                this.RefreshEuphoria();
                                this.remainingDurationUntilRestlessInGameTimeSeconds = this.durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds[Cast<Int32>(this.GetConditionLevel())];
                                
                            } else {
                                // If increasing in level, but not from 0, set the remaining Restless duration to the new duration for this level, if it is lower
                                // than the current duration.
                                if this.remainingDurationUntilRestlessInGameTimeSeconds > this.durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds[Cast<Int32>(this.GetConditionLevel())] {
                                    this.remainingDurationUntilRestlessInGameTimeSeconds = this.durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds[Cast<Int32>(this.GetConditionLevel())];
                                }

                                // 
                                // (Race Condition Workaround) 
                                //
                                // If the current Euphoria amount is exactly the maximum for the previous level, that means that we likely went up in level the moment
                                // we gained Euphoria. Grant the player the highest available amount from the new, higher level.

                                if this.NerveSystem.GetOverchargeValue() == this.euphoriaPerBiocorruptionLevel[Cast<Int32>(previousLevel)] {
                                    this.NerveSystem.needValueOvercharge = this.euphoriaPerBiocorruptionLevel[Cast<Int32>(this.GetConditionLevel())];
                                    this.NerveSystem.UpdateNeedHUDUI();
                                }
                            }

                        } else {
                            DFLog(this, "   ...but we're at max level!");
                            this.accumulatedPercentTowardNextLevel = 100.0;
                        }

                        i += 1;
                    }

                    this.accumulatedPercentTowardNextLevel = (totalConditionProgress % 1.0) * 100.0;
                    DFLog(this, "...incrementing. accumulatedPercentTowardNextLevel: " + ToString(this.accumulatedPercentTowardNextLevel));
                    
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

            this.RefreshConditionStatusEffects();
        }
    }

    public final func OnAddictionTreatmentEffectAppliedOrRemoved() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        if this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() > 0.0 {
            // We applied the Addiction Treatment effect. Remove any Euphoria.
            this.RefreshEuphoria();
        } else if this.GetConditionLevel() > 0u {
            // We removed the Addiction Treatment effect and have Biocorruption. Apply Euphoria if necessary.
            this.RefreshEuphoria();
        }
    }

    public final func HandleWithdrawalLevelChange() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        this.RefreshEuphoria();
    }

    public final func GetCalculatedBiocorruptionLevelInProvidedState(alcoholStage: Int32, nicotineStage: Int32, narcoticStage: Int32, alcoholAmountAsPercentage: Float, nicotineAmountAsPercentage: Float, narcoticAmountAsPercentage: Float) -> Uint32 {
        //DFProfile();
        let conditionProgressFromStages: Float = (Cast<Float>(nicotineStage) * this.conditionProgressPerNicotineAddictionStage) + (Cast<Float>(alcoholStage) * this.conditionProgressPerAlcoholAddictionStage) + (Cast<Float>(narcoticStage) * this.conditionProgressPerNarcoticAddictionStage);
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - conditionProgressFromStages: " + ToString(conditionProgressFromStages));

        let conditionProgressFromAmounts: Float = (nicotineAmountAsPercentage * this.conditionProgressPerNicotineAddictionStage) + (alcoholAmountAsPercentage * this.conditionProgressPerAlcoholAddictionStage) + (narcoticAmountAsPercentage * this.conditionProgressPerNarcoticAddictionStage);
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - conditionProgressFromAmounts: " + ToString(conditionProgressFromAmounts));
        
        let totalConditionProgress: Float = MinF(conditionProgressFromStages + conditionProgressFromAmounts, 5.0);
        DFLog(this, "GetCalculatedBiocorruptionLevelInProvidedState - totalConditionProgress: " + ToString(Cast<Uint32>(FloorF(totalConditionProgress))));
        return Cast<Uint32>(FloorF(totalConditionProgress));
    }

    public final func DispatchApplyDelayedNeedLossEvent(data: DFBiocorruptionDelayedNeedLossDatum) -> Void {
        //DFProfile();
        GameInstance.GetCallbackSystem().DispatchEvent(BiocorruptionApplyDelayedNeedLossEvent.Create(data));
    }

    public final func GetHasEuphoria() -> Bool {
        //DFProfile();
        let overcharge: Float = this.NerveSystem.GetOverchargeValue();
        DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Overcharge Value = " + ToString(overcharge));
        return overcharge > 0.0;
    }

    public final func GetIsCrashed() -> Bool {
        //DFProfile();
        // We are Crashed when we have stacks of the Crash status and we don't have Euphoria.
        return this.lastKnownCrashStackCount > 0u && this.NerveSystem.GetOverchargeValue() == 0.0;
    }

    public final func RefreshEuphoria() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        let biocorruptionLevel: Uint32 = this.GetConditionLevel();
        let biocorruptionLevelInt: Int32 = Cast<Int32>(biocorruptionLevel);
        let totalBuildUpStackCount: Uint32 = this.PlayerStateService.GetAllManagedEffectEuphoriaActiveStacks();
        let stacksRequiredForEuphoria: Uint32 = this.requiredBuildupForEuphoriaPerBiocorruptionLevel[biocorruptionLevelInt];

        //
        // EUPHORIA INTERRUPTS
        //
        // If the Addiction Treatment effect is applied, clear any Euphoria and don't continue.
        if this.PlayerStateService.GetRemainingAddictionTreatmentDurationInGameTimeSeconds() > 0.0 {
            DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: REMOVING: Addiction Treatment applied");
            this.RemoveEuphoriaIfApplied();
            return;
        }

        // If suffering from Crash and we should not apply Euphoria to clear it,
        // clear any Euphoria and don't continue.
        if this.GetIsCrashed() && (totalBuildUpStackCount < stacksRequiredForEuphoria) {
            // Is there a contextually delayed Nerve change from Timeskip? If so, don't change anything,
            // this update will apply the precomputed Crash changes and clear Euphoria.
            for change in this.NerveSystem.GetQueuedContextuallyDelayedNeedValueChanges() {
                if change.isFromTimeskip {
                    DFLog(this, "~%~%~%~%~%~%~%~%~ A Nerve change from Timeskip is queued, exiting!");
                    return;
                }
            }
            
            DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: REMOVING: Suffering from Crash");
            this.RemoveEuphoriaIfApplied();
            return;
        }

        //
        // ALREADY EUPHORIC
        //
        // If already overcharged, don't continue.
        if this.GetHasEuphoria() {
            DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: RETURNING: Already overcharged!");
            // Make sure the player has the Euphoria status.
            if !StatusEffectSystem.ObjectHasStatusEffect(this.player, this.GetEuphoriaEffectID()) {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Adding Euphoria status.");
                StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureEuphoria");
                StatusEffectHelper.ApplyStatusEffect(this.player, this.GetEuphoriaEffectID());
            }
            return;
        } else {
            // If we have the Euphoria status, we should not; remove it.
            if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureEuphoria") {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Removing Euphoria status.");
                StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureEuphoria");
            }
        }

        //
        // Euphoria or Crash Eval Valid: Not Interrupted or Already Euphoric
        //
        if totalBuildUpStackCount >= stacksRequiredForEuphoria {
            //
            // EUPHORIA BLOCKERS
            //
            // If suffering from Cyberpsychosis, don't continue. (Cyberpsychosis is prevented by Euphoria, so
            // no need to clear Euphoria; you had to have gained Cyberpsychosis while not Euphoric.)
            if this.HumanityLossSystem.GetLastKnownCyberpsychosisStackCount() > 0u {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Cyberpsychosis, returning");
                return;
            }

            // If suffering from any Withdrawal, don't continue. (Withdrawal is delayed by Euphoria, so
            // no need to clear Euphoria; you had to have gained Withdrawal while not Euphoric.)
            if this.NicotineAddictionSystem.GetWithdrawalLevel() > 0 || 
                this.AlcoholAddictionSystem.GetWithdrawalLevel() > 0 || 
                this.NarcoticAddictionSystem.GetWithdrawalLevel() > 0 {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Withdrawal, returning");
                return;
            }

            // If suffering from Overdose, don't continue.
            if this.PlayerStateService.GetInOverdose() {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Overdose, returning");
                return;
            }

            //
            // We gained Euphoria and are not Blocked.
            //

            // If we don't already have the Euphoria status, add it.
            if !StatusEffectSystem.ObjectHasStatusEffect(this.player, this.GetEuphoriaEffectID()) {
                DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Adding Euphoria status.");
                StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureEuphoria");
                StatusEffectHelper.ApplyStatusEffect(this.player, this.GetEuphoriaEffectID());
            }

            // SFX / VFX
            let voiceLine: DFNotification;
            voiceLine.allowPlaybackInCombat = true;
            voiceLine.audioSceneFact = DFFactNameValue(n"df_fact_play_voice_line", EnumInt(DFGeneralVoiceLine.Euphoria));
            this.NotificationService.QueueNotification(voiceLine);

            // TODO: status_pain - injury?

            // Set the Euphoria overcharge value.
            let uiFlags: DFNeedChangeUIFlags;
            uiFlags.forceMomentaryUIDisplay = true;
            uiFlags.momentaryDisplayIgnoresSceneTier = true;

            let props: DFChangeNeedValueProps;
            props.uiFlags = uiFlags;

            // TODO - This should be refactored as to not be necessary.
            this.NerveSystem.ChangeNeedValue(100.0, props);
            // TODO >>>>> This is happening before Biocorruption advances.
            this.NerveSystem.needValueOvercharge = this.euphoriaPerBiocorruptionLevel[biocorruptionLevelInt];
            this.NerveSystem.UpdateNeedHUDUI();

            // Clear Crash, but don't remove the internal Crash stack count. It will be reapplied later.
            this.remainingCrashStackDurationInGameTimeSeconds = 0.0;
            this.RefreshCrashStatusEffectAndUpdateLimit();

            // Clear Restless.
            this.remainingDurationUntilRestlessInGameTimeSeconds = this.durationUntilRestlessPerBiocorruptionLevelInGameTimeSeconds[biocorruptionLevelInt];
            this.RefreshRestlessStatusEffect();

            // Set a fact to track having been Euphoric. (Changes text message options.)
            this.QuestsSystem.SetFact(n"df_fact_has_ever_been_euphoric", 1);

            // Convert all Vice status effects into the Lasting variant.
            this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Lasting, DFManagedEffectType.Alcohol);
            this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Lasting, DFManagedEffectType.Narcotic);

            if this.GameStateService.IsInAnyMenu() {
                let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
                evt.soundName = n"ui_menu_perk_buy_major_tier";
                this.player.QueueEvent(evt);
            }
        }

        DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria stack count: " + ToString(totalBuildUpStackCount));
        DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria overcharge value: " + ToString(this.NerveSystem.needValueOvercharge));
    }

    public final func RemoveEuphoriaIfApplied() -> Void {
        //DFProfile();
        // Remove any overcharge and notify the UI.
        if this.GetHasEuphoria() {
            DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Clearing Nerve overcharge.");
            let nerveToRemove: Float = this.NerveSystem.needValueOvercharge + 0.1;
            let changeProps: DFChangeNeedValueProps;
            let uiFlags: DFNeedChangeUIFlags;
            uiFlags.forceMomentaryUIDisplay = true;
            uiFlags.momentaryDisplayIgnoresSceneTier = true;
            changeProps.uiFlags = uiFlags;
            this.NerveSystem.ChangeNeedValue(-nerveToRemove, changeProps);
        }

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureEuphoria") {
            DFLog(this, "~%~%~%~%~%~%~%~%~ Euphoria: Removing Euphoria status.");
            StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureEuphoria");
        }
    }

    public final func EuphoriaBlockedReason() -> DFEuphoriaBlockedReason {
        //DFProfile();
        if StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.AddictionTreatment") {
            return DFEuphoriaBlockedReason.AddictionTreatment;
        
        } else if this.HumanityLossSystem.GetLastKnownCyberpsychosisStackCount() > 0u {
            return DFEuphoriaBlockedReason.Cyberpsychosis;
        
        } else if this.PlayerStateService.GetInOverdose() {
            return DFEuphoriaBlockedReason.Overdose;
        
        } else if this.AlcoholAddictionSystem.GetWithdrawalLevel() > 0 || this.NicotineAddictionSystem.GetWithdrawalLevel() > 0 || this.NarcoticAddictionSystem.GetWithdrawalLevel() > 0 {
            return DFEuphoriaBlockedReason.Withdrawal;
        }


        return DFEuphoriaBlockedReason.None;
    }

    private final func GetEuphoriaEffectID() -> TweakDBID {
        //DFProfile();
        if this.Settings.humanityLossConditionEnabled && this.Settings.humanityLossCyberpsychosisEnabled {
            return t"DarkFutureStatusEffect.Euphoria";

        } else if this.Settings.humanityLossConditionEnabled && !this.Settings.humanityLossCyberpsychosisEnabled {
            return t"DarkFutureStatusEffect.Euphoria_NoCyberpsychosis";

        } else if !this.Settings.humanityLossConditionEnabled && !this.Settings.humanityLossCyberpsychosisEnabled {
            return t"DarkFutureStatusEffect.Euphoria_NoHumanityLoss";
        }
    }

    private final func GetRestlessEffectID() -> TweakDBID {
        //DFProfile();
        return t"DarkFutureStatusEffect.Restless";
    }

    public final func GetRemainingCrashStackDurationInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.remainingCrashStackDurationInGameTimeSeconds;
    }

    public final func GetRemainingTimeUntilRestlessInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.remainingDurationUntilRestlessInGameTimeSeconds;
    }

    public final func GetLastKnownCrashStackCount() -> Uint32 {
        //DFProfile();
        return this.lastKnownCrashStackCount;
    }

    public final func GetMaxCrashStackCount() -> Uint32 {
        //DFProfile();
        return this.maxCrashStackCount;
    }

    public final func ApplyCrashAfterEuphoria() -> Void {
        //DFProfile();
        this.ApplyCrash(this.crashStacksAfterEuphoriaPerBiocorruptionLevel[Cast<Int32>(this.GetConditionLevel())]);
    }

    public final func ApplyCrash(stackCount: Uint32, opt fromQuest: Bool) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        // The Energy loss process will determine if a Blackout or Crash animation will play.
        // Declare the need to Crash. Remains true until condition is satisfied.
        // If fromQuest (sq031 "A Cool Metal Fire" handling), don't queue this.
        if !fromQuest {
            this.SetCrashQueued(DFQueuedCrashType.FromTime);
        }

        this.remainingCrashStackDurationInGameTimeSeconds = HoursToGameTimeSeconds(0.5);

        this.lastKnownCrashStackCount += stackCount;
        if this.lastKnownCrashStackCount > this.maxCrashStackCount {
            this.lastKnownCrashStackCount = this.maxCrashStackCount;
        }

        this.RefreshCrashStatusEffectAndUpdateLimit(true);
        
        // Clear all Euphoric status effects. Party's over.
        let energyPenalty: Float;
        energyPenalty += this.PlayerStateService.ClearManagedEffectOfTypeAndReturnEnergyToChange(DFManagedEffectType.Alcohol);
        energyPenalty += this.PlayerStateService.ClearManagedEffectOfTypeAndReturnEnergyToChange(DFManagedEffectType.Narcotic);

        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Alcohol, true);
        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Narcotic, true);

        // Lose any pending Basic Needs, plus additional amount depending on the severity of the Crash.
        // This will include any temporary Energy gained through Narcotics.
        let props: DFChangeNeedValueProps;
        props.delayPercent = 1.0;
        if NotEquals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.Off) {
            props.skipSevereNeedMessage = true;
        }
        
        this.EnergySystem.ChangeNeedValue(energyPenalty, props);
        this.HydrationSystem.ForceNeedMaxValueUpdate();
        this.NutritionSystem.ForceNeedMaxValueUpdate();
        
        let data: DFBiocorruptionDelayedNeedLossDatum;
        data.depleteEnergy = true;
        data.depleteNutrition = true;
        data.depleteHydration = true;
        data.fromQuest = fromQuest;
        this.DispatchApplyDelayedNeedLossEvent(data); // <<<< Note: This is what actually triggers a Crash animation! See: finalChangeInEuphoriaDepletion

        // If this would cause the player to experience Withdrawal symptoms, update that now.
        this.AlcoholAddictionSystem.ReevaluateSystem();
        this.NicotineAddictionSystem.ReevaluateSystem();
        this.NarcoticAddictionSystem.ReevaluateSystem();
        this.NerveSystem.ForceNeedMaxValueUpdate();

        this.PlayerStateService.UpdateManagedEffectVFX(true);

        // Update the max value of affected Basic Needs.
        //this.HydrationSystem.ForceNeedMaxValueUpdate();
        //this.NutritionSystem.ForceNeedMaxValueUpdate();
    }

    public final func ApplyCrashFromTimeskip() -> Void {
        //DFProfile();
        // This is a stripped-down version of ApplyCrash for use with TimeSkip, as the TimeSkip process
        // invokes each system to already set specific values.

        // The Energy loss process will determine if a Blackout or Crash animation will play.
        // Don't refresh Euphoria here; allow the Nerve change from Timeskip to do it.
        this.PlayerStateService.ClearManagedEffectOfTypeAndReturnEnergyToChange(DFManagedEffectType.Alcohol);
        this.PlayerStateService.ClearManagedEffectOfTypeAndReturnEnergyToChange(DFManagedEffectType.Narcotic);

        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Alcohol, true);
        this.PlayerStateService.SwitchManagedEffectModeOfType(DFManagedEffectMode.Timed, DFManagedEffectType.Narcotic, true);

        this.PlayerStateService.UpdateManagedEffectVFX(true);
    }

    public final func RefreshCrashStatusEffectAndUpdateLimit(opt noWait: Bool, opt forceDisplayBars: Bool) -> Void {
        //DFProfile();
        StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.Crash", this.maxCrashStackCount);
        if this.GetHasEuphoria() {
            this.HydrationSystem.ForceNeedMaxValueUpdate();
            this.NutritionSystem.ForceNeedMaxValueUpdate();
            return;
        }

        let i: Int32 = 0;
        let count: Int32 = Max(Cast<Int32>(this.lastKnownCrashStackCount) - this.GetCrashSuppressionStackCount(), 0);
        while i < count {
            StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Crash");
            i += 1;
        }

        if noWait {
            this.HydrationSystem.ForceNeedMaxValueUpdate(false, forceDisplayBars);
            this.NutritionSystem.ForceNeedMaxValueUpdate(false, forceDisplayBars);
        } else {
            this.HydrationSystem.ForceNeedMaxValueUpdate();
            this.NutritionSystem.ForceNeedMaxValueUpdate();
        }
    }

    public final func GetCrashSuppressionStackCount(opt itemRecordForPreview: ref<Item_Record>) -> Int32 {
        //DFProfile();
        let drugSuppressionValue: Int32 = 4;
        let foodSuppressionValue: Int32 = 2;
        let drinkSuppressionValue: Int32 = 2;

        let itemPreviewTags: array<CName>;
        if IsDefined(itemRecordForPreview) {
            itemPreviewTags = itemRecordForPreview.Tags();
        }

        let hasDrugEffect: Bool = false;
        let hasFoodEffect: Bool = false;
        let hasDrinkEffect: Bool = false;

        // Excelafin
        hasDrugEffect = StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureHangoverTreatmentDrug") || ArrayContains(itemPreviewTags, n"DarkFutureConsumableHangoverTreatmentDrug");

        // Food
        hasFoodEffect = StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureHangoverTreatmentFood") || ArrayContains(itemPreviewTags, n"DarkFutureConsumableHangoverTreatmentFood");

        // Drink
        hasDrinkEffect = StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureHangoverTreatmentDrink") || ArrayContains(itemPreviewTags, n"DarkFutureConsumableHangoverTreatmentDrink");
        
        let suppressionCount: Int32 = 0;
        if hasDrugEffect { suppressionCount += drugSuppressionValue; }
        if hasFoodEffect { suppressionCount += foodSuppressionValue; }
        if hasDrinkEffect { suppressionCount += drinkSuppressionValue; }

        return suppressionCount;
    }

    private final func RefreshRestlessStatusEffect() -> Void {
        //DFProfile();
        // TODO - Compare to addiction treatment function as sanity check
        StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureRestless");

        if this.GetConditionLevel() > 0u && this.remainingDurationUntilRestlessInGameTimeSeconds == 0.0 {
            StatusEffectHelper.ApplyStatusEffect(this.player, this.GetRestlessEffectID());
        }
    }

    public final func GetCrashQueued() -> DFQueuedCrashType {
        //DFProfile();
        return this.queuedCrashType;
    }

    public final func SetCrashQueued(type: DFQueuedCrashType) -> Void {
        //DFProfile();
        this.queuedCrashType = type;
    }

    private final func GetOnCrashEventFact() -> CName {
        //DFProfile();
        return n"df_fact_on_crash_event";
    }

    private final func GetShowBiocorruptionTutorialActionFact() -> CName {
        //DFProfile();
        return n"df_fact_action_show_biocorruption_tutorial";
    }

    private final func GetShowCrashTutorialActionFact() -> CName {
        //DFProfile();
        return n"df_fact_action_show_biocorruptioncrash_tutorial";
    }

    private final func OnCrashEventFactSet(value: Int32) -> Void {
        //DFProfile();
        if value == 1 {
            // We had a headache, or puked!
            this.SetCrashQueued(DFQueuedCrashType.None);
            
        } else if value == 2 {
            // We played a blackout animation, but it did not include vomiting. Queue a separate Crash Animation.
            this.AnimationService.TryToQueueCrashAnimation(DFCrashAnimMode.FromCrash);
        }

        this.QuestsSystem.SetFact(this.GetOnCrashEventFact(), 0);

        // Allow the Crash tutorial text.
        if this.QuestsSystem.GetFact(n"df_fact_start_biocorruptioncrash_dino_text") == 0 {
            this.QuestsSystem.SetFact(n"df_fact_start_biocorruptioncrash_dino_text", 1);
        }
    }

    //
    // Updates
    //
    private final func RegisterBiocorruptionDurationUpdateCallback() -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, BiocorruptionDurationUpdateDelayCallback.Create(), this.biocorruptionDurationUpdateDelayID, this.biocorruptionDurationUpdateIntervalInGameTimeSeconds / this.Settings.timescale);
    }

    private final func UnregisterBiocorruptionDurationUpdateCallback() -> Void {
        //DFProfile();
        UnregisterDFDelayCallback(this.DelaySystem, this.biocorruptionDurationUpdateDelayID);
    }

    public final func OnBiocorruptionDurationUpdate(gameTimeSecondsToReduce: Float) -> Void {
        //DFProfile();
        if !this.GameStateService.IsInAnyMenu() {
            if this.remainingCrashStackDurationInGameTimeSeconds > 0.0 && !this.GetHasEuphoria() {
                this.remainingCrashStackDurationInGameTimeSeconds -= gameTimeSecondsToReduce;

                if this.remainingCrashStackDurationInGameTimeSeconds <= 0.0 {
                    if this.lastKnownCrashStackCount > 0u {
                        this.lastKnownCrashStackCount -= 1u;

                        if this.lastKnownCrashStackCount > 0u {
                            this.remainingCrashStackDurationInGameTimeSeconds = HoursToGameTimeSeconds(0.5);
                        } else {
                            this.remainingCrashStackDurationInGameTimeSeconds = 0.0;
                        }
                        
                    } else {
                        this.remainingCrashStackDurationInGameTimeSeconds = 0.0;
                    }
                    this.RefreshCrashStatusEffectAndUpdateLimit();
                    this.PlayerStateService.UpdateManagedEffectVFX(true);
                }
            }
            DFLog(this, "remainingCrashStackDurationInGameTimeSeconds = " + ToString(this.remainingCrashStackDurationInGameTimeSeconds));

            if this.remainingDurationUntilRestlessInGameTimeSeconds > 0.0 {
                this.remainingDurationUntilRestlessInGameTimeSeconds -= gameTimeSecondsToReduce;

                if this.remainingDurationUntilRestlessInGameTimeSeconds <= 0.0 {
                    this.remainingDurationUntilRestlessInGameTimeSeconds = 0.0;
                    this.RefreshRestlessStatusEffect();
                }
            }
            DFLog(this, "remainingDurationUntilRestlessInGameTimeSeconds = " + ToString(this.remainingDurationUntilRestlessInGameTimeSeconds));
        }
        
        this.RegisterBiocorruptionDurationUpdateCallback();
    }

    public final func UpdateBiocorruptionDataFromTimeskipSerializedWithNerveUpdate(biocorruptionDatum: DFBiocorruptionDatum) -> Void {
        //DFProfile();
        // The Energy system's Timeskip update has the Crash Stack data necessary to know what animation to play.
        this.remainingCrashStackDurationInGameTimeSeconds = biocorruptionDatum.newCrashDuration;
        this.lastKnownCrashStackCount = biocorruptionDatum.newCrashStackCount;
        this.remainingDurationUntilRestlessInGameTimeSeconds = biocorruptionDatum.newTimeUntilRestless;

        if biocorruptionDatum.crashOccuredDuringTimeskip {
            this.ApplyCrashFromTimeskip();
        }

        this.RefreshRestlessStatusEffect();
    }

    public final func GetBiocorruptionDurationUpdateIntervalInGameTimeSeconds() -> Float {
        //DFProfile();
        return this.biocorruptionDurationUpdateIntervalInGameTimeSeconds;
    }

    private final func UpdateUIDescriptions() -> Void {
        //DFProfile();
        let emptyIntArray: array<Int32>;

        if IsSystemEnabledAndRunning(this) {
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Nourishment_UIData.localizedDescription", GetLocalizedTextByKey(n"DarkFutureConsumableUIDescriptionNourishment"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Nourishment_UIData.intValues", [2]);
            TweakDBManager.SetFlat(t"BaseStatusEffect.WellFed_inline4.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionWellFed"));
            TweakDBManager.SetFlat(t"BaseStatusEffect.WellFed_inline4.intValues", [2]);
            
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Hydrated_UIData.localizedDescription", GetLocalizedTextByKey(n"DarkFutureConsumableUIDescriptionHydrated"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Hydrated_UIData.intValues", [5, 2]);
            TweakDBManager.SetFlat(t"BaseStatusEffect.Sated_inline2.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionSated"));
            TweakDBManager.SetFlat(t"BaseStatusEffect.Sated_inline2.intValues", [5, 2]);
            
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatmentDrug_OnEquip_UIData.localizedDescription", GetLocalizedTextByKey(n"DarkFutureConsumableUIDescriptionHangoverTreatment"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatmentDrug_OnEquip_UIData.intValues", [4, 5]);
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatment_UIData.description", GetLocalizedTextByKey(n"DarkFutureConsumableHangoverTreatmentEffectDesc"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatment_UIData.intValues", [4, 5]);

            if this.Settings.humanityLossConditionEnabled {
                if this.Settings.humanityLossCyberpsychosisEnabled {
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAll"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.intValues", [5, 100, 48]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAll"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.intValues", [7, 100, 36]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAll"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.intValues", [9, 100, 30]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAll"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.intValues", [11, 100, 24]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAll"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.intValues", [11, 100, 24]);

                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.description", GetLocalizedTextByKey(n"DarkFutureEuphoriaStatusEffectDescription"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.intValues", [100]);

                } else {
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.intValues", [5, 100, 48]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.intValues", [7, 100, 36]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.intValues", [9, 100, 30]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.intValues", [11, 100, 24]);
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.intValues", [11, 100, 24]);

                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.description", GetLocalizedTextByKey(n"DarkFutureEuphoriaStatusEffectDescriptionNoCyberpsychosis"));
                    TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.intValues", [100]);

                }
            } else {
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoHL"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption01_UIData.intValues", [5, 48]);
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoHL"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption02_UIData.intValues", [7, 36]);
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoHL"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption03_UIData.intValues", [9, 30]);
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoHL"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Female_UIData.intValues", [11, 24]);
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.description", GetLocalizedTextByKey(n"DarkFutureBiocorruptionDescAllNoHL"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Biocorruption04Male_UIData.intValues", [11, 24]);
                
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.description", GetLocalizedTextByKey(n"DarkFutureEuphoriaStatusEffectDescriptionNoHumanityLoss"));
                TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Euphoria_UIData.intValues", emptyIntArray);
            }

        } else {
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Nourishment_UIData.localizedDescription", GetLocalizedTextByKey(n"DarkFutureConsumableUIDescriptionNourishmentNoBiocorruption"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Nourishment_UIData.intValues", emptyIntArray);
            TweakDBManager.SetFlat(t"BaseStatusEffect.WellFed_inline4.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionWellFedNoBiocorruption"));
            TweakDBManager.SetFlat(t"BaseStatusEffect.WellFed_inline4.intValues", emptyIntArray);
            
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Hydrated_UIData.localizedDescription", n"DarkFutureConsumableUIDescriptionHydratedNoBiocorruption");
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Hydrated_UIData.intValues", [5]);
            TweakDBManager.SetFlat(t"BaseStatusEffect.Sated_inline2.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionSatedNoBiocorruption"));
            TweakDBManager.SetFlat(t"BaseStatusEffect.Sated_inline2.intValues", [5]);

            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatmentDrug_OnEquip_UIData.localizedDescription", GetLocalizedTextByKey(n"DarkFutureConsumableUIDescriptionHangoverTreatmentNoBiocorruption"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatmentDrug_OnEquip_UIData.intValues", [5]);
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatment_UIData.description", GetLocalizedTextByKey(n"DarkFutureConsumableHangoverTreatmentEffectDescNoBiocorruption"));
            TweakDBManager.SetFlat(t"DarkFutureStatusEffect.HangoverTreatment_UIData.intValues", [5]);
        }

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Nourishment_UIData");
        TweakDBManager.UpdateRecord(t"BaseStatusEffect.WellFed_inline4");

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Hydrated_UIData");
        TweakDBManager.UpdateRecord(t"BaseStatusEffect.Sated_inline2");

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.HangoverTreatmentDrug_OnEquip_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.HangoverTreatment_UIData");

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Biocorruption01_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Biocorruption02_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Biocorruption03_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Biocorruption04Female_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Biocorruption04Male_UIData");

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Euphoria_UIData");
    }
}

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
    DFAddictionUpdateDatum
}
import DarkFuture.Services.{
    DFGameStateService,
    DFNotificationService,
    DFCyberwareService,
    DFAudioCue,
    DFNotification,
    DFMessage,
    DFMessageContext,
    DFAddictionType,
    DFManagedEffectType
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Addictions.DFAddictionSystemBase
import DarkFuture.Conditions.{
    DFBiocorruptionConditionSystem
}
import DarkFuture.Settings.DFSettings

class DFAlcoholAddictionSystemEventListener extends DFAddictionSystemEventListener {
    private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
        //DFProfile();
        return DFAlcoholAddictionSystem.Get();
    }
}

public class DFAlcoholAddictionSystem extends DFAddictionSystemBase {
    private let alcoholAddictionMaxStage: Int32 = 4;
    private let alcoholAddictionStageAdvanceAmounts: array<Float>;
    private let alcoholAddictionNeedLimits: array<Float>;
    private let alcoholAddictionBackoffDurationsInGameTimeSecondsByStage: array<Float>;
    private let alcoholAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;

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
        return this.Settings.addictionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "addictionEnabled";
    }

    public final func SetupData() -> Void {
        //DFProfile();
        this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds = [
            0.0,
            HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
        ];
        this.alcoholAddictionStageAdvanceAmounts = [
            8.0,
            16.0,
            24.0,
            32.0,
            -1.0
        ];
        this.alcoholAddictionBackoffDurationsInGameTimeSecondsByStage = [
            0.0,
            this.Settings.addictionBackoffDurationStage1 * 3600.0,
            this.Settings.addictionBackoffDurationStage2 * 3600.0,
            this.Settings.addictionBackoffDurationStage3 * 3600.0,
            this.Settings.addictionBackoffDurationStage4 * 3600.0
        ];
        this.alcoholAddictionNeedLimits = [100.0, 80.0, 65.0, 50.0, 35.0, 80.0];
        this.UpdateAlcoholWithdrawalEffectDisplayData();
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "addictionStage1WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage2WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage3WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage4WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionCessationDurationInGameTimeHours") {
            this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds = [
                0.0,
                HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
            ];
            this.UpdateAlcoholWithdrawalEffectDisplayData();

            if IsSystemEnabledAndRunning(this) {
                let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
                let addictionStage: Int32 = this.GetAddictionStage();
                if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSecondsRev2 > this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
                    this.remainingWithdrawalDurationInGameTimeSecondsRev2 = this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
                }
            }
        }

        if ArrayContains(changedSettings, "addictionBackoffDurationStage1") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage2") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage3") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage4") {

                this.alcoholAddictionBackoffDurationsInGameTimeSecondsByStage = [
                    0.0,
                    this.Settings.addictionBackoffDurationStage1 * 3600.0,
                    this.Settings.addictionBackoffDurationStage2 * 3600.0,
                    this.Settings.addictionBackoffDurationStage3 * 3600.0,
                    this.Settings.addictionBackoffDurationStage4 * 3600.0
                ];

                if IsSystemEnabledAndRunning(this) {
                    if this.remainingBackoffDurationInGameTimeSecondsRev2 > this.alcoholAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()] {
                        this.remainingBackoffDurationInGameTimeSecondsRev2 = this.alcoholAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()];
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
        return this.Settings.alcoholAddictionProgressChanceRev2;
    }

    public final func GetAddictionAmountOnUse() -> Float {
        //DFProfile();
        return 1.0;
    }

    private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        //DFProfile();
        return this.alcoholAddictionStageAdvanceAmounts;
    }

    public final func GetAddictionNeedLimits() -> array<Float> {
        //DFProfile();
        return this.alcoholAddictionNeedLimits;
    }

    public func GetAddictionBackoffDurationsInGameTimeSecondsByStage() -> array<Float> {
        //DFProfile();
        return this.alcoholAddictionBackoffDurationsInGameTimeSecondsByStage;
    }

    public final func GetAddictionAmountLossPerDay() -> Float {
        //DFProfile();
        return this.Settings.alcoholAddictionLossPerDayRev2;
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

    public final func GetAddictionManagedEffectType() -> DFManagedEffectType {
        //DFProfile();
        return DFManagedEffectType.Alcohol;
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

    private final func GetAddictionStageFact() -> CName {
        //DFProfile();
        return n"df_fact_addiction_stage_alcohol";
    }

    private final func GetAddictionType() -> DFAddictionType {
        //DFProfile();
        return DFAddictionType.Alcohol;
    }

    private final func GetAddictionAdvanceNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureAlcoholAddictionIncreaseNotification";
    }

    private final func GetAddictionWithdrawalRemovedNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureAlcoholAddictionWithdrawalRemovedNotification";
    }

    //
    //  System-Specific Methods
    //
    private final func UpdateAlcoholWithdrawalEffectDisplayData() -> Void {
        //DFProfile();
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[5]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[1]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[1]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[2]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[2]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[3]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[3]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.alcoholAddictionNeedLimits[4]), GameTimeSecondsToHours(this.alcoholAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

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
//  Base Game Methods
//

@wrapMethod(PlayerPuppet)
private final func ProcessTieredDrunkEffect(evt: ref<StatusEffectEvent>) -> Void {
    //DFProfile();
    if DFSettings.Get().mainSystemEnabled {
        return;
    } else {
        wrappedMethod(evt);
    }
}

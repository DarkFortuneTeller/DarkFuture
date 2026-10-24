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
    DFAddictionUpdateDatum
}
import DarkFuture.Services.{
    DFPlayerStateService,
    DFCyberwareService,
    DFGameStateService,
    DFNotificationService,
    DFAudioCue,
    DFNotification,
    DFMessage,
    DFMessageContext,
    DFAddictionType,
    DFManagedEffectType
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
    private let narcoticAddictionMaxStage: Int32 = 4;
    private let narcoticAddictionStageAdvanceAmounts: array<Float>;
    private let narcoticAddictionNeedLimits: array<Float>;
    private let narcoticAddictionBackoffDurationsInGameTimeSecondsByStage: array<Float>;
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
        return this.Settings.addictionEnabled;
    }

    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "addictionEnabled";
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        super.DoPostSuspendActions();
    }

    public func UnregisterAllDelayCallbacks() -> Void {}

    public final func SetupData() -> Void {
        //DFProfile();
        this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds = [
            0.0,
            HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
        ];
        this.narcoticAddictionStageAdvanceAmounts = [
            6.0,
            12.0,
            16.0,
            20.0,
            -1.0
        ];
        this.narcoticAddictionNeedLimits = [100.0, 80.0, 60.0, 40.0, 20.0, 80.0];
        this.narcoticAddictionBackoffDurationsInGameTimeSecondsByStage = [
            0.0,
            this.Settings.addictionBackoffDurationStage1 * 3600.0,
            this.Settings.addictionBackoffDurationStage2 * 3600.0,
            this.Settings.addictionBackoffDurationStage3 * 3600.0,
            this.Settings.addictionBackoffDurationStage4 * 3600.0
        ];
        this.UpdateNarcoticWithdrawalEffectDisplayData();
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "addictionStage1WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage2WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage3WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage4WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionCessationDurationInGameTimeHours") {
            this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds = [
                0.0,
                HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
            ];
            this.UpdateNarcoticWithdrawalEffectDisplayData();

            if IsSystemEnabledAndRunning(this) {
                let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
                let addictionStage: Int32 = this.GetAddictionStage();
                if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSecondsRev2 > this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
                    this.remainingWithdrawalDurationInGameTimeSecondsRev2 = this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
                }
            }
        }

        if ArrayContains(changedSettings, "addictionBackoffDurationStage1") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage2") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage3") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage4") {

                this.narcoticAddictionBackoffDurationsInGameTimeSecondsByStage = [
                    0.0,
                    this.Settings.addictionBackoffDurationStage1 * 3600.0,
                    this.Settings.addictionBackoffDurationStage2 * 3600.0,
                    this.Settings.addictionBackoffDurationStage3 * 3600.0,
                    this.Settings.addictionBackoffDurationStage4 * 3600.0
                ];

                if IsSystemEnabledAndRunning(this) {
                    if this.remainingBackoffDurationInGameTimeSecondsRev2 > this.narcoticAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()] {
                        this.remainingBackoffDurationInGameTimeSecondsRev2 = this.narcoticAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()];
                    }
                }
        }
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        super.InitSpecific(attachedPlayer);
        this.UpdateNarcoticWithdrawalEffectDisplayData();
    }

    //
    //  Required Overrides
    //
    private final func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
        //DFProfile();
        return addictionData.narcotic;
    }

    private final func GetAddictionMaxStage() -> Int32 {
        //DFProfile();
        return this.narcoticAddictionMaxStage;
    }

    private final func GetAddictionProgressionChance() -> Float {
        //DFProfile();
        return this.Settings.narcoticAddictionProgressChanceRev2;
    }

    public final func GetAddictionAmountOnUse() -> Float {
        //DFProfile();
        return 1.0;
    }

    private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        //DFProfile();
        return this.narcoticAddictionStageAdvanceAmounts;
    }

    public final func GetAddictionNeedLimits() -> array<Float> {
        //DFProfile();
        return this.narcoticAddictionNeedLimits;
    }

    public func GetAddictionBackoffDurationsInGameTimeSecondsByStage() -> array<Float> {
        //DFProfile();
        return this.narcoticAddictionBackoffDurationsInGameTimeSecondsByStage;
    }

    public final func GetAddictionAmountLossPerDay() -> Float {
        //DFProfile();
        return this.Settings.narcoticAddictionLossPerDayRev2;
    }

    public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
        //DFProfile();
        return this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds;
    }

    private final func DoPostAddictionCureActions() -> Void {
        //DFProfile();
        this.UpdateNarcoticWithdrawalEffectDisplayData();
    }

    private final func DoPostAddictionAdvanceActions() -> Void {
        //DFProfile();
        this.UpdateNarcoticWithdrawalEffectDisplayData();
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

    public final func GetAddictionManagedEffectType() -> DFManagedEffectType {
        //DFProfile();
        return DFManagedEffectType.Narcotic;
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

    private final func GetAddictionStageFact() -> CName {
        //DFProfile();
        return n"df_fact_addiction_stage_narcotic";
    }

    private final func GetAddictionType() -> DFAddictionType {
        //DFProfile();
        return DFAddictionType.Narcotic;
    }

    private final func GetAddictionAdvanceNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureNarcoticAddictionIncreaseNotification";
    }

    private final func GetAddictionWithdrawalRemovedNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureNarcoticAddictionWithdrawalRemovedNotification";
    }

    //
    //  System-Specific Methods
    //
    private final func UpdateNarcoticWithdrawalEffectDisplayData() -> Void {
        //DFProfile();
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[5]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[1]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[1]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[2]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[2]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[3]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[3]), 2]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.narcoticAddictionNeedLimits[4]), GameTimeSecondsToHours(this.narcoticAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

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

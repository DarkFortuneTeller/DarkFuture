// -----------------------------------------------------------------------------
// DFNicotineAddictionSystem
// -----------------------------------------------------------------------------
//
// - Nicotine Addiction gameplay system.
//

module DarkFuture.Addictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.{
    HoursToGameTimeSeconds,
    GameTimeSecondsToHours,
    DFRunGuard,
    RandRangeInclusive
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
import DarkFuture.Settings.DFSettings

class DFNicotineAddictionSystemEventListener extends DFAddictionSystemEventListener {
    private func GetSystemInstance() -> wref<DFAddictionSystemBase> {
        //DFProfile();
        return DFNicotineAddictionSystem.Get();
    }
}

public class DFNicotineAddictionSystem extends DFAddictionSystemBase {
    private let nicotineAddictionMaxStage: Int32 = 4;
    private let nicotineAddictionStageAdvanceAmounts: array<Float>;
    private let nicotineAddictionNeedLimits: array<Float>;
    private let nicotineAddictionBackoffDurationsInGameTimeSecondsByStage: array<Float>;
    private let nicotineAddictionWithdrawalDurationsInGameTimeSeconds: array<Float>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFNicotineAddictionSystem> {
        //DFProfile();
        let instance: ref<DFNicotineAddictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFNicotineAddictionSystem>()) as DFNicotineAddictionSystem;
        return instance;
    }

    public final static func Get() -> ref<DFNicotineAddictionSystem> {
        //DFProfile();
        return DFNicotineAddictionSystem.GetInstance(GetGameInstance());
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

    public final func SetupData() -> Void {
        //DFProfile();
        this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds = [
            0.0,
            HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
            HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
        ];
        this.nicotineAddictionStageAdvanceAmounts = [
            3.0,
            6.0,
            8.0,
            10.0,
            -1.0
        ];
        this.nicotineAddictionBackoffDurationsInGameTimeSecondsByStage = [
            0.0,
            this.Settings.addictionBackoffDurationStage1 * 3600.0,
            this.Settings.addictionBackoffDurationStage2 * 3600.0,
            this.Settings.addictionBackoffDurationStage3 * 3600.0,
            this.Settings.addictionBackoffDurationStage4 * 3600.0
        ];
        this.nicotineAddictionNeedLimits = [100.0, 85.0, 75.0, 65.0, 55.0, 85.0];
        this.UpdateNicotineWithdrawalEffectDisplayData();
    }

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "addictionStage1WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage2WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage3WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionStage4WithdrawalDurationInGameTimeHoursV2") ||
           ArrayContains(changedSettings, "addictionCessationDurationInGameTimeHours") {
            this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds = [
                0.0,
                HoursToGameTimeSeconds(this.Settings.addictionStage1WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage2WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage3WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionStage4WithdrawalDurationInGameTimeHoursV2),
                HoursToGameTimeSeconds(this.Settings.addictionCessationDurationInGameTimeHours)
            ];
            this.UpdateNicotineWithdrawalEffectDisplayData();

            if IsSystemEnabledAndRunning(this) {
                let withdrawalLevel: Int32 = this.GetWithdrawalLevel();
                let addictionStage: Int32 = this.GetAddictionStage();
                if withdrawalLevel < addictionStage && this.remainingWithdrawalDurationInGameTimeSecondsRev2 > this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel] {
                    this.remainingWithdrawalDurationInGameTimeSecondsRev2 = this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[withdrawalLevel];
                }
            }
        }

        if ArrayContains(changedSettings, "addictionBackoffDurationStage1") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage2") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage3") ||
            ArrayContains(changedSettings, "addictionBackoffDurationStage4") {

                this.nicotineAddictionBackoffDurationsInGameTimeSecondsByStage = [
                    0.0,
                    this.Settings.addictionBackoffDurationStage1 * 3600.0,
                    this.Settings.addictionBackoffDurationStage2 * 3600.0,
                    this.Settings.addictionBackoffDurationStage3 * 3600.0,
                    this.Settings.addictionBackoffDurationStage4 * 3600.0
                ];

                if IsSystemEnabledAndRunning(this) {
                    if this.remainingBackoffDurationInGameTimeSecondsRev2 > this.nicotineAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()] {
                        this.remainingBackoffDurationInGameTimeSecondsRev2 = this.nicotineAddictionBackoffDurationsInGameTimeSecondsByStage[this.GetAddictionStage()];
                    }
                }
        }
    }

    //
    //  Required Overrides
    //
    private final func GetSpecificAddictionUpdateData(addictionData: DFAddictionDatum) -> DFAddictionUpdateDatum {
        //DFProfile();
        return addictionData.nicotine;
    }

    public final func GetDefaultDebuffEffectDuration() -> Float {
        //DFProfile();
        return 300.0;
    }

    private final func GetEffectDuration() -> Float {
        //DFProfile();
        let durationOverride: Float = this.CyberwareService.GetNicotineEffectDurationOverride();
        if durationOverride > 0.0 {
            return durationOverride;
        } else {
            return this.GetDefaultDebuffEffectDuration();
        }
    }

    private final func GetAddictionMaxStage() -> Int32 {
        //DFProfile();
        return this.nicotineAddictionMaxStage;
    }

    private final func GetAddictionProgressionChance() -> Float {
        //DFProfile();
        return this.Settings.nicotineAddictionProgressChanceRev2;
    }

    public final func GetAddictionAmountOnUse() -> Float {
        //DFProfile();
        return 1.0;
    }

    private final func GetAddictionStageAdvanceAmounts() -> array<Float> {
        //DFProfile();
        return this.nicotineAddictionStageAdvanceAmounts;
    }

    public final func GetAddictionNeedLimits() -> array<Float> {
        //DFProfile();
        return this.nicotineAddictionNeedLimits;
    }

    public func GetAddictionBackoffDurationsInGameTimeSecondsByStage() -> array<Float> {
        //DFProfile();
        return this.nicotineAddictionBackoffDurationsInGameTimeSecondsByStage;
    }

    public final func GetAddictionAmountLossPerDay() -> Float {
        //DFProfile();
        return this.Settings.nicotineAddictionLossPerDayRev2;
    }

    public func GetAddictionWithdrawalDurationsInGameTimeSeconds() -> array<Float> {
        //DFProfile();
        return this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds;
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

            let random: Int32 = RandRangeInclusive(1, 100);
            if random >= 50 {
                if this.GetAddictionStage() <= 2 {
                    notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_light", 5);
                } else {
                    random = RandRangeInclusive(1, 100);
                    if random > 25 {
                        notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_hard", 5);
                    } else {
                        notification.sfx = DFAudioCue(n"g_sc_v_sickness_cough_light", 5);
                    }
                }
            } else {
                if Equals(this.player.GetResolvedGenderName(), n"Female") {
                    notification.sfx = DFAudioCue(n"ono_v_bump", 5);
                } else {
                    notification.sfx = DFAudioCue(n"ono_v_phone", 5);
                }
            }

            this.NotificationService.QueueNotification(notification);
        }
    }

    private final func GetWithdrawalStatusEffectTag() -> CName {
        //DFProfile();
        return n"AddictionWithdrawalNicotine";
    }

    private final func GetAddictionStatusEffectBaseID() -> TweakDBID {
        //DFProfile();
        return t"DarkFutureStatusEffect.NicotineWithdrawal_";
    }

    public final func GetAddictionManagedEffectType() -> DFManagedEffectType {
        //DFProfile();
        return DFManagedEffectType.Nicotine;
    }

    public final func GetWithdrawalAnimationLowFirstTimeMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureWithdrawalNotificationNicotineLow";
    }

    public final func GetWithdrawalAnimationHighFirstTimeMessageKey() -> CName {
        //DFProfile();
        return n"DarkFutureWithdrawalNotificationNicotineHigh";
    }

    private final func GetAddictionNotificationMessageKeyStage1() -> CName {
        //DFProfile();
        return n"DarkFutureAddictionNotificationNicotine01";
    }

    private final func GetAddictionNotificationMessageKeyStage2() -> CName {
        //DFProfile();
        return n"DarkFutureAddictionNotificationNicotine02";
    }

    private final func GetAddictionNotificationMessageKeyStage3() -> CName {
        //DFProfile();
        return n"DarkFutureAddictionNotificationNicotine03";
    }

    private final func GetAddictionNotificationMessageKeyStage4() -> CName {
        //DFProfile();
        return n"DarkFutureAddictionNotificationNicotine04";
    }

    private final func GetAddictionNotificationMessageKeyCured() -> CName {
        //DFProfile();
        return n"DarkFutureAddictionNotificationNicotineCured";
    }

    private final func GetAddictionNotificationMessageContext() -> DFMessageContext {
        //DFProfile();
        return DFMessageContext.NicotineAddiction;
    }

    private final func GetAddictionTherapyResponseIndexFact() -> CName {
        //DFProfile();
        return n"df_fact_therapy_nicotine_response";
    }

    private final func GetSetTherapyAddictionStateIndexFactAction() -> CName {
        //DFProfile();
        return n"df_fact_action_set_therapy_addiction_nicotine_state_index";
    }

    private final func GetAddictionStageFact() -> CName {
        //DFProfile();
        return n"df_fact_addiction_stage_nicotine";
    }

    private final func GetAddictionType() -> DFAddictionType {
        //DFProfile();
        return DFAddictionType.Nicotine;
    }

    private final func GetAddictionAdvanceNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureNicotineAddictionIncreaseNotification";
    }

    private final func GetAddictionWithdrawalRemovedNotificationKey() -> CName {
        //DFProfile();
        return n"DarkFutureNicotineAddictionWithdrawalRemovedNotification";
    }

    //
    //  System-Specific Methods
    //
    public final func UpdateActiveNicotineDebuffEffectDuration(effectID: TweakDBID) -> Void {
        //DFProfile();
        if NotEquals(this.GetEffectDuration(), this.GetDefaultDebuffEffectDuration()) {
            GameInstance.GetStatusEffectSystem(GetGameInstance()).SetStatusEffectRemainingDuration(this.player.GetEntityID(), effectID, this.GetEffectDuration());
        }
    }

    private final func UpdateNicotineWithdrawalEffectDisplayData() -> Void {
        //DFProfile();
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_Cessation_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[5]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[5])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_01_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[1]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[1])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_01_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[1]), 1]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_02_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[2]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[2])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_02_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[2]), 1]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_03_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[3]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[3])]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_03_WithProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[3]), 1]);
        TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NicotineWithdrawal_04_NoProgression_UIData.intValues", [Cast<Int32>(this.nicotineAddictionNeedLimits[4]), GameTimeSecondsToHours(this.nicotineAddictionWithdrawalDurationsInGameTimeSeconds[4])]);

        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_Cessation_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_01_NoProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_01_WithProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_02_NoProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_02_WithProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_03_NoProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_03_WithProgression_UIData");
        TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NicotineWithdrawal_04_NoProgression_UIData");
    }
}

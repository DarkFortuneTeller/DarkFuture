// -----------------------------------------------------------------------------
// DFTraumaAfflictionSystem
// -----------------------------------------------------------------------------
//
// - Trauma Affliction system.
// - Trauma occurs after losing enough Nerve while Nerve is low.
// - Cured by Endotrisine.
// - Suppressed by Alcohol.
//

module DarkFuture.Afflictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.HoursToGameTimeSeconds
import DarkFuture.Main.{
    DFAfflictionDatum,
    DFAfflictionUpdateDatum
}
import DarkFuture.Services.{
    DFPlayerStateService,
    DFNotificationService,
    DFTutorial
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let traumaSystem: ref<DFTraumaAfflictionSystem> = DFTraumaAfflictionSystem.Get();

    if IsSystemEnabledAndRunning(traumaSystem) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectTags: array<CName> = evt.staticData.GameplayTags();
        
        traumaSystem.OnStatusEffectApplied(effectID, effectTags);
    }

	return wrappedMethod(evt);
}

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>) -> Bool {
    let traumaSystem: ref<DFTraumaAfflictionSystem> = DFTraumaAfflictionSystem.Get();

    if IsSystemEnabledAndRunning(traumaSystem) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectTags: array<CName> = evt.staticData.GameplayTags();

        DFTraumaAfflictionSystem.Get().OnStatusEffectRemoved(effectID, effectTags);
    }

	return wrappedMethod(evt);
}

class DFTraumaAfflictionSystemEventListener extends DFAfflictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAfflictionSystemBase> {
		return DFTraumaAfflictionSystem.Get();
	}
}

public class DFTraumaAfflictionSystem extends DFAfflictionSystemBase {
    private persistent let accumulatedNerveLoss: Float = 0.0;
    
    private let PlayerStateService: ref<DFPlayerStateService>;
    private let NerveSystem: ref<DFNerveSystem>;

    private let traumaChanceBase: Float = 100.0; // 100% chance
    private let traumaMaxStacks: Uint32 = 5u;
    private let traumaEffect: TweakDBID = t"DarkFutureStatusEffect.Trauma";
    private let traumaTreatmentEffect: TweakDBID = t"DarkFutureStatusEffect.TraumaTreatment";
    private let traumaSuppressionEffectTag: CName = n"DarkFutureAddictionPrimaryEffectAlcohol";
    private let traumaSuppressionTimeInGameHours: Float = 3.0;
    private let nerveLossAccumulationRatesPerStage: array<Float>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFTraumaAfflictionSystem> {
		let instance: ref<DFTraumaAfflictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Afflictions.DFTraumaAfflictionSystem") as DFTraumaAfflictionSystem;
		return instance;
	}

    public final static func Get() -> ref<DFTraumaAfflictionSystem> {
        return DFTraumaAfflictionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Overrides
    //
    private final func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

    private final func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.traumaAfflictionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        return "traumaAfflictionEnabled";
    }

    private final func GetSystems() -> Void {
        super.GetSystems();

        let gameInstance = GetGameInstance();
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
    }

	private final func SetupData() -> Void {
        this.nerveLossAccumulationRatesPerStage = [
            0.0,
            0.0,
            this.Settings.traumaAccumulationRateNerveStage2,
            this.Settings.traumaAccumulationRateNerveStage3Plus,
            this.Settings.traumaAccumulationRateNerveStage3Plus,
            this.Settings.traumaAccumulationRateNerveStage3Plus
        ];

		let treatmentEffect: DFAfflictionCureEffect;
        treatmentEffect.effectID = this.traumaTreatmentEffect;
        treatmentEffect.cureTimerMode = DFAfflictionEffectTimerMode.UseScriptManagedDuration;
        treatmentEffect.cureDurationInGameTimeSeconds = HoursToGameTimeSeconds(24);
        this.cureEffect = treatmentEffect;

        let alcoholEffect: DFAfflictionSuppressionEffect;
        alcoholEffect.effectTag = this.traumaSuppressionEffectTag;
        alcoholEffect.requiresMatchingStackCount = true;
        alcoholEffect.suppressionTimerMode = DFAfflictionEffectTimerMode.UseScriptManagedDuration;
        alcoholEffect.suppressionDurationInGameTimeSeconds = HoursToGameTimeSeconds(6);
        this.suppressionEffect = alcoholEffect;
	}

    private final func DoPostSuspendActions() -> Void {
        this.accumulatedNerveLoss = 0.0;
    }

    private final func DoStopActions() -> Void {}

    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        if ArrayContains(changedSettings, "traumaAccumulationRateNerveStage2") || ArrayContains(changedSettings, "traumaAccumulationRateNerveStage3Plus") {
            this.nerveLossAccumulationRatesPerStage = [
                0.0,
                0.0,
                this.Settings.traumaAccumulationRateNerveStage2,
                this.Settings.traumaAccumulationRateNerveStage3Plus,
                this.Settings.traumaAccumulationRateNerveStage3Plus,
                this.Settings.traumaAccumulationRateNerveStage3Plus
            ];
        }
    }

    //
    //  Required Overrides
    //
    public func OnDamageReceivedEvent(evt: ref<gameDamageReceivedEvent>) -> Void {}

    private final func OnTimeSkipFinishedActual(afflictionData: DFAfflictionDatum) -> Void {
        this.SetAfflictionStacks(afflictionData.trauma.stackCount);
        this.SetCurrentAfflictionCureDurationInGameTimeSeconds(afflictionData.trauma.cureDuration);
        this.SetCurrentAfflictionSuppressionDurationInGameTimeSeconds(afflictionData.trauma.suppressionDuration);
    }

    public final func GetMaxAfflictionStacks() -> Uint32 {
        return this.traumaMaxStacks;
    }

    public final func GetAfflictionEffect() -> TweakDBID {
        return this.traumaEffect;
    }

    private final func DoPostAfflictionSuppressionActions() -> Void {
        this.NerveSystem.ForceNeedMaxValueUpdate();
    }

    private final func DoPostAfflictionApplyActions() -> Void {
        this.accumulatedNerveLoss = 0.0;
        this.NerveSystem.ForceNeedMaxValueUpdate();
    }

    private final func DoPostAfflictionCureActions() -> Void {
		this.NerveSystem.ForceNeedMaxValueUpdate();
    }

    private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialTraumaTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialTrauma";
	}

    private final func CheckTutorial() -> Void {
        if this.Settings.tutorialsEnabled && !this.hasShownTutorial {
            this.hasShownTutorial = true;

            let tutorial: DFTutorial;
            tutorial.title = GetLocalizedTextByKey(n"DarkFutureTutorialTraumaTitle");
            tutorial.message = GetLocalizedTextByKey(n"DarkFutureTutorialTrauma");
            this.NotificationService.QueueTutorial(tutorial);
        }
    }

    //
    //  System-Specific Methods
    //
    public final func AccumulateNerveLoss(amount: Float, opt forceTraumaAccumulation: Bool) -> Void {
        let stageToCheck: Int32 = this.NerveSystem.GetNeedStageAtValue(this.NerveSystem.GetNeedValue() + amount);

        if this.GetAfflictionStacks() < this.GetMaxAfflictionStacks() && amount < 0.0 && (forceTraumaAccumulation || this.PlayerStateService.GetInDanger()) {
            let lossPct: Float = this.nerveLossAccumulationRatesPerStage[stageToCheck] / 100.0;
            this.accumulatedNerveLoss += (amount * lossPct);
            DFLog(this.debugEnabled, this, "@@@@@@@@@ AccumulateNerveLoss: " + ToString(this.accumulatedNerveLoss));

            if this.accumulatedNerveLoss <= -10.0 {
                this.accumulatedNerveLoss = 0.0;
                this.TryToApplyAfflictionStack();
            }
        }
    }
}
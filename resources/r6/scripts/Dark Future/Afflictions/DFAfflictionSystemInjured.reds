// -----------------------------------------------------------------------------
// DFInjuryAfflictionSystem
// -----------------------------------------------------------------------------
//
// - Injury Affliction system.
// - Injury occurs after taking enough cumulative damage.
// - Cured by First Aid Kit (was Health Booster).
//

module DarkFuture.Afflictions

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.RunGuard
import DarkFuture.Services.{
    DFGameStateService,
    DFNotificationService,
    DFTutorial
}
import DarkFuture.Settings.DFSettings

@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let injurySystem: ref<DFInjuryAfflictionSystem> = DFInjuryAfflictionSystem.Get();

    if IsSystemEnabledAndRunning(injurySystem) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectTags: array<CName> = evt.staticData.GameplayTags();
        
        injurySystem.OnStatusEffectApplied(effectID, effectTags);
    }

	return wrappedMethod(evt);
}

class DFInjuryAfflictionSystemEventListener extends DFAfflictionSystemEventListener {
	private func GetSystemInstance() -> wref<DFAfflictionSystemBase> {
		return DFInjuryAfflictionSystem.Get();
	}
}

public class DFInjuryAfflictionSystem extends DFAfflictionSystemBase {
    private persistent let accumulatedHealthPctLoss: Float = 0.0;

    private let injuryMaxStacks: Uint32 = 4u;
    private let injuryEffect: TweakDBID = t"DarkFutureStatusEffect.Injury";
    private let injuryCureEffect: TweakDBID = t"BaseStatusEffect.HealthBooster";
    private let injuryHealthLossAccumulationRate: Float = 10.0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFInjuryAfflictionSystem> {
		let instance: ref<DFInjuryAfflictionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Afflictions.DFInjuryAfflictionSystem") as DFInjuryAfflictionSystem;
		return instance;
	}

    public final static func Get() -> ref<DFInjuryAfflictionSystem> {
        return DFInjuryAfflictionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    private final func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.injuryAfflictionEnabled;
    }

    private final func GetSystemToggleSettingString() -> String {
        return "injuryAfflictionEnabled";
    }

    private func SetupDebugLogging() -> Void {
        this.debugEnabled = false;
    }

	private func SetupData() -> Void {
        this.cureEffect = this.injuryCureEffect;
	}

    private final func DoPostSuspendActions() -> Void {
        this.accumulatedHealthPctLoss = 0.0;
    }

    //
    //  Required Overrides
    //
	public func OnDamageReceivedEvent(evt: ref<gameDamageReceivedEvent>) -> Void {
        if RunGuard(this) { return; }

        if this.GameStateService.IsValidGameState("OnDamageReceived") {
            // Get the percentage of Health lost
            let healthLost: Float = evt.totalDamageReceived;
            let totalHealth: Float = GameInstance.GetStatPoolsSystem(GetGameInstance()).GetStatPoolMaxPointValue(Cast<StatsObjectID>(this.player.GetEntityID()), gamedataStatPoolType.Health);
            let healthLostPct: Float = healthLost / totalHealth;

            this.AccumulateHealthLoss(healthLostPct);
        }
	}

    public func GetMaxAfflictionStacks() -> Uint32 {
        return this.injuryMaxStacks;
    }

    public func GetAfflictionEffect() -> TweakDBID {
        return this.injuryEffect;
    }

    private final func GetTutorialTitleKey() -> CName {
		return n"DarkFutureTutorialInjuryTitle";
	}

	private final func GetTutorialMessageKey() -> CName {
		return n"DarkFutureTutorialInjury";
	}

    private final func CheckTutorial() -> Void {
        if this.Settings.tutorialsEnabled && !this.hasShownTutorial {
            this.hasShownTutorial = true;

            let tutorial: DFTutorial;
            tutorial.title = GetLocalizedTextByKey(this.GetTutorialTitleKey());
            tutorial.message = GetLocalizedTextByKey(this.GetTutorialMessageKey());
            this.NotificationService.QueueTutorial(tutorial);
        }
    }

    //
    //  System-Specific Functions
    //
    public final func AccumulateHealthLoss(percent: Float) -> Void {
        if this.GetAfflictionStacks() < this.GetMaxAfflictionStacks() && percent > 0.0 {
            let lossPct: Float = this.Settings.injuryHealthLossAccumulationRate / 100.0;
            this.accumulatedHealthPctLoss += (percent * lossPct);
            DFLog(this.debugEnabled, this, "&&&&&&&&&& AccumulateHealthLoss: " + ToString(this.accumulatedHealthPctLoss));

            if this.accumulatedHealthPctLoss >= 1.0 {
                this.accumulatedHealthPctLoss = 0.0;
                this.ApplyAfflictionStack();
            }
        }
    }
}
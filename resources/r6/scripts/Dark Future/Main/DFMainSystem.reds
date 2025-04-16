// -----------------------------------------------------------------------------
// DFMainSystem
// -----------------------------------------------------------------------------
//
// - The Dark Future Main System.
// - Handles mod-wide system startup and shutdown.
//

module DarkFuture.Main

import DarkFuture.Logging.*
import DarkFuture.Settings.*
import DarkFuture.Services.{
    DFGameStateService,
    DFCyberwareService,
    DFNotificationService,
    DFPlayerStateService
}
import DarkFuture.Gameplay.{
    DFInteractionSystem,
    DFVehicleSleepSystem,
    DFVehicleSummonSystem,
    DFRandomEncounterSystem,
    DFStashCraftingSystem,
    DFDeceptiousCompatSystem
}
import DarkFuture.Needs.{
    DFHydrationSystem,
    DFNutritionSystem,
    DFEnergySystem,
    DFNerveSystem
}
import DarkFuture.Addictions.{
    DFAlcoholAddictionSystem,
    DFNicotineAddictionSystem,
    DFNarcoticAddictionSystem
}
import DarkFuture.Afflictions.{
    DFInjuryAfflictionSystem
}
import DarkFuture.UI.{
    DFHUDSystem,
    DFRevisedBackpackUISystem
}

public struct DFNeedChangeDatum {
	public let value: Float;
	public let floor: Float;
	public let ceiling: Float;
    public let valueOnStatusEffectApply: Float;
}

public struct DFNeedsDatum {
  	public let hydration: DFNeedChangeDatum;
  	public let nutrition: DFNeedChangeDatum;
	public let energy: DFNeedChangeDatum;
	public let nerve: DFNeedChangeDatum;
}

public struct DFAddictionUpdateDatum {
    public let addictionAmount: Float;
    public let addictionStage: Int32;
    public let withdrawalLevel: Int32;
    public let remainingBackoffDuration: Float;
    public let remainingWithdrawalDuration: Float;
}

public struct DFAddictionDatum {
    public let alcohol: DFAddictionUpdateDatum;
    public let nicotine: DFAddictionUpdateDatum;
    public let narcotic: DFAddictionUpdateDatum;
    public let newAddictionTreatmentDuration: Float;
}

public struct DFAfflictionUpdateDatum {
	public let stackCount: Uint32;
}

public struct DFFutureHoursData {
    public let futureNeedsData: array<DFNeedsDatum>;
    public let futureAddictionData: array<DFAddictionDatum>;
}

public enum DFTimeSkipType {
    TimeSkip = 0,
    FullSleep = 1,
    LimitedSleep = 2
}

public struct DFTimeSkipData {
    public let targetNeedValues: DFNeedsDatum;
    public let targetAddictionValues: DFAddictionDatum;
    public let hoursSkipped: Int32;
    public let timeSkipType: DFTimeSkipType;
}

public enum DFTempEnergyItemType {
    Caffeine = 0,
    Stimulant = 1
}

@wrapMethod(RadialWheelController)
protected cb func OnLateInit(evt: ref<LateInit>) -> Bool {
	let val: Bool = wrappedMethod(evt);

	// Now that we know that the Radial Wheel is done initializing, it's now safe to act on systems
    // that might apply status effects.
	DFMainSystem.Get().OnRadialWheelLateInitDone();
    
    let widgetSlot: ref<inkWidget> = inkWidgetRef.Get(this.statusEffects.slotAnchorRef);
	DFHUDSystem.Get().SetRadialWheelStatusEffectListWidget(widgetSlot);

	return val;
}

@wrapMethod(DeathMenuGameController)
protected cb func OnInitialize() -> Bool {
	let val: Bool = wrappedMethod();
	
	let DFMainSystem: ref<DFMainSystem> = DFMainSystem.Get();
	DFMainSystem.DispatchPlayerDeathEvent();

	return val;
}

@wrapMethod(PlayerDevelopmentData)
private final const func ModifyProficiencyLevel(proficiencyIndex: Int32, isDebug: Bool, opt levelIncrease: Int32) -> Void {
    wrappedMethod(proficiencyIndex, isDebug, levelIncrease);

    let strengthSkillIndex: Int32 = this.GetProficiencyIndexByType(gamedataProficiencyType.StrengthSkill);
    if Equals(strengthSkillIndex, proficiencyIndex) {
        DFLogNoSystem(true, this, "ModifyProficiencyLevel: Updating Strength Skill Proficiency Carry Weight bonus.");
        DFMainSystem.Get().UpdateStrengthSkillBonuses();
    }
}

public class MainSystemPlayerDeathEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemPlayerDeathEvent> {
        return new MainSystemPlayerDeathEvent();
    }
}

public class MainSystemTimeSkipStartEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemTimeSkipStartEvent> {
        return new MainSystemTimeSkipStartEvent();
    }
}

public class MainSystemTimeSkipCancelledEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemTimeSkipCancelledEvent> {
        return new MainSystemTimeSkipCancelledEvent();
    }
}

public class MainSystemTimeSkipFinishedEvent extends CallbackSystemEvent {
    private let data: DFTimeSkipData;

    public func GetData() -> DFTimeSkipData {
        return this.data;
    }

    static func Create(data: DFTimeSkipData) -> ref<MainSystemTimeSkipFinishedEvent> {
        let event = new MainSystemTimeSkipFinishedEvent();
        event.data = data;
        return event;
    }
}

public class MainSystemItemConsumedEvent extends CallbackSystemEvent {
    private let itemRecord: wref<Item_Record>;
    private let animateUI: Bool;

    public func GetItemRecord() -> wref<Item_Record> {
        return this.itemRecord;
    }

    public func GetAnimateUI() -> Bool {
        return this.animateUI;
    }

    static func Create(itemRecord: wref<Item_Record>, animateUI: Bool) -> ref<MainSystemItemConsumedEvent> {
        let event = new MainSystemItemConsumedEvent();
        event.itemRecord = itemRecord;
        event.animateUI = animateUI;
        return event;
    }
}

public class MainSystemLifecycleInitEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleInitEvent> {
        return new MainSystemLifecycleInitEvent();
    }
}

public class MainSystemLifecycleInitDoneEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleInitDoneEvent> {
        return new MainSystemLifecycleInitDoneEvent();
    }
}

public class MainSystemLifecycleResumeEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleResumeEvent> {
        return new MainSystemLifecycleResumeEvent();
    }
}

public class MainSystemLifecycleResumeDoneEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleResumeDoneEvent> {
        return new MainSystemLifecycleResumeDoneEvent();
    }
}

public class MainSystemLifecycleSuspendEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleSuspendEvent> {
        return new MainSystemLifecycleSuspendEvent();
    }
}

public class MainSystemLifecycleSuspendDoneEvent extends CallbackSystemEvent {
    static func Create() -> ref<MainSystemLifecycleSuspendDoneEvent> {
        return new MainSystemLifecycleSuspendDoneEvent();
    }
}

class DFMainSystemEventListeners extends ScriptableService {
    private func GetSystemInstance() -> wref<DFMainSystem> {
		return DFMainSystem.Get();
	}

	private cb func OnLoad() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Settings.SettingChangedEvent", this, n"OnSettingChangedEvent", true);
    }

    private cb func OnSettingChangedEvent(event: ref<SettingChangedEvent>) {
		this.GetSystemInstance().OnSettingChanged(event.GetData());
	}
}

public final class DFMainSystem extends ScriptableSystem {
    private let debugEnabled: Bool = false;

    private let player: ref<PlayerPuppet>;

    // Callback Handles
    private let playerAttachedCallbackID: Uint32;

    private let lateInitDone: Bool = false;


    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFMainSystem> {
		let instance: ref<DFMainSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Main.DFMainSystem") as DFMainSystem;
		return instance;
	}

    public final static func Get() -> ref<DFMainSystem> {
        return DFMainSystem.GetInstance(GetGameInstance());
	}

    //
    //  Startup and Shutdown
    //
    private func OnAttach() -> Void {
        DFLogNoSystem(this.debugEnabled, this, "OnAttach");
        this.playerAttachedCallbackID = GameInstance.GetPlayerSystem(GetGameInstance()).RegisterPlayerPuppetAttachedCallback(this, n"PlayerAttachedCallback");
    }

    private final func PlayerAttachedCallback(playerPuppet: ref<GameObject>) -> Void {
		if IsDefined(playerPuppet) {
            DFLogNoSystem(this.debugEnabled, this, "PlayerAttachedCallback playerPuppet TweakDBID: " + TDBID.ToStringDEBUG((playerPuppet as PlayerPuppet).GetRecord().GetID()));
            this.player = playerPuppet as PlayerPuppet;

            // Player Replacer / Act 2 Handling - If Late Init is already Done, start all systems.
            if this.lateInitDone {
                this.StartAll();
                this.RefreshAlwaysOnEffects();
            }
        }
    }

    public final func OnRadialWheelLateInitDone() -> Void {
        if !this.lateInitDone {
            this.lateInitDone = true;
            this.StartAll();
            this.RefreshAlwaysOnEffects();
        }
	}

    private final func StartAll() -> Void {
        let gameInstance = GetGameInstance();
        if !IsDefined(this.player) {
            DFLogNoSystem(true, this, "ERROR: PLAYER NOT DEFINED ON DFMainSystem:StartAll()", DFLogLevel.Error);
            return;
        }
        DFLogNoSystem(this.debugEnabled, this, "!!!!! DFMainSystem:StartAll !!!!!");

        // Settings
        DFSettings.GetInstance(gameInstance).Init(this.player);

        // Lifecycle Hook - Start
        this.DispatchLifecycleInitEvent();

        // Services
        DFGameStateService.GetInstance(gameInstance).Init(this.player);
        DFNotificationService.GetInstance(gameInstance).Init(this.player);
        DFPlayerStateService.GetInstance(gameInstance).Init(this.player);

        // Gameplay Systems
        DFVehicleSleepSystem.GetInstance(gameInstance).Init(this.player);
        DFVehicleSummonSystem.GetInstance(gameInstance).Init(this.player);
        DFInteractionSystem.GetInstance(gameInstance).Init(this.player);
        DFStashCraftingSystem.GetInstance(gameInstance).Init(this.player);
        DFRandomEncounterSystem.GetInstance(gameInstance).Init(this.player);

        // Basic Needs
        DFHydrationSystem.GetInstance(gameInstance).Init(this.player);
        DFNutritionSystem.GetInstance(gameInstance).Init(this.player);
        DFEnergySystem.GetInstance(gameInstance).Init(this.player);

        // Addictions
        DFAlcoholAddictionSystem.GetInstance(gameInstance).Init(this.player);
        DFNicotineAddictionSystem.GetInstance(gameInstance).Init(this.player);
        DFNarcoticAddictionSystem.GetInstance(gameInstance).Init(this.player);

        // Nerve
        DFNerveSystem.GetInstance(gameInstance).Init(this.player);

        // Cyberware Service
        DFCyberwareService.GetInstance(gameInstance).Init(this.player);

        // Afflictions
        DFInjuryAfflictionSystem.GetInstance(gameInstance).Init(this.player);

        // UI
        DFHUDSystem.GetInstance(gameInstance).Init(this.player);
        DFRevisedBackpackUISystem.GetInstance(gameInstance).Init(this.player);

        // Compatibility
        DFDeceptiousCompatSystem.GetInstance(gameInstance).Init(this.player);

        // Reconcile settings changes
        DFSettings.GetInstance(gameInstance).ReconcileSettings();

        // Lifecycle Hook - Done
        this.DispatchLifecycleInitDoneEvent();
    }

    private final func ResumeAll() -> Void {
        DFLogNoSystem(this.debugEnabled, this, "!!!!! DFMainSystem:ResumeAll !!!!!");
        let gameInstance = GetGameInstance();

        // Lifecycle Hook - Start
        this.DispatchLifecycleResumeEvent();

        // Services
        DFGameStateService.GetInstance(gameInstance).Resume();
        DFNotificationService.GetInstance(gameInstance).Resume();
        DFPlayerStateService.GetInstance(gameInstance).Resume();

        // Gameplay Systems
        DFVehicleSleepSystem.GetInstance(gameInstance).Resume();
        DFVehicleSummonSystem.GetInstance(gameInstance).Resume();
        DFInteractionSystem.GetInstance(gameInstance).Resume();
        DFStashCraftingSystem.GetInstance(gameInstance).Resume();
        DFRandomEncounterSystem.GetInstance(gameInstance).Resume();

        // Basic Needs
        DFHydrationSystem.GetInstance(gameInstance).Resume();
        DFNutritionSystem.GetInstance(gameInstance).Resume();
        DFEnergySystem.GetInstance(gameInstance).Resume();

        // Addictions
        DFAlcoholAddictionSystem.GetInstance(gameInstance).Resume();
        DFNicotineAddictionSystem.GetInstance(gameInstance).Resume();
        DFNarcoticAddictionSystem.GetInstance(gameInstance).Resume();

        // Nerve
        DFNerveSystem.GetInstance(gameInstance).Resume();

        // Cyberware Service
        DFCyberwareService.GetInstance(gameInstance).Resume();

        // Afflictions
        DFInjuryAfflictionSystem.GetInstance(gameInstance).Resume();

        // UI
        DFHUDSystem.GetInstance(gameInstance).Resume();
        DFRevisedBackpackUISystem.GetInstance(gameInstance).Resume();

        // Compatibility
        DFDeceptiousCompatSystem.GetInstance(gameInstance).Resume();

        // Lifecycle Hook - Done
        this.DispatchLifecycleResumeDoneEvent();
    }

    private final func SuspendAll() -> Void {
        DFLogNoSystem(this.debugEnabled, this, "!!!!! DFMainSystem:SuspendAll !!!!!");

        let gameInstance = GetGameInstance();

        // Lifecycle Hook - Start
        this.DispatchLifecycleSuspendEvent();

        // Compatibility
        DFDeceptiousCompatSystem.GetInstance(gameInstance).Suspend();

        // UI
        DFRevisedBackpackUISystem.GetInstance(gameInstance).Suspend();
        DFHUDSystem.GetInstance(gameInstance).Suspend();

        // Afflictions
        DFInjuryAfflictionSystem.GetInstance(gameInstance).Suspend();
        
        // Cyberware Service
        DFCyberwareService.GetInstance(gameInstance).Suspend();

        // Nerve
        DFNerveSystem.GetInstance(gameInstance).Suspend();

        // Addictions
        DFNarcoticAddictionSystem.GetInstance(gameInstance).Suspend();
        DFNicotineAddictionSystem.GetInstance(gameInstance).Suspend();
        DFAlcoholAddictionSystem.GetInstance(gameInstance).Suspend();
        
        // Basic Needs
        DFEnergySystem.GetInstance(gameInstance).Suspend();
        DFNutritionSystem.GetInstance(gameInstance).Suspend();
        DFHydrationSystem.GetInstance(gameInstance).Suspend();
        
        // Gameplay Systems
        DFRandomEncounterSystem.GetInstance(gameInstance).Suspend();
        DFStashCraftingSystem.GetInstance(gameInstance).Suspend();
        DFInteractionSystem.GetInstance(gameInstance).Suspend();
        DFVehicleSummonSystem.GetInstance(gameInstance).Suspend();
        DFVehicleSleepSystem.GetInstance(gameInstance).Suspend();

        // Services
        DFPlayerStateService.GetInstance(gameInstance).Suspend();
        DFNotificationService.GetInstance(gameInstance).Suspend();
        DFGameStateService.GetInstance(gameInstance).Suspend();

        // Lifecycle Hook - Done
        this.DispatchLifecycleSuspendDoneEvent();
    }

    private final func RefreshAlwaysOnEffects() -> Void {
        let settings: ref<DFSettings> = DFSettings.Get();
        if settings.mainSystemEnabled {
            if settings.increasedStaminaRecoveryTime {
                if !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnStaminaRegen") {
                    StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnStaminaRegen");
                }
            } else {
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnStaminaRegen");
            }
			
            if Equals(settings.reducedCarryWeight, DFReducedCarryWeightAmount.Full) {
                if !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityFull") {
                    StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityFull");
                }
            } else {
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityFull");
            }

            if Equals(settings.reducedCarryWeight, DFReducedCarryWeightAmount.Half) {
                if !StatusEffectSystem.ObjectHasStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityHalf") {
                    StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityHalf");
                }
            } else {
                StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacityHalf");
            }

		} else {
            StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnStaminaRegen");
            StatusEffectHelper.RemoveStatusEffect(this.player, t"DarkFutureStatusEffect.DarkFutureAlwaysOnCarryCapacity");
        }

        this.UpdateStrengthSkillBonuses();
    }

    public final func OnSettingChanged(changedSettings: array<String>) -> Void {
        let settings: ref<DFSettings> = DFSettings.Get();
        if ArrayContains(changedSettings, "increasedStaminaRecoveryTime") || ArrayContains(changedSettings, "reducedCarryWeight") {
            this.RefreshAlwaysOnEffects();
        }

        if ArrayContains(changedSettings, "mainSystemEnabled") {
            if settings.mainSystemEnabled {
                this.ResumeAll();
            } else {
                this.SuspendAll();
            }
            this.RefreshAlwaysOnEffects();
        }
    }

    public final func UpdateStrengthSkillBonuses() -> Void {
        let developmentData: ref<PlayerDevelopmentData> = PlayerDevelopmentSystem.GetInstance(this.player).GetDevelopmentData(this.player);
        let newLevel: Int32 = developmentData.GetProficiencyLevel(gamedataProficiencyType.StrengthSkill);
        StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureStrengthSkillCarryWeightPenalty");
        DFLogNoSystem(this.debugEnabled, this, "    Solo Skill: " + ToString(newLevel));

        let strengthSkillLevel5NewBonus: Int32;
        let strengthSkillLevel25NewBonus: Int32;

        let reducedCarryWeightSettingValue: DFReducedCarryWeightAmount = DFSettings.Get().reducedCarryWeight;
        if Equals(reducedCarryWeightSettingValue, DFReducedCarryWeightAmount.Full) {
            strengthSkillLevel5NewBonus = 20;
            strengthSkillLevel25NewBonus = 30;
            if newLevel >= 25 {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StrengthSkillPenaltyFull25");

            } else if newLevel >= 5 {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StrengthSkillPenaltyFull5");
            }

        } else if Equals(reducedCarryWeightSettingValue, DFReducedCarryWeightAmount.Half) {
            strengthSkillLevel5NewBonus = 25;
            strengthSkillLevel25NewBonus = 50;
            if newLevel >= 25 {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StrengthSkillPenaltyHalf25");

            } else if newLevel >= 5 {
                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.StrengthSkillPenaltyHalf5");
            }
        
        } else if Equals(reducedCarryWeightSettingValue, DFReducedCarryWeightAmount.Off) {
            strengthSkillLevel5NewBonus = 50;
            strengthSkillLevel25NewBonus = 100;
        }

        // Update the descriptions in the Skill Proficiencies UI
        TweakDBManager.SetFlat(t"Proficiencies.StrengthSkill_inline1.intValues", [strengthSkillLevel5NewBonus]);
        TweakDBManager.SetFlat(t"Proficiencies.StrengthSkill_inline7.intValues", [strengthSkillLevel25NewBonus]);
        TweakDBManager.UpdateRecord(t"Proficiencies.StrengthSkill_inline1");
        TweakDBManager.UpdateRecord(t"Proficiencies.StrengthSkill_inline7");
    }

    public final func DispatchPlayerDeathEvent() -> Void {
        DFLogNoSystem(this.debugEnabled, this, "!!!!! DFMainSystem:DispatchPlayerDeathEvent !!!!!");
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemPlayerDeathEvent.Create());
    }

    public final func DispatchTimeSkipStartEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemTimeSkipStartEvent.Create());
    }

    public final func DispatchTimeSkipCancelledEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemTimeSkipCancelledEvent.Create());
    }

    public final func DispatchTimeSkipFinishedEvent(data: DFTimeSkipData) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemTimeSkipFinishedEvent.Create(data));
    }

    public final func DispatchItemConsumedEvent(itemRecord: wref<Item_Record>, animateUI: Bool) -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemItemConsumedEvent.Create(itemRecord, animateUI));
    }

    //
    //  Lifecycle Events for Dark Future Add-Ons and Mods
    //
    public final func DispatchLifecycleInitEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleInitEvent.Create());
    }

    public final func DispatchLifecycleInitDoneEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleInitDoneEvent.Create());
    }

    public final func DispatchLifecycleResumeEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleResumeEvent.Create());
    }

    public final func DispatchLifecycleResumeDoneEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleResumeDoneEvent.Create());
    }

    public final func DispatchLifecycleSuspendEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleSuspendEvent.Create());
    }

    public final func DispatchLifecycleSuspendDoneEvent() -> Void {
        GameInstance.GetCallbackSystem().DispatchEvent(MainSystemLifecycleSuspendDoneEvent.Create());
    }
}

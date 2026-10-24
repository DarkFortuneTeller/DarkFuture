// -----------------------------------------------------------------------------
// DFModCompatSystem
// -----------------------------------------------------------------------------
//
// - System that provides compatibility with Idle Anywhere, Hotscenes, and other mods
//   that require logic in order to ensure compatibility.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Settings.DFSettings
import DarkFuture.Main.{
    DFMainSystem,
    DFTimeSkipData
}
import DarkFuture.Needs.{
    DFNerveSystem,
    DFHydrationSystem,
    DFNutritionSystem
}
import DarkFuture.Services.{
    DFPlayerStateService,
    DFGameStateService,
    DFManagedEffectPipelineResult
}
import DarkFuture.Gameplay.DFInteractionSystem
import DarkFuture.Utils.DFRunGuard

@if(ModuleExists("ConsumableAnimations.Settings"))
import ConsumableAnimations.Settings.{
    CASettings
}

class DFModCompatSystemEventListener extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFModCompatSystem> {
        //DFProfile();
        return DFModCompatSystem.Get();
    }
}

public final class DFModCompatSystem extends DFSystem {
    private let QuestsSystem: ref<QuestsSystem>;
    private let TransactionSystem: ref<TransactionSystem>;
    private let MainSystem: ref<DFMainSystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let HydrationSystem: ref<DFHydrationSystem>;
    private let NutritionSystem: ref<DFNutritionSystem>;
    private let InteractionSystem: ref<DFInteractionSystem>;
    private let PlayerStateService: ref<DFPlayerStateService>;
    private let GameStateService: ref<DFGameStateService>;

    // Idle Anywhere
    private let IAEatFactListener: Uint32;
    private let IADrinkFactListener: Uint32;
    private let IAAlcoholFactListener: Uint32;
    private let IASmokeFactListener: Uint32;
    private let IFVEatDrinkFactListener: Uint32;
    private let IBTDrinkFactListener: Uint32;

    private let IAEatFactLastValue: Int32 = 0;
    private let IADrinkFactLastValue: Int32 = 0;
    private let IAAlcoholFactLastValue: Int32 = 0;
    private let IASmokeFactLastValue: Int32 = 0;
    private let IATriggerFactLastValue: Int32 = 0;
    private let IFVEatDrinkFactLastValue: Int32 = 0;
    private let IBTDrinkFactLastValue: Int32 = 0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFModCompatSystem> {
        //DFProfile();
        let instance: ref<DFModCompatSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFModCompatSystem>()) as DFModCompatSystem;
        return instance;
    }

    public final static func Get() -> ref<DFModCompatSystem> {
        //DFProfile();
        return DFModCompatSystem.GetInstance(GetGameInstance());
    }

    // DFSystem Required Methods
    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        // This system does not have a system-specific toggle.
        return true;
    }

    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        // This system does not have a system-specific toggle.
        return "INVALID";
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        // Consumable Animations - Ensure that it is enabled, if installed.
        if this.IsConsumableAnimationsInstalled() {
            this.ToggleConsumableAnimationsOn();
        }
    }

    public func DoPostResumeActions() -> Void {
        //DFProfile();
        // Consumable Animations - Ensure that it is disabled if Dark Future is installed.
        if this.IsConsumableAnimationsInstalled() {
            this.ToggleConsumableAnimationsOff();
        }
    }
    
    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance: GameInstance = GetGameInstance();
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
        this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
    }
    
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    
    public func SetupData() -> Void {
        //DFProfile();
        this.IAEatFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_food");
        this.IADrinkFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_drink");
        this.IAAlcoholFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_alco");
        this.IASmokeFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_smoke");
        this.IATriggerFactLastValue = this.QuestsSystem.GetFact(n"deceptious_idle");
        this.IFVEatDrinkFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_foodvendor");
        this.IBTDrinkFactLastValue = this.QuestsSystem.GetFact(n"dec_dark_bartender");
    }
    
    private func RegisterListeners() -> Void {
        //DFProfile();
        // Idle Anywhere
        this.IAEatFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_food", this, n"OnIAEatFactChanged");
        this.IADrinkFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_drink", this, n"OnIADrinkFactChanged");
        this.IAAlcoholFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_alco", this, n"OnIAAlcoholFactChanged");
        this.IASmokeFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_smoke", this, n"OnIASmokeFactChanged");

        // Immersive Food Vendors
        this.IFVEatDrinkFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_foodvendor", this, n"OnIFVEatDrinkFactChanged");

        // Immersive Bartenders
        this.IBTDrinkFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_bartender", this, n"OnIBTDrinkFactChanged");
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        // Consumable Animations - Ensure that it is disabled if Dark Future is installed.
        if this.IsConsumableAnimationsInstalled() {
            this.ToggleConsumableAnimationsOff();
        }
    }
    
    private func UnregisterListeners() -> Void {  
        //DFProfile();
        this.QuestsSystem.UnregisterListener(n"dec_dark_food", this.IAEatFactListener);
        this.IAEatFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_drink", this.IADrinkFactListener);
        this.IADrinkFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_alco", this.IAAlcoholFactListener);
        this.IAAlcoholFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_smoke", this.IASmokeFactListener);
        this.IASmokeFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_foodvendor", this.IFVEatDrinkFactListener);
        this.IFVEatDrinkFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_bartender", this.IBTDrinkFactListener);
        this.IBTDrinkFactListener = 0u;
    }

    public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipBegin() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    // System-Specific Methods
    private final func OnIAEatFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIAEatFactChanged: value = " + ToString(value));
        if Equals(this.IAEatFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Food Consumed
            if this.NerveSystem.GetHasNausea() {
                this.InteractionSystem.QueueVomitFromInteractionChoice();
            } else {
                let foodTDBID: TweakDBID = GetFoodRecordFromIdleAnywhereFactValue(value);
                if NotEquals(foodTDBID, t"") {
                    let foodRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(foodTDBID);
                    if IsDefined(foodRecord) {
                        this.MainSystem.DispatchItemConsumedEvent(foodRecord, true, true);

                        if foodRecord.TagsContains(n"DarkFutureAppliesBonusEffect") {
                            StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.WellFed");
                        }
                    }
                }
            }
        }
        
        this.IAEatFactLastValue = value;
    }

    private final func OnIADrinkFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIADrinkFactChanged: value = " + ToString(value));
        if Equals(this.IADrinkFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Drink Consumed
            let drinkTDBID: TweakDBID = GetDrinkRecordFromIdleAnywhereFactValue(value);
            if NotEquals(drinkTDBID, t"") {
                let drinkRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(drinkTDBID);
                if IsDefined(drinkRecord) {
                    this.MainSystem.DispatchItemConsumedEvent(drinkRecord, true, true);

                    if drinkRecord.TagsContains(n"DarkFutureAppliesBonusEffect") {
                        StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Sated");
                    }
                }
            }
        }
        
        this.IADrinkFactLastValue = value;
    }

    private final func OnIAAlcoholFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIAAlcoholFactChanged: value = " + ToString(value));
        if Equals(this.IAAlcoholFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Alcohol Consumed
            let alcoholTDBID: TweakDBID = GetAlcoholRecordFromIdleAnywhereFactValue(value);
            if NotEquals(alcoholTDBID, t"") {
                let alcoholRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(alcoholTDBID);
                if IsDefined(alcoholRecord) {
                    this.MainSystem.DispatchItemConsumedEvent(alcoholRecord, true, true);

                    // Grant Legendary Alcohol benefits.
                    if Equals(alcoholTDBID, t"Items.TopQualityAlcohol8") || Equals(alcoholTDBID, t"Items.TopQualityAlcohol9") || Equals(alcoholTDBID, t"Items.TopQualityAlcohol10") {
                        StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.LegendaryAlcoholXP");
                    }
                }
            }
        }
        
        this.IAAlcoholFactLastValue = value;
    }

    private final func OnIASmokeFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIASmokeFactChanged: value = " + ToString(value));
        if Equals(this.IASmokeFactLastValue, -1) && Equals(value, 1) { // -1 == Ready, 1 == Smoked
            // The Interaction System handles all appropriate effects from the choice prompt.
            // If the player has any cigarettes, remove a pack.
            let cigaretteType1Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"Items.GenericJunkItem23"));
            let cigaretteType2Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"Items.GenericJunkItem24"));
            let cigaretteType3Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"DarkFutureItem.CigarettePackC"));

            let itemToRemove: TweakDBID = t"";
            if cigaretteType1Count > 0 {
                itemToRemove = t"Items.GenericJunkItem23";

            } else if cigaretteType2Count > 0 {
                itemToRemove = t"Items.GenericJunkItem24";

            } else if cigaretteType3Count > 0 {
                itemToRemove = t"DarkFutureItem.CigarettePackC";
            }

            if NotEquals(itemToRemove, t"") {
                this.TransactionSystem.RemoveItemByTDBID(this.player, itemToRemove, 1);
            }

            if this.GameStateService.IsValidGameState(this, true) && !this.InteractionSystem.IsWithinSmokePromptDebounceWindow() {
                this.PlayerStateService.HandleManagedConsumable(TweakDBInterface.GetItemRecord(itemToRemove), true);
            } else {
                DFLog(this, "Ignoring request; game state not valid, or within the smoking prompt debounce window.");
            }
        }
        
        this.IASmokeFactLastValue = value;
    }

    private final func OnIFVEatDrinkFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIFVEatDrinkFactChanged: value = " + ToString(value));
        if Equals(this.IFVEatDrinkFactLastValue, -1) && value >= 1 { // -1 == Ready
            let consumableTDBID: TweakDBID;
            if value == 7 { // Beer (Not Handled Here)
                return;
            } else if value == 1 || value == 2 || value == 3 || value == 4 { // Sandwich, Burger, Sushi, Fruit ($20-$35)
                consumableTDBID = t"Items.GoodQualityFood10"; // Locust Pepperoni Pizza (Nutrition Tier 3, applies bonus)
            } else if value == 5 || value == 6 { // Pudding, Hot Dog ($10 - $15)
                consumableTDBID = t"Items.LowQualityFood3"; // Hawt Dawg (Nutrition Tier 2, applies bonus)
            } else if value == 8 { // Soda ($15)
                consumableTDBID = t"Items.LowQualityDrink10"; // NiCola (Hydration Tier 1, applies Nerve penalty)
            }

            let isFood: Bool = value >= 1 && value <= 6;
            let isSoda: Bool = value == 8;

            if NotEquals(consumableTDBID, t"") {
                let consumableRecord: wref<Item_Record>;
                if isFood {
                    if this.NerveSystem.GetHasNausea() {
                        this.InteractionSystem.QueueVomitFromInteractionChoice();
                    } else {
                        consumableRecord = TweakDBInterface.GetItemRecord(consumableTDBID);
                        if IsDefined(consumableRecord) {
                            this.MainSystem.DispatchItemConsumedEvent(consumableRecord, true, true);
                            if consumableRecord.TagsContains(n"DarkFutureAppliesBonusEffect") {
                                StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.WellFed");
                            }
                        }
                    }
                } else if isSoda {
                    consumableRecord = TweakDBInterface.GetItemRecord(consumableTDBID);
                    if IsDefined(consumableRecord) {
                        this.MainSystem.DispatchItemConsumedEvent(consumableRecord, true, true);
                    }
                }
            }
        }
        
        this.IFVEatDrinkFactLastValue = value;
    }

    private final func OnIBTDrinkFactChanged(value: Int32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

        DFLog(this, "OnIBTDrinkFactChanged: value = " + ToString(value));
        if Equals(this.IBTDrinkFactLastValue, -1) && value == 4 { // -1 == Ready, 4 == Soda
            let consumableRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(t"Items.LowQualityDrink10"); // NiCola
            if IsDefined(consumableRecord) {
                this.MainSystem.DispatchItemConsumedEvent(consumableRecord, true, true);
            }
        }
        
        this.IBTDrinkFactLastValue = value;
    }

    @if(ModuleExists("ConsumableAnimations.Main"))
    private func IsConsumableAnimationsInstalled() -> Bool {
        //DFProfile();
        return true;
    }

    @if(!ModuleExists("ConsumableAnimations.Main"))
    private func IsConsumableAnimationsInstalled() -> Bool {
        //DFProfile();
        return false;
    }

    @if(ModuleExists("ConsumableAnimations.Settings"))
    private func ToggleConsumableAnimationsOff() -> Void {
        //DFProfile();
        let caSettings: ref<CASettings> = CASettings.GetInstance(GetGameInstance());
        caSettings.mainSystemEnabled = false;
        caSettings.OnModSettingsChange();
    }

    @if(!ModuleExists("ConsumableAnimations.Settings"))
    private func ToggleConsumableAnimationsOff() -> Void {
        //DFProfile();
        // Do nothing
    }

    @if(ModuleExists("ConsumableAnimations.Settings"))
    private func ToggleConsumableAnimationsOn() -> Void {
        //DFProfile();
        let caSettings: ref<CASettings> = CASettings.GetInstance(GetGameInstance());
        caSettings.mainSystemEnabled = true;
        caSettings.OnModSettingsChange();
    }

    @if(!ModuleExists("ConsumableAnimations.Settings"))
    private func ToggleConsumableAnimationsOn() -> Void {
        //DFProfile();
        // Do nothing
    }
}
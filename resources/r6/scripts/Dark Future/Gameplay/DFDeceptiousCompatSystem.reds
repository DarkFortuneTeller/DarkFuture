// -----------------------------------------------------------------------------
// DFDeceptiousCompatSystem
// -----------------------------------------------------------------------------
//
// - System that provides compatibility with Idle Anywhere.
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
import DarkFuture.Gameplay.DFInteractionSystem
import DarkFuture.Utils.RunGuard

class DFDeceptiousCompatSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFDeceptiousCompatSystem> {
		return DFDeceptiousCompatSystem.Get();
	}
}

public final class DFDeceptiousCompatSystem extends DFSystem {
    private let QuestsSystem: ref<QuestsSystem>;
    private let TransactionSystem: ref<TransactionSystem>;
    private let MainSystem: ref<DFMainSystem>;
    private let NerveSystem: ref<DFNerveSystem>;
    private let HydrationSystem: ref<DFHydrationSystem>;
    private let NutritionSystem: ref<DFNutritionSystem>;
    private let InteractionSystem: ref<DFInteractionSystem>;

    private let IAEatFactListener: Uint32;
    private let IADrinkFactListener: Uint32;
    private let IAAlcoholFactListener: Uint32;
    private let IASmokeFactListener: Uint32;

    private let IAEatFactLastValue: Int32 = 0;
    private let IADrinkFactLastValue: Int32 = 0;
    private let IAAlcoholFactLastValue: Int32 = 0;
    private let IASmokeFactLastValue: Int32 = 0;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFDeceptiousCompatSystem> {
		let instance: ref<DFDeceptiousCompatSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Gameplay.DFDeceptiousCompatSystem") as DFDeceptiousCompatSystem;
		return instance;
	}

	public final static func Get() -> ref<DFDeceptiousCompatSystem> {
		return DFDeceptiousCompatSystem.GetInstance(GetGameInstance());
	}

    // DFSystem Required Methods
    private func SetupDebugLogging() -> Void {
        this.debugEnabled = true;
    }

    private func GetSystemToggleSettingValue() -> Bool {
        // This system does not have a system-specific toggle.
		return true;
    }

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
        return "INVALID";
    }

    private func DoPostSuspendActions() -> Void {}
    private func DoPostResumeActions() -> Void {}
    private func DoStopActions() -> Void {}
    
    private func GetSystems() -> Void {
        let gameInstance = GetGameInstance();
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
        this.MainSystem = DFMainSystem.GetInstance(gameInstance);
        this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
        this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
        this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
        this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
    }
    
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func SetupData() -> Void {}
    private func RegisterListeners() -> Void {
        // Idle Anywhere
        this.IAEatFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_food", this, n"OnIAEatFactChanged");
        this.IADrinkFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_drink", this, n"OnIADrinkFactChanged");
        this.IAAlcoholFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_alco", this, n"OnIAAlcoholFactChanged");
        this.IASmokeFactListener = this.QuestsSystem.RegisterListener(n"dec_dark_smoke", this, n"OnIASmokeFactChanged");
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    
    private func UnregisterListeners() -> Void {  
        this.QuestsSystem.UnregisterListener(n"dec_dark_food", this.IAEatFactListener);
        this.IAEatFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_drink", this.IADrinkFactListener);
        this.IADrinkFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_alco", this.IAAlcoholFactListener);
        this.IAAlcoholFactListener = 0u;

        this.QuestsSystem.UnregisterListener(n"dec_dark_smoke", this.IASmokeFactListener);
        this.IASmokeFactListener = 0u;
    }

    private func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    // System-Specific Methods
    private final func OnIAEatFactChanged(value: Int32) -> Void {
        if RunGuard(this) { return; }

        DFLog(this, "OnIAEatFactChanged: value = " + ToString(value));
        if Equals(this.IAEatFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Food Consumed
            if this.NerveSystem.GetHasNausea() {
                this.InteractionSystem.QueueVomitFromInteractionChoice();
            } else {
                let foodTDBID: TweakDBID = GetFoodRecordFromIdleAnywhereFactValue(value);
                if NotEquals(foodTDBID, t"") {
                    let foodRecord: wref<ConsumableItem_Record> = TweakDBInterface.GetConsumableItemRecord(foodTDBID);
                    if IsDefined(foodRecord) {
                        this.MainSystem.DispatchItemConsumedEvent(foodRecord);

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
        if RunGuard(this) { return; }

        DFLog(this, "OnIADrinkFactChanged: value = " + ToString(value));
        if Equals(this.IADrinkFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Drink Consumed
            if this.NerveSystem.GetHasNausea() {
                this.InteractionSystem.QueueVomitFromInteractionChoice();
            } else {
                let drinkTDBID: TweakDBID = GetDrinkRecordFromIdleAnywhereFactValue(value);
                if NotEquals(drinkTDBID, t"") {
                    let drinkRecord: wref<ConsumableItem_Record> = TweakDBInterface.GetConsumableItemRecord(drinkTDBID);
                    if IsDefined(drinkRecord) {
                        this.MainSystem.DispatchItemConsumedEvent(drinkRecord);

                        if drinkRecord.TagsContains(n"DarkFutureAppliesBonusEffect") {
                            StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.Sated");
                        }
                    }
                }
            }
        }
        
        this.IADrinkFactLastValue = value;
    }

    private final func OnIAAlcoholFactChanged(value: Int32) -> Void {
        if RunGuard(this) { return; }

        DFLog(this, "OnIAAlcoholFactChanged: value = " + ToString(value));
        if Equals(this.IAAlcoholFactLastValue, -1) && value >= 0 { // -1 == Ready, >= 0 == Alcohol Consumed
            let alcoholTDBID: TweakDBID = GetAlcoholRecordFromIdleAnywhereFactValue(value);
            if NotEquals(alcoholTDBID, t"") {
                let alcoholRecord: wref<ConsumableItem_Record> = TweakDBInterface.GetConsumableItemRecord(alcoholTDBID);
                if IsDefined(alcoholRecord) {
                    this.MainSystem.DispatchItemConsumedEvent(alcoholRecord);

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
        if RunGuard(this) { return; }

        DFLog(this, "OnIASmokeFactChanged: value = " + ToString(value));
        if Equals(this.IASmokeFactLastValue, -1) && Equals(value, 1) { // -1 == Ready, 1 == Smoked
            // Let the Interaction System know that this was not a base game smoking interaction.
            this.InteractionSystem.SetSmokingInteractionCheckQueued(false);
            this.InteractionSystem.UnregisterForSmokingInteractionCheck();
            
            // If the player has any cigarettes, remove a pack, and apply the correct gameplay effects.
            let cigaretteType1Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"Items.GenericJunkItem23"));
            let cigaretteType2Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"Items.GenericJunkItem24"));
            let cigaretteType3Count: Int32 = this.TransactionSystem.GetItemQuantity(this.player, ItemID.FromTDBID(t"DarkFutureItem.CigarettePackC"));

            if cigaretteType1Count > 0 {
                this.ConsumeCigarette(t"Items.GenericJunkItem23");
            } else if cigaretteType2Count > 0 {
                this.ConsumeCigarette(t"Items.GenericJunkItem24");
            } else if cigaretteType3Count > 0 {
                this.ConsumeCigarette(t"DarkFutureItem.CigarettePackC");
            }
        }
        
        this.IASmokeFactLastValue = value;
    }

    private final func ConsumeCigarette(tdbid: TweakDBID) {
        this.TransactionSystem.RemoveItemByTDBID(this.player, tdbid, 1);
        let cigaretteRecord: wref<ConsumableItem_Record> = TweakDBInterface.GetConsumableItemRecord(tdbid);
        if IsDefined(cigaretteRecord) {
            if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"DarkFutureSmoking") {
				StatusEffectHelper.RemoveStatusEffectsWithTag(this.player, n"DarkFutureSmoking");
			}
			
			// Smoking status effect variant to suppress additional unneeded FX
			StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.SmokingFromChoice");

            this.MainSystem.DispatchItemConsumedEvent(cigaretteRecord);
        }
    }
}
// -----------------------------------------------------------------------------
// DFNeedConsumables
// -----------------------------------------------------------------------------
//
// - Provides consumable item data for Basic Needs.
// - Handles method overrides for consumable usage in various scenarios.
//

import DarkFuture.Main.{
	DFMainSystem,
	DFNeedsDatum,
	DFNeedChangeDatum
}
import DarkFuture.Needs.DFNerveSystem
import DarkFuture.Settings.*

// Allow certain types of consumables (Black Lace, etc) to be used in combat.
// Fix a base game bug that prevented Inhalers and Injectors from being swapped between in the Backpack Inventory (but not
// in Quick Access or the Radial Menu).
// Disallow the use of food and drink outside of combat based on Nerve.
@replaceMethod(InventoryGPRestrictionHelper)
public final static func CanUse(const itemData: script_ref<InventoryItemData>, playerPuppet: wref<PlayerPuppet>) -> Bool {
	let bb: ref<IBlackboard>;
	let canUse: Bool = InventoryGPRestrictionHelper.CanInteractByEquipmentArea(itemData, playerPuppet);
	// Edit Start
	if Equals(Deref(itemData).ItemType, gamedataItemType.Prt_Program) {
		bb = GameInstance.GetBlackboardSystem(GetGameInstance()).GetLocalInstanced(playerPuppet.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
		if bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 {
			canUse = false;
		}
	} else if Equals(Deref(itemData).EquipmentArea, gamedataEquipmentArea.Consumable) {
		bb = GameInstance.GetBlackboardSystem(GetGameInstance()).GetLocalInstanced(playerPuppet.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
		if bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 {
			// Allow the use of inhalers, injectors, and any items with Combat Use Allowed tag while in combat.
			let itemType: gamedataItemType = Deref(itemData).GameItemData.GetItemType();
			if Equals(itemType, gamedataItemType.Con_Inhaler) || Equals(itemType, gamedataItemType.Con_Injector) {
				canUse = true;
			} else if Deref(itemData).GameItemData.HasTag(n"DarkFutureConsumableCombatUseAllowed") {
				canUse = true;
			} else {
				canUse = false;
			}
      	} else {
			// Disallow the use of food and drink outside of combat based on Nerve.
			if DFNerveSystem.Get().GetHasNausea() && (Deref(itemData).GameItemData.HasTag(n"Food") || Deref(itemData).GameItemData.HasTag(n"Drink")) {
				canUse = false;
			} else {
				canUse = true;
			}
		}
		// Edit End
    }
	return canUse;
}

// Allow certain types of consumables (Black Lace, etc) to be used in combat.
// Fix a base game bug that prevented Inhalers and Injectors from being swapped between in the Backpack Inventory (but not
// in Quick Access or the Radial Menu).
// Disallow the use of food and drink outside of combat based on Nerve.
@replaceMethod(InventoryGPRestrictionHelper)
public final static func CanUse(itemData: wref<UIInventoryItem>, playerPuppet: wref<PlayerPuppet>) -> Bool {
	let bb: ref<IBlackboard>;
	let canUse: Bool = InventoryGPRestrictionHelper.CanInteractByEquipmentArea(itemData, playerPuppet);
	if Equals(itemData.GetItemType(), gamedataItemType.Prt_Program) {
		bb = GameInstance.GetBlackboardSystem(GetGameInstance()).GetLocalInstanced(playerPuppet.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
		if bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 {
			canUse = false;
		}
	} else if Equals(itemData.GetItemRecord().ItemCategory().Type(), gamedataItemCategory.Consumable) {
		bb = GameInstance.GetBlackboardSystem(GetGameInstance()).GetLocalInstanced(playerPuppet.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
		if bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == 1 {
			// Allow the use of inhalers, injectors, and any items with Combat Use Allowed tag while in combat.
			let itemType: gamedataItemType = itemData.m_realItemData.GetItemType();
			if Equals(itemType, gamedataItemType.Con_Inhaler) || Equals(itemType, gamedataItemType.Con_Injector) {
				canUse = true;
			} else if itemData.m_realItemData.HasTag(n"DarkFutureConsumableCombatUseAllowed") {
				canUse = true;
			} else {
				canUse = false;
			}
      	} else {
			// Disallow the use of food and drink outside of combat based on Nerve.
			if DFNerveSystem.Get().GetHasNausea() && (itemData.m_realItemData.HasTag(n"Food") || itemData.m_realItemData.HasTag(n"Drink")) {
				canUse = false;
			} else {
				canUse = true;
			}
		}
		// Edit End
    }
	return canUse;
}

//	ConsumeAction - If the player's Nerve is too low, disallow consuming food and drink when activated
//	in the world.
//
@wrapMethod(ConsumeAction)
public func IsVisible(const context: script_ref<GetActionsContext>, objectActionsCallbackController: wref<gameObjectActionsCallbackController>) -> Bool {
	let NerveSystem: wref<DFNerveSystem> = DFNerveSystem.Get();

	if NerveSystem.GetHasNausea() && (this.GetItemData().HasTag(n"Food") || this.GetItemData().HasTag(n"Drink")) {
		return false;
	}

	return wrappedMethod(context, objectActionsCallbackController);
}

//	ItemActionsHelper - The main "item consumed" event hook for Dark Future.
//
@wrapMethod(ItemActionsHelper)
public final static func ProcessItemAction(gi: GameInstance, executor: wref<GameObject>, itemData: wref<gameItemData>, actionID: TweakDBID, fromInventory: Bool) -> Bool {
	let actionUsed: Bool = wrappedMethod(gi, executor, itemData, actionID, fromInventory);

	if actionUsed {
		let actionType: CName = TweakDBInterface.GetObjectActionRecord(actionID).ActionName();
		if Equals(actionType, n"Consume") || Equals(actionType, n"Eat") || Equals(actionType, n"Drink") {
			DFMainSystem.Get().DispatchItemConsumedEvent(TweakDBInterface.GetItemRecord(itemData.GetID().GetTDBID()));
		}
	}

	return actionUsed;
}

//	ItemActionsHelper - The main "item consumed" event hook for Dark Future.
//
@wrapMethod(ItemActionsHelper)
public final static func ProcessItemAction(gi: GameInstance, executor: wref<GameObject>, itemData: wref<gameItemData>, actionID: TweakDBID, fromInventory: Bool, quantity: Int32) -> Bool {
	let actionUsed: Bool = wrappedMethod(gi, executor, itemData, actionID, fromInventory, quantity);

	if actionUsed {
		let actionType: CName = TweakDBInterface.GetObjectActionRecord(actionID).ActionName();
		if Equals(actionType, n"Consume") || Equals(actionType, n"Eat") || Equals(actionType, n"Drink") {
			DFMainSystem.Get().DispatchItemConsumedEvent(TweakDBInterface.GetItemRecord(itemData.GetID().GetTDBID()));
		}
	}

	return actionUsed;
}

public final static func GetConsumableNeedsData(itemRecord: wref<Item_Record>) -> DFNeedsDatum {
	// Consumable Need Restoration Values
	let Settings: ref<DFSettings> = DFSettings.Get();

	let HydrationTier1: Float = Settings.hydrationTier1;  // Soda, convenience drinks
	let HydrationTier2: Float = Settings.hydrationTier2;  // Water
	let HydrationTier3: Float = Settings.hydrationTier3;  // Large water

	let NutritionTier1: Float = Settings.nutritionTier1;  // Small convenience snacks
	let NutritionTier2: Float = Settings.nutritionTier2;  // Protein bars, etc
	let NutritionTier3: Float = Settings.nutritionTier3;  // Meals
	let NutritionTier4: Float = Settings.nutritionTier4;  // Large Meals

	let BoosterPenaltyTier1: Float = -15.0;
	let BoosterPenaltyTier2: Float = -25.0;

	let EnergyTier1: Float = Settings.energyTier1;
	let EnergyTier2: Float = Settings.energyTier2;
	let EnergyTier3: Float = Settings.energyTier3;

	let CigarettesNerve: Float = Settings.nerveCigarettes;

	// When the Alcohol Status is applied, it restores 5 Nerve in order
	// for [Drink] dialogue choices to restore Nerve outside of consuming
	// items. (It may take several "sips" when drinking in a cinematic
	// to obtain the Alcohol effect application, which is outside the control
	// of this mod. Therefore, we only "count" the drink and grant Nerve once
	// you've gotten the Alcohol status effect.) These Nerve changes occur in
	// addition to the +5 change in order to reflect the effect magnitude 
	// listed on the item.
	let AlcoholNerveOnStatusEffectApply: Float = Settings.nerveAlcoholTier1;

	let AlcoholNerveTier1: Float = 0.0;  // 6
	let AlcoholNerveTier2: Float = Settings.nerveAlcoholTier2 - Settings.nerveAlcoholTier1;  // 8
	let AlcoholNerveTier3: Float = Settings.nerveAlcoholTier3 - Settings.nerveAlcoholTier1; // 10

	// Nerve Penalties are always 40% of benefit on low-quality consumables.
	let NervePenaltyDrinkTier1: Float = Cast<Float>(-1 * CeilF(Settings.hydrationTier1 * Settings.GetLowQualityConsumablePenaltyFactorAsPercentage()));
	let NervePenaltyFoodTier1: Float = Cast<Float>(-1 * CeilF(Settings.nutritionTier1 * Settings.GetLowQualityConsumablePenaltyFactorAsPercentage()));
	let NervePenaltyFoodTier2: Float = Cast<Float>(-1 * CeilF(Settings.nutritionTier2 * Settings.GetLowQualityConsumablePenaltyFactorAsPercentage()));
	let NervePenaltyFoodTier3: Float = Cast<Float>(-1 * CeilF(Settings.nutritionTier3 * Settings.GetLowQualityConsumablePenaltyFactorAsPercentage()));

	let NervePenaltyDeathTest: Float = -95.0;

	let DrugNerveAmount: Float = 30.0;
	let DrugEnergyPenaltyLow: Float = -15.0;
	let DrugEnergyPenaltyMed: Float = -50.0;

	let LowQualityConsumableNerveLossLimit: Float = Settings.nerveLowQualityConsumablePenaltyLimit;

	let consumableBasicNeedsData: DFNeedsDatum;

	// Default values
	consumableBasicNeedsData.hydration.ceiling = 100.0;
	consumableBasicNeedsData.hydration.floor = 0.0;

	consumableBasicNeedsData.nutrition.ceiling = 100.0;
	consumableBasicNeedsData.nutrition.floor = 0.0;

	consumableBasicNeedsData.energy.ceiling = 100.0;
	consumableBasicNeedsData.energy.floor = 0.0;

	consumableBasicNeedsData.nerve.ceiling = 100.0;
	consumableBasicNeedsData.nerve.floor = 0.0;
	
	// Hydration
	if itemRecord.TagsContains(n"DarkFutureConsumableHydration") {
		if itemRecord.TagsContains(n"DarkFutureConsumableHydrationTier1") {
			consumableBasicNeedsData.hydration.value = HydrationTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableHydrationTier2") {
			consumableBasicNeedsData.hydration.value = HydrationTier2;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableHydrationTier3") {
			consumableBasicNeedsData.hydration.value = HydrationTier3;
		}
	}

	// Nutrition
	if itemRecord.TagsContains(n"DarkFutureConsumableNutrition") {
		if itemRecord.TagsContains(n"DarkFutureConsumableNutritionTier1") {
			consumableBasicNeedsData.nutrition.value = NutritionTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNutritionTier2") {
			consumableBasicNeedsData.nutrition.value = NutritionTier2;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNutritionTier3") {
			consumableBasicNeedsData.nutrition.value = NutritionTier3;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNutritionTier4") {
			consumableBasicNeedsData.nutrition.value = NutritionTier4;
		}
	}

	if itemRecord.TagsContains(n"DarkFutureConsumableBoosterNutritionCost") {
		if itemRecord.TagsContains(n"DarkFutureConsumableBoosterNutritionCostTier1") {
			consumableBasicNeedsData.nutrition.value = BoosterPenaltyTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableBoosterNutritionCostTier2") {
			consumableBasicNeedsData.nutrition.value = BoosterPenaltyTier2;
		}
	}

	// Energy
	if itemRecord.TagsContains(n"DarkFutureConsumableEnergy") {
		if itemRecord.TagsContains(n"DarkFutureConsumableEnergyTier1") {
			consumableBasicNeedsData.energy.value = EnergyTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergyTier2") {
			consumableBasicNeedsData.energy.value = EnergyTier2;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableEnergyTier3") {
			consumableBasicNeedsData.energy.value = EnergyTier3;
		}
	}

	// Nerve
	if itemRecord.TagsContains(n"DarkFutureConsumableNerve") {
		if itemRecord.TagsContains(n"DarkFutureConsumableCigarettesNerve") {
			consumableBasicNeedsData.nerve.value = CigarettesNerve;
		
		} else if itemRecord.TagsContains(n"DarkFutureConsumableAlcoholNerveTier1") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier1;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableAlcoholNerveTier2") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier2;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableAlcoholNerveTier3") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier3;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		}
	}

	// Nerve Penalty from lower-quality consumables
	if itemRecord.TagsContains(n"DarkFutureConsumableNervePenaltyOnConsume") {
		if itemRecord.TagsContains(n"DarkFutureConsumableNervePenaltyDrinkOnConsumeTier1") {
			consumableBasicNeedsData.nerve.value = NervePenaltyDrinkTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNervePenaltyFoodOnConsumeTier1") {
			consumableBasicNeedsData.nerve.value = NervePenaltyFoodTier1;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNervePenaltyFoodOnConsumeTier2") {
			consumableBasicNeedsData.nerve.value = NervePenaltyFoodTier2;
		} else if itemRecord.TagsContains(n"DarkFutureConsumableNervePenaltyFoodOnConsumeTier3") {
			consumableBasicNeedsData.nerve.value = NervePenaltyFoodTier3;
		}
		consumableBasicNeedsData.nerve.floor = LowQualityConsumableNerveLossLimit;
	}

	// Nerve Restore Drug
	if itemRecord.TagsContains(n"DarkFutureConsumableNerveRestoreDrug") {
		consumableBasicNeedsData.nerve.value = DrugNerveAmount;
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyMed;
	}

	// Addiction Treatment Drug
	if itemRecord.TagsContains(n"DarkFutureConsumableAddictionTreatmentDrug") {
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyMed;
	}

	// Sedation Drug
	if itemRecord.TagsContains(n"DarkFutureConsumableSedationDrug") {
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyLow;
	}

	// Nerve Death Test Item
	if itemRecord.TagsContains(n"DarkFutureConsumableNerveDeathTest") {
		consumableBasicNeedsData.nerve.value = NervePenaltyDeathTest;
	}

	return consumableBasicNeedsData;
}

private final static func GetFoodRecordFromIdleAnywhereFactValue(value: Int32) -> TweakDBID {
	switch value {
		case 0:
			return t"Items.LowQualityFood";
			break;
		case 1:
			return t"Items.LowQualityFood1";
			break;
		case 2:
			return t"Items.LowQualityFood2";
			break;
		case 3:
			return t"Items.LowQualityFood3";
			break;
		case 4:
			return t"Items.LowQualityFood4";
			break;
		case 5:
			return t"Items.LowQualityFood5";
			break;
		//case 6: (Mr. Whitey)
		//    return t"Items.LowQualityFood6";
		//    break;
		case 7:
			return t"Items.LowQualityFood7";
			break;
		case 8:
			return t"Items.LowQualityFood8";
			break;
		case 9:
			return t"Items.LowQualityFood9";
			break;
		case 10:
			return t"Items.LowQualityFood10";
			break;
		case 11:
			return t"Items.LowQualityFood11";
			break;
		case 12:
			return t"Items.LowQualityFood12";
			break;
		case 13:
			return t"Items.LowQualityFood13";
			break;
		case 14:
			return t"Items.LowQualityFood14";
			break;
		case 15:
			return t"Items.LowQualityFood15";
			break;
		case 16:
			return t"Items.LowQualityFood16";
			break;
		case 17:
			return t"Items.LowQualityFood17";
			break;
		case 18:
			return t"Items.LowQualityFood18";
			break;
		case 19:
			return t"Items.LowQualityFood19";
			break;
		case 20:
			return t"Items.LowQualityFood20";
			break;
		case 21:
			return t"Items.LowQualityFood21";
			break;
		case 22:
			return t"Items.LowQualityFood22";
			break;
		case 23:
			return t"Items.LowQualityFood23";
			break;
		case 24:
			return t"Items.LowQualityFood24";
			break;
		case 25:
			return t"Items.LowQualityFood25";
			break;
		case 26:
			return t"Items.LowQualityFood26";
			break;
		case 27:
			return t"Items.LowQualityFood27";
			break;
		case 28:
			return t"Items.LowQualityFood28";
			break;
		case 29:
			return t"Items.MediumQualityFood";
			break;
		case 30:
			return t"Items.MediumQualityFood1";
			break;
		case 31:
			return t"Items.MediumQualityFood2";
			break;
		case 32:
			return t"Items.MediumQualityFood3";
			break;
		case 33:
			return t"Items.MediumQualityFood4";
			break;
		case 34:
			return t"Items.MediumQualityFood5";
			break;
		case 35:
			return t"Items.MediumQualityFood6";
			break;
		case 36:
			return t"Items.MediumQualityFood7";
			break;
		case 37:
			return t"Items.MediumQualityFood8";
			break;
		case 38:
			return t"Items.MediumQualityFood9";
			break;
		case 39:
			return t"Items.MediumQualityFood10";
			break;
		//case 40: (Mr. Whitey)
		//    return t"Items.MediumQualityFood11";
		//    break;
		case 41:
			return t"Items.MediumQualityFood12";
			break;
		case 42:
			return t"Items.MediumQualityFood13";
			break;
		//case 43: (Mr. Whitey)
		//    return t"Items.MediumQualityFood14";
		//    break;
		//case 44: (Mr. Whitey)
		//    return t"Items.MediumQualityFood15";
		//    break;
		case 45:
			return t"Items.MediumQualityFood16";
			break;
		case 46:
			return t"Items.MediumQualityFood17";
			break;
		case 47:
			return t"Items.MediumQualityFood18";
			break;
		case 48:
			return t"Items.MediumQualityFood19";
			break;
		case 49:
			return t"Items.MediumQualityFood20";
			break;
		case 50:
			return t"Items.GoodQualityFood";
			break;
		case 51:
			return t"Items.GoodQualityFood1";
			break;
		case 52:
			return t"Items.GoodQualityFood2";
			break;
		case 53:
			return t"Items.GoodQualityFood3";
			break;
		case 54:
			return t"Items.GoodQualityFood4";
			break;
		case 55:
			return t"Items.GoodQualityFood5";
			break;
		case 56:
			return t"Items.GoodQualityFood6";
			break;
		case 57:
			return t"Items.GoodQualityFood7";
			break;
		case 58:
			return t"Items.GoodQualityFood8";
			break;
		case 59:
			return t"Items.GoodQualityFood9";
			break;
		case 60:
			return t"Items.GoodQualityFood10";
			break;
		case 61:
			return t"Items.GoodQualityFood11";
			break;
		case 62:
			return t"Items.GoodQualityFood12";
			break;
		case 63:
			return t"Items.GoodQualityFood13";
			break;
		case 64:
			return t"Items.NomadsFood1";
			break;
		case 65:
			return t"Items.NomadsFood2";
			break;
		case 66:
			return t"Items.HawtDawgKabanos";
			break;
		case 67:
			return t"Items.HawtDawgClassic";
			break;
		case 68:
			return t"Items.HawtDawgCheese";
			break;
		case 69:
			return t"Items.HawtDawgChilli";
			break;
		default:
			return t"";
			break;
	}
}

private final static func GetDrinkRecordFromIdleAnywhereFactValue(value: Int32) -> TweakDBID {
	switch value {
		case 0:
			return t"Items.LowQualityDrink";
			break;
		case 1:
			return t"Items.LowQualityDrink1";
			break;
		case 2:
			return t"Items.LowQualityDrink2";
			break;
		case 3:
			return t"Items.LowQualityDrink3";
			break;
		case 4:
			return t"Items.LowQualityDrink4";
			break;
		case 5:
			return t"Items.LowQualityDrink5";
			break;
		case 6:
			return t"Items.LowQualityDrink6";
			break;
		case 7:
			return t"Items.LowQualityDrink7";
			break;
		case 8:
			return t"Items.LowQualityDrink8";
			break;
		case 9:
			return t"Items.LowQualityDrink9";
			break;
		case 10:
			return t"Items.LowQualityDrink10";
			break;
		case 11:
			return t"Items.LowQualityDrink11";
			break;
		case 12:
			return t"Items.LowQualityDrink12";
			break;
		case 13:
			return t"Items.LowQualityDrink13";
			break;
		case 14:
			return t"Items.MediumQualityDrink";
			break;
		case 15:
			return t"Items.MediumQualityDrink1";
			break;
		case 16:
			return t"Items.MediumQualityDrink2";
			break;
		case 17:
			return t"Items.MediumQualityDrink3";
			break;
		case 18:
			return t"Items.MediumQualityDrink4";
			break;
		case 19:
			return t"Items.MediumQualityDrink5";
			break;
		case 20:
			return t"Items.MediumQualityDrink6";
			break;
		case 21:
			return t"Items.MediumQualityDrink7";
			break;
		case 22:
			return t"Items.MediumQualityDrink8";
			break;
		case 23:
			return t"Items.MediumQualityDrink9";
			break;
		case 24:
			return t"Items.MediumQualityDrink10";
			break;
		case 25:
			return t"Items.MediumQualityDrink11";
			break;
		case 26:
			return t"Items.MediumQualityDrink12";
			break;
		case 27:
			return t"Items.MediumQualityDrink13";
			break;
		case 28:
			return t"Items.MediumQualityDrink14";
			break;
		case 29:
			return t"Items.GoodQualityDrink";
			break;
		case 30:
			return t"Items.GoodQualityDrink1";
			break;
		case 31:
			return t"Items.GoodQualityDrink2";
			break;
		case 32:
			return t"Items.GoodQualityDrink3";
			break;
		case 33:
			return t"Items.GoodQualityDrink4";
			break;
		case 34:
			return t"Items.GoodQualityDrink5";
			break;
		case 35:
			return t"Items.GoodQualityDrink6";
			break;
		case 36:
			return t"Items.GoodQualityDrink7";
			break;
		case 37:
			return t"Items.GoodQualityDrink8";
			break;
		case 38:
			return t"Items.GoodQualityDrink9";
			break;
		case 39:
			return t"Items.GoodQualityDrink10";
			break;
		case 40:
			return t"Items.GoodQualityDrink11";
			break;
		case 41:
			return t"Items.NomadsDrink1";
			break;
		case 42:
			return t"Items.NomadsDrink2";
			break;
		default:
			return t"";
			break;
	}
}

private final static func GetAlcoholRecordFromIdleAnywhereFactValue(value: Int32) -> TweakDBID {
	switch value {
		case 0:
			return t"Items.LowQualityAlcohol";
			break;
		case 1:
			return t"Items.LowQualityAlcohol1";
			break;
		case 2:
			return t"Items.LowQualityAlcohol2";
			break;
		case 3:
			return t"Items.LowQualityAlcohol3";
			break;
		case 4:
			return t"Items.LowQualityAlcohol4";
			break;
		case 5:
			return t"Items.LowQualityAlcohol5";
			break;
		case 6:
			return t"Items.LowQualityAlcohol6";
			break;
		case 7:
			return t"Items.LowQualityAlcohol7";
			break;
		case 8:
			return t"Items.LowQualityAlcohol8";
			break;
		case 9:
			return t"Items.LowQualityAlcohol9";
			break;
		case 10:
			return t"Items.MediumQualityAlcohol";
			break;
		case 11:
			return t"Items.MediumQualityAlcohol1";
			break;
		case 12:
			return t"Items.MediumQualityAlcohol2";
			break;
		case 13:
			return t"Items.MediumQualityAlcohol3";
			break;
		case 14:
			return t"Items.MediumQualityAlcohol4";
			break;
		case 15:
			return t"Items.MediumQualityAlcohol5";
			break;
		case 16:
			return t"Items.MediumQualityAlcohol6";
			break;
		case 17:
			return t"Items.MediumQualityAlcohol7";
			break;
		case 18:
			return t"Items.GoodQualityAlcohol";
			break;
		case 19:
			return t"Items.GoodQualityAlcohol1";
			break;
		case 20:
			return t"Items.GoodQualityAlcohol2";
			break;
		case 21:
			return t"Items.GoodQualityAlcohol3";
			break;
		case 22:
			return t"Items.GoodQualityAlcohol4";
			break;
		case 23:
			return t"Items.GoodQualityAlcohol5";
			break;
		case 24:
			return t"Items.GoodQualityAlcohol6";
			break;
		case 25:
			return t"Items.TopQualityAlcohol";
			break;
		case 26:
			return t"Items.TopQualityAlcohol1";
			break;
		case 27:
			return t"Items.TopQualityAlcohol2";
			break;
		case 28:
			return t"Items.TopQualityAlcohol3";
			break;
		case 29:
			return t"Items.TopQualityAlcohol4";
			break;
		case 30:
			return t"Items.TopQualityAlcohol5";
			break;
		case 31:
			return t"Items.TopQualityAlcohol6";
			break;
		case 32:
			return t"Items.TopQualityAlcohol7";
			break;
		case 33:
			return t"Items.TopQualityAlcohol8";
			break;
		case 34:
			return t"Items.TopQualityAlcohol9";
			break;
		case 35:
			return t"Items.TopQualityAlcohol10";
			break;
		case 36:
			return t"Items.ExquisiteQualityAlcohol";
			break;
		case 37:
			return t"Items.NomadsAlcohol1";
			break;
		case 38:
			return t"Items.NomadsAlcohol2";
			break;
		default:
			return t"";
			break;
	}
}
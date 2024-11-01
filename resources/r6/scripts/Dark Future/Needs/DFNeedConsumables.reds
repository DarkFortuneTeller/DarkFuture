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
			DFMainSystem.Get().DispatchItemConsumedEvent(itemData);
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
			DFMainSystem.Get().DispatchItemConsumedEvent(itemData);
		}
	}

	return actionUsed;
}

public final static func GetConsumableNeedsData(itemData: wref<gameItemData>) -> DFNeedsDatum {
	// Consumable Need Restoration Values
	let HydrationTier1: Float = 5.0;
	let HydrationTier2: Float = 10.0;
	let HydrationTier3: Float = 15.0;

	let NutritionTier1: Float = 3.0;
	let NutritionTier2: Float = 5.0;
	let NutritionTier3: Float = 8.0;
	let NutritionTier4: Float = 10.0;
	let NutritionTier5: Float = 12.0;
	let NutritionTier6: Float = 15.0;
	let NutritionTier7: Float = 18.0;

	let BoosterPenaltyTier1: Float = -15.0;
	let BoosterPenaltyTier2: Float = -25.0;

	let EnergyTier1: Float = 15.0;
	let EnergyTier2: Float = 25.0;
	let EnergyTier3: Float = 35.0;
	let EnergyTier4: Float = 40.0;

	let CigarettesNerve: Float = 15.0;

	// When the Alcohol Status is applied, it restores 5 Nerve in order
	// for [Drink] dialogue choices to restore Nerve outside of consuming
	// items. (It may take several "sips" when drinking in a cinematic
	// to obtain the Alcohol effect application, which is outside the control
	// of this mod. Therefore, we only "count" the drink and grant Nerve once
	// you've gotten the Alcohol status effect.) These Nerve changes occur in
	// addition to the +5 change in order to reflect the effect magnitude 
	// listed on the item.
	let AlcoholNerveOnStatusEffectApply: Float = 5.0;

	let AlcoholNerveTier1: Float = 0.0;  // 5
	let AlcoholNerveTier2: Float = 1.0;  // 6
	let AlcoholNerveTier3: Float = 3.0;  // 8
	let AlcoholNerveTier4: Float = 5.0; // 10

	let NervePenaltyTier1: Float = -1.0;
	let NervePenaltyTier2: Float = -2.0;
	let NervePenaltyTier3: Float = -3.0;

	let DrugNerveAmount: Float = 30.0;
	let DrugEnergyPenaltyLow: Float = -15.0;
	let DrugEnergyPenaltyMed: Float = -50.0;

	let LowQualityConsumableNerveLossLimit: Float = 70.0;

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
	if itemData.HasTag(n"DarkFutureConsumableHydration") {
		if itemData.HasTag(n"DarkFutureConsumableHydrationTier1") {
			consumableBasicNeedsData.hydration.value = HydrationTier1;
		} else if itemData.HasTag(n"DarkFutureConsumableHydrationTier2") {
			consumableBasicNeedsData.hydration.value = HydrationTier2;
		} else if itemData.HasTag(n"DarkFutureConsumableHydrationTier3") {
			consumableBasicNeedsData.hydration.value = HydrationTier3;
		}
	}

	// Nutrition
	if itemData.HasTag(n"DarkFutureConsumableNutrition") {
		if itemData.HasTag(n"DarkFutureConsumableNutritionTier1") {
			consumableBasicNeedsData.nutrition.value = NutritionTier1;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier2") {
			consumableBasicNeedsData.nutrition.value = NutritionTier2;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier3") {
			consumableBasicNeedsData.nutrition.value = NutritionTier3;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier4") {
			consumableBasicNeedsData.nutrition.value = NutritionTier4;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier5") {
			consumableBasicNeedsData.nutrition.value = NutritionTier5;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier6") {
			consumableBasicNeedsData.nutrition.value = NutritionTier6;
		} else if itemData.HasTag(n"DarkFutureConsumableNutritionTier7") {
			consumableBasicNeedsData.nutrition.value = NutritionTier7;
		}
	}

	if itemData.HasTag(n"DarkFutureConsumableBoosterNutritionCost") {
		if itemData.HasTag(n"DarkFutureConsumableBoosterNutritionCostTier1") {
			consumableBasicNeedsData.nutrition.value = BoosterPenaltyTier1;
		} else if itemData.HasTag(n"DarkFutureConsumableBoosterNutritionCostTier2") {
			consumableBasicNeedsData.nutrition.value = BoosterPenaltyTier2;
		}
	}

	// Energy
	if itemData.HasTag(n"DarkFutureConsumableEnergy") {
		if itemData.HasTag(n"DarkFutureConsumableEnergyTier1") {
			consumableBasicNeedsData.energy.value = EnergyTier1;
		} else if itemData.HasTag(n"DarkFutureConsumableEnergyTier2") {
			consumableBasicNeedsData.energy.value = EnergyTier2;
		} else if itemData.HasTag(n"DarkFutureConsumableEnergyTier3") {
			consumableBasicNeedsData.energy.value = EnergyTier3;
		} else if itemData.HasTag(n"DarkFutureConsumableEnergyTier4") {
			consumableBasicNeedsData.energy.value = EnergyTier4;
		}
	}

	// Nerve
	if itemData.HasTag(n"DarkFutureConsumableNerve") {
		if itemData.HasTag(n"DarkFutureConsumableCigarettesNerve") {
			consumableBasicNeedsData.nerve.value = CigarettesNerve;
		
		} else if itemData.HasTag(n"DarkFutureConsumableAlcoholNerveTier1") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier1;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		} else if itemData.HasTag(n"DarkFutureConsumableAlcoholNerveTier2") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier2;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		} else if itemData.HasTag(n"DarkFutureConsumableAlcoholNerveTier3") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier3;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		} else if itemData.HasTag(n"DarkFutureConsumableAlcoholNerveTier4") {
			consumableBasicNeedsData.nerve.value = AlcoholNerveTier4;
			consumableBasicNeedsData.nerve.valueOnStatusEffectApply = AlcoholNerveOnStatusEffectApply;
		}
	}

	// Nerve Penalty from lower-quality consumables
	if itemData.HasTag(n"DarkFutureConsumableNervePenaltyOnConsume") {
		if itemData.HasTag(n"DarkFutureConsumableNervePenaltyOnConsumeTier1") {
			consumableBasicNeedsData.nerve.value = NervePenaltyTier1;
		} else if itemData.HasTag(n"DarkFutureConsumableNervePenaltyOnConsumeTier2") {
			consumableBasicNeedsData.nerve.value = NervePenaltyTier2;
		} else if itemData.HasTag(n"DarkFutureConsumableNervePenaltyOnConsumeTier3") {
			consumableBasicNeedsData.nerve.value = NervePenaltyTier3;
		}
		consumableBasicNeedsData.nerve.floor = LowQualityConsumableNerveLossLimit;
	}

	// Nerve Restore Drug
	if itemData.HasTag(n"DarkFutureConsumableNerveRestoreDrug") {
		consumableBasicNeedsData.nerve.value = DrugNerveAmount;
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyMed;
	}

	// Addiction Treatment Drug
	if itemData.HasTag(n"DarkFutureConsumableAddictionTreatmentDrug") {
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyMed;
	}

	// Sedation Drug
	if itemData.HasTag(n"DarkFutureConsumableSedationDrug") {
		consumableBasicNeedsData.energy.value = DrugEnergyPenaltyLow;
	}

	return consumableBasicNeedsData;
}

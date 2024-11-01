// -----------------------------------------------------------------------------
// DFBaseGameUIOverrides
// -----------------------------------------------------------------------------
//
// - A set of general UI-related base game method overrides.
//

import DarkFuture.Settings.DFSettings
import DarkFuture.System.*
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}

// ===================================================
//  INVENTORY ITEMS
// ===================================================

//  UIInventoryItemsManager - Prevent the storage of consumables in stash.
//
@wrapMethod(UIInventoryItemsManager)
public final static func GetStashBlacklistedTags() -> array<CName> {
	let settings: ref<DFSettings> = DFSettings.Get();
	let tagList: array<CName> = wrappedMethod();
	if settings.mainSystemEnabled && settings.noConsumablesInStash {
		ArrayPush(tagList, n"Consumable");
	}
	return tagList;
}

//  ItemTooltipHeaderController - Show the addictive item tooltip header.
//
@addMethod(ItemTooltipHeaderController)
public final func TryToShowAddictiveConsumableHeader(itemData: wref<gameItemData>) -> Void {
	if itemData.HasTag(n"DarkFutureConsumableAddictive") {
		let addictionLabel: String = "";
		
		if IsSystemEnabledAndRunning(DFNicotineAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveNicotine") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderNicotine");
		}

		if IsSystemEnabledAndRunning(DFAlcoholAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveAlcohol") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderAlcohol");
		}

		if IsSystemEnabledAndRunning(DFNarcoticAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveNarcoticWeak") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderNarcoticWeak");
		}

		if IsSystemEnabledAndRunning(DFNarcoticAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveNarcoticStrong") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderNarcoticStrong");
		}

		if NotEquals(addictionLabel, "") {
			inkWidgetRef.SetVisible(this.m_itemRarityText, true);
    		inkWidgetRef.SetState(this.m_itemRarityText, n"Legendary");
    		inkTextRef.SetText(this.m_itemRarityText, addictionLabel);
		}
	}
}

// ItemTooltipHeaderController - Displays the "Combat Consumable" headers.
//
@addMethod(ItemTooltipHeaderController)
public final func TryToShowCombatConsumableHeader(itemData: wref<gameItemData>) -> Void {
	if DFSettings.Get().mainSystemEnabled {
		let itemType: gamedataItemType = itemData.GetItemType();
		if Equals(itemType, gamedataItemType.Con_Inhaler) {
			inkTextRef.SetText(this.m_itemTypeText, GetLocalizedTextByKey(n"DarkFutureConsumableUICombatInhalerLabel"));
		} else if Equals(itemType, gamedataItemType.Con_Injector) {
			inkTextRef.SetText(this.m_itemTypeText, GetLocalizedTextByKey(n"DarkFutureConsumableUICombatInjectorLabel"));
		} else if (Equals(itemType, gamedataItemType.Con_LongLasting) || Equals(itemType, gamedataItemType.Con_Edible)) && itemData.HasTag(n"DarkFutureConsumableCombatUseAllowed") {
			inkTextRef.SetText(this.m_itemTypeText, GetLocalizedTextByKey(n"DarkFutureConsumableUICombatConsumableLabel"));
		}
	}
}

// ItemTooltipHeaderController - Displays the "Addictive" and "Combat Consumable" headers in the Backpack Inventory
//
@wrapMethod(ItemTooltipHeaderController)
public func NEW_Update(data: wref<UIInventoryItem>) -> Void {
	wrappedMethod(data);

	let realItemData: wref<gameItemData> = data.GetRealItemData();
	if !UIItemsHelper.ShouldDisplayTier(data.GetItemType()) || realItemData.HasTag(n"DarkFutureConsumableOverrideTierWithAddictionHeader") {
		// Check to see if we should display an Addiction Warning instead
		this.TryToShowAddictiveConsumableHeader(realItemData);
	}

	this.TryToShowCombatConsumableHeader(realItemData);
}

// ItemTooltipHeaderController - Displays the "Combat Consumable" headers in the Radial Wheel and Inventory Quick Access Menus
//
@wrapMethod(ItemTooltipHeaderController)
public func Update(data: ref<MinimalItemTooltipData>) -> Void {
    wrappedMethod(data);

	this.TryToShowCombatConsumableHeader(data.itemData);
}

// ItemTooltipBottomModule - Update the weight precision for consumables.
//
@addMethod(ItemTooltipBottomModule)
public final func TryToShowNewItemWeights(itemData: wref<gameItemData>) -> Void {
	let isConsumable: Bool = itemData.HasTag(n"Consumable");

	if isConsumable {
		let itemWeight: Float = RPGManager.GetItemWeight(itemData);
		inkTextRef.SetText(this.m_weightText, s"\(FloatToStringPrec(itemWeight, 1))");
	}
}

// ItemTooltipBottomModule - Update the weight precision for consumables.
//
@wrapMethod(ItemTooltipBottomModule)
public final func NEW_Update(data: wref<UIInventoryItem>, player: wref<PlayerPuppet>, m_overridePrice: Int32) -> Void {
	wrappedMethod(data, player, m_overridePrice);
	if DFSettings.Get().mainSystemEnabled {
		this.TryToShowNewItemWeights(data.GetItemData());
	}
}

// ItemQuantityPickerController - Update the weight precision of consumables when dropping.
//
@replaceMethod(ItemQuantityPickerController)
protected final func UpdateWeight() -> Void {
	let shouldUpdateWeight: Bool = DFSettings.Get().mainSystemEnabled;
	let itemData: ref<gameItemData>;
	if IsDefined(this.m_inventoryItem) {
		itemData = this.m_inventoryItem.GetItemData();
	} else {
		itemData = InventoryItemData.GetGameItemData(this.m_gameData);
	}
	
	let weight: Float = RPGManager.GetItemWeight(itemData) * Cast<Float>(this.m_choosenQuantity);
	let isConsumable: Bool = itemData.HasTag(n"Consumable");

	if shouldUpdateWeight && isConsumable {
		inkTextRef.SetText(this.m_weightText, FloatToStringPrec(weight, 1));
	} else {
		inkTextRef.SetText(this.m_weightText, FloatToStringPrec(weight, 0));
	}
}

// ItemCategoryFliter
//		Remove Healing Items from Consumables.
//		Cluster all Charged Consumables under the same category.
//
@wrapMethod(ItemCategoryFliter)
public final static func IsOfCategoryType(filter: ItemFilterCategory, data: wref<gameItemData>) -> Bool {
	let settings: ref<DFSettings> = DFSettings.Get();
	if IsDefined(data) && settings.mainSystemEnabled && settings.newInventoryFilters {
		if Equals(filter, ItemFilterCategory.Consumables) {
			return data.HasTag(n"Consumable") && !data.HasTag(n"ChargedConsumable");
		} else if Equals(filter, ItemFilterCategory.Grenades) {
			return data.HasTag(n"ChargedConsumable");
		};
	};
	return wrappedMethod(filter, data);
}

//	CraftingDataView
//		Remove Healing Items from Consumables.
//		Cluster all Charged Consumables under the same category.
//
@wrapMethod(CraftingDataView)
public func FilterItem(item: ref<IScriptable>) -> Bool {
	let settings: ref<DFSettings> = DFSettings.Get();
	if settings.mainSystemEnabled && settings.newInventoryFilters {
		let itemRecord: ref<Item_Record>;
		let itemData: ref<ItemCraftingData> = item as ItemCraftingData;
		let recipeData: ref<RecipeData> = item as RecipeData;

		if IsDefined(itemData) {
			itemRecord = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(InventoryItemData.GetID(itemData.inventoryItem)));
		} else {
			if IsDefined(recipeData) {
				itemRecord = recipeData.id;
			};
		};

		if Equals(this.m_itemFilterType, ItemFilterCategory.Consumables) {
			return itemRecord.TagsContains(n"Consumable") && !itemRecord.TagsContains(n"ChargedConsumable");
		} else if Equals(this.m_itemFilterType, ItemFilterCategory.Grenades) {
			return itemRecord.TagsContains(n"ChargedConsumable");
		};
	}

	return wrappedMethod(item);
}

// 	ItemFilterCategories - Set new Filter Category tooltips.
//		Note: the CName values for these new fields MUST start with UI-Filter-* in order to resolve correctly.
//
@wrapMethod(ItemFilterCategories)
public final static func GetLabelKey(filterType: ItemFilterCategory) -> CName {
	let settings: ref<DFSettings> = DFSettings.Get();
	if settings.mainSystemEnabled && settings.newInventoryFilters {
		if Equals(filterType, ItemFilterCategory.Grenades) {
			return n"UI-Filter-DarkFutureChargedConsumables";
		}
	}

	return wrappedMethod(filterType);
}

// ===================================================
// STATUS EFFECTS
// ===================================================

// buffListGameController - Selectively hide certain status icons based on settings.
//
@wrapMethod(buffListGameController)
protected cb func OnBuffDataChanged(value: Variant) -> Bool {
	if !DFSettings.Get().showAllStatusIcons {
		let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    	wrappedMethod(filteredBuffDataList);
	} else {
		wrappedMethod(value);
	}
}

// buffListGameController - Selectively hide certain status icons based on settings.
//
@wrapMethod(buffListGameController)
protected cb func OnDeBuffDataChanged(value: Variant) -> Bool {
	if !DFSettings.Get().showAllStatusIcons {
    	let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    	wrappedMethod(filteredBuffDataList);
	} else {
		wrappedMethod(value);
	}
}

// buffListGameController - Selectively hide certain status icons based on settings.
//
@addMethod(buffListGameController)
private final func GetFilteredBuffList(value: Variant) -> array<BuffInfo> {
	let buffDataList: array<BuffInfo> = FromVariant<array<BuffInfo>>(value);
	let filteredBuffDataList: array<BuffInfo>;
	for buff in buffDataList {
		let buffTags: array<CName> = TweakDBInterface.GetStatusEffectRecord(buff.buffID).GameplayTags();
		if !ArrayContains(buffTags, n"DarkFutureCanHideOnBuffBar") {
			ArrayPush(filteredBuffDataList, buff);
		}
	}

	return filteredBuffDataList;
}



// inkCooldownGameController - The Status Effect Cooldown system, by default, doesn't know how to handle displaying Status Effects that
// have an infinite duration.
//
@replaceMethod(inkCooldownGameController)
public final func RequestCooldownVisualization(buffData: UIBuffInfo) -> Void {
	let i: Int32;
	// Edit Start
	// -1.00 = Infinite Duration
	let tags: array<CName> = TweakDBInterface.GetStatusEffectRecord(buffData.buffID).GameplayTags();
    if buffData.timeRemaining <= 0.00 && !ArrayContains(tags, n"DarkFutureInfiniteDurationEffect") {
		return;
	// Edit End
    };
    i = 0;
    while i < this.m_maxCooldowns {
      if Equals(this.m_cooldownPool[i].GetState(), ECooldownIndicatorState.Pooled) {
        this.m_cooldownPool[i].ActivateCooldown(buffData);
        return;
      };
      i += 1;
    };
}

// BUG FIXES
// The effect list could sometimes erroneously display incorrect stack counts
// on debuffs in the Status Effect / Quick Switch Wheel menu.
@replaceMethod(inkCooldownGameController)
protected cb func OnEffectUpdate(v: Variant) -> Bool {
    let buffs: array<BuffInfo>;
    let debuffs: array<BuffInfo>;
    let effect: UIBuffInfo;
    let effects: array<UIBuffInfo>;
    let i: Int32;
    if !this.GetRootWidget().IsVisible() {
      return false;
    };
    if Equals(this.m_mode, ECooldownGameControllerMode.COOLDOWNS) {
      this.GetBuffs(buffs);
      i = 0;
      while i < ArraySize(buffs) {
        if Equals(TweakDBInterface.GetStatusEffectRecord(buffs[i].buffID).StatusEffectType().Type(), gamedataStatusEffectType.PlayerCooldown) {
          effect.buffID = buffs[i].buffID;
          effect.timeRemaining = buffs[i].timeRemaining;
          effect.isBuff = true;
          ArrayPush(effects, effect);
        };
        i += 1;
      };
    } else {
      this.GetBuffs(buffs);
      this.GetDebuffs(debuffs);
      i = 0;
      while i < ArraySize(buffs) {
        effect.buffID = buffs[i].buffID;
        effect.timeRemaining = buffs[i].timeRemaining;
        effect.stackCount = buffs[i].stackCount;
        effect.isBuff = true;
        ArrayPush(effects, effect);
        i += 1;
      };
      i = 0;
      while i < ArraySize(debuffs) {
        effect.buffID = debuffs[i].buffID;
        effect.timeRemaining = debuffs[i].timeRemaining;
		// Edit Start
		// Incorrectly references buffs[i].stackCount in base game.
        effect.stackCount = debuffs[i].stackCount;
		// Edit End
        effect.isBuff = false;
        ArrayPush(effects, effect);
        i += 1;
      };
    };
    if ArraySize(effects) > 0 {
      inkWidgetRef.SetVisible(this.m_cooldownTitle, true);
      inkWidgetRef.SetVisible(this.m_cooldownContainer, true);
      this.ParseBuffList(effects);
    };
    if ArraySize(effects) == 0 {
      inkWidgetRef.SetVisible(this.m_cooldownTitle, false);
      inkWidgetRef.SetVisible(this.m_cooldownContainer, false);
    };
}

@addField(SingleCooldownManager)
private let m_gameplayTags: array<CName>;

@wrapMethod(SingleCooldownManager)
public final func ActivateCooldown(buffData: UIBuffInfo) -> Void {
	wrappedMethod(buffData);

	// Cache the gameplay tags, for efficiency.
	this.m_gameplayTags = TweakDBInterface.GetStatusEffectRecord(buffData.buffID).GameplayTags();
}

@wrapMethod(SingleCooldownManager)
private final func SetTimeRemaining(time: Float) -> Void {
	if time == -1.0 {
		// Don't display duration text on effects with an infinite duration.
		inkTextRef.SetText(this.m_timeRemaining, "");
		inkWidgetRef.Get(this.m_sprite).SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", AbsF(1.0));
	} else {
		wrappedMethod(time);
	}
}

@replaceMethod(SingleCooldownManager)
public final func Update(timeLeft: Float, stackCount: Uint32) -> Void {
    let fraction: Float;
    let updatedSize: Float;
	// Edit Start
	if timeLeft <= 0.01 && !ArrayContains(this.m_gameplayTags, n"DarkFutureInfiniteDurationEffect") {
	// Edit End
      updatedSize = 0.00;
      this.GetRootWidget().SetVisible(false);
    } else {
      this.GetRootWidget().SetVisible(true);
	  // Edit Start
	  if timeLeft == -1.00 {
		// Set the timeLeft fraction to 1, so that the icon is always displayed "full".
		fraction = 1.00;
	  } else {
		fraction = timeLeft / this.m_initialDuration;
	  }
	  // Edit End
      updatedSize = fraction;
    };
    inkWidgetRef.Get(this.m_sprite).SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", AbsF(updatedSize));
    this.SetTimeRemaining(timeLeft);
    this.SetStackCount(Cast<Int32>(stackCount));
    if timeLeft <= this.m_outroDuration {
      this.FillOutroAnimationStart();
    };
}
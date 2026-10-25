// -----------------------------------------------------------------------------
// DFBaseGameUIOverrides
// -----------------------------------------------------------------------------
//
// - A set of general UI-related base game method overrides.
//

import DarkFuture.Settings.{
    DFSettings,
    DFAmmoWeightSetting
}
import DarkFuture.System.*
import DarkFuture.Logging.*
import DarkFuture.UI.{
    DFHUDSystem,
    DFRadialMenuActiveEffectType
}
import DarkFuture.DelayHelper.*
import DarkFuture.Services.{
    DFNotificationService,
    DFProgressionViewData
}
import DarkFuture.Utils.{
    IsCoinFlipSuccessful,
    RandRangeInclusive
}

// ===================================================
//  INVENTORY ITEMS
// ===================================================

//  UIInventoryItemsManager - Allow ammo to be seen in the inventory.
//
@wrapMethod(UIInventoryItemsManager)
public final static func GetBlacklistedTags() -> array<CName> {
    //DFProfile();
    let filteredTags: array<CName> = wrappedMethod();
    let settings: ref<DFSettings> = DFSettings.Get();

    if Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo) {
        if ArrayContains(filteredTags, n"Ammo") {
            ArrayRemove(filteredTags, n"Ammo");
        };
    }

    return filteredTags;
}

//  UIInventoryItemsManager - Prevent the storage of consumables in stash.
//
@wrapMethod(UIInventoryItemsManager)
public final static func GetStashBlacklistedTags() -> array<CName> {
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();
    let tagList: array<CName> = wrappedMethod();
    if settings.mainSystemEnabled && settings.noConsumablesInStash {
        ArrayPush(tagList, n"Consumable");
    }
    return tagList;
}

// ItemTooltipHeaderController - Displays the "Combat Consumable" headers.
//
@addMethod(ItemTooltipHeaderController)
public final func TryToShowCombatConsumableHeader(itemData: wref<gameItemData>) -> Void {
    //DFProfile();
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

// ItemTooltipHeaderController - Displays the "Combat Consumable" headers in the Backpack Inventory
//
@wrapMethod(ItemTooltipHeaderController)
public func NEW_Update(data: wref<UIInventoryItem>) -> Void {
    //DFProfile();
    wrappedMethod(data);

    let realItemData: wref<gameItemData> = data.GetRealItemData();

    this.TryToShowCombatConsumableHeader(realItemData);
}

// ItemTooltipHeaderController - Displays the "Combat Consumable" headers in the Radial Wheel and Inventory Quick Access Menus
//
@wrapMethod(ItemTooltipHeaderController)
public func Update(data: ref<MinimalItemTooltipData>) -> Void {
    //DFProfile();
    wrappedMethod(data);

    this.TryToShowCombatConsumableHeader(data.itemData);
}

// ItemTooltipBottomModule - Show the price on ammo.
//
@wrapMethod(ItemTooltipBottomModule)
public final static func ShouldDisplayPrice(displayContext: InventoryTooltipDisplayContext, isSellable: Bool, itemData: ref<gameItemData>, itemType: gamedataItemType, opt lootItemType: LootItemType) -> Bool {
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();
    if NotEquals(displayContext, InventoryTooltipDisplayContext.Vendor) && (Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo)) && Equals(itemType, gamedataItemType.Con_Ammo) {
        return true;
    } else {
        return wrappedMethod(displayContext, isSellable, itemData, itemType, lootItemType);
    }
}

// ItemTooltipBottomModule - Update the weight precision for consumables.
//
@addMethod(ItemTooltipBottomModule)
public final func TryToShowNewItemWeights(itemData: wref<gameItemData>) -> Void {
    //DFProfile();
    let isConsumable: Bool = itemData.HasTag(n"Consumable");
    let isAmmo: Bool = itemData.HasTag(n"Ammo");
    let itemWeight: Float;

    if isConsumable {
        itemWeight = RPGManager.GetItemWeight(itemData);
        inkTextRef.SetText(this.m_weightText, s"\(FloatToStringPrec(itemWeight, 1))");
    } else if isAmmo {
        itemWeight = RPGManager.GetItemWeight(itemData);
        inkTextRef.SetText(this.m_weightText, s"\(FloatToStringPrec(itemWeight, 2))");
    }
}

// ItemTooltipBottomModule - Update the weight precision for consumables.
//
@wrapMethod(ItemTooltipBottomModule)
public final func NEW_Update(data: wref<UIInventoryItem>, player: wref<PlayerPuppet>, m_overridePrice: Int32) -> Void {
    //DFProfile();
    wrappedMethod(data, player, m_overridePrice);
    if DFSettings.Get().mainSystemEnabled {
        this.TryToShowNewItemWeights(data.GetItemData());
    }
}

// ItemQuantityPickerController - Update the weight precision of consumables and ammo when dropping.
//
@replaceMethod(ItemQuantityPickerController)
protected final func UpdateWeight() -> Void {
    //DFProfile();
    let itemData: ref<gameItemData>;
    if IsDefined(this.m_inventoryItem) {
        itemData = this.m_inventoryItem.GetItemData();
    } else {
        itemData = InventoryItemData.GetGameItemData(this.m_gameData);
    }

    let weight: Float = RPGManager.GetItemWeight(itemData) * Cast<Float>(this.m_choosenQuantity);
    let isConsumable: Bool = itemData.HasTag(n"Consumable");
    let isAmmo: Bool = itemData.HasTag(n"Ammo");

    if isConsumable {
        inkTextRef.SetText(this.m_weightText, FloatToStringPrec(weight, 1));
    } else if isAmmo {
        inkTextRef.SetText(this.m_weightText, FloatToStringPrec(weight, 2));
    } else {
        inkTextRef.SetText(this.m_weightText, FloatToStringPrec(weight, 0));
    }
}

// ItemCategoryFliter
//      Remove Healing Items from Consumables.
//      Cluster all Charged Consumables under the same category.
//      Locate Ammo under Ranged Weapons.
//
@wrapMethod(ItemCategoryFliter)
public final static func IsOfCategoryType(filter: ItemFilterCategory, data: wref<gameItemData>) -> Bool {
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();
    if IsDefined(data) && settings.mainSystemEnabled && settings.newInventoryFilters {
        if Equals(filter, ItemFilterCategory.Consumables) {
            return data.HasTag(n"Consumable") && !data.HasTag(n"ChargedConsumable");
        } else if Equals(filter, ItemFilterCategory.Grenades) {
            return data.HasTag(n"ChargedConsumable");
        } else if Equals(filter, ItemFilterCategory.RangedWeapons) && (Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo)) {
            return data.HasTag(n"RangedWeapon") || data.HasTag(n"Ammo");
        }
    }
    return wrappedMethod(filter, data);
}

//  CraftingDataView
//      Remove Healing Items from Consumables.
//      Cluster all Charged Consumables under the same category.
//      Locate Ammo under Ranged Weapons.
//
@wrapMethod(CraftingDataView)
public func FilterItem(item: ref<IScriptable>) -> Bool {
    //DFProfile();
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
        } else if Equals(this.m_itemFilterType, ItemFilterCategory.RangedWeapons) && (Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo)) {
            return itemRecord.TagsContains(n"RangedWeapon") || itemRecord.TagsContains(n"Ammo");
        }
    }

    return wrappedMethod(item);
}

//  ItemFilterCategories - Set new Filter Category tooltips.
//      Note: the CName values for these new fields MUST start with UI-Filter-* in order to resolve correctly.
//
@wrapMethod(ItemFilterCategories)
public final static func GetLabelKey(filterType: ItemFilterCategory) -> CName {
    //DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();
    if settings.mainSystemEnabled {
        if settings.newInventoryFilters && Equals(filterType, ItemFilterCategory.Grenades) {
            return n"UI-Filter-DarkFutureChargedConsumables";
        }

        if Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo) {
            if Equals(filterType, ItemFilterCategory.RangedWeapons) {
                return n"UI-Filter-DarkFutureRangedWeaponsAmmo";
            }
        }
    }

    return wrappedMethod(filterType);
}

// ===================================================
// STATUS EFFECTS
// ===================================================

// buffListGameController - Selectively hide certain status icons.
//

@wrapMethod(buffListGameController)
protected cb func OnBuffDataChanged(value: Variant) -> Bool {
//DFProfile();
    let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    wrappedMethod(filteredBuffDataList);
}

// buffListGameController - Selectively hide certain status icons.
//
@wrapMethod(buffListGameController)
protected cb func OnDeBuffDataChanged(value: Variant) -> Bool {
//DFProfile();
    let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    wrappedMethod(filteredBuffDataList);
}

// buffListGameController - Selectively hide certain status icons.
//
@addMethod(buffListGameController)
private final func GetFilteredBuffList(value: Variant) -> array<BuffInfo> {
    //DFProfile();
    let buffDataList: array<BuffInfo> = FromVariant<array<BuffInfo>>(value);
    let filteredBuffDataList: array<BuffInfo>;

    let hidePersistent: Bool = DFSettings.Get().hidePersistentStatusIconsV2;

    for buff in buffDataList {
        let buffTags: array<CName> = TweakDBInterface.GetStatusEffectRecord(buff.buffID).GameplayTags();

        if hidePersistent && Equals(buffTags[0], n"DarkFutureCanHideOnBuffBar") {
            // Filter out buffs that should be hidden on the buff bar.
        } else {
            ArrayPush(filteredBuffDataList, buff);
        }
    }

    return filteredBuffDataList;
}

// buffListGameController - Ignore certain effects when determining whether or not to display the Buff Bar. (Allows the Health Bar to hide.)
//                          Avoid playing animations.
//
@replaceMethod(buffListGameController)
private final func UpdateBuffDebuffList() -> Void {
    //DFProfile();
    let buffList: array<BuffInfo>;
    let buffTimeRemaining: Float;
    let buffTimeTotal: Float;
    let currBuffLoc: wref<buffListItemLogicController>;
    let currBuffWidget: wref<inkWidget>;
    let data: ref<StatusEffect_Record>;
    let incomingBuffsCount: Int32;
    let onScreenBuffsCount: Int32;
    let visibleIncomingBuffsCount: Int32;
    let i: Int32 = 0;
    while i < ArraySize(this.m_buffDataList) {
      ArrayPush(buffList, this.m_buffDataList[i]);
      i = i + 1;
    };
    i = 0;
    while i < ArraySize(this.m_debuffDataList) {
      ArrayPush(buffList, this.m_debuffDataList[i]);
      i = i + 1;
    };
    incomingBuffsCount = ArraySize(buffList);
    onScreenBuffsCount = inkCompoundRef.GetNumChildren(this.m_buffsList);
    i = 0;
    while i < onScreenBuffsCount {
      currBuffWidget = this.m_buffWidgets[i];
      currBuffLoc = currBuffWidget.GetController() as buffListItemLogicController;
      if i >= incomingBuffsCount {
        currBuffWidget.SetVisible(false);
        currBuffLoc.SetStatusEffectRecord(null);
      } else {
        data = TweakDBInterface.GetStatusEffectRecord(buffList[i].buffID);
        buffTimeRemaining = buffList[i].timeRemaining;
        buffTimeTotal = buffList[i].timeTotal;

        if !IsDefined(data) || !IsDefined(data.UiData()) || Equals(data.UiData().IconPath(), "") {
          currBuffWidget.SetVisible(false);
          currBuffLoc.SetStatusEffectRecord(null);
        } else {
          if data != currBuffLoc.GetStatusEffectRecord() {
            currBuffLoc.SetStatusEffectRecord(data);

            // Edit Start
            // Don't play the intro animation.
            // currBuffLoc.PlayLibraryAnimation(n"intro");
            // Edit End
          };
          currBuffLoc.SetData(StringToName(data.UiData().IconPath()), buffTimeRemaining, buffTimeTotal, Cast<Int32>(buffList[i].stackCount));
          currBuffWidget.SetVisible(true);
          visibleIncomingBuffsCount += 1;
        };
      };
      i = i + 1;
    };
    this.SendVisibilityUpdate(inkWidgetRef.IsVisible(this.m_buffsList), visibleIncomingBuffsCount > 0);
    inkWidgetRef.SetVisible(this.m_buffsList, visibleIncomingBuffsCount > 0);
}


// inkCooldownGameController - The Status Effect Cooldown system, by default, doesn't know how to handle displaying Status Effects that
// have an infinite duration.
//
@replaceMethod(inkCooldownGameController)
public final func RequestCooldownVisualization(buffData: UIBuffInfo) -> Void {
    //DFProfile();
    let i: Int32;
    // Edit Start
    // -1.00 = Infinite Duration
    let tags: array<CName> = TweakDBInterface.GetStatusEffectRecord(buffData.buffID).GameplayTags();
    if buffData.timeRemaining <= 0.0 && !ArrayContains(tags, n"DarkFutureInfiniteDurationEffect") {
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

// ===================================================
// BUG FIXES
// ===================================================

// The Status Effect list could sometimes erroneously display incorrect stack counts
// on debuffs in the Status Effect / Radial Wheel menu.
//
@replaceMethod(inkCooldownGameController)
protected cb func OnEffectUpdate(v: Variant) -> Bool {
    //DFProfile();
    let buffs: array<BuffInfo>;
    let debuffs: array<BuffInfo>;
    let filteredBuffs: array<BuffInfo>;
    let filteredDebuffs: array<BuffInfo>;
    let typeToShowOnOpen: DFRadialMenuActiveEffectType;
    let effect: UIBuffInfo;
    let effects: array<UIBuffInfo>;
    let i: Int32;
    let tags: array<CName>;
    if !this.GetRootWidget().IsVisible() {
      return false;
    };
    if Equals(this.m_mode, ECooldownGameControllerMode.COOLDOWNS) {
      this.GetBuffs(buffs);
      // Edit Start
      // Filter the buff list.
      i = 0;
      while i < ArraySize(buffs) {
        tags = TweakDBInterface.GetStatusEffectRecord(buffs[i].buffID).GameplayTags();
        if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.StatusEffects) {
          if (NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining > -1.0)) || Equals(tags[0], n"DarkFutureForceShortTermFilter") {
            ArrayPush(filteredBuffs, buffs[i]);
          }
        } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.LongTermEffects) {
          if NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining == -1.0) {
            ArrayPush(filteredBuffs, buffs[i]);
          }
        } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.Conditions) {
          if Equals(tags[2], n"DarkFutureCondition") {
            ArrayPush(filteredBuffs, buffs[i]);
          }
        }
        i += 1;
      }
      // Edit End
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
      // Edit Start
      // Filter the buff and debuff lists.
      let statusEffectBuffs: array<BuffInfo>;
      let longTermEffectBuffs: array<BuffInfo>;
      let conditionBuffs: array<BuffInfo>;
      let statusEffectDebuffs: array<BuffInfo>;
      let longTermEffectDebuffs: array<BuffInfo>;
      let conditionDebuffs: array<BuffInfo>;

      i = 0;
      while i < ArraySize(buffs) {
        tags = TweakDBInterface.GetStatusEffectRecord(buffs[i].buffID).GameplayTags();

        if this.DarkFutureOpening {
            // Autocalculate the type.
            if (NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining > -1.0)) || Equals(tags[0], n"DarkFutureForceShortTermFilter") {
                ArrayPush(statusEffectBuffs, buffs[i]);
            } else if NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining == -1.0) {
                ArrayPush(longTermEffectBuffs, buffs[i]);
            } else if Equals(tags[2], n"DarkFutureCondition") {
                ArrayPush(conditionBuffs, buffs[i]);
            }

        } else {
            // Use the provided type.
            if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.StatusEffects) {
                if (NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining > -1.0)) || Equals(tags[0], n"DarkFutureForceShortTermFilter") {
                    ArrayPush(filteredBuffs, buffs[i]);
                }
            } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.LongTermEffects) {
                if NotEquals(tags[2], n"DarkFutureCondition") && (buffs[i].timeRemaining == -1.0) {
                    ArrayPush(filteredBuffs, buffs[i]);
                }
            } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.Conditions) {
                if Equals(tags[2], n"DarkFutureCondition") {
                    ArrayPush(filteredBuffs, buffs[i]);
                }
            }
        }

        i += 1;
      }
      i = 0;
      while i < ArraySize(debuffs) {
        tags = TweakDBInterface.GetStatusEffectRecord(debuffs[i].buffID).GameplayTags();

        if this.DarkFutureOpening {
            if (NotEquals(tags[2], n"DarkFutureCondition") && (debuffs[i].timeRemaining > -1.0)) || Equals(tags[0], n"DarkFutureForceShortTermFilter") {
                ArrayPush(statusEffectDebuffs, debuffs[i]);
            } else if NotEquals(tags[2], n"DarkFutureCondition") && (debuffs[i].timeRemaining == -1.0) {
                ArrayPush(longTermEffectDebuffs, debuffs[i]);
            } else if Equals(tags[2], n"DarkFutureCondition") {
                ArrayPush(conditionDebuffs, debuffs[i]);
            }

        } else {
            if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.StatusEffects) {
                if (NotEquals(tags[2], n"DarkFutureCondition") && (debuffs[i].timeRemaining > -1.0)) || Equals(tags[0], n"DarkFutureForceShortTermFilter") {
                    ArrayPush(filteredDebuffs, debuffs[i]);
                }
            } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.LongTermEffects) {
                if NotEquals(tags[2], n"DarkFutureCondition") && (debuffs[i].timeRemaining == -1.0) {
                    ArrayPush(filteredDebuffs, debuffs[i]);
                }
            } else if Equals(this.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.Conditions) {
                if Equals(tags[2], n"DarkFutureCondition") {
                    ArrayPush(filteredDebuffs, debuffs[i]);
                }
            }
        }

        i += 1;
      }

      if this.DarkFutureOpening {
        // Finish calculating the category to show.

        let statusEffectSize: Int32 = ArraySize(statusEffectBuffs) + ArraySize(statusEffectDebuffs);
        typeToShowOnOpen = DFRadialMenuActiveEffectType.StatusEffects;

        let longTermEffectSize: Int32 = ArraySize(longTermEffectBuffs) + ArraySize(longTermEffectDebuffs);
        if statusEffectSize == 0 && longTermEffectSize > 0 {
            typeToShowOnOpen = DFRadialMenuActiveEffectType.LongTermEffects;
        }

        let conditionsSize: Int32 = ArraySize(conditionBuffs) + ArraySize(conditionDebuffs);
        if statusEffectSize == 0 && longTermEffectSize == 0 && conditionsSize > 0 {
            typeToShowOnOpen = DFRadialMenuActiveEffectType.Conditions;
        }

        if Equals(typeToShowOnOpen, DFRadialMenuActiveEffectType.StatusEffects) {
            filteredBuffs = statusEffectBuffs;
            filteredDebuffs = statusEffectDebuffs;

        } else if Equals(typeToShowOnOpen, DFRadialMenuActiveEffectType.LongTermEffects) {
            filteredBuffs = longTermEffectBuffs;
            filteredDebuffs = longTermEffectDebuffs;

        } else if Equals(typeToShowOnOpen, DFRadialMenuActiveEffectType.Conditions) {
            filteredBuffs = conditionBuffs;
            filteredDebuffs = conditionDebuffs;
        }
      }

      // Edit End

      i = 0;
      while i < ArraySize(filteredBuffs) {
        effect.buffID = filteredBuffs[i].buffID;
        effect.timeRemaining = filteredBuffs[i].timeRemaining;
        effect.stackCount = filteredBuffs[i].stackCount;
        effect.isBuff = true;
        ArrayPush(effects, effect);
        i += 1;
      };
      i = 0;
      while i < ArraySize(filteredDebuffs) {
        effect.buffID = filteredDebuffs[i].buffID;
        effect.timeRemaining = filteredDebuffs[i].timeRemaining;
        // Edit Start
        // Incorrectly references buffs[i].stackCount in base game.
        effect.stackCount = filteredDebuffs[i].stackCount;
        // Edit End
        effect.isBuff = false;
        ArrayPush(effects, effect);
        i += 1;
      };
    };

    if ArraySize(effects) > 0 {
        this.ParseBuffList(effects);
    };

    // Force the correct category.
    if this.DarkFutureOpening {
        this.DarkFutureActiveEffectType = typeToShowOnOpen;
        DFHUDSystem.Get().ForceRadialMenuActiveEffectTitle(typeToShowOnOpen);
    }

    this.DarkFutureOpening = false;

    // Edit Start
    /*if ArraySize(effects) == 0 {
      inkWidgetRef.SetVisible(this.m_cooldownTitle, false);
      inkWidgetRef.SetVisible(this.m_cooldownContainer, false);
    };*/
    // Edit End
}

// SingleCooldownManager - Cache the gameplay tags, for efficiency. Fix the vertical alignment of the stack count in
// cases where the duration of the Status Effect is infinite.
//
@addField(SingleCooldownManager)
private let m_gameplayTags: array<CName>;

@wrapMethod(SingleCooldownManager)
public final func ActivateCooldown(buffData: UIBuffInfo) -> Void {
    //DFProfile();
    wrappedMethod(buffData);

    // Cache the gameplay tags, for efficiency.
    this.m_gameplayTags = TweakDBInterface.GetStatusEffectRecord(buffData.buffID).GameplayTags();

    // Bug Fix: Vertically align the Icon Canvas to Top to avoid stack count from displaying outside the bounds
    // of the status icon in the Radial Menu when the Status Effect has an infinite duration.
    let statusEffectIconCanvas: ref<inkCanvas> = inkWidgetRef.Get(this.m_stackCount).GetParentWidget() as inkCanvas;
    if IsDefined(statusEffectIconCanvas) {
        statusEffectIconCanvas.SetVAlign(inkEVerticalAlign.Top);
    }
}

// SingleCooldownManager - Don't display duration text on effects with an infinite duration.
//
@wrapMethod(SingleCooldownManager)
private final func SetTimeRemaining(time: Float) -> Void {
    //DFProfile();
    if time == -1.0 {
        // Don't display duration text on effects with an infinite duration.
        inkTextRef.SetText(this.m_timeRemaining, "");
        inkWidgetRef.Get(this.m_sprite).SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", AbsF(1.0));
    } else {
        wrappedMethod(time);
    }
}

// SingleCooldownManager - Set the timeLeft fraction to 1, so that the icon is always displayed "full".
//
@replaceMethod(SingleCooldownManager)
public final func Update(timeLeft: Float, stackCount: Uint32) -> Void {
    //DFProfile();
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

// ===================================================
// MAIN MENU
// ===================================================

// SingleplayerMenuGameController - Display an invalid language settings warning if the audio
// and subtitle languages do not match.
//
@wrapMethod(SingleplayerMenuGameController)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
    let r: Bool = wrappedMethod();

    let srh: wref<inkISystemRequestsHandler> = this.GetSystemRequestsHandler();

    if IsDefined(srh) {
        // Invalid Language Check
        let langGroup: ref<ConfigGroup> = srh.GetUserSettings().GetGroup(n"/language");
        let subtitleVar: ref<ConfigVarListName> = langGroup.GetVar(n"Subtitles") as ConfigVarListName;
        let onscreenVar: ref<ConfigVarListName> = langGroup.GetVar(n"OnScreen") as ConfigVarListName;

        let subtitleValue: CName = subtitleVar.GetValue();
        let onscreenValue: CName = onscreenVar.GetValue();

        if NotEquals(subtitleValue, onscreenValue) {
            srh.RequestSystemNotificationGeneric(n"DarkFutureWarningInvalidLanguageSettingTitle", n"DarkFutureWarningInvalidLanguageSetting");
        }
    }

    return r;
}

// ===================================================
// WARNING MESSAGE (CONDITIONS)
// ===================================================

// WarningMessageGameController - Changes to support Condition warnings.
//
@addField(WarningMessageGameController)
private let DarkFuture_ShouldResetIcon: Bool = false;

// WarningMessageGameController - Changes to support Condition warnings.
//
@wrapMethod(WarningMessageGameController)
private final func UpdateWidgets() -> Void {
    //DFProfile();
    if this.m_simpleMessage.isShown && StrBeginsWith(this.m_simpleMessage.message, "DarkFutureMagicMessageString") {
        this.DarkFuture_ShouldResetIcon = true;

        let playbackOptions: inkAnimOptions;
        inkTextRef.SetLetterCase(this.m_mainTextWidget, textLetterCase.UpperCase);

        let textToSet: String = this.DarkFutureGetMessageTextFromMagicString(this.m_simpleMessage.message);
        inkTextRef.SetText(this.m_mainTextWidget, textToSet);

        // Custom icon
        this.m_root.SetState(n"Default");
        this.HideAllIcon();

        let iconImage: ref<inkImage>;
        let iconCompoundWidget: ref<inkCompoundWidget> = inkWidgetRef.Get(this.m_twintoneIcon) as inkCompoundWidget;
        for child in iconCompoundWidget.children.children {
            if Equals(child.GetName(), n"CrystalCoat_Icon") {
                iconImage = child as inkImage;
                iconImage.SetAtlasResource(r"darkfuture\\condition_images\\condition_assets.inkatlas");
                iconImage.SetTexturePart(n"ico_condition_outline");
                iconImage.SetSize(Vector2(91, 91));
            }
        }

        inkWidgetRef.SetVisible(this.m_twintoneIcon, true);

        GameInstance.GetAudioSystem(this.GetPlayerControlledObject().GetGame()).Play(n"ui_menu_full_screen_perk_espionage_blue_highlite_01_Play"); // Front-half chirps
        GameInstance.GetAudioSystem(this.GetPlayerControlledObject().GetGame()).Play(n"ui_menu_full_screen_perk_espionage_select_01_Play");  // Back-half chirps

        if this.m_simpleMessage.isInstant {
            playbackOptions.fromMarker = n"idle_start";
        };
        playbackOptions.toMarker = n"freeze_intro";
        if IsDefined(this.m_animProxyShow) {
            this.m_animProxyShow.Stop();
        };
        this.m_animProxyShow = this.PlayLibraryAnimation(n"warning", playbackOptions);
        this.m_animProxyShow.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnShown");
        this.m_root.SetVisible(true);
    } else {
        wrappedMethod();
    }
}

// WarningMessageGameController - Convert the "magic string" into localized text.
//
@addMethod(WarningMessageGameController)
private final func DarkFutureGetMessageTextFromMagicString(magicString: String) -> String {
    //DFProfile();
    switch magicString {
        case "DarkFutureMagicMessageStringConditionInjury1":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationInjury01");
        case "DarkFutureMagicMessageStringConditionInjury2":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationInjury02");
        case "DarkFutureMagicMessageStringConditionInjury3":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationInjury03");
        case "DarkFutureMagicMessageStringConditionInjury4":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationInjury04");
        case "DarkFutureMagicMessageStringConditionHumanityLoss1":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationHumanityLoss01");
        case "DarkFutureMagicMessageStringConditionHumanityLoss2":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationHumanityLoss02");
        case "DarkFutureMagicMessageStringConditionHumanityLoss3":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationHumanityLoss03");
        case "DarkFutureMagicMessageStringConditionHumanityLoss4":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationHumanityLoss04");
        case "DarkFutureMagicMessageStringConditionBiocorruption1":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationBiocorruption01");
        case "DarkFutureMagicMessageStringConditionBiocorruption2":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationBiocorruption02");
        case "DarkFutureMagicMessageStringConditionBiocorruption3":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationBiocorruption03");
        case "DarkFutureMagicMessageStringConditionBiocorruption4":
            return GetLocalizedTextByKey(n"DarkFutureConditionNotificationBiocorruption04");

        default:
            return "";
    }
}

// WarningMessageGameController - Changes to support Condition warnings.
//
@wrapMethod(WarningMessageGameController)
protected cb func OnHidden(anim: ref<inkAnimProxy>) -> Bool {
    //DFProfile();
    let r: Bool = wrappedMethod(anim);

    // Revert the TwinTone icon back to default, if it was changed before.
    if this.DarkFuture_ShouldResetIcon {
        this.DarkFuture_ShouldResetIcon = false;
        let iconImage: ref<inkImage>;
        let iconCompoundWidget: ref<inkCompoundWidget> = inkWidgetRef.Get(this.m_twintoneIcon) as inkCompoundWidget;
        for child in iconCompoundWidget.children.children {
            if Equals(child.GetName(), n"CrystalCoat_Icon") {
                iconImage = child as inkImage;
                iconImage.SetAtlasResource(r"base\\gameplay\\gui\\quests\\mq058\\mq058_assets.inkatlas");
                iconImage.SetTexturePart(n"crystalcoat_icon");
                iconImage.SetSize(Vector2(93, 63));
            }
        }
    }

    return r;
}

// ===================================================
// WARNING MESSAGE (CYBERPSYCHOSIS)
// ===================================================

// WarningMessageGameController - Add required fields to drive "insanity" message VFX.
//
@addField(WarningMessageGameController)
private let DarkFutureCyberpsychosisMessageIndex: Int32 = 0;

@addField(WarningMessageGameController)
private const let DarkFutureCyberpsychosisMessageIndexMax: Int32 = 8;

@addField(WarningMessageGameController)
public let DarkFutureCyberpsychosisMessageDelayID: DelayID;

@addField(WarningMessageGameController)
private let DarkFutureCyberpsychosisMessageDelayIntervalShort: Float = 0.03;

@addField(WarningMessageGameController)
private let DarkFutureCyberpsychosisMessageDelayIntervalLong: Float = 0.06;

public class DFProgressCyberpsychosisMessageCallback extends DFDelayCallback {
    public let warningMessageController: ref<WarningMessageGameController>;

    public static func Create(warningMessageController: wref<WarningMessageGameController>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<DFProgressCyberpsychosisMessageCallback> = new DFProgressCyberpsychosisMessageCallback();
        self.warningMessageController = warningMessageController;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.warningMessageController.DarkFutureCyberpsychosisMessageDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.warningMessageController.ProgressCyberpsychosisMessage();
    }
}

// WarningMessageGameController - Method to register for next message with a delay.
//
@addMethod(WarningMessageGameController)
private final func RegisterProgressCyberpsychosisMessageCallback(opt long: Bool) -> Void {
    //DFProfile();
    let rand: Float = RandRangeF(-0.005, 0.01);

    if long {
        RegisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), DFProgressCyberpsychosisMessageCallback.Create(this), this.DarkFutureCyberpsychosisMessageDelayID, this.DarkFutureCyberpsychosisMessageDelayIntervalLong + rand);
    } else {
        RegisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), DFProgressCyberpsychosisMessageCallback.Create(this), this.DarkFutureCyberpsychosisMessageDelayID, this.DarkFutureCyberpsychosisMessageDelayIntervalShort + rand);
    }
}

// WarningMessageGameController - Method to unregister queued delays.
//
@addMethod(WarningMessageGameController)
private final func UnregisterProgressCyberpsychosisMessageCallback() -> Void {
    //DFProfile();
    UnregisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), this.DarkFutureCyberpsychosisMessageDelayID);
}

// WarningMessageGameController - Main logic for "cyberpsychosis insanity" message effects.
//
@addMethod(WarningMessageGameController)
public final func ProgressCyberpsychosisMessage() -> Void {
    //DFProfile();
    this.DarkFutureCyberpsychosisMessageIndex += 1;
    if this.DarkFutureCyberpsychosisMessageIndex < this.DarkFutureCyberpsychosisMessageIndexMax {

        let glitchOffsetX: Float = RandRangeF(-10.0, 50.0);
        let glitchOffsetY: Float = RandRangeF(-50.0, 50.0);
        let shouldShear: Bool = RandRangeInclusive(1, 100) <= 20;
        let glitchShear: Float = RandRangeF(-0.4, -0.7);

        inkWidgetRef.SetTranslation(this.m_mainTextWidget, Vector2(0.0, 0.0));
        inkWidgetRef.SetTranslation(this.m_mainTextWidget, Vector2(glitchOffsetX, glitchOffsetY));

        if shouldShear {
            inkWidgetRef.SetShear(this.m_mainTextWidget, Vector2(glitchShear, 0.0));
        } else {
            inkWidgetRef.SetShear(this.m_mainTextWidget, Vector2(0.0, 0.0));
        }

        let randomMessageIndex: Int32 = RandRangeInclusive(1, 11);
        this.m_mainTextWidget.SetLocalizedText(StringToName("DarkFutureCyberpsychosisNotification" + ToString(randomMessageIndex)));

        // Randomly stretch, shear, or offset the icon.
        let shouldMutateIcon: Bool = RandRangeInclusive(1, 100) <= 85;
        let randomIconMutation: Int32 = RandRangeInclusive(1, 10);

        if shouldMutateIcon {
            // Reset the icon.
            inkWidgetRef.SetTranslation(this.m_attencionIcon, Vector2(0.0, 0.0));
            inkWidgetRef.SetScale(this.m_attencionIcon, Vector2(1.0, 1.0));
            inkWidgetRef.SetShear(this.m_attencionIcon, Vector2(0.0, 0.0));

            if randomIconMutation <= 2 {
            // Stretch
            inkWidgetRef.SetScale(this.m_attencionIcon, Vector2(1.0, 1.8));
            inkWidgetRef.SetTranslation(this.m_attencionIcon, Vector2(0.0, -20.0));

            } else if randomIconMutation <= 4 {
                // Shear
                inkWidgetRef.SetShear(this.m_attencionIcon, Vector2(-0.4, 0.0));
            } else {
                // Translate
                let iconOffsetX: Float = RandRangeF(-40.0, 40.0);
                let iconOffsetY: Float = RandRangeF(-40.0, 40.0);
                inkWidgetRef.SetTranslation(this.m_attencionIcon, Vector2(iconOffsetX, iconOffsetY));
            }
        }

        this.RegisterProgressCyberpsychosisMessageCallback(this.DarkFutureCyberpsychosisMessageIndex % 3 == 0);

    } else {
        // Reset the icon and message text to default values.
        inkWidgetRef.SetTranslation(this.m_mainTextWidget, Vector2(0.0, 0.0));
        inkWidgetRef.SetShear(this.m_mainTextWidget, Vector2(0.0, 0.0));
        inkWidgetRef.SetTranslation(this.m_attencionIcon, Vector2(0.0, 0.0));
        inkWidgetRef.SetScale(this.m_attencionIcon, Vector2(1.0, 1.0));
        inkWidgetRef.SetShear(this.m_attencionIcon, Vector2(0.0, 0.0));

        this.m_mainTextWidget.SetLocalizedText(n"DarkFutureCyberpsychosisNotification0");
    }
}

// WarningMessageGameController - Event called when the message is fully unfolded. Triggers effect playback.
//
@wrapMethod(WarningMessageGameController)
protected cb func OnShown(anim: ref<inkAnimProxy>) -> Bool {
    //DFProfile();
    if Equals(this.m_simpleMessage.message, GetLocalizedTextByKey(n"DarkFutureCyberpsychosisNotification0")) {
        this.DarkFutureCyberpsychosisMessageIndex = 0;
        this.ProgressCyberpsychosisMessage();
    }

    wrappedMethod(anim);
}

// WarningMessageGameController - When uninitializing the class, unregister for any queued changes.
//
@wrapMethod(WarningMessageGameController)
protected cb func OnUnitialize() -> Bool {
    //DFProfile();
    wrappedMethod();
    this.UnregisterProgressCyberpsychosisMessageCallback();
}

// ===================================================
// PROGRESS NOTIFICATION (CONDITIONS)
// ===================================================

// ItemsNotificationQueue - Give the Dark Future Notification Service a reference to the Items Notification Queue.
//
@wrapMethod(ItemsNotificationQueue)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
    //DFProfile();
    // Store a reference to the Item Notification Queue on Dark Future's Notification Service.
    DFNotificationService.Get().SetItemsNotificationQueue(this);

    return wrappedMethod(playerPuppet);
}

// ItemsNotificationQueue - Method for pushing Dark Future Progress Notifications for Conditions.
//
@addMethod(ItemsNotificationQueue)
public final func PushDarkFutureProgressNotification(value: Int32, remainingPointsToLevelUp: Int32, barDelta: Int32, actualDelta: Int32, notificationColorTheme: CName, const notificationName: script_ref<String>, type: gamedataProficiencyType, currentLevel: Int32, isLevelMaxed: Bool) -> Void {
    //DFProfile();
    let notificationData: gameuiGenericNotificationData;
    let userData: ref<DFProgressionViewData>;
    let sum: Int32 = remainingPointsToLevelUp + value;
    let progress: Float = Cast<Float>(value) / Cast<Float>(sum);

    // If maximum value, force progress to full.
    if progress == 0.0 && isLevelMaxed {
        progress = Cast<Float>(sum);
    }

    notificationData.widgetLibraryItemName = this.m_xpNotification;
    userData = new DFProgressionViewData();
    userData.expProgress = progress;
    userData.expValue = value;
    userData.notificationColorTheme = notificationColorTheme;
    userData.title = Deref(notificationName);
    userData.delta = barDelta;
    userData.actualDelta = actualDelta;
    userData.type = type;
    userData.currentLevel = currentLevel;
    userData.isLevelMaxed = isLevelMaxed;
    notificationData.time = 6.10;
    notificationData.notificationData = userData;
    this.AddNewNotificationData(notificationData);
}

// InitializationSoundController - If an ExpPopup, wait for ProgressionNotification to tell us what to play.
//
@wrapMethod(InitializationSoundController)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
    if Equals(this.m_soundControlName, n"ExpPopup") && Equals(this.m_initializeSoundName, n"OnOpen") {
        // Wait for ProgressionNotification to tell us what to play.
        return false;
    } else {
        return wrappedMethod();
    }
}

// InitializationSoundController - Play the default initialization sound.
//
@addMethod(InitializationSoundController)
public final func DFOnInitialize() -> Bool {
    //DFProfile();
    if NotEquals(this.m_soundControlName, n"None") && NotEquals(this.m_initializeSoundName, n"None") {
        this.PlaySound(this.m_soundControlName, this.m_initializeSoundName);
    };
}

// ProgressionNotification - Replace the SetNotificationData method with enhanced functionality to support Conditions.
//
@replaceMethod(ProgressionNotification)
public native func SetNotificationData(notificationData: ref<GenericNotificationViewData>) -> Void {
    //DFProfile();
    let barEndSize: Vector2;
    let barStartSize: Vector2;
    this.m_expBarWidthSize = inkWidgetRef.GetWidth(this.m_expBar);
    this.m_expBarHeightSize = inkWidgetRef.GetHeight(this.m_expBar);
    this.progression_data = notificationData as ProgressionViewData;
    let asDFProgressionViewData: ref<DFProgressionViewData> = this.progression_data as DFProgressionViewData;

    inkTextRef.SetText(this.m_titleRef, this.progression_data.title);
    inkWidgetRef.SetState(this.m_root, this.progression_data.notificationColorTheme);

    // Edit - Fix a base game bug where delta was used incorrectly on the bar.
    let deltaAsPct: Float = (Cast<Float>(this.progression_data.delta) * this.progression_data.expProgress) / Cast<Float>(this.progression_data.expValue);
    barStartSize = Vector2(AbsF((this.progression_data.expProgress - deltaAsPct) * this.m_expBarWidthSize), this.m_expBarHeightSize);
    //
    barEndSize = Vector2(this.progression_data.expProgress * this.m_expBarWidthSize, this.m_expBarHeightSize);

    // Edit - Support deltas that extend beyond the current bar.
    if IsDefined(asDFProgressionViewData) {
        inkTextRef.SetText(this.m_expText, IntToString(asDFProgressionViewData.actualDelta));
    } else {
        inkTextRef.SetText(this.m_expText, IntToString(this.progression_data.delta));
    }
    //

    inkTextRef.SetText(this.m_currentLevel, IntToString(this.progression_data.currentLevel));

    // Edit - Support "Fully Restored" message when incrementing to 0.
    if this.progression_data.isLevelMaxed {
        inkTextRef.SetText(this.m_nextLevel, "LocKey#42198");
    } else if this.progression_data.currentLevel == 0 && this.progression_data.expValue == 0 {
        inkTextRef.SetText(this.m_nextLevel, GetLocalizedTextByKey(n"DarkFutureProgressionNotificationFullyRestored"));
    } else {
        inkTextRef.SetText(this.m_nextLevel, IntToString(this.progression_data.currentLevel + 1));
    };
    //

    // Edit - Don't assume bar always increases.
    if barStartSize.X > barEndSize.X && this.progression_data.delta >= 0 {
        barStartSize.X = 0.0;
    } else if barStartSize.X < barEndSize.X && this.progression_data.delta < 0 {
        barStartSize.X = this.m_expBarWidthSize;
    }
    //

    this.PlayAnim(n"intro");

    // Does nothing?
    GameInstance.GetAudioSystem(this.GetPlayerControlledObject().GetGame()).Play(n"ui_menu_perk_level_up");

    // Edit - If this is a Dark Future progression notification, call a different version of BarProgressAnim(), set the display text, and play our own sound effect.
    let asProgressionViewData: ref<ProgressionViewData> = notificationData as ProgressionViewData;
    let expTextLabel: ref<inkText> = (inkWidgetRef.Get(this.m_expText).parentWidget as inkHorizontalPanel).GetWidgetByPathName(n"exp_value_title") as inkText;
    let expPlus: ref<inkText> = (inkWidgetRef.Get(this.m_expText).parentWidget as inkHorizontalPanel).GetWidgetByPathName(n"plus") as inkText;
    if IsDefined(asProgressionViewData) {
        if Equals(asProgressionViewData.type, DFEnum_gamedataProficiencyType(n"DarkFutureHumanityLoss")) ||
           Equals(asProgressionViewData.type, DFEnum_gamedataProficiencyType(n"DarkFutureInjury")) ||
           Equals(asProgressionViewData.type, DFEnum_gamedataProficiencyType(n"DarkFutureBiocorruption")) {

            // Hide the plus symbol when the value is decreasing.
            let deltaToCheck: Int32 = IsDefined(asDFProgressionViewData) ? asDFProgressionViewData.actualDelta : this.progression_data.delta;
            // Increasing (Worsening)
            if deltaToCheck >= 0 {
                DFNotificationService.Get().PlayDarkFutureProgressionNotificationSFXNegative();
                if IsDefined(expPlus) {
                    expPlus.SetVisible(true);
                }
            // Decreasing (Restoring)
            } else {
                DFNotificationService.Get().PlayDarkFutureProgressionNotificationSFXPositive();
                if IsDefined(expPlus) {
                    expPlus.SetVisible(false);
                }
            }
            if IsDefined(expTextLabel) {
                expTextLabel.SetText(GetLocalizedTextByKey(n"DarkFutureProgressionNotificationPoints"));
            }
            this.DFBarProgressAnim(this.m_expBar, barStartSize, barEndSize);

        } else {
            let soundController: ref<InitializationSoundController> = inkWidgetRef.Get(this.m_root).parentWidget.GetController() as InitializationSoundController;
            if IsDefined(soundController) {
                soundController.DFOnInitialize();
            }
            if IsDefined(expPlus) {
                expPlus.SetVisible(true);
            }
            if IsDefined(expTextLabel) {
                expTextLabel.SetText(GetLocalizedTextByKey(n"Gameplay-RPG-CharDev-RPG-Experience"));
            }
            this.BarProgressAnim(this.m_expBar, barStartSize, barEndSize);
        }
    }
}

// ProgressionNotification - A copy of BarProgressAnim that supports a custom callback.
//
@addMethod(ProgressionNotification)
public final func DFBarProgressAnim(animatingObject: inkWidgetRef, barStartSize: Vector2, barEndSize: Vector2) -> Void {
    //DFProfile();
    let barProgress: ref<inkAnimDef> = new inkAnimDef();
    let sizeInterpolator: ref<inkAnimSize> = new inkAnimSize();
    sizeInterpolator.SetDuration(1.50);
    sizeInterpolator.SetStartSize(barStartSize);
    sizeInterpolator.SetEndSize(barEndSize);
    sizeInterpolator.SetType(inkanimInterpolationType.Quintic);
    sizeInterpolator.SetMode(inkanimInterpolationMode.EasyInOut);
    barProgress.AddInterpolator(sizeInterpolator);

    this.m_barAnimationProxy = inkWidgetRef.PlayAnimation(animatingObject, barProgress);

    // Custom callback
    this.m_barAnimationProxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnDFBarAnimationFinishDelay");
}

public class DFProgressionNotificationBarAnimFinishDelay extends DFDelayCallback {
    public let ProgressionNotification: wref<ProgressionNotification>;

    public static func Create(ProgressionNotification: wref<ProgressionNotification>) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<DFProgressionNotificationBarAnimFinishDelay> = new DFProgressionNotificationBarAnimFinishDelay();
        self.ProgressionNotification = ProgressionNotification;
        return self;
    }

    public func InvalidateDelayID() -> Void {
        //DFProfile();
        this.ProgressionNotification.DFProgressionNotificationBarAnimFinishDelayID = GetInvalidDelayID();
    }

    public func Callback() -> Void {
        //DFProfile();
        this.ProgressionNotification.PlayAnim(n"outro");
    }
}

// ProgressionNotification - Custom callback support.
//
@addField(ProgressionNotification)
public let DFProgressionNotificationBarAnimFinishDelayID: DelayID;

@addField(ProgressionNotification)
public let DFProgressionNotificationBarAnimFinishDelayInterval: Float = 3.0;

@addMethod(ProgressionNotification)
public final func RegisterDFProgressionNotificationBarAnimFinishDelay() -> Void {
    //DFProfile();
    RegisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), DFProgressionNotificationBarAnimFinishDelay.Create(this), this.DFProgressionNotificationBarAnimFinishDelayID, this.DFProgressionNotificationBarAnimFinishDelayInterval);
}

@addMethod(ProgressionNotification)
protected cb func OnDFBarAnimationFinishDelay(anim: ref<inkAnimProxy>) -> Bool {
    //DFProfile();
    this.RegisterDFProgressionNotificationBarAnimFinishDelay();
}

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
import DarkFuture.UI.DFHUDSystem
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
import DarkFuture.Conditions.{
	DFHumanityLossConditionSystem,
	DFCyberpsychosisChanceData,
	DFInjuryConditionSystem
}
import DarkFuture.DelayHelper.*
import DarkFuture.Services.{
	DFNotificationService,
	DFProgressionViewData
}
import DarkFuture.Utils.{
	GetDarkFutureHDRColor,
	DFHDRColor,
	IsCoinFlipSuccessful
}

// ===================================================
//  INVENTORY ITEMS
// ===================================================

//  UIInventoryItemsManager - Allow ammo to be seen in the inventory.
//
@wrapMethod(UIInventoryItemsManager)
public final static func GetBlacklistedTags() -> array<CName> {
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

		if IsSystemEnabledAndRunning(DFAlcoholAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveAlcoholWeak") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderAlcohol");
		}

		if IsSystemEnabledAndRunning(DFAlcoholAddictionSystem.Get()) && itemData.HasTag(n"DarkFutureConsumableAddictiveAlcoholStrong") {
			addictionLabel = GetLocalizedTextByKey(n"DarkFutureAddictiveItemTooltipHeaderAlcoholStrong");
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

// ItemTooltipBottomModule - Show the price on ammo.
//
@wrapMethod(ItemTooltipBottomModule)
public final static func ShouldDisplayPrice(displayContext: InventoryTooltipDisplayContext, isSellable: Bool, itemData: ref<gameItemData>, itemType: gamedataItemType, opt lootItemType: LootItemType) -> Bool {
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
	let isConsumable: Bool = itemData.HasTag(n"Consumable");
	let isAmmo: Bool = itemData.HasTag(n"Ammo");

	if isConsumable {
		let itemWeight: Float = RPGManager.GetItemWeight(itemData);
		inkTextRef.SetText(this.m_weightText, s"\(FloatToStringPrec(itemWeight, 1))");
	} else if isAmmo {
		let itemWeight: Float = RPGManager.GetItemWeight(itemData);
		inkTextRef.SetText(this.m_weightText, s"\(FloatToStringPrec(itemWeight, 2))");
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

// ItemQuantityPickerController - Update the weight precision of consumables and ammo when dropping.
//
@replaceMethod(ItemQuantityPickerController)
protected final func UpdateWeight() -> Void {
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
//		Remove Healing Items from Consumables.
//		Cluster all Charged Consumables under the same category.
//		Locate Ammo under Ranged Weapons.
//
@wrapMethod(ItemCategoryFliter)
public final static func IsOfCategoryType(filter: ItemFilterCategory, data: wref<gameItemData>) -> Bool {
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

//	CraftingDataView
//		Remove Healing Items from Consumables.
//		Cluster all Charged Consumables under the same category.
//		Locate Ammo under Ranged Weapons.
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
		} else if Equals(this.m_itemFilterType, ItemFilterCategory.RangedWeapons) && (Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(settings.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo)) {
			return itemRecord.TagsContains(n"RangedWeapon") || itemRecord.TagsContains(n"Ammo");
		}
	}

	return wrappedMethod(item);
}

// 	ItemFilterCategories - Set new Filter Category tooltips.
//		Note: the CName values for these new fields MUST start with UI-Filter-* in order to resolve correctly.
//
@wrapMethod(ItemFilterCategories)
public final static func GetLabelKey(filterType: ItemFilterCategory) -> CName {
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

// buffListGameController - Selectively hide certain status icons based on settings.
//
/*
@wrapMethod(buffListGameController)
protected cb func OnBuffDataChanged(value: Variant) -> Bool {
	let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    wrappedMethod(filteredBuffDataList);
}

// buffListGameController - Selectively hide certain status icons based on settings.
//
@wrapMethod(buffListGameController)
protected cb func OnDeBuffDataChanged(value: Variant) -> Bool {
	let filteredBuffDataList: array<BuffInfo> = this.GetFilteredBuffList(value);
    wrappedMethod(filteredBuffDataList);
}

// buffListGameController - Selectively hide certain status icons based on settings.
//
@addMethod(buffListGameController)
private final func GetFilteredBuffList(value: Variant) -> array<BuffInfo> {
	let hideDFPersistentStatusIcons: Bool = DFSettings.Get().hidePersistentStatusIcons;
	let buffDataList: array<BuffInfo> = FromVariant<array<BuffInfo>>(value);
	let filteredBuffDataList: array<BuffInfo>;
	
	for buff in buffDataList {
		let buffTags: array<CName> = TweakDBInterface.GetStatusEffectRecord(buff.buffID).GameplayTags();
		
		if hideDFPersistentStatusIcons && ArrayContains(buffTags, n"DarkFutureCanHideOnBuffBar") {
			// Filter out buffs that should be hidden on the buff bar regardless based on Dark Future settings.
		} else {
			ArrayPush(filteredBuffDataList, buff);
		}
	}

	return filteredBuffDataList;
}
*/


// buffListGameController - Ignore certain effects when determining whether or not to display the Buff Bar. (Allows the Health Bar to hide.)
//                          Avoid playing animations.
//
@replaceMethod(buffListGameController)
private final func UpdateBuffDebuffList() -> Void {
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

		// Edit Start
		// Allow some effects to not be shown on the buff bar.
        if !IsDefined(data) || !IsDefined(data.UiData()) || Equals(data.UiData().IconPath(), "") || data.GameplayTagsContains(n"DarkFutureInvisibleOnBuffBar") {
		// Edit End
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

		  // Edit Start
		  // Only increment the incoming buffs count if the effect doesn't have a certain tag.
		  if !data.GameplayTagsContains(n"DarkFutureAllowBuffBarHide") {
			visibleIncomingBuffsCount += 1;
		  }
		  // Edit End
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
// on debuffs in the Status Effect / Quick Switch Wheel menu.
//
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

// SingleCooldownManager - Cache the gameplay tags, for efficiency. Fix the vertical alignment of the stack count in
// cases where the duration of the Status Effect is infinite.
//
@addField(SingleCooldownManager)
private let m_gameplayTags: array<CName>;

@wrapMethod(SingleCooldownManager)
public final func ActivateCooldown(buffData: UIBuffInfo) -> Void {
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
	let r = wrappedMethod();

	let srh: wref<inkISystemRequestsHandler> = this.GetSystemRequestsHandler();

	if IsDefined(srh) {
		// Invalid Language Check
		let langGroup: ref<ConfigGroup> = srh.GetUserSettings().GetGroup(n"/language");
		let subtitleVar: ref<ConfigVarListName> = langGroup.GetVar(n"Subtitles") as ConfigVarListName;
		let onscreenVar: ref<ConfigVarListName> = langGroup.GetVar(n"OnScreen") as ConfigVarListName;

		let subtitleValue = subtitleVar.GetValue();
		let onscreenValue = onscreenVar.GetValue();

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
		
		default:
			return "";
	}
}

// WarningMessageGameController - Changes to support Condition warnings.
//
@wrapMethod(WarningMessageGameController)
protected cb func OnHidden(anim: ref<inkAnimProxy>) -> Bool {
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
		let self: ref<DFProgressCyberpsychosisMessageCallback> = new DFProgressCyberpsychosisMessageCallback();
		self.warningMessageController = warningMessageController;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.warningMessageController.DarkFutureCyberpsychosisMessageDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.warningMessageController.ProgressCyberpsychosisMessage();
	}
}

// WarningMessageGameController - Method to register for next message with a delay.
//
@addMethod(WarningMessageGameController)
private final func RegisterProgressCyberpsychosisMessageCallback(opt long: Bool) -> Void {
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
	UnregisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), this.DarkFutureCyberpsychosisMessageDelayID);
}

// WarningMessageGameController - Main logic for "cyberpsychosis insanity" message effects.
//
@addMethod(WarningMessageGameController)
public final func ProgressCyberpsychosisMessage() -> Void {
	this.DarkFutureCyberpsychosisMessageIndex += 1;
	if this.DarkFutureCyberpsychosisMessageIndex < this.DarkFutureCyberpsychosisMessageIndexMax {
		
		let glitchOffsetX: Float = RandRangeF(-10.0, 50.0);
		let glitchOffsetY: Float = RandRangeF(-50.0, 50.0);
		let shouldShear: Bool = RandRange(1, 100) <= 20;
		let glitchShear: Float = RandRangeF(-0.4, -0.7);

		inkWidgetRef.SetTranslation(this.m_mainTextWidget, Vector2(0.0, 0.0));
		inkWidgetRef.SetTranslation(this.m_mainTextWidget, Vector2(glitchOffsetX, glitchOffsetY));

		if shouldShear {
			inkWidgetRef.SetShear(this.m_mainTextWidget, Vector2(glitchShear, 0.0));
		} else {
			inkWidgetRef.SetShear(this.m_mainTextWidget, Vector2(0.0, 0.0));
		}

		let randomMessageIndex: Int32 = RandRange(1, 11);
		this.m_mainTextWidget.SetLocalizedText(StringToName("DarkFutureCyberpsychosisNotification" + ToString(randomMessageIndex)));

		// Randomly stretch, shear, or offset the icon.
		let shouldMutateIcon: Bool = RandRange(1, 100) <= 85;
		let randomIconMutation: Int32 = RandRange(1, 10);

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
	// Store a reference to the Item Notification Queue on Dark Future's Notification Service.
	DFNotificationService.Get().SetItemsNotificationQueue(this);

	return wrappedMethod(playerPuppet);
}

// ItemsNotificationQueue - Method for pushing Dark Future Progress Notifications for Conditions.
//
@addMethod(ItemsNotificationQueue)
public final func PushDarkFutureProgressNotification(value: Int32, remainingPointsToLevelUp: Int32, barDelta: Int32, actualDelta: Int32, notificationColorTheme: CName, const notificationName: script_ref<String>, type: gamedataProficiencyType, currentLevel: Int32, isLevelMaxed: Bool) -> Void {
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
	if NotEquals(this.m_soundControlName, n"None") && NotEquals(this.m_initializeSoundName, n"None") {
      	this.PlaySound(this.m_soundControlName, this.m_initializeSoundName);
    };
}

// ProgressionNotification - Replace the SetNotificationData method with enhanced functionality to support Conditions.
//
@replaceMethod(ProgressionNotification)
public native func SetNotificationData(notificationData: ref<GenericNotificationViewData>) -> Void {
    let barEndSize: Vector2;
    let barStartSize: Vector2;
    this.m_expBarWidthSize = inkWidgetRef.GetWidth(this.m_expBar);
    this.m_expBarHeightSize = inkWidgetRef.GetHeight(this.m_expBar);
    this.progression_data = notificationData as ProgressionViewData;
	let asDFProgressionViewData: ref<DFProgressionViewData> = this.progression_data as DFProgressionViewData;

    inkTextRef.SetText(this.m_titleRef, this.progression_data.title);
    inkWidgetRef.SetState(this.m_root, this.progression_data.notificationColorTheme);

	// Edit - Fix a base game bug where delta was used incorrectly on the bar.
	let deltaAsPct = (Cast<Float>(this.progression_data.delta) * this.progression_data.expProgress) / Cast<Float>(this.progression_data.expValue);
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
		if Equals(asProgressionViewData.type, IntEnum<gamedataProficiencyType>(EnumValueFromName(n"gamedataProficiencyType", n"DarkFutureHumanityLoss"))) ||
		   Equals(asProgressionViewData.type, IntEnum<gamedataProficiencyType>(EnumValueFromName(n"gamedataProficiencyType", n"DarkFutureInjury"))) {
			
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
		let self: ref<DFProgressionNotificationBarAnimFinishDelay> = new DFProgressionNotificationBarAnimFinishDelay();
		self.ProgressionNotification = ProgressionNotification;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.ProgressionNotification.DFProgressionNotificationBarAnimFinishDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
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
	RegisterDFDelayCallback(GameInstance.GetDelaySystem(GetGameInstance()), DFProgressionNotificationBarAnimFinishDelay.Create(this), this.DFProgressionNotificationBarAnimFinishDelayID, this.DFProgressionNotificationBarAnimFinishDelayInterval);
}

@addMethod(ProgressionNotification)
protected cb func OnDFBarAnimationFinishDelay(anim: ref<inkAnimProxy>) -> Bool {
    this.RegisterDFProgressionNotificationBarAnimFinishDelay();
}

// ===================================================
// RIPPERDOC MENU
// ===================================================

// RipperdocBarTooltip - Add a Cyberpsychosis chance indicator to the Edgerunner tooltip.
//
@addField(RipperdocBarTooltip)
public let DarkFutureCyberpsychosisStatPanelAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCyberwareCapacityDescriptionAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCapacityDescriptionAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureArmorDescriptionAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCyberpsychosisStatValue: ref<inkText>;

// RipperdocBarTooltip - Add a Cyberpsychosis chance indicator to the Edgerunner tooltip.
//
@wrapMethod(RipperdocBarTooltip)
public func SetData(tooltipData: ref<ATooltipData>) -> Void {
    wrappedMethod(tooltipData);

	let settings: ref<DFSettings> = DFSettings.Get();

	let humanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();
    let isEdgerunnerBarAndHumanityOverallocated: Bool = false;
	let isCapacityBar: Bool = false;
	let isArmorBar: Bool = false;
	let overallocatedBy: Int32;
	let baseFuryChance: Float;
    let data: ref<RipperdocBarTooltipTooltipData> = tooltipData as RipperdocBarTooltipTooltipData;
    if IsDefined(data) {
        if Equals(data.barType, BarType.Edgerunner) {
			if !settings.humanityLossConditionEnabled { return; }
			if !settings.humanityLossCyberpsychosisEnabled { return; }
            
			if data.capacityPerk1Bought {
                let i: Int32 = 0;
                while i < ArraySize(data.statsData) {
                    if Equals(data.statsData[i].type, gamedataStatType.HumanityOverallocated) {
                        isEdgerunnerBarAndHumanityOverallocated = data.statsData[i].value > 0;
						overallocatedBy = data.statsData[i].value;
						baseFuryChance = data.statsData[i].valueF * 0.10;
                        break;
                    }
                    i += 1;
                }
            }
        } else if Equals(data.barType, BarType.CurrentCapacity) {
			if !settings.humanityLossConditionEnabled { return; }
			isCapacityBar = true;
		
		} else if Equals(data.barType, BarType.Armor) {
			if !settings.injuryConditionEnabled { return; }
			isArmorBar = true;
		}
    } else {
		return;
	}

	let statName: ref<inkText>;
	let statColon: ref<inkText>;
	let cyberpsychosisStatHorizPanel: ref<inkHorizontalPanel>;

    if isEdgerunnerBarAndHumanityOverallocated {
        if !this.DarkFutureCyberpsychosisStatPanelAddedThisMenuSession {
            this.DarkFutureCyberpsychosisStatPanelAddedThisMenuSession = true;

            // Crawl up to the Stats panel.
            let statsWidget: ref<inkVerticalPanel> = inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;

            // Create new Stat line for Cyberpsychosis chance.
            statName = new inkText();
            statColon = new inkText();
            this.DarkFutureCyberpsychosisStatValue = new inkText();

            statName.SetName(n"name");
            statName.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            statName.SetFontSize(36);
            statName.SetVerticalAlignment(textVerticalAlignment.Center);
            statName.SetHAlign(inkEHorizontalAlign.Fill);
            statName.SetVAlign(inkEVerticalAlign.Bottom);
            statName.SetSize(Vector2(100.0, 32.0));
            statName.SetFitToContent(true);
            statName.SetAffectsLayoutWhenHidden(false);
            statName.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            statName.SetWrapping(false, 720.0, textWrappingPolicy.Default);
            statName.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
            statName.SetText(GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisChance"));

            statColon.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            statColon.SetName(n"colon");
            statColon.SetFontSize(36);
            statColon.SetVerticalAlignment(textVerticalAlignment.Center);
            statColon.SetHAlign(inkEHorizontalAlign.Fill);
            statColon.SetVAlign(inkEVerticalAlign.Bottom);
            statColon.SetSize(Vector2(100.0, 32.0));
            statColon.SetFitToContent(true);
            statColon.SetAffectsLayoutWhenHidden(false);
            statColon.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            statColon.SetText(":");
            statColon.SetVisible(false);

            this.DarkFutureCyberpsychosisStatValue.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            this.DarkFutureCyberpsychosisStatValue.SetFontSize(36);
            this.DarkFutureCyberpsychosisStatValue.SetVerticalAlignment(textVerticalAlignment.Top);
            this.DarkFutureCyberpsychosisStatValue.SetHAlign(inkEHorizontalAlign.Fill);
            this.DarkFutureCyberpsychosisStatValue.SetVAlign(inkEVerticalAlign.Bottom);
            this.DarkFutureCyberpsychosisStatValue.SetSize(Vector2(100.0, 32.0));
            this.DarkFutureCyberpsychosisStatValue.SetFitToContent(true);
            this.DarkFutureCyberpsychosisStatValue.SetAffectsLayoutWhenHidden(false);
            this.DarkFutureCyberpsychosisStatValue.SetMargin(15.0, 0.0, 0.0, 0.0);
            this.DarkFutureCyberpsychosisStatValue.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            this.DarkFutureCyberpsychosisStatValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));

			let cyberpsychosisChanceData: DFCyberpsychosisChanceData = humanityLossConditionSystem.GetCyberpsychosisChance(overallocatedBy);
			let cyberpsychosisChance: Float = cyberpsychosisChanceData.chance;
			if NotEquals(cyberpsychosisChanceData.reason, "") {
				this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 1) + "% " + cyberpsychosisChanceData.reason);
			} else {
				this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 1) + "%");
			}

            // Create a new Stat Horizontal Panel.
            cyberpsychosisStatHorizPanel = new inkHorizontalPanel();
            cyberpsychosisStatHorizPanel.SetName(n"statDarkFutureCyberpsychosis");
            cyberpsychosisStatHorizPanel.AddChildWidget(statName);
            cyberpsychosisStatHorizPanel.AddChildWidget(statColon);
            cyberpsychosisStatHorizPanel.AddChildWidget(this.DarkFutureCyberpsychosisStatValue);

            // Add to the tooltip.
            statsWidget.AddChildWidget(cyberpsychosisStatHorizPanel);

			// Update the Fury chance based on current data.
			let isBlocked: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
			let furyBonusChance: Float = Cast<Float>(humanityLossConditionSystem.GetCyberpsychosisStacksApplied()) * 0.5;
			if isBlocked {
				inkTextRef.SetText(this.m_stats3Value, "0% " + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonImmunosuppressant"));
			} else {
				inkTextRef.SetText(this.m_stats3Value, FloatToStringPrec(baseFuryChance + furyBonusChance, 1) + "%");
			}
			
        } else {
			let cyberpsychosisChanceData: DFCyberpsychosisChanceData = humanityLossConditionSystem.GetCyberpsychosisChance(overallocatedBy);
			let cyberpsychosisChance: Float = cyberpsychosisChanceData.chance;
            if NotEquals(cyberpsychosisChanceData.reason, "") {
				this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 2) + "% " + cyberpsychosisChanceData.reason);
			} else {
				this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 2) + "%");
			}

			// Update the Fury chance based on current data.
			let isBlocked: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
			let furyBonusChance: Float = Cast<Float>(humanityLossConditionSystem.GetCyberpsychosisStacksApplied()) * 0.5;
			if isBlocked {
				inkTextRef.SetText(this.m_stats3Value, "0% " + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonImmunosuppressant"));
			} else {
				inkTextRef.SetText(this.m_stats3Value, FloatToStringPrec(baseFuryChance + furyBonusChance, 1) + "%");
			}
		}
    
	} else if isCapacityBar {
		// Make the Stats pane visible.
		// Crawl up to the Stats panel.
        let statsWidget: ref<inkVerticalPanel> = inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;
		statsWidget.SetVisible(true);

		// Make the Stats 1 line visible, but no others.
		inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().SetVisible(true);
		inkWidgetRef.Get(this.m_stats2Name).GetParentWidget().SetVisible(false);
		inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().SetVisible(false);

		// Set the data on the Stats 1 line.
		inkTextRef.SetText(this.m_stats1Name, GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipHumanityLossRate"));
		inkWidgetRef.SetTintColor(this.m_stats1Name, GetDarkFutureHDRColor(DFHDRColor.PanelRed));

		let humanityLossMult: Float = 0.0;
		let isBlocked: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
		if !isBlocked {
			humanityLossMult = Cast<Float>(data.totalValue) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
		}
		let precision: Int32 = humanityLossMult >= 100.0 || humanityLossMult == 0.0 ? 0 : 1;
		inkTextRef.SetText(this.m_stats1Value, "+" + FloatToStringPrec(humanityLossMult, precision) + "%");
		inkWidgetRef.SetTintColor(this.m_stats1Value, GetDarkFutureHDRColor(DFHDRColor.PanelRed));
		
		// Set the description text.
		if !this.DarkFutureCapacityDescriptionAddedThisMenuSession {
			this.DarkFutureCapacityDescriptionAddedThisMenuSession = true;

			let descriptionWidget: ref<inkText> = inkWidgetRef.Get(this.m_capacityDescription) as inkText;
			let updatedCapacityText: String = descriptionWidget.GetText() + "\n\n" + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberwareCapacityUpdated");
			(inkWidgetRef.Get(this.m_capacityDescription) as inkText).SetText(updatedCapacityText);
		}
	
	} else if isArmorBar {
		// Make the Stats pane visible.
		// Crawl up to the Stats panel.
        let statsWidget: ref<inkVerticalPanel> = inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;
		statsWidget.SetVisible(true);

		// Make the Stats 1 line visible, but no others.
		inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().SetVisible(true);
		inkWidgetRef.Get(this.m_stats2Name).GetParentWidget().SetVisible(false);
		inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().SetVisible(false);

		// Set the data on the Stats 1 line.
		inkTextRef.SetText(this.m_stats1Name, GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipInjuryRate"));
		inkWidgetRef.SetTintColor(this.m_stats1Name, GetDarkFutureHDRColor(DFHDRColor.MainBlue));

		let injuryMult: Float = DFInjuryConditionSystem.Get().GetArmorInjuryMult();
		let precision: Int32 = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
		inkTextRef.SetText(this.m_stats1Value, "-" + FloatToStringPrec(injuryMult, precision) + "%");
		inkWidgetRef.SetTintColor(this.m_stats1Value, GetDarkFutureHDRColor(DFHDRColor.MainBlue));

		// Set the description text.
		if !this.DarkFutureArmorDescriptionAddedThisMenuSession {
			this.DarkFutureArmorDescriptionAddedThisMenuSession = true;

			let descriptionWidget: ref<inkText> = inkWidgetRef.Get(this.m_armorDescription) as inkText;
			let updatedArmorText: String = descriptionWidget.GetText() + "\n\n" + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipArmorDamageReductionUpdated");
			(inkWidgetRef.Get(this.m_armorDescription) as inkText).SetText(updatedArmorText);
		}
	}
}

// RipperdocMetersBase - Add a method to create a new UI indicator below the Cyberware Capacity and Armor meters.
//
@addMethod(RipperdocMetersBase)
public final func CreateDarkFutureConditionIndicator(root: ref<inkCompoundWidget>, iconPart: CName, color: DFHDRColor, leftMargin: Float, opt isBlocked: Bool, opt blockedMessage: CName) -> ref<inkText> {
	// Create the Humanity Loss / Injury Multiplier Widget
	
	// Canvas
	let indicatorCanvas: ref<inkCanvas> = new inkCanvas();
	indicatorCanvas.SetName(n"DFIndicatorCanvas");
	indicatorCanvas.SetMargin(leftMargin, 1000.0, 5.0, 0.0);
	indicatorCanvas.SetSize(210.0, 75.0);
	indicatorCanvas.Reparent(root);

	// "Blocked" Symbol
	let indicatorBlocked: ref<inkImage> = new inkImage();
	indicatorBlocked.SetName(n"DarkFutureHLIndicatorBlocked");
	indicatorBlocked.SetVisible(false);
	indicatorBlocked.SetMargin(0.0, -8.0, 0.0, 0.0);
	indicatorBlocked.SetSize(32.0, 32.0);
	indicatorBlocked.SetScale(Vector2(1.5, 1.5));
	indicatorBlocked.SetFitToContent(true);
	indicatorBlocked.SetAffectsLayoutWhenHidden(false);
	indicatorBlocked.SetAnchor(inkEAnchor.Centered);
	indicatorBlocked.SetAnchorPoint(0.5, 0.0);
	indicatorBlocked.SetAtlasResource(r"base\\gameplay\\gui\\common\\icons\\atlas_common.inkatlas");
	indicatorBlocked.SetTexturePart(n"ico_locked");
	indicatorBlocked.SetTintColor(GetDarkFutureHDRColor(color));
	indicatorBlocked.Reparent(indicatorCanvas);

	// Icon
	let indicatorIcon: ref<inkImage> = new inkImage();
	indicatorIcon.SetName(n"DarkFutureHLIndicatorIcon");
	indicatorIcon.SetMargin(6.0, -32.0, 0.0, 0.0);
	indicatorIcon.SetSize(32.0, 32.0);
	indicatorIcon.SetFitToContent(true);
	indicatorIcon.SetAffectsLayoutWhenHidden(false);
	indicatorIcon.SetAnchor(inkEAnchor.CenterLeft);
	indicatorIcon.SetAtlasResource(r"darkfuture\\condition_images\\condition_assets.inkatlas");
	indicatorIcon.SetTexturePart(iconPart);
	indicatorIcon.SetTintColor(GetDarkFutureHDRColor(color));
	indicatorIcon.Reparent(indicatorCanvas);

	// Value
	let indicatorValue: ref<inkText> = new inkText();
	indicatorValue.SetName(n"DFIndicatorValue");
	indicatorValue.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
	indicatorValue.SetFontStyle(n"Semi-Bold");
	indicatorValue.SetFontSize(42);
	indicatorValue.SetLetterCase(textLetterCase.UpperCase);
	indicatorValue.SetFitToContent(false);
	indicatorValue.SetHorizontalAlignment(textHorizontalAlignment.Center);
	indicatorValue.SetVerticalAlignment(textVerticalAlignment.Center);
	indicatorValue.SetJustificationType(textJustificationType.Center);
	indicatorValue.SetSize(130.0, 65.0);
	indicatorValue.SetMargin(70.0, 6.0, 0.0, 0.0);
	indicatorValue.SetLockFontInGame(true);
	indicatorValue.SetTintColor(GetDarkFutureHDRColor(color));
	indicatorValue.Reparent(indicatorCanvas);
	indicatorValue.SetText("+0%");

	// "Immunosuppressant" Label
	let indicatorImmunosuppressantLabel: ref<inkText> = new inkText();
	indicatorImmunosuppressantLabel.SetName(n"DFIndicatorImmunosuppressantLabel");
	indicatorImmunosuppressantLabel.SetVisible(false);
	indicatorImmunosuppressantLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
	indicatorImmunosuppressantLabel.SetFontStyle(n"Semi-Bold");
	indicatorImmunosuppressantLabel.SetFontSize(22);
	indicatorImmunosuppressantLabel.SetLetterCase(textLetterCase.UpperCase);
	indicatorImmunosuppressantLabel.SetFitToContent(false);
	indicatorImmunosuppressantLabel.SetHorizontalAlignment(textHorizontalAlignment.Center);
	indicatorImmunosuppressantLabel.SetVerticalAlignment(textVerticalAlignment.Center);
	indicatorImmunosuppressantLabel.SetJustificationType(textJustificationType.Center);
	indicatorImmunosuppressantLabel.SetSize(130.0, 65.0);
	indicatorImmunosuppressantLabel.SetMargin(0.0, 30.0, 0.0, 0.0);
	indicatorImmunosuppressantLabel.SetAnchor(inkEAnchor.Centered);
	indicatorImmunosuppressantLabel.SetAnchorPoint(0.5, 0.0);
	indicatorImmunosuppressantLabel.SetLockFontInGame(true);
	indicatorImmunosuppressantLabel.SetTintColor(GetDarkFutureHDRColor(color));
	indicatorImmunosuppressantLabel.Reparent(indicatorCanvas);
	indicatorImmunosuppressantLabel.SetText(GetLocalizedTextByKey(blockedMessage));
	

	// Frame
	let indicatorFrame: ref<inkImage> = new inkImage();
	indicatorFrame.SetName(n"DFIndicatorFrame");
	indicatorFrame.SetAtlasResource(r"base\\gameplay\\gui\\fullscreen\\ripperdoc\\assets\\cw_bars_assets.inkatlas");
	indicatorFrame.SetTexturePart(n"counterLabel_stroke");
	indicatorFrame.SetContentHAlign(inkEHorizontalAlign.Fill);
	indicatorFrame.SetContentVAlign(inkEVerticalAlign.Fill);
	indicatorFrame.SetNineSliceScale(true);
	indicatorFrame.SetNineSliceGrid(inkMargin(0.0, 0.0, 0.0, 0.0));
	indicatorFrame.SetBrushTileType(inkBrushTileType.NoTile);
	indicatorFrame.SetAnchor(inkEAnchor.Fill);
	indicatorFrame.SetHAlign(inkEHorizontalAlign.Center);
	indicatorFrame.SetVAlign(inkEVerticalAlign.Center);
	indicatorFrame.SetSize(32.0, 32.0);
	indicatorFrame.SetFitToContent(true);
	indicatorFrame.SetAffectsLayoutWhenHidden(false);
	indicatorFrame.SetTintColor(GetDarkFutureHDRColor(color));
	indicatorFrame.Reparent(indicatorCanvas);

	// Set "Blocked" mode
	if isBlocked {
		indicatorIcon.SetOpacity(0.05);
		indicatorValue.SetOpacity(0.05);
		indicatorFrame.SetOpacity(0.05);
		indicatorBlocked.SetVisible(true);
		indicatorImmunosuppressantLabel.SetVisible(true);
	}

	return indicatorValue;
}

// RipperdocMetersCapacity - Fields and methods to add and update the indicator under the Cyberware Capacity meter.
//
@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorValue: ref<inkText>;

@addField(RipperdocMetersCapacity)
private let DarkFutureLastHumanityLossMult: Float;

@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorPulse: ref<PulseAnimation>;

@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorIsBlocked: Bool = false;

@wrapMethod(RipperdocMetersCapacity)
protected cb func OnInitialize() -> Bool {
	wrappedMethod();

	if DFSettings.Get().humanityLossConditionEnabled {
		let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
		let isBlocked: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
		this.DarkFutureHumanityLossMultIndicatorValue = this.CreateDarkFutureConditionIndicator(root, n"ico_condition_humanityloss", DFHDRColor.PanelRed, -42.0, isBlocked, n"DarkFutureItemNameImmunosuppressant");
		this.DarkFutureHumanityLossMultIndicatorIsBlocked = isBlocked;
		this.DarkFutureHumanityLossMultIndicatorPulse = new PulseAnimation();
	}
}

@wrapMethod(RipperdocMetersCapacity)
private final func ConfigureBar(curEquippedCapacity: Int32, newEquippedCapacity: Int32, maxCapacity: Int32, overclockCapacity: Int32, isChange: Bool) -> Void {
	wrappedMethod(curEquippedCapacity, newEquippedCapacity, maxCapacity, overclockCapacity, isChange);

	if this.DarkFutureHumanityLossMultIndicatorIsBlocked { return; }

	if NotEquals(this.DarkFutureHumanityLossMultIndicatorValue, null) {
		let humanityLossMult: Float;

		if newEquippedCapacity > 0 {
			humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
			this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
			this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
		} else {
			if this.m_isHoverdCyberwareEquipped && newEquippedCapacity != 0 {
				humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
				this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
				this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
			} else {
				if newEquippedCapacity < 0 {
					humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
					this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
					this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
				} else {
					humanityLossMult = Cast<Float>(curEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
					this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
					this.StopPulse(this.DarkFutureHumanityLossMultIndicatorPulse);
				}
			}
		}

		this.DarkFutureLastHumanityLossMult = humanityLossMult;
		let precision: Int32 = humanityLossMult >= 100.0 ? 0 : 1;
		this.DarkFutureHumanityLossMultIndicatorValue.SetText("+" + FloatToStringPrec(humanityLossMult, precision) + "%");
	}
}

// RipperdocMetersArmor - Fields and methods to add and update the indicator under the Armor meter.
//
@addField(RipperdocMetersArmor)
private let DarkFutureInjuryMultIndicatorValue: ref<inkText>;

@addField(RipperdocMetersArmor)
private let DarkFutureLastInjuryMult: Float;

@addField(RipperdocMetersArmor)
private let DarkFutureInjuryMultIndicatorPulse: ref<PulseAnimation>;

@wrapMethod(RipperdocMetersArmor)
protected cb func OnInitialize() -> Bool {
	wrappedMethod();

	if DFSettings.Get().injuryConditionEnabled {
		let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
		this.DarkFutureInjuryMultIndicatorValue = this.CreateDarkFutureConditionIndicator(root, n"ico_condition_injury", DFHDRColor.MainBlue, -24.0);
		this.DarkFutureInjuryMultIndicatorPulse = new PulseAnimation();
	}
}

@wrapMethod(RipperdocMetersArmor)
private final func SetArmorData(newEquippedArmor: Float, maxCurrentArmor: Float, maxArmorPossible: Float, maxDamageReduction: Float) -> Void {
	wrappedMethod(newEquippedArmor, maxCurrentArmor, maxArmorPossible, maxDamageReduction);

	if NotEquals(this.DarkFutureInjuryMultIndicatorValue, null) {
		let injuryMult: Float = newEquippedArmor * DFInjuryConditionSystem.Get().armorInjuryMult;
		let precision: Int32 = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
		this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(injuryMult, precision) + "%");
		this.DarkFutureLastInjuryMult = injuryMult;
		this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
		this.StopPulse(this.DarkFutureInjuryMultIndicatorPulse);
	}
}

@wrapMethod(RipperdocMetersArmor)
private final func PreviewChange(change: Float, isHover: Bool, isCyberwareEquipped: Bool) -> Void {
	wrappedMethod(change, isHover, isCyberwareEquipped);

	if NotEquals(this.DarkFutureInjuryMultIndicatorValue, null) {
		if isHover && change != 0.0 {
			let injuryMult: Float = (change * DFInjuryConditionSystem.Get().armorInjuryMult) + this.DarkFutureLastInjuryMult;
			let precision: Int32 = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
			this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(injuryMult, precision) + "%");
			this.StartPulse(this.DarkFutureInjuryMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureInjuryMultIndicatorValue);
			if change > 0.0 {
				this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
			} else {
				this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
			}
		} else {
			let precision: Int32 = this.DarkFutureLastInjuryMult >= 100.0 ? 0 : this.DarkFutureLastInjuryMult >= 10.0 ? 1 : 2;
			this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(this.DarkFutureLastInjuryMult, precision) + "%");
			this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
			this.StopPulse(this.DarkFutureInjuryMultIndicatorPulse);
		}
	}
}
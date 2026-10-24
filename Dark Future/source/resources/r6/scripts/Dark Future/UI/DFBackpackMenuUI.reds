// -----------------------------------------------------------------------------
// DFBackpackMenuUI
// -----------------------------------------------------------------------------
//
// - Handles the UI meters in the Backpack Inventory.
//

import DarkFuture.Logging.*
import DarkFuture.Main.{ 
	DFNeedsDatum,
	DFNeedChangeDatum,
	DFEnergyChangePreview,
	DFNerveChangePreview
}
import DarkFuture.Settings.DFSettings
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
import DarkFuture.Conditions.{
	DFBiocorruptionConditionSystem
}
import DarkFuture.Services.{
	DFGameStateService,
	DFPlayerStateService
}
import DarkFuture.UI.{
	DFNeedsMenuBar,
	DFNeedsMenuBarSetupData
}

@addField(BackpackMainGameController)
private let GameStateService: wref<DFGameStateService>;

@addField(BackpackMainGameController)
private let Settings: wref<DFSettings>;

@addField(BackpackMainGameController)
private let HydrationSystem: wref<DFHydrationSystem>;

@addField(BackpackMainGameController)
private let NutritionSystem: wref<DFNutritionSystem>;

@addField(BackpackMainGameController)
private let EnergySystem: wref<DFEnergySystem>;

@addField(BackpackMainGameController)
private let NerveSystem: wref<DFNerveSystem>;

@addField(BackpackMainGameController)
private let PlayerStateService: wref<DFPlayerStateService>;

@addField(BackpackMainGameController)
private let AlcoholAddictionSystem: wref<DFAlcoholAddictionSystem>;

@addField(BackpackMainGameController)
private let NicotineAddictionSystem: wref<DFNicotineAddictionSystem>;

@addField(BackpackMainGameController)
private let NarcoticAddictionSystem: wref<DFNarcoticAddictionSystem>;

@addField(BackpackMainGameController)
private let BiocorruptionConditionSystem: wref<DFBiocorruptionConditionSystem>;

@addField(BackpackMainGameController)
private let barCluster: ref<inkVerticalPanel>;

@addField(BackpackMainGameController)
private let nerveBar: ref<DFNeedsMenuBar>;

@addField(BackpackMainGameController)
private let energyBar: ref<DFNeedsMenuBar>;

@addField(BackpackMainGameController)
private let nutritionBar: ref<DFNeedsMenuBar>;

@addField(BackpackMainGameController)
private let hydrationBar: ref<DFNeedsMenuBar>;

@addField(BackpackMainGameController)
private let barClusterfadeInAnimProxy: ref<inkAnimProxy>;

@addField(BackpackMainGameController)
private let barClusterfadeInAnim: ref<inkAnimDef>;

@addField(BackpackMainGameController)
private let barClusterfadeOutAnimProxy: ref<inkAnimProxy>;

@addField(BackpackMainGameController)
private let barClusterfadeOutAnim: ref<inkAnimDef>;

@addField(BackpackMainGameController)
private let startedInOvercharge: Bool;

//
//	Base Game Methods
//

//	BackpackMainGameController - Initialization
//
@wrapMethod(BackpackMainGameController)
protected cb func OnInitialize() -> Bool {
	//DFProfile();
	let gameInstance: GameInstance = GetGameInstance();
	this.Settings = DFSettings.GetInstance(gameInstance);
	this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
	this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
	this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
	this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
	this.GameStateService = DFGameStateService.GetInstance(gameInstance);
	this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
	this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
	this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
	this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
	this.BiocorruptionConditionSystem = DFBiocorruptionConditionSystem.GetInstance(gameInstance);

	let parentWidget: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
	
	this.CreateNeedsBarCluster(parentWidget);
	this.SetOriginalValuesInUI();

	wrappedMethod();
}

@addMethod(BackpackMainGameController)
private final func GetStackLimitedNerveToRestore(needsData: DFNeedsDatum, stackingEffect: TweakDBID, maxStacks: Uint32, stacksToTryToApply: Uint32) -> Float {
	//DFProfile();
	let amountToRestore: Float = 0.0;
	let appliedEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(this.m_player, stackingEffect);
	let appliedEffectStackCount: Uint32 = IsDefined(appliedEffect) ? appliedEffect.GetStackCount() : 0u;

	let availableStackCount: Uint32 = maxStacks - appliedEffectStackCount;
	let stacksToApply: Int32 = Min(Cast<Int32>(availableStackCount), Cast<Int32>(stacksToTryToApply));
	if stacksToApply > 0 {
		amountToRestore = needsData.nerve.value * Cast<Float>(stacksToApply);
	}

	return amountToRestore;
}

//	BackpackMainGameController - Update the UI when hovering over consumable items.
//
@wrapMethod(BackpackMainGameController)
protected cb func OnItemDisplayHoverOver(evt: ref<ItemDisplayHoverOverEvent>) -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod(evt);
	
	if this.Settings.mainSystemEnabled {
		let sortingDropdown: ref<DropdownListController> = inkWidgetRef.GetController(this.m_sortingDropdown) as DropdownListController;
		if !sortingDropdown.IsOpened() && IsDefined(evt.uiInventoryItem) {
			let itemData: wref<gameItemData> = evt.uiInventoryItem.GetItemData();

			if itemData.HasTag(n"Consumable") {
				let itemRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(itemData.GetID().GetTDBID());
				let needsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);

				// Show the change in Energy if player meets the energy management effect criteria.
				let energyMax: Float = this.EnergySystem.GetNeedMaxAfterItemUse(itemRecord);
				let ePrev: DFEnergyChangePreview = this.EnergySystem.GetItemEnergyChangePreviewAmountWithCrashInfo(itemRecord);
				this.energyBar.SetUpdatedValue(this.EnergySystem.GetNeedValue() + ePrev.change, energyMax, false, ePrev.indeterminate);

				// Show the increase in Hydration and Nutrition if player's Nerve is not too low or not impacted by Biocorruption.
				let hydrationMax: Float = this.HydrationSystem.GetNeedMaxAfterItemUse(itemRecord);
				let nutritionMax: Float = this.NutritionSystem.GetNeedMaxAfterItemUse(itemRecord);

				this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue(), hydrationMax);
				let hPrev: Float = this.HydrationSystem.GetNeedValue() + needsData.hydration.value;
				this.hydrationBar.SetUpdatedValue(hPrev, MinF(MaxF(needsData.hydration.ceiling, this.HydrationSystem.GetNeedValue()), hydrationMax));
				this.UpdateBarLimit(this.hydrationBar, hydrationMax);

				if this.NerveSystem.GetHasNausea() {
					// Player has nausea from low Nerve.
					this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue(), nutritionMax);
					
				} else {
					let nPrev: Float = this.NutritionSystem.GetNeedValue() + needsData.nutrition.value;
					this.nutritionBar.SetUpdatedValue(nPrev, MinF(MaxF(needsData.nutrition.ceiling, this.NutritionSystem.GetNeedValue()), nutritionMax));
					this.UpdateBarLimit(this.nutritionBar, nutritionMax);
				}

				// Handle Addiction Withdrawal and Alcohol
				let nerveMax: Float = this.NerveSystem.GetNeedMaxAfterItemUse(itemRecord);
				let nerveValue: Float = this.NerveSystem.GetNeedValue();
				let nervePrev: DFNerveChangePreview = this.NerveSystem.GetItemNerveChangePreviewAmount(itemRecord);
				let potentialNewValue: Float = nerveValue + nervePrev.change;

				if nerveValue > potentialNewValue {
					// Decreasing
					if nerveValue >= needsData.nerve.floor {
						if potentialNewValue < needsData.nerve.floor {
							potentialNewValue = needsData.nerve.floor;
						}
					} else {
						potentialNewValue = nerveValue;
					}
				} else if nerveValue < potentialNewValue {
					// Increasing
					if nerveValue <= needsData.nerve.ceiling {
						if potentialNewValue > needsData.nerve.ceiling {
							potentialNewValue = needsData.nerve.ceiling;
						}
					} else {
						potentialNewValue = nerveValue;
					}
				}

				this.nerveBar.SetUpdatedValue(potentialNewValue, nerveMax, false, nervePrev.indeterminate);
				this.UpdateBarLimit(this.nerveBar, nerveMax);

				// TODO - Anything that would obviously force a crash, like Addiquit, should show that change.
				this.UpdateNerveBarOvercharge(this.NerveSystem.GetOverchargeValue(), nervePrev.indeterminate);
			};
		};
	}
	

	return val;
}

//	BackpackMainGameController - Show or hide the UI when selecting filters.
//
@wrapMethod(BackpackMainGameController)
protected cb func OnItemFilterClick(evt: ref<inkPointerEvent>) -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod(evt);

	if this.GameStateService.IsValidGameState(this, true) {
		if evt.IsAction(n"click") {
			let filter: ItemFilterCategory = this.m_activeFilter.GetFilterType();
			
			// More Inventory Filters Compatibility
			let moreInventoryFiltersFoodFilterID: Int32 = 24;

			if Equals(filter, ItemFilterCategory.Consumables) || Equals(filter, ItemFilterCategory.AllItems) || Equals(EnumInt(filter), moreInventoryFiltersFoodFilterID) {
				this.SetBarClusterFadeIn();
				this.UpdateAllBarsAppearance();
				this.nerveBar.UpdateOverchargeAppearance(this.NerveSystem.GetOverchargeValue(), this.Settings.compatibilityProjectE3UI);
			} else {
				this.SetBarClusterFadeOut();
			}
		}
	} else {
		this.barCluster.SetOpacity(0.0);
	}

	return val;
}

//	BackpackMainGameController - Show or hide the UI when the filter buttons spawn.
//	(The spawned button may be an active filter that should allow the UI to appear on menu load.)
//
@wrapMethod(BackpackMainGameController)
protected cb func OnFilterButtonSpawned(widget: ref<inkWidget>, callbackData: ref<BackpackFilterButtonSpawnedCallbackData>) -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod(widget, callbackData);

	if this.GameStateService.IsValidGameState(this, true) {
		let filter: ItemFilterCategory = this.m_activeFilter.GetFilterType();

		// More Inventory Filters Compatibility
		let moreInventoryFiltersFoodFilterID: Int32 = 24;

		if Equals(filter, ItemFilterCategory.Consumables) || Equals(filter, ItemFilterCategory.AllItems) || Equals(EnumInt(filter), moreInventoryFiltersFoodFilterID) {
			this.SetBarClusterFadeIn();
			this.UpdateAllBarsAppearance();
			this.nerveBar.UpdateOverchargeAppearance(this.NerveSystem.GetOverchargeValue(), this.Settings.compatibilityProjectE3UI);
		} else {
			this.SetBarClusterFadeOut();
		}
	} else {
		this.barCluster.SetOpacity(0.0);
	}

	return val;
}

//	BackpackMainGameController - Update the UI when leaving the hover state of an item.
//
@wrapMethod(BackpackMainGameController)
protected cb func OnItemDisplayHoverOut(evt: ref<ItemDisplayHoverOutEvent>) -> Bool {
	//DFProfile();
	if this.Settings.mainSystemEnabled {
		this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
		this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
		this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
		this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());

		this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue(), this.HydrationSystem.GetNeedMax());
		this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue(), this.NutritionSystem.GetNeedMax());
		this.energyBar.SetUpdatedValue(this.EnergySystem.GetNeedValue(), this.EnergySystem.GetNeedMax());
		this.nerveBar.SetUpdatedValue(this.NerveSystem.GetNeedValue(), this.NerveSystem.GetNeedMax());

		this.UpdateBarLimit(this.hydrationBar, this.HydrationSystem.GetNeedMax());
		this.UpdateBarLimit(this.nutritionBar, this.NutritionSystem.GetNeedMax());
		this.UpdateBarLimit(this.nerveBar, this.NerveSystem.GetNeedMax());
		this.UpdateNerveBarOvercharge(this.NerveSystem.GetOverchargeValue());
	}

    return wrappedMethod(evt);
}

//
//	New Methods
//
@addMethod(BackpackMainGameController)
private final func CreateNeedsBarCluster(parent: ref<inkCompoundWidget>) -> Void {
	//DFProfile();
	this.barCluster = new inkVerticalPanel();
	this.barCluster.SetOpacity(0.0);
	this.barCluster.SetName(n"NeedsBarCluster");
	this.barCluster.SetAnchor(inkEAnchor.TopCenter);
	this.barCluster.SetAnchorPoint(Vector2(0.5, 0.5));
	this.barCluster.SetScale(Vector2(1.0, 1.0));
	this.barCluster.SetTranslation(Vector2(0.0, 240.0));
	this.barCluster.Reparent(parent, 12);

	let rowOne: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	rowOne.SetName(n"NeedsBarClusterRowOne");
	rowOne.SetSize(Vector2(100.0, 60.0));
	rowOne.SetHAlign(inkEHorizontalAlign.Center);
	rowOne.SetVAlign(inkEVerticalAlign.Center);
	rowOne.SetAnchor(inkEAnchor.Fill);
	rowOne.SetAnchorPoint(Vector2(0.5, 0.5));
	rowOne.SetMargin(inkMargin(0.0, 0.0, 0.0, 36.0));
	rowOne.Reparent(this.barCluster);

	let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nerveIconName: CName = n"illegal";

	let hydrationIconPath: ResRef = r"base\\gameplay\\gui\\widgets\\healthbar\\atlas_buffinfo.inkatlas";
	let hydrationIconName: CName = n"hydrated";
	
	let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nutritionIconName: CName = n"food_vendor";

	let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let energyIconName: CName = n"wait";

	let barSetupData: DFNeedsMenuBarSetupData;

	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"nerveBar", nerveIconPath, nerveIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNerve"), 400.0, 100.0, 0.0, 0.0, true, false, GetLocalizedTextByKey(n"DarkFutureEuphoriaResourceName"));
	this.nerveBar = new DFNeedsMenuBar();
	this.nerveBar.Init(barSetupData);

	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"hydrationBar", hydrationIconPath, hydrationIconName, GetLocalizedTextByKey(n"DarkFutureUILabelHydration"), 400.0, 100.0, 0.0, 0.0, true, false, "");
	this.hydrationBar = new DFNeedsMenuBar();
	this.hydrationBar.Init(barSetupData);
	
	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"nutritionBar", nutritionIconPath, nutritionIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNutrition"), 400.0, 100.0, 0.0, 0.0, true, false, "");
	this.nutritionBar = new DFNeedsMenuBar();
	this.nutritionBar.Init(barSetupData);

	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"energyBar", energyIconPath, energyIconName, GetLocalizedTextByKey(n"DarkFutureUILabelEnergy"), 400.0, 0.0, 0.0, 0.0, false, false, "");
	this.energyBar = new DFNeedsMenuBar();
	this.energyBar.Init(barSetupData);
}

@addMethod(BackpackMainGameController)
private final func SetBarClusterFadeOut() -> Void {
	//DFProfile();
	this.StopAnimProxyIfDefined(this.barClusterfadeOutAnimProxy);
	this.StopAnimProxyIfDefined(this.barClusterfadeInAnimProxy);

	this.barClusterfadeOutAnim = new inkAnimDef();
	let fadeOutInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
	fadeOutInterp.SetStartTransparency(this.barCluster.GetOpacity());
	fadeOutInterp.SetEndTransparency(0.0);
	fadeOutInterp.SetDuration(0.075);
	this.barClusterfadeOutAnim.AddInterpolator(fadeOutInterp);
	this.barClusterfadeOutAnimProxy = this.barCluster.PlayAnimation(this.barClusterfadeOutAnim);
}

@addMethod(BackpackMainGameController)
private final func SetBarClusterFadeIn() -> Void {
	//DFProfile();
	this.StopAnimProxyIfDefined(this.barClusterfadeInAnimProxy);

	this.barClusterfadeInAnim = new inkAnimDef();
	let fadeInInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
	fadeInInterp.SetStartTransparency(this.barCluster.GetOpacity());
	fadeInInterp.SetEndTransparency(1.0);
	fadeInInterp.SetDuration(0.075);
	this.barClusterfadeInAnim.AddInterpolator(fadeInInterp);
	this.barClusterfadeInAnimProxy = this.barCluster.PlayAnimation(this.barClusterfadeInAnim);
}

@addMethod(BackpackMainGameController)
private final func UpdateAllBarsAppearance() -> Void {
	//DFProfile();
	let useProjectE3UI: Bool = this.Settings.compatibilityProjectE3UI;
	this.hydrationBar.UpdateAppearance(useProjectE3UI);
	this.nutritionBar.UpdateAppearance(useProjectE3UI);
	this.energyBar.UpdateAppearance(useProjectE3UI);
	this.nerveBar.UpdateAppearance(useProjectE3UI);
}

@addMethod(BackpackMainGameController)
private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
	//DFProfile();
	if IsDefined(animProxy) {
		animProxy.Stop();
	}
}

@addMethod(BackpackMainGameController)
private final func SetOriginalValuesInUI() -> Void {
	//DFProfile();
	if this.Settings.mainSystemEnabled {
		this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
		this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
		this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
		this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());

		this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue(), this.HydrationSystem.GetNeedMax());
		this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue(), this.NutritionSystem.GetNeedMax());
		this.energyBar.SetUpdatedValue(this.EnergySystem.GetNeedValue(), this.EnergySystem.GetNeedMax());
		this.nerveBar.SetUpdatedValue(this.NerveSystem.GetNeedValue(), this.NerveSystem.GetNeedMax());

		this.UpdateBarLimit(this.hydrationBar, this.HydrationSystem.GetNeedMax());
		this.UpdateBarLimit(this.nutritionBar, this.NutritionSystem.GetNeedMax());
		this.UpdateBarLimit(this.nerveBar, this.NerveSystem.GetNeedMax());
		let overcharge: Float = this.NerveSystem.GetOverchargeValue();
		if overcharge > 0.0 {
			this.startedInOvercharge = true;
		}
		this.UpdateNerveBarOvercharge(overcharge);
	}
}

@addMethod(BackpackMainGameController)
private final func UpdateBarLimit(bar: ref<DFNeedsMenuBar>, newLimitValue: Float) -> Void {
	//DFProfile();
	let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
	bar.SetProgressEmpty(currentLimitPct);
}

@addMethod(BackpackMainGameController)
private final func UpdateNerveBarOvercharge(newOverchargeValue: Float, opt showIndeterminateValue: Bool) -> Void {
	//DFProfile();
	let currentOverchargePct: Float = newOverchargeValue / 100.0;
	this.nerveBar.SetProgressOvercharge(currentOverchargePct);
	this.nerveBar.UpdateOverchargeAppearance(newOverchargeValue, this.Settings.compatibilityProjectE3UI, !this.startedInOvercharge && currentOverchargePct > 0.0, showIndeterminateValue);
}
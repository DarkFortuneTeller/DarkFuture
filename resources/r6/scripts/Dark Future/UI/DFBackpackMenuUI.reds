// -----------------------------------------------------------------------------
// DFBackpackMenuUI
// -----------------------------------------------------------------------------
//
// - Handles the UI meters in the Backpack Inventory.
//

import DarkFuture.Main.{ 
	DFNeedsDatum,
	DFNeedChangeDatum
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

//
//	Base Game Methods
//

//	BackpackMainGameController - Initialization
//
@wrapMethod(BackpackMainGameController)
protected cb func OnInitialize() -> Bool {
	let gameInstance = GetGameInstance();
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

	let parentWidget: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
	
	this.CreateNeedsBarCluster(parentWidget);
	this.SetOriginalValuesInUI();

	wrappedMethod();
}

//	BackpackMainGameController - Update the UI when hovering over consumable items.
//
@wrapMethod(BackpackMainGameController)
protected cb func OnItemDisplayHoverOver(evt: ref<ItemDisplayHoverOverEvent>) -> Bool {
	let val: Bool = wrappedMethod(evt);
	
	if this.Settings.mainSystemEnabled && !StatusEffectSystem.ObjectHasStatusEffect(this.HydrationSystem.player, t"DarkFutureStatusEffect.Weakened") {
		let sortingDropdown: ref<DropdownListController> = inkWidgetRef.GetController(this.m_sortingDropdown) as DropdownListController;
		if !sortingDropdown.IsOpened() && IsDefined(evt.uiInventoryItem) {
			let itemData: wref<gameItemData> = evt.uiInventoryItem.GetItemData();

			if itemData.HasTag(n"Consumable") {
				let needsData: DFNeedsDatum = GetConsumableNeedsData(itemData);

				// Show the increase in Hydration and Nutrition if player's Nerve is not too low.
				if this.NerveSystem.GetHasNausea() {
					this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue(), this.HydrationSystem.GetNeedMax());
					this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue(), this.NutritionSystem.GetNeedMax());
				} else {
					this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue() + needsData.hydration.value, this.HydrationSystem.GetNeedMax());
					this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue() + needsData.nutrition.value, this.NutritionSystem.GetNeedMax());
				}

				// If restoring, show the increase in Energy if player does not have too much Stimulant.
				let energyToChange: Float = needsData.energy.value;
				let updatedEnergyValue: Float = 0.0;
				
				if energyToChange > 0.0 {
					energyToChange *= (1.0 - (this.EnergySystem.stimulantEnergyRestoreMultPerStack * Cast<Float>(this.EnergySystem.stimulantStacks)));
				}

				updatedEnergyValue = this.EnergySystem.GetNeedValue() + energyToChange;
				this.energyBar.SetUpdatedValue(updatedEnergyValue, this.EnergySystem.GetNeedMax());
				
				// Handle Addiction Withdrawal and Alcohol
				let nerveMax: Float = this.NerveSystem.GetNerveLimitAfterItemUse(itemData);
				let nerveValue: Float = this.NerveSystem.GetNeedValue();
				let potentialNewValue: Float = nerveValue + (needsData.nerve.value + needsData.nerve.valueOnStatusEffectApply);

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

				this.nerveBar.SetUpdatedValue(potentialNewValue, nerveMax);
				this.UpdateNerveBarLimit(nerveMax);
			};
		};
	}
	

	return val;
}

//	BackpackMainGameController - Show or hide the UI when selecting filters.
//
@wrapMethod(BackpackMainGameController)
protected cb func OnItemFilterClick(evt: ref<inkPointerEvent>) -> Bool {
	let val: Bool = wrappedMethod(evt);

	if this.GameStateService.IsValidGameState("OnItemFilterClick") {
		if evt.IsAction(n"click") {
			let filter: ItemFilterCategory = this.m_activeFilter.GetFilterType();
			if Equals(filter, ItemFilterCategory.Consumables) || Equals(filter, ItemFilterCategory.AllItems) {
				this.SetBarClusterFadeIn();
				this.UpdateAllBarsAppearance();
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
	let val: Bool = wrappedMethod(widget, callbackData);

	if this.GameStateService.IsValidGameState("OnFilterButtonSpawned") {
		let filter: ItemFilterCategory = this.m_activeFilter.GetFilterType();
		if Equals(filter, ItemFilterCategory.Consumables) || Equals(filter, ItemFilterCategory.AllItems) {
			this.SetBarClusterFadeIn();
			this.UpdateAllBarsAppearance();
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
	if this.Settings.mainSystemEnabled {
		this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
		this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
		this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
		this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());

		this.hydrationBar.SetUpdatedValue(this.HydrationSystem.GetNeedValue(), this.HydrationSystem.GetNeedMax());
		this.nutritionBar.SetUpdatedValue(this.NutritionSystem.GetNeedValue(), this.NutritionSystem.GetNeedMax());
		this.energyBar.SetUpdatedValue(this.EnergySystem.GetNeedValue(), this.EnergySystem.GetNeedMax());
		this.nerveBar.SetUpdatedValue(this.NerveSystem.GetNeedValue(), this.NerveSystem.GetNeedMax());

		this.UpdateNerveBarLimit(this.NerveSystem.GetNeedMax());
	}

    return wrappedMethod(evt);
}

//
//	New Methods
//
@addMethod(BackpackMainGameController)
private final func CreateNeedsBarCluster(parent: ref<inkCompoundWidget>) -> Void {
	this.barCluster = new inkVerticalPanel();
	this.barCluster.SetOpacity(0.0);
	this.barCluster.SetName(n"NeedsBarCluster");
	this.barCluster.SetAnchor(inkEAnchor.TopCenter);
	this.barCluster.SetAnchorPoint(new Vector2(0.5, 0.5));
	this.barCluster.SetScale(new Vector2(this.Settings.backpackUIScale, this.Settings.backpackUIScale));
	this.barCluster.SetTranslation(new Vector2(this.Settings.backpackUIPosX, this.Settings.backpackUIPosY));
	this.barCluster.Reparent(parent, 12);

	let rowOne: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	rowOne.SetName(n"NeedsBarClusterRowOne");
	rowOne.SetSize(new Vector2(100.0, 60.0));
	rowOne.SetHAlign(inkEHorizontalAlign.Center);
	rowOne.SetVAlign(inkEVerticalAlign.Center);
	rowOne.SetAnchor(inkEAnchor.Fill);
	rowOne.SetAnchorPoint(new Vector2(0.5, 0.5));
	rowOne.SetMargin(new inkMargin(0.0, 0.0, 0.0, 36.0));
	rowOne.Reparent(this.barCluster);

	let rowTwo: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	rowTwo.SetName(n"NeedsBarClusterRowTwo");
	rowTwo.SetSize(new Vector2(100.0, 60.0));
	rowTwo.SetVAlign(inkEVerticalAlign.Center);
	rowTwo.SetAnchor(inkEAnchor.Fill);
	rowTwo.SetAnchorPoint(new Vector2(0.5, 0.5));
	rowTwo.SetMargin(new inkMargin(0.0, 0.0, 0.0, 30.0));
	rowTwo.Reparent(this.barCluster);

	let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nerveIconName: CName = n"illegal";

	let hydrationIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let hydrationIconName: CName = n"bar";
	
	let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nutritionIconName: CName = n"food_vendor";

	let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let energyIconName: CName = n"wait";

	let barSetupData: DFNeedsMenuBarSetupData;

	barSetupData = new DFNeedsMenuBarSetupData(rowOne, n"nerveBar", nerveIconPath, nerveIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNerve"), 400.0, 100.0, 0.0, 0.0, true);
	this.nerveBar = new DFNeedsMenuBar();
	this.nerveBar.Init(barSetupData);

	barSetupData = new DFNeedsMenuBarSetupData(rowOne, n"energyBar", energyIconPath, energyIconName, GetLocalizedTextByKey(n"DarkFutureUILabelEnergy"), 400.0, 0.0, 0.0, 0.0, false);
	this.energyBar = new DFNeedsMenuBar();
	this.energyBar.Init(barSetupData);

	barSetupData = new DFNeedsMenuBarSetupData(rowTwo, n"hydrationBar", hydrationIconPath, hydrationIconName, GetLocalizedTextByKey(n"DarkFutureUILabelHydration"), 400.0, 100.0, 0.0, 0.0, false);
	this.hydrationBar = new DFNeedsMenuBar();
	this.hydrationBar.Init(barSetupData);
	
	barSetupData = new DFNeedsMenuBarSetupData(rowTwo, n"nutritionBar", nutritionIconPath, nutritionIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNutrition"), 400.0, 0.0, 0.0, 0.0, false);
	this.nutritionBar = new DFNeedsMenuBar();
	this.nutritionBar.Init(barSetupData);	
}

@addMethod(BackpackMainGameController)
private final func SetBarClusterFadeOut() -> Void {
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
	let useProjectE3UI: Bool = this.Settings.compatibilityProjectE3UI;
	this.hydrationBar.UpdateAppearance(useProjectE3UI);
	this.nutritionBar.UpdateAppearance(useProjectE3UI);
	this.energyBar.UpdateAppearance(useProjectE3UI);
	this.nerveBar.UpdateAppearance(useProjectE3UI);
}

@addMethod(BackpackMainGameController)
private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
	if IsDefined(animProxy) {
		animProxy.Stop();
	}
}

@addMethod(BackpackMainGameController)
private final func SetOriginalValuesInUI() -> Void {
	if this.Settings.mainSystemEnabled {
		this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
		this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
		this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
		this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());
		this.UpdateNerveBarLimit(this.NerveSystem.GetNeedMax());
	}
}

@addMethod(BackpackMainGameController)
private final func UpdateNerveBarLimit(newLimitValue: Float) -> Void {
	let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
	this.nerveBar.SetProgressEmpty(currentLimitPct);
}

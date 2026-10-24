// -----------------------------------------------------------------------------
// DFInventoryStatsBarOverrides
// -----------------------------------------------------------------------------
//
// - Base game method overrides that support the appearance of stats bars
//   on inventory item cards.
//

import DarkFuture.Utils.{
	DFGetPlayer,
	GetDarkFutureHDRColor,
	DFHDRColor
}
import DarkFuture.Needs.{
	DFHydrationSystem,
    DFEnergySystem,
	DFNerveSystem
}
import DarkFuture.Addictions.{
	DFAlcoholAddictionSystem,
	DFNicotineAddictionSystem,
	DFNarcoticAddictionSystem
}
import DarkFuture.Conditions.{
	DFBiocorruptionConditionSystem,
	DFEuphoriaBlockedReason
}
import DarkFuture.System.{
	DFSystem,
	IsSystemEnabledAndRunning
}
import DarkFuture.Services.{
	DFPlayerStateService,
	DFManagedEffectType,
	DFManagedEffect,
	DFManagedEffectDefinition,
	DFManagedEffectItemDefinition,
	DFManagedEffectStackCountDef,
	DFManagedEffectStackCountMode,
	DFCyberwareService
}

public struct DFStatsBarData {
	public let percentage: Float;
	public let comparedPercentage: Float;
	public let overLimit: Bool;
	public let overLimitRisk: Bool;
}

//  UIInventoryItem - Method that returns whether or not this is an item that should
//                    display stats bars.
//
@addMethod(UIInventoryItem)
public final func IsDarkFutureItemWithShownBars() -> Bool {
	//DFProfile();
	let realItemData: ref<gameItemData> = this.GetRealItemData();
	return realItemData.HasTag(n"DarkFutureItemTooltipShowBars");
}

//  UIInventoryItem - Return if this item should display stats bars.
//
@wrapMethod(UIInventoryItem)
public final func IsUsingBars() -> Bool {
	//DFProfile();
	if this.IsDarkFutureItemWithShownBars() {
		return true;
	} else {
		return wrappedMethod();
	}
}

//  UIInventoryItemStatsManager - Allow the stat bars to be rebuilt each time a Dark Future item is displayed.
//
@wrapMethod(UIInventoryItemStatsManager)
public final func GetWeaponBars(opt force: Bool) -> wref<UIInventoryItemWeaponBars> {
	//DFProfile();
	let gameItemDataStrong: ref<gameItemData> = this.m_gameItemData;
	if gameItemDataStrong.HasTag(n"DarkFutureItemTooltipShowBars") {
		return wrappedMethod(true);
	} else {
		return wrappedMethod(force);
	}
}

//  NewItemTooltipStatBarController - A place to store the last item hovered.
//
@addField(NewItemTooltipStatBarController)
public let DarkFutureLastItemManagedEffectApplicableStackCount: Int32 = 0;

@addField(NewItemTooltipStatBarController)
public let DarkFutureLastItemManagedEffectApplicableStackCountMax: Int32 = 0;

//  ItemTooltipCyberwareWeaponModule - Store off the last item hovered so that we can interrogate what it is later.
//
@wrapMethod(ItemTooltipCyberwareWeaponModule)
public final func NEW_Update(data: wref<UIInventoryItem>, comparisonData: wref<UIInventoryItemComparisonManager>) -> Void {
	//DFProfile();
	let def: DFManagedEffectItemDefinition = DFPlayerStateService.Get().GetItemManagedEffectDefinition(data.m_realItemRecord);
	let managedItem: Bool = false;
	let stacksFromItem: Int32;
	let maxStacksFromItem: Int32;

	if NotEquals(def.itemRecordTag, n"") {
		managedItem = true;
		if Equals(def.stackCountDef.mode, DFManagedEffectStackCountMode.Specific) {
			stacksFromItem = def.stackCountDef.countToApply;
			maxStacksFromItem = stacksFromItem;

		} else if Equals(def.stackCountDef.mode, DFManagedEffectStackCountMode.Random) {
			stacksFromItem = def.stackCountDef.countToApply;
			maxStacksFromItem = def.stackCountDef.countToApplyMax;
		}
	}

	for bar in this.m_bars {
		(inkWidgetRef.GetController(bar) as NewItemTooltipStatBarController).DarkFutureLastItemManagedEffectApplicableStackCount = stacksFromItem;
		(inkWidgetRef.GetController(bar) as NewItemTooltipStatBarController).DarkFutureLastItemManagedEffectApplicableStackCountMax = maxStacksFromItem;
	}

	wrappedMethod(data, comparisonData);

	for bar in this.m_bars {
		// Get the Separator widget. It's not populated in the m_separators property.
		let barNITTSBC: ref<NewItemTooltipStatBarController> = (inkWidgetRef.GetController(bar) as NewItemTooltipStatBarController);
		let parentCanvas: ref<inkCanvas> = inkWidgetRef.Get(barNITTSBC.m_background).GetParentWidget() as inkCanvas;
		for child in parentCanvas.children.children {
			if Equals(child.GetName(), n"separators") {
				// Show or hide the separator bars.
				if managedItem {
					child.SetVisible(false);
				} else {
					child.SetVisible(true);
				}
			}
		}
	}
}

//  Method that creates Alcohol item stat bars.
//
public func DarkFutureMakeAlcohol(statsManager: ref<UIInventoryItemStatsManager>, itemData: ref<gameItemData>, itemType: gamedataItemType) -> ref<UIInventoryItemWeaponBars> {
	//DFProfile();
	let BiocorruptionCondition: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let instance: ref<UIInventoryItemWeaponBars> = new UIInventoryItemWeaponBars();
    instance.m_type = DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureAlcohol");
    instance.m_itemType = itemType;

	let alcoholToleranceStackCount: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksByType(DFManagedEffectType.Alcohol);
	let alcoholActiveStackCount: Uint32 = PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Alcohol);
	let euphoriaBuildUpStackCount: Uint32 = PlayerStateService.GetAllManagedEffectEuphoriaActiveStacks();
	
	ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureAlcoholStacks"), Cast<Float>(alcoholToleranceStackCount + alcoholActiveStackCount), statsManager));
	
	if IsSystemEnabledAndRunning(BiocorruptionCondition) && BiocorruptionCondition.GetConditionLevel() > 0u && !BiocorruptionCondition.GetHasEuphoria() {
		ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksAlcohol"), Cast<Float>(euphoriaBuildUpStackCount), statsManager));
	}

    return instance;
}

//  Method that creates Nicotine item stat bars.
//
public func DarkFutureMakeNicotine(statsManager: ref<UIInventoryItemStatsManager>, itemData: ref<gameItemData>, itemType: gamedataItemType) -> ref<UIInventoryItemWeaponBars> {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let instance: ref<UIInventoryItemWeaponBars> = new UIInventoryItemWeaponBars();
    instance.m_type = DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureNicotine");
    instance.m_itemType = itemType;

	let nicotineToleranceStackCount: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksByType(DFManagedEffectType.Nicotine);
	let nicotineActiveStackCount: Uint32 = PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Nicotine);

	ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureNicotineStacks"), Cast<Float>(nicotineToleranceStackCount + nicotineActiveStackCount), statsManager));
    
	return instance;
}

//  Method that creates Caffeine item stat bars.
//
public func DarkFutureMakeCaffeine(statsManager: ref<UIInventoryItemStatsManager>, itemData: ref<gameItemData>, itemType: gamedataItemType) -> ref<UIInventoryItemWeaponBars> {
	//DFProfile();
	let instance: ref<UIInventoryItemWeaponBars> = new UIInventoryItemWeaponBars();
    instance.m_type = DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureCaffeinated");
    instance.m_itemType = itemType;

    let stackCount: Uint32 = DFPlayerStateService.Get().GetManagedEffectActiveStacksByType(DFManagedEffectType.Caffeine);
    ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureCaffeinatedStacks"), Cast<Float>(stackCount), statsManager));
    return instance;
}

//  Method that creates Narcotic item stat bars.
//
public func DarkFutureMakeNarcotic(statsManager: ref<UIInventoryItemStatsManager>, itemData: ref<gameItemData>, itemType: gamedataItemType) -> ref<UIInventoryItemWeaponBars> {
	//DFProfile();
	let BiocorruptionCondition: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let instance: ref<UIInventoryItemWeaponBars> = new UIInventoryItemWeaponBars();
    instance.m_type = DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureNarcotic");
    instance.m_itemType = itemType;

    let narcoticToleranceStackCount: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksByType(DFManagedEffectType.Narcotic);
	let narcoticActiveStackCount: Uint32 = PlayerStateService.GetManagedEffectActiveStacksByType(DFManagedEffectType.Narcotic);
	let euphoriaBuildUpStackCount: Uint32 = PlayerStateService.GetAllManagedEffectEuphoriaActiveStacks();

	ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureNarcoticStacks"), Cast<Float>(narcoticToleranceStackCount + narcoticActiveStackCount), statsManager));
	
	if IsSystemEnabledAndRunning(BiocorruptionCondition) && BiocorruptionCondition.GetConditionLevel() > 0u {
		ArrayPush(instance.Values, UIInventoryItemWeaponBar.MakeCurve(DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksNarcotic"), Cast<Float>(euphoriaBuildUpStackCount), statsManager));
	}
    
	return instance;
}

//  UIInventoryItemWeaponBars - If the item is an item that should show a stat bar, call the relevant method to create them.
//
@wrapMethod(UIInventoryItemWeaponBars)
public final static func Make(statsManager: ref<UIInventoryItemStatsManager>, itemData: ref<gameItemData>, itemType: gamedataItemType, type: UIInventoryItemWeaponBarsType) -> ref<UIInventoryItemWeaponBars> {
	//DFProfile();
	if itemData.HasTag(n"DarkFutureItemTooltipShowBars") {

        if itemData.HasTag(n"DarkFutureItemTooltipShowBarsAlcohol") {
            return DarkFutureMakeAlcohol(statsManager, itemData, itemType);

        } else if itemData.HasTag(n"DarkFutureItemTooltipShowBarsNicotine") {
            return DarkFutureMakeNicotine(statsManager, itemData, itemType);

        } else if itemData.HasTag(n"DarkFutureItemTooltipShowBarsCaffeine") {
            return DarkFutureMakeCaffeine(statsManager, itemData, itemType);

        } else if itemData.HasTag(n"DarkFutureItemTooltipShowBarsNarcotics") {
            return DarkFutureMakeNarcotic(statsManager, itemData, itemType);
        }
        
	} else {
		return wrappedMethod(statsManager, itemData, itemType, type);
	}
}

//  UIInventoryItemWeaponBars - Return the collection of displayed stat bars.
//
@wrapMethod(UIInventoryItemWeaponBars)
public final static func GetDisplayedStats(barsType: UIInventoryItemWeaponBarsType) -> [WeaponBarType] {
	//DFProfile();
	let result: array<WeaponBarType>;
	let BiocorruptionCondition: ref<DFBiocorruptionConditionSystem>;

	if Equals(barsType, DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureAlcohol")) {
		BiocorruptionCondition = DFBiocorruptionConditionSystem.Get();
		ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureAlcoholStacks"));

		if IsSystemEnabledAndRunning(BiocorruptionCondition) && BiocorruptionCondition.GetConditionLevel() > 0u && !BiocorruptionCondition.GetHasEuphoria() {
			ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksAlcohol"));
		}
		return result;

    } else if Equals(barsType, DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureNicotine")) {
		ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureNicotineStacks"));
		return result;
    
    } else if Equals(barsType, DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureCaffeinated")) {
		ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureCaffeinatedStacks"));
		return result;
    
    } else if Equals(barsType, DFEnum_UIInventoryItemWeaponBarsType(n"DarkFutureNarcotic")) {
		BiocorruptionCondition = DFBiocorruptionConditionSystem.Get();
        ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureNarcoticStacks"));

		if IsSystemEnabledAndRunning(BiocorruptionCondition) && BiocorruptionCondition.GetConditionLevel() > 0u && !BiocorruptionCondition.GetHasEuphoria() {
			ArrayPush(result, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksNarcotic"));
		}
		return result;

	} else {
		return wrappedMethod(barsType);
	}
}

//  NewItemTooltipStatBarController - Return the player-facing name of the stat bar widget.
//
@wrapMethod(NewItemTooltipStatBarController)
private final func BarTypeToName(barType: WeaponBarType) -> String {
	//DFProfile();
	if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureAlcoholStacks")) {
		return GetLocalizedTextByKey(n"DarkFutureAlcoholActiveEffectName");

    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNicotineStacks")) {
		return GetLocalizedTextByKey(n"DarkFutureCigaretteStatusEffectDisplayName");
    
    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNarcoticStacks")) {
		return GetLocalizedTextByKey(n"DarkFutureNarcoticStatusEffectDisplayName");
    
    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureCaffeinatedStacks")) {
		return GetLocalizedTextByKey(n"DarkFutureEffectNameCaffeinated");
	
	} else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksAlcohol")) || Equals(barType, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksNarcotic")) {
		return GetLocalizedTextByKey(n"DarkFutureEuphoriaBuildUpStatBarDisplayName");
	
	} else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureAlcoholTolerance")) || 
			  Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNicotineTolerance")) ||
			  Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNarcoticTolerance")) {
		
		return GetLocalizedTextByKey(n"DarkFutureToleranceStatsBarDisplayName");
	
	} else {
		return wrappedMethod(barType);
	}
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetActiveStackStatBarValues(bar: wref<UIInventoryItemWeaponBar>, effectType: DFManagedEffectType) -> Void {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();

	bar.Value = Cast<Float>(PlayerStateService.GetManagedEffectActiveStacksByType(effectType));
	bar.MaxValue = Cast<Float>(Cast<Int32>(PlayerStateService.GetManagedEffectActiveStacksAtThisAddictionStageByType(effectType)));
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetToleranceStackStatBarValues(bar: wref<UIInventoryItemWeaponBar>, effectType: DFManagedEffectType) -> Void {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	
	let toleranceStacksAtThisStage: Int32 = Cast<Int32>(PlayerStateService.GetManagedEffectToleranceStacksAtThisAddictionStageByType(effectType));
	let toleranceRemaining: Int32 = toleranceStacksAtThisStage - Cast<Int32>(PlayerStateService.GetManagedEffectToleranceStacksByType(effectType));
	bar.Value = Cast<Float>(toleranceRemaining);
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetEuphoriaBuildUpStackStatBarValues(bar: wref<UIInventoryItemWeaponBar>) -> Void {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();

	if IsSystemEnabledAndRunning(BiocorruptionConditionSystem) {
		let activeStacks: Uint32 = PlayerStateService.GetAllManagedEffectEuphoriaActiveStacks();
		bar.Value = Cast<Float>(activeStacks);
		bar.MaxValue = Cast<Float>(BiocorruptionConditionSystem.requiredBuildupForEuphoriaPerBiocorruptionLevel[Cast<Int32>(BiocorruptionConditionSystem.GetConditionLevel())]);
	}
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetEuphoriaBuildUpStackStatBarText(bar: wref<UIInventoryItemWeaponBar>) -> Void {
	//DFProfile();
	let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();

	if IsSystemEnabledAndRunning(BiocorruptionConditionSystem) {
		let blockedReason: DFEuphoriaBlockedReason = BiocorruptionConditionSystem.EuphoriaBlockedReason();
		if BiocorruptionConditionSystem.GetHasEuphoria() {
			inkWidgetRef.Get(this.m_statValue).SetTintColor(HDRColor(1.0, 1.0, 1.0, 1.0));
			inkTextRef.SetText(this.m_statValue, "");

		} else if NotEquals(blockedReason, DFEuphoriaBlockedReason.None) {
			if Equals(blockedReason, DFEuphoriaBlockedReason.AddictionTreatment) {
				inkWidgetRef.Get(this.m_statValue).SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
				inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureEuphoriaBlockedStatBarDescAddictionTreatment"));
			
			} else if Equals(blockedReason, DFEuphoriaBlockedReason.Cyberpsychosis) {
				inkWidgetRef.Get(this.m_statValue).SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
				inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureEuphoriaBlockedStatBarDescCyberpsychosis"));

			} else if Equals(blockedReason, DFEuphoriaBlockedReason.Overdose) {
				inkWidgetRef.Get(this.m_statValue).SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
				inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureEuphoriaBlockedStatBarDescOverdose"));
			
			} else if Equals(blockedReason, DFEuphoriaBlockedReason.Withdrawal) {
				inkWidgetRef.Get(this.m_statValue).SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
				inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureEuphoriaBlockedStatBarDescWithdrawal"));
			}
		} else {
			inkWidgetRef.Get(this.m_statValue).SetTintColor(HDRColor(1.0, 1.0, 1.0, 1.0));
			inkTextRef.SetText(this.m_statValue, "");
		}
	}
}

@addField(NewItemTooltipStatBarController)
public let DarkFuturePipPanel: ref<inkHorizontalPanel>;

@addField(NewItemTooltipStatBarController)
public let DarkFutureIconPanel: ref<inkHorizontalPanel>;

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetUpCustomIconOverlay(type: DFManagedEffectType) -> Void {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let activeStacks: Uint32 = PlayerStateService.GetManagedEffectActiveStacksAtThisAddictionStageByType(type);
	let toleranceStacks: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksAtThisAddictionStageByType(type);
	let toleranceStacksFilled: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksByType(type);
	let toleranceAvailable: Int32 = Cast<Int32>(toleranceStacks - toleranceStacksFilled);

	let toleranceStacksFromItem: Uint32;
	if toleranceAvailable > 0 {
		toleranceStacksFromItem = this.DarkFutureLastItemManagedEffectApplicableStackCount >= toleranceAvailable ? Cast<Uint32>(toleranceAvailable) : Cast<Uint32>(this.DarkFutureLastItemManagedEffectApplicableStackCountMax);
	} else {
		toleranceStacksFromItem = 0u;
	}

	let pipWidth: Float = ((1.0 / Cast<Float>(activeStacks + toleranceStacks)) * 654.0);
	
	let parentCanvas: ref<inkCanvas> = inkWidgetRef.Get(this.m_background).GetParentWidget() as inkCanvas;
	let hPanel: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	hPanel.SetName(n"DarkFutureIconPanel");

	hPanel.SetVisible(true);
	hPanel.Reparent(parentCanvas, 0);
	hPanel.SetAnchor(inkEAnchor.BottomLeft);
	hPanel.SetAnchorPoint(0.0, 1.0);
	hPanel.SetHAlign(inkEHorizontalAlign.Fill);
	hPanel.SetVAlign(inkEVerticalAlign.Fill);
	hPanel.SetSize(654.0, 16.0);
	hPanel.SetFitToContent(true);
	hPanel.SetAffectsLayoutWhenHidden(false);
	hPanel.SetChildMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
	this.DarkFutureIconPanel = hPanel;

	let i: Uint32 = 0u;
	while i < toleranceStacks {
		let toleranceRange: ref<inkCanvas> = new inkCanvas();
		toleranceRange.SetName(n"toleranceRange");
		toleranceRange.SetVisible(true);
		toleranceRange.Reparent(hPanel);
		toleranceRange.SetAnchor(inkEAnchor.TopLeft);
		toleranceRange.SetAnchorPoint(0.0, 0.0);
		toleranceRange.SetHAlign(inkEHorizontalAlign.Fill);
		toleranceRange.SetVAlign(inkEVerticalAlign.Fill);
		toleranceRange.SetSize(pipWidth, 12.0);
		toleranceRange.SetFitToContent(false);
		toleranceRange.SetAffectsLayoutWhenHidden(true);

		let icon: ref<inkImage> = new inkImage();
		icon.SetName(n"tolerancePipImage");
		icon.SetSize(pipWidth - 4.0, 12.0);
		icon.SetFitToContent(false);
		icon.SetAffectsLayoutWhenHidden(true);
		icon.SetAtlasResource(r"base\\gameplay\\gui\\common\\icons\\atlas_common.inkatlas");
		icon.SetTexturePart(n"ico_locked");
		//icon.SetBrushMirrorType(inkBrushMirrorType.Horizontal);
		if i < toleranceStacksFilled {
			icon.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
		} else if toleranceStacksFromItem > 0u && i < (toleranceStacksFilled + toleranceStacksFromItem) {
			icon.SetTintColor(HDRColor(0.113725498, 0.929411829, 0.513725519, 1.0));
		} else {
			icon.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MildRed));
		}
		icon.Reparent(toleranceRange);
		
		i += 1u;
	}

	i = 0u;
	while i < activeStacks {
		let activeRange: ref<inkCanvas> = new inkCanvas();
		activeRange.SetName(n"activeRange");
		activeRange.SetVisible(true);
		activeRange.Reparent(hPanel);
		activeRange.SetAnchor(inkEAnchor.TopLeft);
		activeRange.SetAnchorPoint(0.0, 0.0);
		activeRange.SetHAlign(inkEHorizontalAlign.Fill);
		activeRange.SetVAlign(inkEVerticalAlign.Fill);
		activeRange.SetSize(pipWidth, 12.0);
		activeRange.SetFitToContent(false);
		activeRange.SetAffectsLayoutWhenHidden(true);

		i += 1u;
	}
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetUpCustomSeparatorOverlayByType(type: DFManagedEffectType) -> Void {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let activeStacks: Uint32 = PlayerStateService.GetManagedEffectActiveStacksAtThisAddictionStageByType(type);
	let toleranceStacks: Uint32 = PlayerStateService.GetManagedEffectToleranceStacksAtThisAddictionStageByType(type);

	this.DarkFutureSetUpCustomSeparatorOverlay(activeStacks, toleranceStacks);
}

@addMethod(NewItemTooltipStatBarController)
public final func DarkFutureSetUpCustomSeparatorOverlay(activeStacks: Uint32, toleranceStacks: Uint32) -> Void {
	//DFProfile();
	let pipWidth: Float = ((1.0 / Cast<Float>(activeStacks + toleranceStacks)) * 654.0) - 5.0;
	
	let parentCanvas: ref<inkCanvas> = inkWidgetRef.Get(this.m_background).GetParentWidget() as inkCanvas;
	let hPanel: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	let separator: ref<inkRectangle>;
	hPanel.SetName(n"DarkFuturePipPanel");

	hPanel.SetVisible(true);
	hPanel.Reparent(parentCanvas, 0);
	hPanel.SetAnchor(inkEAnchor.BottomLeft);
	hPanel.SetAnchorPoint(0.0, 1.0);
	hPanel.SetHAlign(inkEHorizontalAlign.Fill);
	hPanel.SetVAlign(inkEVerticalAlign.Fill);
	hPanel.SetSize(654.0, 16.0);
	hPanel.SetFitToContent(true);
	hPanel.SetAffectsLayoutWhenHidden(false);
	hPanel.SetChildMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
	this.DarkFuturePipPanel = hPanel;

	let i: Uint32 = 0u;
	while i < toleranceStacks {
		let toleranceRange: ref<inkRectangle> = new inkRectangle();
		toleranceRange.SetName(n"toleranceRange");
		toleranceRange.SetVisible(true);
		toleranceRange.Reparent(hPanel);
		toleranceRange.SetOpacity(1.0);
		toleranceRange.SetTintColor(HDRColor(0.165, 0.165, 0.165, 1.0));
		toleranceRange.SetAnchor(inkEAnchor.TopLeft);
		toleranceRange.SetAnchorPoint(0.0, 0.0);
		toleranceRange.SetHAlign(inkEHorizontalAlign.Fill);
		toleranceRange.SetVAlign(inkEVerticalAlign.Fill);
		toleranceRange.SetSize(pipWidth, 1.0);
		toleranceRange.SetFitToContent(false);
		toleranceRange.SetAffectsLayoutWhenHidden(true);

		separator = new inkRectangle();
		separator.SetName(n"separator");
		separator.SetVisible(true);
		separator.Reparent(hPanel);
		separator.SetTintColor(HDRColor(0.0, 0.0, 0.0, 0.0));
		separator.SetOpacity(1.0);
		separator.SetAnchor(inkEAnchor.TopLeft);
		separator.SetAnchorPoint(0.0, 0.0);
		separator.SetHAlign(inkEHorizontalAlign.Fill);
		separator.SetVAlign(inkEVerticalAlign.Fill);
		separator.SetSize(5.0, 12.0);
		separator.SetFitToContent(false);
		separator.SetAffectsLayoutWhenHidden(false);

		i += 1u;
	}

	i = 0u;
	while i < activeStacks {
		let activeRange: ref<inkRectangle> = new inkRectangle();
		activeRange.SetName(n"activeRange");
		activeRange.SetVisible(true);
		activeRange.Reparent(hPanel);
		activeRange.SetOpacity(0.0);
		activeRange.SetAnchor(inkEAnchor.TopLeft);
		activeRange.SetAnchorPoint(0.0, 0.0);
		activeRange.SetHAlign(inkEHorizontalAlign.Fill);
		activeRange.SetVAlign(inkEVerticalAlign.Fill);
		activeRange.SetSize(pipWidth, 12.0);
		activeRange.SetFitToContent(false);
		activeRange.SetAffectsLayoutWhenHidden(true);

		let isLast: Bool = i == (activeStacks - 1u);

		if !isLast {
			separator = new inkRectangle();
			separator.SetName(n"separator");
			separator.SetVisible(true);
			separator.Reparent(hPanel);
			separator.SetTintColor(HDRColor(0.0, 0.0, 0.0, 0.0));
			separator.SetOpacity(1.0);
			separator.SetAnchor(inkEAnchor.TopLeft);
			separator.SetAnchorPoint(0.0, 0.0);
			separator.SetHAlign(inkEHorizontalAlign.Fill);
			separator.SetVAlign(inkEVerticalAlign.Fill);
			separator.SetSize(5.0, 12.0);
			separator.SetFitToContent(false);
			separator.SetAffectsLayoutWhenHidden(false);
		}

		i += 1u;
	}
}

//  NewItemTooltipStatBarController - (Called on every hover event) Additional logic to pull relevant player data for the stat bar
//                                    and populate the numerical stat value.
//
@wrapMethod(NewItemTooltipStatBarController)
public final func Setup(itemType: gamedataItemType, bar: wref<UIInventoryItemWeaponBar>, comparedBar: wref<UIInventoryItemWeaponBar>) -> Void {
	//DFProfile();
	if IsDefined(this.DarkFuturePipPanel) {
		(this.DarkFuturePipPanel.GetParentWidget() as inkCanvas).RemoveChildByName(n"DarkFuturePipPanel");
	}

	if IsDefined(this.DarkFutureIconPanel) {
		(this.DarkFutureIconPanel.GetParentWidget() as inkCanvas).RemoveChildByName(n"DarkFutureIconPanel");
	}

	if Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureCaffeinatedStacks")) {
		this.DarkFutureSetActiveStackStatBarValues(bar, DFManagedEffectType.Caffeine);
		wrappedMethod(itemType, bar, comparedBar);
		this.DarkFutureSetUpCustomSeparatorOverlayByType(DFManagedEffectType.Caffeine);
		this.DarkFutureSetUpCustomIconOverlay(DFManagedEffectType.Caffeine);

	} else if Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureAlcoholStacks")) {
		this.DarkFutureSetActiveStackStatBarValues(bar, DFManagedEffectType.Alcohol);
		wrappedMethod(itemType, bar, comparedBar);
		this.DarkFutureSetUpCustomSeparatorOverlayByType(DFManagedEffectType.Alcohol);
		this.DarkFutureSetUpCustomIconOverlay(DFManagedEffectType.Alcohol);
			
    } else if Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureNicotineStacks")) {
		this.DarkFutureSetActiveStackStatBarValues(bar, DFManagedEffectType.Nicotine);
		wrappedMethod(itemType, bar, comparedBar);
		this.DarkFutureSetUpCustomSeparatorOverlayByType(DFManagedEffectType.Nicotine);
		this.DarkFutureSetUpCustomIconOverlay(DFManagedEffectType.Nicotine);
    
    } else if Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureNarcoticStacks")) {
		this.DarkFutureSetActiveStackStatBarValues(bar, DFManagedEffectType.Narcotic);
		wrappedMethod(itemType, bar, comparedBar);
		this.DarkFutureSetUpCustomSeparatorOverlayByType(DFManagedEffectType.Narcotic);
		this.DarkFutureSetUpCustomIconOverlay(DFManagedEffectType.Narcotic);
	
	} else if Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksAlcohol")) || Equals(bar.Type, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksNarcotic")) {
		this.DarkFutureSetEuphoriaBuildUpStackStatBarValues(bar);
		wrappedMethod(itemType, bar, comparedBar);
		this.DarkFutureSetEuphoriaBuildUpStackStatBarText(bar);

		let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.Get();
		let maxBuildUpStackCount: Uint32 = BiocorruptionConditionSystem.requiredBuildupForEuphoriaPerBiocorruptionLevel[Cast<Int32>(BiocorruptionConditionSystem.GetConditionLevel())];
		this.DarkFutureSetUpCustomSeparatorOverlay(maxBuildUpStackCount, 0u);
	} else {
		wrappedMethod(itemType, bar, comparedBar);
	}
}

@addMethod(NewItemTooltipStatBarController)
private final func DarkFutureGetAnimateBarActiveStackPercentages(type: DFManagedEffectType) -> DFStatsBarData {
	//DFProfile();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.Get();
	let percentage: Float = 0.0;
	let comparedPercentage: Float = 0.0;

	let managedEffect: DFManagedEffect = PlayerStateService.GetManagedEffectByType(type);
	let maxActiveStackCount: Int32 = Cast<Int32>(PlayerStateService.GetManagedEffectActiveStacksAtThisAddictionStageByType(type));
	let maxToleranceStackCount: Int32 = Cast<Int32>(PlayerStateService.GetManagedEffectToleranceStacksAtThisAddictionStageByType(type));
	let stacksFromItem: Int32 = this.DarkFutureLastItemManagedEffectApplicableStackCount;
	let maxStacksFromItem: Int32 = this.DarkFutureLastItemManagedEffectApplicableStackCountMax;
	let activeStacksAlreadyApplied: Int32 = ArraySize(managedEffect.activeEffectEnergyChanges);
	let toleranceStacksAlreadyApplied: Int32 = managedEffect.toleranceEffectCount;
	let totalStacksAlreadyApplied: Int32 = activeStacksAlreadyApplied + toleranceStacksAlreadyApplied;

	percentage = MinF(Cast<Float>(activeStacksAlreadyApplied + toleranceStacksAlreadyApplied) / Cast<Float>(maxActiveStackCount + maxToleranceStackCount), 1.0);
	let rawComparedPercentage: Float;
	let rawComparedPercentageMax: Float;
	let comparedPercentageMax: Float;

	if stacksFromItem == 0 {
		comparedPercentage = 0.0;

	} else {
		rawComparedPercentage = Cast<Float>(stacksFromItem) / Cast<Float>(maxActiveStackCount + maxToleranceStackCount);
		rawComparedPercentageMax = Cast<Float>(maxStacksFromItem) / Cast<Float>(maxActiveStackCount + maxToleranceStackCount);
		comparedPercentage = MinF(rawComparedPercentage, 1.0 - percentage);
		comparedPercentageMax = MinF(rawComparedPercentageMax, 1.0 - percentage);
	}

	let r: DFStatsBarData;
	r.percentage = percentage;
	r.comparedPercentage = comparedPercentageMax >= comparedPercentage ? comparedPercentageMax : comparedPercentage;

	// Cyberware bonus for over limit risk calculation.
	if Equals(type, DFManagedEffectType.Narcotic) {
		let CyberwareService: ref<DFCyberwareService> = DFCyberwareService.Get();
		let maxTotalStackCount: Int32 = maxActiveStackCount + maxToleranceStackCount;
		let cyberwareBonus: Int32 = totalStacksAlreadyApplied < maxTotalStackCount ? CyberwareService.GetNarcoticExcessStacksAllowedBonus() : 0;
		let stacksOverMin: Int32 = Max(((stacksFromItem + totalStacksAlreadyApplied) - cyberwareBonus) - maxTotalStackCount, 0);
		let stacksOverMax: Int32 = Max(((maxStacksFromItem + totalStacksAlreadyApplied) - cyberwareBonus) - maxTotalStackCount, 0);
		
		r.overLimit = stacksOverMin > 0;
		r.overLimitRisk = stacksOverMax > 0;
	
	} else {
		r.overLimit = percentage + rawComparedPercentage > 1.0;
		r.overLimitRisk = percentage + rawComparedPercentageMax > 1.0;
	}

	
	return r;
}

@addMethod(NewItemTooltipStatBarController)
private final func DarkFutureGetAnimateBarEuphoriaStackPercentages(type: DFManagedEffectType) -> DFStatsBarData {
	//DFProfile();
	let gameInstance: GameInstance = GetGameInstance();
	let PlayerStateService: ref<DFPlayerStateService> = DFPlayerStateService.GetInstance(gameInstance);
	let BiocorruptionConditionSystem: ref<DFBiocorruptionConditionSystem> = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
	let percentage: Float;
	let comparedPercentage: Float;

	let managedEffect: DFManagedEffect = PlayerStateService.GetManagedEffectByType(type);
	let stacksFromItem: Int32 = this.DarkFutureLastItemManagedEffectApplicableStackCountMax;
	let maxActiveStackCount: Int32 = Cast<Int32>(PlayerStateService.GetManagedEffectActiveStacksAtThisAddictionStageByType(type));
	let maxToleranceStackCount: Int32 = Cast<Int32>(PlayerStateService.GetManagedEffectToleranceStacksAtThisAddictionStageByType(type));
	let euphoriaBuildUpStackCount: Int32 = Cast<Int32>(PlayerStateService.GetAllManagedEffectEuphoriaActiveStacks());
	let activeStacksAlreadyApplied: Int32 = ArraySize(managedEffect.activeEffectEnergyChanges);

	let maxBuildUpStackCount: Uint32 = BiocorruptionConditionSystem.requiredBuildupForEuphoriaPerBiocorruptionLevel[Cast<Int32>(BiocorruptionConditionSystem.GetConditionLevel())];

	if BiocorruptionConditionSystem.GetHasEuphoria() {
		percentage = 1.0;
	} else {
		percentage = MinF(Cast<Float>(euphoriaBuildUpStackCount) / Cast<Float>(maxBuildUpStackCount), 1.0);
	}

	if stacksFromItem == 0 {
		comparedPercentage = 0.0;

	} else {
		if percentage < 1.0 {
			let clampedByMaxActive: Int32;
			if managedEffect.toleranceEffectCount < maxToleranceStackCount {
				let afterTolerance: Int32 = (managedEffect.toleranceEffectCount + stacksFromItem) - maxToleranceStackCount;
				if afterTolerance > 0 {
					clampedByMaxActive = Min(afterTolerance, maxActiveStackCount - activeStacksAlreadyApplied);
					comparedPercentage = MinF(Cast<Float>(clampedByMaxActive) / Cast<Float>(maxBuildUpStackCount), 1.0 - percentage);
				}
			} else {
				clampedByMaxActive = Min(stacksFromItem, maxActiveStackCount - activeStacksAlreadyApplied);
				comparedPercentage = MinF(Cast<Float>(clampedByMaxActive) / Cast<Float>(maxBuildUpStackCount), 1.0 - percentage);
			}
		}
	}

	let r: DFStatsBarData;
	r.percentage = percentage;
	r.comparedPercentage = comparedPercentage;
	return r;
}

//  NewItemTooltipStatBarController - (Called on every hover event) Additional logic to correctly populate the bar percentage.
//
@wrapMethod(NewItemTooltipStatBarController)
private final func AnimateBars(barType: WeaponBarType, percentage: Float, comparedPercentage: Float, isBetter: Bool) -> Void {
	//DFProfile();
	let statsBarData: DFStatsBarData;
	let useStatsBarData: Bool = false;
	let isEuphoria: Bool = false;
	let ignoreOverLimitWarning: Bool = false;

	if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureAlcoholStacks")) {
		statsBarData = this.DarkFutureGetAnimateBarActiveStackPercentages(DFManagedEffectType.Alcohol);
		useStatsBarData = true;
    
    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNicotineStacks")) {
		statsBarData = this.DarkFutureGetAnimateBarActiveStackPercentages(DFManagedEffectType.Nicotine);
		useStatsBarData = true;
		ignoreOverLimitWarning = true;
    
    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureCaffeinatedStacks")) {
		statsBarData = this.DarkFutureGetAnimateBarActiveStackPercentages(DFManagedEffectType.Caffeine);
		useStatsBarData = true;
		ignoreOverLimitWarning = true;
    
    } else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureNarcoticStacks")) {
		statsBarData = this.DarkFutureGetAnimateBarActiveStackPercentages(DFManagedEffectType.Narcotic);
		useStatsBarData = true;

	} else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksAlcohol")) {
		statsBarData = this.DarkFutureGetAnimateBarEuphoriaStackPercentages(DFManagedEffectType.Alcohol);
		useStatsBarData = true;
		isEuphoria = true;
	
	} else if Equals(barType, DFEnum_WeaponBarType(n"DarkFutureEuphoriaBuildUpStacksNarcotic")) {
		statsBarData = this.DarkFutureGetAnimateBarEuphoriaStackPercentages(DFManagedEffectType.Narcotic);
		useStatsBarData = true;
		isEuphoria = true;
	}

	if useStatsBarData {
		if statsBarData.overLimit && !isEuphoria && !ignoreOverLimitWarning {
			inkWidgetRef.Get(this.m_statValue).SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
			inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureBarLabelStackLimitExceeded"));

		} else if statsBarData.overLimitRisk && !isEuphoria && !ignoreOverLimitWarning {
			inkWidgetRef.Get(this.m_statValue).SetTintColor(HDRColor(1.28, 0.32, 0.0, 1.0));
			inkTextRef.SetText(this.m_statValue, GetLocalizedTextByKey(n"DarkFutureBarLabelStackLimitRisk"));

		} else {
			inkWidgetRef.Get(this.m_statValue).SetTintColor(HDRColor(1.0, 1.0, 1.0, 1.0));
			inkTextRef.SetText(this.m_statValue, "");
		}
		wrappedMethod(barType, statsBarData.percentage, statsBarData.comparedPercentage, true);
	} else {
		inkWidgetRef.Get(this.m_statValue).SetTintColor(HDRColor(1.0, 1.0, 1.0, 1.0));
		wrappedMethod(barType, percentage, comparedPercentage, isBetter);
	}
}
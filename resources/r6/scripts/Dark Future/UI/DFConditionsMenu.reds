// -----------------------------------------------------------------------------
// DFConditionsMenu
// -----------------------------------------------------------------------------
//
// - Manages the display of the Conditions Menu.
//

module DarkFuture.UI

import DarkFuture.Logging.*
import DarkFuture.Conditions.{
    DFInjuryConditionSystem,
    DFHumanityLossConditionSystem
    //DFBiocorruptionConditionSystem
}
import DarkFuture.System.{
    DFSystem,
    IsSystemEnabledAndRunning
}
import DarkFuture.Settings.DFSettings

public enum DFConditionType {
    Invalid = 0,
	HumanityLoss = 1,
    Injury = 2,
    Biocorruption = 3
}

public enum DFConditionArea {
    HumanityLoss_Area_01 = 0,
    HumanityLoss_Area_02 = 1,
    HumanityLoss_Area_03 = 2,
    HumanityLoss_Area_04 = 3,
    Injury_Area_01 = 4,
    Injury_Area_02 = 5,
    Injury_Area_03 = 6,
    Injury_Area_04 = 7,
    Biocorruption_Area_01 = 8,
    Biocorruption_Area_02 = 9,
    Biocorruption_Area_03 = 10,
    Biocorruption_Area_04 = 11
}

public class DFConditionHoverOver extends Event {
  public let widget: wref<inkWidget>;
  public let title: String;
  public let description: String;
}

public class DFConditionHoverOut extends Event {}

public class ConditionEffectHoverOver extends Event {
  public let data: wref<DFConditionEffectDisplayData>;
  public let widget: wref<inkWidget>;
}

public class DFConditionEffectHoverOut extends Event {}

public class DFConditionDisplayData extends IDisplayData {
    public let condition: DFConditionType;
    public let index: Int32;
    public let areas: [ref<DFAreaDisplayData>];
    public let conditionEffectsData: [ref<DFConditionEffectDisplayData>];
    public let localizedName: String;
    public let level: Int32;
    public let maxLevel: Int32;
    public let expPoints: Int32;
    public let maxExpPoints: Int32;
    public let unlockedLevel: Int32;

    public func CreateTooltipData() -> ref<DFConditionTooltipData> {
        //DFProfile();
        let data: ref<DFConditionTooltipData> = new DFConditionTooltipData();
        data.conditionType = this.condition;
        return data;
    }
}

public class DFConditionEffectDisplayData extends IDisplayData {
    public let level: Int32;
    public let effectName: String;
    public let description: String;
    public let icon: CName;
    public let locPackage: ref<UILocalizationDataPackage>;
    public let descPackage: ref<UILocalizationDataPackage>;
    public let isLock: Bool;
}

public class DFAreaDisplayData extends IDisplayData {
    public let locked: Bool;
    public let condition: DFConditionType;
    public let area: DFConditionArea;
}

public class DFConditionTooltipData extends BasePerksMenuTooltipData {
    public let conditionType: DFConditionType;
    public let conditionData: ref<DFConditionDisplayData>;
}

class InsertConditionMenu extends ScriptableService {
    private cb func OnLoad() {
        //DFProfile();
        GameInstance.GetCallbackSystem()
        .RegisterCallback(n"Resource/Ready", this, n"OnMenuResourceReady")
        .AddTarget(ResourceTarget.Path(r"base\\gameplay\\gui\\fullscreen\\menu.inkmenu"));
    }

    private cb func OnMenuResourceReady(event: ref<ResourceEvent>) {
        //DFProfile();
        let resource: ref<inkMenuResource> = event.GetResource() as inkMenuResource;
        let newMenuEntry: inkMenuEntry;
        newMenuEntry.depth = 0u;
        newMenuEntry.spawnMode = inkSpawnMode.SingleAndMultiplayer;
        newMenuEntry.isAffectedByFadeout = true;
        newMenuEntry.menuWidget *= r"darkfuture\\gui\\conditions.inkwidget";
        newMenuEntry.name = n"darkfuture_conditions_menu";
        ArrayPush(resource.menusEntries, newMenuEntry);
    }
}

@addMethod(MenuHubLogicController)
private final func IsAnyConditionSystemEnabled() -> Bool {
    //DFProfile();
    if IsSystemEnabledAndRunning(DFInjuryConditionSystem.Get()) || IsSystemEnabledAndRunning(DFHumanityLossConditionSystem.Get()) {
        return true;
    }

    return false;
}

@wrapMethod(MenuHubLogicController)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
    let r: Bool = wrappedMethod();
    
    if this.IsAnyConditionSystemEnabled() {
        this.AddConditionsMenuItem();
    }
    
    return r;
}

@if(ModuleExists("StealthRunner"))
public func DFIsStealthRunnerInstalled() -> Bool {
	//DFProfile();
	return true;
}

@if(!ModuleExists("StealthRunner"))
public func DFIsStealthRunnerInstalled() -> Bool {
	//DFProfile();
	return false;
}

@addMethod(MenuHubLogicController)
private final func AddConditionsMenuItem() -> Void {
    //DFProfile();
  let isPlayerHardwareDisabled: Bool = HubMenuUtility.IsPlayerHardwareDisabled(GetPlayer(GetGameInstance()));
  let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
  let container: ref<inkCompoundWidget> = root.GetWidgetByPathName(n"mainMenu/buttonsContainer/panel_character") as inkCompoundWidget;

  let conditionsMenuButton: ref<inkWidget> = this.SpawnFromLocal(container, n"menu_button");

  if DFIsStealthRunnerInstalled() {
    conditionsMenuButton.SetMargin(inkMargin(0.0, 670.0, 0.0, 0.0));
  } else {
    conditionsMenuButton.SetMargin(inkMargin(0.0, 500.0, 0.0, 0.0));
  }
  conditionsMenuButton.SetName(n"DarkFuture_Conditions");

  let data: MenuData;
  data.disabled = isPlayerHardwareDisabled;
  data.fullscreenName = n"darkfuture_conditions_menu";
  data.identifier = 52;
  data.parentIdentifier = 2;
  data.label = GetLocalizedTextByKey(n"DarkFutureConditionsMenuItem");
  data.icon = n"ico_condition_hub";
  let controller: ref<MenuItemController> = conditionsMenuButton.GetController() as MenuItemController;
  controller.Init(data);
}

@wrapMethod(MenuItemController)
public final func Init(const menuData: script_ref<MenuData>) -> Void {
    //DFProfile();
    if StrBeginsWith(NameToString(Deref(menuData).fullscreenName), "darkfuture_") {
        inkImageRef.SetAtlasResource(this.m_icon, r"darkfuture\\condition_images\\condition_assets.inkatlas");
        wrappedMethod(menuData);
    } else {
        wrappedMethod(menuData);
    }
}

public class ConditionsMenuController extends gameuiMenuGameController {
    private let m_conditionsScreenContainer: inkWidgetRef;
    private let m_conditionsScreenController: ref<ConditionsLogicController>;
    private let m_buttonHintsManagerRef: inkWidgetRef;
    private let m_buttonHintsController: wref<ButtonHints>;
    private let m_tooltipsManagerRef: inkWidgetRef;
    private let m_tooltipsManager: wref<gameuiTooltipsManager>;
    private let m_screenIntroAnimProxy: ref<inkAnimProxy>;

    public cb func OnInitialize() -> Bool {
        //DFProfile();
        this.m_buttonHintsController = this.SpawnFromExternal(inkWidgetRef.Get(this.m_buttonHintsManagerRef), r"base\\gameplay\\gui\\common\\buttonhints.inkwidget", n"Root").GetController() as ButtonHints;
        this.m_buttonHintsController.AddButtonHint(n"back", "Common-Access-Close");
        this.m_tooltipsManager = inkWidgetRef.GetControllerByType(this.m_tooltipsManagerRef, n"gameuiTooltipsManager") as gameuiTooltipsManager;
        this.m_tooltipsManager.Setup(ETooltipsStyle.Menus);
        this.AsyncSpawnFromLocal(inkWidgetRef.Get(this.m_conditionsScreenContainer), n"ConditionsScreen", this, n"OnConditionsScreenSpawned");
        super.OnInitialize();
    }

    private final func ToggleConditionsScreen(show: Bool) -> Void {
        //DFProfile();
        inkWidgetRef.SetVisible(this.m_conditionsScreenContainer, show);
        this.m_screenIntroAnimProxy = this.PlayScreenIntro();
    }

    private final func PlayScreenIntro() -> ref<inkAnimProxy> {
        //DFProfile();
        this.StopScreenAnims();
        return this.PlayLibraryAnimationOnAutoSelectedTargets(n"panel_skills_intro", this.m_conditionsScreenController.GetRootWidget());
    }

    private final func IsPerkScreenAnimPLaying() -> Bool {
        //DFProfile();
        return IsDefined(this.m_screenIntroAnimProxy) && this.m_screenIntroAnimProxy.IsPlaying();
    }

    private final func StopScreenAnims() -> Void {
        //DFProfile();
        if IsDefined(this.m_screenIntroAnimProxy) && this.m_screenIntroAnimProxy.IsPlaying() {
            this.m_screenIntroAnimProxy.UnregisterFromAllCallbacks(inkanimEventType.OnFinish);
            this.m_screenIntroAnimProxy.GotoEndAndStop();
        };
    }

    private cb func OnConditionsScreenSpawned(widget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
        //DFProfile();
        this.m_conditionsScreenController = widget.GetController() as ConditionsLogicController;
        if IsDefined(this.m_conditionsScreenController) {
            this.m_conditionsScreenController.Initialize();
            this.ToggleConditionsScreen(true);
        }
    }

    protected cb func OnConditionHoverOver(evt: ref<DFConditionHoverOver>) -> Bool {
        //DFProfile();
        let tooltipData: ref<MessageTooltipData> = new MessageTooltipData();
        tooltipData.Title = evt.title;
        tooltipData.Description = evt.description;
        this.m_tooltipsManager.ShowTooltipAtWidget(n"descriptionTooltip", evt.widget, tooltipData, gameuiETooltipPlacement.LeftCenter, false, inkMargin(0.00, 0.00, 40.00, 0.00));
    }

    protected cb func OnConditionHoverOut(evt: ref<DFConditionHoverOut>) -> Bool {
        //DFProfile();
        this.m_tooltipsManager.HideTooltips();
    }

    protected cb func OnConditionEffectHoverOver(evt: ref<ConditionEffectHoverOver>) -> Bool {
        //DFProfile();
        let tooltipData: ref<MessageTooltipData> = new MessageTooltipData();
        tooltipData.Title = evt.data.effectName;
        tooltipData.Description = evt.data.description;
        this.m_tooltipsManager.ShowTooltipAtWidget(n"descriptionTooltip", evt.widget, tooltipData, gameuiETooltipPlacement.RightCenter, false, inkMargin(40.00, 0.00, 0.00, 0.00));
    }

    protected cb func OnConditionEffectHoverOut(evt: ref<DFConditionEffectHoverOut>) -> Bool {
        //DFProfile();
        this.m_tooltipsManager.HideTooltips();
    }
}

public class ConditionsLogicController extends inkLogicController {
  private let m_virtualGridContainer: inkVirtualCompoundRef;
  private let m_scrollBarContainer: inkWidgetRef;
  private let m_virtualGrid: wref<inkVirtualGridController>;
  private let m_dataSource: ref<ScriptableDataSource>;
  private let m_itemsClassifier: ref<inkVirtualItemTemplateClassifier>;
  private let m_scrollBar: wref<inkScrollController>;
  private let m_dataManager: wref<PlayerDevelopmentDataManager>;
  private let m_initialized: Bool;
  private let virtualItems: [ref<IScriptable>];

    protected cb func OnUninitialize() -> Bool {
        //DFProfile();
        let controller: wref<ConditionBarLogicController>;
        let i: Int32;
        this.UnregisterData();
        i = 0;
        while i < inkCompoundRef.GetNumChildren(this.m_virtualGridContainer) {
            controller = inkCompoundRef.GetWidgetByIndex(this.m_virtualGridContainer, i).GetController() as ConditionBarLogicController;
            controller.UnregisterAllCallbacks();
            i += 1;
        };
    }

    public final func UnregisterData() -> Void {
        //DFProfile();
        this.m_virtualGrid.SetClassifier(null);
        this.m_virtualGrid.SetSource(null);
        this.m_itemsClassifier = null;
        this.m_dataSource = null;
    }

    public final func Initialize() -> Void {
        //DFProfile();
        if !this.m_initialized {
            this.m_virtualGrid = inkWidgetRef.GetControllerByType(this.m_virtualGridContainer, n"inkVirtualGridController") as inkVirtualGridController;
            this.m_dataSource = new ScriptableDataSource();
            this.m_itemsClassifier = new inkVirtualItemTemplateClassifier();
            this.m_virtualGrid.SetClassifier(this.m_itemsClassifier);
            this.m_virtualGrid.SetSource(this.m_dataSource);

            let index: Int32 = 0;
            if IsSystemEnabledAndRunning(DFInjuryConditionSystem.Get()) {
                let injuryDisplayData: ref<DFConditionDisplayData> = DFInjuryConditionSystem.Get().GetConditionDisplayData(index);
                if IsDefined(injuryDisplayData) {
                    ArrayPush(this.virtualItems, injuryDisplayData);
                    index += 1;
                }
            }

            if IsSystemEnabledAndRunning(DFHumanityLossConditionSystem.Get()) {
                let humanityLossDisplayData: ref<DFConditionDisplayData> = DFHumanityLossConditionSystem.Get().GetConditionDisplayData(index);
                if IsDefined(humanityLossDisplayData) {
                    ArrayPush(this.virtualItems, humanityLossDisplayData);
                    index += 1;
                }
            }

            /*if IsSystemEnabledAndRunning(DFBiocorruptionConditionSystem.Get()) {
                let biocorruptionDisplayData: ref<DFConditionDisplayData> = DFBiocorruptionConditionSystem.Get().GetConditionDisplayData(index);
                if IsDefined(biocorruptionDisplayData) {
                    ArrayPush(this.virtualItems, biocorruptionDisplayData);
                    index += 1;
                }
            }*/

            this.m_dataSource.Reset(this.virtualItems);
        };
        this.m_initialized = true;
    }
}

public class ConditionBarLogicController extends inkVirtualCompoundItemController {
    private let m_statsProgressWidget: inkWidgetRef;
    private let m_levelsContainer: inkCompoundRef;
    private let m_data: ref<DFConditionDisplayData>;
    private let m_requestedConditions: Int32;
    private let m_statsProgressController: wref<StatsProgressController>;
    private let m_levelsControllers: [wref<ConditionLevelLogicController>];

    protected cb func OnInitialize() -> Bool {
        //DFProfile();
        this.m_statsProgressController = inkWidgetRef.GetController(this.m_statsProgressWidget) as StatsProgressController;
        inkWidgetRef.RegisterToCallback(this.m_statsProgressWidget, n"OnHoverOver", this, n"OnConditionHoverOver");
        inkWidgetRef.RegisterToCallback(this.m_statsProgressWidget, n"OnHoverOut", this, n"OnConditionHoverOut");
        this.isNavigalbe = false;
    }

    protected cb func OnDataChanged(value: Variant) -> Bool {
        //DFProfile();
        this.m_data = FromVariant<ref<IScriptable>>(value) as DFConditionDisplayData;
        if IsDefined(this.m_data) {
            let asProficiencyDisplayData: ref<ProficiencyDisplayData> = new ProficiencyDisplayData();
            asProficiencyDisplayData.m_expPoints = this.m_data.expPoints;
            asProficiencyDisplayData.m_maxExpPoints = this.m_data.maxExpPoints;
            asProficiencyDisplayData.m_level = this.m_data.level;
            asProficiencyDisplayData.m_maxLevel = this.m_data.maxLevel;
            asProficiencyDisplayData.m_unlockedLevel = this.m_data.unlockedLevel;
            asProficiencyDisplayData.m_localizedName = this.m_data.localizedName;

            this.m_statsProgressController.SetProfiencyLevel(asProficiencyDisplayData);
            this.UpdateConditionsCount();
        };
    }

    public final func UnregisterAllCallbacks() -> Void {
        //DFProfile();
        let i: Int32 = 0;
        while i < ArraySize(this.m_levelsControllers) {
            this.m_levelsControllers[i].UnregisterFromCallback(n"OnHoverOver", this, n"OnHoverOver");
            this.m_levelsControllers[i].UnregisterFromCallback(n"OnHoverOut", this, n"OnHoverOut");
            i += 1;
        };
        inkWidgetRef.UnregisterFromCallback(this.m_statsProgressWidget, n"OnHoverOver", this, n"OnConditionHoverOver");
        inkWidgetRef.UnregisterFromCallback(this.m_statsProgressWidget, n"OnHoverOut", this, n"OnConditionHoverOut");
    }

    private final func UpdateConditionsCount() -> Void {
        //DFProfile();
        let i: Int32 = 0;
        let counter: Int32 = 0;
        let limit: Int32 = 4;
        while i < limit {
            this.SetConditionLevelData(this.m_levelsControllers[counter], this.m_data.conditionEffectsData[i]);
            counter += 1;
            i += 1;
        };
        
        while this.m_requestedConditions < limit {
            this.AsyncSpawnFromLocal(inkWidgetRef.Get(this.m_levelsContainer), n"ConditionLevel", this, n"OnConditionLevelSpawned");
            this.m_requestedConditions += 1;
        };
    }

    protected cb func OnConditionLevelSpawned(widget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
        //DFProfile();
        let index: Int32;
        ArrayPush(this.m_levelsControllers, widget.GetController() as ConditionLevelLogicController);
        index = ArraySize(this.m_levelsControllers) - 1;
        this.SetConditionLevelData(this.m_levelsControllers[index], this.m_data.conditionEffectsData[index]);
        this.m_levelsControllers[index].RegisterToCallback(n"OnHoverOver", this, n"OnHoverOver");
        this.m_levelsControllers[index].RegisterToCallback(n"OnHoverOut", this, n"OnHoverOut");
    }

    private final func SetConditionLevelData(controller: wref<ConditionLevelLogicController>, levelData: wref<DFConditionEffectDisplayData>) -> Void {
        //DFProfile();
        // Unlike Skills, only highlight a Condition if you are exactly on that Condition's Level.
        let active: Bool;

        if levelData.level == this.m_data.level {
            levelData.isLock = false;
            active = true;
        } else {
            levelData.isLock = true;
            active = false;
        };
        controller.SetData(levelData, active);
    }

    private final func GetConditionDesciption(condition: DFConditionType) -> String {
        //DFProfile();
        if Equals(condition, DFConditionType.Injury) {
            return GetLocalizedTextByKey(n"DarkFutureConditionInjuryDesc");
        } else if Equals(condition, DFConditionType.HumanityLoss) {
            if DFSettings.Get().humanityLossCyberpsychosisEnabled {
                return GetLocalizedTextByKey(n"DarkFutureConditionHumanityLossDesc");
            } else {
                return GetLocalizedTextByKey(n"DarkFutureConditionHumanityLossNoCyberpsychosisDesc");
            }
        } else if Equals(condition, DFConditionType.Biocorruption) {
            return GetLocalizedTextByKey(n"DarkFutureConditionBiocorruptionDesc");
        }
        
        return "";
    }

    protected cb func OnConditionHoverOver(e: ref<inkPointerEvent>) -> Bool {
        //DFProfile();
        let evt: ref<DFConditionHoverOver> = new DFConditionHoverOver();
        evt.widget = e.GetCurrentTarget();
        evt.title = this.m_data.localizedName;
        evt.description = this.GetConditionDesciption(this.m_data.condition);
        this.QueueEvent(evt);
    }

    protected cb func OnConditionHoverOut(e: ref<inkPointerEvent>) -> Bool {
        //DFProfile();
        this.QueueEvent(new DFConditionHoverOut());
    }

    protected cb func OnHoverOver(e: ref<inkPointerEvent>) -> Bool {
        //DFProfile();
        let evt: ref<ConditionEffectHoverOver> = new ConditionEffectHoverOver();
        evt.widget = e.GetCurrentTarget();
        let controller: wref<ConditionLevelLogicController> = evt.widget.GetController() as ConditionLevelLogicController;
        evt.data = controller.GetEffectData();
        controller.HoverOver();
        this.QueueEvent(evt);
    }

    protected cb func OnHoverOut(e: ref<inkPointerEvent>) -> Bool {
        //DFProfile();
        let controller: wref<ConditionLevelLogicController> = e.GetCurrentTarget().GetController() as ConditionLevelLogicController;
        controller.HoverOut();
        this.QueueEvent(new DFConditionEffectHoverOut());
    }
}

public class ConditionLevelLogicController extends inkLogicController {
    private let m_levelText: inkWidgetRef;
    private let m_levelData: ref<DFConditionEffectDisplayData>;
    private let m_active: Bool;
    private let m_hovered: Bool;

    public final func HoverOver() -> Void {
        //DFProfile();
        this.m_hovered = true;
        this.UpdateState();
    }

    public final func HoverOut() -> Void {
        //DFProfile();
        this.m_hovered = false;
        this.UpdateState();
    }

    public final func SetData(levelData: ref<DFConditionEffectDisplayData>, active: Bool) -> Void {
        //DFProfile();
        this.m_levelData = levelData;
        this.m_active = active;
        this.UpdateState();

        let asText: wref<inkText> = inkWidgetRef.Get(this.m_levelText) as inkText;
        asText.SetText(IntToString(this.m_levelData.level));
    }

    private final func UpdateState() -> Void {
        //DFProfile();
        if this.m_hovered {
            if this.m_active {
                this.GetRootWidget().SetState(n"DefaultHover");
            } else {
                this.GetRootWidget().SetState(n"UnavailableHover");
            };
        } else {
            if this.m_active {
                this.GetRootWidget().SetState(n"Default");
            } else {
                this.GetRootWidget().SetState(n"Unavailable");
            };
        };
    }

    public final func GetEffectData() -> ref<DFConditionEffectDisplayData> {
        //DFProfile();
        return this.m_levelData;
    }
}

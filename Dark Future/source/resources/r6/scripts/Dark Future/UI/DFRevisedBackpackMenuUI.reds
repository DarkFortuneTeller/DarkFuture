// -----------------------------------------------------------------------------
// DFRevisedBackpackMenuUI
// -----------------------------------------------------------------------------
//
// - Handles the UI meters in the Revised Backpack Inventory, if installed.
//

module DarkFuture.UI

@if(ModuleExists("RevisedBackpack"))
import RevisedBackpack.{
    RevisedCustomEventBackpackOpened,
    RevisedCustomEventItemHoverOver,
    RevisedCustomEventItemHoverOut,
    RevisedCustomEventCategorySelected
}

import Codeware.UI.VirtualResolutionWatcher
import DarkFuture.Utils.{
    DFGetPlayer
}
import DarkFuture.Settings.{
    DFSettings,
    SettingChangedEvent
}
import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Main.{ 
    DFNeedsDatum,
    DFNeedChangeDatum,
    DFEnergyChangePreview,
    DFNerveChangePreview
}
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
import DarkFuture.Conditions.{
    DFBiocorruptionConditionSystem
}

class DFRevisedBackpackUISystemEventListeners extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFRevisedBackpackUISystem> {
        //DFProfile();
        return DFRevisedBackpackUISystem.Get();
    }

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<RevisedCustomEventBackpackOpened>(), this, n"OnRevisedBackpackOpenedEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<RevisedCustomEventItemHoverOver>(), this, n"OnRevisedCustomEventItemHoverOverEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<RevisedCustomEventItemHoverOut>(), this, n"OnRevisedCustomEventItemHoverOutEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(NameOf<RevisedCustomEventCategorySelected>(), this, n"OnRevisedCustomEventCategorySelectedEvent", true);
    }
    
    private cb func OnRevisedBackpackOpenedEvent(event: ref<RevisedCustomEventBackpackOpened>) {
        //DFProfile();
        this.GetSystemInstance().OnRevisedBackpackOpened(event.opened);
    }

    private cb func OnRevisedCustomEventItemHoverOverEvent(event: ref<RevisedCustomEventItemHoverOver>) {
        //DFProfile();
        this.GetSystemInstance().OnRevisedBackpackItemHoverOver(event.data);
    }

    private cb func OnRevisedCustomEventItemHoverOutEvent(event: ref<RevisedCustomEventItemHoverOut>) {
        //DFProfile();
        this.GetSystemInstance().OnRevisedBackpackItemHoverOut();
    }

    private cb func OnRevisedCustomEventCategorySelectedEvent(event: ref<RevisedCustomEventCategorySelected>) {
        //DFProfile();
        this.GetSystemInstance().OnRevisedRevisedBackpackCategorySelectedEvent(event.categoryId);
    }
}

public final class DFRevisedBackpackUISystem extends DFSystem {
    private let widgetSlot: ref<inkCompoundWidget>;
    private let virtualResolutionWatcher: ref<VirtualResolutionWatcher>;
    private let GameStateService: wref<DFGameStateService>;
    private let HydrationSystem: wref<DFHydrationSystem>;
    private let NutritionSystem: wref<DFNutritionSystem>;
    private let EnergySystem: wref<DFEnergySystem>;
    private let NerveSystem: wref<DFNerveSystem>;
    private let PlayerStateService: wref<DFPlayerStateService>;
    private let AlcoholAddictionSystem: wref<DFAlcoholAddictionSystem>;
    private let NicotineAddictionSystem: wref<DFNicotineAddictionSystem>;
    private let NarcoticAddictionSystem: wref<DFNarcoticAddictionSystem>;
    private let BiocorruptionConditionSystem: wref<DFBiocorruptionConditionSystem>;
    private let barCluster: ref<inkVerticalPanel>;
    private let nerveBar: ref<DFNeedsMenuBar>;
    private let energyBar: ref<DFNeedsMenuBar>;
    private let nutritionBar: ref<DFNeedsMenuBar>;
    private let hydrationBar: ref<DFNeedsMenuBar>;
    private let barClusterfadeInAnimProxy: ref<inkAnimProxy>;
    private let barClusterfadeInAnim: ref<inkAnimDef>;
    private let barClusterfadeOutAnimProxy: ref<inkAnimProxy>;
    private let barClusterfadeOutAnim: ref<inkAnimDef>;
    private let startedInOvercharge: Bool;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFRevisedBackpackUISystem> {
        //DFProfile();
        let instance: ref<DFRevisedBackpackUISystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFRevisedBackpackUISystem>()) as DFRevisedBackpackUISystem;
        return instance;
    }

    public final static func Get() -> ref<DFRevisedBackpackUISystem> {
        //DFProfile();
        return DFRevisedBackpackUISystem.GetInstance(GetGameInstance());
    }

    //
    //  Revised Backpack Custom Event Handlers
    //
    public final func OnRevisedBackpackOpened(opened: Bool) -> Void {
        //DFProfile();
        DFLog(this, "RevisedBackpack: OnRevisedBackpackOpened, opened: " + ToString(opened));
        if opened {
            let inkSystem: ref<inkSystem> = GameInstance.GetInkSystem();
            let inkHUD: ref<inkCompoundWidget> = inkSystem.GetLayer(n"inkMenuLayer").GetVirtualWindow();
            let fullScreenSlot: ref<inkCompoundWidget> = inkHUD.GetWidgetByPathName(n"Root/RevisedBackpackNeedBarFullScreenSlot") as inkCompoundWidget;

            if !IsDefined(fullScreenSlot) {
                fullScreenSlot = this.CreateFullScreenSlot(inkHUD);
            }

            this.widgetSlot = this.CreateWidgetSlot(fullScreenSlot);
            this.CreateNeedsBarCluster(this.widgetSlot);
            this.SetOriginalValuesInUI();
            this.UpdateAllBarsAppearance();
            this.nerveBar.UpdateOverchargeAppearance(this.NerveSystem.GetOverchargeValue(), this.Settings.compatibilityProjectE3UI);

            // Watch for changes to client resolution. Set the correct resolution now to scale all widgets.
            this.virtualResolutionWatcher = new VirtualResolutionWatcher();
            this.virtualResolutionWatcher.Initialize(GetGameInstance());
            this.virtualResolutionWatcher.ScaleWidget(fullScreenSlot);

            this.widgetSlot.SetVisible(this.Settings.mainSystemEnabled);
        
        } else {
            this.widgetSlot.SetVisible(false);
            this.widgetSlot = null;
        }
    }

    private final func GetStackLimitedNerveToRestore(needsData: DFNeedsDatum, stackingEffect: TweakDBID, maxStacks: Uint32, stacksToTryToApply: Uint32) -> Float {
        //DFProfile();
        let amountToRestore: Float = 0.0;
        let appliedEffect: ref<StatusEffect> = StatusEffectHelper.GetStatusEffectByID(DFGetPlayer(), stackingEffect);
        let appliedEffectStackCount: Uint32 = IsDefined(appliedEffect) ? appliedEffect.GetStackCount() : 0u;

        let availableStackCount: Uint32 = maxStacks - appliedEffectStackCount;
        let stacksToApply: Int32 = Min(Cast<Int32>(availableStackCount), Cast<Int32>(stacksToTryToApply));
        if stacksToApply > 0 {
            amountToRestore = needsData.nerve.value * Cast<Float>(stacksToApply);
        }

        return amountToRestore;
    }

    public final func OnRevisedBackpackItemHoverOver(itemData: ref<gameItemData>) -> Void {
        //DFProfile();
        DFLog(this, "RevisedBackpack: OnRevisedBackpackItemHoverOver, itemData: " + ToString(itemData));
        if this.Settings.mainSystemEnabled {
            if IsDefined(itemData) {
                if itemData.HasTag(n"Consumable") {
                    let itemRecord: wref<Item_Record> = TweakDBInterface.GetItemRecord(itemData.GetID().GetTDBID());
                    let needsData: DFNeedsDatum = GetConsumableNeedsData(itemRecord);
                    
                    // Show the change in Energy if player meets the energy management effect criteria.
                    let energyMax: Float = this.EnergySystem.GetNeedMaxAfterItemUse(itemRecord);
                    let ePrev: DFEnergyChangePreview = this.EnergySystem.GetItemEnergyChangePreviewAmountWithCrashInfo(itemRecord);
                    this.energyBar.SetUpdatedValue(this.EnergySystem.GetNeedValue() + ePrev.change, energyMax);

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
                    this.UpdateNerveBarOvercharge(this.NerveSystem.GetOverchargeValue());
                }
            };
        }
    }

    public final func OnRevisedBackpackItemHoverOut() -> Void {
        //DFProfile();
        DFLog(this, "RevisedBackpack: OnRevisedBackpackItemHoverOut");
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
            this.UpdateBarLimit(this.energyBar, this.EnergySystem.GetNeedMax());
            this.UpdateBarLimit(this.nerveBar, this.NerveSystem.GetNeedMax());
            this.UpdateNerveBarOvercharge(this.NerveSystem.GetOverchargeValue());
        }
    }

    public final func OnRevisedRevisedBackpackCategorySelectedEvent(categoryId: Int32) -> Void {
        //DFProfile();
        DFLog(this, "RevisedBackpack: OnRevisedRevisedBackpackCategorySelectedEvent, categoryId: " + ToString(categoryId));
        if this.GameStateService.IsValidGameState(this, true) {
            // 10 = All Items, 50 = Consumables
            if Equals(categoryId, 10) || Equals(categoryId, 50) {
                this.SetBarClusterFadeIn();
                this.UpdateAllBarsAppearance();
                this.nerveBar.UpdateOverchargeAppearance(this.NerveSystem.GetOverchargeValue(), this.Settings.compatibilityProjectE3UI);
            } else {
                this.SetBarClusterFadeOut();
            }
        } else {
            this.barCluster.SetOpacity(0.0);
        }
    }


    //
    //  DFSystem Required Methods
    //
    private func SetupDebugLogging() -> Void {}

    public final func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        // This system does not have a system-specific toggle.
        return true;
    }
    
    private final func GetSystemToggleSettingString() -> String {
        //DFProfile();
        // This system does not have a system-specific toggle.
        return "INVALID";
    }

    public func GetSystems() -> Void {
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
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    public func SetupData() -> Void {}
    private func RegisterListeners() -> Void {}
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func UnregisterListeners() -> Void {}
    public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipBegin() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    public func DoPostSuspendActions() -> Void {}
    public func DoPostResumeActions() -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    private final func CreateFullScreenSlot(inkHUD: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
        //DFProfile();
        // Create a full-screen slot with dimensions 3840x2160, so that when it is rescaled by Codeware VirtualResolutionWatcher,
        // all of its contents and relative positions are also resized.

        let fullScreenSlot: ref<inkCompoundWidget> = new inkCanvas();
        fullScreenSlot.SetName(n"RevisedBackpackNeedBarFullScreenSlot");
        fullScreenSlot.SetSize(Vector2(3840.0, 2160.0));
        fullScreenSlot.SetRenderTransformPivot(Vector2(0.0, 0.0));
        fullScreenSlot.Reparent(inkHUD.GetWidgetByPathName(n"Root") as inkCompoundWidget);

        return fullScreenSlot;
    }

    private final func CreateWidgetSlot(parent: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
        //DFProfile();
        // Create the slot.
        let widgetSlot: ref<inkCompoundWidget> = new inkCanvas();
        widgetSlot.SetName(n"RevisedBackpackNeedBarWidgetSlot");
        widgetSlot.SetFitToContent(true);
        widgetSlot.Reparent(parent);

        return widgetSlot;
    }

    private final func CreateNeedsBarCluster(parent: ref<inkCompoundWidget>) -> Void {
        //DFProfile();
        this.barCluster = new inkVerticalPanel();
        this.barCluster.SetOpacity(0.0);
        this.barCluster.SetName(n"RevisedBackpackNeedsBarCluster");
        this.barCluster.SetAnchor(inkEAnchor.TopCenter);
        this.barCluster.SetAnchorPoint(Vector2(0.5, 0.5));
        this.barCluster.SetScale(Vector2(0.85, 0.85));
        this.barCluster.SetTranslation(Vector2(1920.0, 240.0));
        this.barCluster.Reparent(parent, 12);

        let rowOne: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        rowOne.SetName(n"RevisedBackpackNeedsBarClusterRowOne");
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

    private final func UpdateAllBarsAppearance() -> Void {
        //DFProfile();
        let useProjectE3UI: Bool = this.Settings.compatibilityProjectE3UI;
        this.hydrationBar.UpdateAppearance(useProjectE3UI);
        this.nutritionBar.UpdateAppearance(useProjectE3UI);
        this.energyBar.UpdateAppearance(useProjectE3UI);
        this.nerveBar.UpdateAppearance(useProjectE3UI);
    }

    private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
        //DFProfile();
        if IsDefined(animProxy) {
            animProxy.Stop();
        }
    }

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

    private final func UpdateBarLimit(bar: ref<DFNeedsMenuBar>, newLimitValue: Float) -> Void {
        //DFProfile();
        let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
        bar.SetProgressEmpty(currentLimitPct);
    }

    private final func UpdateNerveBarOvercharge(newOverchargeValue: Float) -> Void {
        //DFProfile();
        let currentOverchargePct: Float = newOverchargeValue / 100.0;
        this.nerveBar.SetProgressOvercharge(currentOverchargePct);
        this.nerveBar.UpdateOverchargeAppearance(newOverchargeValue, this.Settings.compatibilityProjectE3UI, !this.startedInOvercharge && currentOverchargePct > 0.0);
    }
}
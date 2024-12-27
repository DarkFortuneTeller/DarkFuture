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

import DarkFuture.Settings.{
	DFSettings,
	SettingChangedEvent
}
import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Main.{ 
	DFNeedsDatum,
	DFNeedChangeDatum
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

class DFRevisedBackpackUISystemEventListeners extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFRevisedBackpackUISystem> {
		return DFRevisedBackpackUISystem.Get();
	}

    private cb func OnLoad() {
		super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"RevisedBackpack.RevisedCustomEventBackpackOpened", this, n"OnRevisedBackpackOpenedEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"RevisedBackpack.RevisedCustomEventItemHoverOver", this, n"OnRevisedCustomEventItemHoverOverEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"RevisedBackpack.RevisedCustomEventItemHoverOut", this, n"OnRevisedCustomEventItemHoverOutEvent", true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"RevisedBackpack.RevisedCustomEventCategorySelected", this, n"OnRevisedCustomEventCategorySelectedEvent", true);
    }
	
	private cb func OnRevisedBackpackOpenedEvent(event: ref<RevisedCustomEventBackpackOpened>) {
		this.GetSystemInstance().OnRevisedBackpackOpened(event.opened);
	}

	private cb func OnRevisedCustomEventItemHoverOverEvent(event: ref<RevisedCustomEventItemHoverOver>) {
		this.GetSystemInstance().OnRevisedBackpackItemHoverOver(event.data);
	}

    private cb func OnRevisedCustomEventItemHoverOutEvent(event: ref<RevisedCustomEventItemHoverOut>) {
		this.GetSystemInstance().OnRevisedBackpackItemHoverOut();
	}

    private cb func OnRevisedCustomEventCategorySelectedEvent(event: ref<RevisedCustomEventCategorySelected>) {
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
    private let barCluster: ref<inkVerticalPanel>;
    private let nerveBar: ref<DFNeedsMenuBar>;
    private let energyBar: ref<DFNeedsMenuBar>;
    private let nutritionBar: ref<DFNeedsMenuBar>;
    private let hydrationBar: ref<DFNeedsMenuBar>;
    private let barClusterfadeInAnimProxy: ref<inkAnimProxy>;
    private let barClusterfadeInAnim: ref<inkAnimDef>;
    private let barClusterfadeOutAnimProxy: ref<inkAnimProxy>;
    private let barClusterfadeOutAnim: ref<inkAnimDef>;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFRevisedBackpackUISystem> {
		let instance: ref<DFRevisedBackpackUISystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.UI.DFRevisedBackpackUISystem") as DFRevisedBackpackUISystem;
		return instance;
	}

	public final static func Get() -> ref<DFRevisedBackpackUISystem> {
		return DFRevisedBackpackUISystem.GetInstance(GetGameInstance());
	}

    //
    //  Revised Backpack Custom Event Handlers
    //
    public final func OnRevisedBackpackOpened(opened: Bool) -> Void {
        DFLog(this.debugEnabled, this, "RevisedBackpack: OnRevisedBackpackOpened, opened: " + ToString(opened));
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

    public final func OnRevisedBackpackItemHoverOver(itemData: ref<gameItemData>) -> Void {
        DFLog(this.debugEnabled, this, "RevisedBackpack: OnRevisedBackpackItemHoverOver, itemData: " + ToString(itemData));
        if this.Settings.mainSystemEnabled && !StatusEffectSystem.ObjectHasStatusEffect(this.HydrationSystem.player, t"DarkFutureStatusEffect.Weakened") {
            if IsDefined(itemData) {
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
    }

    public final func OnRevisedBackpackItemHoverOut() -> Void {
        DFLog(this.debugEnabled, this, "RevisedBackpack: OnRevisedBackpackItemHoverOut");
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
    }

    public final func OnRevisedRevisedBackpackCategorySelectedEvent(categoryId: Int32) -> Void {
        DFLog(this.debugEnabled, this, "RevisedBackpack: OnRevisedRevisedBackpackCategorySelectedEvent, categoryId: " + ToString(categoryId));
        if this.GameStateService.IsValidGameState("OnItemFilterClick") {
            // 10 = All Items, 50 = Consumables
            if Equals(categoryId, 10) || Equals(categoryId, 50) {
                this.SetBarClusterFadeIn();
                this.UpdateAllBarsAppearance();
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

	private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}
    
	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	private func GetSystems() -> Void {
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
    }

	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	private func SetupData() -> Void {}
	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterListeners() -> Void {}
	private func UnregisterAllDelayCallbacks() -> Void {}
	public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	private func DoPostSuspendActions() -> Void {}
	private func DoPostResumeActions() -> Void {}
	private func DoStopActions() -> Void {}
	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

	private final func CreateFullScreenSlot(inkHUD: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		// Create a full-screen slot with dimensions 3840x2160, so that when it is rescaled by Codeware VirtualResolutionWatcher,
		// all of its contents and relative positions are also resized.

		let fullScreenSlot: ref<inkCompoundWidget> = new inkCanvas();
		fullScreenSlot.SetName(n"RevisedBackpackNeedBarFullScreenSlot");
		fullScreenSlot.SetSize(new Vector2(3840.0, 2160.0));
		fullScreenSlot.SetRenderTransformPivot(new Vector2(0.0, 0.0));
		fullScreenSlot.Reparent(inkHUD.GetWidgetByPathName(n"Root") as inkCompoundWidget);

		return fullScreenSlot;
	}

	private final func CreateWidgetSlot(parent: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		// Create the slot.
		let widgetSlot: ref<inkCompoundWidget> = new inkCanvas();
		widgetSlot.SetName(n"RevisedBackpackNeedBarWidgetSlot");
		widgetSlot.SetFitToContent(true);
		widgetSlot.Reparent(parent);

		return widgetSlot;
	}

	private final func CreateNeedsBarCluster(parent: ref<inkCompoundWidget>) -> Void {
        this.barCluster = new inkVerticalPanel();
        this.barCluster.SetOpacity(0.0);
        this.barCluster.SetName(n"RevisedBackpackNeedsBarCluster");
        this.barCluster.SetAnchor(inkEAnchor.TopCenter);
        this.barCluster.SetAnchorPoint(new Vector2(0.5, 0.5));
        this.barCluster.SetScale(new Vector2(0.85, 0.85));
        this.barCluster.SetTranslation(new Vector2(1920.0, 240.0));
        this.barCluster.Reparent(parent, 12);

        let rowOne: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        rowOne.SetName(n"RevisedBackpackNeedsBarClusterRowOne");
        rowOne.SetSize(new Vector2(100.0, 60.0));
        rowOne.SetHAlign(inkEHorizontalAlign.Center);
        rowOne.SetVAlign(inkEVerticalAlign.Center);
        rowOne.SetAnchor(inkEAnchor.Fill);
        rowOne.SetAnchorPoint(new Vector2(0.5, 0.5));
        rowOne.SetMargin(new inkMargin(0.0, 0.0, 0.0, 36.0));
        rowOne.Reparent(this.barCluster);

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

        barSetupData = new DFNeedsMenuBarSetupData(rowOne, n"hydrationBar", hydrationIconPath, hydrationIconName, GetLocalizedTextByKey(n"DarkFutureUILabelHydration"), 400.0, 100.0, 0.0, 0.0, false);
        this.hydrationBar = new DFNeedsMenuBar();
        this.hydrationBar.Init(barSetupData);
        
        barSetupData = new DFNeedsMenuBarSetupData(rowOne, n"nutritionBar", nutritionIconPath, nutritionIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNutrition"), 400.0, 100.0, 0.0, 0.0, false);
        this.nutritionBar = new DFNeedsMenuBar();
        this.nutritionBar.Init(barSetupData);

        barSetupData = new DFNeedsMenuBarSetupData(rowOne, n"energyBar", energyIconPath, energyIconName, GetLocalizedTextByKey(n"DarkFutureUILabelEnergy"), 400.0, 0.0, 0.0, 0.0, false);
        this.energyBar = new DFNeedsMenuBar();
        this.energyBar.Init(barSetupData);
    }

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

    private final func UpdateAllBarsAppearance() -> Void {
        let useProjectE3UI: Bool = this.Settings.compatibilityProjectE3UI;
        this.hydrationBar.UpdateAppearance(useProjectE3UI);
        this.nutritionBar.UpdateAppearance(useProjectE3UI);
        this.energyBar.UpdateAppearance(useProjectE3UI);
        this.nerveBar.UpdateAppearance(useProjectE3UI);
    }

    private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
        if IsDefined(animProxy) {
            animProxy.Stop();
        }
    }

    private final func SetOriginalValuesInUI() -> Void {
        if this.Settings.mainSystemEnabled {
            this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
            this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
            this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
            this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());
            this.UpdateNerveBarLimit(this.NerveSystem.GetNeedMax());
        }
    }

    private final func UpdateNerveBarLimit(newLimitValue: Float) -> Void {
        let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
        this.nerveBar.SetProgressEmpty(currentLimitPct);
    }
}
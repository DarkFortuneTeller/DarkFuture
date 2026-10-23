// -----------------------------------------------------------------------------
// DFRelaxActionSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles relaxation actions, including immersive item use 
//   via Consumable Animations.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
    DFRunGuard,
    DarkFutureSendRadioEvent,
    RandRangeInclusive
}
import DarkFuture.Settings.DFSettings
import DarkFuture.Main.{
    DFTimeSkipData
}
import DarkFuture.Needs.{
    DFNerveSystem
}
import DarkFuture.Conditions.{
    DFBiocorruptionConditionSystem
}
import DarkFuture.Services.{
    DFAnimationService,
    DFAnimDatum,
    DFAnimType,
    DFConsumableAnimSubType,
    DFConsumableAnimDatum,
    DFPlayerStateService
}

public enum DFRelaxActionItemUseItemType {
    Invalid = 0,
    FoodJunk = 1,
    FoodSnack = 2,
    FoodMeal = 3,
    FoodSpecial = 4,
    DrinkSoda = 5,
    DrinkEnergyDrink = 6,
    DrinkCoffee = 7,
    DrinkTeaDecaf = 8,
    DrinkWater = 9,
    DrinkSpecial = 10,
    Smoke = 11,
    AlcoholBeer = 12,
    AlcoholCocktail = 13,
    AlcoholWine = 14,
    AlcoholLiquor = 15,
    AlcoholSpecial = 16,
    NarcoticMrWhitey = 17,
    NarcoticBlackLace = 18,
    NarcoticGlitter = 19,
    NarcoticVanitol = 20,
    BoosterOlDonkey = 21,
    BoosterAssKick = 22,
    BoosterJellytricity = 23,
    BoosterRAMNugs = 24,
    BoosterCapacity = 25,
    BoosterStamina = 26,
    BoosterMemory = 27,
    PharmaTraumaKit = 28,
    PharmaEmergencyCardioregulator = 29,
    PharmaImmunosuppressant = 30,
    PharmaExcelafin = 31,
    PharmaAddiquit = 32,
    PharmaEndotrisine = 33,
    NarcoticCompatibility_Juice = 34
}

public struct DFRelaxActionItemUseCachedItem {
    public let tdbid: TweakDBID;
    public let type: DFRelaxActionItemUseItemType;
}

// PlayerPuppet - Add an input listener for Relax Action and Repeat.
//
@addField(PlayerPuppet)
public let m_DarkFutureRelaxActionInputListener: ref<DarkFutureRelaxActionInputListener>;

// PlayerPuppet - Unregister for the input listener on detach.
//
@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
	//DFProfile();
    let r: Bool = wrappedMethod();

    this.UnregisterInputListener(this.m_DarkFutureRelaxActionInputListener);
    this.m_DarkFutureRelaxActionInputListener = null;

	return r;
}

// InputContextTransitionEvents - Add the Relax Action prompt
//
@addMethod(InputContextTransitionEvents)
private final func DarkFutureEvaluateRelaxActionInputHint(show: Bool, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>, source: CName) -> Void {
	//DFProfile();
    let settings: ref<DFSettings> = DFSettings.Get();
	if show && settings.relaxActionHotkeyEnabled && settings.relaxActionShowInputHint {
        let inputString: String;
        // Relax
        inputString = GetLocalizedTextByKey(n"DarkFutureRelaxActionPrompt");
        
		this.ShowInputHint(scriptInterface, n"DFRelaxAction", source, inputString, inkInputHintHoldIndicationType.Hold, true, 127);
	} else {
		this.RemoveInputHint(scriptInterface, n"DFRelaxAction", source);
	}
}

// InputContextTransitionEvents - Show the input hint when showing the generic exploration hints.
//
@wrapMethod(InputContextTransitionEvents)
protected final const func ShowGenericExplorationInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	//DFProfile();
	wrappedMethod(stateContext, scriptInterface);

    this.DarkFutureEvaluateRelaxActionInputHint(true, stateContext, scriptInterface, n"Locomotion");
}

// InputContextTransitionEvents - Hide the input hint when showing the generic exploration hints.
//
@wrapMethod(InputContextTransitionEvents)
protected final const func RemoveGenericExplorationInputHints(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
	//DFProfile();
	wrappedMethod(stateContext, scriptInterface);

    this.DarkFutureEvaluateRelaxActionInputHint(false, stateContext, scriptInterface, n"Locomotion");
}

// Input Listener
//
public class DarkFutureRelaxActionInputListener {
	protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
		if Equals(ListenerAction.GetName(action), n"DFRelaxAction") && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_HOLD_COMPLETE) {
			//DFProfile();
			DFRelaxActionSystem.Get().HandleRelaxAction();
		}
	}
}

//
//
// HUD Tooltips
//
//

// InteractionsHubGameController - On Initialize, store a copy of the controller in the RelaxActionSystem.
//
@wrapMethod(InteractionsHubGameController)
protected cb func OnInitialize() -> Bool {
    let r: Bool = wrappedMethod();

    DFRelaxActionSystem.Get().interactionsHubGameController = this;

    return r;
}

// InteractionsHubGameController - Add a method for displaying HUD Tooltips.
//
@addMethod(InteractionsHubGameController)
public final func DarkFutureDisplayCustomTooltip(data: ref<ATooltipData>) -> Void {
    if IsDefined(this.m_TooltipsManager) {
        let dataList: array<ref<ATooltipData>>;
        ArrayPush(dataList, data);
        this.m_TooltipsManager.ShowTooltips(dataList);
        this.m_TooltipsManager.PlayShowingAnimation();
    };
}

// InteractionsHubGameController - Add a method for hiding HUD Tooltips.
//
@addMethod(InteractionsHubGameController)
public final func DarkFutureHideCustomTooltip() -> Void {
    if IsDefined(this.m_TooltipsManager) {
        this.m_TooltipsManager.HideTooltips();
        this.m_TooltipsManager.PlayHidingAnimation();
    }
}

// DialogHubLogicController - After all of the choice items in a Dialog Hub have spawned, check to see
//                            if a tooltip should be displayed.
//
@wrapMethod(DialogHubLogicController)
private final func UpdateDialogHubData() -> Void {
    wrappedMethod();
    this.DarkFutureUpdateRelaxActionItemUseTooltip();
}

// dialogWidgetGameController - If the total Hub count is greater than 1 (i.e., more than just us), stop the mode.
//
@wrapMethod(dialogWidgetGameController)
private final func AdjustHubsCount(count: Int32) -> Void {
    wrappedMethod(count);

    if count > 1 {
        DFRelaxActionSystem.Get().ForceStopRelaxActionMode();
    }
}

// DialogHubLogicController - Add a method for updating (show/hide) the custom tooltip.
//
@addMethod(DialogHubLogicController)
protected func DarkFutureUpdateRelaxActionItemUseTooltip() -> Void {
    let shouldShowTooltip: Bool = false;
    let tooltipType: DFRelaxActionItemUseItemType;
    let i: Int32 = 0;

    let itemControllerCount: Int32 = ArraySize(this.m_itemControllers);
    while i < itemControllerCount {
        if this.m_itemControllers[i].m_isSelected && NotEquals(this.m_itemControllers[i].DarkFutureRelaxActionItemUseChoiceItemType, DFRelaxActionItemUseItemType.Invalid) {
            tooltipType = this.m_itemControllers[i].DarkFutureRelaxActionItemUseChoiceItemType;
            shouldShowTooltip = true;
            break;
        }
        i += 1;
    }

    if shouldShowTooltip {
        this.DarkFutureIsDisplayingRelaxActionItemUseTooltip = true;
        DFRelaxActionSystem.Get().OnShowRelaxActionItemUseTooltip(tooltipType);
    } else {
        this.DarkFutureIsDisplayingRelaxActionItemUseTooltip = false;
        DFRelaxActionSystem.Get().OnHideRelaxActionItemUseTooltip();
    }
}

@addField(DialogHubLogicController)
private let DarkFutureIsDisplayingRelaxActionItemUseTooltip: Bool = false;

// DialogHubLogicController - When hiding any dialog hub, hide the custom tooltip.
//
@wrapMethod(DialogHubLogicController)
public final func FadeOutItems(fadeOutTime: Float) -> Void {
    wrappedMethod(fadeOutTime);

    if this.DarkFutureIsDisplayingRelaxActionItemUseTooltip {
        this.DarkFutureIsDisplayingRelaxActionItemUseTooltip = false;
        DFRelaxActionSystem.Get().OnHideRelaxActionItemUseTooltip();
    }
}

// DialogChoiceLogicController - Add a field on each dialog choice entry that tracks whether or not this 
//                               is an Immersive Item Use choice, and of what type.
//
@addField(DialogChoiceLogicController)
public let DarkFutureRelaxActionItemUseChoiceItemType: DFRelaxActionItemUseItemType;

// DialogChoiceLogicController - When caption parts are set, catch whether or not this is a Dark Future icon
//                               with data injected into the EnumName. We use this to determine exactly which
//                               choice entry is currently selected.
//
@wrapMethod(DialogChoiceLogicController)
public final func SetCaptionParts(const argList: script_ref<[ref<InteractionChoiceCaptionPart>]>) -> Void {
    wrappedMethod(argList);

    let currType: gamedataChoiceCaptionPartType;
    let i: Int32 = 0;

    while i < ArraySize(Deref(argList)) {
        currType = Deref(argList)[i].GetType();
        if Equals(currType, gamedataChoiceCaptionPartType.Icon) {
            let record: wref<ChoiceCaptionIconPart_Record> = (Deref(argList)[i] as InteractionChoiceCaptionIconPart).iconRecord;
            this.DarkFutureRelaxActionItemUseChoiceItemType = this.GetRelaxActionItemUseChoiceTypeFromEnumName(record.EnumName());
        }

        i += 1;
    }
}

@addMethod(DialogChoiceLogicController)
private final func GetRelaxActionItemUseChoiceTypeFromEnumName(name: CName) -> DFRelaxActionItemUseItemType {
    switch name {
        case n"DarkFutureRelaxActionItemUseSpecialFood":
            return DFRelaxActionItemUseItemType.FoodSpecial;
            break;
        case n"DarkFutureRelaxActionItemUseMeal":
            return DFRelaxActionItemUseItemType.FoodMeal;
            break;
        case n"DarkFutureRelaxActionItemUseSnack":
            return DFRelaxActionItemUseItemType.FoodSnack;
            break;
        case n"DarkFutureRelaxActionItemUseJunkFood":
            return DFRelaxActionItemUseItemType.FoodJunk;
            break;
        case n"DarkFutureRelaxActionItemUseSpecialDrink":
            return DFRelaxActionItemUseItemType.DrinkSpecial;
            break;
        case n"DarkFutureRelaxActionItemUseWater":
            return DFRelaxActionItemUseItemType.DrinkWater;
            break;
        case n"DarkFutureRelaxActionItemUseTeaDecaf":
            return DFRelaxActionItemUseItemType.DrinkTeaDecaf;
            break;
        case n"DarkFutureRelaxActionItemUseCoffee":
            return DFRelaxActionItemUseItemType.DrinkCoffee;
            break;
        case n"DarkFutureRelaxActionItemUseEnergyDrink":
            return DFRelaxActionItemUseItemType.DrinkEnergyDrink;
            break;
        case n"DarkFutureRelaxActionItemUseSoda":
            return DFRelaxActionItemUseItemType.DrinkSoda;
            break;
        case n"DarkFutureRelaxActionItemUseCigarette":
            return DFRelaxActionItemUseItemType.Smoke;
            break;
        case n"DarkFutureRelaxActionItemUseSpecialAlcohol":
            return DFRelaxActionItemUseItemType.AlcoholSpecial;
            break;
        case n"DarkFutureRelaxActionItemUseLiquor":
            return DFRelaxActionItemUseItemType.AlcoholLiquor;
            break;
        case n"DarkFutureRelaxActionItemUseWine":
            return DFRelaxActionItemUseItemType.AlcoholWine;
            break;
        case n"DarkFutureRelaxActionItemUseCocktail":
            return DFRelaxActionItemUseItemType.AlcoholCocktail;
            break;
        case n"DarkFutureRelaxActionItemUseBeer":
            return DFRelaxActionItemUseItemType.AlcoholBeer;
            break;
        case n"DarkFutureRelaxActionItemUseMrWhitey":
            return DFRelaxActionItemUseItemType.NarcoticMrWhitey;
            break;
        case n"DarkFutureRelaxActionItemUseBlackLace":
            return DFRelaxActionItemUseItemType.NarcoticBlackLace;
            break;
        case n"DarkFutureRelaxActionItemUseGlitter":
            return DFRelaxActionItemUseItemType.NarcoticGlitter;
            break;
        case n"DarkFutureRelaxActionItemUseVanitol":
            return DFRelaxActionItemUseItemType.NarcoticVanitol;
            break;
        case n"DarkFutureRelaxActionItemUseCompatibilityJuice":
            return DFRelaxActionItemUseItemType.NarcoticCompatibility_Juice;
            break;
        case n"DarkFutureRelaxActionItemUseOlDonkey":
            return DFRelaxActionItemUseItemType.BoosterOlDonkey;
            break;
        case n"DarkFutureRelaxActionItemUseAssKick":
            return DFRelaxActionItemUseItemType.BoosterAssKick;
            break;
        case n"DarkFutureRelaxActionItemUseJellytricity":
            return DFRelaxActionItemUseItemType.BoosterJellytricity;
            break;
        case n"DarkFutureRelaxActionItemUseRAMNugs":
            return DFRelaxActionItemUseItemType.BoosterRAMNugs;
            break;
        case n"DarkFutureRelaxActionItemUseCapacityBooster":
            return DFRelaxActionItemUseItemType.BoosterCapacity;
            break;
        case n"DarkFutureRelaxActionItemUseStaminaBooster":
            return DFRelaxActionItemUseItemType.BoosterStamina;
            break;
        case n"DarkFutureRelaxActionItemUseMemoryBooster":
            return DFRelaxActionItemUseItemType.BoosterMemory;
            break;
        case n"DarkFutureRelaxActionItemUseTraumaKit":
            return DFRelaxActionItemUseItemType.PharmaTraumaKit;
            break;
        case n"DarkFutureRelaxActionItemUseEmergencyCardioregulator":
            return DFRelaxActionItemUseItemType.PharmaEmergencyCardioregulator;
            break;
        case n"DarkFutureRelaxActionItemUseImmunosuppressant":
            return DFRelaxActionItemUseItemType.PharmaImmunosuppressant;
            break;
        case n"DarkFutureRelaxActionItemUseExcelafin":
            return DFRelaxActionItemUseItemType.PharmaExcelafin;
            break;
        case n"DarkFutureRelaxActionItemUseAddiquit":
            return DFRelaxActionItemUseItemType.PharmaAddiquit;
            break;
        case n"DarkFutureRelaxActionItemUseEndotrisine":
            return DFRelaxActionItemUseItemType.PharmaEndotrisine;
            break;
        default:
            return DFRelaxActionItemUseItemType.Invalid;
            break;
    }
}

/*public class RaycastTestDelay extends DFDelayCallback {
	public let DFVehicleSleepSystem: wref<DFVehicleSleepSystem>;

	public static func Create() -> ref<DFDelayCallback> {
		//DFProfile();
		return new RaycastTestDelay();
	}

	public func InvalidateDelayID() -> Void {
		//DFProfile();
		DFRelaxActionSystem.Get().raycastTestDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		//DFProfile();
        DFRelaxActionSystem.Get().RaycastTest();
	}
}*/

class DFRelaxActionSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFRelaxActionSystem> {
        //DFProfile();
		return DFRelaxActionSystem.Get();
	}
}

public final class DFRelaxActionSystem extends DFSystem {
    private let QuestsSystem: ref<QuestsSystem>;
    private let UIInventorySystem: ref<UIInventoryScriptableSystem>;
    private let TransactionSystem: ref<TransactionSystem>;
    private let AnimationService: ref<DFAnimationService>;
    private let BiocorruptionCondition: ref<DFBiocorruptionConditionSystem>;

    private let lastConsumedTDBID: TweakDBID;
    public let animPlaybackCountRemaining: Int32 = 0;

    private let cachedSelectedItems: array<DFRelaxActionItemUseCachedItem>;

    private let danceAllowedSetThisSession: Bool = false;
    
    private let factListenerRelaxActionModeChangedID: Uint32;
    private let factListenerEvaluateInventoryID: Uint32;
    private let factListenerConsumeItemID: Uint32;
    private let factListenerSetForceLastPlaybackActionID: Uint32;
    private let factListenerClearPlaybackCountActionID: Uint32;
    private let factListenerDisplayNoItemMessageActionID: Uint32;
    private let factListenerDanceID: Uint32;
    private let factListenerRelaxActionEvaluateOptionsID: Uint32;
    private let factListenerPlayBraindanceID: Uint32;

    public let interactionsHubGameController: ref<InteractionsHubGameController>;

    public let raycastTestDelayID: DelayID;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFRelaxActionSystem> {
        //DFProfile();
		let instance: ref<DFRelaxActionSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFRelaxActionSystem>()) as DFRelaxActionSystem;
		return instance;
	}

	public final static func Get() -> ref<DFRelaxActionSystem> {
        //DFProfile();
		return DFRelaxActionSystem.GetInstance(GetGameInstance());
	}

    //
    //  DFSystem Required Methods
    //
    private func SetupDebugLogging() -> Void {
        this.debugEnabled = false;
    }

    public func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.relaxActionHotkeyEnabled;
    }

    private func GetSystemToggleSettingString() -> String {
        return "relaxActionHotkeyEnabled";
    }

    public func DoPostSuspendActions() -> Void {
        this.UnregisterRelaxActionListener();
    }

    public func DoPostResumeActions() -> Void {
        this.RegisterRelaxActionListener();
    }

    public func GetSystems() -> Void {
        let gameInstance = GetGameInstance();
        this.UIInventorySystem = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<UIInventoryScriptableSystem>()) as UIInventoryScriptableSystem;
        this.QuestsSystem = GameInstance.GetQuestsSystem(gameInstance);
        this.TransactionSystem = GameInstance.GetTransactionSystem(gameInstance);
        this.AnimationService = DFAnimationService.GetInstance(gameInstance);
        this.BiocorruptionCondition = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
    }

    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    public func SetupData() -> Void {}

    /*private final func RegisterRaycastTest() -> Void {
		//DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, RaycastTestDelay.Create(), this.raycastTestDelayID, 2.0);
	}*/

    /*
    public final func RaycastTest() -> Void {
        FTLog("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- Raycast Test");

        let geometryDescription: ref<GeometryDescriptionQuery>;
        let geometryDescriptionResult: ref<GeometryDescriptionResult>;
        let queryFilter: QueryFilter;
        let currentPosition: Vector4 = this.player.GetWorldPosition();
        QueryFilter.AddGroup(queryFilter, n"Static");
        QueryFilter.AddGroup(queryFilter, n"PlayerBlocker");
        geometryDescription = new GeometryDescriptionQuery();
        geometryDescription.AddFlag(worldgeometryDescriptionQueryFlags.DistanceVector);
        geometryDescription.filter = queryFilter;
        geometryDescription.refPosition = currentPosition;
        geometryDescription.refDirection = Vector4(0.00, 0.00, -1.00, 0.00);
        geometryDescription.primitiveDimension = Vector4(0.20, 0.10, 0.10, 0.00);
        geometryDescription.maxDistance = 0.50;
        geometryDescription.maxExtent = 0.50;
        geometryDescription.probingPrecision = 10.00;
        geometryDescription.probingMaxDistanceDiff = 0.50;
        geometryDescriptionResult = GameInstance.GetSpatialQueriesSystem(GetGameInstance()).GetGeometryDescriptionSystem().QueryExtents(geometryDescription);
        FTLog(ToString(geometryDescriptionResult.collisionNormal));

        this.RegisterRaycastTest();
    }
    */
    
    private func RegisterListeners() -> Void {
        let gameInstance = GetGameInstance();
        this.factListenerRelaxActionModeChangedID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetRelaxActionModeFact(), this, n"OnRelaxActionModeFactSet");
        this.factListenerEvaluateInventoryID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetEvaluateInventoryFact(), this, n"OnEvaluateInventoryFactSet");
        this.factListenerConsumeItemID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetConsumeItemFact(), this, n"OnConsumeItemFactSet");
        this.factListenerSetForceLastPlaybackActionID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetSetForceLastPlaybackActionFact(), this, n"OnSetForceLastPlaybackActionFactSet");
        this.factListenerClearPlaybackCountActionID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetClearPlaybackCountActionFact(), this, n"OnClearPlaybackCountActionFactSet");
        this.factListenerDisplayNoItemMessageActionID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetDisplayNoItemMessageActionFact(), this, n"OnDisplayNoItemMessageActionFactSet");
        this.factListenerDanceID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetDanceStartFact(), this, n"OnDanceFactSet");
        this.factListenerRelaxActionEvaluateOptionsID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetRelaxActionEvaluateOptionsFact(), this, n"OnRelaxActionEvaluateOptionsFactSet");
        this.factListenerPlayBraindanceID = GameInstance.GetQuestsSystem(gameInstance).RegisterListener(this.GetPlayBraindanceFact(), this, n"OnPlayBraindanceFactSet");
    }
    
    private func RegisterAllRequiredDelayCallbacks() -> Void {}

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        this.RegisterRelaxActionListener();
    }

    private func UnregisterListeners() -> Void {
        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetRelaxActionModeFact(), this.factListenerRelaxActionModeChangedID);
        this.factListenerRelaxActionModeChangedID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetEvaluateInventoryFact(), this.factListenerEvaluateInventoryID);
        this.factListenerEvaluateInventoryID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetConsumeItemFact(), this.factListenerConsumeItemID);
        this.factListenerConsumeItemID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetSetForceLastPlaybackActionFact(), this.factListenerSetForceLastPlaybackActionID);
        this.factListenerSetForceLastPlaybackActionID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetClearPlaybackCountActionFact(), this.factListenerClearPlaybackCountActionID);
        this.factListenerClearPlaybackCountActionID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetDisplayNoItemMessageActionFact(), this.factListenerDisplayNoItemMessageActionID);
        this.factListenerDisplayNoItemMessageActionID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetDanceStartFact(), this.factListenerDanceID);
        this.factListenerDanceID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetPlayBraindanceFact(), this.factListenerPlayBraindanceID);
        this.factListenerPlayBraindanceID = 0u;

        GameInstance.GetQuestsSystem(GetGameInstance()).UnregisterListener(this.GetRelaxActionEvaluateOptionsFact(), this.factListenerRelaxActionEvaluateOptionsID);
        this.factListenerRelaxActionEvaluateOptionsID = 0u;
    }

    public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipBegin() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}

    //
    // Public API
    //
    public final func ForceStopRelaxActionMode() -> Void {
        // Call when an interrupting event should gracefully shut down the Relax Action scene and choice prompts.
        this.QuestsSystem.SetFact(this.GetForceShutdownActionFact(), 1);
    }

    //
    // System-Specific Methods
    //
    private final func GetRelaxActionModeFact() -> CName {
        return n"df_fact_relax_action_mode";
    }

    private final func GetCanStandingMeditateFact() -> CName {
        return n"df_fact_relax_action_can_standing_meditate";
    }

    private final func GetCanKneelingMeditateFact() -> CName {
        return n"df_fact_relax_action_can_kneeling_meditate";
    }

    private final func GetCanDanceFact() -> CName {
        return n"df_fact_relax_action_can_dance";
    }

    private final func GetCanSitGroundFact() -> CName {
        return n"df_fact_relax_action_can_sit_ground";
    }

    private final func GetCanSitSurfaceFact() -> CName {
        return n"df_fact_relax_action_can_sit_surface";
    }

    private final func GetCanLieGroundFact() -> CName {
        return n"df_fact_relax_action_can_lie_ground";
    }

    private final func GetCanPlayBraindanceFact() -> CName {
        return n"df_fact_relax_action_can_play_braindance";
    }

    private final func GetHasMealFact() -> CName {
        return n"df_fact_immersive_item_has_meal";
    }

    private final func GetHasSnackFact() -> CName {
        return n"df_fact_immersive_item_has_snack";
    }

    private final func GetHasJunkFoodFact() -> CName {
        return n"df_fact_immersive_item_has_junkfood";
    }

    private final func GetHasSpecialFoodFact() -> CName {
        return n"df_fact_immersive_item_has_specialfood";
    }

    private final func GetHasSpecialDrinkFact() -> CName {
        return n"df_fact_immersive_item_has_specialdrink";
    }

    private final func GetHasWaterFact() -> CName {
        return n"df_fact_immersive_item_has_water";
    }

    private final func GetHasTeaDecafFact() -> CName {
        return n"df_fact_immersive_item_has_tea_decaf";
    }

    private final func GetHasCoffeeFact() -> CName {
        return n"df_fact_immersive_item_has_coffee";
    }

    private final func GetHasEnergyDrinkFact() -> CName {
        return n"df_fact_immersive_item_has_energydrink";
    }

    private final func GetHasSodaFact() -> CName {
        return n"df_fact_immersive_item_has_soda";
    }

    private final func GetHasCigaretteFact() -> CName {
        return n"df_fact_immersive_item_has_cigarette";
    }

    private final func GetHasSpecialAlcoholFact() -> CName {
        return n"df_fact_immersive_item_has_specialalcohol";
    }

    private final func GetHasLiquorFact() -> CName {
        return n"df_fact_immersive_item_has_liquor";
    }

    private final func GetHasWineFact() -> CName {
        return n"df_fact_immersive_item_has_wine";
    }

    private final func GetHasCocktailFact() -> CName {
        return n"df_fact_immersive_item_has_cocktail";
    }

    private final func GetHasBeerFact() -> CName {
        return n"df_fact_immersive_item_has_beer";
    }

    private final func GetHasMrWhiteyFact() -> CName {
        return n"df_fact_immersive_item_has_mrwhitey";
    }

    private final func GetHasBlackLaceFact() -> CName {
        return n"df_fact_immersive_item_has_blacklace";
    }

    private final func GetHasGlitterFact() -> CName {
        return n"df_fact_immersive_item_has_glitter";
    }

    private final func GetHasVanitolFact() -> CName {
        return n"df_fact_immersive_item_has_vanitol";
    }

    private final func Compatibility_GetHasJuiceFact() -> CName {
        return n"df_fact_immersive_item_compatibility_has_juice";
    }

    private final func GetHasOlDonkeyFact() -> CName {
        return n"df_fact_immersive_item_has_oldonkey";
    }

    private final func GetHasAssKickFact() -> CName {
        return n"df_fact_immersive_item_has_asskick";
    }

    private final func GetHasJellytricityFact() -> CName {
        return n"df_fact_immersive_item_has_jellytricity";
    }

    private final func GetHasRAMNugsFact() -> CName {
        return n"df_fact_immersive_item_has_ramnugs";
    }

    private final func GetHasCapacityBoosterFact() -> CName {
        return n"df_fact_immersive_item_has_capacitybooster";
    }

    private final func GetHasStaminaBoosterFact() -> CName {
        return n"df_fact_immersive_item_has_staminabooster";
    }

    private final func GetHasMemoryBoosterFact() -> CName {
        return n"df_fact_immersive_item_has_memorybooster";
    }

    private final func GetHasTraumaKitFact() -> CName {
        return n"df_fact_immersive_item_has_traumakit";
    }

    private final func GetHasEmergencyCardioregulatorFact() -> CName {
        return n"df_fact_immersive_item_has_emergencycardioregulator";
    }

    private final func GetHasImmunosuppressantFact() -> CName {
        return n"df_fact_immersive_item_has_immunosuppressant";
    }

    private final func GetHasExcelafinFact() -> CName {
        return n"df_fact_immersive_item_has_excelafin";
    }

    private final func GetHasAddiquitFact() -> CName {
        return n"df_fact_immersive_item_has_addiquit";
    }

    private final func GetHasEndotrisineFact() -> CName {
        return n"df_fact_immersive_item_has_endotrisine";
    }

    private final func GetEvaluateInventoryFact() -> CName {
        return n"df_fact_immersive_item_evaluate_inventory";
    }

    private final func GetConsumeItemFact() -> CName {
        return n"df_fact_immersive_item_consume";
    }

    private final func GetSetForceLastPlaybackActionFact() -> CName {
        return n"df_fact_action_set_force_last_playback";
    }

    private final func GetClearPlaybackCountActionFact() -> CName {
        return n"df_fact_action_clear_playback_count";
    }

    private final func GetForceShutdownActionFact() -> CName {
        return n"df_fact_action_relax_action_force_shutdown";
    }

    private final func GetHasAnyFoodFact() -> CName {
        return n"df_fact_immersive_item_has_any_food";
    }

    private final func GetHasAnyDrinkFact() -> CName {
        return n"df_fact_immersive_item_has_any_drink";
    }

    private final func GetHasAnyViceFact() -> CName {
        return n"df_fact_immersive_item_has_any_vice";
    }

    private final func GetHasAnyAlcoholFact() -> CName {
        return n"df_fact_immersive_item_has_any_alcohol";
    }

    private final func GetHasAnyNarcoticFact() -> CName {
        return n"df_fact_immersive_item_has_any_narcotic";
    }

    private final func GetHasAnyBoosterFact() -> CName {
        return n"df_fact_immersive_item_has_any_booster";
    }

    private final func GetHasAnyMedicationFact() -> CName {
        return n"df_fact_immersive_item_has_any_medication";
    }

    private final func GetHasAnyItemFact() -> CName {
        return n"df_fact_immersive_item_has_any_item";
    }

    private final func GetDisplayNoItemMessageActionFact() -> CName {
        return n"df_fact_action_display_no_item_message";
    }

    private final func GetDanceStartFact() -> CName {
        return n"df_fact_action_dance_start";
    }

    private final func GetPlayBraindanceFact() -> CName {
        return n"df_fact_action_braindance_start";
    }

    private final func GetRelaxActionEvaluateOptionsFact() -> CName {
        return n"df_fact_relax_action_evaluate_options";
    }

    public final func HandleRelaxAction() -> Void {
        if this.Settings.relaxActionHotkeyEnabled {
            this.TryToStartRelaxActionMode();
        }
    }

    private final func OnRelaxActionModeFactSet(value: Int32) -> Void {
        if value == 0 {
            this.AnimationService.RegisterUnsetRadioRestrictionOverrideCallback();
            this.danceAllowedSetThisSession = false;

            // When exiting Relax Action Mode, make sure to hide any tooltips.
            this.OnHideRelaxActionItemUseTooltip();
        }
    }

    private final func EvaluateInventory() -> Void {
        DFLog(this, "[~][~][~][~][~][~][~][~][~] Evaluating inventory!");

        this.InvalidateAllItemFlagFacts();
        ArrayClear(this.cachedSelectedItems);
        
        let gameInstance = GetGameInstance();
        if !DFNerveSystem.GetInstance(gameInstance).GetHasNausea() {
            this.SetCachedItemData(DFRelaxActionItemUseItemType.FoodSpecial, n"DarkFutureRelaxActionItemUseSpecialFood", this.GetHasSpecialFoodFact(), this.GetHasAnyFoodFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.FoodMeal, n"DarkFutureRelaxActionItemUseMeal", this.GetHasMealFact(), this.GetHasAnyFoodFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.FoodSnack, n"DarkFutureRelaxActionItemUseSnack", this.GetHasSnackFact(), this.GetHasAnyFoodFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.FoodJunk, n"DarkFutureRelaxActionItemUseJunkFood", this.GetHasJunkFoodFact(), this.GetHasAnyFoodFact());
        }
        
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkSpecial, n"DarkFutureRelaxActionItemUseSpecialDrink", this.GetHasSpecialDrinkFact(), this.GetHasAnyDrinkFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkWater, n"DarkFutureRelaxActionItemUseWater", this.GetHasWaterFact(), this.GetHasAnyDrinkFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkTeaDecaf, n"DarkFutureRelaxActionItemUseTeaDecaf", this.GetHasTeaDecafFact(), this.GetHasAnyDrinkFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkCoffee, n"DarkFutureRelaxActionItemUseCoffee", this.GetHasCoffeeFact(), this.GetHasAnyDrinkFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkEnergyDrink, n"DarkFutureRelaxActionItemUseEnergyDrink", this.GetHasEnergyDrinkFact(), this.GetHasAnyDrinkFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.DrinkSoda, n"DarkFutureRelaxActionItemUseSoda", this.GetHasSodaFact(), this.GetHasAnyDrinkFact());

        if !DFPlayerStateService.GetInstance(gameInstance).GetInOverdose() {
            this.SetCachedItemData(DFRelaxActionItemUseItemType.Smoke, n"DarkFutureRelaxActionItemUseCigarette", this.GetHasCigaretteFact(), this.GetHasAnyViceFact());

            this.SetCachedItemData(DFRelaxActionItemUseItemType.AlcoholSpecial, n"DarkFutureRelaxActionItemUseSpecialAlcohol", this.GetHasSpecialAlcoholFact(), this.GetHasAnyViceFact(), this.GetHasAnyAlcoholFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.AlcoholLiquor, n"DarkFutureRelaxActionItemUseLiquor", this.GetHasLiquorFact(), this.GetHasAnyViceFact(), this.GetHasAnyAlcoholFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.AlcoholWine, n"DarkFutureRelaxActionItemUseWine", this.GetHasWineFact(), this.GetHasAnyViceFact(), this.GetHasAnyAlcoholFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.AlcoholCocktail, n"DarkFutureRelaxActionItemUseCocktail", this.GetHasCocktailFact(), this.GetHasAnyViceFact(), this.GetHasAnyAlcoholFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.AlcoholBeer, n"DarkFutureRelaxActionItemUseBeer", this.GetHasBeerFact(), this.GetHasAnyViceFact(), this.GetHasAnyAlcoholFact());

            this.SetCachedItemData(DFRelaxActionItemUseItemType.NarcoticMrWhitey, n"DarkFutureRelaxActionItemUseMrWhitey", this.GetHasMrWhiteyFact(), this.GetHasAnyViceFact(), this.GetHasAnyNarcoticFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.NarcoticBlackLace, n"DarkFutureRelaxActionItemUseBlackLace", this.GetHasBlackLaceFact(), this.GetHasAnyViceFact(), this.GetHasAnyNarcoticFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.NarcoticGlitter, n"DarkFutureRelaxActionItemUseGlitter", this.GetHasGlitterFact(), this.GetHasAnyViceFact(), this.GetHasAnyNarcoticFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.NarcoticVanitol, n"DarkFutureRelaxActionItemUseVanitol", this.GetHasVanitolFact(), this.GetHasAnyViceFact(), this.GetHasAnyNarcoticFact());
            this.SetCachedItemData(DFRelaxActionItemUseItemType.NarcoticCompatibility_Juice, n"DarkFutureRelaxActionItemUseCompatibilityJuice", this.Compatibility_GetHasJuiceFact(), this.GetHasAnyViceFact(), this.GetHasAnyNarcoticFact());
        }

        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterOlDonkey, n"DarkFutureRelaxActionItemUseOlDonkey", this.GetHasOlDonkeyFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterAssKick, n"DarkFutureRelaxActionItemUseAssKick", this.GetHasAssKickFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterJellytricity, n"DarkFutureRelaxActionItemUseJellytricity", this.GetHasJellytricityFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterRAMNugs, n"DarkFutureRelaxActionItemUseRAMNugs", this.GetHasRAMNugsFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterCapacity, n"DarkFutureRelaxActionItemUseCapacityBooster", this.GetHasCapacityBoosterFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterStamina, n"DarkFutureRelaxActionItemUseStaminaBooster", this.GetHasStaminaBoosterFact(), this.GetHasAnyBoosterFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.BoosterMemory, n"DarkFutureRelaxActionItemUseMemoryBooster", this.GetHasMemoryBoosterFact(), this.GetHasAnyBoosterFact());

        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaTraumaKit, n"DarkFutureRelaxActionItemUseTraumaKit", this.GetHasTraumaKitFact(), this.GetHasAnyMedicationFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaEmergencyCardioregulator, n"DarkFutureRelaxActionItemUseEmergencyCardioregulator", this.GetHasEmergencyCardioregulatorFact(), this.GetHasAnyMedicationFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaImmunosuppressant, n"DarkFutureRelaxActionItemUseImmunosuppressant", this.GetHasImmunosuppressantFact(), this.GetHasAnyMedicationFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaExcelafin, n"DarkFutureRelaxActionItemUseExcelafin", this.GetHasExcelafinFact(), this.GetHasAnyMedicationFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaAddiquit, n"DarkFutureRelaxActionItemUseAddiquit", this.GetHasAddiquitFact(), this.GetHasAnyMedicationFact());
        this.SetCachedItemData(DFRelaxActionItemUseItemType.PharmaEndotrisine, n"DarkFutureRelaxActionItemUseEndotrisine", this.GetHasEndotrisineFact(), this.GetHasAnyMedicationFact());

        if this.debugEnabled {
            DFLog(this, "cachedSelectedItems: ");
            for item in this.cachedSelectedItems {
                DFLog(this, "  " + TDBID.ToStringDEBUG(item.tdbid) + ", " + ToString(item.type));
            }
        }
    }

    private final func OnEvaluateInventoryFactSet(value: Int32) -> Void {
        if value > 0 {
            this.EvaluateInventory();

            // Allow the scene to continue.
            this.QuestsSystem.SetFact(this.GetEvaluateInventoryFact(), 0);
        }
    }

    private final func SetCachedItemData(type: DFRelaxActionItemUseItemType, tag: CName, hasItemTypeFact: CName, hasItemTypeCategoryFact: CName, opt hasItemTypeSubcategoryFact: CName) -> DFRelaxActionItemUseCachedItem {
        let outList: array<wref<gameItemData>>;
        let cachedItem: DFRelaxActionItemUseCachedItem;
        this.TransactionSystem.GetItemListByTag(this.player, tag, outList);
        
        if ArraySize(outList) > 0 {
            // TODO - Sort by best, worst
            this.QuestsSystem.SetFact(hasItemTypeFact, 1);
            this.QuestsSystem.SetFact(this.GetHasAnyItemFact(), 1);
            this.QuestsSystem.SetFact(hasItemTypeCategoryFact, 1);
            if NotEquals(hasItemTypeSubcategoryFact, n"") {
                this.QuestsSystem.SetFact(hasItemTypeSubcategoryFact, 1);
            }

            cachedItem.tdbid = outList[0].GetID().GetTDBID();
            cachedItem.type = type;
            ArrayPush(this.cachedSelectedItems, cachedItem);
        }
    }

    private final func OnConsumeItemFactSet(value: Int32) -> Void {
        if value > 0 {
            let typeToConsume: DFRelaxActionItemUseItemType = IntEnum<DFRelaxActionItemUseItemType>(value);
            if NotEquals(typeToConsume, DFRelaxActionItemUseItemType.Invalid) {
                this.SetUpDataAndQueueAnimForItem(this.GetCachedItemTDBIDFromType(typeToConsume));

                // Hide any currently displayed tooltip.
                this.OnHideRelaxActionItemUseTooltip();
            }
        }
    }

    private final func OnSetForceLastPlaybackActionFactSet(value: Int32) -> Void {
        if value > 0 {
            this.animPlaybackCountRemaining = 1;
            this.QuestsSystem.SetFact(this.AnimationService.GetAnimPlaybackCountRemainingFact(), 1);

            // Allow the graph to continue.
            this.QuestsSystem.SetFact(this.GetSetForceLastPlaybackActionFact(), 0);
        }
    }

    private final func OnClearPlaybackCountActionFactSet(value: Int32) -> Void {
        if value > 0 {
            this.animPlaybackCountRemaining = 0;
            this.QuestsSystem.SetFact(this.AnimationService.GetAnimPlaybackCountRemainingFact(), 0);

            // Allow the graph to continue.
            this.QuestsSystem.SetFact(this.GetClearPlaybackCountActionFact(), 0);
        }
    }

    private final func OnDisplayNoItemMessageActionFactSet(value: Int32) -> Void {
        if value > 0 {
            let notificationTitle: String = GetLocalizedTextByKey(n"RelaxActionNoItemMessage");
            let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
            notificationEvent.m_notificationType = UIInGameNotificationType.GenericNotification;
            notificationEvent.m_title = notificationTitle;
            notificationEvent.m_overrideCurrentNotification = true;
            
            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(notificationEvent);

            this.QuestsSystem.SetFact(this.GetDisplayNoItemMessageActionFact(), 0);
        }
    }

    public final func OnShowRelaxActionItemUseTooltip(type: DFRelaxActionItemUseItemType) -> Void {
        if NotEquals(type, DFRelaxActionItemUseItemType.Invalid) {
            let tooltipData: ref<IdentifiedWrappedTooltipData> = this.GetTooltipDataFromCachedItemType(type);
            if IsDefined(this.interactionsHubGameController) && IsDefined(tooltipData) {
                this.interactionsHubGameController.DarkFutureDisplayCustomTooltip(tooltipData);
            }
        }
    }

    public final func OnHideRelaxActionItemUseTooltip() -> Void {
        if IsDefined(this.interactionsHubGameController) {
            this.interactionsHubGameController.DarkFutureHideCustomTooltip();
        }
    }

    private final func GetTooltipDataFromCachedItemType(type: DFRelaxActionItemUseItemType) -> ref<IdentifiedWrappedTooltipData> {
        let identifiedTooltipData: ref<IdentifiedWrappedTooltipData>;
        let item: wref<UIInventoryItem>;
        let uiInventoryItemTooltip: ref<UIInventoryItemTooltipWrapper>;

        let cachedItemTDBID: TweakDBID = this.GetCachedItemTDBIDFromType(type);
        
        if ItemID.IsValid(ItemID.FromTDBID(cachedItemTDBID)) {
            item = this.UIInventorySystem.GetPlayerItem(ItemID.FromTDBID(cachedItemTDBID));
            identifiedTooltipData = new IdentifiedWrappedTooltipData();

            let context = ItemDisplayContextData.Make(this.player, ItemDisplayContext.Tooltip);
            context.AddTag(n"RelaxAction");

            uiInventoryItemTooltip = UIInventoryItemTooltipWrapper.Make(item, context);
            identifiedTooltipData.m_data = uiInventoryItemTooltip;
            identifiedTooltipData.m_identifier = n"itemTooltip";
            identifiedTooltipData.m_tooltipOwner = this.player.GetEntityID();
        };

        return identifiedTooltipData;
    }

    private final func GetCachedItemTDBIDFromType(type: DFRelaxActionItemUseItemType) -> TweakDBID {
        for item in this.cachedSelectedItems {
            if Equals(item.type, type) {
                return item.tdbid;
            }
        }
    }

    private final func SetUpDataAndQueueAnimForItem(itemTDBID: TweakDBID) {
        let anim: DFAnimDatum = this.AnimationService.GetAnimFromItemTDBIDIfPlaybackValid(itemTDBID);
        
        if NotEquals(anim.type, DFAnimType.Invalid) {
            anim.consumableAnimData.fromRelaxAction = true;
            
            if Equals(itemTDBID, this.lastConsumedTDBID) && this.animPlaybackCountRemaining > 0 {
                // This is a repeat playback.
            } else {
                // This is a new item, start from the beginning.
                this.animPlaybackCountRemaining = anim.consumableAnimData.maxPlaybackCount;
                this.QuestsSystem.SetFact(this.AnimationService.GetAnimPlaybackCountRemainingFact(), this.animPlaybackCountRemaining);
            }

            this.lastConsumedTDBID = itemTDBID;    
            
            this.AnimationService.QueueAnimation(anim);
        }
    }

    public final func OnConsumeAnimFinished() -> Void {
        // If there are no more repeats remaining, consume the item and apply its effects.
        DFLog(this, "[~][~][~][~][~][~][~][~][~] Attempting to consume item!");

        if !this.Settings.relaxActionEnableMultiStepConsumption {
            this.animPlaybackCountRemaining = 1;
            this.QuestsSystem.SetFact(this.AnimationService.GetAnimPlaybackCountRemainingFact(), 1);
        }

        if this.animPlaybackCountRemaining > 0 {
            this.DecrementAnimPlaybackCountRemaining();

            if this.animPlaybackCountRemaining == 0 {
                DFLog(this, "[~][~][~][~][~][~][~][~][~] lastConsumedTDBID: " + TDBID.ToStringDEBUG(this.lastConsumedTDBID));

                // TODO Bug with SynthSnack - You cannot do this this way. You need to get the actual tag from the item and use that to select the action.
                let record: ref<Item_Record> = TweakDBInterface.GetRecord(this.lastConsumedTDBID) as Item_Record;
                if IsDefined(record) {
                    if record.TagsContains(n"Food") {
                        ItemActionsHelper.EatItem(this.player, ItemID.FromTDBID(this.lastConsumedTDBID), true);
                        DFLog(this, "[~][~][~][~][~][~][~][~][~] Item eaten!");
                    } else if record.TagsContains(n"Drink") {
                        ItemActionsHelper.DrinkItem(this.player, ItemID.FromTDBID(this.lastConsumedTDBID), true);
                        DFLog(this, "[~][~][~][~][~][~][~][~][~] Item drank!");
                    } else {
                        ItemActionsHelper.ConsumeItem(this.player, ItemID.FromTDBID(this.lastConsumedTDBID), true);
                        DFLog(this, "[~][~][~][~][~][~][~][~][~] Item consumed!");
                    }
                    
                } else {
                    DFLog(this, "[~][~][~][~][~][~][~][~][~] ERROR: The Item_Record of lastConsumedTDBID was invalid!");
                }
            } else {
                DFLog(this, "[~][~][~][~][~][~][~][~][~] animPlaybackCountRemaining: " + ToString(this.animPlaybackCountRemaining));
            }
        }

        // Allow the scene graph to continue.
        this.QuestsSystem.SetFact(n"df_fact_immersive_item_consume", 0);
    }

    private final func OnDanceFactSet(value: Int32) -> Void {
        if value == 1 {
            let pocketRadio: ref<PocketRadio> = this.player.GetPocketRadio();
            if !pocketRadio.IsActive() {
                let randomRadioStation: Int32 = RandRangeInclusive(0, 2);
                let stationIdx: Int32;
                if randomRadioStation == 0 {
                    stationIdx = 8; //Impulse FM
                } else if randomRadioStation == 1 {
                    stationIdx = 4; // Night FM
                } else if randomRadioStation == 2 {
                    stationIdx = 1; // Radio Vexelstrom
                }
                DarkFutureSendRadioEvent(this.player, true, true, stationIdx);
            }

            //this.player.GetStimBroadcasterComponent().CreateStimRequest(gamedataStimType.SpreadFear, 5.0, 10.0);

            this.QuestsSystem.SetFact(this.GetDanceStartFact(), 0);
        }
    }

    private final func OnPlayBraindanceFactSet(value: Int32) -> Void {
        if value == 1 {
            ItemActionsHelper.ConsumeItem(this.player, ItemID.FromTDBID(t"Items.braindances_LizziesBDs"), true);
            this.QuestsSystem.SetFact(this.GetPlayBraindanceFact(), 0);
        }
    }

    private final func OnRelaxActionEvaluateOptionsFactSet(value: Int32) -> Void {
        if value == 1 {
            // Dance
            if this.BiocorruptionCondition.GetHasEuphoria() && !this.player.m_pocketRadio.IsRestricted() && !this.danceAllowedSetThisSession {
                this.QuestsSystem.SetFact(this.GetCanDanceFact(), 1);
                this.danceAllowedSetThisSession = true;
            } else {
                this.QuestsSystem.SetFact(this.GetCanDanceFact(), 0);
                this.danceAllowedSetThisSession = true;
            }

            // Lizzie's Braindances
            if this.IsLizziesBDsInstalled() {
                this.QuestsSystem.SetFact(this.GetCanPlayBraindanceFact(), 1);
            } else {
                this.QuestsSystem.SetFact(this.GetCanPlayBraindanceFact(), 0);
            }

            this.EvaluateInventory();

            this.player.m_pocketRadio.DFSetRestrictionOverride(true);
            
            // Allow the graph to continue.
            this.QuestsSystem.SetFact(this.GetRelaxActionEvaluateOptionsFact(), 0);
        }
    }

    public final func GetAnimPlaybackCountRemaining() -> Int32 {
        return this.animPlaybackCountRemaining;
    }

    public final func RegisterRelaxActionListener() -> Void {
		//DFProfile();
        this.player.m_DarkFutureRelaxActionInputListener = new DarkFutureRelaxActionInputListener();
    	this.player.RegisterInputListener(this.player.m_DarkFutureRelaxActionInputListener);
	}

	public final func UnregisterRelaxActionListener() -> Void {
		//DFProfile();
		this.player.UnregisterInputListener(this, n"DFRelaxAction");
		this.player.m_DarkFutureRelaxActionInputListener = null;
	}

    public final func DecrementAnimPlaybackCountRemaining() -> Void {
        this.animPlaybackCountRemaining -= 1;
        this.QuestsSystem.SetFact(this.AnimationService.GetAnimPlaybackCountRemainingFact(), this.animPlaybackCountRemaining);
    }

    public final func GetInRelaxActionMode() -> Bool {
        return this.QuestsSystem.GetFact(this.GetRelaxActionModeFact()) > 0;
    }

    private final func TryToStartRelaxActionMode() -> Void {
        DFLog(this, "[~][~][~][~][~][~][~][~][~][~]");
        DFLog(this, "[~][~][~][~][~][~][~][~][~][~]");
        DFLog(this, "[~][~][~][~][~][~][~][~][~][~] Starting Relax Action Mode!");
        DFLog(this, "[~][~][~][~][~][~][~][~][~][~]");
        DFLog(this, "[~][~][~][~][~][~][~][~][~][~]");

        if this.AnimationService.IsPlayerInAllowedStateForRelaxActionModeEnterAndShowMessage() {
            this.QuestsSystem.SetFact(this.GetRelaxActionModeFact(), 1);
        }
    }

    private final func InvalidateAllItemFlagFacts() -> Void {
        this.QuestsSystem.SetFact(this.GetHasAnyItemFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasAnyFoodFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyDrinkFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyViceFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyAlcoholFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyNarcoticFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyBoosterFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAnyMedicationFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasSpecialFoodFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasMealFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasSnackFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasJunkFoodFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasSpecialDrinkFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasWaterFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasTeaDecafFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasCoffeeFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasEnergyDrinkFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasSodaFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasCigaretteFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasSpecialAlcoholFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasLiquorFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasWineFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasCocktailFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasBeerFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasMrWhiteyFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasBlackLaceFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasGlitterFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasVanitolFact(), 0);
        this.QuestsSystem.SetFact(this.Compatibility_GetHasJuiceFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasOlDonkeyFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAssKickFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasJellytricityFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasRAMNugsFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasCapacityBoosterFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasStaminaBoosterFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasMemoryBoosterFact(), 0);

        this.QuestsSystem.SetFact(this.GetHasTraumaKitFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasImmunosuppressantFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasEmergencyCardioregulatorFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasExcelafinFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasAddiquitFact(), 0);
        this.QuestsSystem.SetFact(this.GetHasEndotrisineFact(), 0);
    }

    //
    // World Interactions
    //
    public final func ShowDumDumBlackLaceInhalerTooltip() -> Void {
        this.OnShowRelaxActionItemUseTooltip(DFRelaxActionItemUseItemType.NarcoticBlackLace);
    }

    //
	//  Lizzie's BDs Detection
	//

	@if(ModuleExists("LizziesBDs.Main"))
	private final func IsLizziesBDsInstalled() -> Bool {
		//DFProfile();
		return true;
	}

	@if(!ModuleExists("LizziesBDs.Main"))
	private final func IsLizziesBDsInstalled() -> Bool {
		//DFProfile();
		return false;
	}
}
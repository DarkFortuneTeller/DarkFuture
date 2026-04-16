// -----------------------------------------------------------------------------
// DFHUDSystem
// -----------------------------------------------------------------------------
//
// - Manages the display of HUD elements.
//

module DarkFuture.UI

import Codeware.UI.VirtualResolutionWatcher
import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Utils.{
	DFBarColorTheme,
	DFBarColorThemeName,
	GetDarkFutureBarColorTheme,
	DFRunGuard
}
import DarkFuture.Needs.UpdateNeedsHUDUIEvent
import DarkFuture.Conditions.UpdateConditionsHUDUIEvent
import DarkFuture.Services.{
	DisplayNeedsHUDUIEvent,
	DFBarUIDisplay,
	DFSegmentedIndicatorUIDisplay
}
import DarkFuture.Settings.{
	DFSettings,
	SettingChangedEvent
}

//
// Overrides
//
// Modals and UI Pop-Up Menus - Hide Bars
//
@wrapMethod(UISystem)
public final func PushGameContext(context: UIGameContext) -> Void {
	//DFProfile();
	wrappedMethod(context);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.UpdateAllHUDUIFromUIContextChange(true, context);
	}
}

@wrapMethod(UISystem)
public final func PopGameContext(context: UIGameContext, opt invalidate: Bool) -> Void {
	//DFProfile();
    wrappedMethod(context, invalidate);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.UpdateAllHUDUIFromUIContextChange(false, context);
	}
}

@wrapMethod(UISystem)
public final func ResetGameContext() -> Void {
	//DFProfile();
    wrappedMethod();

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.UpdateAllHUDUIFromUIContextChange(false);
	}
}

// Cameras and Turrets - Hide Bars
//
@wrapMethod(TakeOverControlSystem)
public final static func CreateInputHint(context: GameInstance, isVisible: Bool) -> Void {
	//DFProfile();
	wrappedMethod(context, isVisible);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.OnTakeControlOfCameraUpdate(isVisible);
	}
}

// Move Songbird Audio / Holocall Widget
//
@wrapMethod(HudPhoneGameController) // extends SongbirdAudioCallGameController
protected cb func OnInitialize() -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod();
	
	if Equals(this.m_RootWidget.GetName(), n"songbird_audiocall") {       // Songbird Audio Call
		DFHUDSystem.Get().SetSongbirdAudiocallWidget(this.m_RootWidget);
	} else if Equals(this.m_RootWidget.GetName(), n"Root") {              // Songbird Holo Call
		DFHUDSystem.Get().SetSongbirdHolocallWidget(this.m_RootWidget);
	}

	return val;
}

// Move Race UI Widget
//
@wrapMethod(hudCarRaceController) // extends inkHUDGameController
private final func StartCountdown() -> Void {
	//DFProfile();
	wrappedMethod();
	
	DFHUDSystem.Get().SetRaceUIPositionCounterWidget(inkWidgetRef.Get(this.m_PositionCounter));
}

// Move normal Audio / Holocall Widget
// Note: Wrapping the OnInitialize callback was causing a crash when taking control of cameras and turrets, use OnPhoneCall() instead.
//
@wrapMethod(NewHudPhoneGameController)
protected cb func OnPhoneCall(value: Variant) -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod(value);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	let phoneWidget = this.GetRootCompoundWidget();

	if IsDefined(phoneWidget) {
		HUDSystem.UpdateNewHudPhoneWidgetPosition(phoneWidget);
	}
	
	return val;
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnHoloAudioCallSpawned(widget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
	//DFProfile();
	let val: Bool = wrappedMethod(widget, userData);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	let phoneWidget = this.GetRootCompoundWidget();

	if IsDefined(phoneWidget) {
		HUDSystem.UpdateNewHudPhoneWidgetPosition(phoneWidget);
	}
	
	return val;
}

@addField(healthbarWidgetGameController)
private let DarkFutureHUDSystem: ref<DFHUDSystem>;

@wrapMethod(healthbarWidgetGameController)
protected cb func OnInitialize() -> Bool {
	wrappedMethod();
	this.DarkFutureHUDSystem = DFHUDSystem.Get();
	this.DarkFutureHUDSystem.SetHealthBarWidget(this);
}

@wrapMethod(healthbarWidgetGameController)
protected cb func OnUninitialize() -> Bool {
	wrappedMethod();
	this.DarkFutureHUDSystem = null;
}

@wrapMethod(healthbarWidgetGameController)
protected cb func OnUpdateHealthBarVisibility() -> Bool {
    let r: Bool = wrappedMethod();

    if IsDefined(this.DarkFutureHUDSystem) {
		this.DarkFutureHUDSystem.RefreshHUDConditionsUIVisibilityFromHealthBar(this.m_moduleShown);
	}

    return r;
}

@addField(StaminabarWidgetGameController)
private let DarkFutureHUDSystem: ref<DFHUDSystem>;

@wrapMethod(StaminabarWidgetGameController)
protected cb func OnInitialize() -> Bool {
	wrappedMethod();
	this.DarkFutureHUDSystem = DFHUDSystem.Get();
	this.DarkFutureHUDSystem.SetStaminaBarWidget(this);
}

@wrapMethod(StaminabarWidgetGameController)
protected cb func OnUninitialize() -> Bool {
	wrappedMethod();
	this.DarkFutureHUDSystem = null;
}

@wrapMethod(StaminabarWidgetGameController)
public final func EvaluateStaminaBarVisibility() -> Void {
	wrappedMethod();

	if IsDefined(this.DarkFutureHUDSystem) {
		this.DarkFutureHUDSystem.RefreshHUDConditionsUIVisibilityFromStaminaBar(this.m_RootWidget.IsVisible());
	}
}

@wrapMethod(PlayerPuppet)
private final func OnStatusEffectUsedHealingItemOrCyberwareApplied() -> Void {
	wrappedMethod();

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if DFRunGuard(HUDSystem) {
		// Do nothing.
	} else {
		HUDSystem.conditionsIndicator.PulseInjurySegmentIfInjured();
	}
}

@addField(RadialWheelController)
private let DFCycleActiveEffectType: InputHintData;

@wrapMethod(RadialWheelController)
private final func CacheInputHintData() -> Void {
	wrappedMethod();

	let source: CName = n"RadialWheel";
	this.DFCycleActiveEffectType.action = n"DFCycleActiveEffectType";
	this.DFCycleActiveEffectType.source = source;
	this.DFCycleActiveEffectType.queuePriority = 5;
	this.DFCycleActiveEffectType.sortingPriority = 5;
	this.DFCycleActiveEffectType.localizedLabel = "Cycle Status Effect Types";
}

@wrapMethod(RadialWheelController)
private final func UpdateInputHints() -> Void {
	wrappedMethod();
	this.AddInputHint(this.DFCycleActiveEffectType, true);
}

@wrapMethod(RadialWheelController)
protected cb func OnInitialize() -> Bool {
	let r: Bool = wrappedMethod();

	let playerControlledObject: ref<GameObject>;
	if this.initialized {
      	return false;
    };
	playerControlledObject = this.GetPlayerControlledObject();
	playerControlledObject.RegisterInputListener(this, n"DFCycleActiveEffectType");

	return r;
}

@wrapMethod(RadialWheelController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
	let aName: CName = ListenerAction.GetName(action);
	let aType: gameinputActionType = ListenerAction.GetType(action);
	if !this.isActive {
      	return false;
    };

	if Equals(aType, gameinputActionType.BUTTON_PRESSED) && Equals(aName, n"DFCycleActiveEffectType") {
		DFHUDSystem.Get().CycleRadialMenuActiveEffectType();
		return false;
	} else {
		return wrappedMethod(action, consumer);
	}
}

@wrapMethod(RadialWheelController)
protected cb func OnOpenWheelRequest(evt: ref<QuickSlotButtonHoldStartEvent>) -> Bool {
	DFHUDSystem.Get().SetRadialMenuActiveEffectType(DFRadialMenuActiveEffectType.StatusEffects, true);
	return wrappedMethod(evt);
}

@wrapMethod(inkCooldownGameController)
protected cb func OnInitialize() -> Bool {
	let r: Bool = wrappedMethod();

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();

	HUDSystem.SetCooldownController(this);

	// Set the Title and List to be visible by default.
	inkWidgetRef.SetVisible(this.m_cooldownTitle, true);
	inkWidgetRef.SetVisible(this.m_cooldownContainer, true);

	// Set up the new carousel.
	let contentTabArray: array<DFRadialMenuActiveEffectTab>;
	let rootWidget: ref<inkVerticalPanel> = (inkWidgetRef.Get(this.m_cooldownTitle).GetParentWidget() as inkVerticalPanel);
	rootWidget.SetSize(Vector2(818.0, 900.0));
	rootWidget.SetMargin(inkMargin(-15.0, 0.0, 0.0, 0.0));

	let titleWidget: ref<inkText> = (inkWidgetRef.Get(this.m_cooldownTitle) as inkText);
	titleWidget.SetHorizontalAlignment(textHorizontalAlignment.Center);

	let carousel: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	carousel.SetName(n"carousel");
	carousel.SetAnchor(inkEAnchor.TopLeft);
	carousel.SetHAlign(inkEHorizontalAlign.Fill);
	carousel.SetVAlign(inkEVerticalAlign.Fill);
	carousel.SetSizeRule(inkESizeRule.Fixed);
	carousel.SetMargin(0.0, 5.0, 0.0, 0.0);
	carousel.SetSize(1.0, 1.0);
	carousel.SetFitToContent(true);
	carousel.Reparent(rootWidget);
	rootWidget.ReorderChild(carousel, 1);

	let leftLine: ref<inkRectangle> = new inkRectangle();
	leftLine.SetName(n"leftLine");
	leftLine.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
	leftLine.BindProperty(n"tintColor", n"MainColors.PanelRed");
	leftLine.SetOpacity(0.2);
	leftLine.SetAnchor(inkEAnchor.TopLeft);
	leftLine.SetAnchorPoint(Vector2(0.0, 0.0));
	leftLine.SetHAlign(inkEHorizontalAlign.Fill);
	leftLine.SetVAlign(inkEVerticalAlign.Bottom);
	leftLine.SetMargin(0.0, 0.0, 5.0, 0.0);
	leftLine.SetSizeRule(inkESizeRule.Stretch);
	leftLine.SetSize(Vector2(2.0, 2.0));
	leftLine.SetFitToContent(false);
	leftLine.Reparent(carousel);

	// Content Tabs Start
	let tabOne: ref<inkRectangle> = new inkRectangle();
	tabOne.SetName(n"tabOne");
	tabOne.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
	tabOne.BindProperty(n"tintColor", n"MainColors.PanelRed");
	tabOne.SetOpacity(0.2);
	tabOne.SetAnchor(inkEAnchor.TopLeft);
	tabOne.SetAnchorPoint(Vector2(0.0, 0.0));
	tabOne.SetHAlign(inkEHorizontalAlign.Fill);
	tabOne.SetVAlign(inkEVerticalAlign.Bottom);
	tabOne.SetMargin(5.0, 0.0, 5.0, 0.0);
	tabOne.SetSizeRule(inkESizeRule.Stretch);
	tabOne.SetSize(Vector2(2.0, 6.0));
	tabOne.SetFitToContent(false);
	tabOne.Reparent(carousel);

	ArrayPush(contentTabArray, DFRadialMenuActiveEffectTab(DFRadialMenuActiveEffectType.StatusEffects, tabOne));

	let tabTwo: ref<inkRectangle> = new inkRectangle();
	tabTwo.SetName(n"tabTwo");
	tabTwo.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
	tabTwo.BindProperty(n"tintColor", n"MainColors.PanelRed");
	tabTwo.SetOpacity(0.2);
	tabTwo.SetAnchor(inkEAnchor.TopLeft);
	tabTwo.SetAnchorPoint(Vector2(0.0, 0.0));
	tabTwo.SetHAlign(inkEHorizontalAlign.Fill);
	tabTwo.SetVAlign(inkEVerticalAlign.Bottom);
	tabTwo.SetMargin(5.0, 0.0, 5.0, 0.0);
	tabTwo.SetSizeRule(inkESizeRule.Stretch);
	tabTwo.SetSize(Vector2(2.0, 6.0));
	tabTwo.SetFitToContent(false);
	tabTwo.Reparent(carousel);

	ArrayPush(contentTabArray, DFRadialMenuActiveEffectTab(DFRadialMenuActiveEffectType.Conditions, tabTwo));

	// Content Tabs End

	let rightLine: ref<inkRectangle> = new inkRectangle();
	rightLine.SetName(n"rightLine");
	rightLine.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
	rightLine.BindProperty(n"tintColor", n"MainColors.PanelRed");
	rightLine.SetOpacity(0.2);
	rightLine.SetAnchor(inkEAnchor.TopLeft);
	rightLine.SetAnchorPoint(Vector2(0.0, 0.0));
	rightLine.SetHAlign(inkEHorizontalAlign.Fill);
	rightLine.SetVAlign(inkEVerticalAlign.Bottom);
	rightLine.SetMargin(5.0, 0.0, 0.0, 0.0);
	rightLine.SetSizeRule(inkESizeRule.Stretch);
	rightLine.SetSize(Vector2(2.0, 2.0));
	rightLine.SetFitToContent(false);
	rightLine.Reparent(carousel);

	HUDSystem.SetCooldownContentTabs(contentTabArray);

	return r;
}

@addField(inkCooldownGameController)
private let DarkFutureListFadeInAnimProxy: ref<inkAnimProxy>;

@addField(inkCooldownGameController)
private let DarkFutureListFadeInAnim: ref<inkAnimDef>;

@addField(inkCooldownGameController)
private let DarkFutureListFadeOutAnimProxy: ref<inkAnimProxy>;

@addField(inkCooldownGameController)
private let DarkFutureListFadeOutAnim: ref<inkAnimDef>;

@addMethod(inkCooldownGameController)
public final func DarkFutureFadeOutCooldownList() -> Void {
	if IsDefined(this.DarkFutureListFadeOutAnimProxy) {
        this.DarkFutureListFadeOutAnimProxy.Stop();
    }
	if IsDefined(this.DarkFutureListFadeInAnimProxy) {
        this.DarkFutureListFadeInAnimProxy.Stop();
    }
	
	this.DarkFutureListFadeOutAnim = new inkAnimDef();
	let fadeOutInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
	fadeOutInterp.SetStartTransparency(inkWidgetRef.GetOpacity(this.m_cooldownContainer));
	fadeOutInterp.SetEndTransparency(0.0);
	let duration: Float = 0.125;
	fadeOutInterp.SetDuration(duration);
	this.DarkFutureListFadeOutAnim.AddInterpolator(fadeOutInterp);
	this.DarkFutureListFadeOutAnimProxy = inkWidgetRef.PlayAnimation(this.m_cooldownContainer, this.DarkFutureListFadeOutAnim);
	this.DarkFutureListFadeOutAnimProxy.RegisterToCallback(inkanimEventType.OnFinish, DFHUDSystem.Get(), n"OnCooldownFadeOutComplete");
}

@addMethod(inkCooldownGameController)
public final func DarkFutureFadeInCooldownList() -> Void {
	if IsDefined(this.DarkFutureListFadeOutAnimProxy) {
        this.DarkFutureListFadeOutAnimProxy.Stop();
    }
	if IsDefined(this.DarkFutureListFadeInAnimProxy) {
        this.DarkFutureListFadeInAnimProxy.Stop();
    }
	
	this.DarkFutureListFadeInAnim = new inkAnimDef();
	let fadeInInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
	fadeInInterp.SetStartTransparency(inkWidgetRef.GetOpacity(this.m_cooldownContainer));
	fadeInInterp.SetEndTransparency(1.0);
	let duration: Float = 0.125;
	fadeInInterp.SetDuration(duration);
	this.DarkFutureListFadeInAnim.AddInterpolator(fadeInInterp);
	this.DarkFutureListFadeInAnimProxy = inkWidgetRef.PlayAnimation(this.m_cooldownContainer, this.DarkFutureListFadeInAnim);
}

/*NEW: inkHorizontalPanelWidget carousel
				anchor topleft
				halign fill
				valign fill
				size fixed
				margin 0 5 0 0
				size 1 1
				fittocontent true

				inkRectangleWidget leftLine
					tint 1.176 0.381 0.348 1.0
					opacity 0.1
					anchor topleft
					anchorpoint 0 0
					halign fill
					valign bottom
					margin 0 0 5 0
					sizerule stretch
					size 2 2
					fittocontent false
				
				inkRectangleWidget tabOne
					tint 1.176 0.381 0.348 1.0
					opacity 0.4
					anchor topleft
					anchorpoint 0 0
					halign fill
					valign bottom
					margin 5 0 5 0
					sizerule stretch
					size 2 6
					fittocontent false
				
				inkRectangleWidget tabTwo
					tint 1.176 0.381 0.348 1.0
					opacity 0.4
					anchor topleft
					anchorpoint 0 0
					halign fill
					valign bottom
					margin 5 0 5 0
					sizerule stretch
					size 2 6
					fittocontent false
				
				inkRectangleWidget rightLine
					tint 1.176 0.381 0.348 1.0
					opacity 0.1
					anchor topleft
					anchorpoint 0 0
					halign fill
					valign bottom
					margin 5 0 0 0
					sizerule stretch
					size 2 2
					fittocontent false*/

@addField(inkCooldownGameController)
public let DarkFutureActiveEffectType: DFRadialMenuActiveEffectType;

//
// Types
//
public enum DFHUDBarType {
  None = 0,
  Hydration = 1,
  Nutrition = 2,
  Energy = 3,
  Nerve = 4
}

public enum DFHUDSegmentedIndicatorSegmentType {
	None = 0,
	Injury = 1,
	HumanityLoss = 2,
	Biocorruption = 3
}

public struct DFNeedHUDUIUpdate {
	public let bar: DFHUDBarType;
	public let newValue: Float;
	public let newLimitValue: Float;
	public let forceMomentaryDisplay: Bool;
	public let instant: Bool;
	public let forceBright: Bool;
	public let momentaryDisplayIgnoresSceneTier: Bool;
	public let isSoftCapRestrictedChange: Bool;
	public let showLock: Bool;
}

public struct DFHUDSegmentedIndicatorUIUpdate {
	public let segment: DFHUDSegmentedIndicatorSegmentType;
	public let active: Bool;
	public let pulse: Bool;
}

public enum DFRadialMenuActiveEffectType {
	StatusEffects = 0,
	Conditions = 1
}

public struct DFRadialMenuActiveEffectTab {
	public let type: DFRadialMenuActiveEffectType;
	public let widget: ref<inkRectangle>;
}

//
// Classes
//
public final class inkBorderConcrete extends inkBorder {}

public class HUDSystemUpdateUIRequestEvent extends CallbackSystemEvent {
    public static func Create() -> ref<HUDSystemUpdateUIRequestEvent> {
		//DFProfile();
        return new HUDSystemUpdateUIRequestEvent();
    }
}

public class PhoneIconCheckDelayCallback extends DFDelayCallback {
	let widget: ref<inkCompoundWidget>;

	public static func Create(widget: ref<inkCompoundWidget>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self: ref<PhoneIconCheckDelayCallback> = new PhoneIconCheckDelayCallback();
		self.widget = widget;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFHUDSystem.Get().phoneIconCheckDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFHUDSystem.Get().OnPhoneIconCheckCallback(this.widget);
	}
}

class DFHUDSystemEventListeners extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFHUDSystem> {
		//DFProfile();
		return DFHUDSystem.Get();
	}

    public cb func OnLoad() {
		//DFProfile();
		super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<UpdateNeedsHUDUIEvent>(), this, n"OnUpdateNeedsHUDUIEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<DisplayNeedsHUDUIEvent>(), this, n"OnDisplayNeedsHUDUIEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<UpdateConditionsHUDUIEvent>(), this, n"OnUpdateConditionsHUDUIEvent", true);
    }
	
	private cb func OnUpdateNeedsHUDUIEvent(event: ref<UpdateNeedsHUDUIEvent>) {
		//DFProfile();
		this.GetSystemInstance().UpdateNeedsUI(event.GetData());
	}

	private cb func OnDisplayNeedsHUDUIEvent(event: ref<DisplayNeedsHUDUIEvent>) {
		//DFProfile();
		this.GetSystemInstance().DisplayNeedsUI(event.GetData());
	}

	private cb func OnUpdateConditionsHUDUIEvent(event: ref<UpdateConditionsHUDUIEvent>) {
		//DFProfile();
		this.GetSystemInstance().UpdateConditionsUI(event.GetData());
	}
}

public final class DFHUDSystem extends DFSystem {
	private let DarkFutureWidgetSlot: ref<inkCompoundWidget>;
	private let conditionsWidgetSlot: ref<inkCompoundWidget>;
	private let virtualResolutionWatcher: ref<VirtualResolutionWatcher>;
	private let hydrationBar: ref<DFNeedsHUDBar>;
	private let nutritionBar: ref<DFNeedsHUDBar>;
	private let energyBar: ref<DFNeedsHUDBar>;
	public let nerveBar: ref<DFNeedsHUDBar>;
	public let conditionsIndicator: ref<DFHUDSegmentedIndicator>;
	public let healthBarController: ref<healthbarWidgetGameController>;
	public let staminaBarController: ref<StaminabarWidgetGameController>;
	public let cooldownController: ref<inkCooldownGameController>;
	private let cooldownContentTabs: array<DFRadialMenuActiveEffectTab>;
	private let cooldownEmptyText: ref<inkText>;

	private let songbirdAudiocallWidget: ref<inkWidget>;
	private let songbirdHolocallWidget: ref<inkWidget>;
	private let statusEffectListWidget: ref<inkWidget>;
	private let raceUIPositionCounterWidget: ref<inkWidget>;

	public let HUDUIBlockedDueToMenuOpen: Bool = false;
	public let HUDUIBlockedDueToCameraControl: Bool = false;

	public let phoneIconCheckDelayID: DelayID;
	public let phoneIconCheckDelayInterval: Float = 1.0;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHUDSystem> {
		//DFProfile();
		let instance: ref<DFHUDSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFHUDSystem>()) as DFHUDSystem;
		return instance;
	}

	public final static func Get() -> ref<DFHUDSystem> {
		//DFProfile();
		return DFHUDSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		//DFProfile();
		this.debugEnabled = false;
	}

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

	public func GetSystems() -> Void {}
	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	public func SetupData() -> Void {}
	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterListeners() -> Void {}
	
	public func UnregisterAllDelayCallbacks() -> Void {
		this.UnregisterForPhoneIconCheck();
	}
	
	public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

	public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		let inkSystem: ref<inkSystem> = GameInstance.GetInkSystem();
		let inkHUD: ref<inkCompoundWidget> = inkSystem.GetLayer(n"inkHUDLayer").GetVirtualWindow();
		let fullScreenSlot: ref<inkCompoundWidget> = inkHUD.GetWidgetByPathName(n"Root/DarkFutureFullScreenSlot") as inkCompoundWidget;

		if !IsDefined(fullScreenSlot) {
			fullScreenSlot = this.CreateFullScreenSlot(inkHUD);
			this.DarkFutureWidgetSlot = this.CreateWidgetSlot(fullScreenSlot, n"DarkFutureWidgetSlot");
			this.UpdateHUDWidgetPositionAndScale();
			this.CreateWidgets(this.DarkFutureWidgetSlot, attachedPlayer);

			// Watch for changes to client resolution. Set the correct resolution now to scale all widgets.
			this.virtualResolutionWatcher = new VirtualResolutionWatcher();
			this.virtualResolutionWatcher.Initialize(GetGameInstance());
			this.virtualResolutionWatcher.ScaleWidget(fullScreenSlot);

			this.DarkFutureWidgetSlot.SetVisible(this.Settings.mainSystemEnabled && this.Settings.showHUDUI);
		}

		this.UpdateAllBaseGameHUDWidgetPositions();
		this.SendUpdateAllUIRequest();
		//this.UpdateConditionsUIVisibility();
	}

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		this.HUDUIBlockedDueToMenuOpen = false;
		this.HUDUIBlockedDueToCameraControl = false;
		this.DarkFutureWidgetSlot.SetVisible(false);
		this.conditionsWidgetSlot.SetVisible(false);
		this.UpdateAllBaseGameHUDWidgetPositions();
	}

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		this.DarkFutureWidgetSlot.SetVisible(this.Settings.mainSystemEnabled && this.Settings.showHUDUI);
		this.UpdateAllBaseGameHUDWidgetPositions();
	}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
		//DFProfile();
		if ArrayContains(changedSettings, "needHUDUIAlwaysOnThreshold") {
			// Respect the new Always On Threshold
			this.RefreshHUDUIVisibility();
		}

		if ArrayContains(changedSettings, "nerveHUDUIColorTheme") && IsDefined(this.nerveBar) {
			this.nerveBar.UpdateColorTheme(this.Settings.nerveHUDUIColorTheme);
		}

		if ArrayContains(changedSettings, "hydrationHUDUIColorTheme") && IsDefined(this.hydrationBar) {
			this.hydrationBar.UpdateColorTheme(this.Settings.hydrationHUDUIColorTheme);
		}

		if ArrayContains(changedSettings, "nutritionHUDUIColorTheme") && IsDefined(this.nutritionBar) {
			this.nutritionBar.UpdateColorTheme(this.Settings.nutritionHUDUIColorTheme);
		}

		if ArrayContains(changedSettings, "energyHUDUIColorTheme") && IsDefined(this.energyBar) {
			this.energyBar.UpdateColorTheme(this.Settings.energyHUDUIColorTheme);
		}

		if ArrayContains(changedSettings, "conditionsIndicatorHUDUIColorTheme") && IsDefined(this.conditionsIndicator) {
			this.conditionsIndicator.UpdateColorTheme(this.Settings.conditionsIndicatorHUDUIColorTheme);
		}

		if ArrayContains(changedSettings, "showHUDUI") {
			if IsDefined(this.DarkFutureWidgetSlot) {
				this.DarkFutureWidgetSlot.SetVisible(this.Settings.showHUDUI);
			}

			this.UpdateAllBaseGameHUDWidgetPositions();
		}

		if ArrayContains(changedSettings, "hudUIScale") || ArrayContains(changedSettings, "hudUIPosX") || ArrayContains(changedSettings, "hudUIPosY") {
			this.UpdateHUDWidgetPositionAndScale();
		}

		if ArrayContains(changedSettings, "updateHolocallVerticalPosition") || 
		   ArrayContains(changedSettings, "holocallVerticalPositionOffset") ||
		   ArrayContains(changedSettings, "updateStatusEffectListVerticalPosition") || 
		   ArrayContains(changedSettings, "statusEffectListVerticalPositionOffset") ||
		   ArrayContains(changedSettings, "updateRaceUIVerticalPosition") ||
		   ArrayContains(changedSettings, "raceUIVerticalPositionOffset") {
			this.UpdateAllBaseGameHUDWidgetPositions();
		}

		if ArrayContains(changedSettings, "nerveLossIsFatal") && IsDefined(this.nerveBar) {
			if this.Settings.nerveLossIsFatal {
				this.nerveBar.SetPulseContinuouslyAtLowThreshold(true, 0.1);
			} else {
				this.nerveBar.SetPulseContinuouslyAtLowThreshold(false);
			}
		}

		if ArrayContains(changedSettings, "compatibilityProjectE3HUD") {
			let shouldShear: Bool = true;
			if this.Settings.compatibilityProjectE3HUD {
				shouldShear = false;
			}

			if IsDefined(this.nerveBar) { this.nerveBar.UpdateShear(shouldShear); }
			if IsDefined(this.nerveBar) { this.hydrationBar.UpdateShear(shouldShear); }
			if IsDefined(this.nerveBar) { this.nutritionBar.UpdateShear(shouldShear); }
			if IsDefined(this.nerveBar) { this.energyBar.UpdateShear(shouldShear); }
			if IsDefined(this.conditionsIndicator) { this.conditionsIndicator.UpdateShear(shouldShear); }
		}
	}

	private final func CreateFullScreenSlot(inkHUD: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		//DFProfile();
		// Create a full-screen slot with dimensions 3840x2160, so that when it is rescaled by Codeware VirtualResolutionWatcher,
		// all of its contents and relative positions are also resized.

		let fullScreenSlot: ref<inkCompoundWidget> = new inkCanvas();
		fullScreenSlot.SetName(n"DarkFutureFullScreenSlot");
		fullScreenSlot.SetSize(Vector2(3840.0, 2160.0));
		fullScreenSlot.SetRenderTransformPivot(Vector2(0.0, 0.0));
		fullScreenSlot.Reparent(inkHUD.GetWidgetByPathName(n"Root") as inkCompoundWidget);

		return fullScreenSlot;
	}

	private final func CreateWidgetSlot(parent: ref<inkCompoundWidget>, name: CName) -> ref<inkCompoundWidget> {
		//DFProfile();
		// Create the slot.
		let widgetSlot: ref<inkCompoundWidget> = new inkCanvas();
		widgetSlot.SetName(name);
		widgetSlot.SetFitToContent(true);
		widgetSlot.Reparent(parent);

		return widgetSlot;
	}

	private final func UpdateHUDWidgetPositionAndScale() -> Void {
		//DFProfile();
		let scale: Float = this.Settings.hudUIScale;
		let posX: Float = this.Settings.hudUIPosX;
		let posY: Float = this.Settings.hudUIPosY;

		this.DarkFutureWidgetSlot.SetScale(Vector2(scale, scale));
		this.DarkFutureWidgetSlot.SetTranslation(posX, posY);
	}

	// TODO - We don't need to rebuild all of the widgets, only Conditions.
	public final func RebuildWidgets() -> Void {
		this.CreateWidgets(this.DarkFutureWidgetSlot, this.player);
		// TODO - Force re-appearance
	}

	private final func CreateWidgets(slot: ref<inkCompoundWidget>, attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		slot.RemoveAllChildren();

		let conditionSegmentsData: array<DFHUDSegmentSetupDatum>;
		if this.Settings.injuryConditionEnabled {
			ArrayPush(conditionSegmentsData, DFHUDSegmentSetupDatum(DFHUDSegmentedIndicatorSegmentType.Injury, n"DarkFutureConditionInjuryShort", n"DarkFutureConditionInjury"));
		}
		
		if this.Settings.humanityLossConditionEnabled {
			ArrayPush(conditionSegmentsData, DFHUDSegmentSetupDatum(DFHUDSegmentedIndicatorSegmentType.HumanityLoss, n"DarkFutureConditionHumanityLossShort", n"DarkFutureConditionHumanityLoss"));
		}
		
		if this.Settings.biocorruptionConditionEnabled {
			ArrayPush(conditionSegmentsData, DFHUDSegmentSetupDatum(DFHUDSegmentedIndicatorSegmentType.Biocorruption, n"DarkFutureConditionBiocorruptionShort", n"DarkFutureConditionBiocorruption"));
		}
		
		if ArraySize(conditionSegmentsData) > 0 {
			let conditionsIconPath: ResRef = r"darkfuture\\condition_images\\condition_assets.inkatlas";
			let conditionsIconName: CName = n"ico_condition_outline";
			let conditionWidgetSetupData: DFHUDSegmentedIndicatorSetupData = DFHUDSegmentedIndicatorSetupData(slot, n"conditionsIndicator", conditionsIconPath, conditionsIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PanelRed), 800.0, 705.0, 0.0, -41.0, conditionSegmentsData);
			this.conditionsIndicator = new DFHUDSegmentedIndicator();
			this.conditionsIndicator.Init(conditionWidgetSetupData);

			// The Conditions Indicator is in its own Bar Group so that it can display independently.
			let conditionsIndicatorGroup: ref<DFHUDSegmentedIndicatorGroup> = new DFHUDSegmentedIndicatorGroup();
			conditionsIndicatorGroup.Init(attachedPlayer, false, false);
			conditionsIndicatorGroup.AddBarToGroup(this.conditionsIndicator);
			conditionsIndicatorGroup.BarGroupSetupDone();
		}

		let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nerveIconName: CName = n"illegal";
		let nerveBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"nerveBar", nerveIconPath, nerveIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.Rose), 800.0, 700.0, 0.0, 0.0, true, true);
		this.nerveBar = new DFNeedsHUDBar();
		this.nerveBar.Init(nerveBarSetupData);
		if this.Settings.nerveLossIsFatal {
			this.nerveBar.SetPulseContinuouslyAtLowThreshold(true, 0.1);
		}

		// The Nerve Bar is in its own Bar Group so that it can display independently.
		let nerveBarGroup: ref<DFNeedsHUDBarGroup> = new DFNeedsHUDBarGroup();
		nerveBarGroup.Init(attachedPlayer, true, this.Settings.nerveLossIsFatal);
		nerveBarGroup.AddBarToGroup(this.nerveBar);
		nerveBarGroup.BarGroupSetupDone();

		let hydrationIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let hydrationIconName: CName = n"bar";
		let hydrationBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"hydrationBar", hydrationIconPath, hydrationIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 33.0, 41.0, false, true);
		this.hydrationBar = new DFNeedsHUDBar();
		this.hydrationBar.Init(hydrationBarSetupData);

		let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nutritionIconName: CName = n"food_vendor";
		let nutritionBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"nutritionBar", nutritionIconPath, nutritionIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 53.0 + 230.6, 41.0, false, true);
		this.nutritionBar = new DFNeedsHUDBar();
		this.nutritionBar.Init(nutritionBarSetupData);

		let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let energyIconName: CName = n"wait";
		let energyBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"energyBar", energyIconPath, energyIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 73.0 + 462.2, 41.0, false, true);
		this.energyBar = new DFNeedsHUDBar();
		this.energyBar.Init(energyBarSetupData);

		let physicalNeedsBarGroup: ref<DFNeedsHUDBarGroup> = new DFNeedsHUDBarGroup();
		physicalNeedsBarGroup.Init(attachedPlayer, false, (this.Settings.hydrationLossIsFatal || this.Settings.nutritionLossIsFatal));
		physicalNeedsBarGroup.AddBarToGroup(this.hydrationBar);
		physicalNeedsBarGroup.AddBarToGroup(this.nutritionBar);
		physicalNeedsBarGroup.AddBarToGroup(this.energyBar);

		// The Physical Needs Bar Group is the Parent Group of the Nerve Bar Group. When the Physical Needs Bars display, so should the Nerve Bar.
		physicalNeedsBarGroup.AddGroupToChildren(nerveBarGroup);
		physicalNeedsBarGroup.BarGroupSetupDone();
	}

	private final func GetHUDBarFromType(bar: DFHUDBarType) -> ref<DFNeedsHUDBar> {
		//DFProfile();
		switch bar {
			case DFHUDBarType.None:
				return null;
				break;
			case DFHUDBarType.Hydration:
				return this.hydrationBar;
				break;
			case DFHUDBarType.Nutrition:
				return this.nutritionBar;
				break;
			case DFHUDBarType.Energy:
				return this.energyBar;
				break;
			case DFHUDBarType.Nerve:
				return this.nerveBar;
				break;
		}
	}

	private final func GetHUDConditionsIndicator() -> ref<DFHUDSegmentedIndicator> {
		//DFProfile();
		return this.conditionsIndicator;
	}

	public final func DisplayNeedsUI(uiToShow: DFBarUIDisplay) -> Void {
		//DFProfile();
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(uiToShow.bar);

		if uiToShow.pulse {
			bar.SetPulse(false, uiToShow.ignoreSceneTier);
		} else {
			if NotEquals(bar, null) {
				bar.SetForceBright(uiToShow.forceBright);
				bar.EvaluateBarGroupVisibility(true, uiToShow.ignoreSceneTier);
			}
		}

		if bar.HasLock() {
			if uiToShow.showLock {
				bar.SetShowLock();
			}
		}
	}

	public final func DisplayConditionsUI(uiToShow: DFSegmentedIndicatorUIDisplay) -> Void {
		//DFProfile();
		let indicator: ref<DFHUDSegmentedIndicator> = this.GetHUDConditionsIndicator();

		if NotEquals(indicator, null) {
			indicator.EvaluateSegmentedIndicatorGroupVisibility(true, uiToShow.ignoreSceneTier, this.healthBarController.m_moduleShown, this.staminaBarController.m_RootWidget.IsVisible());
			
			if uiToShow.pulse {
				indicator.SetSegmentPulse(uiToShow.targetSegment, 0.3);
			}
		}
	}

	public final func RefreshHUDUIVisibility() -> Void {
		//DFProfile();
		this.hydrationBar.EvaluateBarGroupVisibility(false);
	}

	public final func RefreshHUDConditionsUIVisibilityFromHealthBar(healthBarVisible: Bool) {
		if DFRunGuard(this) { return; }

		if IsDefined(this.staminaBarController) {
			this.conditionsIndicator.EvaluateSegmentedIndicatorGroupVisibility(false, false, healthBarVisible, this.staminaBarController.m_RootWidget.IsVisible());
		}
	}

	public final func RefreshHUDConditionsUIVisibilityFromStaminaBar(staminaBarVisible: Bool) {
		if DFRunGuard(this) { return; }

		if IsDefined(this.healthBarController) {
			this.conditionsIndicator.EvaluateSegmentedIndicatorGroupVisibility(false, false, this.healthBarController.m_moduleShown, staminaBarVisible);
		}
	}

	public final func RefreshHUDConditionsUIVisibilityFromNerve() {
		if IsDefined(this.staminaBarController) && IsDefined(this.healthBarController) {
			this.conditionsIndicator.EvaluateSegmentedIndicatorGroupVisibility(false, false, this.healthBarController.m_moduleShown, this.staminaBarController.m_RootWidget.IsVisible());
		}
	}

	public final func UpdateNeedsUI(update: DFNeedHUDUIUpdate) -> Void {
		//DFProfile();
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(update.bar);
	
		this.UpdateBarLimit(bar, update.newLimitValue);
		this.UpdateBar(bar, update.newValue, update.forceMomentaryDisplay, update.instant, update.forceBright, update.momentaryDisplayIgnoresSceneTier, update.isSoftCapRestrictedChange, update.showLock);

		// If this was the Nerve bar, also check if we should display Conditions based on Nerve Lock display.
		if Equals(update.bar, DFHUDBarType.Nerve) {
			this.RefreshHUDConditionsUIVisibilityFromNerve();
		}
	}

	public final func UpdateConditionsUI(update: DFHUDSegmentedIndicatorUIUpdate) -> Void {
		//DFProfile();

		this.conditionsIndicator.SetActive(update.segment, update.active);

		if update.pulse {
			this.conditionsIndicator.SetSegmentPulse(update.segment, 0.3);
		}
	}

	public final func SendUpdateAllUIRequest() -> Void {
		//DFProfile();
		GameInstance.GetCallbackSystem().DispatchEvent(HUDSystemUpdateUIRequestEvent.Create());
	}

	private final func PulseUI(bar: DFHUDBarType) -> Void {
		//DFProfile();
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(bar);
		bar.SetPulse();
	}

	private final func UpdateBar(bar: ref<DFNeedsHUDBar>, newValue: Float, forceMomentaryDisplay: Bool, instant: Bool, forceBright: Bool, momentaryDisplayIgnoresSceneTier: Bool, isSoftCapRestrictedChange: Bool, showLock: Bool) -> Void {
		//DFProfile();
		bar.SetForceBright(instant || forceBright);

		let needValuePct: Float = newValue / 100.0;
		bar.SetProgress(needValuePct, forceMomentaryDisplay, instant, momentaryDisplayIgnoresSceneTier, isSoftCapRestrictedChange);

		if bar.HasLock() {
			if showLock {
				bar.SetShowLock();
			}
		}
	}

	private final func UpdateBarLimit(bar: ref<DFNeedsHUDBar>, newLimitValue: Float) -> Void {
		//DFProfile();
		let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
		bar.SetProgressEmpty(currentLimitPct);
	}

	public final func UpdateAllHUDUIFromUIContextChange(menuOpen: Bool, opt context: UIGameContext) -> Void {
		//DFProfile();
		if menuOpen {
			if Equals(context, UIGameContext.RadialWheel) {
				// Force momentary display of UI when entering the Radial Wheel.
				this.HUDUIBlockedDueToMenuOpen = false;

				let barToShow: DFBarUIDisplay;
				barToShow.bar = DFHUDBarType.Hydration; // To force all bars to display

				this.DisplayNeedsUI(barToShow);

				let segmentedIndicatorToShow: DFSegmentedIndicatorUIDisplay;
				this.DisplayConditionsUI(segmentedIndicatorToShow);
			} else {
				// A menu was opened, but it was not the Radial Menu. Block the HUD UI.
				this.HUDUIBlockedDueToMenuOpen = true;
				this.SendUpdateAllUIRequest();
			}
		} else {
			// A menu was closed.
			this.HUDUIBlockedDueToMenuOpen = false;
			this.SendUpdateAllUIRequest();
		}
	}

	public final func OnTakeControlOfCameraUpdate(hasControl: Bool) -> Void {
		//DFProfile();
		// Player took or released control of a camera, turret, or the Sniper's Nest.
		this.HUDUIBlockedDueToCameraControl = hasControl;
		this.SendUpdateAllUIRequest();
	}

	public final func SetSongbirdAudiocallWidget(widget: ref<inkWidget>) -> Void {
		//DFProfile();
		this.songbirdAudiocallWidget = widget;
		this.UpdateSongbirdAudiocallWidgetPosition();
	}

	public final func SetSongbirdHolocallWidget(widget: ref<inkWidget>) -> Void {
		//DFProfile();
		this.songbirdHolocallWidget = widget;
		this.UpdateSongbirdHolocallWidgetPosition();
	}

	public final func SetRaceUIPositionCounterWidget(widget: ref<inkWidget>) -> Void {
		//DFProfile();
		this.raceUIPositionCounterWidget = widget;
		this.UpdateRaceUIPositionCounterWidgetPosition();
	}

	public final func SetRadialWheelStatusEffectListWidget(widget: ref<inkWidget>) -> Void {
		//DFProfile();
		this.statusEffectListWidget = widget;
		this.UpdateStatusEffectListWidgetPosition();
	}

	public final func UpdateSongbirdAudiocallWidgetPosition() -> Void {
		//DFProfile();
		if IsDefined(this.songbirdAudiocallWidget) &&
		   this.Settings.mainSystemEnabled && 
		   this.Settings.showHUDUI &&
		   this.Settings.updateHolocallVerticalPosition {
				this.songbirdAudiocallWidget.SetMargin(inkMargin(0.0, this.Settings.holocallVerticalPositionOffset - 13.0, 0.0, 0.0));
			} else {
				this.songbirdAudiocallWidget.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
		}
	}

	public final func UpdateSongbirdHolocallWidgetPosition() -> Void {
		//DFProfile();
		if IsDefined(this.songbirdHolocallWidget) &&
		   this.Settings.mainSystemEnabled &&
		   this.Settings.showHUDUI &&
		   this.Settings.updateHolocallVerticalPosition {
				this.songbirdHolocallWidget.SetMargin(inkMargin(70.0, this.Settings.holocallVerticalPositionOffset, 0.0, 0.0));
			} else {
				this.songbirdHolocallWidget.SetMargin(inkMargin(70.0, 0.0, 0.0, 0.0));
		}
	}

	public final func UpdateNewHudPhoneWidgetPosition(widget: wref<inkCompoundWidget>) -> Void {
		//DFProfile();
		if IsDefined(widget) {
			let incomingCallSlot = widget.GetWidgetByPathName(n"incomming_call_slot");
			let holoAudioCallSlot = widget.GetWidgetByPathName(n"holoaudio_call_slot");
			let holoAudioCallMarker = widget.GetWidgetByPathName(n"holoaudio_call_marker");

			if IsDefined(incomingCallSlot) && IsDefined(holoAudioCallSlot) && IsDefined(holoAudioCallMarker) {
				if this.Settings.mainSystemEnabled &&
				this.Settings.showHUDUI && 
				this.Settings.updateHolocallVerticalPosition {
					let newHoloCallVerticalOffset: Float = this.Settings.holocallVerticalPositionOffset;
					incomingCallSlot.SetMargin(inkMargin(68.0, 300.0 + newHoloCallVerticalOffset, 0.0, 0.0));
					holoAudioCallSlot.SetMargin(inkMargin(80.0, 284.0 + newHoloCallVerticalOffset, 0.0, 0.0));
					holoAudioCallMarker.SetMargin(inkMargin(-50.0, 300.0 + newHoloCallVerticalOffset, 0.0, 0.0));
					
					// Double check the phone icon slot, which can be wrong on save/load.
					this.RegisterForPhoneIconCheck(widget);
				} else {
					incomingCallSlot.SetMargin(inkMargin(-50.0, 300.0, 0.0, 0.0));
					holoAudioCallSlot.SetMargin(inkMargin(80.0, 284.0, 0.0, 0.0));
					holoAudioCallMarker.SetMargin(inkMargin(-50.0, 300.0, 0.0, 0.0));
					this.RegisterForPhoneIconCheck(widget);
				}
			}
		}
	}

	public final func UpdateRaceUIPositionCounterWidgetPosition() -> Void {
		//DFProfile();
		if IsDefined(this.raceUIPositionCounterWidget) &&
		   this.Settings.mainSystemEnabled &&
		   this.Settings.showHUDUI &&
		   this.Settings.updateRaceUIVerticalPosition {
				// Drill down to the element.
				let widgetChildren: array<ref<inkWidget>> = (this.raceUIPositionCounterWidget as inkCanvas).children.children;
				for child in widgetChildren {
					if Equals(child.GetName(), n"Counter_Horizontal") {
						child.SetMargin(67.0, 293.0 + this.Settings.raceUIVerticalPositionOffset, 0.0, 0.0);
						break;
					}
				}
			} else {
				// Drill down to the element.
				let widgetChildren: array<ref<inkWidget>> = (this.raceUIPositionCounterWidget as inkCanvas).children.children;
				for child in widgetChildren {
					if Equals(child.GetName(), n"Counter_Horizontal") {
						child.SetMargin(67.0, 293.0, 0.0, 0.0);
						break;
					}
				}
			
		}
	}

	public final func UpdateStatusEffectListWidgetPosition() -> Void {
		//DFProfile();
		if IsDefined(this.statusEffectListWidget) && 
		   this.Settings.mainSystemEnabled &&
		   this.Settings.showHUDUI &&
		   this.Settings.updateStatusEffectListVerticalPosition {
				this.statusEffectListWidget.SetMargin(inkMargin(100.0, 0.0, 0.0, 650.0 - this.Settings.statusEffectListVerticalPositionOffset));
			} else {
				this.statusEffectListWidget.SetMargin(inkMargin(100.0, 0.0, 0.0, 650.0));
		}
	}

	public final func UpdateAllBaseGameHUDWidgetPositions() -> Void {
		//DFProfile();
		this.UpdateSongbirdAudiocallWidgetPosition();
		this.UpdateSongbirdHolocallWidgetPosition();
		this.UpdateStatusEffectListWidgetPosition();
		this.UpdateRaceUIPositionCounterWidgetPosition();
	}

	public final func OnPhoneIconCheckCallback(widget: ref<inkCompoundWidget>) -> Void {
		//DFProfile();
		let phoneIconSlot = widget.GetWidgetByPathName(n"phone_icon_slot");

		if IsDefined(phoneIconSlot) {
			if Equals(phoneIconSlot.GetTranslation(), Vector2(-50.0, 300.0)) {
				phoneIconSlot.SetTranslation(Vector2(-50.0, 300.0 + this.Settings.holocallVerticalPositionOffset));
			}
		}
	}

	private final func RegisterForPhoneIconCheck(widget: ref<inkCompoundWidget>) -> Void {
        //DFProfile();
        RegisterDFDelayCallback(this.DelaySystem, PhoneIconCheckDelayCallback.Create(widget), this.phoneIconCheckDelayID, this.phoneIconCheckDelayInterval);
    }

	private final func UnregisterForPhoneIconCheck() -> Void {
		//DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.phoneIconCheckDelayID);
	}

	public final func SetHealthBarWidget(healthBar: ref<healthbarWidgetGameController>) -> Void {
		this.healthBarController = healthBar;
	}

	public final func SetStaminaBarWidget(staminaBar: ref<StaminabarWidgetGameController>) -> Void {
		this.staminaBarController = staminaBar;
	}

	public final func IsNerveLockVisible() -> Bool {
		return this.nerveBar.m_lockShown;
	}

	public final func SetCooldownController(cooldownController: ref<inkCooldownGameController>) -> Void {
		this.cooldownController = cooldownController;
	}

	public final func CycleRadialMenuActiveEffectType() -> Void {
		if IsDefined(this.cooldownController) {
			// Set the active effect type.
			if Equals(this.cooldownController.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.StatusEffects) {
				this.cooldownController.DarkFutureActiveEffectType = DFRadialMenuActiveEffectType.Conditions;
			} else if Equals(this.cooldownController.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.Conditions) {
				this.cooldownController.DarkFutureActiveEffectType = DFRadialMenuActiveEffectType.StatusEffects;
			}

			this.UpdateRadialMenuActiveEffects();
		}
	}

	public final func SetRadialMenuActiveEffectType(type: DFRadialMenuActiveEffectType, opt silent: Bool) {
		if IsDefined(this.cooldownController) {
			// Set the active effect type.
			this.cooldownController.DarkFutureActiveEffectType = type;

			this.UpdateRadialMenuActiveEffects(silent);
		}
	}

	private final func UpdateRadialMenuActiveEffects(opt silent: Bool) -> Void {
		if IsDefined(this.cooldownController) {
			// Update the title text based on the new effect type.
			if Equals(this.cooldownController.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.StatusEffects) {
				(inkWidgetRef.Get(this.cooldownController.m_cooldownTitle) as inkText).SetText(GetLocalizedText("LocKey#51709"));

			} else if Equals(this.cooldownController.DarkFutureActiveEffectType, DFRadialMenuActiveEffectType.Conditions) {
				(inkWidgetRef.Get(this.cooldownController.m_cooldownTitle) as inkText).SetText(GetLocalizedTextByKey(n"DarkFutureConditionsMenuItem"));
			}

			// Update the tab highlighting.
			for tab in this.cooldownContentTabs {
				if Equals(tab.type, this.cooldownController.DarkFutureActiveEffectType) {
					tab.widget.BindProperty(n"tintColor", n"MainColors.PanelBlue");
					tab.widget.SetOpacity(1.0);
				} else {
					tab.widget.BindProperty(n"tintColor", n"MainColors.PanelRed");
					tab.widget.SetOpacity(0.2);
				}
			}

			// SFX
			if !silent {
				GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_gui_tab_change");
			}

			let i: Int32 = 0;
			while i < ArraySize(this.cooldownController.m_cooldownPool) {
				this.cooldownController.m_cooldownPool[i].RemoveCooldown();
				i += 1;
			}

			this.cooldownController.DarkFutureFadeOutCooldownList();
		}
	}

	public final func SetCooldownContentTabs(tabs: script_ref<array<DFRadialMenuActiveEffectTab>>) -> Void {
		this.cooldownContentTabs = Deref(tabs);
	}

	public cb func OnCooldownFadeOutComplete(proxy: ref<inkAnimProxy>) -> Void {
		if IsDefined(this.cooldownController) {
			let v: Variant;
			this.cooldownController.OnEffectUpdate(v);
			this.cooldownController.DarkFutureFadeInCooldownList();
		}
	}
}

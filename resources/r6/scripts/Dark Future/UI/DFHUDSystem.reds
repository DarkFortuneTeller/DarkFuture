// -----------------------------------------------------------------------------
// DFHUDSystem
// -----------------------------------------------------------------------------
//
// - Manages the display of the HUD Meters.
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
	GetDarkFutureBarColorTheme
}
import DarkFuture.Needs.UpdateHUDUIEvent
import DarkFuture.Services.{
	DisplayHUDUIEvent,
	DFUIDisplay
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

public struct DFNeedHUDUIUpdate {
	public let bar: DFHUDBarType;
	public let newValue: Float;
	public let newLimitValue: Float;
	public let forceMomentaryDisplay: Bool;
	public let instant: Bool;
	public let forceBright: Bool;
	public let momentaryDisplayIgnoresSceneTier: Bool;
	public let fromInteraction: Bool;
	public let showLock: Bool;
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

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Needs.UpdateHUDUIEvent", this, n"OnUpdateHUDUIEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DisplayHUDUIEvent", this, n"OnDisplayHUDUIEvent", true);
    }
	
	private cb func OnUpdateHUDUIEvent(event: ref<UpdateHUDUIEvent>) {
		//DFProfile();
		this.GetSystemInstance().UpdateUI(event.GetData());
	}

	private cb func OnDisplayHUDUIEvent(event: ref<DisplayHUDUIEvent>) {
		//DFProfile();
		this.GetSystemInstance().DisplayUI(event.GetData());
	}
}

public final class DFHUDSystem extends DFSystem {
	private let widgetSlot: ref<inkCompoundWidget>;
	private let virtualResolutionWatcher: ref<VirtualResolutionWatcher>;
	private let hydrationBar: ref<DFNeedsHUDBar>;
	private let nutritionBar: ref<DFNeedsHUDBar>;
	private let energyBar: ref<DFNeedsHUDBar>;
	public let nerveBar: ref<DFNeedsHUDBar>;

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
		let fullScreenSlot: ref<inkCompoundWidget> = inkHUD.GetWidgetByPathName(n"Root/NeedBarFullScreenSlot") as inkCompoundWidget;

		if !IsDefined(fullScreenSlot) {
			fullScreenSlot = this.CreateFullScreenSlot(inkHUD);
			this.widgetSlot = this.CreateWidgetSlot(fullScreenSlot);
			this.UpdateHUDWidgetPositionAndScale();
			this.CreateBars(this.widgetSlot, attachedPlayer);

			// Watch for changes to client resolution. Set the correct resolution now to scale all widgets.
			this.virtualResolutionWatcher = new VirtualResolutionWatcher();
			this.virtualResolutionWatcher.Initialize(GetGameInstance());
			this.virtualResolutionWatcher.ScaleWidget(fullScreenSlot);

			this.widgetSlot.SetVisible(this.Settings.mainSystemEnabled && this.Settings.showHUDUI);
		}

		this.UpdateAllBaseGameHUDWidgetPositions();
		this.SendUpdateAllUIRequest();
	}

	public func DoPostSuspendActions() -> Void {
		//DFProfile();
		this.HUDUIBlockedDueToMenuOpen = false;
		this.HUDUIBlockedDueToCameraControl = false;
		this.widgetSlot.SetVisible(false);
		this.UpdateAllBaseGameHUDWidgetPositions();
	}

	public func DoPostResumeActions() -> Void {
		//DFProfile();
		this.widgetSlot.SetVisible(this.Settings.mainSystemEnabled && this.Settings.showHUDUI);
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

		if ArrayContains(changedSettings, "showHUDUI") {
			if IsDefined(this.widgetSlot) {
				this.widgetSlot.SetVisible(this.Settings.showHUDUI);
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

		if ArrayContains(changedSettings, "hidePersistentStatusIcons") {
            // "Bounce" all relevant status effects.
            this.UpdateStatusIcons();
        }

		if ArrayContains(changedSettings, "nerveLossIsFatal") && IsDefined(this.nerveBar) {
			if this.Settings.nerveLossIsFatal {
				this.nerveBar.SetPulseContinuouslyAtLowThreshold(true, 0.1);
			} else {
				this.nerveBar.SetPulseContinuouslyAtLowThreshold(false);
			}
		}

		if ArrayContains(changedSettings, "compatibilityProjectE3HUD") && IsDefined(this.nerveBar) && IsDefined(this.hydrationBar) && IsDefined(this.nutritionBar) && IsDefined(this.energyBar) {
			let shouldShear: Bool = true;
			if this.Settings.compatibilityProjectE3HUD {
				shouldShear = false;
			}

			this.nerveBar.UpdateShear(shouldShear);
			this.hydrationBar.UpdateShear(shouldShear);
			this.nutritionBar.UpdateShear(shouldShear);
			this.energyBar.UpdateShear(shouldShear);
		}
	}

	private final func CreateFullScreenSlot(inkHUD: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		//DFProfile();
		// Create a full-screen slot with dimensions 3840x2160, so that when it is rescaled by Codeware VirtualResolutionWatcher,
		// all of its contents and relative positions are also resized.

		let fullScreenSlot: ref<inkCompoundWidget> = new inkCanvas();
		fullScreenSlot.SetName(n"NeedBarFullScreenSlot");
		fullScreenSlot.SetSize(Vector2(3840.0, 2160.0));
		fullScreenSlot.SetRenderTransformPivot(Vector2(0.0, 0.0));
		fullScreenSlot.Reparent(inkHUD.GetWidgetByPathName(n"Root") as inkCompoundWidget);

		return fullScreenSlot;
	}

	private final func CreateWidgetSlot(parent: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		//DFProfile();
		// Create the slot.
		let widgetSlot: ref<inkCompoundWidget> = new inkCanvas();
		widgetSlot.SetName(n"NeedBarWidgetSlot");
		widgetSlot.SetFitToContent(true);
		widgetSlot.Reparent(parent);

		return widgetSlot;
	}

	private final func UpdateHUDWidgetPositionAndScale() -> Void {
		//DFProfile();
		let scale: Float = this.Settings.hudUIScale;
		let posX: Float = this.Settings.hudUIPosX;
		let posY: Float = this.Settings.hudUIPosY;

		this.widgetSlot.SetScale(Vector2(scale, scale));
		this.widgetSlot.SetTranslation(posX, posY);
	}

	private final func CreateBars(slot: ref<inkCompoundWidget>, attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		slot.RemoveAllChildren();

		let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nerveIconName: CName = n"illegal";
		let nerveBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"nerveBar", nerveIconPath, nerveIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.Rose), 800.0, 700.0, 0.0, 0.0, true, true, r"base\\gameplay\\gui\\common\\stamina_oxygen_bar\\stamina_oxygen_bar.inkatlas", n"ico_lock");
		this.nerveBar = new DFNeedsHUDBar();
		this.nerveBar.Init(nerveBarSetupData);
		if this.Settings.nerveLossIsFatal {
			this.nerveBar.SetPulseContinuouslyAtLowThreshold(true, 0.1);
		}

		// The Nerve Bar is in its own Bar Group so that it can display independently.
		let nerveBarGroup: ref<DFNeedsHUDBarGroup> = new DFNeedsHUDBarGroup();
		nerveBarGroup.Init(attachedPlayer, true);
		nerveBarGroup.AddBarToGroup(this.nerveBar);
		nerveBarGroup.BarGroupSetupDone();

		let hydrationIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let hydrationIconName: CName = n"bar";
		let hydrationBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"hydrationBar", hydrationIconPath, hydrationIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 33.0, 41.0, false, false, r"", n"");
		this.hydrationBar = new DFNeedsHUDBar();
		this.hydrationBar.Init(hydrationBarSetupData);

		let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nutritionIconName: CName = n"food_vendor";
		let nutritionBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"nutritionBar", nutritionIconPath, nutritionIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 53.0 + 230.6, 41.0, false, false, r"", n"");
		this.nutritionBar = new DFNeedsHUDBar();
		this.nutritionBar.Init(nutritionBarSetupData);

		let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let energyIconName: CName = n"wait";
		let energyBarSetupData: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"energyBar", energyIconPath, energyIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 73.0 + 462.2, 41.0, false, false, r"", n"");
		this.energyBar = new DFNeedsHUDBar();
		this.energyBar.Init(energyBarSetupData);

		let physicalNeedsBarGroup: ref<DFNeedsHUDBarGroup> = new DFNeedsHUDBarGroup();
		physicalNeedsBarGroup.Init(attachedPlayer, false);
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

	public final func DisplayUI(uiToShow: DFUIDisplay) -> Void {
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

	public final func RefreshHUDUIVisibility() -> Void {
		//DFProfile();
		this.hydrationBar.EvaluateBarGroupVisibility(false);
	}

	public final func UpdateUI(update: DFNeedHUDUIUpdate) -> Void {
		//DFProfile();
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(update.bar);
	
		this.UpdateBarLimit(bar, update.newLimitValue);
		this.UpdateBar(bar, update.newValue, update.forceMomentaryDisplay, update.instant, update.forceBright, update.momentaryDisplayIgnoresSceneTier, update.fromInteraction, update.showLock);
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

	private final func UpdateBar(bar: ref<DFNeedsHUDBar>, newValue: Float, forceMomentaryDisplay: Bool, instant: Bool, forceBright: Bool, momentaryDisplayIgnoresSceneTier: Bool, fromInteraction: Bool, showLock: Bool) -> Void {
		//DFProfile();
		bar.SetForceBright(instant || forceBright);

		let needValuePct: Float = newValue / 100.0;
		bar.SetProgress(needValuePct, forceMomentaryDisplay, instant, momentaryDisplayIgnoresSceneTier, fromInteraction);

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

				let uiToShow: DFUIDisplay;
				uiToShow.bar = DFHUDBarType.Hydration; // To force all bars to display

				this.DisplayUI(uiToShow);
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

	private final func UpdateStatusIcons() -> Void {
		//DFProfile();
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DummyBuffStatus");
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DummyDebuffStatus");
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
}

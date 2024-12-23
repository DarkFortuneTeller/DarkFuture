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
	wrappedMethod(context);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.UpdateAllHUDUIFromUIContextChange(true, context);
	}
}

@wrapMethod(UISystem)
public final func PopGameContext(context: UIGameContext, opt invalidate: Bool) -> Void {
    wrappedMethod(context, invalidate);

	let HUDSystem: ref<DFHUDSystem> = DFHUDSystem.Get();
	if IsSystemEnabledAndRunning(HUDSystem) {
		HUDSystem.UpdateAllHUDUIFromUIContextChange(false, context);
	}
}

@wrapMethod(UISystem)
public final func ResetGameContext() -> Void {
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
	let val: Bool = wrappedMethod();
	
	if Equals(this.m_RootWidget.GetName(), n"songbird_audiocall") {       // Songbird Audio Call
		DFHUDSystem.Get().SetSongbirdAudiocallWidget(this.m_RootWidget);
	} else if Equals(this.m_RootWidget.GetName(), n"Root") {              // Songbird Holo Call
		DFHUDSystem.Get().SetSongbirdHolocallWidget(this.m_RootWidget);
	}

	return val;
}

// Move normal Audio / Holocall Widget
// Note: Wrapping the OnInitialize callback was causing a crash when taking control of cameras and turrets, use OnPhoneCall() instead.
//
@wrapMethod(NewHudPhoneGameController)
protected cb func OnPhoneCall(value: Variant) -> Bool {
	let val: Bool = wrappedMethod(value);

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
enum DFHUDBarType {
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
}

//
// Classes
//
public final class inkBorderConcrete extends inkBorder {}

public class HUDSystemUpdateUIRequestEvent extends CallbackSystemEvent {
    static func Create() -> ref<HUDSystemUpdateUIRequestEvent> {
        return new HUDSystemUpdateUIRequestEvent();
    }
}

class DFHUDSystemEventListeners extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFHUDSystem> {
		return DFHUDSystem.Get();
	}

    private cb func OnLoad() {
		super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Needs.UpdateHUDUIEvent", this, n"OnUpdateHUDUIEvent", true);
		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Services.DisplayHUDUIEvent", this, n"OnDisplayHUDUIEvent", true);
    }
	
	private cb func OnUpdateHUDUIEvent(event: ref<UpdateHUDUIEvent>) {
		this.GetSystemInstance().UpdateUI(event.GetData());
	}

	private cb func OnDisplayHUDUIEvent(event: ref<DisplayHUDUIEvent>) {
		this.GetSystemInstance().DisplayUI(event.GetData());
	}
}

public final class DFHUDSystem extends DFSystem {
	private let widgetSlot: ref<inkCompoundWidget>;
	private let virtualResolutionWatcher: ref<VirtualResolutionWatcher>;
	private let hydrationBar: ref<DFNeedsHUDBar>;
	private let nutritionBar: ref<DFNeedsHUDBar>;
	private let energyBar: ref<DFNeedsHUDBar>;
	private let nerveBar: ref<DFNeedsHUDBar>;

	private let songbirdAudiocallWidget: ref<inkWidget>;
	private let songbirdHolocallWidget: ref<inkWidget>;
	private let statusEffectListWidget: ref<inkWidget>;

	private let HUDUIBlockedDueToMenuOpen: Bool = false;
	private let HUDUIBlockedDueToCameraControl: Bool = false;

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFHUDSystem> {
		let instance: ref<DFHUDSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.UI.DFHUDSystem") as DFHUDSystem;
		return instance;
	}

	public final static func Get() -> ref<DFHUDSystem> {
		return DFHUDSystem.GetInstance(GetGameInstance());
	}

	//
	//  DFSystem Required Methods
	//
	private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

	private final func GetSystemToggleSettingValue() -> Bool {
		// This system does not have a system-specific toggle.
		return true;
	}

	private final func GetSystemToggleSettingString() -> String {
		// This system does not have a system-specific toggle.
		return "INVALID";
	}

	private func GetSystems() -> Void {}
	private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
	private func SetupData() -> Void {}
	private func RegisterListeners() -> Void {}
	private func RegisterAllRequiredDelayCallbacks() -> Void {}
	private func UnregisterListeners() -> Void {}
	private func UnregisterAllDelayCallbacks() -> Void {}
	public func OnTimeSkipStart() -> Void {}
	public func OnTimeSkipCancelled() -> Void {}
	public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

	private func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
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

	private func DoPostSuspendActions() -> Void {
		this.HUDUIBlockedDueToMenuOpen = false;
		this.HUDUIBlockedDueToCameraControl = false;
		this.widgetSlot.SetVisible(false);
		this.UpdateAllBaseGameHUDWidgetPositions();
	}

	private func DoPostResumeActions() -> Void {
		this.widgetSlot.SetVisible(this.Settings.mainSystemEnabled && this.Settings.showHUDUI);
		this.UpdateAllBaseGameHUDWidgetPositions();
	}

	private func DoStopActions() -> Void {}

	public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
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
		   ArrayContains(changedSettings, "statusEffectListVerticalPositionOffset") {
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
		// Create a full-screen slot with dimensions 3840x2160, so that when it is rescaled by Codeware VirtualResolutionWatcher,
		// all of its contents and relative positions are also resized.

		let fullScreenSlot: ref<inkCompoundWidget> = new inkCanvas();
		fullScreenSlot.SetName(n"NeedBarFullScreenSlot");
		fullScreenSlot.SetSize(new Vector2(3840.0, 2160.0));
		fullScreenSlot.SetRenderTransformPivot(new Vector2(0.0, 0.0));
		fullScreenSlot.Reparent(inkHUD.GetWidgetByPathName(n"Root") as inkCompoundWidget);

		return fullScreenSlot;
	}

	private final func CreateWidgetSlot(parent: ref<inkCompoundWidget>) -> ref<inkCompoundWidget> {
		// Create the slot.
		let widgetSlot: ref<inkCompoundWidget> = new inkCanvas();
		widgetSlot.SetName(n"NeedBarWidgetSlot");
		widgetSlot.SetFitToContent(true);
		widgetSlot.Reparent(parent);

		return widgetSlot;
	}

	private final func UpdateHUDWidgetPositionAndScale() -> Void {
		let scale: Float = this.Settings.hudUIScale;
		let posX: Float = this.Settings.hudUIPosX;
		let posY: Float = this.Settings.hudUIPosY;

		this.widgetSlot.SetScale(new Vector2(scale, scale));
		this.widgetSlot.SetTranslation(posX, posY);
	}

	private final func CreateBars(slot: ref<inkCompoundWidget>, attachedPlayer: ref<PlayerPuppet>) -> Void {
		slot.RemoveAllChildren();

		let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nerveIconName: CName = n"illegal";
		let nerveBarSetupData: DFNeedsHUDBarSetupData = new DFNeedsHUDBarSetupData(slot, n"nerveBar", nerveIconPath, nerveIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.Rose), 800.0, 700.0, 0.0, 0.0, true);
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
		let hydrationBarSetupData: DFNeedsHUDBarSetupData = new DFNeedsHUDBarSetupData(slot, n"hydrationBar", hydrationIconPath, hydrationIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 33.0, 41.0, false);
		this.hydrationBar = new DFNeedsHUDBar();
		this.hydrationBar.Init(hydrationBarSetupData);

		let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let nutritionIconName: CName = n"food_vendor";
		let nutritionBarSetupData: DFNeedsHUDBarSetupData = new DFNeedsHUDBarSetupData(slot, n"nutritionBar", nutritionIconPath, nutritionIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 53.0 + 230.6, 41.0, false);
		this.nutritionBar = new DFNeedsHUDBar();
		this.nutritionBar.Init(nutritionBarSetupData);

		let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
		let energyIconName: CName = n"wait";
		let energyBarSetupData: DFNeedsHUDBarSetupData = new DFNeedsHUDBarSetupData(slot, n"energyBar", energyIconPath, energyIconName, GetDarkFutureBarColorTheme(DFBarColorThemeName.PigeonPost), 231.6, 198.3, 73.0 + 462.2, 41.0, false);
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

	private final func DisplayUI(uiToShow: DFUIDisplay) -> Void {
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(uiToShow.bar);

		if uiToShow.pulse {
			bar.SetPulse();
		} else {
			if NotEquals(bar, null) {
				bar.SetForceBright(uiToShow.forceBright);
				bar.EvaluateBarGroupVisibility(true);
			}
		}
	}

	public final func RefreshHUDUIVisibility() -> Void {
		this.hydrationBar.EvaluateBarGroupVisibility(false);
	}

	public final func UpdateUI(update: DFNeedHUDUIUpdate) -> Void {
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(update.bar);
	
		this.UpdateBarLimit(bar, update.newLimitValue);
		this.UpdateBar(bar, update.newValue, update.forceMomentaryDisplay, update.instant, update.forceBright, update.momentaryDisplayIgnoresSceneTier);
	}

	public final func SendUpdateAllUIRequest() -> Void {
		GameInstance.GetCallbackSystem().DispatchEvent(HUDSystemUpdateUIRequestEvent.Create());
	}

	private final func PulseUI(bar: DFHUDBarType) -> Void {
		let bar: ref<DFNeedsHUDBar> = this.GetHUDBarFromType(bar);
		bar.SetPulse();
	}

	private final func UpdateBar(bar: ref<DFNeedsHUDBar>, newValue: Float, forceMomentaryDisplay: Bool, instant: Bool, forceBright: Bool, momentaryDisplayIgnoresSceneTier: Bool) -> Void {
		bar.SetForceBright(instant || forceBright);

		let needValuePct: Float = newValue / 100.0;
		bar.SetProgress(needValuePct, forceMomentaryDisplay, instant, momentaryDisplayIgnoresSceneTier);
	}

	private final func UpdateBarLimit(bar: ref<DFNeedsHUDBar>, newLimitValue: Float) -> Void {
		let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
		bar.SetProgressEmpty(currentLimitPct);
	}

	public final func UpdateAllHUDUIFromUIContextChange(menuOpen: Bool, opt context: UIGameContext) -> Void {
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
		// Player took or released control of a camera, turret, or the Sniper's Nest.
		this.HUDUIBlockedDueToCameraControl = hasControl;
		this.SendUpdateAllUIRequest();
	}

	public final func SetSongbirdAudiocallWidget(widget: ref<inkWidget>) -> Void {
		this.songbirdAudiocallWidget = widget;
		this.UpdateSongbirdAudiocallWidgetPosition();
	}

	public final func SetSongbirdHolocallWidget(widget: ref<inkWidget>) -> Void {
		this.songbirdHolocallWidget = widget;
		this.UpdateSongbirdHolocallWidgetPosition();
	}

	public final func SetRadialWheelStatusEffectListWidget(widget: ref<inkWidget>) -> Void {
		this.statusEffectListWidget = widget;
		this.UpdateStatusEffectListWidgetPosition();
	}

	public final func UpdateSongbirdAudiocallWidgetPosition() -> Void {
		if IsDefined(this.songbirdAudiocallWidget) &&
		   this.Settings.mainSystemEnabled && 
		   this.Settings.showHUDUI &&
		   this.Settings.updateHolocallVerticalPosition {
				this.songbirdAudiocallWidget.SetMargin(new inkMargin(0.0, this.Settings.holocallVerticalPositionOffset - 13.0, 0.0, 0.0));
			} else {
				this.songbirdAudiocallWidget.SetMargin(new inkMargin(0.0, 0.0, 0.0, 0.0));
		}
	}

	public final func UpdateSongbirdHolocallWidgetPosition() -> Void {
		if IsDefined(this.songbirdHolocallWidget) &&
		   this.Settings.mainSystemEnabled &&
		   this.Settings.showHUDUI &&
		   this.Settings.updateHolocallVerticalPosition {
				this.songbirdHolocallWidget.SetMargin(new inkMargin(70.0, this.Settings.holocallVerticalPositionOffset, 0.0, 0.0));
			} else {
				this.songbirdHolocallWidget.SetMargin(new inkMargin(70.0, 0.0, 0.0, 0.0));
		}
	}

	public final func UpdateNewHudPhoneWidgetPosition(widget: wref<inkCompoundWidget>) -> Void {
		if IsDefined(widget) {
			let incomingCallSlot = widget.GetWidgetByPathName(n"incomming_call_slot");
			let holoAudioCallSlot = widget.GetWidgetByPathName(n"holoaudio_call_slot");
			let holoAudioCallMarker = widget.GetWidgetByPathName(n"holoaudio_call_marker");

			if IsDefined(incomingCallSlot) && IsDefined(holoAudioCallSlot) && IsDefined(holoAudioCallMarker) {
				if this.Settings.mainSystemEnabled &&
				this.Settings.showHUDUI && 
				this.Settings.updateHolocallVerticalPosition {
					let newHoloCallVerticalOffset: Float = this.Settings.holocallVerticalPositionOffset;
					incomingCallSlot.SetMargin(new inkMargin(68.0, 300.0 + newHoloCallVerticalOffset, 0.0, 0.0));
					holoAudioCallSlot.SetMargin(new inkMargin(80.0, 284.0 + newHoloCallVerticalOffset, 0.0, 0.0));
					holoAudioCallMarker.SetMargin(new inkMargin(-50.0, 300.0 + newHoloCallVerticalOffset, 0.0, 0.0));
				} else {
					incomingCallSlot.SetMargin(new inkMargin(-50.0, 300.0, 0.0, 0.0));
					holoAudioCallSlot.SetMargin(new inkMargin(80.0, 284.0, 0.0, 0.0));
					holoAudioCallMarker.SetMargin(new inkMargin(-50.0, 300.0, 0.0, 0.0));
				}
			}
		}
	}

	public final func UpdateStatusEffectListWidgetPosition() -> Void {
		if IsDefined(this.statusEffectListWidget) && 
		   this.Settings.mainSystemEnabled &&
		   this.Settings.showHUDUI &&
		   this.Settings.updateStatusEffectListVerticalPosition {
				this.statusEffectListWidget.SetMargin(new inkMargin(100.0, 0.0, 0.0, 650.0 - this.Settings.statusEffectListVerticalPositionOffset));
			} else {
				this.statusEffectListWidget.SetMargin(new inkMargin(100.0, 0.0, 0.0, 650.0));
		}
	}

	public final func UpdateAllBaseGameHUDWidgetPositions() -> Void {
		this.UpdateSongbirdAudiocallWidgetPosition();
		this.UpdateSongbirdHolocallWidgetPosition();
		this.UpdateStatusEffectListWidgetPosition();
	}

	private final func UpdateStatusIcons() -> Void {
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DummyBuffStatus");
		StatusEffectHelper.ApplyStatusEffect(this.player, t"DarkFutureStatusEffect.DummyDebuffStatus");
	}
}

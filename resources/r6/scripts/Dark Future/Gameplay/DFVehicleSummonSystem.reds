// -----------------------------------------------------------------------------
// DFVehicleSummonSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles vehicle summoning restrictions.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
    RunGuard,
    Int32ToFloat,
    HoursToGameTimeSeconds
}
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Settings.{
    DFSettings,
    SettingChangedEvent
}
import DarkFuture.Services.DFGameStateService

public enum DFSummonCreditWidgetAppearance {
    Default = 0,
    ProjectE3 = 1
}

//
// Overrides
//
// VehiclesManagerPopupGameController
//
@addField(VehiclesManagerPopupGameController)
private let m_player: ref<GameObject>;

@wrapMethod(VehiclesManagerPopupGameController)
protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool {
    wrappedMethod(player);
    this.m_player = player;
}

@wrapMethod(VehiclesManagerPopupGameController)
protected func Select(previous: ref<inkVirtualCompoundItemController>, next: ref<inkVirtualCompoundItemController>) -> Void {
    wrappedMethod(previous, next);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();

    if IsSystemEnabledAndRunning(vehicleSummonSystem) {
        let titleText: ref<inkText> = this.GetRootCompoundWidget().GetWidgetByPathName(n"containerRoot/top_holder/contact_name") as inkText;
        let repairText: ref<inkText> = this.GetRootCompoundWidget().GetWidgetByPathName(n"containerRoot/wrapper/container/image/repairOverlay/repairing/inkTextWidget4") as inkText;
        let summonCredits: Int32 = vehicleSummonSystem.GetRemainingSummonCredits();

        if summonCredits > 0 {
            repairText.SetText(GetLocalizedTextByKey(n"Story-base-gameplay-gui-widgets-vehicle_control-vehicles_manager-repairing"));

            if summonCredits < vehicleSummonSystem.GetMaxSummonCredits() {
                titleText.SetText(GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTotalCredits") + ToString(vehicleSummonSystem.GetRemainingSummonCredits()) + GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpNextCreditTime") + vehicleSummonSystem.GetSummonCooldownRemainingTimeString());
            } else {
                titleText.SetText(GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTotalCredits") + ToString(vehicleSummonSystem.GetRemainingSummonCredits()));
            }
        } else {
            titleText.SetText(GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpLimitReached") + vehicleSummonSystem.GetSummonCooldownRemainingTimeString());
            repairText.SetText(GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpUnavailable"));
            inkWidgetRef.SetOpacity(this.m_vehicleIconContainer, 0.08);
            inkWidgetRef.SetVisible(this.m_repairOverlay, true);
            inkWidgetRef.SetVisible(this.m_confirmButton, false);
        }
    }
}

@wrapMethod(VehiclesManagerPopupGameController)
protected func Activate() -> Void {
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();

    if IsSystemEnabledAndRunning(vehicleSummonSystem) && vehicleSummonSystem.GetRemainingSummonCredits() == 0 {
        return;
    } else {
        wrappedMethod();
    }
}

// VehiclesManagerListItemController
//
@wrapMethod(VehiclesManagerListItemController)
protected cb func OnDataChanged(value: Variant) -> Bool {
    wrappedMethod(value);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();

    if IsSystemEnabledAndRunning(vehicleSummonSystem) && vehicleSummonSystem.GetRemainingSummonCredits() == 0 {
        this.GetRootWidget().SetState(n"Disabled");
    }
}

@wrapMethod(VehiclesManagerListItemController)
protected cb func OnSelected(itemController: wref<inkVirtualCompoundItemController>, discreteNav: Bool) -> Bool {
    wrappedMethod(itemController, discreteNav);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();

    if IsSystemEnabledAndRunning(vehicleSummonSystem) {
        if vehicleSummonSystem.GetRemainingSummonCredits() == 0 {
            this.GetRootWidget().SetState(n"DisabledActive");
        }
    }
}

@wrapMethod(VehiclesManagerListItemController)
protected cb func OnDeselected(itemController: wref<inkVirtualCompoundItemController>) -> Bool {
    wrappedMethod(itemController);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();

    if IsSystemEnabledAndRunning(vehicleSummonSystem) {
        if vehicleSummonSystem.GetRemainingSummonCredits() == 0 {
            this.GetRootWidget().SetState(n"Disabled");
        }
    }
}

// VehicleComponent
//
@wrapMethod(VehicleComponent)
protected cb func OnSummonStartedEvent(evt: ref<SummonStartedEvent>) -> Bool {
    wrappedMethod(evt);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();
    
    if IsSystemEnabledAndRunning(vehicleSummonSystem) {
        if Equals(evt.state, vehicleSummonState.EnRoute) {
            // If this caused the vehicle to spawn or move, it is now the "last summoned" vehicle.
            vehicleSummonSystem.SetLastSummonedVehicle(this);
        } else if Equals(evt.state, vehicleSummonState.AlreadySummoned) {
            // Return a Summon Credit; this vehicle was already summoned.
            vehicleSummonSystem.GrantSummonCredit();
        }
    }
}

// QuickSlotsManager
//
@addField(QuickSlotsManager)
private let activeVehicleJustSet: Bool;

@wrapMethod(QuickSlotsManager)
public final func SetActiveVehicle(vehicleData: PlayerVehicle) -> Void {
    // Used to prevent summoning by tapping the Summon hotkey; require the menu to be opened.
    this.activeVehicleJustSet = true;

    wrappedMethod(vehicleData);
}

@wrapMethod(QuickSlotsManager)
public final func SummonVehicle(force: Bool) -> Void {
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();
    
    if IsSystemEnabledAndRunning(vehicleSummonSystem) && DFGameStateService.Get().IsValidGameState("SummonVehicle") {
        let canSummonVehicle: Bool = force || !GameInstance.GetVehicleSystem(GetGameInstance()).IsActivePlayerVehicleOnCooldown(this.GetActiveVehicleType());
        if !canSummonVehicle {
            return;
        };
    
        if vehicleSummonSystem.GetRemainingSummonCredits() > 0 && this.activeVehicleJustSet {
            // We have summon credits, and we used the menu to select it; summon a vehicle.
            vehicleSummonSystem.UseSummonCredit();
            this.activeVehicleJustSet = false;
            let dpadAction: ref<DPADActionPerformed>;
            dpadAction = new DPADActionPerformed();
            dpadAction.action = EHotkey.DPAD_RIGHT;
            dpadAction.state = EUIActionState.COMPLETED;
            dpadAction.successful = true;
            GameInstance.GetVehicleSystem(GetGameInstance()).SpawnPlayerVehicle(this.GetActiveVehicleType());
            GameInstance.GetUISystem(GetGameInstance()).QueueEvent(dpadAction);

        } else {
            // We don't have summon credits, or we did not use the menu; if we have an active vehicle, ping it.
            let lastSummonedVehicle: ref<VehicleComponent> = vehicleSummonSystem.GetLastSummonedVehicle();
            if IsDefined(lastSummonedVehicle) && !lastSummonedVehicle.GetPS().GetIsDestroyed() {
                // Simulate the "pinging" vehicle behavior of when tapping the summon button
                // when near a vehicle, without actually summoning it. 
                lastSummonedVehicle.CreateMappin();
                lastSummonedVehicle.HonkAndFlash();
            }
        }
    } else {
        wrappedMethod(force);
    }
}

// Cameras and Turrets - Hide Widget
//
@wrapMethod(TakeOverControlSystem)
public final static func CreateInputHint(context: GameInstance, isVisible: Bool) -> Void {
	wrappedMethod(context, isVisible);

	let VehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();
	if IsSystemEnabledAndRunning(VehicleSummonSystem) {
		VehicleSummonSystem.OnTakeControlOfCameraUpdate(isVisible);
	}
}

// HotkeysWidgetController
//
@wrapMethod(HotkeysWidgetController)
protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool {
    wrappedMethod(player);
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();
    
    // Create a quantity widget for the Call Vehicle HUD Widget
    let counterCanvas: ref<inkCanvas> = new inkCanvas();
    counterCanvas.SetVisible(false);    // Initialize to being invisible.
    counterCanvas.SetName(n"counterCanvas");
    counterCanvas.SetAnchor(inkEAnchor.TopLeft);
    counterCanvas.SetHAlign(inkEHorizontalAlign.Center);
    counterCanvas.SetVAlign(inkEVerticalAlign.Center);
    counterCanvas.SetMargin(new inkMargin(158.0, 35.0, 0.0, 0.0));
    counterCanvas.SetSize(new Vector2(100.0, 32.0));
    counterCanvas.Reparent(inkCompoundRef.Get(this.m_carSlot) as inkCompoundWidget, 0);

    let counterFlex: ref<inkFlex> = new inkFlex();
    counterFlex.SetName(n"counterFlex");
    counterFlex.SetAnchor(inkEAnchor.TopLeft);
    counterFlex.SetHAlign(inkEHorizontalAlign.Center);
    counterFlex.SetVAlign(inkEVerticalAlign.Center);
    counterFlex.SetSize(new Vector2(25.0, 25.0));
    counterFlex.Reparent(counterCanvas);

    let counterBg: ref<inkImage> = new inkImage();
    counterBg.SetName(n"counterBg");
    counterBg.SetFitToContent(true);
    counterBg.SetAnchorPoint(new Vector2(0.5, 0.5));
    counterBg.SetMargin(new inkMargin(-3.0, 6.0, -3.0, 8.0));
    counterBg.SetSize(new Vector2(32.0, 32.0));
    counterBg.SetAtlasResource(r"base\\gameplay\\gui\\widgets\\phone\\new_phone_assets.inkatlas");
    counterBg.SetTexturePart(n"counterLabel");
    counterBg.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    counterBg.BindProperty(n"tintColor", n"MainColors.Blue");
    counterBg.BindProperty(n"tileHAlign", n"Fill");
    counterBg.BindProperty(n"tileVAlign", n"Fill");
    counterBg.BindProperty(n"useNineSliceScale", n"True");
    counterBg.Reparent(counterFlex);

    let sizeProvider: ref<inkRectangle> = new inkRectangle();
    sizeProvider.SetName(n"sizeProvider");
    sizeProvider.SetAffectsLayoutWhenHidden(true);
    sizeProvider.SetHAlign(inkEHorizontalAlign.Center);
    sizeProvider.SetVAlign(inkEVerticalAlign.Center);
    sizeProvider.SetSize(new Vector2(21.0, 0.0));
    sizeProvider.SetVisible(false);
    sizeProvider.Reparent(counterFlex);

    let label: ref<inkText> = new inkText();
    label.SetName(n"label");
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    label.SetFontSize(42);
    label.SetFontStyle(n"Semi-Bold");
    label.SetHAlign(inkEHorizontalAlign.Center);
    label.SetVAlign(inkEVerticalAlign.Center);
    label.SetSize(new Vector2(100.0, 32.0));
    label.SetVerticalAlignment(textVerticalAlignment.Bottom);
    label.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    label.BindProperty(n"tintColor", n"MainColors.Black");
    label.BindProperty(n"lockFontInGame", n"True");
    label.Reparent(counterFlex);
    label.SetText("2");

    vehicleSummonSystem.SetHotkeySummonCreditCanvas(counterCanvas);
    vehicleSummonSystem.SetHotkeySummonCreditBackground(counterBg);
    vehicleSummonSystem.SetHotkeySummonCreditLabel(label);
    vehicleSummonSystem.RegisterForVehicleSummonCreditChangeDelayCallback();

    vehicleSummonSystem.UpdateWidgetVisibility();
}

// CarHotkeyController
//
@addMethod(CarHotkeyController)
protected func ResolveState() -> Void {
    super.ResolveState();
    let vehicleSummonSystem: ref<DFVehicleSummonSystem> = DFVehicleSummonSystem.Get();
    
    let state: CName = this.GetRootWidget().GetState();
    if Equals(state, n"Unavailable") {
        vehicleSummonSystem.SetHotkeySummonCreditState(false);
    } else {
        vehicleSummonSystem.SetHotkeySummonCreditState(true);
    }
}

//
// Registration
//
public class VehicleSummonCooldownDelayCallback extends DFDelayCallback {
	public let DFVehicleSummonSystem: wref<DFVehicleSummonSystem>;

	public static func Create(DFVehicleSummonSystem: wref<DFVehicleSummonSystem>) -> ref<DFDelayCallback> {
		let self: ref<VehicleSummonCooldownDelayCallback> = new VehicleSummonCooldownDelayCallback();
		self.DFVehicleSummonSystem = DFVehicleSummonSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSummonSystem.summonCreditCooldownDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSummonSystem.OnSummonCooldownCallback();
	}
}

public class VehicleSummonCreditChangeDelayCallback extends DFDelayCallback {
	public let DFVehicleSummonSystem: wref<DFVehicleSummonSystem>;

	public static func Create(DFVehicleSummonSystem: wref<DFVehicleSummonSystem>) -> ref<DFDelayCallback> {
		let self: ref<VehicleSummonCreditChangeDelayCallback> = new VehicleSummonCreditChangeDelayCallback();
		self.DFVehicleSummonSystem = DFVehicleSummonSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFVehicleSummonSystem.creditChangeDebounceDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFVehicleSummonSystem.OnVehicleSummonCreditChangeDelayCallback();
	}
}

//
// Classes
//
class DFVehicleSummonSystemEventListener extends DFSystemEventListener {
    private func GetSystemInstance() -> wref<DFVehicleSummonSystem> {
		return DFVehicleSummonSystem.Get();
	}
}

public final class DFVehicleSummonSystem extends DFSystem {
    private persistent let remainingSummonCredits: Int32 = 9999;
    private persistent let remainingCooldownTime: Float = 0.0;

    private let GameStateService: ref<DFGameStateService>;

    private let lastSummonedVehicle: ref<VehicleComponent>;

    private let creditsMax: Int32;
    private let summonCreditCooldownDurationGameTimeSeconds: Float;
    private let lastSummonCreditLabelCount: Int32;
    private let UIBlockedDueToCameraControl: Bool = false;

    private let summonCreditCooldownDelayID: DelayID;
    private let summonCreditCooldownDelayIntervalGameTimeSeconds: Float = 300.0;
    
    private let hotkeySummonCreditCanvas: ref<inkCanvas>;
    private let hotkeySummonCreditLabel: ref<inkText>;
    private let hotkeySummonCreditBackground: ref<inkImage>;
    private let creditChangeDebounceDelayID: DelayID;
    private let creditChangeDebounceDelayInterval: Float = 0.25;

    private let chkController: ref<CarHotkeyController>;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFVehicleSummonSystem> {
		let instance: ref<DFVehicleSummonSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Gameplay.DFVehicleSummonSystem") as DFVehicleSummonSystem;
		return instance;
	}

    public final static func Get() -> ref<DFVehicleSummonSystem> {
        return DFVehicleSummonSystem.GetInstance(GetGameInstance());
	}

    //
    //  Required Overrides
    //
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    private func GetSystems() -> Void {
        this.GameStateService = DFGameStateService.Get();
    }
    private func RegisterListeners() -> Void {}
    private func UnregisterListeners() -> Void {}

    private func SetupDebugLogging() -> Void {
		this.debugEnabled = false;
	}

    private func SetupData() -> Void {
        if this.remainingSummonCredits == 9999 {
            this.remainingSummonCredits = this.Settings.maxVehicleSummonCredits;
        }
        this.SetHotkeySummonCreditCount(this.remainingSummonCredits);
        this.lastSummonCreditLabelCount = this.remainingSummonCredits;
        this.creditsMax = this.Settings.maxVehicleSummonCredits;
        this.summonCreditCooldownDurationGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.hoursPerSummonCredit);
    }

    public final func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {	
        this.UpdateWidgetVisibility();
    }

    private final func GetSystemToggleSettingValue() -> Bool {
        return this.Settings.limitVehicleSummoning;
    }

    private final func GetSystemToggleSettingString() -> String {
        return "limitVehicleSummoning";
    }

    public final func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        if ArrayContains(changedSettings, "maxVehicleSummonCredits") {
            this.creditsMax = this.Settings.maxVehicleSummonCredits;
            if this.remainingSummonCredits > this.creditsMax {
                this.remainingSummonCredits = this.creditsMax;
                this.SetHotkeySummonCreditCount(this.remainingSummonCredits);
            }
        }

        if ArrayContains(changedSettings, "hoursPerSummonCredit") {
            this.summonCreditCooldownDurationGameTimeSeconds = HoursToGameTimeSeconds(this.Settings.hoursPerSummonCredit);
            if this.remainingCooldownTime > this.summonCreditCooldownDurationGameTimeSeconds {
                this.remainingCooldownTime = this.summonCreditCooldownDurationGameTimeSeconds;
            }
        }

        if ArrayContains(changedSettings, "compatibilityProjectE3HUD") {
            if this.Settings.compatibilityProjectE3HUD {
                this.SetSummonCreditWidgetAppearance(DFSummonCreditWidgetAppearance.ProjectE3);
            } else {
                this.SetSummonCreditWidgetAppearance(DFSummonCreditWidgetAppearance.Default);
            }
        }
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {
        this.RegisterForSummonCooldown();
    }

    private func UnregisterAllDelayCallbacks() -> Void {
        this.UnregisterForSummonCooldown();
        this.UnregisterForVehicleSummonCreditChangeDelayCallback();
    }

    private final func DoPostSuspendActions() -> Void {
        this.remainingSummonCredits = 9999;
        this.remainingCooldownTime = 0.0;
        this.lastSummonedVehicle = null;
        this.lastSummonCreditLabelCount = 0;
        this.creditsMax = 0;
        this.summonCreditCooldownDurationGameTimeSeconds = 0;
        this.UpdateWidgetVisibility();
    }

    private final func DoPostResumeActions() -> Void {
        this.SetupData();
        this.UpdateWidgetVisibility();
    }

    private final func DoStopActions() -> Void {
        this.lastSummonedVehicle = null;
    }

    //
    //  System-Specific Methods
    //
    public final func OnTakeControlOfCameraUpdate(hasControl: Bool) -> Void {
		// Player took or released control of a camera, turret, or the Sniper's Nest.
		this.UIBlockedDueToCameraControl = hasControl;
		this.UpdateWidgetVisibility();
	}

    public final func UpdateWidgetVisibility() -> Void {
        if IsSystemEnabledAndRunning(this) && IsDefined(this.hotkeySummonCreditCanvas) && !this.UIBlockedDueToCameraControl {
            this.hotkeySummonCreditCanvas.SetVisible(true);
        } else {
            this.hotkeySummonCreditCanvas.SetVisible(false);
        }
    }

    public final func SetHotkeySummonCreditCanvas(widget: ref<inkCanvas>) -> Void {
        this.hotkeySummonCreditCanvas = widget;
    }

    public final func SetHotkeySummonCreditLabel(widget: ref<inkText>) -> Void {
        this.hotkeySummonCreditLabel = widget;
    }

    public final func SetHotkeySummonCreditBackground(widget: ref<inkImage>) -> Void {
        this.hotkeySummonCreditBackground = widget;
    }

    public final func SetHotkeySummonCreditCount(count: Int32) {
        this.hotkeySummonCreditLabel.SetText(ToString(count));
    }

    public final func SetHotkeySummonCreditState(state: Bool) {
        if state {
            if this.Settings.compatibilityProjectE3HUD {
                this.hotkeySummonCreditBackground.BindProperty(n"tintColor", n"MainColors.Red");
            } else {
                this.hotkeySummonCreditBackground.BindProperty(n"tintColor", n"MainColors.Blue");
            }
        } else {
            this.hotkeySummonCreditBackground.BindProperty(n"tintColor", n"MainColors.MildRed");
        }
    }

    public final func GetRemainingSummonCredits() -> Int32 {
        return this.remainingSummonCredits;
    }

    public final func GetMaxSummonCredits() -> Int32 {
        return this.creditsMax;
    }

    public final func GetLastSummonedVehicle() -> ref<VehicleComponent> {
        return this.lastSummonedVehicle;
    }

    public final func SetLastSummonedVehicle(vehicle: ref<VehicleComponent>) -> Void {
        this.lastSummonedVehicle = vehicle;
    }

    public final func UseSummonCredit() -> Void {
        if this.remainingSummonCredits > 0 {
            this.remainingSummonCredits -= 1;
            this.RegisterForVehicleSummonCreditChangeDelayCallback();

            if this.remainingCooldownTime == 0.0 {
                this.remainingCooldownTime = this.summonCreditCooldownDurationGameTimeSeconds;
            }
        }
        DFLog(this.debugEnabled, this, "UseSummonCredit() remainingSummonCredits = " + ToString(this.remainingSummonCredits));
    }

    private final func GrantSummonCredit() -> Void {
        this.remainingSummonCredits = Clamp(this.remainingSummonCredits + 1, 0, this.creditsMax);
        this.RegisterForVehicleSummonCreditChangeDelayCallback();
        DFLog(this.debugEnabled, this, "GrantSummonCredit() remainingSummonCredits = " + ToString(this.remainingSummonCredits));
    }

    private final func PlaySummonCreditRestoreEffects() {
        // Play a composite sound effect and blink the HUD.

        let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
		evt.soundName = n"ui_grenade_recharged";
		this.player.QueueEvent(evt);
        
        evt = new SoundPlayEvent();
		evt.soundName = n"ui_jingle_vehicle_arrive";
		this.player.QueueEvent(evt);

        let dpadAction: ref<DPADActionPerformed>;
        dpadAction = new DPADActionPerformed();
        dpadAction.action = EHotkey.DPAD_RIGHT;
        dpadAction.state = EUIActionState.COMPLETED;
        dpadAction.successful = true;
        GameInstance.GetUISystem(GetGameInstance()).QueueEvent(dpadAction);
    }

    private final func RegisterForSummonCooldown() -> Void {
        RegisterDFDelayCallback(this.DelaySystem, VehicleSummonCooldownDelayCallback.Create(this), this.summonCreditCooldownDelayID, this.summonCreditCooldownDelayIntervalGameTimeSeconds / this.Settings.timescale);
    }

    private final func RegisterForVehicleSummonCreditChangeDelayCallback() -> Void {
        RegisterDFDelayCallback(this.DelaySystem, VehicleSummonCreditChangeDelayCallback.Create(this), this.creditChangeDebounceDelayID, this.creditChangeDebounceDelayInterval);
    }

    private final func UnregisterForSummonCooldown() -> Void {
        UnregisterDFDelayCallback(this.DelaySystem, this.summonCreditCooldownDelayID);
    }

    private final func UnregisterForVehicleSummonCreditChangeDelayCallback() -> Void {
        UnregisterDFDelayCallback(this.DelaySystem, this.creditChangeDebounceDelayID);
    }

    public final func OnSummonCooldownCallback() -> Void {
        if this.GameStateService.IsValidGameState("OnSummonCooldownCallback") {
            this.remainingCooldownTime -= this.summonCreditCooldownDelayIntervalGameTimeSeconds;
            if this.remainingCooldownTime <= 0.0 {
                this.remainingCooldownTime = 0.0;
                this.GrantSummonCredit();
                if this.remainingSummonCredits < this.creditsMax {
                    this.remainingCooldownTime = this.summonCreditCooldownDurationGameTimeSeconds;
                }
            }
        }
        this.RegisterForSummonCooldown();
        DFLog(this.debugEnabled, this, "OnSummonCooldownCallback() remainingSummonCredits = " + ToString(this.remainingSummonCredits) + ", remainingCooldownTime = " + ToString(this.remainingCooldownTime));
    }

    public final func OnVehicleSummonCreditChangeDelayCallback() -> Void {
        this.SetHotkeySummonCreditCount(this.remainingSummonCredits);

        if this.lastSummonCreditLabelCount < this.remainingSummonCredits {
           this.PlaySummonCreditRestoreEffects();
        }

        this.lastSummonCreditLabelCount = this.remainingSummonCredits;
    }

    public final func OnTimeSkipStart() -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipStart");

		this.UnregisterForSummonCooldown();
	}

	public final func OnTimeSkipCancelled() -> Void {
		if RunGuard(this) { return; }
		DFLog(this.debugEnabled, this, "OnTimeSkipStart");

		this.RegisterForSummonCooldown();
	}

    public final func OnTimeSkipFinished(data: DFTimeSkipData) {
        if RunGuard(this) { return; }

        let secondsPassed: Float = Int32ToFloat(data.hoursSkipped) * 3600.0;
        let creditsToGrant: Int32 = FloorF(((this.summonCreditCooldownDurationGameTimeSeconds - this.remainingCooldownTime) + secondsPassed) / this.summonCreditCooldownDurationGameTimeSeconds);
        this.remainingSummonCredits = Clamp(this.remainingSummonCredits + creditsToGrant, 0, this.creditsMax);
        this.RegisterForVehicleSummonCreditChangeDelayCallback();

        let timeLeftOver: Float = ((this.summonCreditCooldownDurationGameTimeSeconds - this.remainingCooldownTime) + secondsPassed) % this.summonCreditCooldownDurationGameTimeSeconds;
        if this.remainingSummonCredits < this.creditsMax {
            this.remainingCooldownTime = this.summonCreditCooldownDurationGameTimeSeconds - timeLeftOver;
        } else {
            this.remainingCooldownTime = 0.0;
        }

        this.RegisterForSummonCooldown();
        
        DFLog(this.debugEnabled, this, "OnTimeSkip() hoursSkipped = " + ToString(data.hoursSkipped) + " remainingSummonCredits = " + ToString(this.remainingSummonCredits) + ", remainingCooldownTime = " + ToString(this.remainingCooldownTime));
    }

    public final func GetSummonCooldownRemainingTimeString() -> String {
        if this.remainingCooldownTime > 0.0 {
            let hours: Int32 = FloorF(this.remainingCooldownTime / 3600.0);
            let minutes: Int32 = FloorF((this.remainingCooldownTime % 3600.0) / 60.0);

            if hours > 0 && minutes > 0 {
                return ToString(hours) + GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeHourAbbreviation") + " " + ToString(minutes) + GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeMinuteAbbreviation");
            } else if hours > 0 {
                return ToString(hours) + GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeHourAbbreviation");
            } else if minutes > 0 {
                return ToString(minutes) + GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeMinuteAbbreviation");
            } else {
                return GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeLessThanOneMinuteAbbreviation");
            }
        } else {
            return GetLocalizedTextByKey(n"DarkFutureSummonCarPopUpTimeLessThanOneMinuteAbbreviation");
        }
    }

    public final func SetCarHotkeyController(controller: ref<CarHotkeyController>) -> Void {
        DFLog(this.debugEnabled, this, "SetCarHotkeyController " + ToString(controller));
        this.chkController = controller;
    }

    public final func SetSummonCreditWidgetAppearance(appearance: DFSummonCreditWidgetAppearance) {
        if IsDefined(this.hotkeySummonCreditCanvas) && IsDefined(this.hotkeySummonCreditBackground) {
            switch appearance {
                case DFSummonCreditWidgetAppearance.Default:
                    this.hotkeySummonCreditCanvas.SetMargin(new inkMargin(158.0, 35.0, 0.0, 0.0));
                    this.hotkeySummonCreditCanvas.SetScale(new Vector2(1.0, 1.0));
                    this.hotkeySummonCreditBackground.BindProperty(n"tintColor", n"MainColors.Blue");
                    break;
                case DFSummonCreditWidgetAppearance.ProjectE3:
                    this.hotkeySummonCreditCanvas.SetMargin(new inkMargin(34.0, 152.0, 0.0, 0.0));
                    this.hotkeySummonCreditCanvas.SetScale(new Vector2(0.8, 0.8));
                    this.hotkeySummonCreditBackground.BindProperty(n"tintColor", n"MainColors.Red");
                    break;
            }
        }
    }
}
// -----------------------------------------------------------------------------
// DFStashCraftingSystem
// -----------------------------------------------------------------------------
//
// - Gameplay System that handles restricting crafting to V's stash containers.
//

module DarkFuture.Gameplay

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Settings.DFSettings
import DarkFuture.Main.DFTimeSkipData
import DarkFuture.Utils.IsRevisedBackpackInstalled

public final class DFStashCraftingSystem extends DFSystem {
    public let inGameMenuGameController: ref<gameuiInGameMenuGameController>;
    public let craftingAllowed: Bool = false;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFStashCraftingSystem> {
        //DFProfile();
		let instance: ref<DFStashCraftingSystem> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFStashCraftingSystem>()) as DFStashCraftingSystem;
		return instance;
	}

	public final static func Get() -> ref<DFStashCraftingSystem> {
        //DFProfile();
		return DFStashCraftingSystem.GetInstance(GetGameInstance());
	}

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }
    public func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        return this.Settings.stashCraftingEnabled;
    }
    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "stashCraftingEnabled";
    }
    public func DoPostSuspendActions() -> Void {}
    public func DoPostResumeActions() -> Void {}
    public func GetSystems() -> Void {}
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}
    public func SetupData() -> Void {}
    private func RegisterListeners() -> Void {}
    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    private func UnregisterListeners() -> Void {}
    public func UnregisterAllDelayCallbacks() -> Void {}
    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}
    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {}
    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    public final func SetInGameMenuGameController(inGameMenuGameController: ref<gameuiInGameMenuGameController>) {
        //DFProfile();
        this.inGameMenuGameController = inGameMenuGameController;
    }
}

public class OpenCraft extends ActionBool {
	public final func SetProperties() -> Void {
        //DFProfile();
    	this.actionName = n"OpenCraft";
    	this.prop = DeviceActionPropertyFunctions.SetUpProperty_Bool(this.actionName, true, this.actionName, this.actionName);
  	}

    public final static func IsDefaultConditionMet(device: ref<ScriptableDeviceComponentPS>, const context: script_ref<GetActionsContext>) -> Bool {
        //DFProfile();
        if OpenStash.IsAvailable(device) && OpenStash.IsClearanceValid(Deref(context).clearance) {
            return true;
        };
        return false;
    }

    public final static func IsAvailable(device: ref<ScriptableDeviceComponentPS>) -> Bool {
        //DFProfile();
        if device.IsUnpowered() || device.IsDisabled() {
            return false;
        };
        return true;
    }

    public final static func IsClearanceValid(clearance: ref<Clearance>) -> Bool {
        //DFProfile();
        if Clearance.IsInRange(clearance, 2) {
            return true;
        };
        return false;
    }
}

//
//  UI
//

//  MenuScenario_BaseMenu - Re-block crafting when the player exits the top-level Hub Menu.
//
@wrapMethod(MenuScenario_BaseMenu)
protected func GotoIdleState() -> Void {
    //DFProfile();
    wrappedMethod();
    DFStashCraftingSystem.Get().craftingAllowed = false;
}

//  gameuiInGameMenuGameController - Grab a reference of this inkGameController on initialization
//  so that we can use it to open the crafting menu later.
//
@wrapMethod(gameuiInGameMenuGameController)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
	DFStashCraftingSystem.Get().SetInGameMenuGameController(this);
    return wrappedMethod();
}

//  gameuiInGameMenuGameController - Disable the Crafting Menu Hotkey.
//
@wrapMethod(gameuiInGameMenuGameController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    //DFProfile();
    if IsSystemEnabledAndRunning(DFStashCraftingSystem.Get()) {
        if Equals(ListenerAction.GetName(action), n"OpenCraftingMenu") {
            return false;
        }
    }

    return wrappedMethod(action, consumer);
}

//  HubMenuUtility - Block access to the Crafting Menu unless DFStashCraftingSystem
//  has seen the player press the interaction button.
//
@wrapMethod(HubMenuUtility)
public final static func IsCraftingAvailable(player: wref<PlayerPuppet>) -> Bool {
    //DFProfile();
    let stashCraftingSystem: wref<DFStashCraftingSystem> = DFStashCraftingSystem.Get();
    if IsSystemEnabledAndRunning(stashCraftingSystem) && !stashCraftingSystem.craftingAllowed {
        return false;
    } else {
        return wrappedMethod(player);
    }
}

//  gameuiInventoryGameController - Remove gap between "Backpack" and "Stats" buttons
//  in Inventory screen when Crafting button is hidden. (It is already hidden by default.)
//
@wrapMethod(gameuiInventoryGameController)
protected cb func OnSetUserData(userData: ref<IScriptable>) -> Bool {
    //DFProfile();
    let val: Bool = wrappedMethod(userData);

    if !HubMenuUtility.IsCraftingAvailable(this.m_player) {
        inkWidgetRef.Get(this.m_btnCrafting).SetAffectsLayoutWhenHidden(false);
    }

    return val;
}

//  MenuItemController - Hide the Hub Menu Crafting button if it is in
//  a disabled state, instead of always showing "Unavailable" outside of
//  the Stash context.
//
//  Update (1.1): Show the "Unavailable" button if Revised Backpack is installed
//  in order to avoid a "floating" button.
//
@wrapMethod(MenuItemController)
public final func Init(const menuData: script_ref<MenuData>) -> Void {
    //DFProfile();
    wrappedMethod(menuData);
    if this.m_menuData.disabled && Equals(inkImageRef.GetTexturePart(this.m_icon), n"ico_cafting") && !IsRevisedBackpackInstalled() {
        this.GetRootWidget().SetVisible(false);
    }
}

//
//  HIDEOUT STASH
//

//  Stash - Event callback handler for new Crafting Action.
//
@addMethod(Stash)
protected cb func OnOpenCraft(evt: ref<OpenCraft>) -> Bool {
    //DFProfile();
    this.TryOpenCraftingMenu();
}

//  Stash - Open the Crafting Menu using the gameuiInGameMenuGameController, 
//  identically to using a HotKey. Let the Stash Crafting System know that it's OK
//  to open crafting.
//
@addMethod(Stash)
private final func TryOpenCraftingMenu() -> Void {
    //DFProfile();
    DFStashCraftingSystem.Get().craftingAllowed = true;
	DFStashCraftingSystem.Get().inGameMenuGameController.TryOpenCraftingMenu(n"OpenCraftingMenu");
}

//  StashControllerPS - Add a Crafting Interaction Action.
//
@addMethod(StashControllerPS)
private final func ActionOpenCraft() -> ref<OpenCraft> {
    //DFProfile();
    let action: ref<OpenCraft> = new OpenCraft();
    action.clearanceLevel = 2;
    action.SetUp(this);
    action.SetProperties();
    action.AddDeviceName(this.m_deviceName);
    action.CreateInteraction();
    return action;
}

//  StashControllerPS - Emit the new Action as an Event.
//
@addMethod(StashControllerPS)
private final func OnOpenCraft(evt: ref<OpenCraft>) -> EntityNotificationType {
    //DFProfile();
    this.UseNotifier(evt);
    return EntityNotificationType.SendThisEventToEntity;
}

//  StashControllerPS - Push the Crafting Action into the set of Actions.
//
@wrapMethod(StashControllerPS)
public func GetActions(out outActions: array<ref<DeviceAction>>, context: GetActionsContext) -> Bool {
    //DFProfile();
    if IsSystemEnabledAndRunning(DFStashCraftingSystem.Get()) {
	    ArrayPush(outActions, this.ActionOpenCraft());
    }
	return wrappedMethod(outActions, context);
}

//
//  VEHICLE STASH
//

//  VehicleComponentPS - Add a Crafting Interaction Action.
//
@addMethod(VehicleComponentPS)
private final func ActionOpenCraft() -> ref<OpenCraft> {
    //DFProfile();
    let action: ref<OpenCraft> = new OpenCraft();
    action.clearanceLevel = 2;
    action.SetUp(this);
    action.SetProperties();
    action.AddDeviceName(this.GetDeviceName());
    action.CreateInteraction();
    return action;
}

//  VehicleComponentPS - Add a Crafting Interaction Action.
//
@wrapMethod(VehicleComponentPS)
public final func GetTrunkActions(actions: script_ref<array<ref<DeviceAction>>>, const context: script_ref<VehicleActionsContext>) -> Void {
    //DFProfile();
    wrappedMethod(actions, context);

    let foundAction: Bool = false;
    let i: Int32 = 0;
    while i < ArraySize(Deref(actions)) && !foundAction {
        if IsDefined(Deref(actions)[i] as VehiclePlayerTrunk) {
            foundAction = true;
        }
        i += 1;
    }

    if foundAction && IsSystemEnabledAndRunning(DFStashCraftingSystem.Get()) {
        ArrayPush(Deref(actions), this.ActionOpenCraft());
    }
}

//  VehicleComponentPS - Emit the new Action as an Event.
//
@addMethod(VehicleComponentPS)
private final func OnOpenCraft(evt: ref<OpenCraft>) -> EntityNotificationType {
    //DFProfile();
    this.UseNotifier(evt);
    return EntityNotificationType.SendThisEventToEntity;
}

//  VehicleComponent - Event callback handler for new Crafting Action.
//
@addMethod(VehicleComponent)
protected cb func OnOpenCraft(evt: ref<OpenCraft>) -> Bool {
    //DFProfile();
    this.TryOpenCraftingMenu();
}

//  VehicleComponent - Open the Crafting Menu using the gameuiInGameMenuGameController, 
//  identically to using a HotKey. Let the Stash Crafting System know that it's OK
//  to open crafting.
//
@addMethod(VehicleComponent)
private final func TryOpenCraftingMenu() -> Void {
    //DFProfile();
    DFStashCraftingSystem.Get().craftingAllowed = true;
	DFStashCraftingSystem.Get().inGameMenuGameController.TryOpenCraftingMenu(n"OpenCraftingMenu");
}
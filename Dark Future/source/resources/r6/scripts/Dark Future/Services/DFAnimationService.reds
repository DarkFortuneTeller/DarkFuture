// -----------------------------------------------------------------------------
// DFAnimationService
// -----------------------------------------------------------------------------
//
// - Service that handles player animation playback.
//

module DarkFuture.Services

import DarkFuture.Logging.*
import DarkFuture.System.*
import DarkFuture.Utils.*
import DarkFuture.DelayHelper.*
import DarkFuture.Settings.{
    DFSettings,
    DFConsumableAnimationCooldownBehavior,
    DFCrashAnimSetting
}
import DarkFuture.Main.{
    DFMainSystem,
    DFNeedsDatum,
    DFAddictionDatum,
    DFAddictionUpdateDatum,
    DFHumanityLossDatum,
    DFBiocorruptionDatum,
    MainSystemItemConsumedEvent,
    DFFutureHoursData,
    DFTimeSkipData,
    DFTimeSkipType
}
import DarkFuture.Services.{
    GameState,
	DFGameStateService,
    DFNotificationService
}
import DarkFuture.Addictions.{
    DFAddictionSystemBase,
    DFNicotineAddictionSystem,
    DFAlcoholAddictionSystem,
    DFNarcoticAddictionSystem

}
import DarkFuture.Conditions.{
    DFBiocorruptionConditionSystem,
    DFQueuedCrashType
}
import DarkFuture.Gameplay.{
    DFInteractionSystem,
    DFImpairedDrivingSystem,
    DFRelaxActionSystem
}
import DarkFuture.Needs.{
    DFEnergySystem,
    DFNerveSystem
}

// AudioSystem - Don't play item action sounds immediately, instead allow the Animation Service
// to attempt to play them. If we don't play the animation, the Animation Service will play
// the sound.
//
@wrapMethod(AudioSystem)
public final func PlayItemActionSound(action: CName, itemData: wref<gameItemData>) -> Void {
    //DFProfile();
    if IsSystemEnabledAndRunning(DFAnimationService.Get()) && (Equals(action, n"Eat") || Equals(action, n"Drink") || Equals(action, n"Consume")) {
        this.Play(n"g_sc_v_work_grab");
    } else {
        wrappedMethod(action, itemData);
    }
}

////
//// Credit: Portions of LootingController code below code adapted from Disassemble As Looting Choice (Author: pMarK)
////

// LootingController - Helper method to obtain the entity of the loot container currently being looked at.
//
@addMethod(LootingController)
public func DFGetOwningLootEntity() -> wref<GameObject> {
    return GameInstance.FindEntityByID(this.m_gameInstance, this.m_currendData.ownerId) as GameObject;
}

// LootingContainer - Helper method to check if a Consumable Animations prompt is already being shown.
//
@addMethod(LootingController)
private func DFIsAnimatedConsumeChoiceShown(data: LootData) -> Bool {
    for choice in data.choices {
        if Equals(choice.localizedName, GetLocalizedTextByKey(n"ConsumableAnimChoiceDrinkAnimated")) ||
           Equals(choice.localizedName, GetLocalizedTextByKey(n"ConsumableAnimChoiceDrinkChugAnimated")) ||
           Equals(choice.localizedName, GetLocalizedTextByKey(n"ConsumableAnimChoiceEatAnimated")) ||
           Equals(choice.localizedName, GetLocalizedTextByKey(n"ConsumableAnimChoiceConsumeAnimated")) ||
           Equals(choice.localizedName, GetLocalizedTextByKey(n"ConsumableAnimChoiceSmokeAnimated")) {
            return true;
        }
    }

    return false;
}

// LootingContainer - Helper method to obtain the currently selected gameItemData in the active loot container.
//
@addMethod(LootingController)
public func DFGetSelectedLootGameItemData() -> ref<gameItemData> {
    return this.m_dataManager.GetExternalGameItemData(this.m_currendData.ownerId, this.m_currendData.itemIDs[this.m_currendData.currentIndex]);
}

// LootingContainer - Helper method to obtain the currently selected InventoryItemData in the active loot container.
//
@addMethod(LootingController)
public func DFGetSelectedLootInventoryItemData() -> InventoryItemData {
    let itemData: ref<gameItemData> = this.DFGetSelectedLootGameItemData();
    return this.m_dataManager.GetInventoryItemData(this.DFGetOwningLootEntity(), itemData);
}

// LootingContainer - Checks if the currently selected item in the loot container is an animated consumable.
//
@addMethod(LootingController)
public func DFIsAnimatedConsumable() -> Bool {
    let itemData: ref<gameItemData> = this.DFGetSelectedLootGameItemData();

    if itemData.HasTag(n"DarkFutureAnimatedConsumable") {
        return true;
    }

    return false;
}

@addMethod(LootingController)
public func DFIsConsumptionAllowed() -> Bool {
    let itemData: ref<gameItemData> = this.DFGetSelectedLootGameItemData();

    // Simplification - Just disable if player in Overdose instead of checking item types.
    let inOverdose: Bool = DFPlayerStateService.Get().GetInOverdose();
    let hasNausea: Bool = DFNerveSystem.Get().GetHasNausea();
    let isFood: Bool = itemData.HasTag(n"Food");
    
    if inOverdose {
        return false;

    } else if isFood && hasNausea {
        return false;

    } else {
        return true;
    }
    
}

// LootingContainer - Helper method to obtain the selected item's Secondary Action Name.
//
@addMethod(LootingController)
public final func DFGetSelectedItemSecondaryActionName() -> CName {
    let currentItem: InventoryItemData = this.DFGetSelectedLootInventoryItemData();
    let itemTDBID: TweakDBID = ItemID.GetTDBID(currentItem.GameItemData.GetID());
    let itemRecord: ref<Item_Record> = TweakDBInterface.GetItemRecord(itemTDBID);
    return itemRecord.ItemSecondaryAction().ActionName();
}

// LootingContainer - Add the new choice prompt, if the feature is enabled.
//
@addMethod(LootingController)
private final func DFUpdateAnimatedConsumeChoice(data: LootData) -> LootData {
    let Settings = DFSettings.Get();
    let AnimService = DFAnimationService.Get();

    if Settings.consumableAnimationsEnabled && 
        Settings.consumableAnimationLootActionEnabled && 
        this.DFIsAnimatedConsumable() && 
        this.DFIsConsumptionAllowed() &&
        !this.m_isLocked && 
        !AnimService.player.m_inCrouch {
        if !this.DFIsAnimatedConsumeChoiceShown(data) {
            AnimService.SetLootingController(this);

            let captionTextKey: CName;
            let actionName: CName = this.DFGetSelectedItemSecondaryActionName();

            if this.DFGetSelectedLootGameItemData().HasTag(n"DarkFutureAnimatedConsumableDrinkChug") {
                captionTextKey = n"ConsumableAnimChoiceDrinkChugAnimated";

            } else if this.DFGetSelectedLootGameItemData().HasTag(n"DarkFutureAnimSmoking") {
                captionTextKey = n"ConsumableAnimChoiceSmokeAnimated";

            } else if Equals(actionName, n"Drink") {
                captionTextKey = n"ConsumableAnimChoiceDrinkAnimated";

            } else if Equals(actionName, n"Eat") {
                captionTextKey = n"ConsumableAnimChoiceEatAnimated";

            } else if Equals(actionName, n"Consume") {
                captionTextKey = n"ConsumableAnimChoiceConsumeAnimated";
            }

            let choiceData: InteractionChoiceData;
            choiceData.inputAction = n"DFAnimatedConsumableManualChoiceAction";
            choiceData.isHoldAction = true;
            choiceData.localizedName = GetLocalizedTextByKey(captionTextKey);
            choiceData.type = this.m_currendData.choices[0].type;
            choiceData.data = this.m_currendData.choices[0].data;
            choiceData.captionParts = this.m_currendData.choices[0].captionParts;

            ArrayPush(data.choices, choiceData);
        }
        AnimService.player.RegisterInputListener(AnimService, n"DFAnimatedConsumableManualChoiceAction");
    
    } else {
        AnimService.player.UnregisterInputListener(AnimService, n"DFAnimatedConsumableManualChoiceAction");
    }

    return data;
}

// LootingContainer - When displaying the choices pool, update the input registration.
//
@wrapMethod(LootingController)
private final func RefreshChoicesPool(choices: script_ref<array<InteractionChoiceData>>) -> Void {
    this.m_currendData = this.DFUpdateAnimatedConsumeChoice(this.m_currendData);

    wrappedMethod(this.m_currendData.choices);
}

// LootingContainer - When hiding the choices pool, always unregister for input handling.
//
@wrapMethod(LootingController)
public final func Hide() -> Void {
    wrappedMethod();
    let AnimService = DFAnimationService.Get();
    AnimService.player.UnregisterInputListener(AnimService, n"DFAnimatedConsumableManualChoiceAction");
}

// PocketRadio - Helper function to set / unset playback restriction override.
//
@addMethod(PocketRadio)
public final func DFSetRestrictionOverride(override: Bool) -> Void {
    if override {
        this.m_isRestrictionOverwritten = true;
        this.m_isConditionRestricted = false;
        this.HandleRestrictionStateChanged();
    } else {
        this.m_isRestrictionOverwritten = false;
    }
}

// VehicleComponent - Add a method to force dismount the player from a bike.
//                    Modified version of VehicleComponent.OnDelayedBikeKnockOffEvent().
//
@addMethod(VehicleComponent)
public final func DarkFutureForceBikeDismount(player: ref<PlayerPuppet>) -> Void {
    DFLogNoSystem(DFSystemlessDebugEnabled(), this, "####### FORCING BIKE DISMOUNT");
    let bike: ref<BikeObject> = this.GetVehicle() as BikeObject;
    let driver: ref<GameObject> = VehicleComponent.GetDriverMounted(bike.GetGame(), this.GetVehicle().GetEntityID());
    if driver != null {
        if IsDefined(driver as PlayerPuppet) {
            DFLogNoSystem(DFSystemlessDebugEnabled(), this, "####### EXECUTING");
            // Apply a collision vector that is offset by a few degrees to ensure that V is sent clear of the bike.
            let collisionForceVector: Vector4 = -bike.GetLinearVelocity();
            bike.AddCollisionForce(collisionForceVector);
        } else {
            DFLogNoSystem(DFSystemlessDebugEnabled(), this, "####### DRIVER NOT PLAYERPUPPET");
        }
    } else {
        DFLogNoSystem(DFSystemlessDebugEnabled(), this, "####### DRIVER NULL");
    }
    this.ToggleVehicleSystems(false, false, false);
}

// VehicleObject - Check for animations when exiting a vehicle.
//
@wrapMethod(VehicleObject)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
	//DFProfile();
	let r = wrappedMethod(evt);

	let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
	if IsSystemEnabledAndRunning(DFAnimationService.Get()) && IsDefined(mountChild) && mountChild.IsPlayer() {
		DFAnimationService.Get().CheckIfPlayerShouldBlackOut();
	}
	
	return r;
}

public class BlackoutForceBikeDismountRecheckAnimValidityDelayCallback extends DFDelayCallback {
    public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
        return new BlackoutForceBikeDismountRecheckAnimValidityDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFAnimationService.Get().blackoutForceBikeDismountRecheckAnimValidityDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFAnimationService.Get().OnBlackoutForceBikeDismountCheckAnimValidity();
	}
}

public class ContextuallyDelayedBlackoutAnimationDelayCallback extends DFDelayCallback {
    public static func Create() -> ref<DFDelayCallback> {
        //DFProfile();
        return new ContextuallyDelayedBlackoutAnimationDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFAnimationService.Get().contextuallyDelayedBlackoutAnimationDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFAnimationService.Get().TryToQueueBlackoutAnimation();
	}
}

public class ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback extends DFDelayCallback {
    public let addictionData: DFAddictionDatum;
    public let timeSkipType: DFTimeSkipType;

    public static func Create(addictionData: DFAddictionDatum, timeSkipType: DFTimeSkipType) -> ref<DFDelayCallback> {
        //DFProfile();
        let self = new ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback();
		self.addictionData = addictionData;
        self.timeSkipType = timeSkipType;
        return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFAnimationService.Get().contextuallyDelayedAddictionWithdrawalAnimationDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFAnimationService.Get().TryToQueueAddictionWithdrawalAnimation(this.addictionData, this.timeSkipType);
	}
}

public class ContextuallyDelayedCrashAnimationDelayCallback extends DFDelayCallback {
    let mode: DFCrashAnimMode;

    public static func Create(mode: DFCrashAnimMode) -> ref<DFDelayCallback> {
        //DFProfile();
        let self: ref<ContextuallyDelayedCrashAnimationDelayCallback> = new ContextuallyDelayedCrashAnimationDelayCallback();
        self.mode = mode;
        return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		DFAnimationService.Get().contextuallyDelayedCrashAnimationDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		DFAnimationService.Get().TryToQueueCrashAnimation(this.mode);
	}
}

private enum DFAnimQuestPhaseGraphDebugMessageID {
    None = 0,
    Start = 1,
    FailedConditionCheck = 2,
    SelectedAnimTypeAndID = 3,
    Done = 4
}

public enum DFAnimType {
    Invalid = 0,
    Consumable = 1,
    Withdrawal = 2,
    Blackout = 3,
    Crash = 4
}

private enum DFConsumableAnimType {
    Invalid = 0,
    Drugs = 1,
    DrinkSipRightHand = 2,
    DrinkChugLeftHand = 3,
    EatDrinkThinPackagedLeftHand = 4,
    EatLookDownRightHand = 5
}

public enum DFConsumableAnimSubType {
    Invalid = 0,
    EatDrinkThinPackagedLeftHand = 1,
    EatLookDownRightHand = 2,
    DrinkSipRightHand = 3,
    DrinkChugLeftHand = 4,
    HealthBooster = 5,
    Smoking = 6,
    Pills = 7,
    Inhaler = 8,
    MrWhitey = 9
}

private enum DFConsumableAnimPropType {
    Invalid = 0,
    Smoking = 1,
    MrWhitey = 2,
    PharmaceuticalLarge = 7,
    PharmaceuticalThinPackaged = 8,
    PharmaceuticalInhaler = 3,
    DrugInhaler = 4,
    HealthBooster = 5,
    Pill = 6,
    CoffeeTeaToGo = 9,
    CoffeeTeaOpenCup = 10,
    SodaCan = 11,
    WaterBottle = 12,
    SmallBottle = 13,
    Cocktail = 14,
    LargeBottle = 15,
    SodaCanChug = 16,
    ThinPackagedFood = 17,
    ThinPackagedDrink = 18,
    LargeFood = 19,
    CatFood = 20   
}

private enum DFConsumableAnimPropSubType {
    Invalid = 0,
    Smoking = 1,
    MrWhitey = 2,
    Addiquit = 3,
    EmergencyCardioregulator = 4,
    Glitter = 5,
    BlackLace = 6,
    HealthBooster = 7,
    Pill_A = 8,
    Pill_B = 9,
    CoffeeTeaToGo = 10,
    CoffeeTeaOpenCup = 11,
    Nicola = 12,
    CirrusCola = 13,
    Tiancha = 14,
    SpunkyMonkey = 15,
    Chromanticore = 16,
    WaterBottle = 17,
    BrosephBottle = 18,
    AbydosSmall = 19,
    Cocktail = 20,
    Vatnajokull = 21,
    Wine = 22,
    CalaveraFeliz = 23,
    Champaradise = 24,
    Donaghys = 25,
    Centzon = 26,
    JoeTiel = 27,
    AbydosLarge = 28,
    Bumelant = 29,
    ChamparadiseInverted = 30,
    JoeTielInverted = 31,
    CentzonInverted = 32,
    Odickin = 33,
    OdickinInverted = 34,
    Bolshevik = 35,
    TequilaEspecial = 36,
    CentzonIndigoUnique = 37,
    TequilaEspecialInverted = 38,
    PingoPalido = 39,
    GenericHooch = 40,
    TwentyFirstStout = 41,
    BlueGrass = 42,
    ChromanticoreChug = 43,
    SainRuisseau = 44,
    Burrito = 45,
    Holobites = 46,
    Moonchies = 47,
    LeelouBeans = 48,
    PopTurd = 49,
    ShwabShwab = 50,
    ThinPackagedGeneric = 51,
    CatFood = 52,
    DaringDairy = 53,
    ThinPackagedGenericLarge = 54,
    SynthSnack = 55,
    SynthSnackNoLabel = 56,
    CandyBar = 57,
    LeelouBeansInverted = 58,
    RAMNugs = 59,
    Wontons = 60,
    Taco = 61,
    HotDog = 62,
    SoupLight = 63,
    SoupDark = 64,
    LargePackagedGenericGold = 65,
    LargePackagedGenericSilver = 66,
    Fruit = 67,
    BeefCan = 68,
    Ramen = 69,
    Pizza = 70,
    MeatLog = 71,
    Nigiri = 72,
    DriedMeat = 73,
    Sandwich = 74,
    Pierogi = 75,
    Cupcake = 76,
    Norimaki = 77,
    Jellytricity = 78,
    Immunosuppressant = 79
}

private enum DFConsumableAnimCooldownExceptionType {
    None = 0,
    Unique = 1,
    Drug = 2,
    Alcohol = 3,
    Pharmaceutical = 4
}

private struct DFConsumableAnimCooldownEntry {
    public let subType: DFConsumableAnimSubType;
    public let propType: DFConsumableAnimPropType;
    public let propSubType: DFConsumableAnimPropSubType;
    public let cooldownExceptionType: DFConsumableAnimCooldownExceptionType;
    public let id: Int32;
    public let timestamp: Float;
}

private enum DFDrugsAnimID {
    Invalid = 0,
    Smoking = 1,
    MrWhitey = 2,
    Addiquit = 3,
    EmergencyCardioregulator = 4,
    Glitter = 5,
    BlackLace = 6,
    HealthBooster = 7,
    Pill_A_Blue = 8,
    Pill_A_Green = 9,
    Pill_A_Pink = 10,
    Pill_B_Red = 11,
    Pill_B_Green = 12,
    Pill_B_Pink = 13,
    Immunosuppressant = 14,
    SmokingRepeat = 15,
    SmokingRepeatFlick = 16,
    SmokingRepeatFinish = 17
}

private enum DFDrinkSipRightHandAnimID {
    Invalid = 0,
    CoffeeTeaToGo = 1,
    CoffeeTeaOpenCup = 2,
    Nicola_A = 3,
    Nicola_B = 4,
    CirrusCola_A = 5,
    CirrusCola_B = 6,
    Tiancha = 7,
    SpunkyMonkey = 8,
    Chromanticore = 9,
    WaterBottle = 10,
    BrosephBrown = 11,
    BrosephBlue = 12,
    AbydosSmall = 13,
    BrosephBrownInverted = 14,
    Cocktail = 15,
    Vatnajokull = 16
}

private enum DFDrinkChugLeftHandAnimID {
    Invalid = 0,
    Wine = 1,
    CalaveraFeliz = 2,
    Champaradise = 3,
    Donaghys = 4,
    Centzon = 5,
    JoeTiel = 6,
    AbydosLarge = 7,
    Bumelant = 8,
    ChamparadiseInverted = 9,
    JoeTielInverted = 10,
    CentzonInverted = 11,
    Odickin = 12,
    OdickinInverted = 13,
    Bolshevik = 14,
    TequilaEspecial = 15,
    CentzonIndigoUnique = 16,
    TequilaEspecialInverted = 17,
    PingoPalido = 18,
    GenericHooch = 19,
    TwentyFirstStout = 20,
    BlueGrass = 21,
    ChromanticoreChug = 22,
    SainRuisseau = 23
}

private enum DFEatDrinkThinPackagedLeftHandAnimID {
    Invalid = 0,
    Burrito_A = 1,
    Burrito_B = 2,
    Burrito_C = 3,
    Holobites = 4,
    Moonchies = 5,
    LeelouBeans = 6,
    PopTurd = 7,
    ShwabShwab = 8,
    ThinPackagedGeneric = 9,
    CatFood = 10,
    DaringDairy = 11,
    ThinPackagedGenericLarge = 12,
    SynthSnack = 13,
    SynthSnackNoLabel = 14,
    CandyBar = 15,
    LeelouBeansInverted = 16,
    RAMNugs = 17
}

private enum DFEatLookDownRightHandAnimID {
    Invalid = 0,
    Wontons = 1,
    Taco = 2,
    HotDog = 3,
    SoupLight = 4,
    SoupDark = 5,
    LargePackagedGenericGold = 6,
    LargePackagedGenericSilver = 7,
    Fruit = 8,
    BeefCan = 9,
    Ramen = 10,
    Pizza = 11,
    MeatLog = 12,
    Nigiri = 13,
    DriedMeat = 14,
    PizzaUnique = 15,
    SandwichUnique = 16,
    PierogiUnique = 17,
    CupcakeUnique = 18,
    Norimaki = 19,
    Jellytricity = 20
}

private struct DFConsumableAnimFX {
    let audio: CName = n"";
    let vfx: CName = n"";
    let statusEffect: TweakDBID = t"";
}

private enum DFAddictionWithdrawalAnimSeverity {
    Invalid = 0,
    Low = 1,
    High = 2
}

private enum DFCrashAnimSeverity {
    Invalid = 0,
    Headache = 1,
    Vomit = 2
}

private enum DFBlackoutAnimType {
    Invalid = 0,
    Full = 1,
    Blocked = 2,
    Vehicle = 3,
    Bike = 4,
    VehicleMoving = 5,
    AutoDrive = 6
}

private enum DFBlackoutAnimFullSubtype {
    Invalid = 0,
    Back = 1,
    Left = 2,
    Right = 3
}

private enum DFBlackoutBikeDismountAnimType {
    Invalid = 0,
    Limited = 1,
    Blocked = 2,
    Full = 3
}

public struct DFAnimDatum {
    let type: DFAnimType;
    let consumableAnimData: DFConsumableAnimDatum;
    let blackoutAnimData: DFBlackoutAnimDatum;
    let withdrawalAnimData: DFWithdrawalAnimDatum;
    let crashAnimData: DFCrashAnimDatum;
}

public struct DFConsumableAnimDatum {
    let type: DFConsumableAnimType;
    let subType: DFConsumableAnimSubType;
    let propType: DFConsumableAnimPropType;
    let propSubType: DFConsumableAnimPropSubType;
    let cooldownExceptionType: DFConsumableAnimCooldownExceptionType;
    let id: Int32;
    let tag: CName;
    let priority: Int32;
    let fallbackFX: DFConsumableAnimFX;
    let maxPlaybackCount: Int32;
    let fromRelaxAction: Bool;
}

private struct DFBlackoutAnimDatum {
    let type: DFBlackoutAnimType;
    let subType: DFBlackoutAnimFullSubtype;
}

private struct DFWithdrawalAnimDatum {
    let type: DFAddictionType;
    let severity: DFAddictionWithdrawalAnimSeverity;
}

private struct DFCrashAnimDatum {
    let severity: DFCrashAnimSeverity;
}

public enum DFCrashAnimMode {
    FromCrash = 0,
    ForceHeadache = 1,
    ForceVomit = 2
}

private struct DFClearQueuedAnimFlags {
    let clearConsumable: Bool;
    let clearBlackout: Bool;
    let clearWithdrawal: Bool;
    let clearCrash: Bool;
}

private struct DFFutureAllowedWithdrawalAnims {
    public persistent let allowNicotine: Bool;
    public persistent let allowAlcohol: Bool;
    public persistent let allowNarcotic: Bool;
}

public class ProcessAnimQueueDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new ProcessAnimQueueDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFAnimationService.Get().processAnimQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFAnimationService.Get().OnProcessAnimQueue();
	}
}

public class ProcessFallbackFXQueueDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new ProcessFallbackFXQueueDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFAnimationService.Get().processFallbackFXQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFAnimationService.Get().OnProcessFallbackFX();
	}
}

public class UnsetRadioRestrictionOverrideDelayCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new UnsetRadioRestrictionOverrideDelayCallback();
	}

	public func InvalidateDelayID() -> Void {
		DFAnimationService.Get().unsetRadioRestrictionOverrideDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		DFAnimationService.Get().OnUnsetRadioRestrictionOverride();
	}
}

class DFAnimationSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFAnimationService> {
		return DFAnimationService.Get();
	}

    public cb func OnLoad() {
        super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(NameOf<MainSystemItemConsumedEvent>(), this, n"OnMainSystemItemConsumedEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetNoAnimation());
    }
}

public final class DFAnimationService extends DFSystem {
    private persistent let futureAllowedWithdrawalAnims: DFFutureAllowedWithdrawalAnims;

    private let QuestsSystem: ref<QuestsSystem>;
    private let AutoDriveSystem: ref<AutoDriveSystem>;
    private let GameStateService: ref<DFGameStateService>;
    private let PlayerStateService: ref<DFPlayerStateService>;
    private let NotificationService: ref<DFNotificationService>;
    private let EnergySystem: ref<DFEnergySystem>;
    private let NicotineAddictionSystem: ref<DFNicotineAddictionSystem>;
    private let AlcoholAddictionSystem: ref<DFAlcoholAddictionSystem>;
    private let NarcoticAddictionSystem: ref<DFNarcoticAddictionSystem>;
    private let ImpairedDrivingSystem: ref<DFImpairedDrivingSystem>;
    private let BiocorruptionCondition: ref<DFBiocorruptionConditionSystem>;
    private let RelaxActionSystem: ref<DFRelaxActionSystem>;

    private let currentlyPlayingAnimType: DFAnimType;
    private let queuedAnims: array<DFAnimDatum>;
    private let queuedBlackoutAnim: DFAnimDatum;
    private let queuedWithdrawalAnim: DFAnimDatum;
    private let queuedCrashAnim: DFAnimDatum;
    private let blackoutMotorcycleSequenceFailsafeCounter: Int32 = 0;
    private let shouldRestoreRadioAfterBlackout: Bool = false;

    private let consumableAnimData: array<DFConsumableAnimDatum>;
    private let queuedFallbackFX: DFConsumableAnimFX;
    private let lootingController: ref<LootingController>;

    private let factListenerAnimQuestPhaseDebugMessageID: Uint32;
    private let factListenerPlayQueuedAnimByID: Uint32;
    private let factListenerPlayBlackoutAnim: Uint32;
    private let factListenerPlayWithdrawalAnim: Uint32;
    private let factListenerPlayCrashAnim: Uint32;

    public let processAnimQueueDelayID: DelayID;
    public let processFallbackFXQueueDelayID: DelayID;
    public let unsetRadioRestrictionOverrideDelayID: DelayID;
    public let contextuallyDelayedBlackoutAnimationDelayID: DelayID;
    public let contextuallyDelayedAddictionWithdrawalAnimationDelayID: DelayID;
    public let blackoutForceBikeDismountRecheckAnimValidityDelayID: DelayID;
    public let contextuallyDelayedCrashAnimationDelayID: DelayID;
    private const let processAnimQueueDelayInterval: Float = 0.01;
    private const let processAnimQueueDelayIntervalSlow: Float = 0.5;
    private const let processFallbackFXQueueDelayInterval: Float = 0.01;
    private const let unsetRadioRestrictionOverrideDelayInterval: Float = 0.5;
    private const let contextuallyDelayedBlackoutAnimationDelayInterval: Float = 0.25;
    private const let contextuallyDelayedAddictionWithdrawalAnimationDelayInterval: Float = 0.25;
    private const let blackoutForceBikeDismountRecheckAnimValidityDelayInterval: Float = 0.5;
    private const let contextuallyDelayedCrashAnimationDelayInterval: Float = 1.0;
    private const let maxPlaybackCountFood: Int32 = 1;
    private const let maxPlaybackCountDrugs: Int32 = 1;
    private const let maxPlaybackCountDrinks: Int32 = 3;
    private const let maxPlaybackCountDrinksChug: Int32 = 1;
    private const let maxPlaybackCountSmoking: Int32 = 4;

    private let cooldownStack: array<DFConsumableAnimCooldownEntry>;
    private let nextConsumedItemIsForcedAnimPlayback: Bool = false;
    private let nextConsumedItemIsFromLootConsumption: Bool = false;

    public final static func GetInstance(gameInstance: GameInstance) -> ref<DFAnimationService> {
        //DFProfile();
		let instance: ref<DFAnimationService> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFAnimationService>()) as DFAnimationService;
		return instance;
	}

	public final static func Get() -> ref<DFAnimationService> {
        //DFProfile();
		return DFAnimationService.GetInstance(GetGameInstance());
	}

    private func SetupDebugLogging() -> Void {
        //DFProfile();
        this.debugEnabled = false;
    }

    public func GetSystemToggleSettingValue() -> Bool {
        //DFProfile();
        // This system does not have a system-specific toggle.
		return true;
    }

    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        // This system does not have a system-specific toggle.
		return "INVALID";
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        let flags: DFClearQueuedAnimFlags;
        flags.clearConsumable = true;
        flags.clearBlackout = true;
        flags.clearWithdrawal = true;
        flags.clearCrash = true;
        this.ClearQueuedAnims(flags);
    }

    public func DoPostResumeActions() -> Void {}

    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance = GetGameInstance();
        this.QuestsSystem = gameInstance.GetQuestsSystem();
        this.AutoDriveSystem = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<AutoDriveSystem>()) as AutoDriveSystem;
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.NotificationService = DFNotificationService.GetInstance(gameInstance);
        this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
        this.NicotineAddictionSystem = DFNicotineAddictionSystem.GetInstance(gameInstance);
        this.AlcoholAddictionSystem = DFAlcoholAddictionSystem.GetInstance(gameInstance);
        this.NarcoticAddictionSystem = DFNarcoticAddictionSystem.GetInstance(gameInstance);
        this.ImpairedDrivingSystem = DFImpairedDrivingSystem.GetInstance(gameInstance);
        this.BiocorruptionCondition = DFBiocorruptionConditionSystem.GetInstance(gameInstance);
        this.RelaxActionSystem = DFRelaxActionSystem.GetInstance(gameInstance);
    }
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    public func SetupData() -> Void {
        //DFProfile();
        this.SetupConsumableAnimData();
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
        this.factListenerAnimQuestPhaseDebugMessageID = this.QuestsSystem.RegisterListener(this.GetAnimDebugQuestPhaseGraphMessageIDQuestFact(), this, n"OnAnimDebugMessage");
        this.factListenerPlayQueuedAnimByID = this.QuestsSystem.RegisterListener(this.GetPlayQueuedAnimByIDActionQuestFact(), this, n"OnPlayQueuedAnimByID");
        this.factListenerPlayBlackoutAnim = this.QuestsSystem.RegisterListener(this.GetStartBlackoutFactAction(), this, n"OnPlayBlackoutAnimFactChanged");
        this.factListenerPlayWithdrawalAnim = this.QuestsSystem.RegisterListener(this.GetStartWithdrawalFactAction(), this, n"OnPlayWithdrawalAnimFactChanged");
        this.factListenerPlayCrashAnim = this.QuestsSystem.RegisterListener(this.GetStartCrashFactAction(), this, n"OnPlayCrashAnimFactChanged");
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    
    private func UnregisterListeners() -> Void {
        //DFProfile();
        this.QuestsSystem.UnregisterListener(this.GetAnimDebugQuestPhaseGraphMessageIDQuestFact(), this.factListenerAnimQuestPhaseDebugMessageID);
        this.factListenerAnimQuestPhaseDebugMessageID = 0u;

        this.QuestsSystem.UnregisterListener(this.GetPlayQueuedAnimByIDActionQuestFact(), this.factListenerPlayQueuedAnimByID);
        this.factListenerPlayQueuedAnimByID = 0u;

        this.QuestsSystem.UnregisterListener(this.GetStartBlackoutFactAction(), this.factListenerPlayBlackoutAnim);
        this.factListenerPlayBlackoutAnim = 0u;

        this.QuestsSystem.UnregisterListener(this.GetStartWithdrawalFactAction(), this.factListenerPlayWithdrawalAnim);
        this.factListenerPlayWithdrawalAnim = 0u;

        this.QuestsSystem.UnregisterListener(this.GetStartCrashFactAction(), this.factListenerPlayCrashAnim);
        this.factListenerPlayCrashAnim = 0u;
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterProcessAnimQueueCallback();
        this.UnregisterProcessFallbackFXQueueCallback();
        this.UnregisterUnsetRadioRestrictionOverrideCallback();
        this.UnregisterContextuallyDelayedBlackoutAnimation();
        this.UnregisterBlackoutForceBikeDismountRecheckAnimValidity();
        this.UnregisterContextuallyDelayedAddictionWithdrawalAnimation();
        this.UnregisterContextuallyDelayedCrashAnimation();
    }

    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}

    public func OnTimeSkipBegin() -> Void {
        // If an animation was queued during the same menu session as a timeskip, it can cause problems.
        // So, purge the animation queue now.
        let flags: DFClearQueuedAnimFlags;
        flags.clearConsumable = true;
        flags.clearBlackout = true;
        flags.clearWithdrawal = true;
        flags.clearCrash = true;
        this.ClearQueuedAnims(flags);
    }

    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "consumableAnimationsEnabled") || ArrayContains(changedSettings, "consumableAnimationCooldownTimeInRealTimeSeconds") || ArrayContains(changedSettings, "consumableAnimationCooldownBehavior") {
            let flags: DFClearQueuedAnimFlags;
            flags.clearConsumable = true;
            this.ClearQueuedAnims(flags);
            ArrayClear(this.cooldownStack);
        }

        if ArrayContains(changedSettings, "withdrawalAnimationsEnabled") {
            this.UnregisterContextuallyDelayedAddictionWithdrawalAnimation();
            let flags: DFClearQueuedAnimFlags;
            flags.clearWithdrawal = true;
            this.ClearQueuedAnims(flags);
        }

        if ArrayContains(changedSettings, "blackoutEnabled") {
            this.UnregisterBlackoutForceBikeDismountRecheckAnimValidity();
            this.UnregisterContextuallyDelayedBlackoutAnimation();
            let flags: DFClearQueuedAnimFlags;
            flags.clearBlackout = true;
            flags.clearCrash = true;
            this.ClearQueuedAnims(flags);
            this.CheckIfPlayerShouldBlackOut();
        }

        if ArrayContains(changedSettings, "crashAnimationSetting") {
            this.UnregisterContextuallyDelayedCrashAnimation();
            let flags: DFClearQueuedAnimFlags;
            flags.clearCrash = true;
            this.ClearQueuedAnims(flags);
            this.SetVomitAllowedFact();
        }
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        let flags: DFClearQueuedAnimFlags;
        flags.clearConsumable = true;
        flags.clearBlackout = true;
        flags.clearWithdrawal = true;
        flags.clearCrash = true;
        this.ClearQueuedAnims(flags);
    }

    //
	//	Consumable Animations
	//
    public func OnItemConsumed(itemRecord: wref<Item_Record>, noAnimation: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnItemConsumed");

        if this.RelaxActionSystem.GetInRelaxActionMode() {
            DFLog(this, "    RETURNING: In Relax Action Mode");
            return;
        }

        let wasFromLoot: Bool = this.GetNextConsumedItemIsFromLootConsumption();
        this.SetNextConsumedItemIsFromLootConsumption(false);

        let forceAnimation: Bool = this.GetNextConsumedItemIsForcedAnimPlayback();
        this.SetNextConsumedItemIsForcedAnimPlayback(false);

        // Find the animation to queue.
        let anim: DFAnimDatum;
        for tag in itemRecord.Tags() {
            let consumableAnimData: DFConsumableAnimDatum = this.FindConsumableAnimByTag(tag);
            if NotEquals(consumableAnimData.type, DFConsumableAnimType.Invalid) {
                anim.type = DFAnimType.Consumable;
                anim.consumableAnimData = consumableAnimData;
                break;
            }
        }

        if DFRunGuard(this) { 
            DFLog(this, "    RETURNING: RunGuard");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return; 
        }

        if !this.Settings.consumableAnimationsEnabled {
            DFLog(this, "    RETURNING: Feature Disabled");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return;
        }

        if !this.GameStateService.IsValidGameState(this) { 
            DFLog(this, "    RETURNING: GameState");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return;
        }

        if noAnimation {
            DFLog(this, "    RETURNING: noAnimation");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return;
        }

        if !this.IsPlayerInAllowedStateForConsumableAnimation() { 
            DFLog(this, "    RETURNING: AllowedState");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return;
        }

        if !this.IsAnimationSubTypeEnabled(anim.consumableAnimData.subType) {
            DFLog(this, "    RETURNING: Animation Type Not Enabled");
            this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
            return;
        }

        let useCooldown: Bool = true;
        if this.Settings.consumableAnimationLootActionEnabled {
            if wasFromLoot {
                DFLog(this, "    RETURNING: Consumed from world with Loot Action enabled");
                this.QueueFallbackFX(anim.consumableAnimData.fallbackFX);
                return;

            } else if forceAnimation {
                // This originated from the consumable animation prompt; ignore cooldown and always play.
                DFLog(this, "    IGNORE COOLDOWN: Action Prompt Used"); 
                useCooldown = false;

            } else {
                DFLog(this, "    USE COOLDOWN: Originated from other source"); 
                // Originated from other source (i.e. Custom Quickslots) - Use normal Cooldown behavior
            }
        }

        if useCooldown {
            let newCooldownEntry: DFConsumableAnimCooldownEntry = DFConsumableAnimCooldownEntry(anim.consumableAnimData.subType, anim.consumableAnimData.propType, anim.consumableAnimData.propSubType, anim.consumableAnimData.cooldownExceptionType, anim.consumableAnimData.id, GameInstance.GetSimTime(GetGameInstance()).ToFloat());
            if this.IsAnimOnCooldownAndUpdateCooldownStack(newCooldownEntry) {
                DFLog(this, "    RETURNING: On Cooldown");
                this.QueueFallbackFX(anim.consumableAnimData.fallbackFX, this.queuedAnims);
                return;
            }
        }
    
        if ArraySize(this.queuedAnims) > 0 {
            for a in this.queuedAnims {
                if Equals(a, anim) {
                    // Don't queue the same animation twice in a row.
                    return;
                }
            }

            if ArraySize(this.queuedAnims) < this.Settings.consumableAnimationQueueDepth {
                // There is space in the queue. We don't need to check the priority.
                this.QueueAnimation(anim);

            } else {
                // Try to find space in the queue by removing a lower-priority item.
                let ableToQueue = true;
                let i: Int32 = 0;
                while i < ArraySize(this.queuedAnims) {
                    let alreadyQueuedConsumableAnim: DFConsumableAnimDatum = this.queuedAnims[i].consumableAnimData;
                    if NotEquals(alreadyQueuedConsumableAnim, this.GetInvalidDFConsumableAnimDatum()) {

                        // This anim is a consumable anim; check its priority.
                        if alreadyQueuedConsumableAnim.priority < anim.consumableAnimData.priority {
                            // Queued animation's priority was higher. Keep checking.

                        } else if alreadyQueuedConsumableAnim.priority == anim.consumableAnimData.priority {
                            // Queued animation's priority was the same. Choose one at random.
                            if IsCoinFlipSuccessful() {
                                // We chose the new animation. Play the old queued animation's fallback FX.
                                this.QueueFallbackFX(alreadyQueuedConsumableAnim.fallbackFX, this.queuedAnims);
                                this.QueueAnimation(anim, true, i);
                                ableToQueue = true;
                                break;

                            } else {
                                // We chose the old animation. Keep checking.

                            }
                        } else {
                            // Queued animation's priority was less. Queue the new animation. Play the old queued animation's fallback FX.
                            this.QueueFallbackFX(alreadyQueuedConsumableAnim.fallbackFX, this.queuedAnims);
                            this.QueueAnimation(anim, true, i);
                            ableToQueue = true;
                            break;
                        }
                    } else {
                        // This is another type of animation; don't replace it.
                    }

                    i += 1;
                }

                if !ableToQueue {
                    // We were not able to queue the animation. Play this anim's fallback FX.
                    this.QueueFallbackFX(anim.consumableAnimData.fallbackFX, this.queuedAnims);
                }
            }
        } else {
            // The animation queue is empty. Queue the animation.
            this.QueueAnimation(anim);
            
        }
	}

    public func GetAnimFromItemTDBIDIfPlaybackValid(itemTDBID: TweakDBID) -> DFAnimDatum {
        // Grab the Consumable Animation more directly, with far fewer opportunities
        // to bail out. The assumption is that most necessary sanity checks have already
        // been performed.
        let cannotPlay: Bool = false;

        // Find the animation to queue.
        let anim: DFAnimDatum;
        let tags: array<CName> = TweakDBInterface.GetItemRecord(itemTDBID).Tags();
        for tag in tags {
            let consumableAnimData: DFConsumableAnimDatum = this.FindConsumableAnimByTag(tag);
            if NotEquals(consumableAnimData.type, DFConsumableAnimType.Invalid) {
                anim.type = DFAnimType.Consumable;
                anim.consumableAnimData = consumableAnimData;
                break;
            }
        }

        if DFRunGuard(this) { 
            DFLog(this, "    RETURNING: RunGuard");
            cannotPlay = true;
        }

        if !this.IsPlayerInAllowedStateForRelaxActionAnimation() { 
            DFLog(this, "    RETURNING: AllowedState");
            cannotPlay = true;
        }

        if cannotPlay {
            // Failsafe
            this.QuestsSystem.SetFact(n"df_fact_immersive_item_consume", 0);
            // TODO - Show warning
            let invalidAnim: DFAnimDatum;
            return invalidAnim;
        }

        return anim;
    }

    //
    // Blackout Animations
    //
    public final func TryToQueueBlackoutAnimation() -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

		DFLog(this, "-----------");
        DFLog(this, "-----------");
        DFLog(this, "TryToStartBlackoutAnimation");
        DFLog(this, "-----------");
        DFLog(this, "-----------");

        if NotEquals(this.Settings.blackoutEnabled, true) {
            DFLog(this, "    Setting disabled!");
            return;
        }

        if NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid) {
            DFLog(this, "    Ignoring request, a blackout animation is already queued!");
            return;
        }

        if Equals(this.currentlyPlayingAnimType, DFAnimType.Blackout) {
            DFLog(this, "    Ignoring request, a blackout animation is currently playing!");
            return;
        }
		
		let gs: GameState = this.GameStateService.GetGameState(this);
		if Equals(gs, GameState.Valid) {
            DFLog(this, "    Game State is Valid, continuing.");
        } else if Equals(gs, GameState.TemporarilyInvalid) {
            DFLog(this, "    Game State is Temporarily Invalid, checking again.");
            this.RegisterContextuallyDelayedBlackoutAnimation();
            return;
        }

        if this.ImpairedDrivingSystem.controlLossHappeningNow {
            DFLog(this, "    Impaired driving action in progress, checking again.");
            this.RegisterContextuallyDelayedBlackoutAnimation();
            return;
        }

        let gameInstance = GetGameInstance();

        let vehicleObj: wref<VehicleObject>;
		VehicleComponent.GetVehicle(gameInstance, this.player, vehicleObj);
        let vc: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();

        if !this.IsPlayerInAllowedStateForBlackoutAnimation() {
            DFLog(this, "    Player is not in allowed state for blackout animation, checking again.");
            this.RegisterContextuallyDelayedBlackoutAnimation();
            return;
        }

        let blackoutAnim: DFAnimDatum;
        blackoutAnim.type = DFAnimType.Blackout;

        let hasSpaceBehind: Bool = this.PlayerHasSpaceBehind(0.90, 1.50, 1.25);
        let hasSpaceLeft: Bool = this.PlayerHasSpaceLeft(0.90, 1.50, 1.25);
        let hasSpaceRight: Bool = this.PlayerHasSpaceRight(0.90, 1.50, 1.25);
        let cliffBehind: Bool = this.IsCliffBehind();
        let floorTooSteep: Bool = this.IsFloorTooSteep();

        let validFullAnims: array<DFBlackoutAnimFullSubtype>;
        if !floorTooSteep {
            if !cliffBehind && hasSpaceBehind {
                DFLog(this, "    Full - Back allowed!");
                ArrayPush(validFullAnims, DFBlackoutAnimFullSubtype.Back);
            }

            if hasSpaceLeft {
                DFLog(this, "    Full - Left allowed!");
                ArrayPush(validFullAnims, DFBlackoutAnimFullSubtype.Left);
            }

            if hasSpaceRight {
                DFLog(this, "    Full - Right allowed!");
                ArrayPush(validFullAnims, DFBlackoutAnimFullSubtype.Right);
            }
        }

		if IsDefined(vehicleObj) && IsDefined(vc) {
            if vehicleObj.IsQuest() {
                DFLog(this, "    In a quest vehicle, checking again.");
                this.RegisterContextuallyDelayedBlackoutAnimation();
                return;

            } else if vehicleObj == (vehicleObj as BikeObject) {
                let recordID: TweakDBID = vc.GetVehicle().GetRecordID();
                let vehicleRecord: ref<Vehicle_Record> = TweakDBInterface.GetVehicleRecord(recordID);
                let vehicleDataPackage: ref<VehicleDataPackage_Record> = vehicleRecord.VehDataPackage();
                let collisionForce: Vector4 = -vehicleObj.GetLinearVelocity();
                
                if Vector4.Length(collisionForce) > (vehicleDataPackage.KnockOffForce() * 1.5) && Vector4.Length(collisionForce) <= (vehicleDataPackage.KnockOffForce() * 1.75) {
                    DFLog(this, "    On a motorcycle and within speed tolerance; starting sequence!");
                    vc.DarkFutureForceBikeDismount(this.player);
                    this.RegisterBlackoutForceBikeDismountCheckAnimValidity();
                } else {
                    DFLog(this, "    On a motorcycle, but going too fast/slow for forced dismount!");
                    if Vector4.Length(collisionForce) > (vehicleDataPackage.KnockOffForce() * 1.75) {
                        DFLog(this, "        Forcing brakes!");
                        vehicleObj.ForceBrakesUntilStoppedOrFor(4.0);
                    }
                    
                    this.RegisterContextuallyDelayedBlackoutAnimation();
                    return;
                } 
            } else if VehicleComponent.IsDriver(gameInstance, this.player) {
                if this.AutoDriveSystem.GetAutodriveEnabled() {
                    if this.AutoDriveSystem.GetAutodriveIsDelamain() {
                        DFLog(this, "    In a Delamain! Checking again.");
                        this.RegisterContextuallyDelayedBlackoutAnimation();
                    } else {
                        DFLog(this, "    In a vehicle (moving) with AutoDrive; stopping vehicle and starting sequence!");
                        this.AutoDriveSystem.SetAutodriveEnabled(false);
                        vehicleObj.ForceBrakesUntilStoppedOrFor(4.0);
                        blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.AutoDrive;
                        this.QueueAnimation(blackoutAnim);
                    }

                } else if this.GetVehicleSpeedInMph(vehicleObj) > 1 {
                    DFLog(this, "    In a vehicle (moving); starting sequence!");
                    vehicleObj.ForceBrakesUntilStoppedOrFor(4.0);
                    blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.VehicleMoving;
                    this.QueueAnimation(blackoutAnim);
                } else {
                    DFLog(this, "    In a vehicle (stationary); playing anim!");
                    blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.Vehicle;
                    this.QueueAnimation(blackoutAnim);
                }
            } else {
                DFLog(this, "    Passenger in a vehicle, checking again.");
                this.RegisterContextuallyDelayedBlackoutAnimation();
            }
        } else if ArraySize(validFullAnims) > 0 {
            DFLog(this, "    Playing full anim!");
            blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.Full;
            blackoutAnim.blackoutAnimData.subType = validFullAnims[RandRangeInclusive(0, ArraySize(validFullAnims) - 1)];

            this.QueueAnimation(blackoutAnim);

        } else {
            DFLog(this, "    Playing blocked anim!");
            
            blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.Blocked;
            this.QueueAnimation(blackoutAnim);
        }
    }

    private final func GetVehicleSpeedInMph(vehicleObj: ref<VehicleObject>) -> Int32 {
        let speedValue: Int32 = -1;

        if IsDefined(vehicleObj) {
            let rawSpeed: Float = vehicleObj.GetCurrentSpeed();
            let velocity: Float = AbsF(rawSpeed);
            let multiplier: Float = GameInstance.GetStatsDataSystem(GetGameInstance()).GetValueFromCurve(n"vehicle_ui", velocity, n"speed_to_multiplier");
            speedValue = RoundMath(velocity * multiplier);
        }

        return speedValue;
    }

    private final func GetLastBlackoutHoursSleptFact() -> CName {
        return n"df_fact_last_blackout_hours_slept";
    }

    private final func OnPlayBlackoutAnimFactChanged(value: Int32) -> Void {
        if value == 0 {
            // Clear the notification queue prior to blacking out.
            this.NotificationService.ClearAllNotificationQueues();

            // Calculate future hours.
            let calculatedFutureHours: DFFutureHoursData = DFInteractionSystem.Get().GetCalculatedValuesForFutureHours(DFTimeSkipType.Blackout, GameTime.Hours(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTime()));

            // "Sleep"
            let hoursSlept: Int32 = this.QuestsSystem.GetFact(this.GetLastBlackoutHoursSleptFact());
            let tsd: DFTimeSkipData;
            tsd.hoursSkipped = hoursSlept;
            tsd.targetNeedValues = calculatedFutureHours.futureNeedsData[hoursSlept - 1];
            tsd.targetAddictionValues = calculatedFutureHours.futureAddictionData[hoursSlept - 1];
            tsd.targetHumanityLossValues = calculatedFutureHours.futureHumanityLossData[hoursSlept - 1];
            tsd.targetBiocorruptionValues = calculatedFutureHours.futureBiocorruptionData[hoursSlept - 1];
            tsd.timeSkipType = DFTimeSkipType.Blackout;
            tsd.skipSevereNeedMessage = true;
            DFMainSystem.Get().DispatchTimeSkipFinishedEvent(tsd);

            // Standard time skip handling.
            GameTimeUtils.FastForwardPlayerState(this.player);

            // Restore radio.
            this.HandleRadioOnBlackout(true);

            // Tell the rest of the system that the animation finished playing.
            this.OnAnimFinishedPlaying();
        }
    }

    public final func OnBlackoutForceBikeDismountCheckAnimValidity() -> Void {
        if (this.player.IsMovingHorizontally() || this.player.IsMovingVertically() || VehicleComponent.IsMountedToVehicle(GetGameInstance(), this.player)) && this.blackoutMotorcycleSequenceFailsafeCounter < 50 {
            DFLog(this, "    Player still moving, trying again. Failsafe counter: " + ToString(this.blackoutMotorcycleSequenceFailsafeCounter));
            this.blackoutMotorcycleSequenceFailsafeCounter += 1;
            this.RegisterBlackoutForceBikeDismountCheckAnimValidity();
            return;
        }

        // Reset the counter.
        this.blackoutMotorcycleSequenceFailsafeCounter = 0;

        if !this.IsPlayerInAllowedStateForForcedBikeDismountBlackoutAnimation() {
            DFLog(this, "    Player in invalid state after dismount (such as swimming); playing alternative anim!");
            this.QuestsSystem.SetFact(this.GetBlackoutForceBikeDismountAnimValidityStateFact(), EnumInt<DFBlackoutBikeDismountAnimType>(DFBlackoutBikeDismountAnimType.Limited));

        } else if this.IsFloorTooSteep() || !this.PlayerHasSpaceBehind(0.90, 1.50, 1.25) || this.IsCliffBehind() {
            DFLog(this, "    Floor too steep or no room behind; playing blocked anim!");
            this.QuestsSystem.SetFact(this.GetBlackoutForceBikeDismountAnimValidityStateFact(), EnumInt<DFBlackoutBikeDismountAnimType>(DFBlackoutBikeDismountAnimType.Blocked));
            
        } else {
            DFLog(this, "    Playing full anim!");
            this.QuestsSystem.SetFact(this.GetBlackoutForceBikeDismountAnimValidityStateFact(), EnumInt<DFBlackoutBikeDismountAnimType>(DFBlackoutBikeDismountAnimType.Full));
        }

        let blackoutAnim: DFAnimDatum;
        blackoutAnim.type = DFAnimType.Blackout;
        blackoutAnim.blackoutAnimData.type = DFBlackoutAnimType.Bike;
        this.QueueAnimation(blackoutAnim);
    }

    private final func HandleRadioOnBlackout(turnOn: Bool) -> Void {
        DFLog(this, "    Handling radio: " + ToString(turnOn));
        if turnOn {
            if this.shouldRestoreRadioAfterBlackout {
                this.shouldRestoreRadioAfterBlackout = false;
                DarkFutureSendRadioEvent(this.player, true, false, 0);
            }
        } else {
            let pocketRadio: ref<PocketRadio> = this.player.GetPocketRadio();
            if pocketRadio.IsActive() {
                this.shouldRestoreRadioAfterBlackout = true;
                DarkFutureSendRadioEvent(this.player, false, false, -1);
            }
        }
    }

    private final func IsFloorTooSteep() -> Bool {
        let floorAngle: Float;
        if SpatialQueriesHelper.GetFloorAngle(this.player, floorAngle) && floorAngle >= TDB.GetFloat(t"AIGeneralSettings.maxAllowedIncapacitatedFloorAngle") {
            DFLog(this, "      - Floor too steep!");
            return true;
        };
        return false;
    }

    public final func IsCliffInFront() -> Bool {
        let raycastResult: TraceResult;
        let floorAngle: Float;
        let playerWorldPos: Vector4 = this.player.GetWorldPosition();
        let startPosition: Vector4 = playerWorldPos + Vector4(0.00, 0.00, 0.0, 0.00);
        let endPosition: Vector4 = playerWorldPos + Vector4(0.00, 0.00, 1.5, 0.00);
        if GameInstance.GetSpatialQueriesSystem(GetGameInstance()).SyncRaycastByCollisionGroup(startPosition, endPosition, n"Static", raycastResult, true, false) {
            floorAngle = Vector4.GetAngleBetween(Cast<Vector4>(raycastResult.normal), this.player.GetWorldUp());
            if floorAngle >= TDB.GetFloat(t"AIGeneralSettings.maxAllowedIncapacitatedFloorAngle") {
                DFLog(this, "      - Cliff in front!");
                return true;
            } else {
                return false;
            }
        };
        return false;
    }

    public final func IsCliffBehind() -> Bool {
        let raycastResult: TraceResult;
        let floorAngle: Float;
        let playerWorldPos: Vector4 = this.player.GetWorldPosition();
        let startPosition: Vector4 = playerWorldPos + Vector4(0.00, 0.00, 0.00, 0.00);
        let endPosition: Vector4 = playerWorldPos + Vector4(0.00, 0.00, -1.5, 0.00);
        if GameInstance.GetSpatialQueriesSystem(GetGameInstance()).SyncRaycastByCollisionGroup(startPosition, endPosition, n"Static", raycastResult, true, false) {
            floorAngle = Vector4.GetAngleBetween(Cast<Vector4>(raycastResult.normal), this.player.GetWorldUp());
            if floorAngle >= TDB.GetFloat(t"AIGeneralSettings.maxAllowedIncapacitatedFloorAngle") {
                DFLog(this, "      - Cliff behind!");
                return true;
            } else {
                return false;
            }
        };
        return false;
    }

    private final func PlayerHasSpaceBehind(areaWidth: Float, areaLength: Float, areaHeight: Float) -> Bool {
        let gameInstance = GetGameInstance();
        let SQS: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(gameInstance);

        let boxDimensions: Vector4;
        let boxOrientation: EulerAngles;
        let fitTestOvelap: TraceResult;
        let overlapSuccessStatic: Bool;
        let overlapSuccessVehicle: Bool;
        let queryDirection = this.player.GetWorldForward() * -1.0;
        queryDirection.Z = 0.00;
        queryDirection = Vector4.Normalize(queryDirection);
        boxDimensions.X = areaWidth * 0.50;
        boxDimensions.Y = areaLength * 0.50;
        boxDimensions.Z = areaHeight * 0.50;
        let queryPosition: Vector4 = this.player.GetWorldPosition();
        queryPosition.Z += boxDimensions.Z + 0.6; // Ground clearance
        queryPosition += boxDimensions.Y * queryDirection;
        boxOrientation = Quaternion.ToEulerAngles(Quaternion.BuildFromDirectionVector(queryDirection));
        overlapSuccessStatic = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Static", fitTestOvelap);
        overlapSuccessVehicle = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Vehicle", fitTestOvelap);
        let hasSpace: Bool = !overlapSuccessStatic && !overlapSuccessVehicle;
        if !hasSpace {
            DFLog(this, "      - Not enough space behind!");
        }
        return hasSpace;
    }

    private final func PlayerHasSpaceLeft(areaWidth: Float, areaLength: Float, areaHeight: Float) -> Bool {
        let gameInstance = GetGameInstance();
        let SQS: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(gameInstance);

        let boxDimensions: Vector4;
        let boxOrientation: EulerAngles;
        let fitTestOvelap: TraceResult;
        let overlapSuccessStatic: Bool;
        let overlapSuccessVehicle: Bool;
        let queryDirection = this.player.GetWorldRight() * -1.0;
        queryDirection.Z = 0.00;
        queryDirection = Vector4.Normalize(queryDirection);
        boxDimensions.X = areaWidth * 0.50;
        boxDimensions.Y = areaLength * 0.50;
        boxDimensions.Z = areaHeight * 0.50;
        let queryPosition: Vector4 = this.player.GetWorldPosition();
        queryPosition.Z += boxDimensions.Z + 0.6; // Ground clearance
        queryPosition += boxDimensions.Y * queryDirection;
        boxOrientation = Quaternion.ToEulerAngles(Quaternion.BuildFromDirectionVector(queryDirection));
        overlapSuccessStatic = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Static", fitTestOvelap);
        overlapSuccessVehicle = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Vehicle", fitTestOvelap);
        let hasSpace: Bool = !overlapSuccessStatic && !overlapSuccessVehicle;
        if !hasSpace {
            DFLog(this, "      - Not enough space behind!");
        }
        return hasSpace;
    }

    private final func PlayerHasSpaceRight(areaWidth: Float, areaLength: Float, areaHeight: Float) -> Bool {
        let gameInstance = GetGameInstance();
        let SQS: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(gameInstance);

        let boxDimensions: Vector4;
        let boxOrientation: EulerAngles;
        let fitTestOvelap: TraceResult;
        let overlapSuccessStatic: Bool;
        let overlapSuccessVehicle: Bool;
        let queryDirection = this.player.GetWorldRight();
        queryDirection.Z = 0.00;
        queryDirection = Vector4.Normalize(queryDirection);
        boxDimensions.X = areaWidth * 0.50;
        boxDimensions.Y = areaLength * 0.50;
        boxDimensions.Z = areaHeight * 0.50;
        let queryPosition: Vector4 = this.player.GetWorldPosition();
        queryPosition.Z += boxDimensions.Z + 0.6; // Ground clearance
        queryPosition += boxDimensions.Y * queryDirection;
        boxOrientation = Quaternion.ToEulerAngles(Quaternion.BuildFromDirectionVector(queryDirection));
        overlapSuccessStatic = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Static", fitTestOvelap);
        overlapSuccessVehicle = SQS.Overlap(boxDimensions, queryPosition, boxOrientation, n"Vehicle", fitTestOvelap);
        let hasSpace: Bool = !overlapSuccessStatic && !overlapSuccessVehicle;
        if !hasSpace {
            DFLog(this, "      - Not enough space behind!");
        }
        return hasSpace;
    }

    private final func PlayerHasSpaceInFront() -> Bool {
        let hasSpace: Bool = SpatialQueriesHelper.HasSpaceInFront(this.player, 0.6, 0.90, 1.50, 1.25);
        if !hasSpace {
            DFLog(this, "      - Not enough space in front!");
        }
        return hasSpace;
    }

    private final func IsExitVehicleBlocked() -> Bool {
        let vehicle: ref<VehicleObject>;
        let vehicleWeak: wref<VehicleObject>;
        let gameInstance = GetGameInstance();

        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"VehicleScene") {
            return true;
        };
        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"VehicleCombat") {
            return true;
        };
        if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"VehicleBlockExit") {
            return true;
        };
        if GameInstance.GetPhotoModeSystem(gameInstance).IsPhotoModeActive() {
            return true;
        };
        if GameInstance.GetRacingSystem(gameInstance).IsRaceInProgress() {
            return true;
        };

        VehicleComponent.GetVehicle(gameInstance, this.player, vehicleWeak);
        vehicle = vehicleWeak;
        if IsDefined(vehicle) && vehicle.IsFlippedOver() && vehicle.RecordHasTag(n"Important") {
            return true;
        };

        return false;
    }

    public final func CheckIfPlayerShouldBlackOut() -> Void {
        if this.Settings.blackoutEnabled && this.EnergySystem.GetNeedValue() == 0.0 {
            this.TryToQueueBlackoutAnimation();
        }
    }

    public final func IsBlackoutQueued() -> Bool {
        return NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid);
    }

    //
    // Crash Animations
    //
    public final func TryToQueueCrashAnimation(mode: DFCrashAnimMode, opt crashStackCountFromTimeskip: Uint32) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }

		DFLog(this, "-----------");
        DFLog(this, "-----------");
        DFLog(this, "TryToStartCrashAnimation");
        DFLog(this, "-----------");
        DFLog(this, "-----------");

        if NotEquals(this.queuedCrashAnim.type, DFAnimType.Invalid) {
            DFLog(this, "    Ignoring request, a crash animation is already queued!");
            return;
        }

        if Equals(this.currentlyPlayingAnimType, DFAnimType.Crash) {
            DFLog(this, "    Ignoring request, a crash animation is currently playing!");
            return;
        }
		
		let gs: GameState = this.GameStateService.GetGameState(this);
		if Equals(gs, GameState.Valid) {
            DFLog(this, "    Game State is Valid, continuing.");
        } else if Equals(gs, GameState.TemporarilyInvalid) {
            DFLog(this, "    Game State is Temporarily Invalid, checking again.");
            this.RegisterContextuallyDelayedCrashAnimation(mode);
            return;
        }

        if NotEquals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.Off) {
            let gameInstance = GetGameInstance();

            let vehicleObj: wref<VehicleObject>;
            VehicleComponent.GetVehicle(gameInstance, this.player, vehicleObj);
            let vc: wref<VehicleComponent> = vehicleObj.GetVehicleComponent();

            if !this.IsPlayerInAllowedStateForCrashAnimation() {
                DFLog(this, "    Player is not in allowed state for crash animation, checking again.");
                this.RegisterContextuallyDelayedCrashAnimation(mode);
                return;
            }

            let crashAnim: DFAnimDatum;
            crashAnim.type = DFAnimType.Crash;

            if Equals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.HeadacheOnly) {
                crashAnim.crashAnimData.severity = DFCrashAnimSeverity.Headache;
            
            } else if Equals(mode, DFCrashAnimMode.ForceVomit) {
                crashAnim.crashAnimData.severity = DFCrashAnimSeverity.Vomit;
            
            } else if Equals(mode, DFCrashAnimMode.ForceHeadache) {
                crashAnim.crashAnimData.severity = DFCrashAnimSeverity.Headache;

            } else {
                let biocorruptionLevel: Uint32 = this.BiocorruptionCondition.GetConditionLevel();
                if biocorruptionLevel == 0u {
                    crashAnim.crashAnimData.severity = DFCrashAnimSeverity.Vomit;
                
                } else if biocorruptionLevel >= 1u {
                    let queuedCrashType: DFQueuedCrashType = this.BiocorruptionCondition.GetCrashQueued();
                    let crashStacks: Uint32;
                    
                    if Equals(queuedCrashType, DFQueuedCrashType.FromTime) {
                        crashStacks = this.BiocorruptionCondition.GetLastKnownCrashStackCount();

                    } else if Equals(queuedCrashType, DFQueuedCrashType.FromTimeskip) && crashStackCountFromTimeskip > 0u {
                        crashStacks = crashStackCountFromTimeskip;

                    }

                    crashAnim.crashAnimData.severity = crashStacks < this.BiocorruptionCondition.crashStackVomitThreshold ? DFCrashAnimSeverity.Headache : DFCrashAnimSeverity.Vomit;
                }
            }

            if IsDefined(vehicleObj) && IsDefined(vc) {
                DFLog(this, "    In a vehicle, checking again.");
                this.RegisterContextuallyDelayedCrashAnimation(mode);

            } else if this.IsFloorTooSteep() || !this.PlayerHasSpaceInFront() || this.IsCliffInFront() {
                DFLog(this, "    Floor too steep, cliff in front, or no room in front; checking again.");
                
                this.RegisterContextuallyDelayedCrashAnimation(mode);

            } else {
                DFLog(this, "    Playing anim!");
                this.QueueAnimation(crashAnim);
            }
        }
    }

    public final func UnqueuePendingCrashAnim() -> Void {
        // Called in the case of queuing a Blackout animation to ensure this doesn't play.
        this.UnregisterContextuallyDelayedCrashAnimation();
        let flags: DFClearQueuedAnimFlags;
        flags.clearCrash = true;
        this.ClearQueuedAnims(flags);
    }

    private final func OnPlayCrashAnimFactChanged(value: Int32) -> Void {
        if value == 0 {
            // Tell the rest of the system that the animation finished playing.
            this.OnAnimFinishedPlaying();
        }
    }

    private final func SetVomitAllowedFact() -> Void {
        if Equals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.HeadacheOnly) || Equals(this.Settings.crashAnimationSetting, DFCrashAnimSetting.Off) {
            this.QuestsSystem.SetFact(n"df_fact_crash_anim_no_vomit", 1);
        } else {
            this.QuestsSystem.SetFact(n"df_fact_crash_anim_no_vomit", 0);
        }
    }

    //
    // Withdrawal Animations
    //
    public final func TryToQueueAddictionWithdrawalAnimation(addictionData: DFAddictionDatum, timeSkipType: DFTimeSkipType) -> Void {
        //DFProfile();
        if DFRunGuard(this) { return; }
        
		DFLog(this, "-----------");
        DFLog(this, "-----------");
        DFLog(this, "TryToQueueAddictionWithdrawalAnimation");
        DFLog(this, "-----------");
        DFLog(this, "-----------");
		
		let gs: GameState = this.GameStateService.GetGameState(this);
		if Equals(gs, GameState.Valid) {
            DFLog(this, "    Game State is Valid, continuing.");

        } else if Equals(gs, GameState.TemporarilyInvalid) {
            DFLog(this, "    Game State is Temporarily Invalid, checking again.");
            this.RegisterContextuallyDelayedAddictionWithdrawalAnimation(addictionData, timeSkipType);
            return;
        }

        // Is the Addiction Treatment effect active? If so, stop and do not retry.
        if addictionData.newAddictionTreatmentDuration > 0.0 {
            DFLog(this, "    Player has an addiction treatment duration. Exiting!");
            return;
        }

        // Which addiction withdrawal is currently the most severe?
        let mostSevereAddiction: DFAddictionType = DFAddictionType.None;
        let mostSevereAddictionWithdrawalNerveLimit: Float = 100.0;
        let mostSevereAddictionWithdrawalAnimSeverity: DFAddictionWithdrawalAnimSeverity;

        if this.Settings.withdrawalAnimationsEnabled {
            let nicotineNerveLimits: array<Float> = this.NicotineAddictionSystem.GetAddictionNeedLimits();
            let nicotineNerveLimit: Float = nicotineNerveLimits[addictionData.nicotine.withdrawalLevel];

            // Clean up any stale flags.
            if addictionData.nicotine.withdrawalLevel == 0 {
                DFLog(this, "    Cleaning up possibly stale flag: allowNicotine");
                this.futureAllowedWithdrawalAnims.allowNicotine = false;
            }
            if addictionData.alcohol.withdrawalLevel == 0 {
                DFLog(this, "    Cleaning up possibly stale flag: allowAlcohol");
                this.futureAllowedWithdrawalAnims.allowAlcohol = false;
            }
            if addictionData.narcotic.withdrawalLevel == 0 {
                DFLog(this, "    Cleaning up possibly stale flag: allowNarcotic");
                this.futureAllowedWithdrawalAnims.allowNarcotic = false;
            }

            // Select an animation.
            if addictionData.nicotine.withdrawalLevel > 0 && nicotineNerveLimit <= mostSevereAddictionWithdrawalNerveLimit && (addictionData.nicotine.isWithdrawalLevelWorsened || this.futureAllowedWithdrawalAnims.allowNicotine) {
                DFLog(this, "    Nicotine withdrawal worsened OR we are allowing playback anyway...");
                if addictionData.nicotine.withdrawalLevel == 2 {
                    DFLog(this, "    Nicotine withdrawal = 2...");
                    if Equals(this.NicotineAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Nicotine Withdrawal Stage 2 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Nicotine;
                        mostSevereAddictionWithdrawalNerveLimit = nicotineNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.Low;
                    }

                } else if addictionData.nicotine.withdrawalLevel >= 3 {
                    DFLog(this, "    Nicotine withdrawal >= 3...");
                    if Equals(this.NicotineAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Nicotine Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Nicotine;
                        mostSevereAddictionWithdrawalNerveLimit = nicotineNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.High;
                    }
                }
            }

            let alcoholNerveLimits: array<Float> = this.AlcoholAddictionSystem.GetAddictionNeedLimits();
            let alcoholNerveLimit: Float = alcoholNerveLimits[addictionData.alcohol.withdrawalLevel];
            if addictionData.alcohol.withdrawalLevel > 0 && alcoholNerveLimit <= mostSevereAddictionWithdrawalNerveLimit && (addictionData.alcohol.isWithdrawalLevelWorsened || this.futureAllowedWithdrawalAnims.allowAlcohol) {
                DFLog(this, "    Alcohol withdrawal worsened OR we are allowing playback anyway...");
                if addictionData.alcohol.withdrawalLevel == 2 {
                    DFLog(this, "    Alcohol withdrawal = 2...");
                    if Equals(this.AlcoholAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Alcohol Withdrawal Stage 2 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Alcohol;
                        mostSevereAddictionWithdrawalNerveLimit = alcoholNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.Low;
                    }

                } else if addictionData.alcohol.withdrawalLevel >= 3 {
                    DFLog(this, "    Alcohol withdrawal >= 3...");
                    if Equals(this.AlcoholAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Alcohol Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Alcohol;
                        mostSevereAddictionWithdrawalNerveLimit = alcoholNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.High;
                    }
                }
            }

            let narcoticNerveLimits: array<Float> = this.NarcoticAddictionSystem.GetAddictionNeedLimits();
            let narcoticNerveLimit: Float = narcoticNerveLimits[addictionData.narcotic.withdrawalLevel];
            if addictionData.narcotic.withdrawalLevel > 0 && narcoticNerveLimit <= mostSevereAddictionWithdrawalNerveLimit && (addictionData.narcotic.isWithdrawalLevelWorsened || this.futureAllowedWithdrawalAnims.allowNarcotic) {
                DFLog(this, "    Narcotic withdrawal worsened OR we are allowing playback anyway...");
                if addictionData.narcotic.withdrawalLevel == 2 {
                    DFLog(this, "    Narcotic withdrawal = 2...");
                    if Equals(this.NarcoticAddictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Narcotic Withdrawal Stage 2 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Narcotic;
                        mostSevereAddictionWithdrawalNerveLimit = narcoticNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.Low;
                    }

                } else if addictionData.narcotic.withdrawalLevel >= 3 {
                    DFLog(this, "    Narcotic withdrawal >= 3...");
                    if Equals(this.NarcoticAddictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) || RandRangeInclusive(1, 100) <= this.Settings.withdrawalAnimationChance {
                        DFLog(this, "    We've never played Narcotic Withdrawal Stage 3 animation before, or, the random roll succeeded!");
                        mostSevereAddiction = DFAddictionType.Narcotic;
                        mostSevereAddictionWithdrawalNerveLimit = narcoticNerveLimit;
                        mostSevereAddictionWithdrawalAnimSeverity = DFAddictionWithdrawalAnimSeverity.High;
                    }
                }
            }
        } else {
            DFLog(this, "    Withdrawal animations are disabled. Exiting!");
        }

        if NotEquals(mostSevereAddiction, DFAddictionType.None) {
            DFLog(this, "    We are going to play a Withdrawal Animation! mostSevereAddiction Type: " + ToString(mostSevereAddiction) + ", mostSevereAddictionWithdrawalNerveLimit: " + ToString(mostSevereAddictionWithdrawalNerveLimit));

            // Clear any existing audio notifications.
            this.NotificationService.ClearOutOfCombatAudioNotifications();

            let withdrawalAnim: DFAnimDatum;
            withdrawalAnim.type = DFAnimType.Withdrawal;
            withdrawalAnim.withdrawalAnimData.type = mostSevereAddiction;
            withdrawalAnim.withdrawalAnimData.severity = mostSevereAddictionWithdrawalAnimSeverity;

            // If for any reason we can't queue this, or it is unqueued, allow it to be queued in the future irrespective of the Withdrawal Level worsening.
            if Equals(mostSevereAddiction, DFAddictionType.Nicotine) {
                this.futureAllowedWithdrawalAnims.allowNicotine = true;

            } else if Equals(mostSevereAddiction, DFAddictionType.Alcohol) {
                this.futureAllowedWithdrawalAnims.allowAlcohol = true;

            } else if Equals(mostSevereAddiction, DFAddictionType.Narcotic) {
                this.futureAllowedWithdrawalAnims.allowNarcotic = true;
            }

            // Did this Timeskip originate from a Blackout? If so, stop here and don't queue the animation. (We've already watched a lot.) We can try to play 
            // it later on the next timeskip (futureAllowedWithdrawalAnims), if the condition is still valid.
            if Equals(timeSkipType, DFTimeSkipType.Blackout) {
                DFLog(this, "    Timeskip originated from Blackout. Exiting!");
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowNicotine: " + ToString(this.futureAllowedWithdrawalAnims.allowNicotine));
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowAlcohol: " + ToString(this.futureAllowedWithdrawalAnims.allowAlcohol));
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowNarcotic: " + ToString(this.futureAllowedWithdrawalAnims.allowNarcotic));
                return;

            // Are we in an invalid state to play an animation? If so, stop here and don't queue the animation. We can try to play it later on the next
            // timeskip (futureAllowedWithdrawalAnims), if the condition is still valid.
            } else if !this.IsPlayerInAllowedStateForAddictionWithdrawalAnimation() {
                DFLog(this, "    Player is not in allowed state for withdrawal animation. Exiting!");
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowNicotine: " + ToString(this.futureAllowedWithdrawalAnims.allowNicotine));
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowAlcohol: " + ToString(this.futureAllowedWithdrawalAnims.allowAlcohol));
                DFLog(this, "    this.futureAllowedWithdrawalAnims.allowNarcotic: " + ToString(this.futureAllowedWithdrawalAnims.allowNarcotic));
                return;

            } else {
                this.QueueAnimation(withdrawalAnim);
            }

        } else {
            DFLog(this, "    We did not pick a Withdrawal Animation.");

            if addictionData.nicotine.isWithdrawalLevelWorsened {
                DFLog(this, "    Nicotine withdrawal worsened, try to play fallback FX!");
                this.NicotineAddictionSystem.PlayWithdrawalAdvanceSFX();
                this.futureAllowedWithdrawalAnims.allowNicotine = false;
            }

            if addictionData.alcohol.isWithdrawalLevelWorsened {
                DFLog(this, "    Alcohol withdrawal worsened, try to play fallback FX!");
                this.AlcoholAddictionSystem.PlayWithdrawalAdvanceSFX();
                this.futureAllowedWithdrawalAnims.allowAlcohol = false;
            }

            if addictionData.narcotic.isWithdrawalLevelWorsened {
                DFLog(this, "    Narcotic withdrawal worsened, try to play fallback FX!");
                this.NarcoticAddictionSystem.PlayWithdrawalAdvanceSFX();
                this.futureAllowedWithdrawalAnims.allowNarcotic = false;
            }
        }
    }

    private final func SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(addictionSystem: ref<DFAddictionSystemBase>, animSeverity: DFAddictionWithdrawalAnimSeverity) -> Void {
        //DFProfile();
        if Equals(animSeverity, DFAddictionWithdrawalAnimSeverity.Low) && Equals(addictionSystem.GetHasEverPlayedTier1WithdrawalAnim(), false) {
            this.NotificationService.SetMessage(GetLocalizedTextByKey(addictionSystem.GetWithdrawalAnimationLowFirstTimeMessageKey()), SimpleMessageType.Negative);
            addictionSystem.SetHasEverPlayedTier1WithdrawalAnim(true);
        } else if Equals(animSeverity, DFAddictionWithdrawalAnimSeverity.High) && Equals(addictionSystem.GetHasEverPlayedTier2WithdrawalAnim(), false) {
            this.NotificationService.SetMessage(GetLocalizedTextByKey(addictionSystem.GetWithdrawalAnimationHighFirstTimeMessageKey()), SimpleMessageType.Negative);
            addictionSystem.SetHasEverPlayedTier2WithdrawalAnim(true);
        }
    }

    private final func UnqueuePendingAddictionWithdrawalAnim() -> Void {
        // Called in the case of queuing a Blackout or Crash animation to ensure this doesn't play.
        this.UnregisterContextuallyDelayedAddictionWithdrawalAnimation();
        let flags: DFClearQueuedAnimFlags;
        flags.clearWithdrawal = true;
        this.ClearQueuedAnims(flags);
    }

    private final func OnPlayWithdrawalAnimFactChanged(value: Int32) -> Void {
        if value == 0 {
            // Tell the rest of the system that the animation finished playing.
            this.OnAnimFinishedPlaying();
        }
    }

    //
    //  System-Specific Functions
    //
    private final func GetAnimDebugQuestPhaseGraphMessageIDQuestFact() -> CName {
        //DFProfile();
        return n"df_fact_anim_debug_questphase_graph_message_id";
    }
    
    private final func GetQueuedAnimTypeQuestFact() -> CName {
        //DFProfile();
        return n"df_fact_queued_anim_type";
    }

    private final func GetPlayQueuedAnimByIDActionQuestFact() -> CName {
        //DFProfile();
        return n"df_fact_action_play_anim_by_id";
    }

    private final func GetFullBlackoutAnimSubtypeFactAction() -> CName {
        return n"df_fact_blackout_anim_full_subtype";
    }

    private final func GetStartBlackoutFactAction() -> CName {
        return n"df_fact_start_blackout_anim";
    }

    private final func GetStartCrashFactAction() -> CName {
        return n"df_fact_start_crash_anim";
    }

    private final func GetCrashAnimSeverityFact() -> CName {
        return n"df_fact_crash_anim_severity";
    }

    public final func GetNextBlackoutShouldIncludeCrashFact() -> CName {
        return n"df_fact_next_blackout_include_vomit";
    }

    private final func GetBlackoutForceBikeDismountCheckAnimValidityFactAction() -> CName {
        return n"df_fact_action_blackout_force_bike_dismount_check_anim_validity";
    }

    private final func GetBlackoutForceBikeDismountAnimValidityStateFact() -> CName {
        return n"df_fact_blackout_force_bike_dismount_anim_validity_state";
    }

    private final func GetAddictionWithdrawalAnimSeverityFact() -> CName {
        return n"df_fact_addiction_withdrawal_anim_severity";
    }

    private final func GetAddictionWithdrawalAnimType() -> CName {
        return n"df_fact_addiction_withdrawal_anim_type";
    }

    private final func GetStartWithdrawalFactAction() -> CName {
        return n"df_fact_start_addiction_withdrawal_anim";
    }

    public final func GetAnimPlaybackCountRemainingFact() -> CName {
        return n"df_fact_anim_playback_count_remaining";
    }

    public final func OnAnimDebugMessage(value: Int32) -> Void {
        //DFProfile();
        let messageID: DFAnimQuestPhaseGraphDebugMessageID = IntEnum<DFAnimQuestPhaseGraphDebugMessageID>(value);

        switch messageID {
            case DFAnimQuestPhaseGraphDebugMessageID.None:
                break;
            case DFAnimQuestPhaseGraphDebugMessageID.Start:
                DFLog(this, "[[[[[[Quest Phase]]]]]] Animation Quest Phase started.");
                break;
            case DFAnimQuestPhaseGraphDebugMessageID.FailedConditionCheck:
                DFLog(this, "[[[[[[Quest Phase]]]]]] Failed condition check!");
                break;
            case DFAnimQuestPhaseGraphDebugMessageID.SelectedAnimTypeAndID:
                DFLog(this, "[[[[[[Quest Phase]]]]]] Selected Type and ID: Type = " + ToString(IntEnum<DFConsumableAnimType>(this.QuestsSystem.GetFact(this.GetQueuedAnimTypeQuestFact()))) + ", ID = " + ToString(this.QuestsSystem.GetFact(this.GetPlayQueuedAnimByIDActionQuestFact())));
                break;
            default:
                break;
        }
    }

    public final func OnPlayQueuedAnimByID(value: Int32) -> Void {
        if value == 0 {
            // Slight delay in lifting the Pocket Radio restriction override to avoid a 
            // race condition when consuming certain consumables, like pills.
            this.RegisterUnsetRadioRestrictionOverrideCallback();

            // Tell the rest of the system that the animation finished playing.
            this.OnAnimFinishedPlaying();

            // Signal to the Relax Action system that playback is finished. This will
            // trigger other actions.
            this.RelaxActionSystem.OnConsumeAnimFinished();
        }
    }

    private final func SetupConsumableAnimData() -> Void {
        //DFProfile();
        let fallbackMethFX: DFConsumableAnimFX;
        fallbackMethFX.vfx = n"reflex_buster";

        let fallbackHealFX: DFConsumableAnimFX;
        fallbackHealFX.vfx = n"splinter_buff";

        let fallbackDrinkFX: DFConsumableAnimFX;
        fallbackDrinkFX.audio = n"ui_loot_drink";

        let fallbackEatFX: DFConsumableAnimFX;
        fallbackEatFX.audio = n"ui_loot_eat";

        let fallbackGenericFX: DFConsumableAnimFX;
        fallbackGenericFX.audio = n"ui_menu_item_consumable_generic";

        // P0 (Unique)
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Pizza, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.PizzaUnique), n"DarkFutureAnimFoodPizzaUnique", 0, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.SodaCanChug, DFConsumableAnimPropSubType.ChromanticoreChug, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFDrinkChugLeftHandAnimID.ChromanticoreChug), n"DarkFutureAnimDrinkChromanticoreChugUnique", 0, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Sandwich, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.SandwichUnique), n"DarkFutureAnimFoodSandwichUnique", 0, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.CoffeeTeaToGo, DFConsumableAnimPropSubType.CoffeeTeaToGo, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaToGo), n"DarkFutureAnimCoffeeTeaToGoUnique", 0, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Pierogi, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.PierogiUnique), n"DarkFutureAnimFoodPierogiUnique", 0, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Cupcake, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.CupcakeUnique), n"DarkFutureAnimFoodCupcakeUnique", 0, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.CoffeeTeaOpenCup, DFConsumableAnimPropSubType.CoffeeTeaOpenCup, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaOpenCup), n"DarkFutureAnimCoffeeTeaOpenCupUnique", 0, fallbackDrinkFX, this.maxPlaybackCountDrinks, false)); // TODOFUTURE - Visual error
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.CentzonIndigoUnique, DFConsumableAnimCooldownExceptionType.Unique, EnumInt(DFDrinkChugLeftHandAnimID.CentzonIndigoUnique), n"DarkFutureAnimAlcoholCentzonUnique", 0, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        
        // P10
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.CatFood, DFConsumableAnimPropSubType.CatFood, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.CatFood), n"DarkFutureAnimFoodCatFood", 10, fallbackEatFX, this.maxPlaybackCountFood, false));

        // P20
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Inhaler, DFConsumableAnimPropType.DrugInhaler, DFConsumableAnimPropSubType.Glitter, DFConsumableAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.Glitter), n"DarkFutureAnimInhalerGlitter", 20, fallbackMethFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Inhaler, DFConsumableAnimPropType.DrugInhaler, DFConsumableAnimPropSubType.BlackLace, DFConsumableAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.BlackLace), n"DarkFutureAnimInhalerBlackLace", 20, fallbackMethFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.MrWhitey, DFConsumableAnimPropType.MrWhitey, DFConsumableAnimPropSubType.MrWhitey, DFConsumableAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.MrWhitey), n"DarkFutureAnimNarcoticsMrWhitey", 20, fallbackMethFX, this.maxPlaybackCountDrugs, false));

        // P30
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Smoking, DFConsumableAnimPropType.Smoking, DFConsumableAnimPropSubType.Smoking, DFConsumableAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.Smoking), n"DarkFutureAnimSmoking", 30, fallbackGenericFX, this.maxPlaybackCountSmoking, false));

        // P40
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_B, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Red), n"DarkFutureAnimPillBRed", 40, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_B, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Green), n"DarkFutureAnimPillBGreen", 40, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_B, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Pink), n"DarkFutureAnimPillBPink", 40, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.SodaCanChug, DFConsumableAnimPropSubType.ChromanticoreChug, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkChugLeftHandAnimID.ChromanticoreChug), n"DarkFutureAnimDrinkChromanticoreChug", 40, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));

        // P50
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Inhaler, DFConsumableAnimPropType.PharmaceuticalInhaler, DFConsumableAnimPropSubType.Immunosuppressant, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Immunosuppressant), n"DarkFutureAnimInhalerImmunosuppressant", 50, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Inhaler, DFConsumableAnimPropType.PharmaceuticalInhaler, DFConsumableAnimPropSubType.Addiquit, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Addiquit), n"DarkFutureAnimInhalerAddiquit", 50, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Inhaler, DFConsumableAnimPropType.PharmaceuticalInhaler, DFConsumableAnimPropSubType.EmergencyCardioregulator, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.EmergencyCardioregulator), n"DarkFutureAnimInhalerEmergencyCardioregulator", 50, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.PharmaceuticalLarge, DFConsumableAnimPropSubType.Jellytricity, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFEatLookDownRightHandAnimID.Jellytricity), n"DarkFutureAnimDrugJellytricity", 50, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.PharmaceuticalThinPackaged, DFConsumableAnimPropSubType.RAMNugs, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.RAMNugs), n"DarkFutureAnimDrugRAMNugs", 50, fallbackHealFX, this.maxPlaybackCountDrugs, false));

        // P60
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.HealthBooster, DFConsumableAnimPropType.HealthBooster, DFConsumableAnimPropSubType.HealthBooster, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.HealthBooster), n"DarkFutureAnimHealthBooster", 60, fallbackHealFX, this.maxPlaybackCountDrugs, false));

        // P70
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_A, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Blue), n"DarkFutureAnimPillABlue", 70, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_A, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Green), n"DarkFutureAnimPillAGreen", 70, fallbackHealFX, this.maxPlaybackCountDrugs, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.Drugs, DFConsumableAnimSubType.Pills, DFConsumableAnimPropType.Pill, DFConsumableAnimPropSubType.Pill_A, DFConsumableAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Pink), n"DarkFutureAnimPillAPink", 70, fallbackHealFX, this.maxPlaybackCountDrugs, false));

        // P80
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.PingoPalido, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.PingoPalido), n"DarkFutureAnimAlcoholPingoPalido", 80, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        
        // P90
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.Cocktail, DFConsumableAnimPropSubType.Cocktail, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.Cocktail), n"DarkFutureAnimAlcoholCocktail", 90, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));

        // P100
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Centzon, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Centzon), n"DarkFutureAnimAlcoholCentzon", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Donaghys, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Donaghys), n"DarkFutureAnimAlcoholDonaghys", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Bolshevik, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Bolshevik), n"DarkFutureAnimAlcoholBolshevik", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.TequilaEspecial, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TequilaEspecial), n"DarkFutureAnimAlcoholTequilaEspecial", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.BlueGrass, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.BlueGrass), n"DarkFutureAnimAlcoholBlueGrass", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Wine, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Wine), n"DarkFutureAnimAlcoholWine", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Champaradise, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Champaradise), n"DarkFutureAnimAlcoholChamparadise", 100, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));

        // P110
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.CalaveraFeliz, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.CalaveraFeliz), n"DarkFutureAnimAlcoholCalaveraFeliz", 110, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.JoeTiel, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.JoeTiel), n"DarkFutureAnimAlcoholJoeTiel", 110, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Bumelant, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Bumelant), n"DarkFutureAnimAlcoholBumelant", 110, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.Odickin, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Odickin), n"DarkFutureAnimAlcoholOdickin", 110, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));

        // P120
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.CentzonInverted, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.CentzonInverted), n"DarkFutureAnimAlcoholCentzonInverted", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.JoeTielInverted, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.JoeTielInverted), n"DarkFutureAnimAlcoholJoeTielInverted", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.OdickinInverted, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.OdickinInverted), n"DarkFutureAnimAlcoholOdickinInverted", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.TequilaEspecialInverted, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TequilaEspecialInverted), n"DarkFutureAnimAlcoholTequilaEspecialInverted", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.GenericHooch, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.GenericHooch), n"DarkFutureAnimAlcoholGenericHooch", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.ChamparadiseInverted, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.ChamparadiseInverted), n"DarkFutureAnimAlcoholChamparadiseInverted", 120, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        
        // P130
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.AbydosLarge, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.AbydosLarge), n"DarkFutureAnimAlcoholAbydosLarge", 130, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.LargeBottle, DFConsumableAnimPropSubType.TwentyFirstStout, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TwentyFirstStout), n"DarkFutureAnimAlcoholTwentyFirstStout", 130, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SmallBottle, DFConsumableAnimPropSubType.BrosephBottle, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBrown), n"DarkFutureAnimAlcoholBrosephBrown", 130, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SmallBottle, DFConsumableAnimPropSubType.BrosephBottle, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBlue), n"DarkFutureAnimAlcoholBrosephBlue", 130, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SmallBottle, DFConsumableAnimPropSubType.BrosephBottle, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBrownInverted), n"DarkFutureAnimAlcoholBrosephBrownInverted", 130, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SmallBottle, DFConsumableAnimPropSubType.AbydosSmall, DFConsumableAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.AbydosSmall), n"DarkFutureAnimAlcoholAbydosSmall", 130, fallbackDrinkFX, this.maxPlaybackCountDrinks, false)); // TODOFUTURE - Visual error

        // P140
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkChugLeftHand, DFConsumableAnimSubType.DrinkChugLeftHand, DFConsumableAnimPropType.WaterBottle, DFConsumableAnimPropSubType.SainRuisseau, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkChugLeftHandAnimID.SainRuisseau), n"DarkFutureAnimDrinkSainRuisseau", 140, fallbackDrinkFX, this.maxPlaybackCountDrinksChug, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.WaterBottle, DFConsumableAnimPropSubType.Vatnajokull, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Vatnajokull), n"DarkFutureAnimDrinkVatnajokull", 140, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.CoffeeTeaOpenCup, DFConsumableAnimPropSubType.CoffeeTeaOpenCup, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaOpenCup), n"DarkFutureAnimCoffeeTeaOpenCup", 140, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.CoffeeTeaToGo, DFConsumableAnimPropSubType.CoffeeTeaToGo, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaToGo), n"DarkFutureAnimCoffeeTeaToGo", 140, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.WaterBottle, DFConsumableAnimPropSubType.WaterBottle, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.WaterBottle), n"DarkFutureAnimDrinkWaterBottle", 140, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.LargePackagedGenericGold, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.LargePackagedGenericGold), n"DarkFutureAnimFoodLargePackagedGenericGold", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.LargePackagedGenericSilver, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.LargePackagedGenericSilver), n"DarkFutureAnimFoodLargePackagedGenericSilver", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.MeatLog, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.MeatLog), n"DarkFutureAnimFoodMeatLog", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Nigiri, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Nigiri), n"DarkFutureAnimFoodNigiri", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Norimaki, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Norimaki), n"DarkFutureAnimFoodNorimaki", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.DriedMeat, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.DriedMeat), n"DarkFutureAnimFoodDriedMeat", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Wontons, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Wontons), n"DarkFutureAnimFoodWontons", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Ramen, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Ramen), n"DarkFutureAnimFoodRamen", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.SoupLight, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.SoupLight), n"DarkFutureAnimFoodSoupLight", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.SoupDark, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.SoupDark), n"DarkFutureAnimFoodSoupDark", 140, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedDrink, DFConsumableAnimPropSubType.DaringDairy, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.DaringDairy), n"DarkFutureAnimDrinkDaringDairy", 140, fallbackEatFX, this.maxPlaybackCountFood, false));

        // P150
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Taco, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Taco), n"DarkFutureAnimFoodTaco", 150, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.HotDog, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.HotDog), n"DarkFutureAnimFoodHotDog", 150, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Fruit, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Fruit), n"DarkFutureAnimFoodFruit", 150, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.BeefCan, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.BeefCan), n"DarkFutureAnimFoodBeefCan", 150, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatLookDownRightHand, DFConsumableAnimSubType.EatLookDownRightHand, DFConsumableAnimPropType.LargeFood, DFConsumableAnimPropSubType.Pizza, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Pizza), n"DarkFutureAnimFoodPizza", 150, fallbackEatFX, this.maxPlaybackCountFood, false));

        // P160
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.Chromanticore, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Chromanticore), n"DarkFutureAnimDrinkChromanticore", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.Nicola, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Nicola_A), n"DarkFutureAnimDrinkNicolaA", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.Nicola, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Nicola_B), n"DarkFutureAnimDrinkNicolaB", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.CirrusCola, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CirrusCola_A), n"DarkFutureAnimDrinkCirrusColaA", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.CirrusCola, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CirrusCola_B), n"DarkFutureAnimDrinkCirrusColaB", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.Tiancha, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Tiancha), n"DarkFutureAnimDrinkTiancha", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.DrinkSipRightHand, DFConsumableAnimSubType.DrinkSipRightHand, DFConsumableAnimPropType.SodaCan, DFConsumableAnimPropSubType.SpunkyMonkey, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.SpunkyMonkey), n"DarkFutureAnimDrinkSpunkyMonkey", 160, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.Burrito, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_A), n"DarkFutureAnimFoodBurritoA", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.Burrito, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_B), n"DarkFutureAnimFoodBurritoB", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.Burrito, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_C), n"DarkFutureAnimFoodBurritoC", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.Holobites, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Holobites), n"DarkFutureAnimFoodHolobites", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.Moonchies, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Moonchies), n"DarkFutureAnimFoodMoonchies", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.LeelouBeans, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.LeelouBeans), n"DarkFutureAnimFoodLeelouBeans", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.PopTurd, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.PopTurd), n"DarkFutureAnimFoodPopTurd", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.ShwabShwab, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ShwabShwab), n"DarkFutureAnimFoodShwabShwab", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.SynthSnack, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.SynthSnack), n"DarkFutureAnimFoodSynthSnack", 160, fallbackEatFX, this.maxPlaybackCountFood, false));
        
        // P900
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedDrink, DFConsumableAnimPropSubType.LeelouBeansInverted, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.LeelouBeansInverted), n"DarkFutureAnimDrinkLeelouBeansInverted", 900, fallbackDrinkFX, this.maxPlaybackCountDrinks, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.ThinPackagedGeneric, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ThinPackagedGeneric), n"DarkFutureAnimFoodThinPackagedGeneric", 900, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.ThinPackagedGenericLarge, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ThinPackagedGenericLarge), n"DarkFutureAnimFoodThinPackagedGenericLarge", 900, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.SynthSnackNoLabel, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.SynthSnackNoLabel), n"DarkFutureAnimFoodSynthSnackNoLabel", 900, fallbackEatFX, this.maxPlaybackCountFood, false));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFConsumableAnimType.EatDrinkThinPackagedLeftHand, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand, DFConsumableAnimPropType.ThinPackagedFood, DFConsumableAnimPropSubType.CandyBar, DFConsumableAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.CandyBar), n"DarkFutureAnimFoodCandyBar", 900, fallbackEatFX, this.maxPlaybackCountFood, false));
    }

    private final func FindConsumableAnimByTag(tag: CName) -> DFConsumableAnimDatum {
        //DFProfile();
        for datum in this.consumableAnimData {
            if Equals(datum.tag, tag) {
                DFLog(this, "FindConsumableAnimByTag returning " + ToString(datum));
                return datum;
            }
        }
        return this.GetInvalidDFConsumableAnimDatum();
    }

    private final func ClearConsumableFallbackFXQueue() -> Void {
        //DFProfile();
        this.queuedFallbackFX = this.GetInvalidDFConsumableAnimFX();
    }

    private final func GetInvalidAnimPriority() -> Int32 {
        //DFProfile();
        return 9999;
    }

    public final func GetInvalidDFConsumableAnimDatum() -> DFConsumableAnimDatum {
        //DFProfile();
        let invalidFX: DFConsumableAnimFX;
        return DFConsumableAnimDatum(DFConsumableAnimType.Invalid, DFConsumableAnimSubType.Invalid, DFConsumableAnimPropType.Invalid, DFConsumableAnimPropSubType.Invalid, DFConsumableAnimCooldownExceptionType.None, 0, n"", this.GetInvalidAnimPriority(), invalidFX, 0, false);
    }

    private final func GetInvalidDFConsumableAnimFX() -> DFConsumableAnimFX {
        //DFProfile();
        let invalidFX: DFConsumableAnimFX;
        return invalidFX;
    }

    public final func OnProcessFallbackFX() -> Void {
        //DFProfile();
        this.ProcessFallbackFXQueue();
    }

    public final func OnUnsetRadioRestrictionOverride() -> Void {
        this.player.m_pocketRadio.DFSetRestrictionOverride(false);
    }

    private final func ProcessFallbackFXQueue() -> Void {
        //DFProfile();
        this.TryToPlayConsumableFallbackFX();
        this.ClearConsumableFallbackFXQueue();
    }

    private final func QueueFallbackFX(fx: DFConsumableAnimFX, opt queuedAnims: array<DFAnimDatum>) -> Void {
        //DFProfile();
        for anim in queuedAnims {
            if Equals(anim.type, DFAnimType.Consumable) && Equals(anim.consumableAnimData.fallbackFX, fx) {
                // Avoid playing fallback effects for repeated use of the same consumable.
                return;
            }
        }

        this.queuedFallbackFX = fx;
        this.RegisterProcessFallbackFXQueueCallback();
    }

    public final func TryToPlayConsumableFallbackFX() -> Void {
        //DFProfile();
        if NotEquals(this.queuedFallbackFX.vfx, n"") {
            GameObjectEffectHelper.StartEffectEvent(this.player, this.queuedFallbackFX.vfx, false, null, false);
        }

        if NotEquals(this.queuedFallbackFX.statusEffect, t"") {
            StatusEffectHelper.ApplyStatusEffect(this.player, this.queuedFallbackFX.statusEffect);
        }

        if !this.GameStateService.IsInAnyMenu() {
            if NotEquals(this.queuedFallbackFX.audio, n"") {
                let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
                evt.soundName = this.queuedFallbackFX.audio;
                this.player.QueueEvent(evt);
            }    
        }
    }

    //
	//  Registration
	//
    private final func RegisterProcessAnimQueueCallback(debounce: Bool) -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessAnimQueueDelayCallback.Create(), this.processAnimQueueDelayID, debounce ? this.processAnimQueueDelayIntervalSlow : this.processAnimQueueDelayInterval);
	}

    private final func RegisterProcessFallbackFXQueueCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessFallbackFXQueueDelayCallback.Create(), this.processFallbackFXQueueDelayID, this.processFallbackFXQueueDelayInterval);
	}

    public final func RegisterUnsetRadioRestrictionOverrideCallback() -> Void {
		RegisterDFDelayCallback(this.DelaySystem, UnsetRadioRestrictionOverrideDelayCallback.Create(), this.unsetRadioRestrictionOverrideDelayID, this.unsetRadioRestrictionOverrideDelayInterval);
	}

    private final func RegisterContextuallyDelayedBlackoutAnimation() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedBlackoutAnimationDelayCallback.Create(), this.contextuallyDelayedBlackoutAnimationDelayID, this.contextuallyDelayedBlackoutAnimationDelayInterval);
	}

    public final func RegisterBlackoutForceBikeDismountCheckAnimValidity() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, BlackoutForceBikeDismountRecheckAnimValidityDelayCallback.Create(), this.blackoutForceBikeDismountRecheckAnimValidityDelayID, this.blackoutForceBikeDismountRecheckAnimValidityDelayInterval);
	}

    public final func RegisterContextuallyDelayedAddictionWithdrawalAnimation(addictionData: DFAddictionDatum, timeSkipType: DFTimeSkipType) -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedAddictionWithdrawalAnimationDelayCallback.Create(addictionData, timeSkipType), this.contextuallyDelayedAddictionWithdrawalAnimationDelayID, this.contextuallyDelayedAddictionWithdrawalAnimationDelayInterval);
	}

    public final func RegisterContextuallyDelayedCrashAnimation(mode: DFCrashAnimMode) -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ContextuallyDelayedCrashAnimationDelayCallback.Create(mode), this.contextuallyDelayedCrashAnimationDelayID, this.contextuallyDelayedCrashAnimationDelayInterval);
    }

    //
	//	Deregistration
	//
	private final func UnregisterProcessAnimQueueCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.processAnimQueueDelayID);
	}

    private final func UnregisterProcessFallbackFXQueueCallback() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.processFallbackFXQueueDelayID);
	}

    private final func UnregisterUnsetRadioRestrictionOverrideCallback() -> Void {
		UnregisterDFDelayCallback(this.DelaySystem, this.unsetRadioRestrictionOverrideDelayID);
	}

    private final func UnregisterContextuallyDelayedBlackoutAnimation() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedBlackoutAnimationDelayID);
	}

    private final func UnregisterBlackoutForceBikeDismountRecheckAnimValidity() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.blackoutForceBikeDismountRecheckAnimValidityDelayID);
	}

    private final func UnregisterContextuallyDelayedAddictionWithdrawalAnimation() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedAddictionWithdrawalAnimationDelayID);
	}

    private final func UnregisterContextuallyDelayedCrashAnimation() -> Void {
        //DFProfile();
		UnregisterDFDelayCallback(this.DelaySystem, this.contextuallyDelayedCrashAnimationDelayID);
	}

    public final func IsPlayerInAllowedStateForAnyAnimation(opt ignoreVehicle: Bool, opt vehicleExitBlocked: Bool, opt ignoreGroundCheck: Bool) -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();

        let validGameState: Bool = this.GameStateService.IsValidGameState(this);

        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).GetLocalInstanced(this.player.GetEntityID(), bbDefs.PlayerStateMachine);
        let upperBodyState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.UpperBody);
        let inLoreAnimationScene: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsInLoreAnimationScene);
        let isCarryingBody: Bool = bboard.GetInt(bbDefs.PlayerStateMachine.BodyCarrying) > 0;
        let isControllingDevice: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingDevice);
        let isControllingCamera: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingCamera);
        let isForceOpeningDoor: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsForceOpeningDoor);

        let locomotionState: gamePSMDetailedLocomotionStates = IntEnum<gamePSMDetailedLocomotionStates>(bboard.GetInt(bbDefs.PlayerStateMachine.LocomotionDetailed));
        let isLocomotionStateAllowed: Bool = Equals(locomotionState, gamePSMDetailedLocomotionStates.Stand);
        
        let combatGadgetState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.CombatGadget);
        let leftHandCyberwareState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.LeftHandCyberware);
        
        let isPlayerInsideElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideElevator);
        let isPlayerInsideMovingElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideMovingElevator);
        isPlayerInsideElevator = isPlayerInsideElevator || isPlayerInsideMovingElevator;

        let isOnGround: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsOnGround) || ignoreGroundCheck;
        let uploadingQuickHackIDs: array<TweakDBID> = FromVariant<array<TweakDBID>>(bboard.GetVariant(bbDefs.PlayerStateMachine.UploadingQuickHackIDs));
        let isUploadingQuickhacks: Bool = ArraySize(uploadingQuickHackIDs) > 0;

        let isInCombat: Bool = this.player.IsInCombat();
        let isReplacer: Bool = this.player.IsReplacer();
        let allowedSceneTier: Bool = PlayerPuppet.GetSceneTier(this.player) <= 2;
        let isSwimming: Bool = PlayerPuppet.IsSwimming(this.player);
        let isMountedToVehicle: Bool = VehicleComponent.IsMountedToVehicle(gameInstance, this.player);
        let vehObj: wref<VehicleObject>;
        VehicleComponent.GetVehicle(gameInstance, this.player, vehObj);
        let isMountedToQuestVehicle: Bool = IsDefined(vehObj) && vehObj.IsQuest();

        let isPlayerInWorkspot: Bool = GameInstance.GetWorkspotSystem(gameInstance).IsActorInWorkspot(this.player);
        let isPhoneCallActive: Bool = GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive();
        let isPlayerPursuedByNCPD: Bool = this.player.GetPreventionSystem().IsChasingPlayer();

        let inValidVehicleState: Bool = (ignoreVehicle && !vehicleExitBlocked && !isMountedToQuestVehicle);
        let allowedVehicleCondition: Bool = (!isMountedToVehicle || inValidVehicleState);
        let allowedWorkspotCondition: Bool = (!isPlayerInWorkspot || (isMountedToVehicle && inValidVehicleState));
        let allowedGroundCondition: Bool = (isOnGround || (isMountedToVehicle && inValidVehicleState));

        if validGameState &&
            !isInCombat && 
            !isReplacer && 
            !inLoreAnimationScene &&
            !isCarryingBody &&
            !isControllingDevice &&
            !isControllingCamera &&
            !isForceOpeningDoor &&
            allowedSceneTier && 
            !isSwimming && 
            allowedVehicleCondition && 
            allowedWorkspotCondition &&
            upperBodyState != 4 && 
            isLocomotionStateAllowed && 
            combatGadgetState == 0 && 
            leftHandCyberwareState == 0 && 
            !isPhoneCallActive &&
            !isPlayerInsideElevator && 
            allowedGroundCondition && 
            !isUploadingQuickhacks && 
            !isPlayerPursuedByNCPD {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        validGameState (expected true): " + ToString(validGameState));
        DFLog(this, "        isInCombat (expected false): "  + ToString(isInCombat));
        DFLog(this, "        isReplacer (expected false): "  + ToString(isReplacer));
        DFLog(this, "        inLoreAnimationScene (expected false): " + ToString(inLoreAnimationScene));
        DFLog(this, "        isCarryingBody (expected false): " + ToString(isCarryingBody));
        DFLog(this, "        isControllingDevice (expected false): " + ToString(isControllingDevice));
        DFLog(this, "        isControllingCamera (expected false): " + ToString(isControllingCamera));
        DFLog(this, "        isForceOpeningDoor (expected false): " + ToString(isForceOpeningDoor));
        DFLog(this, "        allowedSceneTier (expected true): " + ToString(allowedSceneTier));
        DFLog(this, "        isSwimming (expected false): "  + ToString(isSwimming));
        DFLog(this, "        allowedVehicleCondition (expected true): "  + ToString(allowedVehicleCondition));
        DFLog(this, "        allowedWorkspotCondition (expected true): "  + ToString(allowedWorkspotCondition));
        DFLog(this, "        upperBodyState (expected != 4): " + ToString(upperBodyState));
        DFLog(this, "        isLocomotionStateAllowed (expected true): " + ToString(isLocomotionStateAllowed));
        DFLog(this, "        combatGadgetState (expected 0): " + ToString(combatGadgetState));
        DFLog(this, "        leftHandCyberwareState (expected 0): " + ToString(leftHandCyberwareState));
        DFLog(this, "        isPhoneCallActive (expected false): " + ToString(isPhoneCallActive));
        DFLog(this, "        isPlayerInsideElevator (expected false): " + ToString(isPlayerInsideElevator));
        DFLog(this, "        allowedGroundCondition (expected true): " + ToString(allowedGroundCondition));
        DFLog(this, "        isUploadingQuickhacks (expected false): " + ToString(isUploadingQuickhacks));
        DFLog(this, "        isPlayerPursuedByNCPD (expected false): " + ToString(isPlayerPursuedByNCPD));

        return false;
    }

    public final func IsPlayerInAllowedStateForForcedBikeDismountBlackoutAnimation() -> Bool {
        //DFProfile();
        let validGameState: Bool = this.GameStateService.IsValidGameState(this);
        let isSwimming: Bool = PlayerPuppet.IsSwimming(this.player);

        if validGameState &&
            !isSwimming {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        validGameState (expected true): " + ToString(validGameState));
        DFLog(this, "        isSwimming (expected false): "  + ToString(isSwimming));

        return false;
    }

    public final func IsPlayerInAllowedStateForConsumableAnimation() -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();
        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).GetLocalInstanced(this.player.GetEntityID(), bbDefs.PlayerStateMachine);

        let isMoving: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingHorizontally) || bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingVertically);

        if this.IsPlayerInAllowedStateForAnyAnimation() && !isMoving {
            return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        isMoving (expected false): " + ToString(isMoving));

        return false;
    }

    public final func IsPlayerInAllowedStateForRelaxActionModeEnterAndShowMessage() -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();

        let validGameState: Bool = this.GameStateService.IsValidGameState(this);

        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).GetLocalInstanced(this.player.GetEntityID(), bbDefs.PlayerStateMachine);
        let upperBodyState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.UpperBody);
        let inLoreAnimationScene: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsInLoreAnimationScene);
        let psmLocomotion: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.Locomotion);
        let isCrouching: Bool = psmLocomotion == 1;
        let isSprinting: Bool = psmLocomotion == 2;
        let isJumping: Bool = psmLocomotion == 4;
        let isCrouchSprinting: Bool = psmLocomotion == 11;
        let isCrouchDodging: Bool = psmLocomotion == 12;
        let meleeState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.MeleeWeapon);
        let leftRangedState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.LeftWeapon);
        let rightRangedState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.RightWeapon);

        let isCarryingBody: Bool = bboard.GetInt(bbDefs.PlayerStateMachine.BodyCarrying) > 0;
        let isControllingDevice: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingDevice);
        let isControllingCamera: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingCamera);
        let isForceOpeningDoor: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsForceOpeningDoor);

        let locomotionState: gamePSMDetailedLocomotionStates = IntEnum<gamePSMDetailedLocomotionStates>(bboard.GetInt(bbDefs.PlayerStateMachine.LocomotionDetailed));
        let isLocomotionStateAllowed: Bool = Equals(locomotionState, gamePSMDetailedLocomotionStates.Stand);
        
        let combatGadgetState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.CombatGadget);
        let leftHandCyberwareState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.LeftHandCyberware);
        
        let isPlayerInsideElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideElevator);
        let isPlayerInsideMovingElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideMovingElevator);
        isPlayerInsideElevator = isPlayerInsideElevator || isPlayerInsideMovingElevator;

        let isOnGround: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsOnGround);
        let uploadingQuickHackIDs: array<TweakDBID> = FromVariant<array<TweakDBID>>(bboard.GetVariant(bbDefs.PlayerStateMachine.UploadingQuickHackIDs));
        let isUploadingQuickhacks: Bool = ArraySize(uploadingQuickHackIDs) > 0;

        let isInCombat: Bool = this.player.IsInCombat();
        let isReplacer: Bool = this.player.IsReplacer();
        let allowedSceneTier: Bool = PlayerPuppet.GetSceneTier(this.player) <= 2;
        let isSwimming: Bool = PlayerPuppet.IsSwimming(this.player);
        let isMountedToVehicle: Bool = VehicleComponent.IsMountedToVehicle(gameInstance, this.player);

        let isPlayerInWorkspot: Bool = GameInstance.GetWorkspotSystem(gameInstance).IsActorInWorkspot(this.player);
        let isPhoneCallActive: Bool = GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive();
        let isPlayerPursuedByNCPD: Bool = this.player.GetPreventionSystem().IsChasingPlayer();

        let uiInteractionsBboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).Get(bbDefs.UIInteractions);
        let dialogChoiceHubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(uiInteractionsBboard.GetVariant(bbDefs.UIInteractions.DialogChoiceHubs));
        let noDialogueChoiceHubsShown: Bool = ArraySize(dialogChoiceHubs.choiceHubs) == 0;

        if isInCombat ||
            inLoreAnimationScene ||
            isForceOpeningDoor ||
            (!isLocomotionStateAllowed && !isCrouching && !isPlayerInWorkspot && !isSprinting && !isJumping && !isCrouchSprinting && !isCrouchDodging) ||
            combatGadgetState != 0 || 
            leftHandCyberwareState != 0 || 
            isPhoneCallActive ||
            isPlayerInsideElevator || 
            !isOnGround ||
            isUploadingQuickhacks || 
            isPlayerPursuedByNCPD {
                // Show message
                let UISystem = GameInstance.GetUISystem(GetGameInstance());
		        let notificationEvent: ref<UIInGameNotificationEvent> = new UIInGameNotificationEvent();
                notificationEvent.m_notificationType = UIInGameNotificationType.ActionRestriction;
                UISystem.QueueEvent(notificationEvent);

        }


        if validGameState &&
            !isInCombat && 
            meleeState == 0 &&
            leftRangedState == 0 &&
            rightRangedState == 0 &&
            noDialogueChoiceHubsShown &&
            !isReplacer && 
            !inLoreAnimationScene &&
            !isCrouching &&
            !isCarryingBody &&
            !isControllingDevice &&
            !isControllingCamera &&
            !isForceOpeningDoor &&
            allowedSceneTier && 
            !isSwimming && 
            !isMountedToVehicle && 
            !isPlayerInWorkspot &&
            upperBodyState != 4 && 
            isLocomotionStateAllowed && 
            combatGadgetState == 0 && 
            leftHandCyberwareState == 0 && 
            !isPhoneCallActive &&
            !isPlayerInsideElevator && 
            isOnGround && 
            !isUploadingQuickhacks && 
            !isPlayerPursuedByNCPD {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        validGameState (expected true): " + ToString(validGameState));
        DFLog(this, "        isInCombat (expected false): "  + ToString(isInCombat));
        DFLog(this, "        meleeState (expected 0): " + ToString(meleeState));
        DFLog(this, "        leftRangedState (expected 0): " + ToString(leftRangedState));
        DFLog(this, "        rightRangedState (expected 0): " + ToString(rightRangedState));
        DFLog(this, "        noDialogueChoiceHubsShown (expected true): " + ToString(noDialogueChoiceHubsShown));
        DFLog(this, "        isReplacer (expected false): "  + ToString(isReplacer));
        DFLog(this, "        inLoreAnimationScene (expected false): " + ToString(inLoreAnimationScene));
        DFLog(this, "        isCrouching (expected false): " + ToString(isCrouching));
        DFLog(this, "        isCarryingBody (expected false): " + ToString(isCarryingBody));
        DFLog(this, "        isControllingDevice (expected false): " + ToString(isControllingDevice));
        DFLog(this, "        isControllingCamera (expected false): " + ToString(isControllingCamera));
        DFLog(this, "        isForceOpeningDoor (expected false): " + ToString(isForceOpeningDoor));
        DFLog(this, "        allowedSceneTier (expected true): " + ToString(allowedSceneTier));
        DFLog(this, "        isSwimming (expected false): "  + ToString(isSwimming));
        DFLog(this, "        isMountedToVehicle (expected false): "  + ToString(isMountedToVehicle));
        DFLog(this, "        isPlayerInWorkspot (expected false): "  + ToString(isPlayerInWorkspot));
        DFLog(this, "        upperBodyState (expected != 4): " + ToString(upperBodyState));
        DFLog(this, "        isLocomotionStateAllowed (expected true): " + ToString(isLocomotionStateAllowed));
        DFLog(this, "        combatGadgetState (expected 0): " + ToString(combatGadgetState));
        DFLog(this, "        leftHandCyberwareState (expected 0): " + ToString(leftHandCyberwareState));
        DFLog(this, "        isPhoneCallActive (expected false): " + ToString(isPhoneCallActive));
        DFLog(this, "        isPlayerInsideElevator (expected false): " + ToString(isPlayerInsideElevator));
        DFLog(this, "        isOnGround (expected true): " + ToString(isOnGround));
        DFLog(this, "        isUploadingQuickhacks (expected false): " + ToString(isUploadingQuickhacks));
        DFLog(this, "        isPlayerPursuedByNCPD (expected false): " + ToString(isPlayerPursuedByNCPD));

        return false;
    }

    public final func IsPlayerInAllowedStateForRelaxActionAnimation() -> Bool {
        // By this point we already know that the player isn't moving, in an elevator, etc.
        // Only check for states that might change since we last checked.

        //DFProfile();
        let gameInstance = GetGameInstance();

        let validGameState: Bool = this.GameStateService.IsValidGameState(this);

        let isInCombat: Bool = this.player.IsInCombat();
        let isPhoneCallActive: Bool = GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive();
        let isPlayerPursuedByNCPD: Bool = this.player.GetPreventionSystem().IsChasingPlayer();

        if validGameState &&
            !isInCombat && 
            !isPhoneCallActive &&
            !isPlayerPursuedByNCPD {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        validGameState (expected true): " + ToString(validGameState));
        DFLog(this, "        isInCombat (expected false): "  + ToString(isInCombat));
        DFLog(this, "        isPhoneCallActive (expected false): " + ToString(isPhoneCallActive));
        DFLog(this, "        isPlayerPursuedByNCPD (expected false): " + ToString(isPlayerPursuedByNCPD));

        return false;
    }

    public final func IsPlayerInAllowedStateForAddictionWithdrawalAnimation() -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();
        
        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).Get(bbDefs.UIInteractions);
        let dialogChoiceHubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(bboard.GetVariant(bbDefs.UIInteractions.DialogChoiceHubs));
        let noDialogueChoiceHubsShown: Bool = ArraySize(dialogChoiceHubs.choiceHubs) == 0;
        let inRelaxActionMode: Bool = this.RelaxActionSystem.GetInRelaxActionMode();

        // Since this is always the result of a time skip, ignore ground state checks. (Player can't skip time in mid-air, and
        // this was causing spurious failures when exiting a bed.)
        if this.IsPlayerInAllowedStateForAnyAnimation(false, false, true) && (noDialogueChoiceHubsShown || inRelaxActionMode) {
            return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        noDialogueChoiceHubsShown (Expected: true): " + ToString(noDialogueChoiceHubsShown) + ", overridden by inRelaxActionMode: " + ToString(inRelaxActionMode));

        return false;
    }

    public final func IsPlayerInAllowedStateForBlackoutAnimation() -> Bool {
        //DFProfile();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();
        
        let psmBBoard: ref<IBlackboard> = this.player.GetPlayerStateMachineBlackboard();
        let uiBBoard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(bbDefs.UIInteractions);
        let dialogChoiceHubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(uiBBoard.GetVariant(bbDefs.UIInteractions.DialogChoiceHubs));
        let noDialogueChoiceHubsShown: Bool = ArraySize(dialogChoiceHubs.choiceHubs) == 0;
        let inRelaxActionMode: Bool = this.RelaxActionSystem.GetInRelaxActionMode();

        let variantData: Variant = psmBBoard.GetVariant(GetAllBlackboardDefs().PlayerStateMachine.SecurityZoneData);
        let securityData: SecurityAreaData;
        if IsDefined(variantData) {
            securityData = FromVariant<SecurityAreaData>(variantData);
        };

        let blockTimeSkip: Bool = psmBBoard.GetInt(bbDefs.PlayerStateMachine.Combat) == 1 || 
                                  StatusEffectSystem.ObjectHasStatusEffectWithTag(this.player, n"NoTimeSkip") || 
                                  this.player.IsMovingVertically() || 
                                  PlayerPuppet.IsSwimming(this.player) || 
                                  securityData.securityAreaType > ESecurityAreaType.SAFE ||
                                  GameInstance.GetPhoneManager(GetGameInstance()).IsPhoneCallActive() ||
                                  psmBBoard.GetBool(bbDefs.PlayerStateMachine.Carrying);

        if this.IsPlayerInAllowedStateForAnyAnimation(true, this.IsExitVehicleBlocked()) && 
            (noDialogueChoiceHubsShown || inRelaxActionMode) && 
            (!blockTimeSkip || inRelaxActionMode) {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        noDialogueChoiceHubsShown (Expected: true): " + ToString(noDialogueChoiceHubsShown) + ", overridden by inRelaxActionMode: " + ToString(inRelaxActionMode));
        DFLog(this, "        blockTimeSkip (Expected: false): " + ToString(blockTimeSkip) + ", overridden by inRelaxActionMode: " + ToString(inRelaxActionMode));

        return false;
    }

    // TODO - Guard against being in a "Hostile" location.
    public final func IsPlayerInAllowedStateForCrashAnimation() -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();
        
        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).Get(bbDefs.UIInteractions);
        let dialogChoiceHubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(bboard.GetVariant(bbDefs.UIInteractions.DialogChoiceHubs));
        let noDialogueChoiceHubsShown: Bool = ArraySize(dialogChoiceHubs.choiceHubs) == 0;
        let inRelaxActionMode: Bool = this.RelaxActionSystem.GetInRelaxActionMode();
        let isOverdosing: Bool = this.PlayerStateService.GetInOverdose();

        if this.IsPlayerInAllowedStateForAnyAnimation() && (noDialogueChoiceHubsShown || inRelaxActionMode) && !isOverdosing {
            return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        noDialogueChoiceHubsShown (Expected: true): " + ToString(noDialogueChoiceHubsShown) + ", overridden by inRelaxActionMode: " + ToString(inRelaxActionMode));
        DFLog(this, "        isOverdosing (Expected: false): " + ToString(isOverdosing));

        return false;
    }

    //
	//	Animation Toggles and Cooldown Stack
	//
    private final func IsAnimationSubTypeEnabled(type: DFConsumableAnimSubType) -> Bool {
        //DFProfile();
        if Equals(type, DFConsumableAnimSubType.Invalid) {
            return false;

        } else if Equals(type, DFConsumableAnimSubType.EatDrinkThinPackagedLeftHand) {
            if this.Settings.consumableAnimationsEatDrinkThinPackagedLeftHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.EatLookDownRightHand) {
            if this.Settings.consumableAnimationsEatLookDownRightHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.DrinkSipRightHand) {
            if this.Settings.consumableAnimationsDrinkSipRightHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.DrinkChugLeftHand) {
            if this.Settings.consumableAnimationsDrinkChugLeftHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.HealthBooster) {
            if this.Settings.consumableAnimationsTraumaKitEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.Smoking) {
            if this.Settings.consumableAnimationsSmokingEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.Pills) {
            if this.Settings.consumableAnimationsPillEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.Inhaler) {
            if this.Settings.consumableAnimationsInhalerEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFConsumableAnimSubType.MrWhitey) {
            if this.Settings.consumableAnimationsMrWhiteyEnabled {
                return true;
            } else {
                return false;
            }
        }
    }

    private final func IsAnimOnCooldownAndUpdateCooldownStack(newEntry: DFConsumableAnimCooldownEntry) -> Bool {
        //DFProfile();
        if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.Off) {
            // We aren't using the cooldown system.
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFConsumableAnimCooldownExceptionType.Unique) && this.Settings.consumableAnimationsUniqueItemsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a unique item, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFConsumableAnimCooldownExceptionType.Drug) && this.Settings.consumableAnimationsDrugsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a drug, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFConsumableAnimCooldownExceptionType.Pharmaceutical) && this.Settings.consumableAnimationsPharmaceuticalsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a pharmaceutical, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFConsumableAnimCooldownExceptionType.Alcohol) && this.Settings.consumableAnimationsAlcoholIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is an alcoholic drink, which ignores cooldowns. Allowing animation.");
            return false;
        }

        let foundMatchingEntry: Bool = false;
        let matchingEntry: DFConsumableAnimCooldownEntry;
        if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.ByExactVisualProp) {
            for existingEntry in this.cooldownStack {
                if Equals(existingEntry.subType, newEntry.subType) && Equals(existingEntry.id, newEntry.id) {
                    matchingEntry = existingEntry;
                    foundMatchingEntry = true;
                    break;
                }
            }

        } else if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.ByGeneralVisualProp) {
            for existingEntry in this.cooldownStack {
                if Equals(existingEntry.propSubType, newEntry.propSubType) {
                    matchingEntry = existingEntry;
                    foundMatchingEntry = true;
                    break;
                }
            }

        } else if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.ByVisualPropType) {
            for existingEntry in this.cooldownStack {
                if Equals(existingEntry.propType, newEntry.propType) {
                    matchingEntry = existingEntry;
                    foundMatchingEntry = true;
                    break;
                }
            }

        } else if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.ByAnimationType) {
            for existingEntry in this.cooldownStack {
                if Equals(existingEntry.subType, newEntry.subType) {
                    matchingEntry = existingEntry;
                    foundMatchingEntry = true;
                    break;
                }
            }

        } else if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.All) {
            for existingEntry in this.cooldownStack {
                matchingEntry = existingEntry;
                foundMatchingEntry = true;
                break;
            }
        }

        if foundMatchingEntry {
            if newEntry.timestamp - matchingEntry.timestamp >= this.Settings.consumableAnimationCooldownTimeInRealTimeSeconds {
                DFLog(this, "[[[Anim Cooldown]]] A matching cooldown entry was found, but it has expired. Pushing new cooldown entry and allowing animation.");
                ArrayRemove(this.cooldownStack, matchingEntry);
                ArrayPush(this.cooldownStack, newEntry);
                DFLog(this, "[[[Anim Cooldown]]] New cooldown stack: " + ToString(this.cooldownStack));
                return false;
            } else {
                DFLog(this, "[[[Anim Cooldown]]] A matching cooldown entry was found, and this animation is still cooling down. Prohibiting animation.");
                DFLog(this, "[[[Anim Cooldown]]] Cooldown stack: " + ToString(this.cooldownStack));
                return true;
            }
        } else {
            DFLog(this, "[[[Anim Cooldown]]] A matching cooldown entry was not found. Pushing new cooldown entry and allowing animation.");
            ArrayPush(this.cooldownStack, newEntry);
            DFLog(this, "[[[Anim Cooldown]]] New cooldown stack: " + ToString(this.cooldownStack));
            return false;
        }
    }

    //
    //  Animation Choice Prompt
    //
    public final func SetLootingController(controller: ref<LootingController>) -> Void {
        this.lootingController = controller;
    }

    public final func GetNextConsumedItemIsForcedAnimPlayback() -> Bool {
        return this.nextConsumedItemIsForcedAnimPlayback;
    }

    public final func SetNextConsumedItemIsForcedAnimPlayback(force: Bool) -> Void {
        this.nextConsumedItemIsForcedAnimPlayback = force;
    }

    public final func GetNextConsumedItemIsFromLootConsumption() -> Bool {
        return this.nextConsumedItemIsFromLootConsumption;
    }

    public final func SetNextConsumedItemIsFromLootConsumption(wasFromLoot: Bool) -> Void {
        this.nextConsumedItemIsFromLootConsumption = wasFromLoot;
    }

    private final func ConsumeSelectedLootItemAndAnimate() -> Void {
        let inv: InventoryItemData = this.lootingController.DFGetSelectedLootInventoryItemData();
        let gameInstance = GetGameInstance();
        let transactionSystem: ref<TransactionSystem> = GameInstance.GetTransactionSystem(gameInstance);
        let itemQuantity: Int32 = InventoryItemData.GetQuantity(inv);
        let actionName: CName = this.lootingController.DFGetSelectedItemSecondaryActionName();

        transactionSystem.TransferItem(this.lootingController.DFGetOwningLootEntity(), this.player, inv.GameItemData.GetID(), itemQuantity);
        this.ForceInteractionRefresh();

        if Equals(actionName, n"Drink") {
            this.SetNextConsumedItemIsForcedAnimPlayback(true);
            ItemActionsHelper.DrinkItem(this.player, inv.GameItemData.GetID(), true);

        } else if Equals(actionName, n"Eat") {
            this.SetNextConsumedItemIsForcedAnimPlayback(true);
            ItemActionsHelper.EatItem(this.player, inv.GameItemData.GetID(), true);

        } else if Equals(actionName, n"Consume") {
            this.SetNextConsumedItemIsForcedAnimPlayback(true);
            ItemActionsHelper.ConsumeItem(this.player, inv.GameItemData.GetID(), true);
        }
    }

    private final func ForceInteractionRefresh() -> Void {
        if IsDefined(this.lootingController) {
            let event: ref<InteractionActivationEvent> = new InteractionActivationEvent();
            event.eventType = gameinteractionsEInteractionEventType.EIET_activate;
            event.hotspot = this.lootingController.DFGetOwningLootEntity();
            event.activator = this.player;
            event.layerData = InteractionLayerData(n"Loot");

            this.lootingController.DFGetOwningLootEntity().QueueEvent(event);
        }   
    }

    protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        if  Equals(ListenerAction.GetName(action), n"DFAnimatedConsumableManualChoiceAction") &&
            Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_HOLD_COMPLETE) {
                this.OnConsumeActionHeld();
                return true;
        }
        return false;
    }

    public final func OnConsumeActionHeld() -> Void {
        if this.IsPlayerInAllowedStateForConsumableAnimation() {
            if this.lootingController.DFIsAnimatedConsumable() {
                this.ConsumeSelectedLootItemAndAnimate();
            }
        }
    }

    //
    //  Queue Management
    //
    public final func QueueAnimation(anim: DFAnimDatum, opt useIndex: Bool, opt atIndex: Int32) -> Void {
        //DFProfile();

        // Treat these special cases separately so that they don't impact the queue depth
        // and always play last in a specific sequence.
        let shouldProcessQueue: Bool = false;
        let shouldUnqueueWithdrawalAnim: Bool = false;
        let shouldClearOverdoseNotification: Bool = false;
        let invalidAnim: DFAnimDatum;
        let slow: Bool;

        if Equals(anim.type, DFAnimType.Blackout) {
            this.queuedBlackoutAnim = anim;
            shouldProcessQueue = true;
            // Don't play Withdrawal animation with Blackout.
            shouldUnqueueWithdrawalAnim = true;
            shouldClearOverdoseNotification = true;
            this.RelaxActionSystem.ForceStopRelaxActionMode();

        } else if Equals(anim.type, DFAnimType.Crash) {
            this.queuedCrashAnim = anim;
            shouldProcessQueue = true;
            // Don't play Withdrawal animation with Crash.
            shouldUnqueueWithdrawalAnim = true;
            this.RelaxActionSystem.ForceStopRelaxActionMode();

        } else if Equals(anim.type, DFAnimType.Withdrawal) {
            // Don't play Withdrawal animation if Blackout or Crash are already queued.
            // futureAllowedWithdrawalAnims will allow it to be played the next time time is skipped for any reason.
            if Equals(this.queuedBlackoutAnim, invalidAnim) && Equals(this.queuedCrashAnim, invalidAnim) {
                this.queuedWithdrawalAnim = anim;
                shouldProcessQueue = true;
                slow = true; // Use the slow update here to debounce against Blackout and Crash.
                this.RelaxActionSystem.ForceStopRelaxActionMode();
            }
        
        } else {
            // Consumable Anim
            // Try to add the animation to the queue.
            if anim.consumableAnimData.fromRelaxAction {
                ArrayInsert(this.queuedAnims, 0, anim);
                shouldProcessQueue = true;
            
            } else if useIndex && ArraySize(this.queuedAnims) >= (atIndex + 1) {
                this.queuedAnims[atIndex] = anim;
                shouldProcessQueue = true;

            } else if ArraySize(this.queuedAnims) < this.Settings.consumableAnimationQueueDepth {
                ArrayInsert(this.queuedAnims, 0, anim);
                shouldProcessQueue = true;
            }
        }

        if shouldClearOverdoseNotification {
            // This type of notification feels out of place after waking up, so clear it now.
            this.NotificationService.ClearOverdoseNotification();
        }

        if shouldUnqueueWithdrawalAnim {
            this.UnqueuePendingAddictionWithdrawalAnim();
        }

        if shouldProcessQueue {
            this.RegisterProcessAnimQueueCallback(slow);
        }

        DFLog(this, "########## QueueAnimation, Withdrawal?: " + ToString(NotEquals(this.queuedWithdrawalAnim.type, DFAnimType.Invalid)) + 
            ", Blackout?: " + ToString(NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid)) + 
            ", Crash?: " + ToString(NotEquals(this.queuedCrashAnim.type, DFAnimType.Invalid)) + 
            ", queue: " + ToString(this.queuedAnims));
    }

    private final func ClearQueuedAnims(flags: DFClearQueuedAnimFlags) -> Void {
        //DFProfile();
        if flags.clearConsumable {
            ArrayClear(this.queuedAnims);
        }

        let invalidAnim: DFAnimDatum;
        
        if flags.clearBlackout {
            this.queuedBlackoutAnim = invalidAnim;
        }

        if flags.clearWithdrawal {
            this.queuedWithdrawalAnim = invalidAnim;
        }

        if flags.clearCrash {
            this.queuedCrashAnim = invalidAnim;
        }
    }

    public final func OnProcessAnimQueue() -> Void {
        //DFProfile();
		this.ProcessAnimQueue(this.queuedAnims);
	}

    public final func OnAnimFinishedPlaying() -> Void {
        this.currentlyPlayingAnimType = DFAnimType.Invalid;
        DFLog(this, "########## OnAnimFinishedPlaying, Withdrawal?: " + ToString(NotEquals(this.queuedWithdrawalAnim.type, DFAnimType.Invalid)) + ", Blackout?: " + ToString(NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid)) + ", Crash?: " + ToString(NotEquals(this.queuedCrashAnim.type, DFAnimType.Invalid)) + ", queue: " + ToString(this.queuedAnims));
        if ArraySize(this.queuedAnims) > 0 || 
            NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid) || 
            NotEquals(this.queuedWithdrawalAnim.type, DFAnimType.Invalid) ||
            NotEquals(this.queuedCrashAnim.type, DFAnimType.Invalid) {
            this.OnProcessAnimQueue();
        }
    }

    private final func ProcessAnimQueue(animQueue: script_ref<array<DFAnimDatum>>) -> Void {
        //DFProfile();

        this.player.m_pocketRadio.DFSetRestrictionOverride(true);

        // Empty the queue first.
        let animQueueSize: Int32 = ArraySize(Deref(animQueue));
        if animQueueSize > 0 {
            let foundAnim : DFAnimDatum = ArrayPop(Deref(animQueue));
            this.PlayAnim(foundAnim);
            return;
        }

        // Handle special cases.
        if NotEquals(this.queuedBlackoutAnim.type, DFAnimType.Invalid) {
            this.PlayAnim(this.queuedBlackoutAnim);
            let invalidAnim: DFAnimDatum;
            this.queuedBlackoutAnim = invalidAnim;
            return;
        }

        if NotEquals(this.queuedCrashAnim.type, DFAnimType.Invalid) {
            this.PlayAnim(this.queuedCrashAnim);
            let invalidAnim: DFAnimDatum;
            this.queuedCrashAnim = invalidAnim;
            return;
        }

        if NotEquals(this.queuedWithdrawalAnim.type, DFAnimType.Invalid) {
            this.PlayAnim(this.queuedWithdrawalAnim);
            let invalidAnim: DFAnimDatum;
            this.queuedWithdrawalAnim = invalidAnim;
            return;
        }
    }

    private final func PlayAnim(anim: DFAnimDatum) -> Void {
        //DFProfile();
        if Equals(anim.type, DFAnimType.Consumable) {
            DFLog(this, "PlayQueuedConsumableAnim: Selected Type and ID: Type = " + ToString(anim.consumableAnimData.type) + ", ID = " + ToString(anim.consumableAnimData.id));
            // MISMATCH
            // TODO: ??? ^
            this.currentlyPlayingAnimType = DFAnimType.Consumable;
            this.QuestsSystem.SetFact(this.GetQueuedAnimTypeQuestFact(), EnumInt<DFConsumableAnimType>(anim.consumableAnimData.type));
            this.QuestsSystem.SetFact(this.GetPlayQueuedAnimByIDActionQuestFact(), anim.consumableAnimData.id);
        
        } else if Equals(anim.type, DFAnimType.Blackout) {
            this.HandleRadioOnBlackout(false);
            this.currentlyPlayingAnimType = DFAnimType.Blackout;
            this.QuestsSystem.SetFact(this.GetFullBlackoutAnimSubtypeFactAction(), EnumInt<DFBlackoutAnimFullSubtype>(anim.blackoutAnimData.subType));
            this.QuestsSystem.SetFact(this.GetStartBlackoutFactAction(), EnumInt<DFBlackoutAnimType>(anim.blackoutAnimData.type));
        
        } else if Equals(anim.type, DFAnimType.Withdrawal) {
            // Set first time playback and message data, and clear flags that would have allowed this anim to play in the future.
            if Equals(anim.withdrawalAnimData.type, DFAddictionType.Nicotine) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.NicotineAddictionSystem, anim.withdrawalAnimData.severity);
                this.futureAllowedWithdrawalAnims.allowNicotine = false;

            } else if Equals(anim.withdrawalAnimData.type, DFAddictionType.Alcohol) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.AlcoholAddictionSystem, anim.withdrawalAnimData.severity);
                this.futureAllowedWithdrawalAnims.allowAlcohol = false;

            } else if Equals(anim.withdrawalAnimData.type, DFAddictionType.Narcotic) {
                this.SetAddictionSystemWithdrawalAnimationFirstTimePlaybackData(this.NarcoticAddictionSystem, anim.withdrawalAnimData.severity);
                this.futureAllowedWithdrawalAnims.allowNarcotic = false;
            }

            this.currentlyPlayingAnimType = DFAnimType.Withdrawal;
            this.QuestsSystem.SetFact(this.GetAddictionWithdrawalAnimSeverityFact(), EnumInt<DFAddictionWithdrawalAnimSeverity>(anim.withdrawalAnimData.severity));
            this.QuestsSystem.SetFact(this.GetAddictionWithdrawalAnimType(), EnumInt<DFAddictionType>(anim.withdrawalAnimData.type));
            this.QuestsSystem.SetFact(this.GetStartWithdrawalFactAction(), 1);
        
        } else if Equals(anim.type, DFAnimType.Crash) {
            this.currentlyPlayingAnimType = DFAnimType.Crash;
            this.QuestsSystem.SetFact(this.GetCrashAnimSeverityFact(), EnumInt<DFCrashAnimSeverity>(anim.crashAnimData.severity));
            this.QuestsSystem.SetFact(this.GetStartCrashFactAction(), 1);
        }
    }
}


/*
    // q101_sc_06_takemura_grabs
    // q101_sc_07c_v_takes_pills_02
    // q201_sc_08_v_takes_cube
    // q004_sc_02_evelyn_takes_drink
    // q101_sc_07c_v_takes_pills_03
    // g_sc_v_work_grab

    AUDIO
    cmn_generic_work_food_takeout - Good for "eating noodles"
    g_sc_v_work_swallow - Generic food swallow

    cmn_generic_female_drink_swallow

    q000_nomad_sc_05_papers_04 - crinkly paper
    lcm_fs_additional_surface_trash_shuffle
    lcm_fs_additional_decal_trash <----- crinkly wrapper
    lcm_fs_npc_additional_decal_trash
    lcm_fs_additional_surface_trash_walk

    q115_sc_02d_card_grab <---- Small card
    ph_dst_foam_box
    ph_food_box_soft
    ph_medkit_mobile_soft
    q001_sc_01_v_cant_drink <---- canteen / water bottle
    q000_corpo_sc_01_v_male_drinks <----- sip
    q110_sc_02_granny_drinks <----- sip coffee

    # Movement Sounds
    q201_sc_03_v_moves_01
    q105_sc_03a_v_hand_movement
    lcm_mvs_canvas_fast_light
    lcm_mvs_canvas_normal_light
    lcm_mvs_normal_medium <---- used by other base game stuff
    lcm_mvs_slow_light <----- same



    synced claire gives shard c 01 player
    synced q005 06 undercover jackie gives shard to v
    stand 2h on sides__show cyberdeck 01   <---- drink done rh
    synced mq305 v shows card bree hides gun 01 player <---- cig in hand?
    player stand roulette table lean0 2h on table 01 call waiter 01 <--- snap fingers, beckon
    use consumable first 01 <---- shard


    synced_idle_player_holds_gun_on_rinder__01__player <<<< Super nice idle for holding cig
    stand wall lean0 2h on wall 01 turn radio off 01 <<<< leaning against wall, motioning away
    

*/

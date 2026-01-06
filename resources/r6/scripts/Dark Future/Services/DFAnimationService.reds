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
    DFConsumableAnimationCooldownBehavior
}
import DarkFuture.Main.{
    MainSystemItemConsumedEvent,
    DFTimeSkipData
}
import DarkFuture.Services.{
    GameState,
	DFGameStateService
}

// AudioSystem - Don't play item action sounds immediately, instead allow the animation system
// to attempt to play them. If we don't play the animation, the animation system will play
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

private enum DFAnimQuestPhaseGraphDebugMessageID {
    None = 0,
    Start = 1,
    FailedConditionCheck = 2,
    SelectedAnimTypeAndID = 3,
    Done = 4
}

private enum DFAnimType {
    Invalid = 0,
    Drugs = 1,
    DrinkSipRightHand = 2,
    DrinkChugLeftHand = 3,
    EatDrinkThinPackagedLeftHand = 4,
    EatLookDownRightHand = 5
}

private enum DFAnimSubType {
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

private enum DFAnimPropType {
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

private enum DFAnimPropSubType {
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

private enum DFAnimCooldownExceptionType {
    None = 0,
    Unique = 1,
    Drug = 2,
    Alcohol = 3,
    Pharmaceutical = 4
}

private struct DFAnimCooldownEntry {
    public let subType: DFAnimSubType;
    public let propType: DFAnimPropType;
    public let propSubType: DFAnimPropSubType;
    public let cooldownExceptionType: DFAnimCooldownExceptionType;
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
    Immunosuppressant = 14
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

private struct DFConsumableAnimDatum {
    let type: DFAnimType;
    let subType: DFAnimSubType;
    let propType: DFAnimPropType;
    let propSubType: DFAnimPropSubType;
    let cooldownExceptionType: DFAnimCooldownExceptionType;
    let id: Int32;
    let tag: CName;
    let priority: Int32;
    let fallbackFX: DFConsumableAnimFX;
}

public class ProcessAnimQueueDelayCallback extends DFDelayCallback {
	public let AnimationSystem: wref<DFAnimationService>;

	public static func Create(AnimationSystem: wref<DFAnimationService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self: ref<ProcessAnimQueueDelayCallback> = new ProcessAnimQueueDelayCallback();
		self.AnimationSystem = AnimationSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.AnimationSystem.processAnimQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.AnimationSystem.OnProcessAnimQueue();
	}
}

public class ProcessFallbackFXQueueDelayCallback extends DFDelayCallback {
	public let AnimationSystem: wref<DFAnimationService>;

	public static func Create(AnimationSystem: wref<DFAnimationService>) -> ref<DFDelayCallback> {
        //DFProfile();
		let self: ref<ProcessFallbackFXQueueDelayCallback> = new ProcessFallbackFXQueueDelayCallback();
		self.AnimationSystem = AnimationSystem;
		return self;
	}

	public func InvalidateDelayID() -> Void {
        //DFProfile();
		this.AnimationSystem.processFallbackFXQueueDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
        //DFProfile();
		this.AnimationSystem.OnProcessFallbackFX();
	}
}

class DFAnimationSystemEventListener extends DFSystemEventListener {
	private func GetSystemInstance() -> wref<DFAnimationService> {
        //DFProfile();
		return DFAnimationService.Get();
	}

    public cb func OnLoad() {
        //DFProfile();
        super.OnLoad();

		GameInstance.GetCallbackSystem().RegisterCallback(n"DarkFuture.Main.MainSystemItemConsumedEvent", this, n"OnMainSystemItemConsumedEvent", true);
    }

    private cb func OnMainSystemItemConsumedEvent(event: ref<MainSystemItemConsumedEvent>) {
        //DFProfile();
        this.GetSystemInstance().OnItemConsumed(event.GetItemRecord(), event.GetAnimateUI(), event.GetNoAnimation());
    }
}

public final class DFAnimationService extends DFSystem {
    private let QuestsSystem: ref<QuestsSystem>;
    private let GameStateService: ref<DFGameStateService>;
    private let PlayerStateService: ref<DFPlayerStateService>;

    private let consumableAnimData: array<DFConsumableAnimDatum>;
    private let queuedAnim: DFConsumableAnimDatum;
    private let queuedFallbackFX: DFConsumableAnimFX;

    private let factListenerAnimQuestPhaseDebugMessageID: Uint32;

    public let processAnimQueueDelayID: DelayID;
    public let processFallbackFXQueueDelayID: DelayID;
    private let processAnimQueueDelayInterval: Float = 0.01;
    private let processFallbackFXQueueDelayInterval: Float = 0.01;

    private let cooldownStack: array<DFAnimCooldownEntry>;

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
        return this.Settings.consumableAnimationsEnabled;
    }

    private func GetSystemToggleSettingString() -> String {
        //DFProfile();
        return "consumableAnimationsEnabled";
    }

    public func DoPostSuspendActions() -> Void {
        //DFProfile();
        this.ClearAnimQueue();
    }

    public func DoPostResumeActions() -> Void {}

    public func GetSystems() -> Void {
        //DFProfile();
        let gameInstance = GetGameInstance();
        this.QuestsSystem = gameInstance.GetQuestsSystem();
		this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
    }
    private func GetBlackboards(attachedPlayer: ref<PlayerPuppet>) -> Void {}

    public func SetupData() -> Void {
        //DFProfile();
        this.SetupConsumableAnimData();
    }

    private func RegisterListeners() -> Void {
        //DFProfile();
        this.factListenerAnimQuestPhaseDebugMessageID = this.QuestsSystem.RegisterListener(this.GetAnimDebugQuestPhaseGraphMessageIDQuestFact(), this, n"OnAnimDebugMessage");
    }

    private func RegisterAllRequiredDelayCallbacks() -> Void {}
    
    private func UnregisterListeners() -> Void {
        //DFProfile();
        this.QuestsSystem.UnregisterListener(this.GetAnimDebugQuestPhaseGraphMessageIDQuestFact(), this.factListenerAnimQuestPhaseDebugMessageID);
        this.factListenerAnimQuestPhaseDebugMessageID = 0u;
    }

    public func UnregisterAllDelayCallbacks() -> Void {
        //DFProfile();
        this.UnregisterProcessAnimQueueCallback();
        this.UnregisterProcessFallbackFXQueueCallback();
    }

    public func OnTimeSkipStart() -> Void {}
    public func OnTimeSkipCancelled() -> Void {}
    public func OnTimeSkipFinished(data: DFTimeSkipData) -> Void {}

    public func OnSettingChangedSpecific(changedSettings: array<String>) -> Void {
        //DFProfile();
        if ArrayContains(changedSettings, "consumableAnimationsEnabled") || ArrayContains(changedSettings, "consumableAnimationCooldownTimeInRealTimeSeconds") || ArrayContains(changedSettings, "consumableAnimationCooldownBehavior") {
            // Clear the cooldown stack.
            ArrayClear(this.cooldownStack);
        }
    }

    public func InitSpecific(attachedPlayer: ref<PlayerPuppet>) -> Void {
        //DFProfile();
        this.ClearAnimQueue();
    }

    //
	//	RunGuard Protected Methods
	//
    public func OnItemConsumed(itemRecord: wref<Item_Record>, animateUI: Bool, noAnimation: Bool) -> Void {
        //DFProfile();
        DFLog(this, "OnItemConsumed");

        // Find the animation to queue.
        let anim: DFConsumableAnimDatum;
        for tag in itemRecord.Tags() {
            anim = this.FindAnimByTag(tag);
            if NotEquals(anim.type, DFAnimType.Invalid) {
                break;
            }
        }

        if DFRunGuard(this) { 
            DFLog(this, "    RETURNING: RunGuard");
            this.QueueFallbackFX(anim.fallbackFX);
            return; 
        }

        if !this.GameStateService.IsValidGameState(this) { 
            DFLog(this, "    RETURNING: GameState");
            this.QueueFallbackFX(anim.fallbackFX);
            return; 
        }

        if noAnimation {
            DFLog(this, "    RETURNING: noAnimation");
            this.QueueFallbackFX(anim.fallbackFX);
            return;
        }

        if !this.IsPlayerInAllowedStateForConsumableAnimation() { 
            DFLog(this, "    RETURNING: AllowedState");
            this.QueueFallbackFX(anim.fallbackFX);
            return;
        }

        if !this.IsAnimationSubTypeEnabled(anim.subType) {
            DFLog(this, "    RETURNING: Animation Type Not Enabled");
            this.QueueFallbackFX(anim.fallbackFX);
            return;
        }

        let newCooldownEntry: DFAnimCooldownEntry = DFAnimCooldownEntry(anim.subType, anim.propType, anim.propSubType, anim.cooldownExceptionType, anim.id, GameInstance.GetSimTime(GetGameInstance()).ToFloat());
        if this.IsAnimOnCooldownAndUpdateCooldownStack(newCooldownEntry) {
            DFLog(this, "    RETURNING: On Cooldown");
            this.QueueFallbackFX(anim.fallbackFX, this.queuedAnim);
            return;
        }
    
        if NotEquals(this.queuedAnim.priority, this.GetInvalidAnimPriority()) {
            if this.queuedAnim.priority < anim.priority {
                // Queued animation's priority was higher. Play this anim's fallback FX.
                this.QueueFallbackFX(anim.fallbackFX, this.queuedAnim);

            } else if this.queuedAnim.priority == anim.priority {
                // Queued animation's priority was the same. Choose one at random.
                if IsCoinFlipSuccessful() {
                    // We chose the new animation. Play the old queued animation's fallback FX.
                    this.QueueFallbackFX(this.queuedAnim.fallbackFX, anim);
                    this.queuedAnim = anim;
                    this.RegisterProcessAnimQueueCallback();

                } else {
                    // We chose the old animation. Play the new animation's fallback FX.
                    this.QueueFallbackFX(anim.fallbackFX, this.queuedAnim);
                }
            } else {
                // Queued animation's priority was less. Queue the new animation. Play the old queued animation's fallback FX.
                this.QueueFallbackFX(this.queuedAnim.fallbackFX, anim);
                this.queuedAnim = anim;
                this.RegisterProcessAnimQueueCallback();
            }
        } else {
            // The queued anim is in an initial, invalid state (is null). Queue this new animation.
            this.queuedAnim = anim;
            this.RegisterProcessAnimQueueCallback();
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
                DFLog(this, "[[[[[[Quest Phase]]]]]] Selected Type and ID: Type = " + ToString(IntEnum<DFAnimType>(this.QuestsSystem.GetFact(this.GetQueuedAnimTypeQuestFact()))) + ", ID = " + ToString(this.QuestsSystem.GetFact(this.GetPlayQueuedAnimByIDActionQuestFact())));
                break;
            default:
                break;
        }
    }

    private final func SetupConsumableAnimData() -> Void {
        //DFProfile();
        let fallbackMethFX: DFConsumableAnimFX;
        fallbackMethFX.vfx = n"reflex_buster";

        let fallbackGlitterFX: DFConsumableAnimFX;
        fallbackGlitterFX.vfx = n"reflex_buster";
        fallbackGlitterFX.statusEffect = t"DarkFutureStatusEffect.GlitterSlowTime";

        let fallbackHealFX: DFConsumableAnimFX;
        fallbackHealFX.vfx = n"splinter_buff";

        let fallbackDrinkFX: DFConsumableAnimFX;
        fallbackDrinkFX.audio = n"ui_loot_drink";

        let fallbackEatFX: DFConsumableAnimFX;
        fallbackEatFX.audio = n"ui_loot_eat";

        let fallbackGenericFX: DFConsumableAnimFX;
        fallbackGenericFX.audio = n"ui_menu_item_consumable_generic";

        // P0 (Unique)
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Pizza, DFAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.PizzaUnique), n"DarkFutureAnimFoodPizzaUnique", 0, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.SodaCanChug, DFAnimPropSubType.ChromanticoreChug, DFAnimCooldownExceptionType.Unique, EnumInt(DFDrinkChugLeftHandAnimID.ChromanticoreChug), n"DarkFutureAnimDrinkChromanticoreChugUnique", 0, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Sandwich, DFAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.SandwichUnique), n"DarkFutureAnimFoodSandwichUnique", 0, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.CoffeeTeaToGo, DFAnimPropSubType.CoffeeTeaToGo, DFAnimCooldownExceptionType.Unique, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaToGo), n"DarkFutureAnimCoffeeTeaToGoUnique", 0, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Pierogi, DFAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.PierogiUnique), n"DarkFutureAnimFoodPierogiUnique", 0, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Cupcake, DFAnimCooldownExceptionType.Unique, EnumInt(DFEatLookDownRightHandAnimID.CupcakeUnique), n"DarkFutureAnimFoodCupcakeUnique", 0, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.CoffeeTeaOpenCup, DFAnimPropSubType.CoffeeTeaOpenCup, DFAnimCooldownExceptionType.Unique, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaOpenCup), n"DarkFutureAnimCoffeeTeaOpenCupUnique", 0, fallbackDrinkFX)); // TODOFUTURE - Visual error
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.CentzonIndigoUnique, DFAnimCooldownExceptionType.Unique, EnumInt(DFDrinkChugLeftHandAnimID.CentzonIndigoUnique), n"DarkFutureAnimAlcoholCentzonUnique", 0, fallbackDrinkFX));
        
        // P10
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.CatFood, DFAnimPropSubType.CatFood, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.CatFood), n"DarkFutureAnimFoodCatFood", 10, fallbackEatFX));

        // P20
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Inhaler, DFAnimPropType.DrugInhaler, DFAnimPropSubType.Glitter, DFAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.Glitter), n"DarkFutureAnimInhalerGlitter", 20, fallbackGlitterFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Inhaler, DFAnimPropType.DrugInhaler, DFAnimPropSubType.BlackLace, DFAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.BlackLace), n"DarkFutureAnimInhalerBlackLace", 20, fallbackMethFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.MrWhitey, DFAnimPropType.MrWhitey, DFAnimPropSubType.MrWhitey, DFAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.MrWhitey), n"DarkFutureAnimNarcoticsMrWhitey", 20, fallbackMethFX));

        // P30
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Smoking, DFAnimPropType.Smoking, DFAnimPropSubType.Smoking, DFAnimCooldownExceptionType.Drug, EnumInt(DFDrugsAnimID.Smoking), n"DarkFutureAnimSmoking", 30, fallbackGenericFX));

        // P40
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_B, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Red), n"DarkFutureAnimPillBRed", 40, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_B, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Green), n"DarkFutureAnimPillBGreen", 40, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_B, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_B_Pink), n"DarkFutureAnimPillBPink", 40, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.SodaCanChug, DFAnimPropSubType.ChromanticoreChug, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkChugLeftHandAnimID.ChromanticoreChug), n"DarkFutureAnimDrinkChromanticoreChug", 40, fallbackDrinkFX));

        // P50
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Inhaler, DFAnimPropType.PharmaceuticalInhaler, DFAnimPropSubType.Immunosuppressant, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Immunosuppressant), n"DarkFutureAnimInhalerImmunosuppressant", 50, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Inhaler, DFAnimPropType.PharmaceuticalInhaler, DFAnimPropSubType.Addiquit, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Addiquit), n"DarkFutureAnimInhalerAddiquit", 50, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Inhaler, DFAnimPropType.PharmaceuticalInhaler, DFAnimPropSubType.EmergencyCardioregulator, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.EmergencyCardioregulator), n"DarkFutureAnimInhalerEmergencyCardioregulator", 50, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.PharmaceuticalLarge, DFAnimPropSubType.Jellytricity, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFEatLookDownRightHandAnimID.Jellytricity), n"DarkFutureAnimDrugJellytricity", 50, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.PharmaceuticalThinPackaged, DFAnimPropSubType.RAMNugs, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.RAMNugs), n"DarkFutureAnimDrugRAMNugs", 50, fallbackHealFX));

        // P60
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.HealthBooster, DFAnimPropType.HealthBooster, DFAnimPropSubType.HealthBooster, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.HealthBooster), n"DarkFutureAnimHealthBooster", 60, fallbackHealFX));

        // P70
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_A, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Blue), n"DarkFutureAnimPillABlue", 70, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_A, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Green), n"DarkFutureAnimPillAGreen", 70, fallbackHealFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.Drugs, DFAnimSubType.Pills, DFAnimPropType.Pill, DFAnimPropSubType.Pill_A, DFAnimCooldownExceptionType.Pharmaceutical, EnumInt(DFDrugsAnimID.Pill_A_Pink), n"DarkFutureAnimPillAPink", 70, fallbackHealFX));

        // P80
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.PingoPalido, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.PingoPalido), n"DarkFutureAnimAlcoholPingoPalido", 80, fallbackDrinkFX));
        
        // P90
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.Cocktail, DFAnimPropSubType.Cocktail, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.Cocktail), n"DarkFutureAnimAlcoholCocktail", 90, fallbackDrinkFX));

        // P100
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Centzon, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Centzon), n"DarkFutureAnimAlcoholCentzon", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Donaghys, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Donaghys), n"DarkFutureAnimAlcoholDonaghys", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Bolshevik, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Bolshevik), n"DarkFutureAnimAlcoholBolshevik", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.TequilaEspecial, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TequilaEspecial), n"DarkFutureAnimAlcoholTequilaEspecial", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.BlueGrass, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.BlueGrass), n"DarkFutureAnimAlcoholBlueGrass", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Wine, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Wine), n"DarkFutureAnimAlcoholWine", 100, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Champaradise, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Champaradise), n"DarkFutureAnimAlcoholChamparadise", 100, fallbackDrinkFX));

        // P110
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.CalaveraFeliz, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.CalaveraFeliz), n"DarkFutureAnimAlcoholCalaveraFeliz", 110, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.JoeTiel, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.JoeTiel), n"DarkFutureAnimAlcoholJoeTiel", 110, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Bumelant, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Bumelant), n"DarkFutureAnimAlcoholBumelant", 110, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.Odickin, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.Odickin), n"DarkFutureAnimAlcoholOdickin", 110, fallbackDrinkFX));

        // P120
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.CentzonInverted, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.CentzonInverted), n"DarkFutureAnimAlcoholCentzonInverted", 120, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.JoeTielInverted, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.JoeTielInverted), n"DarkFutureAnimAlcoholJoeTielInverted", 120, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.OdickinInverted, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.OdickinInverted), n"DarkFutureAnimAlcoholOdickinInverted", 120, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.TequilaEspecialInverted, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TequilaEspecialInverted), n"DarkFutureAnimAlcoholTequilaEspecialInverted", 120, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.GenericHooch, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.GenericHooch), n"DarkFutureAnimAlcoholGenericHooch", 120, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.ChamparadiseInverted, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.ChamparadiseInverted), n"DarkFutureAnimAlcoholChamparadiseInverted", 120, fallbackDrinkFX));
        
        // P130
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.AbydosLarge, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.AbydosLarge), n"DarkFutureAnimAlcoholAbydosLarge", 130, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.LargeBottle, DFAnimPropSubType.TwentyFirstStout, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkChugLeftHandAnimID.TwentyFirstStout), n"DarkFutureAnimAlcoholTwentyFirstStout", 130, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SmallBottle, DFAnimPropSubType.BrosephBottle, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBrown), n"DarkFutureAnimAlcoholBrosephBrown", 130, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SmallBottle, DFAnimPropSubType.BrosephBottle, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBlue), n"DarkFutureAnimAlcoholBrosephBlue", 130, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SmallBottle, DFAnimPropSubType.BrosephBottle, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.BrosephBrownInverted), n"DarkFutureAnimAlcoholBrosephBrownInverted", 130, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SmallBottle, DFAnimPropSubType.AbydosSmall, DFAnimCooldownExceptionType.Alcohol, EnumInt(DFDrinkSipRightHandAnimID.AbydosSmall), n"DarkFutureAnimAlcoholAbydosSmall", 130, fallbackDrinkFX)); // TODOFUTURE - Visual error

        // P140
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkChugLeftHand, DFAnimSubType.DrinkChugLeftHand, DFAnimPropType.WaterBottle, DFAnimPropSubType.SainRuisseau, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkChugLeftHandAnimID.SainRuisseau), n"DarkFutureAnimDrinkSainRuisseau", 140, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.WaterBottle, DFAnimPropSubType.Vatnajokull, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Vatnajokull), n"DarkFutureAnimDrinkVatnajokull", 140, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.CoffeeTeaOpenCup, DFAnimPropSubType.CoffeeTeaOpenCup, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaOpenCup), n"DarkFutureAnimCoffeeTeaOpenCup", 140, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.CoffeeTeaToGo, DFAnimPropSubType.CoffeeTeaToGo, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CoffeeTeaToGo), n"DarkFutureAnimCoffeeTeaToGo", 140, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.WaterBottle, DFAnimPropSubType.WaterBottle, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.WaterBottle), n"DarkFutureAnimDrinkWaterBottle", 140, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.LargePackagedGenericGold, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.LargePackagedGenericGold), n"DarkFutureAnimFoodLargePackagedGenericGold", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.LargePackagedGenericSilver, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.LargePackagedGenericSilver), n"DarkFutureAnimFoodLargePackagedGenericSilver", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.MeatLog, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.MeatLog), n"DarkFutureAnimFoodMeatLog", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Nigiri, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Nigiri), n"DarkFutureAnimFoodNigiri", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Norimaki, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Norimaki), n"DarkFutureAnimFoodNorimaki", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.DriedMeat, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.DriedMeat), n"DarkFutureAnimFoodDriedMeat", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Wontons, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Wontons), n"DarkFutureAnimFoodWontons", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Ramen, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Ramen), n"DarkFutureAnimFoodRamen", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.SoupLight, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.SoupLight), n"DarkFutureAnimFoodSoupLight", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.SoupDark, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.SoupDark), n"DarkFutureAnimFoodSoupDark", 140, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedDrink, DFAnimPropSubType.DaringDairy, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.DaringDairy), n"DarkFutureAnimDrinkDaringDairy", 140, fallbackEatFX));

        // P150
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Taco, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Taco), n"DarkFutureAnimFoodTaco", 150, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.HotDog, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.HotDog), n"DarkFutureAnimFoodHotDog", 150, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Fruit, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Fruit), n"DarkFutureAnimFoodFruit", 150, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.BeefCan, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.BeefCan), n"DarkFutureAnimFoodBeefCan", 150, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatLookDownRightHand, DFAnimSubType.EatLookDownRightHand, DFAnimPropType.LargeFood, DFAnimPropSubType.Pizza, DFAnimCooldownExceptionType.None, EnumInt(DFEatLookDownRightHandAnimID.Pizza), n"DarkFutureAnimFoodPizza", 150, fallbackEatFX));

        // P160
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.Chromanticore, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Chromanticore), n"DarkFutureAnimDrinkChromanticore", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.Nicola, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Nicola_A), n"DarkFutureAnimDrinkNicolaA", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.Nicola, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Nicola_B), n"DarkFutureAnimDrinkNicolaB", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.CirrusCola, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CirrusCola_A), n"DarkFutureAnimDrinkCirrusColaA", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.CirrusCola, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.CirrusCola_B), n"DarkFutureAnimDrinkCirrusColaB", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.Tiancha, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.Tiancha), n"DarkFutureAnimDrinkTiancha", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.DrinkSipRightHand, DFAnimSubType.DrinkSipRightHand, DFAnimPropType.SodaCan, DFAnimPropSubType.SpunkyMonkey, DFAnimCooldownExceptionType.None, EnumInt(DFDrinkSipRightHandAnimID.SpunkyMonkey), n"DarkFutureAnimDrinkSpunkyMonkey", 160, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.Burrito, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_A), n"DarkFutureAnimFoodBurritoA", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.Burrito, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_B), n"DarkFutureAnimFoodBurritoB", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.Burrito, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Burrito_C), n"DarkFutureAnimFoodBurritoC", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.Holobites, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Holobites), n"DarkFutureAnimFoodHolobites", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.Moonchies, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.Moonchies), n"DarkFutureAnimFoodMoonchies", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.LeelouBeans, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.LeelouBeans), n"DarkFutureAnimFoodLeelouBeans", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.PopTurd, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.PopTurd), n"DarkFutureAnimFoodPopTurd", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.ShwabShwab, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ShwabShwab), n"DarkFutureAnimFoodShwabShwab", 160, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.SynthSnack, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.SynthSnack), n"DarkFutureAnimFoodSynthSnack", 160, fallbackEatFX));
        
        // P900
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedDrink, DFAnimPropSubType.LeelouBeansInverted, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.LeelouBeansInverted), n"DarkFutureAnimDrinkLeelouBeansInverted", 900, fallbackDrinkFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.ThinPackagedGeneric, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ThinPackagedGeneric), n"DarkFutureAnimFoodThinPackagedGeneric", 900, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.ThinPackagedGenericLarge, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.ThinPackagedGenericLarge), n"DarkFutureAnimFoodThinPackagedGenericLarge", 900, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.SynthSnackNoLabel, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.SynthSnackNoLabel), n"DarkFutureAnimFoodSynthSnackNoLabel", 900, fallbackEatFX));
        ArrayPush(this.consumableAnimData, DFConsumableAnimDatum(DFAnimType.EatDrinkThinPackagedLeftHand, DFAnimSubType.EatDrinkThinPackagedLeftHand, DFAnimPropType.ThinPackagedFood, DFAnimPropSubType.CandyBar, DFAnimCooldownExceptionType.None, EnumInt(DFEatDrinkThinPackagedLeftHandAnimID.CandyBar), n"DarkFutureAnimFoodCandyBar", 900, fallbackEatFX));
    }

    private final func FindAnimByTag(tag: CName) -> DFConsumableAnimDatum {
        //DFProfile();
        for datum in this.consumableAnimData {
            if Equals(datum.tag, tag) {
                DFLog(this, "FindAnimByTag returning " + ToString(datum));
                return datum;
            }
        }
        return this.GetInvalidDFConsumableAnimDatum();
    }

    private final func IsAnimPlaying() -> Bool {
        //DFProfile();
        return this.QuestsSystem.GetFact(this.GetPlayQueuedAnimByIDActionQuestFact()) > 0 ? true : false;
    }

    private final func PlayQueuedAnim() -> Void {
        //DFProfile();
        DFLog(this, "PlayQueuedAnim: Selected Type and ID: Type = " + ToString(this.queuedAnim.type) + ", ID = " + ToString(this.queuedAnim.id));
        // MISMATCH
        this.QuestsSystem.SetFact(this.GetQueuedAnimTypeQuestFact(), EnumInt<DFAnimType>(this.queuedAnim.type));
        this.QuestsSystem.SetFact(this.GetPlayQueuedAnimByIDActionQuestFact(), this.queuedAnim.id);
    }

    private final func ClearAnimQueue() -> Void {
        //DFProfile();
        this.queuedAnim = this.GetInvalidDFConsumableAnimDatum();
    }

    private final func ClearFallbackFXQueue() -> Void {
        //DFProfile();
        this.queuedFallbackFX = this.GetInvalidDFConsumableAnimFX();
    }

    private final func GetInvalidAnimPriority() -> Int32 {
        //DFProfile();
        return 9999;
    }

    private final func GetInvalidDFConsumableAnimDatum() -> DFConsumableAnimDatum {
        //DFProfile();
        let invalidFX: DFConsumableAnimFX;
        return DFConsumableAnimDatum(DFAnimType.Invalid, DFAnimSubType.Invalid, DFAnimPropType.Invalid, DFAnimPropSubType.Invalid, DFAnimCooldownExceptionType.None, 0, n"", this.GetInvalidAnimPriority(), invalidFX);
    }

    private final func GetInvalidDFConsumableAnimFX() -> DFConsumableAnimFX {
        //DFProfile();
        let invalidFX: DFConsumableAnimFX;
        return invalidFX;
    }

    public final func OnProcessAnimQueue() -> Void {
        //DFProfile();
		if NotEquals(this.queuedAnim.type, DFAnimType.Invalid) {
			this.ProcessAnimQueue();
		}
	}

    public final func OnProcessFallbackFX() -> Void {
        //DFProfile();
        this.ProcessFallbackFXQueue();
    }

    private final func ProcessAnimQueue() -> Void {
        //DFProfile();
        this.PlayQueuedAnim();
        this.ClearAnimQueue();
    }

    private final func ProcessFallbackFXQueue() -> Void {
        //DFProfile();
        this.TryToPlayFallbackFX();
        this.ClearFallbackFXQueue();
    }

    private final func QueueFallbackFX(fx: DFConsumableAnimFX, opt queuedAnim: DFConsumableAnimDatum) -> Void {
        //DFProfile();
        if Equals(queuedAnim.fallbackFX, fx) {
            // Avoid playing fallback effects for repeated use of the same consumable.
            return;
        }

        this.queuedFallbackFX = fx;
        this.RegisterProcessFallbackFXQueueCallback();
    }

    public final func TryToPlayFallbackFX() -> Void {
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
    private final func RegisterProcessAnimQueueCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessAnimQueueDelayCallback.Create(this), this.processAnimQueueDelayID, this.processAnimQueueDelayInterval);
	}

    private final func RegisterProcessFallbackFXQueueCallback() -> Void {
        //DFProfile();
		RegisterDFDelayCallback(this.DelaySystem, ProcessFallbackFXQueueDelayCallback.Create(this), this.processFallbackFXQueueDelayID, this.processFallbackFXQueueDelayInterval);
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

    public final func IsPlayerInAllowedStateForConsumableAnimation() -> Bool {
        //DFProfile();
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();

        let validGameState: Bool = this.GameStateService.IsValidGameState(this);
        let animPlaying: Bool = this.IsAnimPlaying();

        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).GetLocalInstanced(this.player.GetEntityID(), bbDefs.PlayerStateMachine);
        let upperBodyState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.UpperBody);
        let inLoreAnimationScene: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsInLoreAnimationScene);
        let isMoving: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingHorizontally) || bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingVertically);
        let isCarryingBody: Bool = bboard.GetInt(bbDefs.PlayerStateMachine.BodyCarrying) > 0;
        let isControllingDevice: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingDevice);
        let isControllingCamera: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingCamera);
        let isForceOpeningDoor: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsForceOpeningDoor);

        let locomotionState: gamePSMDetailedLocomotionStates = IntEnum<gamePSMDetailedLocomotionStates>(bboard.GetInt(bbDefs.PlayerStateMachine.LocomotionDetailed));
        let isLocomotionStateAllowed: Bool = Equals(locomotionState, gamePSMDetailedLocomotionStates.Stand) || Equals(locomotionState, gamePSMDetailedLocomotionStates.Crouch);
        
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

        if validGameState &&
            !animPlaying &&
            !isInCombat && 
            !isReplacer && 
            !inLoreAnimationScene &&
            !isMoving &&
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

        return false;
    }

    public final func IsPlayerInAllowedStateForAddictionWithdrawalAnimation() -> Bool {
        //DFProfile();
        DFLog(this, "IsPlayerInAllowedStateForAddictionWithdrawalAnimation");
        let gameInstance = GetGameInstance();
        let bbDefs: ref<AllBlackboardDefinitions> = GetAllBlackboardDefs();

        let bboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gameInstance).GetLocalInstanced(this.player.GetEntityID(), bbDefs.PlayerStateMachine);
        let upperBodyState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.UpperBody);
        let inLoreAnimationScene: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsInLoreAnimationScene);
        let isMoving: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingHorizontally) || bboard.GetBool(bbDefs.PlayerStateMachine.IsMovingVertically);
        let isCarryingBody: Bool = bboard.GetInt(bbDefs.PlayerStateMachine.BodyCarrying) > 0;
        let isControllingDevice: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingDevice);
        let isControllingCamera: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsControllingCamera);
        let isForceOpeningDoor: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsForceOpeningDoor);

        let locomotionState: gamePSMDetailedLocomotionStates = IntEnum<gamePSMDetailedLocomotionStates>(bboard.GetInt(bbDefs.PlayerStateMachine.LocomotionDetailed));
        let isLocomotionStateAllowed: Bool = Equals(locomotionState, gamePSMDetailedLocomotionStates.Stand) || Equals(locomotionState, gamePSMDetailedLocomotionStates.Crouch);
        
        let combatGadgetState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.CombatGadget);
        let leftHandCyberwareState: Int32 = bboard.GetInt(bbDefs.PlayerStateMachine.LeftHandCyberware);
        
        let isPlayerInsideElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideElevator);
        let isPlayerInsideMovingElevator: Bool = bboard.GetBool(bbDefs.PlayerStateMachine.IsPlayerInsideMovingElevator);
        isPlayerInsideElevator = isPlayerInsideElevator || isPlayerInsideMovingElevator;
        
        let uploadingQuickHackIDs: array<TweakDBID> = FromVariant<array<TweakDBID>>(bboard.GetVariant(bbDefs.PlayerStateMachine.UploadingQuickHackIDs));
        let isUploadingQuickhacks: Bool = ArraySize(uploadingQuickHackIDs) > 0;
        
        bboard = GameInstance.GetBlackboardSystem(gameInstance).Get(bbDefs.UIInteractions);
        let dialogChoiceHubs: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(bboard.GetVariant(bbDefs.UIInteractions.DialogChoiceHubs));
        let noDialogueChoiceHubsShown: Bool = ArraySize(dialogChoiceHubs.choiceHubs) == 0;

        let isInCombat: Bool = this.player.IsInCombat();
        let isReplacer: Bool = this.player.IsReplacer();
        let isSwimming: Bool = PlayerPuppet.IsSwimming(this.player);
        let isMountedToVehicle: Bool = VehicleComponent.IsMountedToVehicle(gameInstance, this.player);
        let isPlayerInWorkspot: Bool = GameInstance.GetWorkspotSystem(gameInstance).IsActorInWorkspot(this.player);
        let isPhoneCallActive: Bool = GameInstance.GetPhoneManager(gameInstance).IsPhoneCallActive();
        let isPlayerPursuedByNCPD: Bool = this.player.GetPreventionSystem().IsChasingPlayer();

        if !isInCombat && 
            !isReplacer && 
            !inLoreAnimationScene &&
            !isMoving &&
            !isCarryingBody &&
            !isControllingDevice &&
            !isControllingCamera &&
            !isForceOpeningDoor &&
            !isSwimming && 
            !isMountedToVehicle && 
            !isPlayerInWorkspot && 
            upperBodyState != 4 && 
            isLocomotionStateAllowed && 
            combatGadgetState == 0 && 
            leftHandCyberwareState == 0 && 
            !isPhoneCallActive &&
            !isPlayerInsideElevator && 
            !isUploadingQuickhacks && 
            noDialogueChoiceHubsShown && 
            !isPlayerPursuedByNCPD {
                return true;
        }

        DFLog(this, "    Returning false. State: ");
        DFLog(this, "        isInCombat (Expected: false): " + ToString(isInCombat));
        DFLog(this, "        isReplacer (Expected: false): " + ToString(isReplacer));
        DFLog(this, "        inLoreAnimationScene (Expected: false): " + ToString(inLoreAnimationScene));
        DFLog(this, "        isMoving (Expected: false): " + ToString(isMoving));
        DFLog(this, "        isCarryingBody (Expected: false): " + ToString(isCarryingBody));
        DFLog(this, "        isControllingDevice (Expected: false): " + ToString(isControllingDevice));
        DFLog(this, "        isControllingCamera (Expected: false): " + ToString(isControllingCamera));
        DFLog(this, "        isForceOpeningDoor (Expected: false): " + ToString(isForceOpeningDoor));
        DFLog(this, "        isSwimming (Expected: false): " + ToString(isSwimming));
        DFLog(this, "        isMountedToVehicle (Expected: false): " + ToString(isMountedToVehicle));
        DFLog(this, "        isPlayerInWorkspot (Expected: false): " + ToString(isPlayerInWorkspot));
        DFLog(this, "        upperBodyState (Expected: != 4): " + ToString(upperBodyState));
        DFLog(this, "        isLocomotionStateAllowed (Expected: true): " + ToString(isLocomotionStateAllowed));
        DFLog(this, "        combatGadgetState (Expected: 0): " + ToString(combatGadgetState));
        DFLog(this, "        leftHandCyberwareState (Expected: 0): " + ToString(leftHandCyberwareState));
        DFLog(this, "        isPhoneCallActive (Expected: false): " + ToString(isPhoneCallActive));
        DFLog(this, "        isPlayerInsideElevator (Expected: false): " + ToString(isPlayerInsideElevator));
        DFLog(this, "        isUploadingQuickhacks (Expected: false): " + ToString(isUploadingQuickhacks));
        DFLog(this, "        noDialogueChoiceHubsShown (Expected: true): " + ToString(noDialogueChoiceHubsShown));
        DFLog(this, "        isPlayerPursuedByNCPD (Expected: false): " + ToString(isPlayerPursuedByNCPD));

        return false;
    }

    //
	//	Animation Toggles and Cooldown Stack
	//
    private final func IsAnimationSubTypeEnabled(type: DFAnimSubType) -> Bool {
        //DFProfile();
        if Equals(type, DFAnimSubType.Invalid) {
            return false;

        } else if Equals(type, DFAnimSubType.EatDrinkThinPackagedLeftHand) {
            if this.Settings.consumableAnimationsEatDrinkThinPackagedLeftHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.EatLookDownRightHand) {
            if this.Settings.consumableAnimationsEatLookDownRightHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.DrinkSipRightHand) {
            if this.Settings.consumableAnimationsDrinkSipRightHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.DrinkChugLeftHand) {
            if this.Settings.consumableAnimationsDrinkChugLeftHandEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.HealthBooster) {
            if this.Settings.consumableAnimationsTraumaKitEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.Smoking) {
            if this.Settings.consumableAnimationsSmokingEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.Pills) {
            if this.Settings.consumableAnimationsPillEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.Inhaler) {
            if this.Settings.consumableAnimationsInhalerEnabled {
                return true;
            } else {
                return false;
            }
        } else if Equals(type, DFAnimSubType.MrWhitey) {
            if this.Settings.consumableAnimationsMrWhiteyEnabled {
                return true;
            } else {
                return false;
            }
        }
    }

    private final func IsAnimOnCooldownAndUpdateCooldownStack(newEntry: DFAnimCooldownEntry) -> Bool {
        //DFProfile();
        if Equals(this.Settings.consumableAnimationCooldownBehavior, DFConsumableAnimationCooldownBehavior.Off) {
            // We aren't using the cooldown system.
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFAnimCooldownExceptionType.Unique) && this.Settings.consumableAnimationsUniqueItemsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a unique item, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFAnimCooldownExceptionType.Drug) && this.Settings.consumableAnimationsDrugsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a drug, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFAnimCooldownExceptionType.Pharmaceutical) && this.Settings.consumableAnimationsPharmaceuticalsIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is a pharmaceutical, which ignores cooldowns. Allowing animation.");
            return false;
        }

        if Equals(newEntry.cooldownExceptionType, DFAnimCooldownExceptionType.Alcohol) && this.Settings.consumableAnimationsAlcoholIgnoreCooldown {
            DFLog(this, "[[[Anim Cooldown]]] This is an alcoholic drink, which ignores cooldowns. Allowing animation.");
            return false;
        }

        let foundMatchingEntry: Bool = false;
        let matchingEntry: DFAnimCooldownEntry;
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
*/
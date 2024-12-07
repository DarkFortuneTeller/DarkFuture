// -----------------------------------------------------------------------------
// DFSettings
// -----------------------------------------------------------------------------
//
// - Mod Settings configuration.
//

module DarkFuture.Settings

import DarkFuture.Logging.*
import DarkFuture.Utils.DFBarColorThemeName
import DarkFuture.Gameplay.{
	EnhancedVehicleSystemCompatPowerBehaviorDriver,
	EnhancedVehicleSystemCompatPowerBehaviorPassenger
}

enum DFReducedCarryWeightAmount {
	Full = 0,
	Half = 1,
	Off = 2
}

public enum DFRoadDetectionToleranceSetting {
	Curb = 0,
	Roadside = 1,
	Secluded = 2
}

public enum DFSleepQualitySetting {
	Limited = 0,
	Full = 1
}

//	ModSettings - Register if Mod Settings installed
//
@if(ModuleExists("ModSettingsModule")) 
public func RegisterDFSettingsListener(listener: ref<IScriptable>) {
	ModSettings.RegisterListenerToClass(listener);
  	ModSettings.RegisterListenerToModifications(listener);
}

@if(ModuleExists("ModSettingsModule")) 
public func UnregisterDFSettingsListener(listener: ref<IScriptable>) {
	ModSettings.UnregisterListenerToClass(listener);
  	ModSettings.UnregisterListenerToModifications(listener);
}

//	ModSettings - No-op if Mod Settings not installed
//
@if(!ModuleExists("ModSettingsModule")) 
public func RegisterDFSettingsListener(listener: ref<IScriptable>) {
	//FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener registration aborted.");
}
@if(!ModuleExists("ModSettingsModule")) 
public func UnregisterDFSettingsListener(listener: ref<IScriptable>) {
	//FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener unregistration aborted.");
}

public class SettingChangedEvent extends CallbackSystemEvent {
	let changedSettings: array<String>;

	public final func GetData() -> array<String> {
		return this.changedSettings;
	}

    static func Create(data: array<String>) -> ref<SettingChangedEvent> {
		let self: ref<SettingChangedEvent> = new SettingChangedEvent();
		self.changedSettings = data;
        return self;
    }
}

//
//	Dark Future Settings
//
public class DFSettings extends ScriptableSystem {
	private let debugEnabled: Bool = false;

	private func OnAttach() {
		GameInstance.GetCallbackSystem().RegisterCallback(n"Session/Start", this, n"OnSessionStart");
	}

	public final func OnSessionStart(evt: ref<GameSessionEvent>) {
		DFLog(this.debugEnabled, this, "OnSessionStart - Injecting TweakDB updates.");
		
		// Ammo Changes
		//
		if this.ammoWeightEnabled {
			// Weight
			//
			TweakDBManager.SetFlat(t"DarkFutureItem.HandgunAmmoWeight.value", this.weightHandgunAmmo);
			TweakDBManager.SetFlat(t"DarkFutureItem.RifleAmmoWeight.value", this.weightRifleAmmo);
			TweakDBManager.SetFlat(t"DarkFutureItem.ShotgunAmmoWeight.value", this.weightShotgunAmmo);
			TweakDBManager.SetFlat(t"DarkFutureItem.SniperAmmoWeight.value", this.weightSniperAmmo);

			// Quantity
			//
			TweakDBManager.SetFlat(t"DarkFutureItem.HandgunAmmoQuantityOverride.value", 99999001.0); // +999
			TweakDBManager.SetFlat(t"DarkFutureItem.RifleAmmoQuantityOverride.value", 99999001.0);	 // +999
			TweakDBManager.SetFlat(t"DarkFutureItem.ShotgunAmmoQuantityOverride.value", 99999800.0); // +200
			TweakDBManager.SetFlat(t"DarkFutureItem.SniperAmmoQuantityOverride.value", 99999825.0);  // +175
			
			TweakDBManager.UpdateRecord(t"DarkFutureItem.HandgunAmmoWeight");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.RifleAmmoWeight");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.ShotgunAmmoWeight");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.SniperAmmoWeight");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.HandgunAmmoQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.RifleAmmoQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.ShotgunAmmoQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.SniperAmmoQuantityOverride");

		}

		// Ammo - Price
		TweakDBManager.SetFlat(t"DarkFutureItem.AmmoHandgunBuyPriceMultiplier.value", this.priceHandgunAmmo);
		TweakDBManager.SetFlat(t"DarkFutureItem.AmmoRifleBuyPriceMultiplier.value", this.priceRifleAmmo);
		TweakDBManager.SetFlat(t"DarkFutureItem.AmmoShotgunBuyPriceMultiplier.value", this.priceShotgunAmmo);
		TweakDBManager.SetFlat(t"DarkFutureItem.AmmoSniperBuyPriceMultiplier.value", this.priceSniperAmmo);
		TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoHandgunBuyPriceMultiplier");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoRifleBuyPriceMultiplier");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoShotgunBuyPriceMultiplier");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoSniperBuyPriceMultiplier");

		// Consumable Basic Needs
		//
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier1_UIData.intValues", [Cast<Int32>(this.hydrationTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier2_UIData.intValues", [Cast<Int32>(this.hydrationTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier3_UIData.intValues", [Cast<Int32>(this.hydrationTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier1_UIData.intValues", [Cast<Int32>(this.nutritionTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier2_UIData.intValues", [Cast<Int32>(this.nutritionTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier3_UIData.intValues", [Cast<Int32>(this.nutritionTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier4_UIData.intValues", [Cast<Int32>(this.nutritionTier4)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableEnergyTier1_UIData.intValues", [Cast<Int32>(this.energyTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableEnergyTier2_UIData.intValues", [Cast<Int32>(this.energyTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableEnergyTier3_UIData.intValues", [Cast<Int32>(this.energyTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier1_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier2_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier3_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNerveCigarettes_UIData.intValues", [Cast<Int32>(this.nerveCigarettes)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNervePenaltyDrinkTier1_UIData.intValues", [-1 * CeilF(this.hydrationTier1 * this.GetLowQualityConsumablePenaltyFactorAsPercentage()), Cast<Int32>(this.nerveLowQualityConsumablePenaltyLimit)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier1_UIData.intValues", [-1 * CeilF(this.nutritionTier1 * this.GetLowQualityConsumablePenaltyFactorAsPercentage()), Cast<Int32>(this.nerveLowQualityConsumablePenaltyLimit)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier2_UIData.intValues", [-1 * CeilF(this.nutritionTier2 * this.GetLowQualityConsumablePenaltyFactorAsPercentage()), Cast<Int32>(this.nerveLowQualityConsumablePenaltyLimit)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier3_UIData.intValues", [-1 * CeilF(this.nutritionTier3 * this.GetLowQualityConsumablePenaltyFactorAsPercentage()), Cast<Int32>(this.nerveLowQualityConsumablePenaltyLimit)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.WeakNarcotic_NerveChange_UIData.intValues", [Cast<Int32>(this.nerveWeakNarcotics), -1 * Cast<Int32>(this.nerveWeakNarcotics), 1]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.StrongNarcotic_NerveChange_UIData.intValues", [Cast<Int32>(this.nerveStrongNarcotics), -1 * Cast<Int32>(this.nerveStrongNarcotics), 1]);

		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier4_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableEnergyTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableEnergyTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableEnergyTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNerveAlcoholTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNerveCigarettes_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNervePenaltyDrinkTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNervePenaltyFoodTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.WeakNarcotic_NerveChange_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.StrongNarcotic_NerveChange_UIData");

		// Consumable Weight
		//
		TweakDBManager.SetFlat(t"DarkFutureItem.VerySmallFoodWeight.value", this.weightFoodVerySmall);
		TweakDBManager.SetFlat(t"DarkFutureItem.SmallFoodWeight.value", this.weightFoodSmall);
		TweakDBManager.SetFlat(t"DarkFutureItem.MediumFoodWeight.value", this.weightFoodMedium);
		TweakDBManager.SetFlat(t"DarkFutureItem.LargeFoodWeight.value", this.weightFoodLarge);
		TweakDBManager.SetFlat(t"DarkFutureItem.SmallDrinkWeight.value", this.weightDrinkSmall);
		TweakDBManager.SetFlat(t"DarkFutureItem.LargeDrinkWeight.value", this.weightDrinkLarge);
		TweakDBManager.SetFlat(t"DarkFutureItem.SmallDrugWeight.value", this.weightDrugSmall);
		TweakDBManager.SetFlat(t"DarkFutureItem.MediumDrugWeight.value", this.weightDrugMedium);
		TweakDBManager.SetFlat(t"DarkFutureItem.LargeDrugWeight.value", this.weightDrugLarge);
		TweakDBManager.SetFlat(t"DarkFutureItem.FirstAidKitDrugWeight.value", this.weightTraumaKit);

		TweakDBManager.UpdateRecord(t"DarkFutureItem.VerySmallFoodWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.SmallFoodWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.MediumFoodWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.LargeFoodWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.SmallDrinkWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.LargeDrinkWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.SmallDrugWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.MediumDrugWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.LargeDrugWeight");
		TweakDBManager.UpdateRecord(t"DarkFutureItem.FirstAidKitDrugWeight");

		// Consumable Prices
		//
		TweakDBManager.SetFlat(t"DarkFuturePrice.NomadDrinks.value", this.priceDrinkNomad);
		TweakDBManager.SetFlat(t"DarkFuturePrice.CommonDrinks.value", this.priceDrinkCommon);
		TweakDBManager.SetFlat(t"DarkFuturePrice.UncommonDrinks.value", this.priceDrinkUncommon);
		TweakDBManager.SetFlat(t"DarkFuturePrice.RareDrinks.value", this.priceDrinkRare);
		TweakDBManager.SetFlat(t"DarkFuturePrice.EpicDrinks.value", this.priceDrinkEpic);
		TweakDBManager.SetFlat(t"DarkFuturePrice.LegendaryDrinks.value", this.priceDrinkLegendary);
		TweakDBManager.SetFlat(t"DarkFuturePrice.IllegalDrinks.value", this.priceDrinkIllegal);
		TweakDBManager.SetFlat(t"DarkFuturePrice.NomadFood.value", this.priceFoodNomad);
		TweakDBManager.SetFlat(t"DarkFuturePrice.CommonFoodSnack.value", this.priceFoodCommonSnackSmall);
		TweakDBManager.SetFlat(t"DarkFuturePrice.CommonFoodLargeSnack.value", this.priceFoodCommonSnackLarge);
		TweakDBManager.SetFlat(t"DarkFuturePrice.CommonFoodMeal.value", this.priceFoodCommonMeal);
		TweakDBManager.SetFlat(t"DarkFuturePrice.UncommonFood.value", this.priceFoodUncommon);
		TweakDBManager.SetFlat(t"DarkFuturePrice.RareFood.value", this.priceFoodRare);
		TweakDBManager.SetFlat(t"DarkFuturePrice.EpicFood.value", this.priceFoodEpic);
		TweakDBManager.SetFlat(t"DarkFuturePrice.LegendaryFoodSnack.value", this.priceFoodIllegalSnack);
		TweakDBManager.SetFlat(t"DarkFuturePrice.LegendaryFoodMeal.value", this.priceFoodIllegalMeal);
		TweakDBManager.SetFlat(t"Price.LowQualityAlcohol.value", this.priceAlcoholLowQuality);
		TweakDBManager.SetFlat(t"Price.MediumQualityAlcohol.value", this.priceAlcoholMediumQuality);
		TweakDBManager.SetFlat(t"Price.GoodQualityAlcohol.value", this.priceAlcoholGoodQuality);
		TweakDBManager.SetFlat(t"Price.TopQualityAlcohol.value", this.priceAlcoholTopQuality);
		TweakDBManager.SetFlat(t"Price.ExquisiteQualityAlcohol.value", this.priceAlcoholExquisiteQuality);
		TweakDBManager.SetFlat(t"DarkFuturePrice.Cigarettes.value", this.priceCigarettes);
		TweakDBManager.SetFlat(t"DarkFuturePrice.MrWhitey.value", this.priceMrWhitey);
		TweakDBManager.SetFlat(t"DarkFuturePrice.Pharmaceuticals.value", this.pricePharmaceuticals);
		TweakDBManager.SetFlat(t"DarkFuturePrice.IllegalDrugs.value", this.priceIllegalDrugs);

		TweakDBManager.UpdateRecord(t"DarkFuturePrice.NomadDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.CommonDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.UncommonDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.RareDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.EpicDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.LegendaryDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.IllegalDrinks");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.NomadFood");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.CommonFoodSnack");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.CommonFoodLargeSnack");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.CommonFoodMeal");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.UncommonFood");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.RareFood");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.EpicFood");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.LegendaryFoodSnack");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.LegendaryFoodMeal");
		TweakDBManager.UpdateRecord(t"Price.LowQualityAlcohol");
		TweakDBManager.UpdateRecord(t"Price.MediumQualityAlcohol");
		TweakDBManager.UpdateRecord(t"Price.GoodQualityAlcohol");
		TweakDBManager.UpdateRecord(t"Price.TopQualityAlcohol");
		TweakDBManager.UpdateRecord(t"Price.ExquisiteQualityAlcohol");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.Cigarettes");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.MrWhitey");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.Pharmaceuticals");
		TweakDBManager.UpdateRecord(t"DarkFuturePrice.IllegalDrugs");
	}

	private final func ToggleAmmoCrafting(craftingEnabled: Bool) {
		let craftingSystem: ref<CraftingSystem> = CraftingSystem.GetInstance(GetGameInstance());
    	let playerCraftBook: ref<CraftBook> = craftingSystem.GetPlayerCraftBook();

		playerCraftBook.HideRecipe(t"Ammo.HandgunAmmo", !this.ammoCraftingEnabled);
		playerCraftBook.HideRecipe(t"Ammo.ShotgunAmmo", !this.ammoCraftingEnabled);
		playerCraftBook.HideRecipe(t"Ammo.RifleAmmo", !this.ammoCraftingEnabled);
		playerCraftBook.HideRecipe(t"Ammo.SniperRifleAmmo", !this.ammoCraftingEnabled);
	}

	//
	//	CHANGE TRACKING
	//
	// Internal change tracking use only. DO NOT USE.
	// Internal change tracking use only. DO NOT USE.
	private let _mainSystemEnabled: Bool = true;
	private let _showHUDUI: Bool = true;
	private let _needHUDUIAlwaysOnThreshold: Float = 75.0;
	private let _nerveHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.Rose;
	private let _hydrationHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _nutritionHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _energyHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _increasedStaminaRecoveryTime: Bool = true;
	private let _reducedCarryWeight: DFReducedCarryWeightAmount = DFReducedCarryWeightAmount.Full;
	private let _alcoholAddictionEnabled: Bool = true;
	private let _alcoholAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;
	private let _alcoholAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _alcoholAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;
	private let _alcoholAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _alcoholAddictionCessationDurationInGameTimeHours: Int32 = 24;
	private let _alcoholAddictionMinAmountStage1: Float = 6.0;
	private let _alcoholAddictionMinAmountStage2: Float = 12.0;
	private let _alcoholAddictionMinAmountStage3: Float = 18.0;
	private let _alcoholAddictionMinAmountStage4: Float = 24.0;
	private let _alcoholAddictionBackoffDurationStage1: Float = 30.0;
	private let _alcoholAddictionBackoffDurationStage2: Float = 22.5;
	private let _alcoholAddictionBackoffDurationStage3: Float = 15.0;
	private let _alcoholAddictionBackoffDurationStage4: Float = 10.0;
	private let _nicotineAddictionEnabled: Bool = true;
	private let _nicotineAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;
	private let _nicotineAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _nicotineAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;
	private let _nicotineAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _nicotineAddictionCessationDurationInGameTimeHours: Int32 = 24;
	private let _nicotineAddictionMinAmountStage1: Float = 4.0;
	private let _nicotineAddictionMinAmountStage2: Float = 8.0;
	private let _nicotineAddictionMinAmountStage3: Float = 12.0;
	private let _nicotineAddictionMinAmountStage4: Float = 16.0;
	private let _nicotineAddictionBackoffDurationStage1: Float = 30.0;
	private let _nicotineAddictionBackoffDurationStage2: Float = 22.5;
	private let _nicotineAddictionBackoffDurationStage3: Float = 15.0;
	private let _nicotineAddictionBackoffDurationStage4: Float = 10.0;
	private let _narcoticAddictionEnabled: Bool = true;
	private let _narcoticAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;
	private let _narcoticAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _narcoticAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;
	private let _narcoticAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _narcoticAddictionCessationDurationInGameTimeHours: Int32 = 24;
	private let _narcoticAddictionMinAmountStage1: Float = 3.0;
	private let _narcoticAddictionMinAmountStage2: Float = 5.0;
	private let _narcoticAddictionMinAmountStage3: Float = 7.0;
	private let _narcoticAddictionMinAmountStage4: Float = 9.0;
	private let _narcoticAddictionBackoffDurationStage1: Float = 30.0;
	private let _narcoticAddictionBackoffDurationStage2: Float = 22.5;
	private let _narcoticAddictionBackoffDurationStage3: Float = 15.0;
	private let _narcoticAddictionBackoffDurationStage4: Float = 10.0;
	private let _injuryAfflictionEnabled: Bool = true;
	private let _fastTravelDisabled: Bool = true;
	private let _limitVehicleSummoning: Bool = true;
	private let _maxVehicleSummonCredits: Int32 = 2;
	private let _hoursPerSummonCredit: Int32 = 8;
	private let _nerveLossIsFatal: Bool = true;
	private let _criticalNerveVFXEnabled: Bool = true;
	private let _hudUIScale: Float = 1.0;
	private let _hudUIPosX: Float = 70.0;
	private let _hudUIPosY: Float = 240.0;
	private let _updateHolocallVerticalPosition: Bool = true;
	private let _holocallVerticalPositionOffset: Float = 85.0;
	private let _updateStatusEffectListVerticalPosition: Bool = true;
	private let _statusEffectListVerticalPositionOffset: Float = 85.0;
	private let _needNegativeEffectsRepeatEnabled: Bool = true;
	private let _needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds: Float = 300.0;
	private let _needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds: Float = 180.0;
	private let _lowNerveBreathingEffectEnabled: Bool = true;
	private let _hidePersistentStatusIcons: Bool = false;
	private let _timescale: Float = 8.0;
	private let _compatibilityProjectE3HUD: Bool = false;
	private let _compatibilityProjectE3UI: Bool = false;
	// Internal change tracking use only. DO NOT USE.
	// Internal change tracking use only. DO NOT USE.

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFSettings> {
		let instance: ref<DFSettings> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"DarkFuture.Settings.DFSettings") as DFSettings;
		return instance;
	}

	public final static func Get() -> ref<DFSettings> {
		return DFSettings.GetInstance(GetGameInstance());
	}
	
	private func OnDetach() -> Void {
		UnregisterDFSettingsListener(this);
	}

	public func Init(attachedPlayer: ref<PlayerPuppet>) -> Void {
		DFLog(this.debugEnabled, this, "Ready!");

		RegisterDFSettingsListener(this);
    }

	public func OnModSettingsChange() -> Void {
		this.ReconcileSettings();
	}

	public final func GetLowQualityConsumablePenaltyFactorAsPercentage() -> Float {
		return this.nerveLowQualityConsumablePenaltyFactor / 100.0;
	}

	public final func ReconcileSettings() -> Void {
		DFLog(this.debugEnabled, this, "Beginning Settings Reconciliation...");
		let changedSettings: array<String>;

		if NotEquals(this._mainSystemEnabled, this.mainSystemEnabled) {
			this._mainSystemEnabled = this.mainSystemEnabled;
			ArrayPush(changedSettings, "mainSystemEnabled");
		}

		if NotEquals(this._showHUDUI, this.showHUDUI) {
			this._showHUDUI = this.showHUDUI;
			ArrayPush(changedSettings, "showHUDUI");
		}

		if NotEquals(this._needHUDUIAlwaysOnThreshold, this.needHUDUIAlwaysOnThreshold) {
			this._needHUDUIAlwaysOnThreshold = this.needHUDUIAlwaysOnThreshold;
			ArrayPush(changedSettings, "needHUDUIAlwaysOnThreshold");
		}

		if NotEquals(this._nerveHUDUIColorTheme, this.nerveHUDUIColorTheme) {
			this._nerveHUDUIColorTheme = this.nerveHUDUIColorTheme;
			ArrayPush(changedSettings, "nerveHUDUIColorTheme");
		}

		if NotEquals(this._hydrationHUDUIColorTheme, this.hydrationHUDUIColorTheme) {
			this._hydrationHUDUIColorTheme = this.hydrationHUDUIColorTheme;
			ArrayPush(changedSettings, "hydrationHUDUIColorTheme");
		}

		if NotEquals(this._nutritionHUDUIColorTheme, this.nutritionHUDUIColorTheme) {
			this._nutritionHUDUIColorTheme = this.nutritionHUDUIColorTheme;
			ArrayPush(changedSettings, "nutritionHUDUIColorTheme");
		}

		if NotEquals(this._energyHUDUIColorTheme, this.energyHUDUIColorTheme) {
			this._energyHUDUIColorTheme = this.energyHUDUIColorTheme;
			ArrayPush(changedSettings, "energyHUDUIColorTheme");
		}

		if NotEquals(this._increasedStaminaRecoveryTime, this.increasedStaminaRecoveryTime) {
			this._increasedStaminaRecoveryTime = this.increasedStaminaRecoveryTime;
			ArrayPush(changedSettings, "increasedStaminaRecoveryTime");
		}

		if NotEquals(this._reducedCarryWeight, this.reducedCarryWeight) {
			this._reducedCarryWeight = this.reducedCarryWeight;
			ArrayPush(changedSettings, "reducedCarryWeight");
		}

		if NotEquals(this._alcoholAddictionEnabled, this.alcoholAddictionEnabled) {
			this._alcoholAddictionEnabled = this.alcoholAddictionEnabled;
			ArrayPush(changedSettings, "alcoholAddictionEnabled");
		}

		if NotEquals(this._alcoholAddictionStage1WithdrawalDurationInGameTimeHours, this.alcoholAddictionStage1WithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionStage1WithdrawalDurationInGameTimeHours = this.alcoholAddictionStage1WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionStage1WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionStage2WithdrawalDurationInGameTimeHours, this.alcoholAddictionStage2WithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionStage2WithdrawalDurationInGameTimeHours = this.alcoholAddictionStage2WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionStage2WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionStage3WithdrawalDurationInGameTimeHours, this.alcoholAddictionStage3WithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionStage3WithdrawalDurationInGameTimeHours = this.alcoholAddictionStage3WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionStage3WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionStage4WithdrawalDurationInGameTimeHours, this.alcoholAddictionStage4WithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionStage4WithdrawalDurationInGameTimeHours = this.alcoholAddictionStage4WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionStage4WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionCessationDurationInGameTimeHours, this.alcoholAddictionCessationDurationInGameTimeHours) {
			this._alcoholAddictionCessationDurationInGameTimeHours = this.alcoholAddictionCessationDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionCessationDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionMinAmountStage1, this.alcoholAddictionMinAmountStage1) {
			this._alcoholAddictionMinAmountStage1 = this.alcoholAddictionMinAmountStage1;
			ArrayPush(changedSettings, "alcoholAddictionMinAmountStage1");
		}

		if NotEquals(this._alcoholAddictionMinAmountStage2, this.alcoholAddictionMinAmountStage2) {
			this._alcoholAddictionMinAmountStage2 = this.alcoholAddictionMinAmountStage2;
			ArrayPush(changedSettings, "alcoholAddictionMinAmountStage2");
		}

		if NotEquals(this._alcoholAddictionMinAmountStage3, this.alcoholAddictionMinAmountStage3) {
			this._alcoholAddictionMinAmountStage3 = this.alcoholAddictionMinAmountStage3;
			ArrayPush(changedSettings, "alcoholAddictionMinAmountStage3");
		}

		if NotEquals(this._alcoholAddictionMinAmountStage4, this.alcoholAddictionMinAmountStage4) {
			this._alcoholAddictionMinAmountStage4 = this.alcoholAddictionMinAmountStage4;
			ArrayPush(changedSettings, "alcoholAddictionMinAmountStage4");
		}

		if NotEquals(this._alcoholAddictionBackoffDurationStage1, this.alcoholAddictionBackoffDurationStage1) {
			this._alcoholAddictionBackoffDurationStage1 = this.alcoholAddictionBackoffDurationStage1;
			ArrayPush(changedSettings, "alcoholAddictionBackoffDurationStage1");
		}

		if NotEquals(this._alcoholAddictionBackoffDurationStage2, this.alcoholAddictionBackoffDurationStage2) {
			this._alcoholAddictionBackoffDurationStage2 = this.alcoholAddictionBackoffDurationStage2;
			ArrayPush(changedSettings, "alcoholAddictionBackoffDurationStage2");
		}

		if NotEquals(this._alcoholAddictionBackoffDurationStage3, this.alcoholAddictionBackoffDurationStage3) {
			this._alcoholAddictionBackoffDurationStage3 = this.alcoholAddictionBackoffDurationStage3;
			ArrayPush(changedSettings, "alcoholAddictionBackoffDurationStage3");
		}

		if NotEquals(this._alcoholAddictionBackoffDurationStage4, this.alcoholAddictionBackoffDurationStage4) {
			this._alcoholAddictionBackoffDurationStage4 = this.alcoholAddictionBackoffDurationStage4;
			ArrayPush(changedSettings, "alcoholAddictionBackoffDurationStage4");
		}

		if NotEquals(this._nicotineAddictionEnabled, this.nicotineAddictionEnabled) {
			this._nicotineAddictionEnabled = this.nicotineAddictionEnabled;
			ArrayPush(changedSettings, "nicotineAddictionEnabled");
		}

		if NotEquals(this._nicotineAddictionStage1WithdrawalDurationInGameTimeHours, this.nicotineAddictionStage1WithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionStage1WithdrawalDurationInGameTimeHours = this.nicotineAddictionStage1WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionStage1WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionStage2WithdrawalDurationInGameTimeHours, this.nicotineAddictionStage2WithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionStage2WithdrawalDurationInGameTimeHours = this.nicotineAddictionStage2WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionStage2WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionStage3WithdrawalDurationInGameTimeHours, this.nicotineAddictionStage3WithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionStage3WithdrawalDurationInGameTimeHours = this.nicotineAddictionStage3WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionStage3WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionStage4WithdrawalDurationInGameTimeHours, this.nicotineAddictionStage4WithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionStage4WithdrawalDurationInGameTimeHours = this.nicotineAddictionStage4WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionStage4WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionCessationDurationInGameTimeHours, this.nicotineAddictionCessationDurationInGameTimeHours) {
			this._nicotineAddictionCessationDurationInGameTimeHours = this.nicotineAddictionCessationDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionCessationDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionMinAmountStage1, this.nicotineAddictionMinAmountStage1) {
			this._nicotineAddictionMinAmountStage1 = this.nicotineAddictionMinAmountStage1;
			ArrayPush(changedSettings, "nicotineAddictionMinAmountStage1");
		}

		if NotEquals(this._nicotineAddictionMinAmountStage2, this.nicotineAddictionMinAmountStage2) {
			this._nicotineAddictionMinAmountStage2 = this.nicotineAddictionMinAmountStage2;
			ArrayPush(changedSettings, "nicotineAddictionMinAmountStage2");
		}

		if NotEquals(this._nicotineAddictionMinAmountStage3, this.nicotineAddictionMinAmountStage3) {
			this._nicotineAddictionMinAmountStage3 = this.nicotineAddictionMinAmountStage3;
			ArrayPush(changedSettings, "nicotineAddictionMinAmountStage3");
		}

		if NotEquals(this._nicotineAddictionMinAmountStage4, this.nicotineAddictionMinAmountStage4) {
			this._nicotineAddictionMinAmountStage4 = this.nicotineAddictionMinAmountStage4;
			ArrayPush(changedSettings, "nicotineAddictionMinAmountStage4");
		}

		if NotEquals(this._nicotineAddictionBackoffDurationStage1, this.nicotineAddictionBackoffDurationStage1) {
			this._nicotineAddictionBackoffDurationStage1 = this.nicotineAddictionBackoffDurationStage1;
			ArrayPush(changedSettings, "nicotineAddictionBackoffDurationStage1");
		}

		if NotEquals(this._nicotineAddictionBackoffDurationStage2, this.nicotineAddictionBackoffDurationStage2) {
			this._nicotineAddictionBackoffDurationStage2 = this.nicotineAddictionBackoffDurationStage2;
			ArrayPush(changedSettings, "nicotineAddictionBackoffDurationStage2");
		}

		if NotEquals(this._nicotineAddictionBackoffDurationStage3, this.nicotineAddictionBackoffDurationStage3) {
			this._nicotineAddictionBackoffDurationStage3 = this.nicotineAddictionBackoffDurationStage3;
			ArrayPush(changedSettings, "nicotineAddictionBackoffDurationStage3");
		}

		if NotEquals(this._nicotineAddictionBackoffDurationStage4, this.nicotineAddictionBackoffDurationStage4) {
			this._nicotineAddictionBackoffDurationStage4 = this.nicotineAddictionBackoffDurationStage4;
			ArrayPush(changedSettings, "nicotineAddictionBackoffDurationStage4");
		}

		if NotEquals(this._narcoticAddictionEnabled, this.narcoticAddictionEnabled) {
			this._narcoticAddictionEnabled = this.narcoticAddictionEnabled;
			ArrayPush(changedSettings, "narcoticAddictionEnabled");
		}

		if NotEquals(this._narcoticAddictionStage1WithdrawalDurationInGameTimeHours, this.narcoticAddictionStage1WithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionStage1WithdrawalDurationInGameTimeHours = this.narcoticAddictionStage1WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionStage1WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionStage2WithdrawalDurationInGameTimeHours, this.narcoticAddictionStage2WithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionStage2WithdrawalDurationInGameTimeHours = this.narcoticAddictionStage2WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionStage2WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionStage3WithdrawalDurationInGameTimeHours, this.narcoticAddictionStage3WithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionStage3WithdrawalDurationInGameTimeHours = this.narcoticAddictionStage3WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionStage3WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionStage4WithdrawalDurationInGameTimeHours, this.narcoticAddictionStage4WithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionStage4WithdrawalDurationInGameTimeHours = this.narcoticAddictionStage4WithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionStage4WithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionCessationDurationInGameTimeHours, this.narcoticAddictionCessationDurationInGameTimeHours) {
			this._narcoticAddictionCessationDurationInGameTimeHours = this.narcoticAddictionCessationDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionCessationDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionMinAmountStage1, this.narcoticAddictionMinAmountStage1) {
			this._narcoticAddictionMinAmountStage1 = this.narcoticAddictionMinAmountStage1;
			ArrayPush(changedSettings, "narcoticAddictionMinAmountStage1");
		}

		if NotEquals(this._narcoticAddictionMinAmountStage2, this.narcoticAddictionMinAmountStage2) {
			this._narcoticAddictionMinAmountStage2 = this.narcoticAddictionMinAmountStage2;
			ArrayPush(changedSettings, "narcoticAddictionMinAmountStage2");
		}

		if NotEquals(this._narcoticAddictionMinAmountStage3, this.narcoticAddictionMinAmountStage3) {
			this._narcoticAddictionMinAmountStage3 = this.narcoticAddictionMinAmountStage3;
			ArrayPush(changedSettings, "narcoticAddictionMinAmountStage3");
		}

		if NotEquals(this._narcoticAddictionMinAmountStage4, this.narcoticAddictionMinAmountStage4) {
			this._narcoticAddictionMinAmountStage4 = this.narcoticAddictionMinAmountStage4;
			ArrayPush(changedSettings, "narcoticAddictionMinAmountStage4");
		}

		if NotEquals(this._narcoticAddictionBackoffDurationStage1, this.narcoticAddictionBackoffDurationStage1) {
			this._narcoticAddictionBackoffDurationStage1 = this.narcoticAddictionBackoffDurationStage1;
			ArrayPush(changedSettings, "narcoticAddictionBackoffDurationStage1");
		}

		if NotEquals(this._narcoticAddictionBackoffDurationStage2, this.narcoticAddictionBackoffDurationStage2) {
			this._narcoticAddictionBackoffDurationStage2 = this.narcoticAddictionBackoffDurationStage2;
			ArrayPush(changedSettings, "narcoticAddictionBackoffDurationStage2");
		}

		if NotEquals(this._narcoticAddictionBackoffDurationStage3, this.narcoticAddictionBackoffDurationStage3) {
			this._narcoticAddictionBackoffDurationStage3 = this.narcoticAddictionBackoffDurationStage3;
			ArrayPush(changedSettings, "narcoticAddictionBackoffDurationStage3");
		}

		if NotEquals(this._narcoticAddictionBackoffDurationStage4, this.narcoticAddictionBackoffDurationStage4) {
			this._narcoticAddictionBackoffDurationStage4 = this.narcoticAddictionBackoffDurationStage4;
			ArrayPush(changedSettings, "narcoticAddictionBackoffDurationStage4");
		}

		if NotEquals(this._injuryAfflictionEnabled, this.injuryAfflictionEnabled) {
			this._injuryAfflictionEnabled = this.injuryAfflictionEnabled;
			ArrayPush(changedSettings, "injuryAfflictionEnabled");
		}

		if NotEquals(this._fastTravelDisabled, this.fastTravelDisabled) {
			this._fastTravelDisabled = this.fastTravelDisabled;
			ArrayPush(changedSettings, "fastTravelDisabled");
		}

		if NotEquals(this._limitVehicleSummoning, this.limitVehicleSummoning) {
			this._limitVehicleSummoning = this.limitVehicleSummoning;
			ArrayPush(changedSettings, "limitVehicleSummoning");
		}

		if NotEquals(this._maxVehicleSummonCredits, this.maxVehicleSummonCredits) {
			this._maxVehicleSummonCredits = this.maxVehicleSummonCredits;
			ArrayPush(changedSettings, "maxVehicleSummonCredits");
		}

		if NotEquals(this._hoursPerSummonCredit, this.hoursPerSummonCredit) {
			this._hoursPerSummonCredit = this.hoursPerSummonCredit;
			ArrayPush(changedSettings, "hoursPerSummonCredit");
		}

		if NotEquals(this._nerveLossIsFatal, this.nerveLossIsFatal) {
			this._nerveLossIsFatal = this.nerveLossIsFatal;
			ArrayPush(changedSettings, "nerveLossIsFatal");
		}

		if NotEquals(this._criticalNerveVFXEnabled, this.criticalNerveVFXEnabled) {
			this._criticalNerveVFXEnabled = this.criticalNerveVFXEnabled;
			ArrayPush(changedSettings, "criticalNerveVFXEnabled");
		}

		if NotEquals(this._hudUIScale, this.hudUIScale) {
			this._hudUIScale = this.hudUIScale;
			ArrayPush(changedSettings, "hudUIScale");
		}

		if NotEquals(this._hudUIPosX, this.hudUIPosX) {
			this._hudUIPosX = this.hudUIPosX;
			ArrayPush(changedSettings, "hudUIPosX");
		}

		if NotEquals(this._hudUIPosY, this.hudUIPosY) {
			this._hudUIPosY = this.hudUIPosY;
			ArrayPush(changedSettings, "hudUIPosY");
		}

		if NotEquals(this._updateHolocallVerticalPosition, this.updateHolocallVerticalPosition) {
			this._updateHolocallVerticalPosition = this.updateHolocallVerticalPosition;
			ArrayPush(changedSettings, "updateHolocallVerticalPosition");
		}

		if NotEquals(this._holocallVerticalPositionOffset, this.holocallVerticalPositionOffset) {
			this._holocallVerticalPositionOffset = this.holocallVerticalPositionOffset;
			ArrayPush(changedSettings, "holocallVerticalPositionOffset");
		}

		if NotEquals(this._updateStatusEffectListVerticalPosition, this.updateStatusEffectListVerticalPosition) {
			this._updateStatusEffectListVerticalPosition = this.updateStatusEffectListVerticalPosition;
			ArrayPush(changedSettings, "updateStatusEffectListVerticalPosition");
		}

		if NotEquals(this._statusEffectListVerticalPositionOffset, this.statusEffectListVerticalPositionOffset) {
			this._statusEffectListVerticalPositionOffset = this.statusEffectListVerticalPositionOffset;
			ArrayPush(changedSettings, "statusEffectListVerticalPositionOffset");
		}


		if NotEquals(this._needNegativeEffectsRepeatEnabled, this.needNegativeEffectsRepeatEnabled) {
			this._needNegativeEffectsRepeatEnabled = this.needNegativeEffectsRepeatEnabled;
			ArrayPush(changedSettings, "needNegativeEffectsRepeatEnabled");
		}

		if NotEquals(this._needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds, this.needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds) {
			this._needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds = this.needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds;
			ArrayPush(changedSettings, "needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds");
		}

		if NotEquals(this._needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds, this.needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds) {
			this._needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds = this.needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds;
			ArrayPush(changedSettings, "needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds");
		}

		if NotEquals(this._lowNerveBreathingEffectEnabled, this.lowNerveBreathingEffectEnabled) {
			this._lowNerveBreathingEffectEnabled = this.lowNerveBreathingEffectEnabled;
			ArrayPush(changedSettings, "lowNerveBreathingEffectEnabled");
		}

		if NotEquals(this._hidePersistentStatusIcons, this.hidePersistentStatusIcons) {
			this._hidePersistentStatusIcons = this.hidePersistentStatusIcons;
			ArrayPush(changedSettings, "hidePersistentStatusIcons");
		}

		if NotEquals(this._timescale, this.timescale) {
			this._timescale = this.timescale;
			ArrayPush(changedSettings, "timescale");
		}

		if NotEquals(this._compatibilityProjectE3HUD, this.compatibilityProjectE3HUD) {
			this._compatibilityProjectE3HUD = this.compatibilityProjectE3HUD;
			ArrayPush(changedSettings, "compatibilityProjectE3HUD");
		}

		if NotEquals(this._compatibilityProjectE3UI, this.compatibilityProjectE3UI) {
			this._compatibilityProjectE3UI = this.compatibilityProjectE3UI;
			ArrayPush(changedSettings, "compatibilityProjectE3UI");
		}
		
		if ArraySize(changedSettings) > 0 {
			DFLog(this.debugEnabled, this, "        ...the following settings have changed: " + ToString(changedSettings));
			GameInstance.GetCallbackSystem().DispatchEvent(SettingChangedEvent.Create(changedSettings));
		}

		DFLog(this.debugEnabled, this, "        ...updating ammo crafting recipe availability...");
		this.ToggleAmmoCrafting(this.ammoCraftingEnabled);

		DFLog(this.debugEnabled, this, "        ...done!");
	}

	// -------------------------------------------------------------------------
	// System Settings
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "10")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingMainSystemEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingMainSystemEnabledDesc")
	public let mainSystemEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - General
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingReducedCarryWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingReducedCarryWeightDesc")
	@runtimeProperty("ModSettings.displayValues.Full", "DarkFutureReducedCarryWeightAmountFull")
    @runtimeProperty("ModSettings.displayValues.Half", "DarkFutureReducedCarryWeightAmountHalf")
	@runtimeProperty("ModSettings.displayValues.Off", "DarkFutureReducedCarryWeightAmountOff")
	public let reducedCarryWeight: DFReducedCarryWeightAmount = DFReducedCarryWeightAmount.Full;
	
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingIncreasedStaminaRecoveryTime")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingIncreasedStaminaRecoveryTimeDesc")
	public let increasedStaminaRecoveryTime: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingStashCraftingEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingStashCraftingEnabledDesc")
	public let stashCraftingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNoConsumablesInStash")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNoConsumablesInStashDesc")
	public let noConsumablesInStash: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - Fast Travel
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayFastTravel")
	@runtimeProperty("ModSettings.category.order", "30")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingFastTravelDisabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingFastTravelDisabledDesc")
	public let fastTravelDisabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayFastTravel")
	@runtimeProperty("ModSettings.category.order", "30")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHideFastTravelMarkers")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHideFastTravelMarkersDesc")
	public let hideFastTravelMarkers: Bool = true;
	
	// -------------------------------------------------------------------------
	// Gameplay - Vehicle Summoning
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSummoning")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLimitVehicleSummoning")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLimitVehicleSummoningDesc")
	public let limitVehicleSummoning: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSummoning")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingMaxVehicleSummonCredits")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingMaxVehicleSummonCreditsDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "9")
	public let maxVehicleSummonCredits: Int32 = 2;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSummoning")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHoursPerSummonCredit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHoursPerSummonCreditDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "24")
	public let hoursPerSummonCredit: Int32 = 8;

	// -------------------------------------------------------------------------
	// Gameplay - Sleeping In Vehicles
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAllowSleepingInVehicles")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAllowSleepingInVehiclesDesc")
	public let allowSleepingInVehicles: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSleepingInVehiclesRoadDetection")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSleepingInVehiclesRoadDetectionDesc")
	@runtimeProperty("ModSettings.displayValues.Curb", "DarkFutureSettingSleepingInVehiclesRoadDetectionSettingCurb")
    @runtimeProperty("ModSettings.displayValues.Roadside", "DarkFutureSettingSleepingInVehiclesRoadDetectionSettingRoadside")
	@runtimeProperty("ModSettings.displayValues.Secluded", "DarkFutureSettingSleepingInVehiclesRoadDetectionSettingSecluded")
	public let sleepingInVehiclesRoadDetectionToleranceSetting: DFRoadDetectionToleranceSetting = DFRoadDetectionToleranceSetting.Roadside;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyLimitSleepInVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyLimitSleepInVehicleDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let limitedEnergySleepingInVehicles: Float = 70.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingVehicleSleepQualityCity")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingVehicleSleepQualityCityDesc")
	@runtimeProperty("ModSettings.displayValues.Limited", "DarkFutureSettingSleepQualityLimited")
    @runtimeProperty("ModSettings.displayValues.Full", "DarkFutureSettingSleepQualityFull")
	public let vehicleSleepQualityCity: DFSleepQualitySetting = DFSleepQualitySetting.Limited;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingVehicleSleepQualityBadlands")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingVehicleSleepQualityBadlandsDesc")
	@runtimeProperty("ModSettings.displayValues.Limited", "DarkFutureSettingSleepQualityLimited")
    @runtimeProperty("ModSettings.displayValues.Full", "DarkFutureSettingSleepQualityFull")
	public let vehicleSleepQualityBadlands: DFSleepQualitySetting = DFSleepQualitySetting.Limited;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingForceFPPWhenSleepingInVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingForceFPPWhenSleepingInVehicleDesc")
	public let forceFPPWhenSleepingInVehicle: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowSleepingInVehiclesInputHint")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowSleepingInVehiclesInputHintDesc")
	public let showSleepingInVehiclesInputHint: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - Sleep Encounters
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnableRandomEncountersWhenSleepingInVehicles")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnableRandomEncountersWhenSleepingInVehiclesDesc")
	public let enableRandomEncountersWhenSleepingInVehicles: Bool = true;
	
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceGangDistrict")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceGangDistrictDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceGangDistrict: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceCityCenter")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceCityCenterDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceCityCenter: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceBadlands")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceBadlandsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceBadlands: Float = 15.0;

	// -------------------------------------------------------------------------
	// Survival - Basic Needs
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let hydrationLossRatePct: Float = 100.0;
	
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nutritionLossRatePct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let energyLossRatePct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateInCombatPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateInCombatPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nerveLossRateInCombatPct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateWhenTracedPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateWhenTracedPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nerveLossRateWhenTracedPct: Float = 200.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossIsFatal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossIsFatalDesc")
	public let nerveLossIsFatal: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveWeaponSwayEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveWeaponSwayEnabledDesc")
	public let nerveWeaponSwayEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Survival - Injury
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionInjury")
	@runtimeProperty("ModSettings.category.order", "55")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryAfflictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryAfflictionEnabledDesc")
	public let injuryAfflictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionInjury")
	@runtimeProperty("ModSettings.category.order", "55")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryAccumulationRate")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryAccumulationRateDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let injuryHealthLossAccumulationRate: Float = 5.0;

	// -------------------------------------------------------------------------
	// Survival - Alcohol Addiction
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAlcoholAddictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAlcoholAddictionEnabledDesc")
	public let alcoholAddictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let alcoholAddictionProgressChance: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAmountOnUse")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAmountOnUseDesc")
	@runtimeProperty("ModSettings.step", "0.2")
	@runtimeProperty("ModSettings.min", "0.2")
	@runtimeProperty("ModSettings.max", "4.0")
	public let alcoholAddictionAmountOnUse: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let alcoholAddictionLossPerDay: Float = 2.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let alcoholAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionCessationDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionCessationDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionCessationDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage1Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let alcoholAddictionMinAmountStage1: Float = 6.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage2Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let alcoholAddictionMinAmountStage2: Float = 12.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage3Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let alcoholAddictionMinAmountStage3: Float = 18.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage4Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let alcoholAddictionMinAmountStage4: Float = 24.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage1Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage1: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage2: Float = 22.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage3: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage4: Float = 10.0;

	// -------------------------------------------------------------------------
	// Survival - Nicotine Addiction
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNicotineAddictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNicotineAddictionEnabledDesc")
	public let nicotineAddictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nicotineAddictionProgressChance: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAmountOnUse")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAmountOnUseDesc")
	@runtimeProperty("ModSettings.step", "0.2")
	@runtimeProperty("ModSettings.min", "0.2")
	@runtimeProperty("ModSettings.max", "4.0")
	public let nicotineAddictionAmountOnUse: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let nicotineAddictionLossPerDay: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let nicotineAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionCessationDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionCessationDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionCessationDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage1Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let nicotineAddictionMinAmountStage1: Float = 4.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage2Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let nicotineAddictionMinAmountStage2: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage3Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let nicotineAddictionMinAmountStage3: Float = 12.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage4Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let nicotineAddictionMinAmountStage4: Float = 16.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage1Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage1: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage2: Float = 22.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage3: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage4: Float = 10.0;

	// -------------------------------------------------------------------------
	// Survival - Narcotic Addiction
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticAddictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNarcoticAddictionEnabledDesc")
	public let narcoticAddictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let narcoticAddictionProgressChance: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "8")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAmountOnUseNarcoticLow")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAmountOnUseNarcoticLowDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "4.0")
	public let narcoticAddictionAmountOnUseLow: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "8")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAmountOnUseNarcoticHigh")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAmountOnUseNarcoticHighDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "4.0")
	public let narcoticAddictionAmountOnUseHigh: Float = 2.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let narcoticAddictionLossPerDay: Float = 0.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let narcoticAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionStage1WithdrawalDurationInGameTimeHours: Int32 = 12;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionStage2WithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionStage3WithdrawalDurationInGameTimeHours: Int32 = 36;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionStage4WithdrawalDurationInGameTimeHours: Int32 = 48;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionCessationDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionCessationDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionCessationDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage1Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let narcoticAddictionMinAmountStage1: Float = 3.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage2Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let narcoticAddictionMinAmountStage2: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage3Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let narcoticAddictionMinAmountStage3: Float = 7.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMinAmountStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMinAmountStage4Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "50.0")
	public let narcoticAddictionMinAmountStage4: Float = 9.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage1Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage1: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage2: Float = 22.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage3: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage4: Float = 10.0;

	// -------------------------------------------------------------------------
	// Interface
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHidePersistentStatusIcons")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHidePersistentStatusIconsDesc")
	public let hidePersistentStatusIcons: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowHUDUI")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowHUDUIDesc")
	public let showHUDUI: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedHUDUIAlwaysOnThreshold")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedHUDUIAlwaysOnThresholdDesc")
	@runtimeProperty("ModSettings.step", "5.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let needHUDUIAlwaysOnThreshold: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveHUDUIColorTheme")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveHUDUIColorThemeDesc")
	@runtimeProperty("ModSettings.displayValues.Rose", "DarkFutureColorThemeNameRose")
    @runtimeProperty("ModSettings.displayValues.HotPink", "DarkFutureColorThemeNameHotPink")
	@runtimeProperty("ModSettings.displayValues.PanelRed", "DarkFutureColorThemeNamePanelRed")
	@runtimeProperty("ModSettings.displayValues.MainRed", "DarkFutureColorThemeNameMainRed")
	@runtimeProperty("ModSettings.displayValues.Magenta", "DarkFutureColorThemeNameMagenta")
	@runtimeProperty("ModSettings.displayValues.PigeonPost", "DarkFutureColorThemeNamePigeonPost")
    @runtimeProperty("ModSettings.displayValues.MainBlue", "DarkFutureColorThemeNameMainBlue")
	@runtimeProperty("ModSettings.displayValues.Aqua", "DarkFutureColorThemeNameAqua")
    @runtimeProperty("ModSettings.displayValues.SpringGreen", "DarkFutureColorThemeNameSpringGreen")
    @runtimeProperty("ModSettings.displayValues.StreetCredGreen", "DarkFutureColorThemeNameStreetCredGreen")
	@runtimeProperty("ModSettings.displayValues.Yellow", "DarkFutureColorThemeNameYellow")
	@runtimeProperty("ModSettings.displayValues.White", "DarkFutureColorThemeNameWhite")
	public let nerveHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.Rose;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationHUDUIColorTheme")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationHUDUIColorThemeDesc")
	@runtimeProperty("ModSettings.displayValues.Rose", "DarkFutureColorThemeNameRose")
    @runtimeProperty("ModSettings.displayValues.HotPink", "DarkFutureColorThemeNameHotPink")
	@runtimeProperty("ModSettings.displayValues.PanelRed", "DarkFutureColorThemeNamePanelRed")
	@runtimeProperty("ModSettings.displayValues.MainRed", "DarkFutureColorThemeNameMainRed")
	@runtimeProperty("ModSettings.displayValues.Magenta", "DarkFutureColorThemeNameMagenta")
	@runtimeProperty("ModSettings.displayValues.PigeonPost", "DarkFutureColorThemeNamePigeonPost")
    @runtimeProperty("ModSettings.displayValues.MainBlue", "DarkFutureColorThemeNameMainBlue")
	@runtimeProperty("ModSettings.displayValues.Aqua", "DarkFutureColorThemeNameAqua")
    @runtimeProperty("ModSettings.displayValues.SpringGreen", "DarkFutureColorThemeNameSpringGreen")
    @runtimeProperty("ModSettings.displayValues.StreetCredGreen", "DarkFutureColorThemeNameStreetCredGreen")
	@runtimeProperty("ModSettings.displayValues.Yellow", "DarkFutureColorThemeNameYellow")
	@runtimeProperty("ModSettings.displayValues.White", "DarkFutureColorThemeNameWhite")
	public let hydrationHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionHUDUIColorTheme")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionHUDUIColorThemeDesc")
	@runtimeProperty("ModSettings.displayValues.Rose", "DarkFutureColorThemeNameRose")
    @runtimeProperty("ModSettings.displayValues.HotPink", "DarkFutureColorThemeNameHotPink")
	@runtimeProperty("ModSettings.displayValues.PanelRed", "DarkFutureColorThemeNamePanelRed")
	@runtimeProperty("ModSettings.displayValues.MainRed", "DarkFutureColorThemeNameMainRed")
	@runtimeProperty("ModSettings.displayValues.Magenta", "DarkFutureColorThemeNameMagenta")
	@runtimeProperty("ModSettings.displayValues.PigeonPost", "DarkFutureColorThemeNamePigeonPost")
    @runtimeProperty("ModSettings.displayValues.MainBlue", "DarkFutureColorThemeNameMainBlue")
	@runtimeProperty("ModSettings.displayValues.Aqua", "DarkFutureColorThemeNameAqua")
    @runtimeProperty("ModSettings.displayValues.SpringGreen", "DarkFutureColorThemeNameSpringGreen")
    @runtimeProperty("ModSettings.displayValues.StreetCredGreen", "DarkFutureColorThemeNameStreetCredGreen")
	@runtimeProperty("ModSettings.displayValues.Yellow", "DarkFutureColorThemeNameYellow")
	@runtimeProperty("ModSettings.displayValues.White", "DarkFutureColorThemeNameWhite")
	public let nutritionHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyHUDUIColorTheme")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyHUDUIColorThemeDesc")
	@runtimeProperty("ModSettings.displayValues.Rose", "DarkFutureColorThemeNameRose")
    @runtimeProperty("ModSettings.displayValues.HotPink", "DarkFutureColorThemeNameHotPink")
	@runtimeProperty("ModSettings.displayValues.PanelRed", "DarkFutureColorThemeNamePanelRed")
	@runtimeProperty("ModSettings.displayValues.MainRed", "DarkFutureColorThemeNameMainRed")
	@runtimeProperty("ModSettings.displayValues.Magenta", "DarkFutureColorThemeNameMagenta")
	@runtimeProperty("ModSettings.displayValues.PigeonPost", "DarkFutureColorThemeNamePigeonPost")
    @runtimeProperty("ModSettings.displayValues.MainBlue", "DarkFutureColorThemeNameMainBlue")
	@runtimeProperty("ModSettings.displayValues.Aqua", "DarkFutureColorThemeNameAqua")
    @runtimeProperty("ModSettings.displayValues.SpringGreen", "DarkFutureColorThemeNameSpringGreen")
    @runtimeProperty("ModSettings.displayValues.StreetCredGreen", "DarkFutureColorThemeNameStreetCredGreen")
	@runtimeProperty("ModSettings.displayValues.Yellow", "DarkFutureColorThemeNameYellow")
	@runtimeProperty("ModSettings.displayValues.White", "DarkFutureColorThemeNameWhite")
	public let energyHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNewInventoryFilters")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNewInventoryFiltersDesc")
	public let newInventoryFilters: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let interfaceAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIMinOpacity")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIMinOpacityDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hudUIMinOpacity: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIScale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIScaleDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "4.0")
	public let hudUIScale: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIPosX")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIPosXDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "3840.0")
	public let hudUIPosX: Float = 70.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIPosY")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIPosYDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "2160.0")
	public let hudUIPosY: Float = 240.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBackpackUIScale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBackpackUIScaleDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "4.0")
	public let backpackUIScale: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBackpackUIPosX")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBackpackUIPosXDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "3840.0")
	public let backpackUIPosX: Float = 675.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBackpackUIPosY")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBackpackUIPosYDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "2160.0")
	public let backpackUIPosY: Float = 425.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateHolocallPosition")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateHolocallPositionDesc")
	public let updateHolocallVerticalPosition: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHolocallVerticalPositionOffset")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHolocallVerticalPositionOffsetDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "1600.0")
	public let holocallVerticalPositionOffset: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateStatusEffectListPosition")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateStatusEffectListPositionDesc")
	public let updateStatusEffectListVerticalPosition: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingStatusEffectListVerticalPositionOffset")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingStatusEffectListVerticalPositionOffsetDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "1600.0")
	public let statusEffectListVerticalPositionOffset: Float = 85.0;

	// -------------------------------------------------------------------------
	// Sounds and Visual Effects
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatEnabledDesc")
	public let needNegativeEffectsRepeatEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencyModerateInRealTimeSecondsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "1800.0")
	public let needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds: Float = 300.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencySevereInRealTimeSeconds")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencySevereInRealTimeSecondsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "1800.0")
	public let needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds: Float = 180.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeSFXEnabledDesc")
	public let needNegativeSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedPositiveSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedPositiveSFXEnabledDesc")
	public let needPositiveSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let fxAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSFXEnabledDesc")
	public let addictionSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingOutOfBreathEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingOutOfBreathEffectEnabledDesc")
	public let outOfBreathEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLowNerveBreathingEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLowNerveBreathingEffectEnabledDesc")
	public let lowNerveBreathingEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticsSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNarcoticsSFXEnabledDesc")
	public let narcoticsSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveNeedVFXEnabledDesc")
	public let nerveNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCriticalNerveVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCriticalNerveVFXEnabledDesc")
	public let criticalNerveVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationNeedVFXEnabledDesc")
	public let hydrationNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionNeedVFXEnabledDesc")
	public let nutritionNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyNeedVFXEnabledDesc")
	public let energyNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingOutOfBreathCameraEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingOutOfBreathCameraEffectEnabledDesc")
	public let outOfBreathCameraEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSmokingEffectsEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSmokingEffectsEnabledDesc")
	public let smokingEffectsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNauseaInteractableEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNauseaInteractableEffectEnabledDesc")
	public let nauseaInteractableEffectEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Notifications
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryNotifications")
	@runtimeProperty("ModSettings.category.order", "130")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedMessagesEnabledDesc")
	public let needMessagesEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryNotifications")
	@runtimeProperty("ModSettings.category.order", "130")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMessagesEnabledDesc")
	public let addictionMessagesEnabled: Bool = true;		

	// -------------------------------------------------------------------------
	// Compatibility
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnSleepVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnSleepVehicleDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
    @runtimeProperty("ModSettings.displayValues.TurnOff", "DarkFutureCompatEVSPowerBehaviorTurnOff")
	@runtimeProperty("ModSettings.displayValues.TurnOn", "DarkFutureCompatEVSPowerBehaviorTurnOn")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorOnSleep: EnhancedVehicleSystemCompatPowerBehaviorDriver = EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOff;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnWakeVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnWakeVehicleDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
	@runtimeProperty("ModSettings.displayValues.TurnOff", "DarkFutureCompatEVSPowerBehaviorTurnOff")
    @runtimeProperty("ModSettings.displayValues.TurnOn", "DarkFutureCompatEVSPowerBehaviorTurnOn")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorOnWake: EnhancedVehicleSystemCompatPowerBehaviorDriver = EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOn;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorAsPassengerDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
	@runtimeProperty("ModSettings.displayValues.SameAsDriver", "DarkFutureCompatEVSPowerBehaviorSameAsDriver")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger: EnhancedVehicleSystemCompatPowerBehaviorPassenger = EnhancedVehicleSystemCompatPowerBehaviorPassenger.SameAsDriver;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityWannabeEdgerunner")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityWannabeEdgerunnerDesc")
	public let compatibilityWannabeEdgerunner: Bool = true;
	
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityProjectE3HUD")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityProjectE3HUDDesc")
	public let compatibilityProjectE3HUD: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "150")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityProjectE3UI")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityProjectE3UIDesc")
	public let compatibilityProjectE3UI: Bool = false;

	// -------------------------------------------------------------------------
	// Misc
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "160")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTutorialsEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTutorialsEnabledDesc")
	public let tutorialsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "160")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTimescale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTimescaleDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "40.0")
	public let timescale: Float = 8.0;

	// -------------------------------------------------------------------------
	// Advanced - Consumable Restoration
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let showConsumableRestorationSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier1: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier2: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier3: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier1: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier2: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier3: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier4: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyTier1: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyTier2: Float = 25.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyTier3: Float = 35.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveAlcoholInteractionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier1: Float = 6.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier2: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier3: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveCigarettes")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveCigarettes: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveNarcoticsWeak")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveNarcoticsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveWeakNarcotics: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveNarcoticsPotent")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveNarcoticsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveStrongNarcotics: Float = 40.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNervePenaltyFactor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsNervePenaltyFactorDesc")
	@runtimeProperty("ModSettings.step", "10.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveLowQualityConsumablePenaltyFactor: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "showConsumableRestorationSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNervePenaltyLimit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsNervePenaltyLimitDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveLowQualityConsumablePenaltyLimit: Float = 70.0;

	// -------------------------------------------------------------------------
	// Advanced - Consumable Weight
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let showConsumableWeightSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodVerySmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodVerySmall: Float = 0.6;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodSmall: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodMedium")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodMedium: Float = 1.2;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodLarge: Float = 1.6;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrinkSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrinkSmall: Float = 0.8;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrinkLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrinkLarge: Float = 1.2;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugSmall: Float = 0.3;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugMedium")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugMedium: Float = 0.6;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugLarge: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "showConsumableWeightSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugTraumaKit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightTraumaKit: Float = 2.0;

	// -------------------------------------------------------------------------
	// Advanced - Consumable Prices
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let showConsumablePriceSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkNomad")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkNomad: Float = 0.65;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkCommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkCommon: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkUncommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkUncommon: Float = 1.25;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkRare")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkRare: Float = 2.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkEpic")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkEpic: Float = 4.4;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkLegendary")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkLegendary: Float = 10.25;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkIllegal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkIllegal: Float = 31.25;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodNomad")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodNomad: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonSmallSnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonSnackSmall: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonLargeSnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonSnackLarge: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonMeal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonMeal: Float = 2.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodUncommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodUncommon: Float = 3.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodRare")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodRare: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodEpic")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodEpic: Float = 9.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodLegendarySnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodIllegalSnack: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodLegendaryMeal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodIllegalMeal: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholLowQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceAlcoholLowQuality: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholMediumQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceAlcoholMediumQuality: Float = 2.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholGoodQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceAlcoholGoodQuality: Float = 3.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholTopQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceAlcoholTopQuality: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholExquisiteQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceAlcoholExquisiteQuality: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceCigarettes")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceCigarettes: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceMrWhitey")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceMrWhitey: Float = 7.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPricePharmaceuticals")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let pricePharmaceuticals: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "showConsumablePriceSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrugsIllegal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceIllegalDrugs: Float = 1.0;

	// -------------------------------------------------------------------------
	// Advanced - Ammo
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let showAmmoSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsAmmoWeightDesc")
	public let ammoWeightEnabled: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoCrafting")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsAmmoCraftingDesc")
	public let ammoCraftingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoHandgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightHandgunAmmo: Float = 0.01;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoRifle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightRifleAmmo: Float = 0.01;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoShotgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightShotgunAmmo: Float = 0.03;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoSniper")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightSniperAmmo: Float = 0.05;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoHandgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceHandgunAmmo: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoRifle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceRifleAmmo: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoShotgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceShotgunAmmo: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "showAmmoSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoSniper")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceSniperAmmo: Float = 2.0;
}

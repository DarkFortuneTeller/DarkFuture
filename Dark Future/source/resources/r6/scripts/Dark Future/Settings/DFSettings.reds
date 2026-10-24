// -----------------------------------------------------------------------------
// DFSettings
// -----------------------------------------------------------------------------
//
// - Mod Settings configuration.
//

module DarkFuture.Settings

import DarkFuture.Logging.*
import DarkFuture.Utils.{
	DFBarColorThemeName
}
import DarkFuture.Gameplay.{
	EnhancedVehicleSystemCompatPowerBehaviorDriver,
	EnhancedVehicleSystemCompatPowerBehaviorPassenger
}

public enum DFReducedCarryWeightAmount {
	Full = 0,
	Half = 1,
	Off = 2
}

public enum DFAmmoWeightSetting {
	Disabled = 0,
	EnabledLimitedAmmo = 1,
	EnabledUnlimitedAmmo = 2
}

public enum DFSleepQualitySetting {
	Limited = 0,
	Full = 1
}

public enum DFFastTravelSetting {
	Disabled = 0,
	DisabledAllowMetro = 1,
	Enabled = 2
}

public enum DFAmmoHandicapSetting {
	DontModify = 0,
	Disabled = 1,
	Enabled = 2
}

public enum DFEconomicSetting {
	DontModify = 0,
	Modify = 1
}

public enum DFConsumableAnimationCooldownBehavior {
	Off = 0,
	ByExactVisualProp = 1,
	ByGeneralVisualProp = 2,
	ByVisualPropType = 3,
	ByAnimationType = 4,
	All = 5
}

public enum DFCrashAnimSetting {
	On = 0,
	HeadacheOnly = 1,
	Off = 2
}

//	ModSettings - Register if Mod Settings installed
//
@if(ModuleExists("ModSettingsModule")) 
public func RegisterDFSettingsListener(listener: ref<IScriptable>) {
	//DFProfile();
	ModSettings.RegisterListenerToClass(listener);
  	ModSettings.RegisterListenerToModifications(listener);
}

@if(ModuleExists("ModSettingsModule")) 
public func UnregisterDFSettingsListener(listener: ref<IScriptable>) {
	//DFProfile();
	ModSettings.UnregisterListenerToClass(listener);
  	ModSettings.UnregisterListenerToModifications(listener);
}

//	ModSettings - No-op if Mod Settings not installed
//
@if(!ModuleExists("ModSettingsModule")) 
public func RegisterDFSettingsListener(listener: ref<IScriptable>) {
	//DFProfile();
	//FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener registration aborted.");
}
@if(!ModuleExists("ModSettingsModule")) 
public func UnregisterDFSettingsListener(listener: ref<IScriptable>) {
	//DFProfile();
	//FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener unregistration aborted.");
}

public class SettingChangedEvent extends CallbackSystemEvent {
	let changedSettings: array<String>;

	public final func GetData() -> array<String> {
		//DFProfile();
		return this.changedSettings;
	}

    public static func Create(data: array<String>) -> ref<SettingChangedEvent> {
		//DFProfile();
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

	public func OnAttach() {
		//DFProfile();
		GameInstance.GetCallbackSystem().RegisterCallback(n"Session/Start", this, n"OnSessionStart");
	}

	public final func OnSessionStart(evt: ref<GameSessionEvent>) {
		//DFProfile();
		DFLogNoSystem(this.debugEnabled, this, "OnSessionStart - Injecting TweakDB updates.");
		
		// Ammo Changes
		//
		if Equals(this.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledLimitedAmmo) || Equals(this.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo) {
			// Weight
			//
			TweakDBManager.SetFlat(t"DarkFutureWeight.AmmoHandgun.value", this.weightHandgunAmmo);
			TweakDBManager.SetFlat(t"DarkFutureWeight.AmmoRifle.value", this.weightRifleAmmo);
			TweakDBManager.SetFlat(t"DarkFutureWeight.AmmoShotgun.value", this.weightShotgunAmmo);
			TweakDBManager.SetFlat(t"DarkFutureWeight.AmmoSniper.value", this.weightSniperAmmo);

			TweakDBManager.UpdateRecord(t"DarkFutureWeight.AmmoHandgun");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.AmmoRifle");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.AmmoShotgun");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.AmmoSniper");
		}

		if Equals(this.ammoWeightEnabledV2, DFAmmoWeightSetting.EnabledUnlimitedAmmo) {
			// Quantity
			//
			TweakDBManager.SetFlat(t"DarkFutureItem.AmmoHandgunQuantityOverride.value", 99999001.0); // +999
			TweakDBManager.SetFlat(t"DarkFutureItem.AmmoRifleQuantityOverride.value", 99999001.0);	 // +999
			TweakDBManager.SetFlat(t"DarkFutureItem.AmmoShotgunQuantityOverride.value", 99999800.0); // +200
			TweakDBManager.SetFlat(t"DarkFutureItem.AmmoSniperQuantityOverride.value", 99999825.0);  // +175
			
			TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoHandgunQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoRifleQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoShotgunQuantityOverride");
			TweakDBManager.UpdateRecord(t"DarkFutureItem.AmmoSniperQuantityOverride");
		}

		// Ammo - Handicap Drops
		//
		if Equals(this.ammoHandicapDrops, DFAmmoHandicapSetting.Enabled) {
			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapLimit", 120);
			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapMaxQty", 150);
  			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapMinQty", 90);

			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapLimit", 120);
			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapMaxQty", 150);
  			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapMinQty", 90);

			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapLimit", 50);
			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapMaxQty", 125);
			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapMinQty", 75);

			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapLimit", 40);
			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapMaxQty", 80);
			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapMinQty", 40);

			TweakDBManager.UpdateRecord(t"Ammo.HandicapHandgunAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapRifleAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapShotgunAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapSniperRifleAmmoPreset");
			
		} else if Equals(this.ammoHandicapDrops, DFAmmoHandicapSetting.Disabled) {
			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapLimit", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapMaxQty", 0);
  			TweakDBManager.SetFlat(t"Ammo.HandicapHandgunAmmoPreset.handicapMinQty", 0);

			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapLimit", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapMaxQty", 0);
  			TweakDBManager.SetFlat(t"Ammo.HandicapRifleAmmoPreset.handicapMinQty", 0);

			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapLimit", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapMaxQty", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapShotgunAmmoPreset.handicapMinQty", 0);

			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapLimit", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapMaxQty", 0);
			TweakDBManager.SetFlat(t"Ammo.HandicapSniperRifleAmmoPreset.handicapMinQty", 0);

			TweakDBManager.UpdateRecord(t"Ammo.HandicapHandgunAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapRifleAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapShotgunAmmoPreset");
			TweakDBManager.UpdateRecord(t"Ammo.HandicapSniperRifleAmmoPreset");
		}

		// Ammo - Price
		//
		if Equals(this.ammoPriceModify, DFEconomicSetting.Modify) {
			TweakDBManager.SetFlat(t"DarkFuturePrice.AmmoHandgunBuyMult.value", this.priceHandgunAmmo);
			TweakDBManager.SetFlat(t"DarkFuturePrice.AmmoRifleBuyMult.value", this.priceRifleAmmo);
			TweakDBManager.SetFlat(t"DarkFuturePrice.AmmoShotgunBuyMult.value", this.priceShotgunAmmo);
			TweakDBManager.SetFlat(t"DarkFuturePrice.AmmoSniperBuyMult.value", this.priceSniperAmmo);
			TweakDBManager.SetFlat(t"DarkFuturePrice.AmmoSellMult.value", this.priceAmmoSellMult);
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.AmmoHandgunBuyMult");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.AmmoRifleBuyMult");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.AmmoShotgunBuyMult");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.AmmoSniperBuyMult");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.AmmoSellMult");
		}

		// Consumable Basic Needs
		//
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier1_UIData.intValues", [Cast<Int32>(this.hydrationTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier2_UIData.intValues", [Cast<Int32>(this.hydrationTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableHydrationTier3_UIData.intValues", [Cast<Int32>(this.hydrationTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier1_UIData.intValues", [Cast<Int32>(this.nutritionTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier2_UIData.intValues", [Cast<Int32>(this.nutritionTier2)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier3_UIData.intValues", [Cast<Int32>(this.nutritionTier3)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableNutritionTier4_UIData.intValues", [Cast<Int32>(this.nutritionTier4)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.CaffeinatedEffect_UIData.intValues", [Cast<Int32>(this.energyCaffeineTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Caffeinated1Stack_UIData.intValues", [Cast<Int32>(this.energyCaffeineTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Caffeinated2Stack_UIData.intValues", [2, Cast<Int32>(this.energyCaffeineTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Drunk_UIData.intValues", [5, Cast<Int32>(this.energyAlcoholTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier1_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier1Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier2_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier2Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier2_UIData.intValues", [Cast<Int32>(this.nerveAlcoholTier3Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_WineCocktail_Tier2_UIData.intValues", [2, Cast<Int32>(this.nerveAlcoholTier2Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_WineCocktail_Tier3_UIData.intValues", [2, Cast<Int32>(this.nerveAlcoholTier3Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier1_UIData.intValues", [3, Cast<Int32>(this.nerveAlcoholTier1Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier2_UIData.intValues", [3, Cast<Int32>(this.nerveAlcoholTier2Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier3_UIData.intValues", [3, Cast<Int32>(this.nerveAlcoholTier3Rev4), Cast<Int32>(-this.energyAlcoholTier1), 5]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.CigaretteStatusEffect_UIData.intValues", [Cast<Int32>(this.energyNicotineTier1), 50]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.ConsumableCigaretteEffect_UIData.intValues", [Cast<Int32>(this.nerveCigarettesRev3), Cast<Int32>(this.energyNicotineTier1)]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Narcotic_UIData.intValues", [Cast<Int32>(this.energyNarcoticTier1), 3, 3]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.MrWhitey_OnEquip_UIData.intValues", [1, 4, Cast<Int32>(this.nerveNarcoticsRev2), Cast<Int32>(this.energyNarcoticTier1), 3, 3]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.NarcoticPill_OnEquip_UIData.intValues", [2, 4, Cast<Int32>(this.nerveNarcoticsRev2), Cast<Int32>(this.energyNarcoticTier1), 3, 3]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Glitter_OnEquip_UIData.intValues", [3, 6, Cast<Int32>(this.nerveNarcoticsRev2), Cast<Int32>(this.energyNarcoticTier1), 3, 3]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.BlackLaceV0_OnEquip_UIData.intValues", [4, 6, Cast<Int32>(this.nerveNarcoticsRev2), Cast<Int32>(this.energyNarcoticTier1), 3, 3]);
		TweakDBManager.SetFlat(t"DarkFutureStatusEffect.BlackLaceV1_OnEquip_UIData.intValues", [5, 7, Cast<Int32>(this.nerveNarcoticsRev2), Cast<Int32>(this.energyNarcoticTier1), 3, 3]);

		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableHydrationTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableNutritionTier4_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.CaffeinatedEffect_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Caffeinated1Stack_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Caffeinated2Stack_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Drunk_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemSingleStackEffect_Tier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_WineCocktail_Tier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_WineCocktail_Tier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier1_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier2_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.AlcoholItemMultiStackEffect_Liquor_Tier3_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.CigaretteStatusEffect_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.ConsumableCigaretteEffect_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Narcotic_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.MrWhitey_OnEquip_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.NarcoticPill_OnEquip_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Glitter_OnEquip_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.BlackLaceV0_OnEquip_UIData");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.BlackLaceV1_OnEquip_UIData");

		// Consumable Weight
		//
		if Equals(this.consumableWeightsModify, DFEconomicSetting.Modify) {
			TweakDBManager.SetFlat(t"DarkFutureWeight.VerySmallFood.value", this.weightFoodVerySmall);
			TweakDBManager.SetFlat(t"DarkFutureWeight.SmallFood.value", this.weightFoodSmall);
			TweakDBManager.SetFlat(t"DarkFutureWeight.MediumFood.value", this.weightFoodMedium);
			TweakDBManager.SetFlat(t"DarkFutureWeight.LargeFood.value", this.weightFoodLarge);
			TweakDBManager.SetFlat(t"DarkFutureWeight.SmallDrink.value", this.weightDrinkSmall);
			TweakDBManager.SetFlat(t"DarkFutureWeight.LargeDrink.value", this.weightDrinkLarge);
			TweakDBManager.SetFlat(t"DarkFutureWeight.SmallDrug.value", this.weightDrugSmall);
			TweakDBManager.SetFlat(t"DarkFutureWeight.MediumDrug.value", this.weightDrugMedium);
			TweakDBManager.SetFlat(t"DarkFutureWeight.LargeDrug.value", this.weightDrugLarge);
			TweakDBManager.SetFlat(t"DarkFutureWeight.FirstAidKitDrug.value", this.weightTraumaKit);

			TweakDBManager.UpdateRecord(t"DarkFutureWeight.VerySmallFood");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.SmallFood");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.MediumFood");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.LargeFood");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.SmallDrink");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.LargeDrink");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.SmallDrug");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.MediumDrug");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.LargeDrug");
			TweakDBManager.UpdateRecord(t"DarkFutureWeight.FirstAidKitDrug");
		}

		// Consumable Prices
		//
		if Equals(this.consumablePricesModify, DFEconomicSetting.Modify) {
			TweakDBManager.SetFlat(t"Price.Food.value", 6.0);
			TweakDBManager.SetFlat(t"Price.Drink.value", 8.0);
			TweakDBManager.SetFlat(t"Price.LowQualityAlcohol.value", this.priceAlcoholLowQuality);
			TweakDBManager.SetFlat(t"Price.MediumQualityAlcohol.value", this.priceAlcoholMediumQuality);
			TweakDBManager.SetFlat(t"Price.GoodQualityAlcohol.value", this.priceAlcoholGoodQuality);
			TweakDBManager.SetFlat(t"Price.TopQualityAlcohol.value", this.priceAlcoholTopQuality);
			TweakDBManager.SetFlat(t"Price.ExquisiteQualityAlcohol.value", this.priceAlcoholExquisiteQuality);

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
			
			TweakDBManager.SetFlat(t"DarkFuturePrice.Cigarettes.value", this.priceCigarettes);
			TweakDBManager.SetFlat(t"DarkFuturePrice.MrWhitey.value", this.priceMrWhitey);
			TweakDBManager.SetFlat(t"DarkFuturePrice.Pharmaceuticals.value", this.pricePharmaceuticals);
			TweakDBManager.SetFlat(t"DarkFuturePrice.IllegalDrugs.value", this.priceIllegalDrugs);
			TweakDBManager.SetFlat(t"DarkFuturePrice.EndotrisineMult.value", this.priceEndotrisine);

			TweakDBManager.UpdateRecord(t"Price.Food");
			TweakDBManager.UpdateRecord(t"Price.Drink");
			TweakDBManager.UpdateRecord(t"Price.LowQualityAlcohol");
			TweakDBManager.UpdateRecord(t"Price.MediumQualityAlcohol");
			TweakDBManager.UpdateRecord(t"Price.GoodQualityAlcohol");
			TweakDBManager.UpdateRecord(t"Price.TopQualityAlcohol");
			TweakDBManager.UpdateRecord(t"Price.ExquisiteQualityAlcohol");

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
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.Cigarettes");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.MrWhitey");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.Pharmaceuticals");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.IllegalDrugs");
			TweakDBManager.UpdateRecord(t"DarkFuturePrice.EndotrisineMult");
		}

		// Trauma Kit
		//
		let healthBoosterOnEquip: array<TweakDBID> = FromVariant<array<TweakDBID>>(TweakDBInterface.GetFlat(t"Items.HealthBooster.OnEquip"));
        let newHealthBoosterOnEquip: array<TweakDBID>;
		if this.injuryConditionEnabled {
			// Prepend our effect. Don't allow duplicates.
			ArrayPush(newHealthBoosterOnEquip, t"DarkFutureItem.InjuryCureDrugOnEquip");
		}

		for onEquip in healthBoosterOnEquip {
			if NotEquals(onEquip, t"DarkFutureItem.InjuryCureDrugOnEquip") {
				ArrayPush(newHealthBoosterOnEquip, onEquip);
			}
		}
        TweakDBManager.SetFlat(t"Items.HealthBooster.OnEquip", newHealthBoosterOnEquip);
		TweakDBManager.UpdateRecord(t"Items.HealthBooster");

		// Immunosuppressant
		//
		let newImmunosuppressantOnEquip: array<TweakDBID>;
		if this.humanityLossConditionEnabled {
			if this.humanityLossCyberpsychosisEnabled {
				// Humanity Loss Condition and Cyberpsychosis are enabled.
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_CureCyberpsychosis");
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_SuppressHumanityLoss");
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_NegateHealthReduction");
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_PreventCyberpsychosis");
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Immunosuppressant_UIData.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionImmunosuppressantAllEffects"));
			} else {
				// Humanity Loss Condition is enabled. Cyberpsychosis is disabled.
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_SuppressHumanityLoss");
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_NegateHealthReduction");
				ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_PreventFury");
				TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Immunosuppressant_UIData.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionImmunosuppressantNoCyberpsychosis"));
			}

		} else {
			// Humanity Loss Condition is disabled. Implicitly, Cyberpsychosis is disabled.
			ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_NegateHealthReduction");
			ArrayPush(newImmunosuppressantOnEquip, t"DarkFutureItem.ImmunosuppressantDrugOnEquip_PreventFury");
			TweakDBManager.SetFlat(t"DarkFutureStatusEffect.Immunosuppressant_UIData.description", GetLocalizedTextByKey(n"DarkFutureEffectDescriptionImmunosuppressantNoHumanityLoss"));
		}

		TweakDBManager.SetFlat(t"DarkFutureItem.ImmunosuppressantDrug.OnEquip", newImmunosuppressantOnEquip);
		TweakDBManager.UpdateRecord(t"DarkFutureItem.ImmunosuppressantDrug");
		TweakDBManager.UpdateRecord(t"DarkFutureStatusEffect.Immunosuppressant_UIData");

		// Hangover Treatment
		//
		let hangoverTreatmentOnEquip: array<TweakDBID> = FromVariant<array<TweakDBID>>(TweakDBInterface.GetFlat(t"DarkFutureItem.HangoverTreatmentDrug.OnEquip"));
		let newHangoverTreatmentOnEquip: array<TweakDBID>;
		if this.biocorruptionConditionEnabled {
			// Prepend our effect. Don't allow duplicates.
			ArrayPush(newHangoverTreatmentOnEquip, t"DarkFutureStatusEffect.HangoverTreatmentDrug_CrashRestore_OnEquip");
		}

		for onEquip in hangoverTreatmentOnEquip {
			if NotEquals(onEquip, t"DarkFutureStatusEffect.HangoverTreatmentDrug_CrashRestore_OnEquip") {
				ArrayPush(newHangoverTreatmentOnEquip, onEquip);
			}
		}

		TweakDBManager.SetFlat(t"DarkFutureItem.HangoverTreatmentDrug.OnEquip", newHangoverTreatmentOnEquip);
		TweakDBManager.UpdateRecord(t"DarkFutureItem.HangoverTreatmentDrug");

		// TODO: Update with new effects
		/*
		this.ApplyHangoverCureFoodDescriptions();
		this.ApplyHangoverCureDrinkDescriptions();
		*/
	}

	private final func ApplyHangoverCureFoodDescriptions() -> Void {
		//DFProfile();
		let foodList: array<String> = [
			"Items.GoodQualityFood10",
			"Items.GoodQualityFood11",
			"Items.GoodQualityFood12",
			"Items.GoodQualityFood13",
			"Items.GoodQualityFood5",
			"Items.GoodQualityFood6",
			"Items.LowQualityFood10",
			"Items.MediumQualityFood9",
			"Items.HawtDawgKabanos",
			"Items.RiverFood1",
			"Items.LowQualityFood3",
			"Items.HawtDawgClassic",
			"Items.HawtDawgCheese",
			"Items.HawtDawgChilli",
			"Items.NomadsFood1",
			"Items.NomadsFood2",
			"Items.GoodQualityFood2",
			"Items.GoodQualityFood9",
			"Items.MediumQualityFood10",
			"Items.JudyFood1",
			"Items.PanamFood1",
			"Items.sq026_judy_sandwich",
			"Items.CombatFood1",
			"Items.CombatFood3",
			"Items.HealthFood1",
			"Items.NetrunnerFood2",
			"Items.StealthFood1",
			"Items.CombatFood2",
			"Items.HealthFood2",
			"Items.HealthFood3"
		];

		for food in foodList {
			let foodTDBID: TweakDBID = TDBID.Create(food);
			let foodOnEquipTDBID: TweakDBID = TDBID.Create(food + ".OnEquip");
			let foodOnEquip: array<TweakDBID> = FromVariant<array<TweakDBID>>(TweakDBInterface.GetFlat(foodOnEquipTDBID));
			let newFoodOnEquip: array<TweakDBID>;

			for onEquip in foodOnEquip {
				if NotEquals(onEquip, t"DarkFutureStatusEffect.FoodCrashRestore_OnEquip") {
					ArrayPush(newFoodOnEquip, onEquip);
				}
			}

			if this.biocorruptionConditionEnabled {
				// Append our effect. Don't allow duplicates.
				ArrayPush(newFoodOnEquip, t"DarkFutureStatusEffect.FoodCrashRestore_OnEquip");
			}

			TweakDBManager.SetFlat(foodOnEquipTDBID, newFoodOnEquip);
			TweakDBManager.UpdateRecord(foodTDBID);
		}
	}

	private final func ApplyHangoverCureDrinkDescriptions() -> Void {
		//DFProfile();
		let drinkList: array<String> = [
			"Items.LowQualityDrink1",
			"Items.LowQualityDrink11",
			"Items.LowQualityDrink12",
			"Items.LowQualityDrink13",
			"Items.MediumQualityDrink10",
			"Items.JudyDrink1",
			"Items.sq026_judy_coffee",
			"Items.RiverDrink1",
			"Items.LowQualityDrink2",
			"Items.MediumQualityDrink3",
			"Items.MediumQualityDrink4",
			"Items.GoodQualityDrink5",
			"Items.GoodQualityDrink6",
			"Items.GoodQualityDrink7",
			"Items.MediumQualityDrink11",
			"Items.NomadsDrink1",
			"Items.GoodQualityDrink10",
			"Items.GoodQualityDrink1",
			"Items.GoodQualityDrink8",
			"Items.GoodQualityDrink9",
			"Items.CarFood1",
			"Items.NetrunnerFood1"
		];

		for drink in drinkList {
			let drinkTDBID: TweakDBID = TDBID.Create(drink);
			let drinkOnEquipTDBID: TweakDBID = TDBID.Create(drink + ".OnEquip");
			let drinkOnEquip: array<TweakDBID> = FromVariant<array<TweakDBID>>(TweakDBInterface.GetFlat(drinkOnEquipTDBID));
			let newDrinkOnEquip: array<TweakDBID>;

			for onEquip in drinkOnEquip {
				if NotEquals(onEquip, t"DarkFutureStatusEffect.DrinkCrashRestore_OnEquip") {
					ArrayPush(newDrinkOnEquip, onEquip);
				}
			}

			if this.biocorruptionConditionEnabled {
				// Append our effect. Don't allow duplicates.
				ArrayPush(newDrinkOnEquip, t"DarkFutureStatusEffect.DrinkCrashRestore_OnEquip");
			}

			TweakDBManager.SetFlat(drinkOnEquipTDBID, newDrinkOnEquip);
			TweakDBManager.UpdateRecord(drinkTDBID);
		}
	}

	private final func ToggleAmmoCrafting(craftingEnabled: Bool) {
		//DFProfile();
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
	private let _tutorialsEnabled: Bool = true;
	private let _showHUDUI: Bool = true;
	private let _needHUDUIAlwaysOnThreshold: Float = 75.0;
	private let _nerveHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.Rose;
	private let _hydrationHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _nutritionHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _energyHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.PigeonPost;
	private let _conditionsIndicatorHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.MainRed;
	private let _reducedCarryWeight: DFReducedCarryWeightAmount = DFReducedCarryWeightAmount.Full;
	private let _addictionEnabled: Bool = true;
	private let _addictionStage1WithdrawalDurationInGameTimeHoursV2: Int32 = 24;
	private let _addictionStage2WithdrawalDurationInGameTimeHoursV2: Int32 = 36;
	private let _addictionStage3WithdrawalDurationInGameTimeHoursV2: Int32 = 48;
	private let _addictionStage4WithdrawalDurationInGameTimeHoursV2: Int32 = 60;
	private let _addictionCessationDurationInGameTimeHours: Int32 = 48;
	private let _addictionBackoffDurationStage1: Float = 8.0;
	private let _addictionBackoffDurationStage2: Float = 6.0;
	private let _addictionBackoffDurationStage3: Float = 5.0;
	private let _addictionBackoffDurationStage4: Float = 4.0;
	private let _injuryConditionEnabled: Bool = true;
	private let _humanityLossConditionEnabled: Bool = true;
	private let _biocorruptionConditionEnabled: Bool = true;
	private let _fastTravelSettingV2: DFFastTravelSetting = DFFastTravelSetting.Disabled;
	private let _limitVehicleSummoning: Bool = true;
	private let _maxVehicleSummonCredits: Int32 = 2;
	private let _hoursPerSummonCredit: Int32 = 8;
	private let _nerveLossIsFatal: Bool = true;
	private let _criticalNeedVFXEnabled: Bool = true;
	private let _hudUIScale: Float = 1.0;
	private let _hudUIPosX: Float = 70.0;
	private let _hudUIPosY: Float = 240.0;
	private let _updateHolocallVerticalPosition: Bool = true;
	private let _holocallVerticalPositionOffset: Float = 85.0;
	private let _updateStatusEffectListVerticalPosition: Bool = true;
	private let _statusEffectListVerticalPositionOffset: Float = 85.0;
	private let _updateRaceUIVerticalPosition: Bool = true;
	private let _raceUIVerticalPositionOffset: Float = 85.0;
	private let _needNegativeEffectsRepeatEnabled: Bool = true;
	private let _needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds: Float = 300.0;
	private let _needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds: Float = 180.0;
	private let _lowNerveBreathingEffectEnabled: Bool = true;
	private let _timescale: Float = 8.0;
	private let _compatibilityProjectE3HUD: Bool = false;
	private let _compatibilityProjectE3UI: Bool = false;
	private let _consumableAnimationsEnabled: Bool = true;
	private let _consumableAnimationCooldownTimeInRealTimeSeconds: Float = 60.0;
	private let _consumableAnimationCooldownBehavior: DFConsumableAnimationCooldownBehavior = DFConsumableAnimationCooldownBehavior.ByGeneralVisualProp;
	private let _forceFPPWhenSleepingInVehicle: Bool = true;
	public let _humanityLossCyberpsychosisEnabled: Bool = true;
	private let _cyberpsychosisSFXEnabled: Bool = true;
	private let _cyberpsychosisEffectsRepeatEnabled: Bool = true;
	private let _cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds: Float = 180.0;
	private let _humanityLossFuryAcceleratedPrevention: Bool = true;
	private let _basicNeedThresholdValue1V2: Float = 85.0;
	private let _basicNeedThresholdValue2V2: Float = 75.0;
	private let _basicNeedThresholdValue3V2: Float = 50.0;
	private let _basicNeedThresholdValue4V2: Float = 25.0;
	private let _withdrawalAnimationsEnabled: Bool = true;
	private let _blackoutEnabled: Bool = true;
	private let _impairedDrivingEnabled: Bool = true;
	private let _showConditionsIndicatorHUDUI: Bool = true;
	private let _syncConditionsUIWithHealthStamina: Bool = true;
	private let _crashAnimationSetting: DFCrashAnimSetting = DFCrashAnimSetting.On;
	// Internal change tracking use only. DO NOT USE.
	// Internal change tracking use only. DO NOT USE.

	public final static func GetInstance(gameInstance: GameInstance) -> ref<DFSettings> {
		//DFProfile();
		let instance: ref<DFSettings> = GameInstance.GetScriptableSystemsContainer(gameInstance).Get(NameOf<DFSettings>()) as DFSettings;
		return instance;
	}

	public final static func Get() -> ref<DFSettings> {
		//DFProfile();
		return DFSettings.GetInstance(GetGameInstance());
	}
	
	public func OnDetach() -> Void {
		//DFProfile();
		UnregisterDFSettingsListener(this);
	}

	public func Init(attachedPlayer: ref<PlayerPuppet>) -> Void {
		//DFProfile();
		DFLogNoSystem(this.debugEnabled, this, "Ready!");

		RegisterDFSettingsListener(this);
    }

	public func OnModSettingsChange() -> Void {
		//DFProfile();
		this.ReconcileSettings();
	}

	/*public final func GetLowQualityConsumablePenaltyFactorAsPercentage() -> Float {
		//DFProfile();
		return this.nerveLowQualityConsumablePenaltyFactor / 100.0;
	}*/

	public final func ReconcileSettings() -> Void {
		//DFProfile();
		DFLogNoSystem(this.debugEnabled, this, "Beginning Settings Reconciliation...");
		let changedSettings: array<String>;

		if NotEquals(this._mainSystemEnabled, this.mainSystemEnabled) {
			this._mainSystemEnabled = this.mainSystemEnabled;
			ArrayPush(changedSettings, "mainSystemEnabled");
		}

		if NotEquals(this._tutorialsEnabled, this.tutorialsEnabled) {
			this._tutorialsEnabled = this.tutorialsEnabled;

			GameInstance.GetQuestsSystem(GetGameInstance()).SetFact(n"df_fact_tutorials_disabled", this.tutorialsEnabled ? 0 : 1);

			ArrayPush(changedSettings, "tutorialsEnabled");
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

		if NotEquals(this._conditionsIndicatorHUDUIColorTheme, this.conditionsIndicatorHUDUIColorTheme) {
			this._conditionsIndicatorHUDUIColorTheme = this.conditionsIndicatorHUDUIColorTheme;
			ArrayPush(changedSettings, "conditionsIndicatorHUDUIColorTheme");
		}

		if NotEquals(this._reducedCarryWeight, this.reducedCarryWeight) {
			this._reducedCarryWeight = this.reducedCarryWeight;
			ArrayPush(changedSettings, "reducedCarryWeight");
		}

		if NotEquals(this._addictionEnabled, this.addictionEnabled) {
			this._addictionEnabled = this.addictionEnabled;
			ArrayPush(changedSettings, "addictionEnabled");
		}

		if NotEquals(this._addictionStage1WithdrawalDurationInGameTimeHoursV2, this.addictionStage1WithdrawalDurationInGameTimeHoursV2) {
			this._addictionStage1WithdrawalDurationInGameTimeHoursV2 = this.addictionStage1WithdrawalDurationInGameTimeHoursV2;
			ArrayPush(changedSettings, "addictionStage1WithdrawalDurationInGameTimeHoursV2");
		}

		if NotEquals(this._addictionStage2WithdrawalDurationInGameTimeHoursV2, this.addictionStage2WithdrawalDurationInGameTimeHoursV2) {
			this._addictionStage2WithdrawalDurationInGameTimeHoursV2 = this.addictionStage2WithdrawalDurationInGameTimeHoursV2;
			ArrayPush(changedSettings, "addictionStage2WithdrawalDurationInGameTimeHoursV2");
		}

		if NotEquals(this._addictionStage3WithdrawalDurationInGameTimeHoursV2, this.addictionStage3WithdrawalDurationInGameTimeHoursV2) {
			this._addictionStage3WithdrawalDurationInGameTimeHoursV2 = this.addictionStage3WithdrawalDurationInGameTimeHoursV2;
			ArrayPush(changedSettings, "addictionStage3WithdrawalDurationInGameTimeHoursV2");
		}

		if NotEquals(this._addictionStage4WithdrawalDurationInGameTimeHoursV2, this.addictionStage4WithdrawalDurationInGameTimeHoursV2) {
			this._addictionStage4WithdrawalDurationInGameTimeHoursV2 = this.addictionStage4WithdrawalDurationInGameTimeHoursV2;
			ArrayPush(changedSettings, "addictionStage4WithdrawalDurationInGameTimeHoursV2");
		}

		if NotEquals(this._addictionCessationDurationInGameTimeHours, this.addictionCessationDurationInGameTimeHours) {
			this._addictionCessationDurationInGameTimeHours = this.addictionCessationDurationInGameTimeHours;
			ArrayPush(changedSettings, "addictionCessationDurationInGameTimeHours");
		}

		if NotEquals(this._addictionBackoffDurationStage1, this.addictionBackoffDurationStage1) {
			this._addictionBackoffDurationStage1 = this.addictionBackoffDurationStage1;
			ArrayPush(changedSettings, "addictionBackoffDurationStage1");
		}

		if NotEquals(this._addictionBackoffDurationStage2, this.addictionBackoffDurationStage2) {
			this._addictionBackoffDurationStage2 = this.addictionBackoffDurationStage2;
			ArrayPush(changedSettings, "addictionBackoffDurationStage2");
		}

		if NotEquals(this._addictionBackoffDurationStage3, this.addictionBackoffDurationStage3) {
			this._addictionBackoffDurationStage3 = this.addictionBackoffDurationStage3;
			ArrayPush(changedSettings, "addictionBackoffDurationStage3");
		}

		if NotEquals(this._addictionBackoffDurationStage4, this.addictionBackoffDurationStage4) {
			this._addictionBackoffDurationStage4 = this.addictionBackoffDurationStage4;
			ArrayPush(changedSettings, "addictionBackoffDurationStage4");
		}

		if NotEquals(this._injuryConditionEnabled, this.injuryConditionEnabled) {
			this._injuryConditionEnabled = this.injuryConditionEnabled;
			ArrayPush(changedSettings, "injuryConditionEnabled");
		}

		if NotEquals(this._humanityLossConditionEnabled, this.humanityLossConditionEnabled) {
			this._humanityLossConditionEnabled = this.humanityLossConditionEnabled;
			ArrayPush(changedSettings, "humanityLossConditionEnabled");
		}

		if NotEquals(this._biocorruptionConditionEnabled, this.biocorruptionConditionEnabled) {
			this._biocorruptionConditionEnabled = this.biocorruptionConditionEnabled;
			ArrayPush(changedSettings, "biocorruptionConditionEnabled");
		}

		if NotEquals(this._fastTravelSettingV2, this.fastTravelSettingV2) {
			this._fastTravelSettingV2 = this.fastTravelSettingV2;
			ArrayPush(changedSettings, "fastTravelSettingV2");
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

		if NotEquals(this._criticalNeedVFXEnabled, this.criticalNeedVFXEnabled) {
			this._criticalNeedVFXEnabled = this.criticalNeedVFXEnabled;
			ArrayPush(changedSettings, "criticalNeedVFXEnabled");
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

		if NotEquals(this._updateRaceUIVerticalPosition, this.updateRaceUIVerticalPosition) {
			this._updateRaceUIVerticalPosition = this.updateRaceUIVerticalPosition;
			ArrayPush(changedSettings, "updateRaceUIVerticalPosition");
		}

		if NotEquals(this._raceUIVerticalPositionOffset, this.raceUIVerticalPositionOffset) {
			this._raceUIVerticalPositionOffset = this.raceUIVerticalPositionOffset;
			ArrayPush(changedSettings, "raceUIVerticalPositionOffset");
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

		if NotEquals(this._consumableAnimationsEnabled, this.consumableAnimationsEnabled) {
			this._consumableAnimationsEnabled = this.consumableAnimationsEnabled;
			ArrayPush(changedSettings, "consumableAnimationsEnabled");
		}

		if NotEquals(this._consumableAnimationCooldownTimeInRealTimeSeconds, this.consumableAnimationCooldownTimeInRealTimeSeconds) {
			this._consumableAnimationCooldownTimeInRealTimeSeconds = this.consumableAnimationCooldownTimeInRealTimeSeconds;
			ArrayPush(changedSettings, "consumableAnimationCooldownTimeInRealTimeSeconds");
		}

		if NotEquals(this._consumableAnimationCooldownBehavior, this.consumableAnimationCooldownBehavior) {
			this._consumableAnimationCooldownBehavior = this.consumableAnimationCooldownBehavior;
			ArrayPush(changedSettings, "consumableAnimationCooldownBehavior");
		}

		if NotEquals(this._forceFPPWhenSleepingInVehicle, this.forceFPPWhenSleepingInVehicle) {
			this._forceFPPWhenSleepingInVehicle = this.forceFPPWhenSleepingInVehicle;
			ArrayPush(changedSettings, "forceFPPWhenSleepingInVehicle");
		}

		if NotEquals(this._humanityLossCyberpsychosisEnabled, this.humanityLossCyberpsychosisEnabled) {
			this._humanityLossCyberpsychosisEnabled = this.humanityLossCyberpsychosisEnabled;
			ArrayPush(changedSettings, "humanityLossCyberpsychosisEnabled");
		}

		if NotEquals(this._cyberpsychosisSFXEnabled, this.cyberpsychosisSFXEnabled) {
			this._cyberpsychosisSFXEnabled = this.cyberpsychosisSFXEnabled;
			ArrayPush(changedSettings, "cyberpsychosisSFXEnabled");
		}

		if NotEquals(this._cyberpsychosisEffectsRepeatEnabled, this.cyberpsychosisEffectsRepeatEnabled) {
			this._cyberpsychosisEffectsRepeatEnabled = this.cyberpsychosisEffectsRepeatEnabled;
			ArrayPush(changedSettings, "cyberpsychosisEffectsRepeatEnabled");
		}

		if NotEquals(this._cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds, this.cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds) {
			this._cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds = this.cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds;
			ArrayPush(changedSettings, "cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds");
		}

		if NotEquals(this._humanityLossFuryAcceleratedPrevention, this.humanityLossFuryAcceleratedPrevention) {
			this._humanityLossFuryAcceleratedPrevention = this.humanityLossFuryAcceleratedPrevention;
			ArrayPush(changedSettings, "humanityLossFuryAcceleratedPrevention");
		}

		if NotEquals(this._basicNeedThresholdValue1V2, this.basicNeedThresholdValue1V2) {
			this._basicNeedThresholdValue1V2 = this.basicNeedThresholdValue1V2;
			ArrayPush(changedSettings, "basicNeedThresholdValue1V2");
		}

		if NotEquals(this._basicNeedThresholdValue2V2, this.basicNeedThresholdValue2V2) {
			this._basicNeedThresholdValue2V2 = this.basicNeedThresholdValue2V2;
			ArrayPush(changedSettings, "basicNeedThresholdValue2V2");
		}

		if NotEquals(this._basicNeedThresholdValue3V2, this.basicNeedThresholdValue3V2) {
			this._basicNeedThresholdValue3V2 = this.basicNeedThresholdValue3V2;
			ArrayPush(changedSettings, "basicNeedThresholdValue3V2");
		}

		if NotEquals(this._basicNeedThresholdValue4V2, this.basicNeedThresholdValue4V2) {
			this._basicNeedThresholdValue4V2 = this.basicNeedThresholdValue4V2;
			ArrayPush(changedSettings, "basicNeedThresholdValue4V2");
		}

		if NotEquals(this._withdrawalAnimationsEnabled, this.withdrawalAnimationsEnabled) {
			this._withdrawalAnimationsEnabled = this.withdrawalAnimationsEnabled;
			ArrayPush(changedSettings, "withdrawalAnimationsEnabled");
		}

		if NotEquals(this._blackoutEnabled, this.blackoutEnabled) {
			this._blackoutEnabled = this.blackoutEnabled;
			ArrayPush(changedSettings, "blackoutEnabled");
		}

		if NotEquals(this._impairedDrivingEnabled, this.impairedDrivingEnabled) {
			this._impairedDrivingEnabled = this.impairedDrivingEnabled;
			ArrayPush(changedSettings, "impairedDrivingEnabled");
		}

		if NotEquals(this._showConditionsIndicatorHUDUI, this.showConditionsIndicatorHUDUI) {
			this._showConditionsIndicatorHUDUI = this.showConditionsIndicatorHUDUI;
			ArrayPush(changedSettings, "showConditionsIndicatorHUDUI");
		}

		if NotEquals(this._syncConditionsUIWithHealthStamina, this.syncConditionsUIWithHealthStamina) {
			this._syncConditionsUIWithHealthStamina = this.syncConditionsUIWithHealthStamina;
			ArrayPush(changedSettings, "syncConditionsUIWithHealthStamina");
		}

		if NotEquals(this._crashAnimationSetting, this.crashAnimationSetting) {
			this._crashAnimationSetting = this.crashAnimationSetting;
			ArrayPush(changedSettings, "crashAnimationSetting");
		}
		
		if ArraySize(changedSettings) > 0 {
			DFLogNoSystem(this.debugEnabled, this, "        ...the following settings have changed: " + ToString(changedSettings));
			GameInstance.GetCallbackSystem().DispatchEvent(SettingChangedEvent.Create(changedSettings));
		}

		DFLogNoSystem(this.debugEnabled, this, "        ...updating ammo crafting recipe availability...");
		this.ToggleAmmoCrafting(this.ammoCraftingEnabled);

		DFLogNoSystem(this.debugEnabled, this, "        ...done!");
	}

	// -------------------------------------------------------------------------
	// System Settings
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "10")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingMainSystemEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingMainSystemEnabledDesc")
	public let mainSystemEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "10")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTutorialsEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTutorialsEnabledDesc")
	public let tutorialsEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - General
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingReducedCarryWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingReducedCarryWeightDesc")
	@runtimeProperty("ModSettings.displayValues.Full", "DarkFutureReducedCarryWeightAmountFull")
    @runtimeProperty("ModSettings.displayValues.Half", "DarkFutureReducedCarryWeightAmountHalf")
	@runtimeProperty("ModSettings.displayValues.Off", "DarkFutureReducedCarryWeightAmountOff")
	public let reducedCarryWeight: DFReducedCarryWeightAmount = DFReducedCarryWeightAmount.Full;
	
	/*
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingIncreasedStaminaRecoveryTime")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingIncreasedStaminaRecoveryTimeDesc")
	public let increasedStaminaRecoveryTime: Bool = true;
	*/

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingStashCraftingEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingStashCraftingEnabledDesc")
	public let stashCraftingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNoConsumablesInStash")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNoConsumablesInStashDesc")
	public let noConsumablesInStash: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - Fast Travel
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayFastTravel")
	@runtimeProperty("ModSettings.category.order", "30")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingFastTravel")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingFastTravelDesc")
	@runtimeProperty("ModSettings.displayValues.Disabled", "DarkFutureFastTravelDisabled")
	@runtimeProperty("ModSettings.displayValues.DisabledAllowMetro", "DarkFutureFastTravelDisabledAllowMetro")
	@runtimeProperty("ModSettings.displayValues.Enabled", "DarkFutureFastTravelEnabled")
	public let fastTravelSettingV2: DFFastTravelSetting = DFFastTravelSetting.Disabled;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayFastTravel")
	@runtimeProperty("ModSettings.category.order", "30")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHideFastTravelMarkers")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHideFastTravelMarkersDesc")
	public let hideFastTravelMarkers: Bool = true;
	
	// -------------------------------------------------------------------------
	// Gameplay - Vehicle Summoning
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSummoning")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLimitVehicleSummoning")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLimitVehicleSummoningDesc")
	public let limitVehicleSummoning: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSummoning")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingMaxVehicleSummonCredits")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingMaxVehicleSummonCreditsDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "9")
	public let maxVehicleSummonCredits: Int32 = 2;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
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
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSleepingInVehiclesKeybindingMain")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSleepingInVehiclesKeybindingMainDesc")
	public let DFVehicleSleepButtonMain: EInputKey = EInputKey.IK_LShift;
 
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSleepingInVehiclesKeybindingAlt")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSleepingInVehiclesKeybindingAltDesc")
	public let DFVehicleSleepButtonAlt: EInputKey = EInputKey.IK_Pad_DigitRight;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let sleepingInVehiclesAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.dependency", "sleepingInVehiclesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingVehicleSleepQualityCity")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingVehicleSleepQualityCityDesc")
	@runtimeProperty("ModSettings.displayValues.Limited", "DarkFutureSettingSleepQualityLimited")
    @runtimeProperty("ModSettings.displayValues.Full", "DarkFutureSettingSleepQualityFull")
	public let vehicleSleepQualityCity: DFSleepQualitySetting = DFSleepQualitySetting.Limited;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.dependency", "sleepingInVehiclesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingVehicleSleepQualityBadlands")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingVehicleSleepQualityBadlandsDesc")
	@runtimeProperty("ModSettings.displayValues.Limited", "DarkFutureSettingSleepQualityLimited")
    @runtimeProperty("ModSettings.displayValues.Full", "DarkFutureSettingSleepQualityFull")
	public let vehicleSleepQualityBadlandsV2: DFSleepQualitySetting = DFSleepQualitySetting.Full;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.dependency", "sleepingInVehiclesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyLimitSleepInVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyLimitSleepInVehicleDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let limitedEnergySleepingInVehicles: Float = 70.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.dependency", "sleepingInVehiclesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingForceFPPWhenSleepingInVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingForceFPPWhenSleepingInVehicleDesc")
	public let forceFPPWhenSleepingInVehicle: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleeping")
	@runtimeProperty("ModSettings.category.order", "45")
	@runtimeProperty("ModSettings.dependency", "sleepingInVehiclesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowSleepingInVehiclesInputHint")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowSleepingInVehiclesInputHintDesc")
	public let showSleepingInVehiclesInputHint: Bool = true;

	// -------------------------------------------------------------------------
	// Gameplay - Sleep Encounters
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnableRandomEncountersWhenSleepingInVehicles")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnableRandomEncountersWhenSleepingInVehiclesDesc")
	public let enableRandomEncountersWhenSleepingInVehicles: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let randomEncountersAdvancedSettings: Bool = false;
	
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.dependency", "randomEncountersAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceGangDistrict")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceGangDistrictDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceGangDistrict: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.dependency", "randomEncountersAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceCityCenter")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceCityCenterDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceCityCenter: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicleSleepEncounters")
	@runtimeProperty("ModSettings.category.order", "48")
	@runtimeProperty("ModSettings.dependency", "randomEncountersAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRandomEncounterChanceBadlands")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRandomEncounterChanceBadlandsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let randomEncounterChanceBadlandsV2: Float = 10.0;

	// -------------------------------------------------------------------------
	// Survival - Basic Needs
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossIsFatal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossIsFatalDesc")
	public let nerveLossIsFatal: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveWeaponSwayEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveWeaponSwayEnabledDesc")
	public let nerveWeaponSwayEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingImpairedDrivingEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingImpairedDrivingEnabledDesc")
	public let impairedDrivingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBlackoutEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBlackoutEnabledDesc")
	public let blackoutEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let basicNeedsAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let hydrationLossRatePct: Float = 100.0;
	
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nutritionLossRatePct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let energyLossRatePctV2: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateInCombatPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateInCombatPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nerveLossRateInCombatPct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateWhenTracedPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateWhenTracedPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "800.0")
	public let nerveLossRateWhenTracedPct: Float = 200.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBasicNeedThresholdValue1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBasicNeedThresholdValue1Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "4.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let basicNeedThresholdValue1V2: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBasicNeedThresholdValue2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBasicNeedThresholdValue2Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "3.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let basicNeedThresholdValue2V2: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBasicNeedThresholdValue3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBasicNeedThresholdValue3Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "2.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let basicNeedThresholdValue3V2: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.dependency", "basicNeedsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBasicNeedThresholdValue4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBasicNeedThresholdValue4Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let basicNeedThresholdValue4V2: Float = 25.0;

	// -------------------------------------------------------------------------
	// Survival - Addiction
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionEnabledDesc")
	public let addictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let addictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAlcoholAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let alcoholAddictionProgressChanceRev2: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAlcoholAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let alcoholAddictionLossPerDayRev2: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNicotineAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nicotineAddictionProgressChanceRev2: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNicotineAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let nicotineAddictionLossPerDayRev2: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticAddictionProgressChance")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionProgressChanceDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let narcoticAddictionProgressChanceRev2: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticAddictionLossPerDay")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionLossPerDayDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "30.0")
	public let narcoticAddictionLossPerDayRev2: Float = 0.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage1WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let addictionStage1WithdrawalDurationInGameTimeHoursV2: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage2WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let addictionStage2WithdrawalDurationInGameTimeHoursV2: Int32 = 36;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage3WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let addictionStage3WithdrawalDurationInGameTimeHoursV2: Int32 = 48;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionStage4WithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let addictionStage4WithdrawalDurationInGameTimeHoursV2: Int32 = 60;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionCessationDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionCessationDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let addictionCessationDurationInGameTimeHours: Int32 = 48;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage1Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "24.0")
	public let addictionBackoffDurationStage1: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "24.0")
	public let addictionBackoffDurationStage2: Float = 6.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "24.0")
	public let addictionBackoffDurationStage3: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddiction")
	@runtimeProperty("ModSettings.category.order", "52")
	@runtimeProperty("ModSettings.dependency", "addictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "24.0")
	public let addictionBackoffDurationStage4: Float = 4.0;

	// -------------------------------------------------------------------------
	// Survival - Injury
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionInjury")
	@runtimeProperty("ModSettings.category.order", "55")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryConditionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryConditionEnabledDesc")
	public let injuryConditionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionInjury")
	@runtimeProperty("ModSettings.category.order", "55")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryAccumulationRate")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryAccumulationRateDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let injuryHealthLossAccumulationRateRev3: Float = 20.0;

	// -------------------------------------------------------------------------
	// Survival - Humanity Loss
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossConditionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossConditionEnabledDesc")
	public let humanityLossConditionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossCyberpsychosisEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossCyberpsychosisEnabledDesc")
	public let humanityLossCyberpsychosisEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossAccumulationRate")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossAccumulationRateDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "400.0")
	public let humanityLossNerveLossAccumulationRate: Float = 65.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let humanityLossAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenRepeatableMinor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenRepeatableMinorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountRepeatableMinorRev2: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenRepeatableMajor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenRepeatableMajorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountRepeatableMajorRev2: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenRepeatablePivotal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenRepeatablePivotalDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountRepeatablePivotalRev2: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenOneTimeMinor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenOneTimeMinorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountOneTimeMinorRev2: Float = 40.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenOneTimeMajor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenOneTimeMajorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountOneTimeMajorRev2: Float = 60.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenOneTimePivotal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenOneTimePivotalDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossRegenerationAmountOneTimePivotalRev2: Float = 80.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossCostRelicMalfunction")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossCostRelicMalfunctionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossCostAmountRelicMalfunction: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossCostOneTimeMinor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossCostOneTimeMinorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossCostAmountOneTimeMinor: Float = 25.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossCostOneTimeMajor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossCostOneTimeMajorDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossCostAmountOneTimeMajor: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossCostOneTimePivotal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossCostOneTimePivotalDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let humanityLossCostAmountOneTimePivotal: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionHumanityLoss")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.dependency", "humanityLossAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossFuryAcceleratedPrevention")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossFuryAcceleratedPreventionDesc")
	public let humanityLossFuryAcceleratedPrevention: Bool = true;

	// -------------------------------------------------------------------------
	// Survival - Biocorruption
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayConditionBiocorruption")
	@runtimeProperty("ModSettings.category.order", "57")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingBiocorruptionConditionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingBiocorruptionConditionEnabledDesc")
	public let biocorruptionConditionEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Interface
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowHUDUI")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowHUDUIDesc")
	public let showHUDUI: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
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

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
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

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
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

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
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

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowConditionsUI")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowConditionsUIDesc")
	public let showConditionsIndicatorHUDUI: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingConditionsIndicatorHUDUIColorTheme")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingConditionsIndicatorHUDUIColorThemeDesc")
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
	public let conditionsIndicatorHUDUIColorTheme: DFBarColorThemeName = DFBarColorThemeName.MainRed;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let interfaceAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSyncConditionsUIWithHealthStamina")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSyncConditionsUIWithHealthStaminaDesc")
	public let syncConditionsUIWithHealthStamina: Bool = true;
	
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedHUDUIAlwaysOnThreshold")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedHUDUIAlwaysOnThresholdDesc")
	@runtimeProperty("ModSettings.step", "5.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let needHUDUIAlwaysOnThreshold: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHidePersistentStatusIcons")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHidePersistentStatusIconsDesc")
	public let hidePersistentStatusIconsV2: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNewInventoryFilters")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNewInventoryFiltersDesc")
	public let newInventoryFilters: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIMinOpacity")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIMinOpacityDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hudUIMinOpacity: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIScale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIScaleDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "4.0")
	public let hudUIScale: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIPosX")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIPosXDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "3840.0")
	public let hudUIPosX: Float = 70.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHUDUIPosY")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHUDUIPosYDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "2160.0")
	public let hudUIPosY: Float = 240.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateHolocallPosition")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateHolocallPositionDesc")
	public let updateHolocallVerticalPosition: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHolocallVerticalPositionOffset")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHolocallVerticalPositionOffsetDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "1600.0")
	public let holocallVerticalPositionOffset: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateStatusEffectListPosition")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateStatusEffectListPositionDesc")
	public let updateStatusEffectListVerticalPosition: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingStatusEffectListVerticalPositionOffset")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingStatusEffectListVerticalPositionOffsetDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "1600.0")
	public let statusEffectListVerticalPositionOffset: Float = 85.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateRaceUIPosition")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateRaceUIPositionDesc")
	public let updateRaceUIVerticalPosition: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.dependency", "interfaceAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingRaceUIVerticalPositionOffset")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingRaceUIVerticalPositionOffsetDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "1600.0")
	public let raceUIVerticalPositionOffset: Float = 85.0;

	// -------------------------------------------------------------------------
	// Sounds and Visual Effects
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeSFXEnabledDesc")
	public let needNegativeSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedPositiveSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedPositiveSFXEnabledDesc")
	public let needPositiveSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let fxAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatEnabledDesc")
	public let needNegativeEffectsRepeatEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencyModerateInRealTimeSecondsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "1800.0")
	public let needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds: Float = 300.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencySevereInRealTimeSeconds")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedNegativeEffectsRepeatFrequencySevereInRealTimeSecondsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "1800.0")
	public let needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds: Float = 180.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingOutOfBreathEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingOutOfBreathEffectEnabledDesc")
	public let outOfBreathEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLowNerveBreathingEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLowNerveBreathingEffectEnabledDesc")
	public let lowNerveBreathingEffectEnabled: Bool = true;
	
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSFXEnabledDesc")
	public let addictionSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHumanityLossRegenerationSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHumanityLossRegenerationSFXEnabledDesc")
	public let humanityLossRegenerationSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCyberpsychosisSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCyberpsychosisSFXEnabledDesc")
	public let cyberpsychosisSFXEnabled: Bool = true;

	/*@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticsSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNarcoticsSFXEnabledDesc")
	public let narcoticsSFXEnabled: Bool = true;*/

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCriticalNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCriticalNeedVFXEnabledDesc")
	public let criticalNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveNeedVFXEnabledDesc")
	public let nerveNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationNeedVFXEnabledDesc")
	public let hydrationNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionNeedVFXEnabledDesc")
	public let nutritionNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyNeedVFXEnabledDesc")
	public let energyNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCyberpsychosisVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCyberpsychosisVFXEnabledDesc")
	public let cyberpsychosisVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingOutOfBreathCameraEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingOutOfBreathCameraEffectEnabledDesc")
	public let outOfBreathCameraEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCyberpsychosisRepeatFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCyberpsychosisRepeatFXEnabledDesc")
	public let cyberpsychosisEffectsRepeatEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.dependency", "fxAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCyberpsychosisRepeatFXFrequencyInRealTimeSeconds")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCyberpsychosisRepeatFXFrequencyInRealTimeSecondsDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "1800.0")
	public let cyberpsychosisEffectsRepeatFrequencyInRealTimeSeconds: Float = 180.0;

	// -------------------------------------------------------------------------
	// Animations
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryAnimations")
	@runtimeProperty("ModSettings.category.order", "140")
	@runtimeProperty("ModSettings.displayName", "DarkFutureCrashAnimSetting")
	@runtimeProperty("ModSettings.description", "DarkFutureCrashAnimSettingDesc")
	@runtimeProperty("ModSettings.displayValues.On", "DarkFutureCrashAnimSettingOn")
	@runtimeProperty("ModSettings.displayValues.HeadacheOnly", "DarkFutureCrashAnimSettingHeadacheOnly")
	@runtimeProperty("ModSettings.displayValues.Off", "DarkFutureCrashAnimSettingOff")
	public let crashAnimationSetting: DFCrashAnimSetting = DFCrashAnimSetting.On;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryAnimations")
	@runtimeProperty("ModSettings.category.order", "140")
	@runtimeProperty("ModSettings.displayName", "DarkFutureWithdrawalAnimSettingEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureWithdrawalAnimSettingEnabledDesc")
	public let withdrawalAnimationsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryAnimations")
	@runtimeProperty("ModSettings.category.order", "140")
	@runtimeProperty("ModSettings.displayName", "DarkFutureWithdrawalAnimSettingChance")
	@runtimeProperty("ModSettings.description", "DarkFutureWithdrawalAnimSettingChanceDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "0")
	@runtimeProperty("ModSettings.max", "100")
	public let withdrawalAnimationChance: Int32 = 35;

	// -------------------------------------------------------------------------
	// Consumable Animations
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnabled")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnabledDesc")
	public let consumableAnimationsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingLootActionBehavior")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingLootActionBehaviorDesc")
	public let consumableAnimationLootActionEnabled: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationLootActionEnabled")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingLootActionManualKeyKBM")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingLootActionManualKeyKBMDesc")
	public let consumableAnimationLootActionKeyKBM: EInputKey = EInputKey.IK_R;
 
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationLootActionEnabled")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingLootActionManualKeyController")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingLootActionManualKeyControllerDesc")
	public let consumableAnimationLootActionKeyControllerV2: EInputKey = EInputKey.IK_Pad_B_CIRCLE;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingAdvancedSettingsDesc")
	public let consumableAnimationsAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingCooldownTimer")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingCooldownTimerDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "600.0")
	public let consumableAnimationCooldownTimeInRealTimeSeconds: Float = 60.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingCooldownBehavior")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingCooldownBehaviorDesc")
	@runtimeProperty("ModSettings.displayValues.Off", "ConsumableAnimSettingCooldownBehaviorTypeOff")
	@runtimeProperty("ModSettings.displayValues.ByExactVisualProp", "ConsumableAnimSettingCooldownBehaviorTypeByExactVisualProp")
	@runtimeProperty("ModSettings.displayValues.ByGeneralVisualProp", "ConsumableAnimSettingCooldownBehaviorTypeByGeneralVisualProp")
	@runtimeProperty("ModSettings.displayValues.ByVisualPropType", "ConsumableAnimSettingCooldownBehaviorTypeByVisualPropType")
    @runtimeProperty("ModSettings.displayValues.ByAnimationType", "ConsumableAnimSettingCooldownBehaviorTypeByAnimationType")
	@runtimeProperty("ModSettings.displayValues.All", "ConsumableAnimSettingCooldownBehaviorTypeAll")
	public let consumableAnimationCooldownBehavior: DFConsumableAnimationCooldownBehavior = DFConsumableAnimationCooldownBehavior.ByGeneralVisualProp;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingQueueDepth")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingQueueDepthDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "5")
	public let consumableAnimationQueueDepth: Int32 = 2;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingUniqueItemsIgnoreCooldown")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingUniqueItemsIgnoreCooldownDesc")
	public let consumableAnimationsUniqueItemsIgnoreCooldown: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingDrugsIgnoreCooldown")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingDrugsIgnoreCooldownDesc")
	public let consumableAnimationsDrugsIgnoreCooldown: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingPharmaceuticalsIgnoreCooldown")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingPharmaceuticalsIgnoreCooldownDesc")
	public let consumableAnimationsPharmaceuticalsIgnoreCooldown: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingAlcoholIgnoreCooldown")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingAlcoholIgnoreCooldownDesc")
	public let consumableAnimationsAlcoholIgnoreCooldown: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationEatDrinkThinPackagedLeftHand")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsEatDrinkThinPackagedLeftHandEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationEatLookDownRightHand")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsEatLookDownRightHandEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationDrinkSipRightHand")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsDrinkSipRightHandEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationDrinkChugLeftHand")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsDrinkChugLeftHandEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationTraumaKit")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsTraumaKitEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationSmoking")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsSmokingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationPill")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsPillEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationInhaler")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsInhalerEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "ConsumableAnimSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "145")
	@runtimeProperty("ModSettings.dependency", "consumableAnimationsAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "ConsumableAnimSettingEnableAnimationMrWhitey")
	@runtimeProperty("ModSettings.description", "ConsumableAnimSettingEnableAnimationDesc")
	public let consumableAnimationsMrWhiteyEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Relax Action
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "RelaxActionSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "146")
	@runtimeProperty("ModSettings.displayName", "RelaxActionSettingEnabled")
	@runtimeProperty("ModSettings.description", "RelaxActionSettingEnabledDesc")
	public let relaxActionHotkeyEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "RelaxActionSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "146")
	@runtimeProperty("ModSettings.dependency", "relaxActionHotkeyEnabled")
	@runtimeProperty("ModSettings.displayName", "RelaxActionSettingKeyKBM")
	@runtimeProperty("ModSettings.description", "RelaxActionSettingKeyKBMDesc")
	public let relaxActionKeyKBM: EInputKey = EInputKey.IK_LControl;
 
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "RelaxActionSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "146")
	@runtimeProperty("ModSettings.dependency", "relaxActionHotkeyEnabled")
	@runtimeProperty("ModSettings.displayName", "RelaxActionSettingKeyController")
	@runtimeProperty("ModSettings.description", "RelaxActionSettingKeyControllerDesc")
	public let relaxActionKeyController: EInputKey = EInputKey.IK_Pad_LeftThumb;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "RelaxActionSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "146")
	@runtimeProperty("ModSettings.dependency", "relaxActionHotkeyEnabled")
	@runtimeProperty("ModSettings.displayName", "RelaxActionSettingShowInputHint")
	@runtimeProperty("ModSettings.description", "RelaxActionSettingShowInputHintDesc")
	public let relaxActionShowInputHint: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "RelaxActionSettingsCategoryMain")
	@runtimeProperty("ModSettings.category.order", "146")
	@runtimeProperty("ModSettings.dependency", "relaxActionHotkeyEnabled")
	@runtimeProperty("ModSettings.displayName", "RelaxActionSettingMultiStep")
	@runtimeProperty("ModSettings.description", "RelaxActionSettingMultiStepDesc")
	public let relaxActionEnableMultiStepConsumption: Bool = true;

	// -------------------------------------------------------------------------
	// Notifications
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryNotifications")
	@runtimeProperty("ModSettings.category.order", "147")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNeedMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNeedMessagesEnabledDesc")
	public let needMessagesEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryNotifications")
	@runtimeProperty("ModSettings.category.order", "147")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMessagesEnabledDesc")
	public let addictionMessagesEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryNotifications")
	@runtimeProperty("ModSettings.category.order", "147")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingConditionMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingConditionMessagesEnabledDesc")
	public let conditionMessagesEnabled: Bool = true;

	// -------------------------------------------------------------------------
	// Misc
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "160")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingUpdateMessagesEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingUpdateMessagesEnabledDesc")
	public let upgradeMessagesEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "160")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingForceShowUpdateMessage")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingForceShowUpdateMessageDesc")
	public let forceShowUpgradeMessageOnNewGame: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "160")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTimescale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTimescaleDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "40.0")
	public let timescale: Float = 8.0;

	// -------------------------------------------------------------------------
	// Compatibility
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let compatibilityAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnSleepVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnSleepVehicleDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
    @runtimeProperty("ModSettings.displayValues.TurnOff", "DarkFutureCompatEVSPowerBehaviorTurnOff")
	@runtimeProperty("ModSettings.displayValues.TurnOn", "DarkFutureCompatEVSPowerBehaviorTurnOn")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorOnSleep: EnhancedVehicleSystemCompatPowerBehaviorDriver = EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOff;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnWakeVehicle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorOnWakeVehicleDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
	@runtimeProperty("ModSettings.displayValues.TurnOff", "DarkFutureCompatEVSPowerBehaviorTurnOff")
    @runtimeProperty("ModSettings.displayValues.TurnOn", "DarkFutureCompatEVSPowerBehaviorTurnOn")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorOnWake: EnhancedVehicleSystemCompatPowerBehaviorDriver = EnhancedVehicleSystemCompatPowerBehaviorDriver.TurnOn;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityEnhancedVehicleSystemPowerBehaviorAsPassengerDesc")
	@runtimeProperty("ModSettings.displayValues.DoNothing", "DarkFutureCompatEVSPowerBehaviorDoNothing")
	@runtimeProperty("ModSettings.displayValues.SameAsDriver", "DarkFutureCompatEVSPowerBehaviorSameAsDriver")
	public let compatibilityEnhancedVehicleSystemPowerBehaviorAsPassenger: EnhancedVehicleSystemCompatPowerBehaviorPassenger = EnhancedVehicleSystemCompatPowerBehaviorPassenger.SameAsDriver;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityWannabeEdgerunner")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityWannabeEdgerunnerDesc")
	public let compatibilityWannabeEdgerunner: Bool = true;
	
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityProjectE3HUD")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityProjectE3HUDDesc")
	public let compatibilityProjectE3HUD: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryCompatibility")
	@runtimeProperty("ModSettings.category.order", "165")
	@runtimeProperty("ModSettings.dependency", "compatibilityAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCompatibilityProjectE3UI")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCompatibilityProjectE3UIDesc")
	public let compatibilityProjectE3UI: Bool = false;

	// -------------------------------------------------------------------------
	// Advanced - Consumable Restoration
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let consumableRestorationAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier1: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier2: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsHydrationTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationHydrationDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let hydrationTier3: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier1: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier2: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier3: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNutritionTier4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNutritionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nutritionTier4: Float = 30.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyCaffeineTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyCaffeineTier1: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyNicotineTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyNicotineTier1: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyNarcoticTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyNarcoticTier1: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsEnergyAlcoholTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsCostEnergyDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let energyAlcoholTier1: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier1")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveAlcoholInteractionDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier1Rev4: Float = 8.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier2Rev4: Float = 9.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveAlcoholTier3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveAlcoholTier3Rev4: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveCigarettes")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveCigarettesRev3: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveNarcotics")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveNarcoticsRev2: Float = 12.0;

	/*@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNerveNarcoticsPotent")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsRestorationNerveDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveStrongNarcoticsRev3: Float = 35.0;
	*/

	/*@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNervePenaltyFactor")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsNervePenaltyFactorDesc")
	@runtimeProperty("ModSettings.step", "10.0")
	@runtimeProperty("ModSettings.min", "10.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveLowQualityConsumablePenaltyFactor: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableRestoration")
	@runtimeProperty("ModSettings.category.order", "170")
	@runtimeProperty("ModSettings.dependency", "consumableRestorationAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsNervePenaltyLimit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsNervePenaltyLimitDesc")
	@runtimeProperty("ModSettings.step", "1.0")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "100.0")
	public let nerveLowQualityConsumablePenaltyLimit: Float = 70.0;*/

	// -------------------------------------------------------------------------
	// Advanced - Consumable Weight
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let consumableWeightAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsConsumablesModifyWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsEconomicDesc")
	@runtimeProperty("ModSettings.displayValues.DontModify", "DarkFutureSettingItemsEconomicDontModify")
	@runtimeProperty("ModSettings.displayValues.Modify", "DarkFutureSettingItemsEconomicModify")
	public let consumableWeightsModify: DFEconomicSetting = DFEconomicSetting.Modify;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodVerySmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodVerySmall: Float = 0.6;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodSmall: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodMedium")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodMedium: Float = 1.2;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightFoodLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightFoodLarge: Float = 1.6;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrinkSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrinkSmall: Float = 0.8;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrinkLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrinkLarge: Float = 1.2;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugSmall")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugSmall: Float = 0.3;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugMedium")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugMedium: Float = 0.6;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugLarge")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightDrugLarge: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumableWeight")
	@runtimeProperty("ModSettings.category.order", "180")
	@runtimeProperty("ModSettings.dependency", "consumableWeightAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightDrugTraumaKit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "10.0")
	public let weightTraumaKit: Float = 2.0;

	// -------------------------------------------------------------------------
	// Advanced - Consumable Prices
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let consumablePricesAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsConsumablesModifyPrice")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsEconomicDesc")
	@runtimeProperty("ModSettings.displayValues.DontModify", "DarkFutureSettingItemsEconomicDontModify")
	@runtimeProperty("ModSettings.displayValues.Modify", "DarkFutureSettingItemsEconomicModify")
	public let consumablePricesModify: DFEconomicSetting = DFEconomicSetting.Modify;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkNomad")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkNomad: Float = 0.65;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkCommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkCommon: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkUncommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkUncommon: Float = 1.25;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkRare")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkRare: Float = 2.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkEpic")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkEpic: Float = 4.4;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkLegendary")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkLegendary: Float = 10.25;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrinkIllegal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceDrinkIllegal: Float = 31.25;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodNomad")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodNomad: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonSmallSnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonSnackSmall: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonLargeSnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonSnackLarge: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodCommonMeal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodCommonMeal: Float = 2.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodUncommon")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodUncommon: Float = 3.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodRare")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodRare: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodEpic")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodEpic: Float = 9.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodLegendarySnack")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodIllegalSnack: Float = 50.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceFoodLegendaryMeal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "100.0")
	public let priceFoodIllegalMeal: Float = 75.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholLowQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceAlcoholLowQuality: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholMediumQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceAlcoholMediumQuality: Float = 2.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholGoodQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceAlcoholGoodQuality: Float = 3.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholTopQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceAlcoholTopQuality: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAlcoholExquisiteQuality")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceAlcoholExquisiteQuality: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceCigarettes")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceCigarettes: Float = 5.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceMrWhitey")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "20.0")
	public let priceMrWhitey: Float = 7.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPricePharmaceuticals")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "10.0")
	public let pricePharmaceuticals: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceDrugsIllegal")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceIllegalDrugs: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsConsumablePrice")
	@runtimeProperty("ModSettings.category.order", "185")
	@runtimeProperty("ModSettings.dependency", "consumablePricesAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceEndotrisine")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.05")
	@runtimeProperty("ModSettings.min", "0.05")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceEndotrisine: Float = 1.0;

	// -------------------------------------------------------------------------
	// Advanced - Ammo
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAdvancedSettingsDesc")
	public let ammoAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsAmmoWeightDesc")
	@runtimeProperty("ModSettings.displayValues.Disabled", "DarkFutureSettingItemsAmmoWeightDisabled")
    @runtimeProperty("ModSettings.displayValues.EnabledLimitedAmmo", "DarkFutureSettingItemsAmmoWeightEnabledLimitedAmmo")
	@runtimeProperty("ModSettings.displayValues.EnabledUnlimitedAmmo", "DarkFutureSettingItemsAmmoWeightEnabledUnlimitedAmmo")
	public let ammoWeightEnabledV2: DFAmmoWeightSetting = DFAmmoWeightSetting.Disabled;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoCrafting")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsAmmoCraftingDesc")
	public let ammoCraftingEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoHandicapDrops")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsAmmoHandicapDropsDesc")
	@runtimeProperty("ModSettings.displayValues.DontModify", "DarkFutureSettingItemsAmmoHandicapDropsDontModify")
    @runtimeProperty("ModSettings.displayValues.Disabled", "DarkFutureSettingItemsAmmoHandicapDropsDisabled")
	@runtimeProperty("ModSettings.displayValues.Enabled", "DarkFutureSettingItemsAmmoHandicapDropsEnabled")
	public let ammoHandicapDrops: DFAmmoHandicapSetting = DFAmmoHandicapSetting.DontModify;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoHandgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightHandgunAmmo: Float = 0.01;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoRifle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightRifleAmmo: Float = 0.01;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoShotgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightShotgunAmmo: Float = 0.03;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsWeightAmmoSniper")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsWeightGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.01")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "0.5")
	public let weightSniperAmmo: Float = 0.05;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsAmmoModifyPrice")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsEconomicDesc")
	@runtimeProperty("ModSettings.displayValues.DontModify", "DarkFutureSettingItemsEconomicDontModify")
	@runtimeProperty("ModSettings.displayValues.Modify", "DarkFutureSettingItemsEconomicModify")
	public let ammoPriceModify: DFEconomicSetting = DFEconomicSetting.Modify;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoHandgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceHandgunAmmo: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoRifle")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceRifleAmmo: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoShotgun")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceShotgunAmmo: Float = 1.5;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoSniper")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceSniperAmmo: Float = 2.0;

	@runtimeProperty("ModSettings.mod", "DarkFutureSettingsModName")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryItemsAmmo")
	@runtimeProperty("ModSettings.category.order", "190")
	@runtimeProperty("ModSettings.dependency", "ammoAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingItemsPriceAmmoSell")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingItemsPriceGeneralDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "0.1")
	@runtimeProperty("ModSettings.max", "10.0")
	public let priceAmmoSellMult: Float = 0.5;
}

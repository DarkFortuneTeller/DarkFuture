// -----------------------------------------------------------------------------
// DFSettings
// -----------------------------------------------------------------------------
//
// - Mod Settings configuration.
//

module DarkFuture.Settings

import DarkFuture.Logging.*
import DarkFuture.Utils.DFBarColorThemeName

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
	FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener registration aborted.");
}
@if(!ModuleExists("ModSettingsModule")) 
public func UnregisterDFSettingsListener(listener: ref<IScriptable>) {
	FTLog("WARN: Mod Settings was not installed, or not installed correctly; listener unregistration aborted.");
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
	private let debugEnabled: Bool = true;

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
	private let _reducedCarryWeight: Bool = true;
	private let _alcoholAddictionEnabled: Bool = true;
	private let _alcoholAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _alcoholAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _alcoholAddictionMinAmountStage1: Float = 6.0;
	private let _alcoholAddictionMinAmountStage2: Float = 12.0;
	private let _alcoholAddictionMinAmountStage3: Float = 18.0;
	private let _alcoholAddictionMinAmountStage4: Float = 24.0;
	private let _alcoholAddictionBackoffDurationStage1: Float = 20.0;
	private let _alcoholAddictionBackoffDurationStage2: Float = 15.0;
	private let _alcoholAddictionBackoffDurationStage3: Float = 10.0;
	private let _alcoholAddictionBackoffDurationStage4: Float = 5.0;
	private let _nicotineAddictionEnabled: Bool = true;
	private let _nicotineAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _nicotineAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _nicotineAddictionMinAmountStage1: Float = 4.0;
	private let _nicotineAddictionMinAmountStage2: Float = 8.0;
	private let _nicotineAddictionMinAmountStage3: Float = 12.0;
	private let _nicotineAddictionMinAmountStage4: Float = 16.0;
	private let _nicotineAddictionBackoffDurationStage1: Float = 20.0;
	private let _nicotineAddictionBackoffDurationStage2: Float = 15.0;
	private let _nicotineAddictionBackoffDurationStage3: Float = 10.0;
	private let _nicotineAddictionBackoffDurationStage4: Float = 5.0;
	private let _narcoticAddictionEnabled: Bool = true;
	private let _narcoticAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;
	private let _narcoticAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;
	private let _narcoticAddictionMinAmountStage1: Float = 3.0;
	private let _narcoticAddictionMinAmountStage2: Float = 5.0;
	private let _narcoticAddictionMinAmountStage3: Float = 7.0;
	private let _narcoticAddictionMinAmountStage4: Float = 9.0;
	private let _narcoticAddictionBackoffDurationStage1: Float = 20.0;
	private let _narcoticAddictionBackoffDurationStage2: Float = 15.0;
	private let _narcoticAddictionBackoffDurationStage3: Float = 10.0;
	private let _narcoticAddictionBackoffDurationStage4: Float = 5.0;
	private let _injuryAfflictionEnabled: Bool = true;
	private let _traumaAfflictionEnabled: Bool = true;
	private let _fastTravelDisabled: Bool = true;
	private let _limitVehicleSummoning: Bool = true;
	private let _maxVehicleSummonCredits: Int32 = 2;
	private let _hoursPerSummonCredit: Int32 = 8;
	private let _nerveLossIsFatal: Bool = true;
	private let _nerveWeaponSwayEnabled: Bool = true;
	private let _criticalNerveVFXEnabled: Bool = true;
	private let _needNegativeEffectsRepeatEnabled: Bool = true;
	private let _needNegativeEffectsRepeatFrequencyModerateInRealTimeSeconds: Float = 300.0;
	private let _needNegativeEffectsRepeatFrequencySevereInRealTimeSeconds: Float = 180.0;
	private let _lowNerveBreathingEffectEnabled: Bool = true;
	private let _showNeedStatusIcons: Bool = true;
	private let _timescale: Float = 8.0;
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

	public final func ReconcileSettings() -> Void {
		DFLog(true, this, "Beginning Settings Reconciliation...");
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

		if NotEquals(this._alcoholAddictionMildWithdrawalDurationInGameTimeHours, this.alcoholAddictionMildWithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionMildWithdrawalDurationInGameTimeHours = this.alcoholAddictionMildWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionMildWithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._alcoholAddictionSevereWithdrawalDurationInGameTimeHours, this.alcoholAddictionSevereWithdrawalDurationInGameTimeHours) {
			this._alcoholAddictionSevereWithdrawalDurationInGameTimeHours = this.alcoholAddictionSevereWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "alcoholAddictionSevereWithdrawalDurationInGameTimeHours");
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

		if NotEquals(this._nicotineAddictionMildWithdrawalDurationInGameTimeHours, this.nicotineAddictionMildWithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionMildWithdrawalDurationInGameTimeHours = this.nicotineAddictionMildWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionMildWithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._nicotineAddictionSevereWithdrawalDurationInGameTimeHours, this.nicotineAddictionSevereWithdrawalDurationInGameTimeHours) {
			this._nicotineAddictionSevereWithdrawalDurationInGameTimeHours = this.nicotineAddictionSevereWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "nicotineAddictionSevereWithdrawalDurationInGameTimeHours");
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

		if NotEquals(this._narcoticAddictionMildWithdrawalDurationInGameTimeHours, this.narcoticAddictionMildWithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionMildWithdrawalDurationInGameTimeHours = this.narcoticAddictionMildWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionMildWithdrawalDurationInGameTimeHours");
		}

		if NotEquals(this._narcoticAddictionSevereWithdrawalDurationInGameTimeHours, this.narcoticAddictionSevereWithdrawalDurationInGameTimeHours) {
			this._narcoticAddictionSevereWithdrawalDurationInGameTimeHours = this.narcoticAddictionSevereWithdrawalDurationInGameTimeHours;
			ArrayPush(changedSettings, "narcoticAddictionSevereWithdrawalDurationInGameTimeHours");
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

		if NotEquals(this._traumaAfflictionEnabled, this.traumaAfflictionEnabled) {
			this._traumaAfflictionEnabled = this.traumaAfflictionEnabled;
			ArrayPush(changedSettings, "traumaAfflictionEnabled");
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

		if NotEquals(this._nerveWeaponSwayEnabled, this.nerveWeaponSwayEnabled) {
			this._nerveWeaponSwayEnabled = this.nerveWeaponSwayEnabled;
			ArrayPush(changedSettings, "nerveWeaponSwayEnabled");
		}

		if NotEquals(this._criticalNerveVFXEnabled, this.criticalNerveVFXEnabled) {
			this._criticalNerveVFXEnabled = this.criticalNerveVFXEnabled;
			ArrayPush(changedSettings, "criticalNerveVFXEnabled");
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

		if NotEquals(this._showNeedStatusIcons, this.showNeedStatusIcons) {
			this._showNeedStatusIcons = this.showNeedStatusIcons;
			ArrayPush(changedSettings, "showNeedStatusIcons");
		}

		if NotEquals(this._timescale, this.timescale) {
			this._timescale = this.timescale;
			ArrayPush(changedSettings, "timescale");
		}

		if ArraySize(changedSettings) > 0 {
			DFLog(true, this, "        ...the following settings have changed: " + ToString(changedSettings));
			GameInstance.GetCallbackSystem().DispatchEvent(SettingChangedEvent.Create(changedSettings));
		}

		DFLog(true, this, "        ...done!");
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
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingIncreasedStaminaRecoveryTime")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingIncreasedStaminaRecoveryTimeDesc")
	public let increasedStaminaRecoveryTime: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayGeneral")
	@runtimeProperty("ModSettings.category.order", "20")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingReducedCarryWeight")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingReducedCarryWeightDesc")
	public let reducedCarryWeight: Bool = true;

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
	// Fast Travel
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
	// Vehicle Summoning
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicles")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLimitVehicleSummoning")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLimitVehicleSummoningDesc")
	public let limitVehicleSummoning: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicles")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingMaxVehicleSummonCredits")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingMaxVehicleSummonCreditsDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "9")
	public let maxVehicleSummonCredits: Int32 = 2;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayVehicles")
	@runtimeProperty("ModSettings.category.order", "40")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHoursPerSummonCredit")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHoursPerSummonCreditDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "24")
	public let hoursPerSummonCredit: Int32 = 8;

	// -------------------------------------------------------------------------
	// Gameplay - Basic Needs
	// -------------------------------------------------------------------------
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

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let hydrationLossRatePct: Float = 100.0;
	
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let nutritionLossRatePct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyLossRatePct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyLossRatePctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let energyLossRatePct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateInDangerPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateInDangerPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let nerveLossRateInDangerPct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateHeatPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateHeatPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let nerveLossRateHeatPct: Float = 100.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayBasicNeeds")
	@runtimeProperty("ModSettings.category.order", "50")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveLossRateInWithdrawalPct")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveLossRateInWithdrawalPctDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.0")
	@runtimeProperty("ModSettings.max", "400.0")
	public let nerveLossRateInWithdrawalPct: Float = 100.0;

	// -------------------------------------------------------------------------
	// Gameplay - Alcohol Addiction
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
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAdvancedSettingsDesc")
	public let alcoholAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let alcoholAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;

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
	public let alcoholAddictionBackoffDurationStage1: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage2: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage3: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionAlcohol")
	@runtimeProperty("ModSettings.category.order", "60")
	@runtimeProperty("ModSettings.dependency", "alcoholAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let alcoholAddictionBackoffDurationStage4: Float = 5.0;

	// -------------------------------------------------------------------------
	// Gameplay - Nicotine Addiction
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
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAdvancedSettingsDesc")
	public let nicotineAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let nicotineAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;

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
	public let nicotineAddictionBackoffDurationStage1: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage2: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage3: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNicotine")
	@runtimeProperty("ModSettings.category.order", "70")
	@runtimeProperty("ModSettings.dependency", "nicotineAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let nicotineAddictionBackoffDurationStage4: Float = 5.0;

	// -------------------------------------------------------------------------
	// Gameplay - Narcotic Addiction
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
	@runtimeProperty("ModSettings.step", "0.25")
	@runtimeProperty("ModSettings.min", "0.25")
	@runtimeProperty("ModSettings.max", "4.0")
	public let narcoticAddictionAmountOnUseLow: Float = 1.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "8")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAmountOnUseNarcoticHigh")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAmountOnUseNarcoticHighDesc")
	@runtimeProperty("ModSettings.step", "0.25")
	@runtimeProperty("ModSettings.min", "0.25")
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
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionAdvancedSettingsDesc")
	public let narcoticAddictionAdvancedSettings: Bool = false;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionMildWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionMildWithdrawalDurationInGameTimeHours: Int32 = 24;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHours")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSevereWithdrawalDurationInGameTimeHoursDesc")
	@runtimeProperty("ModSettings.step", "1")
	@runtimeProperty("ModSettings.min", "1")
	@runtimeProperty("ModSettings.max", "72")
	public let narcoticAddictionSevereWithdrawalDurationInGameTimeHours: Int32 = 48;

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
	public let narcoticAddictionBackoffDurationStage1: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage2Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage2: Float = 15.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage3")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage3Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage3: Float = 10.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAddictionNarcotic")
	@runtimeProperty("ModSettings.category.order", "80")
	@runtimeProperty("ModSettings.dependency", "narcoticAddictionAdvancedSettings")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionBackoffDurationStage4")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionBackoffDurationStage4Desc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "120.0")
	public let narcoticAddictionBackoffDurationStage4: Float = 5.0;

	// -------------------------------------------------------------------------
	// Gameplay - Injury
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionInjury")
	@runtimeProperty("ModSettings.category.order", "90")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryAfflictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryAfflictionEnabledDesc")
	public let injuryAfflictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionInjury")
	@runtimeProperty("ModSettings.category.order", "90")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingInjuryAccumulationRate")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingInjuryAccumulationRateDesc")
	@runtimeProperty("ModSettings.step", "0.5")
	@runtimeProperty("ModSettings.min", "0.5")
	@runtimeProperty("ModSettings.max", "100.0")
	public let injuryHealthLossAccumulationRate: Float = 5.0;

	// -------------------------------------------------------------------------
	// Gameplay - Trauma
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionTrauma")
	@runtimeProperty("ModSettings.category.order", "100")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTraumaAfflictionEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTraumaAfflictionEnabledDesc")
	public let traumaAfflictionEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionTrauma")
	@runtimeProperty("ModSettings.category.order", "100")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTraumaAccumulationRateNerveStage2")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTraumaAccumulationRateNerveStage2Desc")
	@runtimeProperty("ModSettings.step", "0.25")
	@runtimeProperty("ModSettings.min", "0.25")
	@runtimeProperty("ModSettings.max", "100.0")
	public let traumaAccumulationRateNerveStage2: Float = 20.0;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryGameplayAfflictionTrauma")
	@runtimeProperty("ModSettings.category.order", "100")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTraumaAccumulationRateNerveStage3Plus")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTraumaAccumulationRateNerveStage3PlusDesc")
	@runtimeProperty("ModSettings.step", "0.25")
	@runtimeProperty("ModSettings.min", "0.25")
	@runtimeProperty("ModSettings.max", "100.0")
	public let traumaAccumulationRateNerveStage3Plus: Float = 50.0;

	// -------------------------------------------------------------------------
	// Interface
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryUI")
	@runtimeProperty("ModSettings.category.order", "110")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingShowNeedStatusIcons")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingShowNeedStatusIconsDesc")
	public let showNeedStatusIcons: Bool = true;

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
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingAddictionSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingAddictionSFXEnabledDesc")
	public let addictionSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLowHydrationBreathingEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLowHydrationBreathingEffectEnabledDesc")
	public let lowHydrationBreathingEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLowNerveBreathingEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLowNerveBreathingEffectEnabledDesc")
	public let lowNerveBreathingEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNarcoticsSFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNarcoticsSFXEnabledDesc")
	public let narcoticsSFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNerveNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNerveNeedVFXEnabledDesc")
	public let nerveNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingCriticalNerveVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingCriticalNerveVFXEnabledDesc")
	public let criticalNerveVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingHydrationNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingHydrationNeedVFXEnabledDesc")
	public let hydrationNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingNutritionNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingNutritionNeedVFXEnabledDesc")
	public let nutritionNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingEnergyNeedVFXEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingEnergyNeedVFXEnabledDesc")
	public let energyNeedVFXEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingLowHydrationCameraEffectEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingLowHydrationCameraEffectEnabledDesc")
	public let lowHydrationCameraEffectEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingSmokingEffectsEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingSmokingEffectsEnabledDesc")
	public let smokingEffectsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryFX")
	@runtimeProperty("ModSettings.category.order", "120")
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
	// Misc
	// -------------------------------------------------------------------------
	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "140")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTutorialsEnabled")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTutorialsEnabledDesc")
	public let tutorialsEnabled: Bool = true;

	@runtimeProperty("ModSettings.mod", "Dark Future")
	@runtimeProperty("ModSettings.category", "DarkFutureSettingsCategoryMisc")
	@runtimeProperty("ModSettings.category.order", "140")
	@runtimeProperty("ModSettings.displayName", "DarkFutureSettingTimescale")
	@runtimeProperty("ModSettings.description", "DarkFutureSettingTimescaleDesc")
	@runtimeProperty("ModSettings.step", "0.1")
	@runtimeProperty("ModSettings.min", "1.0")
	@runtimeProperty("ModSettings.max", "40.0")
	public let timescale: Float = 8.0;
}

// -----------------------------------------------------------------------------
// DFTimeskipMenuUI
// -----------------------------------------------------------------------------
//
// - Handles the UI meters in the Timeskip Menu.
//

import DarkFuture.Logging.*
import DarkFuture.Settings.{
	DFSettings,
	DFSleepQualitySetting
}
import DarkFuture.Main.{
	DFMainSystem,
	DFNeedsDatum,
	DFAddictionDatum,
	DFNeedChangeDatum,
	DFFutureHoursData,
	DFTimeSkipData,
	DFTimeSkipType,
	DFHumanityLossDatum
}
import DarkFuture.Services.DFGameStateService
import DarkFuture.Gameplay.{
	DFInteractionSystem,
	DFVehicleSleepSystem
}
import DarkFuture.Needs.{
	DFHydrationSystem,
	DFNutritionSystem,
	DFEnergySystem,
	DFNerveSystem
}
import DarkFuture.UI.{
	DFNeedsMenuBar,
	DFNeedsMenuBarSetupData
}
import DarkFuture.Utils.{
	DFIsSleeping,
	IsPlayerInBadlands,
	DFHDRColor,
	GetDarkFutureHDRColor
}

@addField(TimeskipGameController)
private let GameStateService: wref<DFGameStateService>;

@addField(TimeskipGameController)
private let Settings: wref<DFSettings>;

@addField(TimeskipGameController)
private let MainSystem: wref<DFMainSystem>;

@addField(TimeskipGameController)
private let InteractionSystem: wref<DFInteractionSystem>;

@addField(TimeskipGameController)
private let VehicleSleepSystem: wref<DFVehicleSleepSystem>;

@addField(TimeskipGameController)
private let HydrationSystem: wref<DFHydrationSystem>;

@addField(TimeskipGameController)
private let NutritionSystem: wref<DFNutritionSystem>;

@addField(TimeskipGameController)
private let EnergySystem: wref<DFEnergySystem>;

@addField(TimeskipGameController)
private let NerveSystem: wref<DFNerveSystem>;

@addField(TimeskipGameController)
private let barCluster: ref<inkVerticalPanel>;

@addField(TimeskipGameController)
private let nerveBar: ref<DFNeedsMenuBar>;

@addField(TimeskipGameController)
private let energyBar: ref<DFNeedsMenuBar>;

@addField(TimeskipGameController)
private let nutritionBar: ref<DFNeedsMenuBar>;

@addField(TimeskipGameController)
private let hydrationBar: ref<DFNeedsMenuBar>;

@addField(TimeskipGameController)
private let calculatedFutureValues: DFFutureHoursData;

@addField(TimeskipGameController)
private let timeSkipType: DFTimeSkipType;

@addField(TimeskipGameController)
private let timeskipAllowed: Bool = true;

@addField(TimeskipGameController)
private let timeskipAllowedReasonLabel: wref<inkText>;

//
//	Base Game Methods
//
//  HubTimeSkipController - Time Skip Button Press
//
@wrapMethod(HubTimeSkipController)
protected cb func OnTimeSkipButtonPressed(e: ref<inkPointerEvent>) -> Bool {
	//DFProfile();
	if e.IsAction(n"click") {
		DFInteractionSystem.GetInstance(GetGameInstance()).SetSkippingTimeFromHubMenu(true);
	}
	
	return wrappedMethod(e);
}


//	TimeskipGameController - Initialization
//
@wrapMethod(TimeskipGameController)
protected cb func OnInitialize() -> Bool {
	//DFProfile();
	let gameInstance = GetGameInstance();

	this.Settings = DFSettings.GetInstance(gameInstance);
	this.MainSystem = DFMainSystem.GetInstance(gameInstance);
	this.GameStateService = DFGameStateService.GetInstance(gameInstance);
	this.InteractionSystem = DFInteractionSystem.GetInstance(gameInstance);
	this.VehicleSleepSystem = DFVehicleSleepSystem.GetInstance(gameInstance);
	this.HydrationSystem = DFHydrationSystem.GetInstance(gameInstance);
	this.NutritionSystem = DFNutritionSystem.GetInstance(gameInstance);
	this.EnergySystem = DFEnergySystem.GetInstance(gameInstance);
	this.NerveSystem = DFNerveSystem.GetInstance(gameInstance);
	
	if this.Settings.mainSystemEnabled {
		this.MainSystem.DispatchTimeSkipStartEvent();
		this.timeSkipType = this.GetTimeskipType(this.NerveSystem.GetNeedStage());
		this.calculatedFutureValues = this.InteractionSystem.GetCalculatedValuesForFutureHours(this.timeSkipType);
	}

	let value: Bool = wrappedMethod();
	let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();

	this.CreateNeedsBarCluster(root.GetWidget(n"container") as inkCanvas);
	this.CreateTimeskipAllowedReasonWidget(root);
	this.SetOriginalValuesInUI();
	this.UpdateAllBarsAppearance();
	this.UpdateUI();
    
	return value;
}

// TimeskipGameController - Disable the Confirm button if TimeSkip is not allowed.
//
@wrapMethod(TimeskipGameController)
protected cb func OnGlobalInput(e: ref<inkPointerEvent>) -> Bool {
	//DFProfile();
	if e.IsHandled() {
      return false;
    };
    if e.IsAction(n"click") || e.IsAction(n"one_click_confirm") {
		if this.Settings.mainSystemEnabled {
			if this.timeskipAllowed {
				return wrappedMethod(e);
			} else {
				// Time skip is not allowed.
			}
		} else {
			return wrappedMethod(e);
		}
	} else {
		return wrappedMethod(e);
	}
}

// TimeskipGameController - Animate the bars as time progresses.
//
@wrapMethod(TimeskipGameController)
protected cb func OnUpdate(timeDelta: Float) -> Bool {
	//DFProfile();
	wrappedMethod(timeDelta);

	if this.Settings.mainSystemEnabled {
		// Derive the current hour the same way as the wrapped method.
		let angle: Float;
		let diff: Float;
		let h: Int32;

		if !this.m_inputEnabled {
			if IsDefined(this.m_progressAnimProxy) && this.m_progressAnimProxy.IsPlaying() {
				angle = Deg2Rad(inkWidgetRef.GetRotation(this.m_currentTimePointerRef));

				if angle > this.m_targetTimeAngle {
					diff = Rad2Deg(6.28 - angle + this.m_targetTimeAngle);
				} else {
					diff = Rad2Deg(this.m_targetTimeAngle - angle);
				};
				
				h = RoundF(diff / 360.00 * 24.00);	// h = The remaining number of hours to wait.
				this.UpdateUIDuringTimeskip(h);
			};
		}
	}
}

// TimeskipGameController - Dispatch Time Skip Finished event.
//
@wrapMethod(TimeskipGameController)
protected cb func OnCloseAfterFinishing(proxy: ref<inkAnimProxy>) -> Bool {
	//DFProfile();
	if this.Settings.mainSystemEnabled {
		this.GameStateService.SetInSleepCinematic(false);

		let tsd: DFTimeSkipData;
		tsd.hoursSkipped = this.m_hoursToSkip;
		tsd.targetNeedValues = this.calculatedFutureValues.futureNeedsData[this.m_hoursToSkip - 1];
		tsd.targetAddictionValues = this.calculatedFutureValues.futureAddictionData[this.m_hoursToSkip - 1];
		tsd.targetHumanityLossValues = this.calculatedFutureValues.futureHumanityLossData[this.m_hoursToSkip - 1];
		tsd.timeSkipType = this.timeSkipType;
		this.MainSystem.DispatchTimeSkipFinishedEvent(tsd);
	}
	return wrappedMethod(proxy);
}

// TimeskipGameController - Dispatch Time Skip Cancelled event.
//
@wrapMethod(TimeskipGameController)
protected cb func OnCloseAfterCanceling(proxy: ref<inkAnimProxy>) -> Bool {
	//DFProfile();
	if this.Settings.mainSystemEnabled {
		this.GameStateService.SetInSleepCinematic(false);
		this.MainSystem.DispatchTimeSkipCancelledEvent();
	}
	return wrappedMethod(proxy);
}

// TimeskipGameController - Menu was closed, clear values.
//
@wrapMethod(TimeskipGameController)
protected cb func OnUninitialize() -> Bool {
	//DFProfile();
	if this.Settings.mainSystemEnabled {
		this.GameStateService.SetInSleepCinematic(false);
		this.InteractionSystem.SetSkippingTimeFromHubMenu(false);
	}
	
	return wrappedMethod();
}

// TimeskipGameController - Update UI based on selected time to wait.
//
@wrapMethod(TimeskipGameController)
private final func UpdateTargetTime(angle: Float) -> Void {
	//DFProfile();
	wrappedMethod(angle);
	this.UpdateUI();
}

@wrapMethod(TimeskipGameController)
private final func SetTimeSkipText(textWidgetRef: inkTextRef, textParamsRef: ref<inkTextParams>, hours: Int32) -> Void {
	//DFProfile();
	wrappedMethod(textWidgetRef, textParamsRef, hours);
	
	if DFIsSleeping(this.timeSkipType) {
		textParamsRef = new inkTextParams();
      	textParamsRef.AddNumber("value", hours);
		inkTextRef.SetLocalizedText(textWidgetRef, n"DarkFutureTimeskipSleepText", textParamsRef);
	}
}

//
//	New Methods
//

@addMethod(TimeskipGameController)
private final func SetOriginalValuesInUI() -> Void {
	//DFProfile();
	if !this.Settings.mainSystemEnabled { return; }

	this.hydrationBar.SetOriginalValue(this.HydrationSystem.GetNeedValue());
	this.nutritionBar.SetOriginalValue(this.NutritionSystem.GetNeedValue());
	this.energyBar.SetOriginalValue(this.EnergySystem.GetNeedValue());
	this.nerveBar.SetOriginalValue(this.NerveSystem.GetNeedValue());
	this.UpdateNerveBarLimit(this.NerveSystem.GetNeedMax());
}

@addMethod(TimeskipGameController)
private final func CreateNeedsBarCluster(parent: ref<inkCompoundWidget>) -> Void {
	//DFProfile();
	this.barCluster = new inkVerticalPanel();
	this.barCluster.SetVisible(this.GameStateService.IsValidGameState(this, true));
	this.barCluster.SetName(n"NeedsBarCluster");
	this.barCluster.SetAnchor(inkEAnchor.TopCenter);
	this.barCluster.SetAnchorPoint(Vector2(0.5, 0.5));
	this.barCluster.SetMargin(inkMargin(-20.0, 0.0, 0.0, 0.0));
	this.barCluster.Reparent(parent, 12);

	let rowOne: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	rowOne.SetName(n"NeedsBarClusterRowOne");
	rowOne.SetSize(Vector2(100.0, 60.0));
	rowOne.SetHAlign(inkEHorizontalAlign.Center);
	rowOne.SetVAlign(inkEVerticalAlign.Center);
	rowOne.SetAnchor(inkEAnchor.Fill);
	rowOne.SetAnchorPoint(Vector2(0.5, 0.5));
	rowOne.SetMargin(inkMargin(0.0, 0.0, 0.0, 50.0));
	rowOne.Reparent(this.barCluster);

	let rowTwo: ref<inkHorizontalPanel> = new inkHorizontalPanel();
	rowTwo.SetName(n"NeedsBarClusterRowTwo");
	rowTwo.SetSize(Vector2(100.0, 60.0));
	rowTwo.SetVAlign(inkEVerticalAlign.Center);
	rowTwo.SetAnchor(inkEAnchor.Fill);
	rowTwo.SetAnchorPoint(Vector2(0.5, 0.5));
	rowTwo.SetMargin(inkMargin(0.0, 0.0, 0.0, 50.0));
	rowTwo.Reparent(this.barCluster);

	let nerveIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nerveIconName: CName = n"illegal";

	let hydrationIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let hydrationIconName: CName = n"bar";
	
	let nutritionIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let nutritionIconName: CName = n"food_vendor";

	let energyIconPath: ResRef = r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas";
	let energyIconName: CName = n"wait";

	let barSetupData: DFNeedsMenuBarSetupData;

	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"nerveBar", nerveIconPath, nerveIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNerve"), 485.0, 100.0, 0.0, 0.0, true);
	this.nerveBar = new DFNeedsMenuBar();
	this.nerveBar.Init(barSetupData);

	barSetupData = DFNeedsMenuBarSetupData(rowOne, n"energyBar", energyIconPath, energyIconName, GetLocalizedTextByKey(n"DarkFutureUILabelEnergy"), 485.0, 0.0, 0.0, 0.0, true);
	this.energyBar = new DFNeedsMenuBar();
	this.energyBar.Init(barSetupData);

	barSetupData = DFNeedsMenuBarSetupData(rowTwo, n"hydrationBar", hydrationIconPath, hydrationIconName, GetLocalizedTextByKey(n"DarkFutureUILabelHydration"), 485.0, 100.0, 0.0, 0.0, true);
	this.hydrationBar = new DFNeedsMenuBar();
	this.hydrationBar.Init(barSetupData);
	
	barSetupData = DFNeedsMenuBarSetupData(rowTwo, n"nutritionBar", nutritionIconPath, nutritionIconName, GetLocalizedTextByKey(n"DarkFutureUILabelNutrition"), 485.0, 0.0, 0.0, 0.0, true);
	this.nutritionBar = new DFNeedsMenuBar();
	this.nutritionBar.Init(barSetupData);	
}

@addMethod(TimeskipGameController)
private final func CreateTimeskipAllowedReasonWidget(parent: ref<inkCompoundWidget>) -> Void {
	//DFProfile();
	let reasonWidget: ref<inkVerticalPanel> = new inkVerticalPanel();
	reasonWidget.SetVisible(this.GameStateService.IsValidGameState(this, true));
	reasonWidget.SetName(n"ReasonWidget");
	reasonWidget.SetFitToContent(true);
	reasonWidget.SetSize(Vector2(150.0, 32.0));
	reasonWidget.SetHAlign(inkEHorizontalAlign.Center);
	reasonWidget.SetVAlign(inkEVerticalAlign.Bottom);
	reasonWidget.SetAnchor(inkEAnchor.BottomCenter);
	reasonWidget.SetAnchorPoint(Vector2(0.5, 0.5));
	reasonWidget.SetMargin(inkMargin(0.0, 0.0, 0.0, 600.0));
	reasonWidget.Reparent(parent, 2);

	let reasonLabel: ref<inkText> = new inkText();
	reasonLabel.SetName(n"TimeskipAllowedReasonLabel");
	reasonLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
	reasonLabel.SetFontSize(38);
	reasonLabel.SetSize(Vector2(150.0, 32.0));
	reasonLabel.SetHorizontalAlignment(textHorizontalAlignment.Center);
	reasonLabel.SetHAlign(inkEHorizontalAlign.Center);
	reasonLabel.SetVAlign(inkEVerticalAlign.Bottom);
	reasonLabel.SetAnchor(inkEAnchor.BottomCenter);
	reasonLabel.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
	reasonLabel.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
	reasonLabel.BindProperty(n"tintColor", n"MainColors.Red");
	reasonLabel.Reparent(reasonWidget);

	this.timeskipAllowedReasonLabel = reasonWidget.GetWidget(n"TimeskipAllowedReasonLabel") as inkText;
}

@addMethod(TimeskipGameController)
private final func UpdateUI() -> Void {
	//DFProfile();
	if !this.GameStateService.IsValidGameState(this, true) { return; }
	let timeskipAllowedReasonKey: CName = n"";
	let index: Int32 = this.m_hoursToSkip - 1;

	let hydration: Float = this.calculatedFutureValues.futureNeedsData[index].hydration.value;
	let nutrition: Float = this.calculatedFutureValues.futureNeedsData[index].nutrition.value;
	let energy: Float = this.calculatedFutureValues.futureNeedsData[index].energy.value;
	let nerve: Float = this.calculatedFutureValues.futureNeedsData[index].nerve.value;

	this.hydrationBar.SetUpdatedValue(hydration, 100.0);
	this.nutritionBar.SetUpdatedValue(nutrition, 100.0);
	this.energyBar.SetUpdatedValue(energy, 100.0);
	
	let nerveMax: Float = this.calculatedFutureValues.futureNeedsData[index].nerve.ceiling;
	this.nerveBar.SetUpdatedValue(nerve, nerveMax);
	this.UpdateNerveBarLimit(nerveMax);

	if (this.Settings.nerveLossIsFatal && nerve <= 1.0) ||
	   (this.Settings.hydrationLossIsFatal && hydration <= 1.0) ||
	   (this.Settings.nutritionLossIsFatal && nutrition <= 1.0) ||
	   (this.Settings.energyLossIsFatal && energy <= 1.0) {
		this.timeskipAllowed = false;
		timeskipAllowedReasonKey = n"DarkFutureTimeskipReasonFatal";
	} else if DFIsSleeping(this.timeSkipType) && this.NerveSystem.GetNeedStageAtValue(nerve) >= this.NerveSystem.insomniaNeedStageThreshold {
		this.timeskipAllowed = true;
		timeskipAllowedReasonKey = n"DarkFutureTimeskipReasonNerveNoRecovery";
	} else if Equals(this.timeSkipType, DFTimeSkipType.LimitedSleep) {
		this.timeskipAllowed = true;
		timeskipAllowedReasonKey = n"DarkFutureTimeskipReasonLimitedSleepVehicle";
	} else {
		this.timeskipAllowed = true;
	}

	this.UpdateConfirmButton(this.timeskipAllowed);
	this.RefreshTimeskipAllowedReasonWidget(this.timeskipAllowed, timeskipAllowedReasonKey);
}

@addMethod(TimeskipGameController)
private final func GetTimeskipType(nerveStage: Int32) -> DFTimeSkipType {
	//DFProfile();
	let sleepingInBed: Bool = this.InteractionSystem.IsPlayerSleeping();
	let sleepingInVehicle: Bool = this.GameStateService.GetSleepingInVehicle();

	if sleepingInVehicle {
		let inBadlands: Bool = IsPlayerInBadlands(this.GameStateService.player);
		
		if (inBadlands && Equals(this.Settings.vehicleSleepQualityBadlandsV2, DFSleepQualitySetting.Limited)) {
			return DFTimeSkipType.LimitedSleep;

		} else if !inBadlands && Equals(this.Settings.vehicleSleepQualityCity, DFSleepQualitySetting.Limited) {
			return DFTimeSkipType.LimitedSleep;

		} else {
			return DFTimeSkipType.FullSleep;
		}
	
	} else if sleepingInBed {
		return DFTimeSkipType.FullSleep;

	} else {
		return DFTimeSkipType.TimeSkip;
	}
}

@addMethod(TimeskipGameController)
private final func UpdateAllBarsAppearance() -> Void {
	//DFProfile();
	let useProjectE3UI: Bool = this.Settings.compatibilityProjectE3UI;
	this.hydrationBar.UpdateAppearance(useProjectE3UI);
	this.nutritionBar.UpdateAppearance(useProjectE3UI);
	this.energyBar.UpdateAppearance(useProjectE3UI);
	this.nerveBar.UpdateAppearance(useProjectE3UI);
}

@addMethod(TimeskipGameController)
private final func UpdateUIDuringTimeskip(remainingHoursToSkip: Int32) -> Void {
	//DFProfile();
	if !this.Settings.mainSystemEnabled { return; }

	let index: Int32 = (this.m_hoursToSkip - remainingHoursToSkip) - 1;

	let hydration: Float = this.calculatedFutureValues.futureNeedsData[index].hydration.value;
	let nutrition: Float = this.calculatedFutureValues.futureNeedsData[index].nutrition.value;
	let energy: Float = this.calculatedFutureValues.futureNeedsData[index].energy.value;
	let nerve: Float = this.calculatedFutureValues.futureNeedsData[index].nerve.value;
	let nerveMax: Float = this.calculatedFutureValues.futureNeedsData[index].nerve.ceiling;

	this.hydrationBar.SetOriginalValue(hydration);
	this.nutritionBar.SetOriginalValue(nutrition);
	this.energyBar.SetOriginalValue(energy);
	this.nerveBar.SetOriginalValue(nerve);
	this.UpdateNerveBarLimit(nerveMax);

	let newIndex: Int32 = this.m_hoursToSkip - 1;

	let newHydration: Float = this.calculatedFutureValues.futureNeedsData[newIndex].hydration.value;
	let newNutrition: Float = this.calculatedFutureValues.futureNeedsData[newIndex].nutrition.value;
	let newEnergy: Float = this.calculatedFutureValues.futureNeedsData[newIndex].energy.value;
	let newNerve: Float = this.calculatedFutureValues.futureNeedsData[newIndex].nerve.value;

	this.hydrationBar.SetUpdatedValue(newHydration, 100.0);
	this.nutritionBar.SetUpdatedValue(newNutrition, 100.0);
	this.energyBar.SetUpdatedValue(newEnergy, 100.0);
	
	let nerveMax: Float = this.calculatedFutureValues.futureNeedsData[newIndex].nerve.ceiling;
	this.nerveBar.SetUpdatedValue(newNerve, nerveMax);
}

@addMethod(TimeskipGameController)
private final func UpdateConfirmButton(state: Bool) -> Void {
	//DFProfile();
	let confirmContainer: ref<inkHorizontalPanel> = this.GetRootCompoundWidget().GetWidget(n"hints/container/ok") as inkHorizontalPanel;
	let confirmAction: ref<inkText> = confirmContainer.GetWidget(n"action") as inkText;
	let confirmInputIcon: ref<inkImage> = confirmContainer.GetWidget(n"inputIcon") as inkImage;
	if state {
		confirmAction.BindProperty(n"tintColor", n"MainColors.Blue");
		confirmInputIcon.BindProperty(n"tintColor", n"MainColors.Blue");
	} else {
		confirmAction.BindProperty(n"tintColor", n"MainColors.MildBlue");
		confirmInputIcon.BindProperty(n"tintColor", n"MainColors.MildBlue");
	}
}

@addMethod(TimeskipGameController)
private final func RefreshTimeskipAllowedReasonWidget(timeskipAllowed: Bool, opt reasonText: CName) -> Void {
	//DFProfile();
	if timeskipAllowed {
		inkWidgetRef.SetTintColor(this.m_diffTimeLabel, GetDarkFutureHDRColor(DFHDRColor.PanelRed));
	} else {
		inkTextRef.SetText(this.m_diffTimeLabel, "Blocked");
		inkWidgetRef.SetTintColor(this.m_diffTimeLabel, GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
	}

	if NotEquals(reasonText, n"") {
		this.timeskipAllowedReasonLabel.SetText(GetLocalizedTextByKey(reasonText));
	} else {
		this.timeskipAllowedReasonLabel.SetText("");
	}
}

@addMethod(TimeskipGameController)
private final func UpdateNerveBarLimit(newLimitValue: Float) -> Void {
	//DFProfile();
	let currentLimitPct: Float = 1.0 - (newLimitValue / 100.0);
	this.nerveBar.SetProgressEmpty(currentLimitPct);
}

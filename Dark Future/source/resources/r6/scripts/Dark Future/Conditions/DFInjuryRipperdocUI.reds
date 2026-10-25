// -----------------------------------------------------------------------------
// DFInjuryRipperdocUI
// -----------------------------------------------------------------------------
//
// - Adds the Injury rate to the Ripperdoc Armor tooltip and an indicator under the Armor meter.
//

module DarkFuture.Conditions

import DarkFuture.Settings.DFSettings
import DarkFuture.Utils.{
    GetDarkFutureHDRColor,
    DFHDRColor
}

// RipperdocBarTooltip - Add the Injury rate to the Armor tooltip.
//
@addField(RipperdocBarTooltip)
public let DarkFutureArmorDescriptionAddedThisMenuSession: Bool = false;

@wrapMethod(RipperdocBarTooltip)
public func SetData(tooltipData: ref<ATooltipData>) -> Void {
    //DFProfile();
    wrappedMethod(tooltipData);

    let data: ref<RipperdocBarTooltipTooltipData> = tooltipData as RipperdocBarTooltipTooltipData;
    if !IsDefined(data) || NotEquals(data.barType, BarType.Armor) { return; }
    if !DFSettings.Get().injuryConditionEnabled { return; }

    let statsWidget: ref<inkVerticalPanel>;
    let precision: Int32;
    let descriptionWidget: ref<inkText>;

    // Make the Stats pane visible.
    // Crawl up to the Stats panel.
    statsWidget = inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;
    statsWidget.SetVisible(true);

    // Make the Stats 1 line visible, but no others.
    inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().SetVisible(true);
    inkWidgetRef.Get(this.m_stats2Name).GetParentWidget().SetVisible(false);
    inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().SetVisible(false);

    // Set the data on the Stats 1 line.
    inkTextRef.SetText(this.m_stats1Name, GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipInjuryRate"));
    inkWidgetRef.SetTintColor(this.m_stats1Name, GetDarkFutureHDRColor(DFHDRColor.MainBlue));

    let injuryMult: Float = DFInjuryConditionSystem.Get().GetArmorInjuryMult();
    precision = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
    inkTextRef.SetText(this.m_stats1Value, "-" + FloatToStringPrec(injuryMult, precision) + "%");
    inkWidgetRef.SetTintColor(this.m_stats1Value, GetDarkFutureHDRColor(DFHDRColor.MainBlue));

    // Set the description text.
    if !this.DarkFutureArmorDescriptionAddedThisMenuSession {
        this.DarkFutureArmorDescriptionAddedThisMenuSession = true;

        descriptionWidget = inkWidgetRef.Get(this.m_armorDescription) as inkText;
        let updatedArmorText: String = descriptionWidget.GetText() + "\n\n" + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipArmorDamageReductionUpdated");
        (inkWidgetRef.Get(this.m_armorDescription) as inkText).SetText(updatedArmorText);
    }
}

// RipperdocMetersArmor - Fields and methods to add and update the indicator under the Armor meter.
//
@addField(RipperdocMetersArmor)
private let DarkFutureInjuryMultIndicatorValue: ref<inkText>;

@addField(RipperdocMetersArmor)
private let DarkFutureLastInjuryMult: Float;

@addField(RipperdocMetersArmor)
private let DarkFutureInjuryMultIndicatorPulse: ref<PulseAnimation>;

@wrapMethod(RipperdocMetersArmor)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
    wrappedMethod();

    if DFSettings.Get().injuryConditionEnabled {
        let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
        this.DarkFutureInjuryMultIndicatorValue = this.CreateDarkFutureConditionIndicator(root, n"ico_condition_injury", DFHDRColor.MainBlue, -24.0);
        this.DarkFutureInjuryMultIndicatorPulse = new PulseAnimation();
    }
}

@wrapMethod(RipperdocMetersArmor)
private final func SetArmorData(newEquippedArmor: Float, maxCurrentArmor: Float, maxArmorPossible: Float, maxDamageReduction: Float) -> Void {
    //DFProfile();
    wrappedMethod(newEquippedArmor, maxCurrentArmor, maxArmorPossible, maxDamageReduction);

    if NotEquals(this.DarkFutureInjuryMultIndicatorValue, null) {
        let injuryMult: Float = newEquippedArmor * DFInjuryConditionSystem.Get().armorInjuryMult;
        let precision: Int32 = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
        this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(injuryMult, precision) + "%");
        this.DarkFutureLastInjuryMult = injuryMult;
        this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
        this.StopPulse(this.DarkFutureInjuryMultIndicatorPulse);
    }
}

@wrapMethod(RipperdocMetersArmor)
private final func PreviewChange(change: Float, isHover: Bool, isCyberwareEquipped: Bool) -> Void {
    //DFProfile();
    wrappedMethod(change, isHover, isCyberwareEquipped);

    if NotEquals(this.DarkFutureInjuryMultIndicatorValue, null) {
        let precision: Int32;
        if isHover && change != 0.0 {
            let injuryMult: Float = (change * DFInjuryConditionSystem.Get().armorInjuryMult) + this.DarkFutureLastInjuryMult;
            precision = injuryMult >= 100.0 ? 0 : injuryMult >= 10.0 ? 1 : 2;
            this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(injuryMult, precision) + "%");
            this.StartPulse(this.DarkFutureInjuryMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureInjuryMultIndicatorValue);
            if change > 0.0 {
                this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
            } else {
                this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
            }
        } else {
            precision = this.DarkFutureLastInjuryMult >= 100.0 ? 0 : this.DarkFutureLastInjuryMult >= 10.0 ? 1 : 2;
            this.DarkFutureInjuryMultIndicatorValue.SetText("-" + FloatToStringPrec(this.DarkFutureLastInjuryMult, precision) + "%");
            this.DarkFutureInjuryMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
            this.StopPulse(this.DarkFutureInjuryMultIndicatorPulse);
        }
    }
}

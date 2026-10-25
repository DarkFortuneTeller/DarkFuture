// -----------------------------------------------------------------------------
// DFHumanityLossRipperdocUI
// -----------------------------------------------------------------------------
//
// - Adds a Cyberpsychosis chance line to the Ripperdoc Edgerunner tooltip.
// - Adds the Humanity Loss rate to the Cyberware Capacity tooltip and an indicator under its meter.
//

module DarkFuture.Conditions

import DarkFuture.Settings.DFSettings
import DarkFuture.Utils.{
    GetDarkFutureHDRColor,
    DFHDRColor
}

// RipperdocBarTooltip - Add a Cyberpsychosis chance indicator to the Edgerunner tooltip.
//
@addField(RipperdocBarTooltip)
public let DarkFutureCyberpsychosisStatPanelAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCyberwareCapacityDescriptionAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCapacityDescriptionAddedThisMenuSession: Bool = false;

@addField(RipperdocBarTooltip)
public let DarkFutureCyberpsychosisStatValue: ref<inkText>;

// RipperdocBarTooltip - Add a Cyberpsychosis chance indicator to the Edgerunner tooltip, and the Humanity Loss rate to the Capacity tooltip.
//
@wrapMethod(RipperdocBarTooltip)
public func SetData(tooltipData: ref<ATooltipData>) -> Void {
    //DFProfile();
    wrappedMethod(tooltipData);

    let settings: ref<DFSettings> = DFSettings.Get();

    let humanityLossConditionSystem: ref<DFHumanityLossConditionSystem> = DFHumanityLossConditionSystem.Get();
    let isEdgerunnerBarAndHumanityOverallocated: Bool = false;
    let isCapacityBar: Bool = false;
    let overallocatedBy: Int32;
    let baseFuryChance: Float;
    let data: ref<RipperdocBarTooltipTooltipData> = tooltipData as RipperdocBarTooltipTooltipData;
    if IsDefined(data) {
        if Equals(data.barType, BarType.Edgerunner) {
            if !settings.humanityLossConditionEnabled { return; }
            if !settings.humanityLossCyberpsychosisEnabled { return; }

            if data.capacityPerk1Bought {
                let i: Int32 = 0;
                while i < ArraySize(data.statsData) {
                    if Equals(data.statsData[i].type, gamedataStatType.HumanityOverallocated) {
                        isEdgerunnerBarAndHumanityOverallocated = data.statsData[i].value > 0;
                        overallocatedBy = data.statsData[i].value;
                        baseFuryChance = data.statsData[i].valueF * 0.10;
                        break;
                    }
                    i += 1;
                }
            }
        } else if Equals(data.barType, BarType.CurrentCapacity) {
            if !settings.humanityLossConditionEnabled { return; }
            isCapacityBar = true;
        }
    } else {
        return;
    }

    let statName: ref<inkText>;
    let statColon: ref<inkText>;
    let cyberpsychosisStatHorizPanel: ref<inkHorizontalPanel>;
    let statsWidget: ref<inkVerticalPanel>;
    let cyberpsychosisChanceData: DFCyberpsychosisChanceData;
    let cyberpsychosisChance: Float;
    let isBlocked: Bool;
    let furyBonusChance: Float;
    let precision: Int32;
    let descriptionWidget: ref<inkText>;

    if isEdgerunnerBarAndHumanityOverallocated {
        if !this.DarkFutureCyberpsychosisStatPanelAddedThisMenuSession {
            this.DarkFutureCyberpsychosisStatPanelAddedThisMenuSession = true;

            // Crawl up to the Stats panel.
            statsWidget = inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;

            // Create new Stat line for Cyberpsychosis chance.
            statName = new inkText();
            statColon = new inkText();
            this.DarkFutureCyberpsychosisStatValue = new inkText();

            statName.SetName(n"name");
            statName.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            statName.SetFontSize(36);
            statName.SetVerticalAlignment(textVerticalAlignment.Center);
            statName.SetHAlign(inkEHorizontalAlign.Fill);
            statName.SetVAlign(inkEVerticalAlign.Bottom);
            statName.SetSize(Vector2(100.0, 32.0));
            statName.SetFitToContent(true);
            statName.SetAffectsLayoutWhenHidden(false);
            statName.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            statName.SetWrapping(false, 720.0, textWrappingPolicy.Default);
            statName.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
            statName.SetText(GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisChance"));

            statColon.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            statColon.SetName(n"colon");
            statColon.SetFontSize(36);
            statColon.SetVerticalAlignment(textVerticalAlignment.Center);
            statColon.SetHAlign(inkEHorizontalAlign.Fill);
            statColon.SetVAlign(inkEVerticalAlign.Bottom);
            statColon.SetSize(Vector2(100.0, 32.0));
            statColon.SetFitToContent(true);
            statColon.SetAffectsLayoutWhenHidden(false);
            statColon.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            statColon.SetText(":");
            statColon.SetVisible(false);

            this.DarkFutureCyberpsychosisStatValue.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
            this.DarkFutureCyberpsychosisStatValue.SetFontSize(36);
            this.DarkFutureCyberpsychosisStatValue.SetVerticalAlignment(textVerticalAlignment.Top);
            this.DarkFutureCyberpsychosisStatValue.SetHAlign(inkEHorizontalAlign.Fill);
            this.DarkFutureCyberpsychosisStatValue.SetVAlign(inkEVerticalAlign.Bottom);
            this.DarkFutureCyberpsychosisStatValue.SetSize(Vector2(100.0, 32.0));
            this.DarkFutureCyberpsychosisStatValue.SetFitToContent(true);
            this.DarkFutureCyberpsychosisStatValue.SetAffectsLayoutWhenHidden(false);
            this.DarkFutureCyberpsychosisStatValue.SetMargin(15.0, 0.0, 0.0, 0.0);
            this.DarkFutureCyberpsychosisStatValue.BindProperty(n"tintColor", n"TooltipRipperdoc.textMainColor");
            this.DarkFutureCyberpsychosisStatValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));

            cyberpsychosisChanceData = humanityLossConditionSystem.GetCyberpsychosisChance(overallocatedBy);
            cyberpsychosisChance = cyberpsychosisChanceData.chance;
            if NotEquals(cyberpsychosisChanceData.reason, "") {
                this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 1) + "% " + cyberpsychosisChanceData.reason);
            } else {
                this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 1) + "%");
            }

            // Create a new Stat Horizontal Panel.
            cyberpsychosisStatHorizPanel = new inkHorizontalPanel();
            cyberpsychosisStatHorizPanel.SetName(n"statDarkFutureCyberpsychosis");
            cyberpsychosisStatHorizPanel.AddChildWidget(statName);
            cyberpsychosisStatHorizPanel.AddChildWidget(statColon);
            cyberpsychosisStatHorizPanel.AddChildWidget(this.DarkFutureCyberpsychosisStatValue);

            // Add to the tooltip.
            statsWidget.AddChildWidget(cyberpsychosisStatHorizPanel);

            // Update the Fury chance based on current data.
            isBlocked = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
            furyBonusChance = Cast<Float>(humanityLossConditionSystem.GetCyberpsychosisStacksApplied()) * 0.5;
            if isBlocked {
                inkTextRef.SetText(this.m_stats3Value, "0% " + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonImmunosuppressant"));
            } else {
                inkTextRef.SetText(this.m_stats3Value, FloatToStringPrec(baseFuryChance + furyBonusChance, 1) + "%");
            }

        } else {
            cyberpsychosisChanceData = humanityLossConditionSystem.GetCyberpsychosisChance(overallocatedBy);
            cyberpsychosisChance = cyberpsychosisChanceData.chance;
            if NotEquals(cyberpsychosisChanceData.reason, "") {
                this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 2) + "% " + cyberpsychosisChanceData.reason);
            } else {
                this.DarkFutureCyberpsychosisStatValue.SetText(FloatToStringPrec(cyberpsychosisChance, 2) + "%");
            }

            // Update the Fury chance based on current data.
            isBlocked = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
            furyBonusChance = Cast<Float>(humanityLossConditionSystem.GetCyberpsychosisStacksApplied()) * 0.5;
            if isBlocked {
                inkTextRef.SetText(this.m_stats3Value, "0% " + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberpsychosisReasonImmunosuppressant"));
            } else {
                inkTextRef.SetText(this.m_stats3Value, FloatToStringPrec(baseFuryChance + furyBonusChance, 1) + "%");
            }
        }

    } else if isCapacityBar {
        // Make the Stats pane visible.
        // Crawl up to the Stats panel.
        statsWidget = inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().GetParentWidget() as inkVerticalPanel;
        statsWidget.SetVisible(true);

        // Make the Stats 1 line visible, but no others.
        inkWidgetRef.Get(this.m_stats1Name).GetParentWidget().SetVisible(true);
        inkWidgetRef.Get(this.m_stats2Name).GetParentWidget().SetVisible(false);
        inkWidgetRef.Get(this.m_stats3Name).GetParentWidget().SetVisible(false);

        // Set the data on the Stats 1 line.
        inkTextRef.SetText(this.m_stats1Name, GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipHumanityLossRate"));
        inkWidgetRef.SetTintColor(this.m_stats1Name, GetDarkFutureHDRColor(DFHDRColor.PanelRed));

        let humanityLossMult: Float = 0.0;
        isBlocked = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
        if !isBlocked {
            humanityLossMult = Cast<Float>(data.totalValue) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
        }
        precision = humanityLossMult >= 100.0 || humanityLossMult == 0.0 ? 0 : 1;
        inkTextRef.SetText(this.m_stats1Value, "+" + FloatToStringPrec(humanityLossMult, precision) + "%");
        inkWidgetRef.SetTintColor(this.m_stats1Value, GetDarkFutureHDRColor(DFHDRColor.PanelRed));

        // Set the description text.
        if !this.DarkFutureCapacityDescriptionAddedThisMenuSession {
            this.DarkFutureCapacityDescriptionAddedThisMenuSession = true;

            descriptionWidget = inkWidgetRef.Get(this.m_capacityDescription) as inkText;
            let updatedCapacityText: String = descriptionWidget.GetText() + "\n\n" + GetLocalizedTextByKey(n"DarkFutureRipperdocTooltipCyberwareCapacityUpdated");
            (inkWidgetRef.Get(this.m_capacityDescription) as inkText).SetText(updatedCapacityText);
        }
    }
}

// RipperdocMetersCapacity - Fields and methods to add and update the indicator under the Cyberware Capacity meter.
//
@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorValue: ref<inkText>;

@addField(RipperdocMetersCapacity)
private let DarkFutureLastHumanityLossMult: Float;

@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorPulse: ref<PulseAnimation>;

@addField(RipperdocMetersCapacity)
private let DarkFutureHumanityLossMultIndicatorIsBlocked: Bool = false;

@wrapMethod(RipperdocMetersCapacity)
protected cb func OnInitialize() -> Bool {
    //DFProfile();
    wrappedMethod();

    if DFSettings.Get().humanityLossConditionEnabled {
        let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
        let isBlocked: Bool = StatusEffectSystem.ObjectHasStatusEffectWithTag(DFHumanityLossConditionSystem.Get().player, n"DarkFutureImmunosuppressant");
        this.DarkFutureHumanityLossMultIndicatorValue = this.CreateDarkFutureConditionIndicator(root, n"ico_condition_humanityloss", DFHDRColor.PanelRed, -42.0, isBlocked, n"DarkFutureItemNameImmunosuppressant");
        this.DarkFutureHumanityLossMultIndicatorIsBlocked = isBlocked;
        this.DarkFutureHumanityLossMultIndicatorPulse = new PulseAnimation();
    }
}

@wrapMethod(RipperdocMetersCapacity)
private final func ConfigureBar(curEquippedCapacity: Int32, newEquippedCapacity: Int32, maxCapacity: Int32, overclockCapacity: Int32, isChange: Bool) -> Void {
    //DFProfile();
    wrappedMethod(curEquippedCapacity, newEquippedCapacity, maxCapacity, overclockCapacity, isChange);

    if this.DarkFutureHumanityLossMultIndicatorIsBlocked { return; }

    if NotEquals(this.DarkFutureHumanityLossMultIndicatorValue, null) {
        let humanityLossMult: Float;

        if newEquippedCapacity > 0 {
            humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
            this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
            this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
        } else {
            if this.m_isHoverdCyberwareEquipped && newEquippedCapacity != 0 {
                humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
                this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
                this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
            } else {
                if newEquippedCapacity < 0 {
                    humanityLossMult = Cast<Float>(curEquippedCapacity + newEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
                    this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveGreen));
                    this.StartPulse(this.DarkFutureHumanityLossMultIndicatorPulse, this.m_pulseAnimationParams, this.DarkFutureHumanityLossMultIndicatorValue);
                } else {
                    humanityLossMult = Cast<Float>(curEquippedCapacity) * DFHumanityLossConditionSystem.Get().cyberwareCapacityHumanityLossMult;
                    this.DarkFutureHumanityLossMultIndicatorValue.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
                    this.StopPulse(this.DarkFutureHumanityLossMultIndicatorPulse);
                }
            }
        }

        this.DarkFutureLastHumanityLossMult = humanityLossMult;
        let precision: Int32 = humanityLossMult >= 100.0 ? 0 : 1;
        this.DarkFutureHumanityLossMultIndicatorValue.SetText("+" + FloatToStringPrec(humanityLossMult, precision) + "%");
    }
}

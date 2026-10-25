// -----------------------------------------------------------------------------
// DFConditionRipperdocUI
// -----------------------------------------------------------------------------
//
// - Shared Ripperdoc menu UI for Conditions: the indicator shown below a Ripperdoc meter.
//

module DarkFuture.Conditions

import DarkFuture.Utils.{
    GetDarkFutureHDRColor,
    DFHDRColor
}

// RipperdocMetersBase - Add a method to create a new UI indicator below the Cyberware Capacity and Armor meters.
//
@addMethod(RipperdocMetersBase)
public final func CreateDarkFutureConditionIndicator(root: ref<inkCompoundWidget>, iconPart: CName, color: DFHDRColor, leftMargin: Float, opt isBlocked: Bool, opt blockedMessage: CName) -> ref<inkText> {
    //DFProfile();
    // Create the Humanity Loss / Injury Multiplier Widget

    // Canvas
    let indicatorCanvas: ref<inkCanvas> = new inkCanvas();
    indicatorCanvas.SetName(n"DFIndicatorCanvas");
    indicatorCanvas.SetMargin(leftMargin, 1000.0, 5.0, 0.0);
    indicatorCanvas.SetSize(210.0, 75.0);
    indicatorCanvas.Reparent(root);

    // "Blocked" Symbol
    let indicatorBlocked: ref<inkImage> = new inkImage();
    indicatorBlocked.SetName(n"DarkFutureHLIndicatorBlocked");
    indicatorBlocked.SetVisible(false);
    indicatorBlocked.SetMargin(0.0, -8.0, 0.0, 0.0);
    indicatorBlocked.SetSize(32.0, 32.0);
    indicatorBlocked.SetScale(Vector2(1.5, 1.5));
    indicatorBlocked.SetFitToContent(true);
    indicatorBlocked.SetAffectsLayoutWhenHidden(false);
    indicatorBlocked.SetAnchor(inkEAnchor.Centered);
    indicatorBlocked.SetAnchorPoint(0.5, 0.0);
    indicatorBlocked.SetAtlasResource(r"base\\gameplay\\gui\\common\\icons\\atlas_common.inkatlas");
    indicatorBlocked.SetTexturePart(n"ico_locked");
    indicatorBlocked.SetTintColor(GetDarkFutureHDRColor(color));
    indicatorBlocked.Reparent(indicatorCanvas);

    // Icon
    let indicatorIcon: ref<inkImage> = new inkImage();
    indicatorIcon.SetName(n"DarkFutureHLIndicatorIcon");
    indicatorIcon.SetMargin(6.0, -32.0, 0.0, 0.0);
    indicatorIcon.SetSize(32.0, 32.0);
    indicatorIcon.SetFitToContent(true);
    indicatorIcon.SetAffectsLayoutWhenHidden(false);
    indicatorIcon.SetAnchor(inkEAnchor.CenterLeft);
    indicatorIcon.SetAtlasResource(r"darkfuture\\condition_images\\condition_assets.inkatlas");
    indicatorIcon.SetTexturePart(iconPart);
    indicatorIcon.SetTintColor(GetDarkFutureHDRColor(color));
    indicatorIcon.Reparent(indicatorCanvas);

    // Value
    let indicatorValue: ref<inkText> = new inkText();
    indicatorValue.SetName(n"DFIndicatorValue");
    indicatorValue.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    indicatorValue.SetFontStyle(n"Semi-Bold");
    indicatorValue.SetFontSize(42);
    indicatorValue.SetLetterCase(textLetterCase.UpperCase);
    indicatorValue.SetFitToContent(false);
    indicatorValue.SetHorizontalAlignment(textHorizontalAlignment.Center);
    indicatorValue.SetVerticalAlignment(textVerticalAlignment.Center);
    indicatorValue.SetJustificationType(textJustificationType.Center);
    indicatorValue.SetSize(130.0, 65.0);
    indicatorValue.SetMargin(70.0, 6.0, 0.0, 0.0);
    indicatorValue.SetLockFontInGame(true);
    indicatorValue.SetTintColor(GetDarkFutureHDRColor(color));
    indicatorValue.Reparent(indicatorCanvas);
    indicatorValue.SetText("+0%");

    // "Immunosuppressant" Label
    let indicatorImmunosuppressantLabel: ref<inkText> = new inkText();
    indicatorImmunosuppressantLabel.SetName(n"DFIndicatorImmunosuppressantLabel");
    indicatorImmunosuppressantLabel.SetVisible(false);
    indicatorImmunosuppressantLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    indicatorImmunosuppressantLabel.SetFontStyle(n"Semi-Bold");
    indicatorImmunosuppressantLabel.SetFontSize(22);
    indicatorImmunosuppressantLabel.SetLetterCase(textLetterCase.UpperCase);
    indicatorImmunosuppressantLabel.SetFitToContent(false);
    indicatorImmunosuppressantLabel.SetHorizontalAlignment(textHorizontalAlignment.Center);
    indicatorImmunosuppressantLabel.SetVerticalAlignment(textVerticalAlignment.Center);
    indicatorImmunosuppressantLabel.SetJustificationType(textJustificationType.Center);
    indicatorImmunosuppressantLabel.SetSize(130.0, 65.0);
    indicatorImmunosuppressantLabel.SetMargin(0.0, 30.0, 0.0, 0.0);
    indicatorImmunosuppressantLabel.SetAnchor(inkEAnchor.Centered);
    indicatorImmunosuppressantLabel.SetAnchorPoint(0.5, 0.0);
    indicatorImmunosuppressantLabel.SetLockFontInGame(true);
    indicatorImmunosuppressantLabel.SetTintColor(GetDarkFutureHDRColor(color));
    indicatorImmunosuppressantLabel.Reparent(indicatorCanvas);
    indicatorImmunosuppressantLabel.SetText(GetLocalizedTextByKey(blockedMessage));


    // Frame
    let indicatorFrame: ref<inkImage> = new inkImage();
    indicatorFrame.SetName(n"DFIndicatorFrame");
    indicatorFrame.SetAtlasResource(r"base\\gameplay\\gui\\fullscreen\\ripperdoc\\assets\\cw_bars_assets.inkatlas");
    indicatorFrame.SetTexturePart(n"counterLabel_stroke");
    indicatorFrame.SetContentHAlign(inkEHorizontalAlign.Fill);
    indicatorFrame.SetContentVAlign(inkEVerticalAlign.Fill);
    indicatorFrame.SetNineSliceScale(true);
    indicatorFrame.SetNineSliceGrid(inkMargin(0.0, 0.0, 0.0, 0.0));
    indicatorFrame.SetBrushTileType(inkBrushTileType.NoTile);
    indicatorFrame.SetAnchor(inkEAnchor.Fill);
    indicatorFrame.SetHAlign(inkEHorizontalAlign.Center);
    indicatorFrame.SetVAlign(inkEVerticalAlign.Center);
    indicatorFrame.SetSize(32.0, 32.0);
    indicatorFrame.SetFitToContent(true);
    indicatorFrame.SetAffectsLayoutWhenHidden(false);
    indicatorFrame.SetTintColor(GetDarkFutureHDRColor(color));
    indicatorFrame.Reparent(indicatorCanvas);

    // Set "Blocked" mode
    if isBlocked {
        indicatorIcon.SetOpacity(0.05);
        indicatorValue.SetOpacity(0.05);
        indicatorFrame.SetOpacity(0.05);
        indicatorBlocked.SetVisible(true);
        indicatorImmunosuppressantLabel.SetVisible(true);
    }

    return indicatorValue;
}

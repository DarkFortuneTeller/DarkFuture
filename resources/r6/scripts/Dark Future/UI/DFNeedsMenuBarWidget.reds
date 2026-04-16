// -----------------------------------------------------------------------------
// DFNeedsMenuBarWidget
// -----------------------------------------------------------------------------
//
// - Basic Need Menu (Backpack UI, Timeskip UI) Bar Meter Widget definition and logic.
//

module DarkFuture.UI

import DarkFuture.Logging.*
import DarkFuture.Utils.{
    DFHDRColor,
    GetDarkFutureHDRColor
}

public struct DFNeedsMenuBarSetupData {
    public let parent: ref<inkCompoundWidget>;
    public let widgetName: CName;
    public let iconPath: ResRef;
    public let iconName: CName;
    public let barLabel: String;
    public let canvasWidth: Float;
    public let canvasRightMargin: Float;
    public let translationX: Float;
    public let translationY: Float;
    public let showEmptyBar: Bool;
    public let hasLock: Bool;
}

public class DFNeedsMenuBar extends inkCanvas {
    public let m_setupData: DFNeedsMenuBarSetupData;

    private let m_width: Float;
    private let m_height: Float;
    private let m_hasLock: Bool;

    private let m_rootWidget: ref<inkCanvas>;
    private let m_icon: ref<inkImage>;
    private let m_labelPanel: ref<inkFlex>;
    private let m_barLabel: ref<inkText>;
    private let m_bg: ref<inkRectangle>;
    private let m_border: ref<inkBorderConcrete>;
    private let m_fullBar: ref<inkRectangle>;
    private let m_emptyBar: ref<inkRectangle>;
    private let m_changeBar: ref<inkRectangle>;
    private let m_valueLabel: ref<inkText>;
    private let m_lock: ref<inkImage>;
    private let m_shadow: ref<inkImage>;

    private let m_showLock_anim: ref<inkAnimDef>;
    private let m_showLock_lock_anim_proxy: ref<inkAnimProxy>;
    private let m_showLock_shadow_anim_proxy: ref<inkAnimProxy>;
    private let m_hideLock_anim: ref<inkAnimDef>;
    private let m_hideLock_anim_proxy: ref<inkAnimProxy>;
    private let m_hideLock_lock_anim_proxy: ref<inkAnimProxy>;
    private let m_hideLock_shadow_anim_proxy: ref<inkAnimProxy>;

    private let m_originalValueLabelTintColor: HDRColor;

    private let m_originalValue: Float = 1.0;
    private let m_currentValue: Float = 1.0;
    private let m_previousValue: Float = 1.0;
    private let m_lockShown: Bool = false;

    private let m_barContentHeight: Float = 8.0;

    public final func Init(setupData: DFNeedsMenuBarSetupData) -> Void {
        //DFProfile();
        this.m_setupData = setupData;
        this.CreateBar();
        this.SetDefaultValues();
    }

    public final func SetDefaultValues() -> Void {
        //DFProfile();
        let tempSize: Vector2 = this.m_fullBar.GetSize();
        this.m_width = tempSize.X;
        this.m_height = tempSize.Y;
        this.m_fullBar.SetSize(Vector2(this.m_width, this.m_height));
        this.m_changeBar.SetSize(Vector2(0.00, this.m_height));
    }

    private final func CreateBar() -> ref<inkCanvas> {
        //DFProfile();
        //
        // Recreate a custom Stamina-like bar.
        //
        let canvas: ref<inkCanvas> = new inkCanvas();
        canvas.SetName(this.m_setupData.widgetName);
        canvas.SetChildOrder(inkEChildOrder.Backward);
        canvas.SetSize(Vector2(this.m_setupData.canvasWidth, 60.0));
        canvas.SetHAlign(inkEHorizontalAlign.Center);
        canvas.SetMargin(inkMargin(0.0, 0.0, this.m_setupData.canvasRightMargin, 0.0));
        this.m_rootWidget = canvas;
        canvas.Reparent(this.m_setupData.parent);

        if this.m_setupData.hasLock {
            this.m_hasLock = true;

            let lock: ref<inkImage> = new inkImage();
            lock.SetName(n"lock");
            lock.SetFitToContent(true);
            lock.SetAnchor(inkEAnchor.Centered);
            lock.SetAnchorPoint(Vector2(0.5, 0.5));
            lock.SetHAlign(inkEHorizontalAlign.Center);
            lock.SetVAlign(inkEVerticalAlign.Center);
            lock.SetMargin(70.0, 20.0, 0.0, 0.0);
            lock.SetOpacity(0.0);
            lock.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActiveMainRed));
            lock.SetSize(Vector2(100.0, 32.0));
            lock.SetAtlasResource(r"base\\gameplay\\gui\\common\\stamina_oxygen_bar\\stamina_oxygen_bar.inkatlas");
            lock.SetTexturePart(n"ico_lock");
            lock.Reparent(canvas);
            this.m_lock = lock;

            let shadow: ref<inkImage> = new inkImage();
            shadow.SetName(n"shadow");
            shadow.SetAffectsLayoutWhenHidden(true);
            shadow.SetAnchor(inkEAnchor.Centered);
            shadow.SetAnchorPoint(Vector2(0.5, 0.5));
            shadow.SetHAlign(inkEHorizontalAlign.Center);
            shadow.SetVAlign(inkEVerticalAlign.Center);
            shadow.SetMargin(70.0, 20.0, 0.0, 0.0);
            shadow.SetOpacity(0.0);
            shadow.SetTintColor(HDRColor(0.0, 0.0, 0.0, 1.0));
            shadow.SetSize(Vector2(150.0, 100.0));
            shadow.SetAtlasResource(r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas");
            shadow.SetTexturePart(n"shadowBlobText");
            shadow.Reparent(canvas);
            this.m_shadow = shadow;
        
        } else {
            this.m_hasLock = false;
        }

        let horizPanel: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        horizPanel.SetName(n"horizPanel");
        horizPanel.SetAnchor(inkEAnchor.Fill);
        horizPanel.Reparent(canvas);

        let icon: ref<inkImage> = new inkImage();
        icon.SetName(n"icon");
        icon.SetAffectsLayoutWhenHidden(true);
        icon.SetAnchor(inkEAnchor.TopLeft);
        icon.SetContentHAlign(inkEHorizontalAlign.Center);
        icon.SetContentVAlign(inkEVerticalAlign.Center);
        icon.SetMargin(inkMargin(20.0, 10.0, 20.0, 0.0));
        icon.SetSize(Vector2(30.0, 30.0));
        icon.SetBrushMirrorType(inkBrushMirrorType.NoMirror);
        icon.SetBrushTileType(inkBrushTileType.NoTile);
        icon.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
        icon.SetAtlasResource(this.m_setupData.iconPath);
        icon.SetTexturePart(this.m_setupData.iconName);
        icon.Reparent(horizPanel);
        this.m_icon = icon;

        let vertPanel: ref<inkVerticalPanel> = new inkVerticalPanel();
        vertPanel.SetName(n"vertPanel");
        vertPanel.SetMargin(inkMargin(20.0, 0.0, 0.0, 0.0));
        vertPanel.SetAnchor(inkEAnchor.TopLeft);
        vertPanel.SetVAlign(inkEVerticalAlign.Center);
        vertPanel.SetSize(Vector2(100.0, 32.0));
        vertPanel.Reparent(horizPanel);

        let labelPanel: ref<inkFlex> = new inkFlex();
        labelPanel.SetName(n"labelPanel");
        labelPanel.SetAnchor(inkEAnchor.Fill);
        //labelPanel.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
        labelPanel.SetSize(Vector2(this.m_setupData.canvasWidth * 0.875, 32.0));
        labelPanel.Reparent(vertPanel);
        this.m_labelPanel = labelPanel;

        let barLabel: ref<inkText> = new inkText();
        barLabel.SetName(n"barLabel");
        barLabel.SetMargin(inkMargin(2.0, 0.0, 0.0, 3.0));
        barLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
	    barLabel.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
        barLabel.SetLetterCase(textLetterCase.UpperCase);
        barLabel.SetFontSize(36);
        barLabel.SetText(this.m_setupData.barLabel);
        barLabel.SetHAlign(inkEHorizontalAlign.Left);
        barLabel.SetVAlign(inkEVerticalAlign.Bottom);
        barLabel.Reparent(labelPanel);
        this.m_barLabel = barLabel;

        let valueLabel: ref<inkText> = new inkText();
        valueLabel.SetName(n"valueLabel");
        valueLabel.SetAnchor(inkEAnchor.BottomRight);
        valueLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
	    valueLabel.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
        valueLabel.SetLetterCase(textLetterCase.UpperCase);
        valueLabel.SetFontSize(36);
        valueLabel.SetText("100");
        valueLabel.SetHAlign(inkEHorizontalAlign.Right);
        valueLabel.SetVAlign(inkEVerticalAlign.Bottom);
        valueLabel.SetMargin(inkMargin(0.0, 0.0, 30.0, 3.0));
        valueLabel.Reparent(labelPanel);
        this.m_valueLabel = valueLabel;

        let wrapper: ref<inkFlex> = new inkFlex();
        wrapper.SetName(n"wrapper");
        wrapper.SetMargin(inkMargin(0.0, 0.0, 20.0, 0.0));
        wrapper.SetAnchor(inkEAnchor.TopLeft);
        wrapper.SetHAlign(inkEHorizontalAlign.Left);
        wrapper.SetVAlign(inkEVerticalAlign.Top);
        wrapper.SetSize(Vector2(100.0, 15.0));
        wrapper.Reparent(vertPanel);

        let bg: ref<inkRectangle> = new inkRectangle();
        bg.SetName(n"bg");
        bg.SetHAlign(inkEHorizontalAlign.Left);
        bg.SetVAlign(inkEVerticalAlign.Center);
        bg.SetMargin(inkMargin(5.0, 0.0, 0.0, 0.0));
        bg.SetOpacity(0.3);
        bg.SetShear(Vector2(0.5, 0.0));
        bg.SetRenderTransformPivot(Vector2(1.0, 0.5));
        bg.SetSize(Vector2(this.m_setupData.canvasWidth * 0.875, 10.0));
        bg.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.FaintPanelRed));
        bg.Reparent(wrapper);
        this.m_bg = bg;

        let border: ref<inkBorderConcrete> = new inkBorderConcrete();
        border.SetName(n"border");
        border.SetMargin(inkMargin(5.0, 0.0, 0.0, 0.0));
        border.SetHAlign(inkEHorizontalAlign.Fill);
        border.SetVAlign(inkEVerticalAlign.Center);
        border.SetOpacity(0.5);
        border.SetShear(Vector2(0.5, 0.0));
        border.SetSize(Vector2(100.0, 12.0));
        border.SetThickness(2.0);
        border.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.PanelRed));
        border.Reparent(wrapper);
        this.m_border = border;

        let logic: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        logic.SetName(n"logic");
        logic.SetHAlign(inkEHorizontalAlign.Left);
        logic.SetVAlign(inkEVerticalAlign.Center);
        logic.SetMargin(inkMargin(-1.0, 0.0, 0.0, 0.0));
        logic.SetSize(240.0, 28.0);
        logic.Reparent(wrapper);

        let empty: ref<inkRectangle> = new inkRectangle();
        empty.SetName(n"empty");
        empty.SetHAlign(inkEHorizontalAlign.Right);
        empty.SetVAlign(inkEVerticalAlign.Center);
        empty.SetShear(Vector2(0.5, 0.0));
        empty.SetSize(Vector2(0.0, 8.0));
        empty.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        empty.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.Rose));
        empty.SetVisible(this.m_setupData.showEmptyBar);
        empty.Reparent(wrapper);
        this.m_emptyBar = empty;

        let fullBar: ref<inkRectangle> = new inkRectangle();
        fullBar.SetName(n"fullBar");
        fullBar.SetHAlign(inkEHorizontalAlign.Left);
        fullBar.SetVAlign(inkEVerticalAlign.Center);
        fullBar.SetShear(Vector2(0.5, 0.0));
        fullBar.SetTranslation(8.0, 0.0);
        fullBar.SetSize(Vector2((this.m_setupData.canvasWidth * 0.875) - 2.0, this.m_barContentHeight));
        fullBar.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MildRed));
        fullBar.Reparent(logic);
        this.m_fullBar = fullBar;

        let changeBar: ref<inkRectangle> = new inkRectangle();
        changeBar.SetName(n"changeBar");
        changeBar.SetAnchor(inkEAnchor.BottomLeft);
        changeBar.SetHAlign(inkEHorizontalAlign.Left);
        changeBar.SetVAlign(inkEVerticalAlign.Center);
        changeBar.SetShear(Vector2(0.5, 0.0));
        changeBar.SetTranslation(8.0, 0.0);
        changeBar.SetSize(Vector2(0.0, this.m_barContentHeight));
        changeBar.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.DarkRed));
        changeBar.Reparent(wrapper);
        this.m_changeBar = changeBar;

        return canvas;
    }

    public final func SetOriginalValue(value: Float) -> Void {
        //DFProfile();
        this.m_originalValue = ClampF(value, 0.0, 100.0);
    }

    public final func SetUpdatedValue(newValue: Float, max: Float, opt showLock: Bool) -> Void {
        //DFProfile();
        this.m_valueLabel.SetText(ToString(Cast<Int32>(ClampF(newValue, 0.0, max))));

        let negativeMargin: inkMargin;

        this.m_previousValue = this.m_originalValue / 100.0;
        this.m_currentValue = ClampF(newValue, 0.0, max) / 100.0;

        if this.m_previousValue < this.m_currentValue && this.m_currentValue - this.m_previousValue >= 0.01 {
            this.m_changeBar.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
            this.m_valueLabel.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.MainBlue));
            this.m_fullBar.SetSize(Vector2((this.m_width * this.m_previousValue) - 2.0, this.m_barContentHeight));
            this.m_changeBar.SetSize(Vector2(((this.m_width * this.m_currentValue) - (this.m_width * this.m_previousValue)), this.m_barContentHeight));
            negativeMargin.left = (this.m_width * this.m_previousValue) - 3.0;
            this.m_changeBar.SetMargin(negativeMargin);

        } else if this.m_previousValue > this.m_currentValue && this.m_previousValue - this.m_currentValue >= 0.01 {
            this.m_changeBar.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
            this.m_valueLabel.SetTintColor(GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed));
            this.m_fullBar.SetSize(Vector2((this.m_width * this.m_currentValue) - 2.0, this.m_barContentHeight));
            this.m_changeBar.SetSize(Vector2(((this.m_width * this.m_previousValue) - (this.m_width * this.m_currentValue)), this.m_barContentHeight));
            negativeMargin.left = (this.m_width * this.m_currentValue) - 3.0;
            this.m_changeBar.SetMargin(negativeMargin);

        } else {
            this.m_valueLabel.SetTintColor(this.m_originalValueLabelTintColor);
            this.m_fullBar.SetSize(Vector2((this.m_width * this.m_previousValue) - 2.0, this.m_barContentHeight));
            this.m_changeBar.SetSize(Vector2(0.0, this.m_barContentHeight));
        }

        if showLock {
            this.SetShowLock();
        } else {
            this.SetHideLock();
        }
    }

    public final func SetProgressEmpty(newValue: Float) {
        //DFProfile();
        this.m_emptyBar.SetSize(Vector2(this.m_width * newValue, this.m_barContentHeight));
        this.m_emptyBar.SetMargin(inkMargin(0.0, 0.0, 3.0, 0.0));
    }

    public final func GetFullSize() -> Vector2 {
        //DFProfile();
        return Vector2(this.m_width, this.m_height);
    }

    public final func UpdateAppearance(useProjectE3UI: Bool) {
        //DFProfile();
        let shear: Float = useProjectE3UI ? 0.0 : 0.5;

        let iconColor: HDRColor = useProjectE3UI ? GetDarkFutureHDRColor(DFHDRColor.MildWhite) : GetDarkFutureHDRColor(DFHDRColor.PanelRed);
        let barLabelColor: HDRColor = useProjectE3UI ? GetDarkFutureHDRColor(DFHDRColor.MildWhite) : GetDarkFutureHDRColor(DFHDRColor.PanelRed);

        let tintColor: HDRColor = useProjectE3UI ? GetDarkFutureHDRColor(DFHDRColor.White) : GetDarkFutureHDRColor(DFHDRColor.PanelRed);
        let faintTintColor: HDRColor = useProjectE3UI ? GetDarkFutureHDRColor(DFHDRColor.FaintWhite) : GetDarkFutureHDRColor(DFHDRColor.FaintPanelRed);
        let mildTintColor: HDRColor = useProjectE3UI ? GetDarkFutureHDRColor(DFHDRColor.MildWhite) : GetDarkFutureHDRColor(DFHDRColor.MildRed);

        this.m_icon.SetTintColor(iconColor);
        this.m_barLabel.SetTintColor(barLabelColor);
        this.m_valueLabel.SetTintColor(tintColor);
        this.m_originalValueLabelTintColor = tintColor;
        
        this.m_bg.SetTintColor(faintTintColor);
        this.m_bg.SetShear(Vector2(shear, 0.0));

        this.m_border.SetTintColor(tintColor);
        this.m_border.SetShear(Vector2(shear, 0.0));
        
        this.m_fullBar.SetTintColor(mildTintColor);
        this.m_fullBar.SetShear(Vector2(shear, 0.0));

        this.m_emptyBar.SetShear(Vector2(shear, 0.0));
        this.m_changeBar.SetShear(Vector2(shear, 0.0));
    }

    private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
        //DFProfile();
        if IsDefined(animProxy) {
            animProxy.Stop();
        }
    }

    public final func HasLock() -> Bool {
        //DFProfile();
        return this.m_hasLock;
    }

    public final func SetShowLock() -> Void {
        //DFProfile();
        if !this.m_lockShown {
            this.m_lockShown = true;

            this.StopAnimProxyIfDefined(this.m_showLock_lock_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_showLock_shadow_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_hideLock_lock_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_hideLock_shadow_anim_proxy);

            this.m_showLock_anim = new inkAnimDef();

            let showLockScaleInterp: ref<inkAnimScale> = new inkAnimScale();
            showLockScaleInterp.SetDuration(0.25);
            showLockScaleInterp.SetMode(inkanimInterpolationMode.EasyOut);
            showLockScaleInterp.SetType(inkanimInterpolationType.Back);
            showLockScaleInterp.SetStartScale(Vector2(1.5, 1.5));
            showLockScaleInterp.SetEndScale(Vector2(1.0, 1.0));
            this.m_showLock_anim.AddInterpolator(showLockScaleInterp);

            let showLockTransparencyInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
            showLockTransparencyInterp.SetDuration(0.24);
            showLockTransparencyInterp.SetMode(inkanimInterpolationMode.EasyOut);
            showLockTransparencyInterp.SetType(inkanimInterpolationType.Quartic);
            showLockTransparencyInterp.SetStartTransparency(0.0);
            showLockTransparencyInterp.SetEndTransparency(1.0);
            this.m_showLock_anim.AddInterpolator(showLockTransparencyInterp);

            this.m_showLock_lock_anim_proxy = this.m_lock.PlayAnimation(this.m_showLock_anim);
            this.m_showLock_shadow_anim_proxy = this.m_shadow.PlayAnimation(this.m_showLock_anim);
        }
    }

    public final func SetHideLock() -> Void {
        //DFProfile();
        if this.m_lockShown {
            this.m_lockShown = false;

            this.StopAnimProxyIfDefined(this.m_showLock_lock_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_showLock_shadow_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_hideLock_lock_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_hideLock_shadow_anim_proxy);

            this.m_hideLock_anim = new inkAnimDef();

            let hideLockScaleInterp: ref<inkAnimScale> = new inkAnimScale();
            hideLockScaleInterp.SetDuration(0.25);
            hideLockScaleInterp.SetMode(inkanimInterpolationMode.EasyOut);
            hideLockScaleInterp.SetType(inkanimInterpolationType.Back);
            hideLockScaleInterp.SetStartScale(Vector2(1.0, 1.0));
            hideLockScaleInterp.SetEndScale(Vector2(1.5, 1.5));
            this.m_hideLock_anim.AddInterpolator(hideLockScaleInterp);

            let hideLockTransparencyInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
            hideLockTransparencyInterp.SetDuration(0.24);
            hideLockTransparencyInterp.SetMode(inkanimInterpolationMode.EasyOut);
            hideLockTransparencyInterp.SetType(inkanimInterpolationType.Quartic);
            hideLockTransparencyInterp.SetStartTransparency(1.0);
            hideLockTransparencyInterp.SetEndTransparency(0.0);
            this.m_hideLock_anim.AddInterpolator(hideLockTransparencyInterp);

            this.m_hideLock_lock_anim_proxy = this.m_lock.PlayAnimation(this.m_hideLock_anim);
            this.m_hideLock_shadow_anim_proxy = this.m_shadow.PlayAnimation(this.m_hideLock_anim);
        }
    }
}

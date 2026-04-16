// -----------------------------------------------------------------------------
// DFHUDSegmentedIndicatorWidget
// -----------------------------------------------------------------------------
//
// - Segmented Indicator HUD Widget definition and logic.
//

module DarkFuture.UI

import DarkFuture.Logging.*
import DarkFuture.Utils.{
    DFBarColorTheme,
    DFBarColorThemeName,
    GetDarkFutureBarColorTheme
}
import DarkFuture.Services.DFGameStateService
import DarkFuture.Settings.DFSettings

public struct DFHUDSegmentSetupDatum {
    public let type: DFHUDSegmentedIndicatorSegmentType;
    public let abbreviatedNameKey: CName;
    public let longNameKey: CName;
}

public struct DFHUDSegmentWidgetDatum {
    public let type: DFHUDSegmentedIndicatorSegmentType;
    public let active: Bool = false;
    public let widget: ref<inkCanvas>;
    public let bg: ref<inkRectangle>;
    public let border: ref<inkBorderConcrete>;
    public let label: ref<inkText>;
}

public struct DFHUDSegmentedIndicatorSetupData {
    public let parent: ref<inkCompoundWidget>;
    public let widgetName: CName;
    public let iconPath: ResRef;
    public let iconName: CName;
    public let colorTheme: DFBarColorTheme;
    public let canvasWidth: Float;
    public let indicatorTotalWidth: Float;
    public let translationX: Float;
    public let translationY: Float;
    public let segments: array<DFHUDSegmentSetupDatum>;
}

public class DFHUDSegmentedIndicatorGroup extends DFNeedsHUDBarGroup {
    public let m_hasPulsedOnThisLockDisplay: Bool = false;
    public let m_displayingOverStamina: Bool = false;

    public final func EvaluateAllSegmentedIndicatorVisibility(forceMomentaryDisplay: Bool, fromParentUpdate: Bool, momentaryDisplayIgnoresSceneTier: Bool, healthBarVisible: Bool, staminaBarVisible: Bool) -> Void {
        //DFProfile();
        DFLogNoSystem(this.debugEnabled, this, "EvaluateAllBarVisibility forceMomentaryDisplay: " + ToString(forceMomentaryDisplay));
        if this.displayManagedByParentGroup {
            DFLogNoSystem(this.debugEnabled, this, "EvaluateAllBarVisibility managed by parent group, returning.");
            return;
        }

        // Early exit - If already displaying over Stamina, exit.
        if this.m_displayingOverStamina {
            return;
        }

        // Early exit - If Stamina Bar is visible, hide immediately.
        if staminaBarVisible && !forceMomentaryDisplay {
            this.SetAllFadeOut(true);
            return;
        }

        let anySegmentActive: Bool = false;
        for bar in this.needsBars {
            let indicator: ref<DFHUDSegmentedIndicator> = bar as DFHUDSegmentedIndicator;
            for segment in indicator.m_segments {
                if Equals(segment.active, true) {
                    anySegmentActive = true;
                    break;
                }
            }
        }

        let currentSceneTier: GameplayTier;

        let playerStateMachineBlackboard: ref<IBlackboard> = this.GetPSMBlackboard(this.HUDSystem.player);
        let playerSMDef: ref<PlayerStateMachineDef> = GetAllBlackboardDefs().PlayerStateMachine;
        if IsDefined(playerStateMachineBlackboard) && IsDefined(playerSMDef) {
            currentSceneTier = IntEnum<GameplayTier>(playerStateMachineBlackboard.GetInt(playerSMDef.SceneTier));
        }

        // If Dark Future Updates aren't currently allowed, or if menus are blocking display, bail out.
        // SetAllDisplayContinuous() or SetAllDisplayMomentary() must be called in order for the bar to remain visible. If neither qualify, we hide them.
        if this.GameStateService.IsValidGameState(this, true) && !this.HUDSystem.HUDUIBlockedDueToMenuOpen && !this.HUDSystem.HUDUIBlockedDueToCameraControl {
            let nerveLockVisible: Bool = this.HUDSystem.IsNerveLockVisible();

            // Clear the Nerve Lock display flag.
            if !nerveLockVisible {
                this.m_hasPulsedOnThisLockDisplay = false;
            }
            
            if this.ShouldDisplayContinuously(anySegmentActive, currentSceneTier, healthBarVisible, staminaBarVisible, nerveLockVisible) {
                this.SetAllDisplayContinuous();

                for bar in this.needsBars {
                    let indicator: ref<DFHUDSegmentedIndicator> = bar as DFHUDSegmentedIndicator;
                    indicator.m_shadow.SetVisible(false);
                    indicator.m_iconshadow.SetVisible(false);
                }
                
                // If displaying continuously and the Nerve lock is visible, pulse the Humanity Loss segment (once).
                if nerveLockVisible {
                    for bar in this.needsBars {
                        let indicator: ref<DFHUDSegmentedIndicator> = bar as DFHUDSegmentedIndicator;
                        for segment in indicator.m_segments {
                            if Equals(segment.type, DFHUDSegmentedIndicatorSegmentType.HumanityLoss) && Equals(segment.active, true) {
                                (bar as DFHUDSegmentedIndicator).SetSegmentPulse(segment.type, 0.3);
                            }
                        }
                    }
                }

            // We ignore parent updates that might qualify for momentary display in order to avoid doubling up on momentary display lengths. See: OnFadeOutStart()
            } else if !fromParentUpdate {
                let ignoreSceneTier: Bool = this.m_groupBeingDisplayedAndIgnoringSceneTier || momentaryDisplayIgnoresSceneTier;
                let forceDisplay: Bool = this.m_groupBeingDisplayedAndIgnoringSceneTier || forceMomentaryDisplay;
                if this.ShouldDisplayMomentarily(forceDisplay, currentSceneTier, ignoreSceneTier, staminaBarVisible) {
                    this.SetAllDisplayMomentary(momentaryDisplayIgnoresSceneTier);

                    if staminaBarVisible {
                        this.m_displayingOverStamina = true;

                        for bar in this.needsBars {
                            let indicator: ref<DFHUDSegmentedIndicator> = bar as DFHUDSegmentedIndicator;
                            indicator.m_shadow.SetVisible(true);
                            indicator.m_iconshadow.SetVisible(true);
                        }
                    } else {
                        for bar in this.needsBars {
                            let indicator: ref<DFHUDSegmentedIndicator> = bar as DFHUDSegmentedIndicator;
                            indicator.m_shadow.SetVisible(false);
                            indicator.m_iconshadow.SetVisible(false);
                        }
                    }
                
                } else {
                    this.SetAllFadeOut();
                }

            } else {
                this.SetAllFadeOut();
            }
        
        } else {
            this.SetAllFadeOut();
        }
        
        // Now that we have made decisions using the previous value at least once, consume it.
        this.NormalizeAllPreviousValues();
    }

    private final func ShouldDisplayContinuously(anySegmentActive: Bool, currentSceneTier: GameplayTier, healthBarVisible: Bool, staminaBarVisible: Bool, nerveLockVisible: Bool) -> Bool {
        //DFProfile();
        DFLogNoSystem(this.debugEnabled, this, "ShouldDisplayContinuously anySegmentActive " + ToString(anySegmentActive) + ", currentSceneTier " + ToString(currentSceneTier));

        if Equals(currentSceneTier, GameplayTier.Tier1_FullGameplay) && anySegmentActive && healthBarVisible && !staminaBarVisible {
            // Contextual Display - Show continuously when any segment is active, the health bar is displayed, and the stamina bar is not displayed.
            return true;
        
        } else if !staminaBarVisible && nerveLockVisible {
            // Humanity Loss
            return true;
        }

        return false;
    }

    private final func ShouldDisplayMomentarily(forceMomentaryDisplay: Bool, currentSceneTier: GameplayTier, momentaryDisplayIgnoresSceneTier: Bool, staminaBarVisible: Bool) -> Bool {
        //DFProfile();
        // momentaryDisplayIgnoresSceneTier is used very selectively to display bars restoring in otherwise invalid scene tiers (while drinking, smoking, etc).

        if (!staminaBarVisible || forceMomentaryDisplay) && (momentaryDisplayIgnoresSceneTier || (Equals(currentSceneTier, GameplayTier.Tier1_FullGameplay) || Equals(currentSceneTier, GameplayTier.Tier2_StagedGameplay))) {
            if forceMomentaryDisplay {
                return true;
            }
            
            for bar in this.needsBars {
                let indicator = bar as DFHUDSegmentedIndicator;
                if NotEquals(indicator.GetCurrentSegmentValue(), indicator.m_previousSegmentValue) {
                    DFLogNoSystem(this.debugEnabled, this, "ShouldDisplayMomentarily different segments active");
                    return true;
                }
            }
        }
        
        return false;
    }

    private final func SetAllDisplayContinuous() -> Void {
        //DFProfile();
        DFLogNoSystem(this.debugEnabled, this, "SetAllDisplayContinuous");
        for bar in this.needsBars {
            bar.SetFadeIn(false);
        }
        this.UnregisterForFadeOut();

        for child in this.needsBarGroupChildren {
            child.SetDisplayManagedByParent(true);
            for bar in child.needsBars {
                bar.SetFadeIn(true);
            }
            child.UnregisterForFadeOut();
        }
    }

    private final func NormalizeAllPreviousValues() -> Void {
        //DFProfile();

        for bar in this.needsBars {
            let indicator = bar as DFHUDSegmentedIndicator;
            indicator.m_previousSegmentValue = indicator.GetCurrentSegmentValue();
        }

        for child in this.needsBarGroupChildren {
            for bar in child.needsBars {
                let indicator = bar as DFHUDSegmentedIndicator;
                indicator.m_previousSegmentValue = indicator.GetCurrentSegmentValue();
            }
        }
    }

    public final func OnFadeOutStart(fromParent: Bool) -> Void {
        //DFProfile();
        DFLogNoSystem(this.debugEnabled, this, "OnFadeOutStart fromParent: " + ToString(fromParent));

        // If currently being displayed regardless of scene tier, clear that flag.
        this.m_groupBeingDisplayedAndIgnoringSceneTier = false;

        if fromParent && this.displayManagedByParentGroup {
            // If initiated from a parent, break the relationship and decide for ourselves whether we should
            // still be displayed or not. Flagged as from parent update to skip erroneous momentary display (causes double-length display).
            this.displayManagedByParentGroup = false;
            this.EvaluateAllSegmentedIndicatorVisibility(false, true, false, this.HUDSystem.healthBarController.m_moduleShown, this.HUDSystem.staminaBarController.m_RootWidget.IsVisible());
        } else {
            this.m_displayingOverStamina = false;
            for bar in this.needsBars {
                bar.SetFadeOut();
            }
        }
    }

    public final func SetAllFadeOut(opt instant: Bool) -> Void {
        super.SetAllFadeOut(instant);

        this.m_displayingOverStamina = false;
    }
}

public class DFHUDSegmentedIndicator extends DFNeedsHUDBar {
    public let m_setupData: DFHUDSegmentedIndicatorSetupData;
    public let m_segments: array<DFHUDSegmentWidgetDatum>;
    public let m_previousSegmentValue: array<Bool>;
    public let m_shadow: ref<inkImage>;
    public let m_iconshadow: ref<inkImage>;

    public final func Init(setupData: DFHUDSegmentedIndicatorSetupData) -> Void {
        //DFProfile();
        this.m_setupData = setupData;
        this.CreateIndicator();
        this.CreateAnimations();
        // Initial Evaluate Visibility to be done after all bars added to group
    }

    private final func CreateIndicator() -> ref<inkCanvas> {
        //DFProfile();
        //
        // Create a segmented indicator bar.
        //
        let canvas: ref<inkCanvas> = new inkCanvas();
        canvas.SetName(this.m_setupData.widgetName);
        canvas.SetChildOrder(inkEChildOrder.Backward);
        canvas.SetSize(Vector2(this.m_setupData.canvasWidth, 100.0));
        canvas.SetTranslation(this.m_setupData.translationX, this.m_setupData.translationY);
        this.m_rootWidget = canvas;
        canvas.Reparent(this.m_setupData.parent);

        this.m_hasLock = false;

        let indicatorMain: ref<inkFlex> = new inkFlex();
        indicatorMain.SetName(n"indicatorMain");
        indicatorMain.SetAnchor(inkEAnchor.Centered);
        indicatorMain.SetAnchorPoint(Vector2(0.5, 0.5));
        indicatorMain.SetHAlign(inkEHorizontalAlign.Fill);
        indicatorMain.SetVAlign(inkEVerticalAlign.Fill);
        indicatorMain.SetSize(Vector2(100.0, 100.0));
        indicatorMain.Reparent(canvas);
        this.m_barMain = indicatorMain;

        let iconshadow: ref<inkImage> = new inkImage();
        iconshadow.SetName(n"iconshadow");
        iconshadow.SetVisible(false);
        iconshadow.SetOpacity(0.98);
        iconshadow.SetAffectsLayoutWhenHidden(false);
        iconshadow.SetAnchor(inkEAnchor.Centered);
        iconshadow.SetAnchorPoint(Vector2(0.5, 0.5));
        iconshadow.SetHAlign(inkEHorizontalAlign.Center);
        iconshadow.SetVAlign(inkEVerticalAlign.Center);
        iconshadow.SetContentHAlign(inkEHorizontalAlign.Fill);
        iconshadow.SetContentVAlign(inkEVerticalAlign.Fill);
        iconshadow.SetSize(Vector2(80.0, 40.0));
        iconshadow.SetShear(Vector2(0.5, 0.0));
        iconshadow.SetNineSliceScale(true);
        iconshadow.SetTranslation(-371.0, 0.0);
        iconshadow.SetBrushMirrorType(inkBrushMirrorType.NoMirror);
        iconshadow.SetBrushTileType(inkBrushTileType.NoTile);
        iconshadow.SetTintColor(HDRColor(0.0, 0.0, 0.0, 1.0));
        iconshadow.SetAtlasResource(r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas");
        iconshadow.SetTexturePart(n"shadowBlobText");
        iconshadow.Reparent(indicatorMain);
        this.m_iconshadow = iconshadow;

        let shadow: ref<inkImage> = new inkImage();
        shadow.SetName(n"shadow");
        shadow.SetVisible(false);
        shadow.SetOpacity(0.98);
        shadow.SetAffectsLayoutWhenHidden(false);
        shadow.SetAnchor(inkEAnchor.Centered);
        shadow.SetAnchorPoint(Vector2(0.5, 0.5));
        shadow.SetHAlign(inkEHorizontalAlign.Center);
        shadow.SetVAlign(inkEVerticalAlign.Center);
        shadow.SetContentHAlign(inkEHorizontalAlign.Fill);
        shadow.SetContentVAlign(inkEVerticalAlign.Fill);
        shadow.SetSize(Vector2(750.0, 40.0));
        shadow.SetShear(Vector2(0.5, 0.0));
        shadow.SetNineSliceScale(true);
        shadow.SetBrushMirrorType(inkBrushMirrorType.NoMirror);
        shadow.SetBrushTileType(inkBrushTileType.NoTile);
        shadow.SetTintColor(HDRColor(0.0, 0.0, 0.0, 1.0));
        shadow.SetAtlasResource(r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas");
        shadow.SetTexturePart(n"shadowBlobText");
        shadow.Reparent(indicatorMain);
        this.m_shadow = shadow;

        let icon: ref<inkImage> = new inkImage();
        icon.SetName(n"icon");
        icon.SetAffectsLayoutWhenHidden(false);
        icon.SetAnchor(inkEAnchor.TopLeft);
        icon.SetAnchorPoint(Vector2(0.5, 0.5));
        icon.SetHAlign(inkEHorizontalAlign.Center);
        icon.SetVAlign(inkEVerticalAlign.Center);
        icon.SetOpacity(0.4);
        icon.SetTranslation(-374.0, 0.0);
        icon.SetSize(Vector2(28.0, 28.0));
        icon.SetBrushMirrorType(inkBrushMirrorType.NoMirror);
        icon.SetBrushTileType(inkBrushTileType.NoTile);
        icon.SetTintColor(this.m_setupData.colorTheme.ActiveColor);
        icon.SetAtlasResource(this.m_setupData.iconPath);
        icon.SetTexturePart(this.m_setupData.iconName);
        icon.Reparent(indicatorMain);
        this.m_icon = icon;

        let wrapper: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        wrapper.SetName(n"wrapper");
        wrapper.SetAnchor(inkEAnchor.TopLeft);
        wrapper.SetHAlign(inkEHorizontalAlign.Center);
        wrapper.SetVAlign(inkEVerticalAlign.Center);
        wrapper.SetSize(Vector2(this.m_setupData.indicatorTotalWidth, 18.0));
        wrapper.SetMargin(inkMargin(8.0, 0.0, 0.0, 0.0));
        wrapper.SetFitToContent(false);
        wrapper.Reparent(indicatorMain);

        // Specific segment data goes below here

        let i: Int32 = 0;
        while i < ArraySize(this.m_setupData.segments) {
            let seg: DFHUDSegmentWidgetDatum;

            seg.type = this.m_setupData.segments[i].type;

            let segmentWrapper: ref<inkCanvas> = new inkCanvas();
            segmentWrapper.SetName(n"segmentWrapper" + StringToName(ToString(i)));
            segmentWrapper.SetSizeRule(inkESizeRule.Stretch);
            segmentWrapper.SetHAlign(inkEHorizontalAlign.Fill);
            segmentWrapper.SetVAlign(inkEVerticalAlign.Fill);
            segmentWrapper.SetMargin(inkMargin(0.0, 0.0, 5.0, 0.0));
            segmentWrapper.Reparent(wrapper);
            seg.widget = segmentWrapper;

            let segmentBg: ref<inkRectangle> = new inkRectangle();
            segmentBg.SetName(n"segmentBg" + StringToName(ToString(i)));
            segmentBg.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
            segmentBg.SetAnchor(inkEAnchor.Fill);
            segmentBg.SetHAlign(inkEHorizontalAlign.Fill);
            segmentBg.SetVAlign(inkEVerticalAlign.Center);
            segmentBg.SetOpacity(0.0);
            segmentBg.SetShear(Vector2(0.5, 0.0));
            segmentBg.SetSize(Vector2(100.0, 12.0));
            segmentBg.SetTintColor(this.m_setupData.colorTheme.FaintColor);
            segmentBg.Reparent(segmentWrapper);
            seg.bg = segmentBg;

            let segmentBorder: ref<inkBorderConcrete> = new inkBorderConcrete();
            segmentBorder.SetName(n"segmentBorder" + StringToName(ToString(i)));
            segmentBorder.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
            segmentBorder.SetAnchor(inkEAnchor.Fill);
            segmentBorder.SetHAlign(inkEHorizontalAlign.Fill);
            segmentBorder.SetVAlign(inkEVerticalAlign.Center);
            segmentBorder.SetOpacity(0.125);
            segmentBorder.SetShear(Vector2(0.5, 0.0));
            segmentBorder.SetSize(Vector2(100.0, 12.0));
            segmentBorder.SetThickness(2.0);
            segmentBorder.SetTintColor(this.m_setupData.colorTheme.MainColor);
            segmentBorder.Reparent(segmentWrapper);
            seg.border = segmentBorder;

            let segmentLabel: ref<inkText> = new inkText();
            segmentLabel.SetName(n"segmentLabel" + StringToName(ToString(i)));
            segmentLabel.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
            segmentLabel.SetAnchor(inkEAnchor.Centered);
            segmentLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily");
            segmentLabel.SetFontStyle(n"Medium");
            segmentLabel.SetTintColor(this.m_setupData.colorTheme.ActiveColor);
            segmentLabel.SetLetterCase(textLetterCase.UpperCase);
            segmentLabel.SetFontSize(13);
            segmentLabel.SetTracking(2);
            segmentLabel.SetText(GetLocalizedTextByKey(this.m_setupData.segments[i].abbreviatedNameKey));
            segmentLabel.SetHAlign(inkEHorizontalAlign.Center);
            segmentLabel.SetVAlign(inkEVerticalAlign.Center);
            segmentLabel.SetOpacity(0.125);
            segmentLabel.SetJustificationType(textJustificationType.Center);
            segmentLabel.SetHorizontalAlignment(textHorizontalAlignment.Center);
            segmentLabel.SetVerticalAlignment(textVerticalAlignment.Center);
            segmentLabel.SetAnchorPoint(Vector2(0.5, 0.3));
            segmentLabel.Reparent(segmentWrapper);
            seg.label = segmentLabel;

            ArrayPush(this.m_segments, seg);

            i += 1;
        }

        return canvas;
    }

    public final func UpdateColorTheme(themeName: DFBarColorThemeName) {
        //DFProfile();
        let newColorTheme: DFBarColorTheme = GetDarkFutureBarColorTheme(themeName);

        this.m_icon.SetTintColor(newColorTheme.ActiveColor);

        for segment in this.m_segments {
            segment.bg.SetTintColor(newColorTheme.FaintColor);
            segment.border.SetTintColor(newColorTheme.MainColor);
            segment.label.SetTintColor(newColorTheme.ActiveColor);
        }
    }

    public final func UpdateShear(shouldShear: Bool) {
        //DFProfile();
        let shear: Float = 0.0;
        if shouldShear {
            shear = 0.5;
        }

        for segment in this.m_segments {
            segment.bg.SetShear(Vector2(shear, 0.0));
            segment.border.SetShear(Vector2(shear, 0.0));
        }
    }

    public final func SetFadeIn(fromParent: Bool) -> Void {
        //DFProfile();
        DFLogNoSystem(this.debugEnabled, this, "SetFadeIn name: " + ToString(this.m_setupData.widgetName) + " m_shouldForceBrightOnNextFadeIn: " + ToString(this.m_shouldForceBrightOnNextFadeIn));
        if IsDefined(this.m_barGroup) && this.m_barGroup.displayManagedByParentGroup && !fromParent {
            return;
        }

        this.StopAnimProxyIfDefined(this.m_fadeIn_anim_proxy);

        // Always fade the widget in at 1.0.
        this.m_fadeInTargetTransparency = 1.0;

        this.m_fadeIn_anim = new inkAnimDef();
        let fadeInInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
        fadeInInterp.SetStartTransparency(this.m_rootWidget.GetOpacity());
        fadeInInterp.SetEndTransparency(this.m_fadeInTargetTransparency);
        fadeInInterp.SetDuration(0.5);
        this.m_fadeIn_anim.AddInterpolator(fadeInInterp);
        this.m_fadeIn_anim_proxy = this.m_rootWidget.PlayAnimation(this.m_fadeIn_anim);
    }

    public final func EvaluateSegmentedIndicatorGroupVisibility(forceMomentaryDisplay: Bool, momentaryDisplayIgnoresSceneTier: Bool, healthBarVisible: Bool, staminaBarVisible: Bool) -> Void {
        //DFProfile();
        if IsDefined(this.m_barGroup) {
            if this.m_barGroup.displayManagedByParentGroup && IsDefined(this.m_barGroup.needsBarGroupParent) {
                (this.m_barGroup.needsBarGroupParent as DFHUDSegmentedIndicatorGroup).EvaluateAllSegmentedIndicatorVisibility(forceMomentaryDisplay, false, momentaryDisplayIgnoresSceneTier, healthBarVisible, staminaBarVisible);
            } else {
                (this.m_barGroup as DFHUDSegmentedIndicatorGroup).EvaluateAllSegmentedIndicatorVisibility(forceMomentaryDisplay, false, momentaryDisplayIgnoresSceneTier, healthBarVisible, staminaBarVisible);
            }
        }
    }

    public final func SetActive(type: DFHUDSegmentedIndicatorSegmentType, active: Bool) -> Void {
        let i: Int32 = 0;
        let typeFound: Bool = false;

        while i < ArraySize(this.m_segments) && !typeFound {
            if Equals(this.m_segments[i].type, type) {
                typeFound = true;
                this.m_segments[i].active = active;

                if active {
                    this.m_segments[i].label.SetOpacity(0.8);
                    this.m_segments[i].border.SetOpacity(0.4);
                    this.m_segments[i].bg.SetOpacity(0.4);
                } else {
                    this.m_segments[i].label.SetOpacity(0.125);
                    this.m_segments[i].border.SetOpacity(0.125);
                    this.m_segments[i].bg.SetOpacity(0.0);
                }

                this.EvaluateSegmentedIndicatorGroupVisibility(true, false, this.m_barGroup.HUDSystem.healthBarController.m_moduleShown, this.m_barGroup.HUDSystem.staminaBarController.m_RootWidget.IsVisible());
            }
            i += 1;
        }
    }

    public final func GetCurrentSegmentValue() -> array<Bool> {
        let currentSegmentValue: array<Bool>;
        
        for segment in this.m_segments {
            ArrayPush(currentSegmentValue, segment.active);
        }
        
        return currentSegmentValue;
    }

    public final func SetSegmentPulse(segmentType: DFHUDSegmentedIndicatorSegmentType, rate: Float) -> Void {
        //DFProfile();

        if !this.m_pulsing && !(this.m_barGroup as DFHUDSegmentedIndicatorGroup).m_hasPulsedOnThisLockDisplay {
            this.m_pulsing = true;
            (this.m_barGroup as DFHUDSegmentedIndicatorGroup).m_hasPulsedOnThisLockDisplay = true;

            let segmentToPulse: ref<inkCanvas>;
            for segment in this.m_segments {
                if Equals(segment.type, segmentType) {
                    segmentToPulse = segment.widget;
                    break;
                }
            }

            this.m_pulse_anim.Configure(segmentToPulse, 1.00, 0.10, rate);
            this.m_pulse_anim.Start(false);
            this.RegisterForPulseStop();
        }
    }

    public final func PulseInjurySegmentIfInjured() -> Void {
        for segment in this.m_segments {
            if Equals(segment.type, DFHUDSegmentedIndicatorSegmentType.Injury) && Equals(segment.active, true) {
                this.SetSegmentPulse(DFHUDSegmentedIndicatorSegmentType.Injury, 0.5);
                break;       
            }
        }
    }
}
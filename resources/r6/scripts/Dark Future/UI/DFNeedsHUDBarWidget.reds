// -----------------------------------------------------------------------------
// DFNeedsHUDBarWidget
// -----------------------------------------------------------------------------
//
// - Basic Need HUD Bar Meter Widget definition and logic.
//

module DarkFuture.UI

import DarkFuture.Logging.*
import DarkFuture.DelayHelper.*
import DarkFuture.Utils.{
    DFBarColorTheme,
    DFBarColorThemeName,
    GetDarkFutureBarColorTheme
}
import DarkFuture.Services.{
    DFGameStateService,
    DFPlayerStateService
}
import DarkFuture.Settings.DFSettings

public struct DFNeedsHUDBarSetupData {
    public let parent: ref<inkCompoundWidget>;
    public let widgetName: CName;
    public let iconPath: ResRef;
    public let iconName: CName;
    public let colorTheme: DFBarColorTheme;
    public let canvasWidth: Float;
    public let barWidth: Float;
    public let translationX: Float;
    public let translationY: Float;
    public let showEmptyBar: Bool;
}

public class DFNeedsHUDBarGroupFadeOutDelayCallback extends DFDelayCallback {
	public let DFNeedsHUDBarGroup: wref<DFNeedsHUDBarGroup>;
    public let fromParent: Bool;

	public static func Create(dfNeedsHUDBarGroup: wref<DFNeedsHUDBarGroup>, fromParent: Bool) -> ref<DFDelayCallback> {
		let self: ref<DFNeedsHUDBarGroupFadeOutDelayCallback> = new DFNeedsHUDBarGroupFadeOutDelayCallback();
		self.DFNeedsHUDBarGroup = dfNeedsHUDBarGroup;
        self.fromParent = fromParent;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFNeedsHUDBarGroup.m_fadeOutDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFNeedsHUDBarGroup.OnFadeOutStart(this.fromParent);
	}
}

public class DFNeedsHUDBarPulseStopDelayCallback extends DFDelayCallback {
	public let DFNeedsHUDBar: wref<DFNeedsHUDBar>;

	public static func Create(DFNeedsHUDBar: wref<DFNeedsHUDBar>) -> ref<DFDelayCallback> {
		let self: ref<DFNeedsHUDBarPulseStopDelayCallback> = new DFNeedsHUDBarPulseStopDelayCallback();
		self.DFNeedsHUDBar = DFNeedsHUDBar;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFNeedsHUDBar.m_pulseStopDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFNeedsHUDBar.OnPulseStop();
	}
}

public class DFNeedsHUDBarGroupDisplayRecheckAfterForceBrightDelayCallback extends DFDelayCallback {
	public let DFNeedsHUDBarGroup: wref<DFNeedsHUDBarGroup>;

	public static func Create(DFNeedsHUDBarGroup: wref<DFNeedsHUDBarGroup>) -> ref<DFDelayCallback> {
		let self: ref<DFNeedsHUDBarGroupDisplayRecheckAfterForceBrightDelayCallback> = new DFNeedsHUDBarGroupDisplayRecheckAfterForceBrightDelayCallback();
		self.DFNeedsHUDBarGroup = DFNeedsHUDBarGroup;
		return self;
	}

	public func InvalidateDelayID() -> Void {
		this.DFNeedsHUDBarGroup.m_displayRecheckAfterForceBrightDelayID = GetInvalidDelayID();
	}

	public func Callback() -> Void {
		this.DFNeedsHUDBarGroup.OnDisplayRecheckAfterForceBright();
	}
}

public class DFNeedsHUDBarGroup {
    private let debugEnabled: Bool = false;

    /*
     *  A class that collects a group of Needs Bars.
     *  Allows the group to be treated as if they were
     *  a single bar for display purposes.
     *
     *  Also allows Bar Groups to be grouped together into
     *  parent / child relationships. If the parent is displayed,
     *  all children mirror the display of the parent. This
     *  allows the Nerve Bar Group (child) to always be displayed
     *  when the Physical Needs Bar Group (parent) is displayed,
     *  to avoid strange-looking negative space in the UI.
     */
    private let needsBars: array<ref<DFNeedsHUDBar>>;
    private let needsBarGroupChildren: array<ref<DFNeedsHUDBarGroup>>;
    private let needsBarGroupParent: ref<DFNeedsHUDBarGroup>;
    private let displayManagedByParentGroup: Bool = false;
    private let alwaysVisibleInDanger: Bool;
    private let GameStateService: ref<DFGameStateService>;
    private let HUDSystem: ref<DFHUDSystem>;
    private let DelaySystem: ref<DelaySystem>;
    private let PlayerStateService: wref<DFPlayerStateService>;
    private let Settings: ref<DFSettings>;
    
    private let m_fadeOutDelayID: DelayID;
    private let m_fadeOutDelayInterval: Float = 5.0;

    private let m_displayRecheckAfterForceBrightDelayID: DelayID;
    private let m_displayRecheckAfterForceBrightDelayInterval: Float = 2.5;

    public final func Init(attachedPlayer: ref<PlayerPuppet>, alwaysVisibleInDanger: Bool) -> Void {
        let gameInstance = GetGameInstance();
        this.HUDSystem = DFHUDSystem.GetInstance(gameInstance);
        this.GameStateService = DFGameStateService.GetInstance(gameInstance);
        this.PlayerStateService = DFPlayerStateService.GetInstance(gameInstance);
        this.Settings = DFSettings.GetInstance(gameInstance);
        this.DelaySystem = GameInstance.GetDelaySystem(gameInstance);
        this.alwaysVisibleInDanger = alwaysVisibleInDanger;
    }

    private final func GetPSMBlackboard(player: ref<PlayerPuppet>) -> ref<IBlackboard> {
        return GameInstance.GetBlackboardSystem(GetGameInstance()).GetLocalInstanced(player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    }

    public final func AddBarToGroup(bar: ref<DFNeedsHUDBar>) -> Void {
        ArrayPush(this.needsBars, bar);
        bar.m_barGroup = this;
    }

    public final func AddGroupToChildren(group: ref<DFNeedsHUDBarGroup>) -> Void {
        ArrayPush(this.needsBarGroupChildren, group);
        group.AddParentGroup(this);
    }

    public final func AddParentGroup(group: ref<DFNeedsHUDBarGroup>) -> Void {
        this.needsBarGroupParent = group;
    }

    public final func BarGroupSetupDone() -> Void {
        // We've declared that setting up the group is now complete,
        // do an initial visibility update.
        this.EvaluateAllBarVisibility(false);
    }

    public final func EvaluateAllBarVisibility(forceMomentaryDisplay: Bool, opt fromParentUpdate: Bool, opt momentaryDisplayIgnoresSceneTier: Bool) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "EvaluateAllBarVisibility forceMomentaryDisplay: " + ToString(forceMomentaryDisplay));
        if this.displayManagedByParentGroup {
            DFLogNoSystem(this.debugEnabled, this, "EvaluateAllBarVisibility managed by parent group, returning.");
            return;
        }

        let lowestValueInGroup: Float = 1.0;
        for bar in this.needsBars {
            if bar.m_currentValue < lowestValueInGroup {
                lowestValueInGroup = bar.m_currentValue;
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
            if this.ShouldDisplayContinuously(lowestValueInGroup, currentSceneTier) {
                this.SetAllDisplayContinuous(lowestValueInGroup);

            // We ignore parent updates that might qualify for momentary display in order to avoid doubling up on momentary display lengths. See: OnFadeOutStart()
            } else if !fromParentUpdate && this.ShouldDisplayMomentarily(forceMomentaryDisplay, currentSceneTier, momentaryDisplayIgnoresSceneTier) {
                this.SetAllDisplayMomentary(lowestValueInGroup);

            } else {
                this.SetAllFadeOut();
            }
        } else {
            this.SetAllFadeOut();
        }
        
        // Now that we have made decisions using the previous value at least once, consume it.
        this.NormalizeAllPreviousValues();
    }

    private final func NormalizeAllPreviousValues() -> Void {
        for bar in this.needsBars {
            bar.m_previousValue = bar.m_currentValue;
        }

        for child in this.needsBarGroupChildren {
            for bar in child.needsBars {
                bar.m_previousValue = bar.m_currentValue;
            }
        }
    }

    private final func ShouldDisplayContinuously(lowestValueInGroup: Float, currentSceneTier: GameplayTier) -> Bool {
        DFLogNoSystem(this.debugEnabled, this, "ShouldDisplayContinuously lowestValueInGroup " + ToString(lowestValueInGroup) + ", currentSceneTier " + ToString(currentSceneTier));

        if Equals(currentSceneTier, GameplayTier.Tier1_FullGameplay) {
            if this.alwaysVisibleInDanger {
                if this.PlayerStateService.GetInDanger() {
                    return true;
                }
                if lowestValueInGroup <= (this.Settings.needHUDUIAlwaysOnThreshold / 100.0) {
                    return true;
                }
            } else {
                if this.PlayerStateService.GetInDanger() {
                    DFLogNoSystem(this.debugEnabled, this, "alwaysVisibleInDanger false GetInDanger true");
                    return false;
                }
                if lowestValueInGroup <= (this.Settings.needHUDUIAlwaysOnThreshold / 100.0) {
                    DFLogNoSystem(this.debugEnabled, this, "alwaysVisibleInDanger false lowestValueInGroup <= always on threshold");
                    return true;
                }
            }
        }

        return false;
    }

    private final func ShouldDisplayMomentarily(forceMomentaryDisplay: Bool, currentSceneTier: GameplayTier, momentaryDisplayIgnoresSceneTier: Bool) -> Bool {
        // momentaryDisplayIgnoresSceneTier is used very selectively to display bars restoring in otherwise invalid scene tiers (while drinking, smoking, etc).

        if momentaryDisplayIgnoresSceneTier || (Equals(currentSceneTier, GameplayTier.Tier1_FullGameplay) || Equals(currentSceneTier, GameplayTier.Tier2_StagedGameplay)) {
            if forceMomentaryDisplay {
                return true;
            }
            for bar in this.needsBars {
                if bar.m_previousValue > 0.85 && bar.m_currentValue <= 0.85 {
                    return true;
                
                } else if AbsF(bar.m_previousValue - bar.m_currentValue) > 0.01 {
                    DFLogNoSystem(this.debugEnabled, this, "ShouldDisplayMomentarily change > 0.01");
                    return true;
                }
            }
        }
        
        return false;
    }

    private final func SetAllDisplayContinuous(lowestValueInGroup: Float) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "SetAllDisplayContinuous lowestValueInGroup: " + ToString(lowestValueInGroup));
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

    private final func SetAllDisplayMomentary(lowestValueInGroup: Float) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "SetAllDisplayMomentary lowestValueInGroup: " + ToString(lowestValueInGroup));
        for bar in this.needsBars {
            bar.SetFadeIn(false);
        }
        this.RegisterForFadeOut();

        for child in this.needsBarGroupChildren {
            child.SetDisplayManagedByParent(true);
            for bar in child.needsBars {
                bar.SetFadeIn(true);
            }
            child.RegisterForFadeOut(true);
        }
    }

    private final func SetAllFadeOut() -> Void {
        if this.m_fadeOutDelayID != GetInvalidDelayID() {
            if this.HUDSystem.HUDUIBlockedDueToMenuOpen || this.HUDSystem.HUDUIBlockedDueToCameraControl {
                // Allow the bars to fade out.
                this.UnregisterForFadeOut();
            } else {
                // For any other reason, ignore this request.
                return;
            }
        }

        DFLogNoSystem(this.debugEnabled, this, "SetAllFadeOut");
        for bar in this.needsBars {
            bar.SetFadeOut();
        }

        for child in this.needsBarGroupChildren {
            child.SetDisplayManagedByParent(false);
        }
    }

    public final func SetDisplayManagedByParent(managedByParentGroup: Bool) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "SetDisplayManagedByParent managedByParentGroup: " + ToString(managedByParentGroup));
        this.displayManagedByParentGroup = managedByParentGroup;

        if !managedByParentGroup {
            this.EvaluateAllBarVisibility(false);
        }
    }

    private final func RegisterForFadeOut(opt fromParent: Bool) -> Void {
        RegisterDFDelayCallback(this.DelaySystem, DFNeedsHUDBarGroupFadeOutDelayCallback.Create(this, fromParent), this.m_fadeOutDelayID, this.m_fadeOutDelayInterval, true);
    }

    private final func UnregisterForFadeOut() -> Void {
        UnregisterDFDelayCallback(this.DelaySystem, this.m_fadeOutDelayID);
    }

    // Typically, Force Bright is used to force the bar to display brightly when the player has taken an action that affects it (consuming something, using something).
    // This registers for a callback that brings the bar back down to normal opacity after a short duration.
    private final func RegisterForDisplayRecheckAfterForceBright() -> Void {
        // If we aren't actively managed by a parent group, try to register against our group so that only our bars briefly display.
        // Used for displaying only the Nerve bar when i.e. stepping out of the shower, even if hungry, thirsty, or tired.

        if this.displayManagedByParentGroup && IsDefined(this.needsBarGroupParent) {
            RegisterDFDelayCallback(this.DelaySystem, DFNeedsHUDBarGroupDisplayRecheckAfterForceBrightDelayCallback.Create(this.needsBarGroupParent), this.m_displayRecheckAfterForceBrightDelayID, this.m_displayRecheckAfterForceBrightDelayInterval, true);
        } else {
            RegisterDFDelayCallback(this.DelaySystem, DFNeedsHUDBarGroupDisplayRecheckAfterForceBrightDelayCallback.Create(this), this.m_displayRecheckAfterForceBrightDelayID, this.m_displayRecheckAfterForceBrightDelayInterval, true);
        }
    }

    public final func OnDisplayRecheckAfterForceBright() -> Void {
        DFLogNoSystem(this.debugEnabled, this, "OnDisplayRecheckAfterForceBright");
        for bar in this.needsBars {
            bar.SetForceBright(false);
        }

        for child in this.needsBarGroupChildren {
            for bar in child.needsBars {
                bar.SetForceBright(false);
            }
        }
        
        if this.displayManagedByParentGroup && IsDefined(this.needsBarGroupParent) {
            // Between registering for this callback and now, we became managed by a parent group. This can cause the bar's opacity to "stick" to a bright value
            // for longer than intended, because EvaluateAllBarVisibility() will early exit as we no longer manage our own display. Try again on the group parent.
            DFLogNoSystem(this.debugEnabled, this, "FAILSAFE: OnDisplayRecheckAfterForceBright called back to a Needs Bar Group that is managed by a parent! Calling the parent's implementation instead.");
            this.needsBarGroupParent.EvaluateAllBarVisibility(true);
        } else {
            this.EvaluateAllBarVisibility(true);
        }
    }

    public final func OnFadeOutStart(fromParent: Bool) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "OnFadeOutStart fromParent: " + ToString(fromParent));
        if fromParent && this.displayManagedByParentGroup {
            // If initiated from a parent, break the relationship and decide for ourselves whether we should
            // still be displayed or not. Flagged as from parent update to skip erroneous momentary display (causes double-length display).
            this.displayManagedByParentGroup = false;
            this.EvaluateAllBarVisibility(false, true);
        } else {
            for bar in this.needsBars {
                bar.SetFadeOut();
            }
        }
    }
}

public class DFNeedsHUDBar extends inkCanvas {
    private let debugEnabled: Bool = false;

    public let m_setupData: DFNeedsHUDBarSetupData;
    public let m_barGroup: ref<DFNeedsHUDBarGroup>;

    private let m_width: Float;
    private let m_height: Float;

    private let m_rootWidget: ref<inkCanvas>;
    private let m_icon: ref<inkImage>;
    private let m_bg: ref<inkRectangle>;
    private let m_border: ref<inkBorderConcrete>;
    private let m_barMain: ref<inkFlex>;
    private let m_fullBar: ref<inkRectangle>;
    private let m_emptyBar: ref<inkRectangle>;
    private let m_barcap: ref<inkRectangle>;
    private let m_changePositiveBar: ref<inkRectangle>;
    private let m_changeNegativeBar: ref<inkRectangle>;

    private let m_full_anim_proxy: ref<inkAnimProxy>;
    private let m_full_anim: ref<inkAnimDef>;
    private let m_changePositive_anim_proxy: ref<inkAnimProxy>;
    private let m_changePositive_anim: ref<inkAnimDef>;
    private let m_changeNegative_anim_proxy: ref<inkAnimProxy>;
    private let m_changeNegative_anim: ref<inkAnimDef>;
    private let m_fadeIn_anim_proxy: ref<inkAnimProxy>;
    private let m_fadeIn_anim: ref<inkAnimDef>;
    private let m_fadeOut_anim_proxy: ref<inkAnimProxy>;
    private let m_fadeOut_anim: ref<inkAnimDef>;
    private let m_pulse_anim: ref<PulseAnimation>;
    private let m_pulsing: Bool = false;

    private let m_currentValue: Float = 1.0;
    private let m_previousValue: Float = 1.0;
    private let m_MaxChangeNegativeBarFlashSize: Float = 500.0;
    private let m_animDuration: Float = 2.0;
    private let m_inDanger: Bool = false;

    private let m_pulseStopDelayID: DelayID;
    private let m_pulseStopDelayInterval: Float = 3.0;
    private let m_continuousPulseAtLowThresholdInCombat: Bool = false;
    private let m_continuousPulseThreshold: Float = 0.0;

    private let m_shouldForceBrightOnNextFadeIn: Bool = false;

    public final func Init(setupData: DFNeedsHUDBarSetupData) -> Void {
        this.m_setupData = setupData;
        this.CreateBar();
        this.CreateAnimations();
        this.SetDefaultValues();
        // Initial Evaluate Visibility to be done after all bars added to group
    }

    public final func SetDefaultValues() -> Void {
        let tempSize: Vector2 = this.m_fullBar.GetSize();
        this.m_width = tempSize.X;
        this.m_height = tempSize.Y;
        this.m_fullBar.SetSize(new Vector2(this.m_width, this.m_height));
        this.m_changePositiveBar.SetSize(new Vector2(0.00, this.m_height));
        this.m_changeNegativeBar.SetSize(new Vector2(0.00, this.m_height));
    }

    public final func SetPulseContinuouslyAtLowThreshold(pulse: Bool, opt threshold: Float) -> Void {
        this.m_continuousPulseAtLowThresholdInCombat = pulse;
        this.m_continuousPulseThreshold = threshold;
    }

    public final func SetInDanger(inDanger: Bool) -> Void {
        this.m_inDanger = inDanger;
        this.EvaluateBarPulse(this.m_currentValue, this.m_previousValue);
    }

    private final func CreateBar() -> ref<inkCanvas> {
        //
        // Recreate a custom Stamina-like bar.
        //
        let canvas: ref<inkCanvas> = new inkCanvas();
        canvas.SetName(this.m_setupData.widgetName);
        canvas.SetChildOrder(inkEChildOrder.Backward);
        canvas.SetSize(new Vector2(this.m_setupData.canvasWidth, 100.0));
        canvas.SetTranslation(this.m_setupData.translationX, this.m_setupData.translationY);
        this.m_rootWidget = canvas;
        canvas.Reparent(this.m_setupData.parent);

        let barMain: ref<inkFlex> = new inkFlex();
        barMain.SetName(n"barMain");
        barMain.SetAnchor(inkEAnchor.Centered);
        barMain.SetAnchorPoint(new Vector2(0.5, 0.5));
        barMain.SetHAlign(inkEHorizontalAlign.Left);
        barMain.SetVAlign(inkEVerticalAlign.Top);
        barMain.SetSize(new Vector2(100.0, 100.0));
        barMain.Reparent(canvas);
        this.m_barMain = barMain;

        let icon: ref<inkImage> = new inkImage();
        icon.SetName(n"icon");
        icon.SetAffectsLayoutWhenHidden(true);
        icon.SetAnchor(inkEAnchor.TopLeft);
        icon.SetAnchorPoint(new Vector2(0.5, 0.5));
        icon.SetHAlign(inkEHorizontalAlign.Left);
        icon.SetVAlign(inkEVerticalAlign.Center);
        icon.SetMargin(new inkMargin(-35.0, 0.0, 0.0, 0.0));
        icon.SetSize(new Vector2(28.0, 28.0));
        icon.SetBrushMirrorType(inkBrushMirrorType.NoMirror);
        icon.SetBrushTileType(inkBrushTileType.NoTile);
        icon.SetTintColor(this.m_setupData.colorTheme.ActiveColor);
        icon.SetAtlasResource(this.m_setupData.iconPath);
        icon.SetTexturePart(this.m_setupData.iconName);
        icon.Reparent(barMain);
        this.m_icon = icon;

        let wrapper: ref<inkFlex> = new inkFlex();
        wrapper.SetName(n"wrapper");
        wrapper.SetAnchor(inkEAnchor.TopLeft);
        wrapper.SetHAlign(inkEHorizontalAlign.Left);
        wrapper.SetVAlign(inkEVerticalAlign.Center);
        wrapper.SetSize(new Vector2(100.0, 100.0));
        wrapper.Reparent(barMain);

        let bg: ref<inkRectangle> = new inkRectangle();
        bg.SetName(n"bg");
        bg.SetHAlign(inkEHorizontalAlign.Left);
        bg.SetVAlign(inkEVerticalAlign.Center);
        bg.SetMargin(new inkMargin(5.0, 0.0, 0.0, 0.0));
        bg.SetOpacity(0.3);
        bg.SetShear(new Vector2(0.5, 0.0));
        bg.SetRenderTransformPivot(new Vector2(1.0, 0.5));
        bg.SetSize(new Vector2(this.m_setupData.barWidth, 10.0));
        bg.SetTintColor(this.m_setupData.colorTheme.FaintColor);
        bg.Reparent(wrapper);
        this.m_bg = bg;

        let logic: ref<inkHorizontalPanel> = new inkHorizontalPanel();
        logic.SetName(n"logic");
        logic.SetHAlign(inkEHorizontalAlign.Left);
        logic.SetVAlign(inkEVerticalAlign.Center);
        logic.SetMargin(new inkMargin(-1.0, 0.0, 0.0, 0.0));
        logic.SetSize(240.0, 28.0);
        logic.Reparent(wrapper);

        let empty: ref<inkRectangle> = new inkRectangle();
        empty.SetName(n"empty");
        empty.SetHAlign(inkEHorizontalAlign.Right);
        empty.SetVAlign(inkEVerticalAlign.Center);
        empty.SetShear(new Vector2(0.5, 0.0));
        empty.SetSize(new Vector2(0.0, 10.0));
        empty.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        empty.BindProperty(n"tintColor", n"MainColors.MildRed");
        empty.SetVisible(this.m_setupData.showEmptyBar);
        empty.Reparent(wrapper);
        this.m_emptyBar = empty;

        let border: ref<inkBorderConcrete> = new inkBorderConcrete();
        border.SetName(n"border");
        border.SetMargin(new inkMargin(5.0, 0.0, 0.0, 0.0));
        border.SetHAlign(inkEHorizontalAlign.Fill);
        border.SetVAlign(inkEVerticalAlign.Center);
        border.SetOpacity(0.5);
        border.SetShear(new Vector2(0.5, 0.0));
        border.SetSize(new Vector2(100.0, 12.0));
        border.SetThickness(2.0);
        border.SetTintColor(this.m_setupData.colorTheme.ActiveColor);
        border.Reparent(wrapper);
        this.m_border = border;

        let full: ref<inkRectangle> = new inkRectangle();
        full.SetName(n"full");
        full.SetHAlign(inkEHorizontalAlign.Left);
        full.SetVAlign(inkEVerticalAlign.Center);
        full.SetShear(new Vector2(0.5, 0.0));
        full.SetTranslation(6.0, 0.0);
        full.SetSize(new Vector2(this.m_setupData.barWidth, 10.0));
        full.SetTintColor(this.m_setupData.colorTheme.MainColor);
        full.Reparent(logic);
        this.m_fullBar = full;

        let barcap: ref<inkRectangle> = new inkRectangle();
        barcap.SetName(n"barcap");
        barcap.SetHAlign(inkEHorizontalAlign.Left);
        barcap.SetVAlign(inkEVerticalAlign.Center);
        barcap.SetSize(new Vector2(6.0, 10.0));
        barcap.SetShear(new Vector2(0.5, 0.0));
        barcap.SetTintColor(this.m_setupData.colorTheme.ActiveColor);
        barcap.SetVisible(false);
        barcap.Reparent(logic);
        this.m_barcap = barcap;

        let changeP: ref<inkRectangle> = new inkRectangle();
        changeP.SetName(n"changeP");
        changeP.SetHAlign(inkEHorizontalAlign.Left);
        changeP.SetVAlign(inkEVerticalAlign.Center);
        changeP.SetShear(new Vector2(0.5, 0.0));
        changeP.SetTranslation(6.0, 0.0);
        changeP.SetSize(new Vector2(0.0, 15.0));
        changeP.SetTintColor(this.m_setupData.colorTheme.ChangePositiveColor);
        changeP.SetVisible(false);
        changeP.Reparent(logic);
        this.m_changePositiveBar = changeP;

        let changeN: ref<inkRectangle> = new inkRectangle();
        changeN.SetName(n"changeN");
        changeN.SetAnchor(inkEAnchor.BottomLeft);
        changeN.SetHAlign(inkEHorizontalAlign.Left);
        changeN.SetVAlign(inkEVerticalAlign.Center);
        changeN.SetShear(new Vector2(0.5, 0.0));
        changeN.SetSize(new Vector2(5.0, 15.0));
        changeN.SetTintColor(this.m_setupData.colorTheme.ChangeNegativeColor);
        changeN.Reparent(wrapper);
        this.m_changeNegativeBar = changeN;

        return canvas;
    }

    public final func UpdateColorTheme(themeName: DFBarColorThemeName) {
        let newColorTheme: DFBarColorTheme = GetDarkFutureBarColorTheme(themeName);
        this.m_icon.SetTintColor(newColorTheme.ActiveColor);
        this.m_bg.SetTintColor(newColorTheme.FaintColor);
        this.m_border.SetTintColor(newColorTheme.ActiveColor);
        this.m_fullBar.SetTintColor(newColorTheme.MainColor);
        this.m_barcap.SetTintColor(newColorTheme.ActiveColor);
        this.m_changePositiveBar.SetTintColor(newColorTheme.ChangePositiveColor);
        this.m_changeNegativeBar.SetTintColor(newColorTheme.ChangeNegativeColor);
    }

    public final func UpdateShear(shouldShear: Bool) {
        let shear: Float = 0.0;
        if shouldShear {
            shear = 0.5;
        }

        this.m_bg.SetShear(new Vector2(shear, 0.0));
        this.m_emptyBar.SetShear(new Vector2(shear, 0.0));
        this.m_border.SetShear(new Vector2(shear, 0.0));
        this.m_fullBar.SetShear(new Vector2(shear, 0.0));
        this.m_barcap.SetShear(new Vector2(shear, 0.0));
        this.m_changePositiveBar.SetShear(new Vector2(shear, 0.0));
        this.m_changeNegativeBar.SetShear(new Vector2(shear, 0.0));
    }

    private final func StopAnimProxyIfDefined(animProxy: ref<inkAnimProxy>) -> Void {
        if IsDefined(animProxy) {
            animProxy.Stop();
        }
    }

    public final func SetForceBright(forceBright: Bool) -> Void {
        this.m_shouldForceBrightOnNextFadeIn = forceBright;
    }

    public final func SetProgress(newValue: Float, forceMomentaryDisplay: Bool, instant: Bool, momentaryDisplayIgnoresSceneTier: Bool) -> Void {
        let barSize: Vector2;
        let fullBarSize: Vector2;
        let negativeMargin: inkMargin;
        let sizeChangeNegative: Float;
        let sizeChangePositive: Float;
        let sizeE: Float;
        let sizeF: Float;
        let sizeInterpolator: ref<inkAnimSize>;
        let visualChangeNegativeMax: Float;

        this.m_previousValue = this.m_currentValue;
        this.m_currentValue = newValue;

        this.m_barcap.SetVisible(newValue <= 0.99 && newValue >= 0.01);

        if instant {
            this.StopAnimProxyIfDefined(this.m_full_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_changePositive_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_changeNegative_anim_proxy);

            this.m_fullBar.SetSize(new Vector2(this.m_width * this.m_currentValue, this.m_height));
            this.m_changePositiveBar.SetSize(new Vector2(0.00, this.m_height));
            this.m_changeNegativeBar.SetSize(new Vector2(0.00, this.m_height));

        } else {
            if this.m_previousValue < this.m_currentValue {
                barSize = this.m_changePositiveBar.GetSize();
                sizeChangePositive = ClampF(barSize.X / this.m_width + AbsF(this.m_previousValue - this.m_currentValue), 0.00, 1.00);
                if this.m_changeNegative_anim_proxy.IsPlaying() {
                    barSize = this.m_changeNegativeBar.GetSize();
                    sizeChangeNegative = ClampF(barSize.X / this.m_width - AbsF(this.m_previousValue - this.m_currentValue), 0.00, 1.00);
                } else {
                    sizeChangeNegative = 0.00;
                };
            } else {
                barSize = this.m_changeNegativeBar.GetSize();
                sizeChangeNegative = ClampF(barSize.X / this.m_width + AbsF(this.m_previousValue - this.m_currentValue), 0.00, 1.00);
                if IsDefined(this.m_changePositive_anim_proxy) && this.m_changePositive_anim_proxy.IsPlaying() {
                    barSize = this.m_changePositiveBar.GetSize();
                    sizeChangePositive = ClampF(barSize.X / this.m_width - AbsF(this.m_previousValue - this.m_currentValue), 0.00, 1.00);
                } else {
                    sizeChangePositive = 0.00;
                };
            };
            sizeF = ClampF(this.m_currentValue - sizeChangePositive, 0.00, 1.00);
            sizeE = ClampF(1.00 - this.m_currentValue - sizeChangeNegative, 0.00, 1.00);
            
            this.StopAnimProxyIfDefined(this.m_full_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_changePositive_anim_proxy);
            this.StopAnimProxyIfDefined(this.m_changeNegative_anim_proxy);
            
            this.m_full_anim = new inkAnimDef();
            sizeInterpolator = new inkAnimSize();
            sizeInterpolator.SetStartSize(new Vector2(this.m_width * sizeF, this.m_height));
            sizeInterpolator.SetEndSize(new Vector2(this.m_width * this.m_currentValue, this.m_height));
            sizeInterpolator.SetDuration((sizeF + sizeChangePositive) * this.m_animDuration);
            sizeInterpolator.SetStartDelay(0.00);
            sizeInterpolator.SetType(inkanimInterpolationType.Linear);
            sizeInterpolator.SetMode(inkanimInterpolationMode.EasyIn);
            this.m_full_anim.AddInterpolator(sizeInterpolator);

            this.m_changePositive_anim = new inkAnimDef();
            sizeInterpolator = new inkAnimSize();
            sizeInterpolator.SetStartSize(new Vector2(this.m_width * sizeChangePositive, this.m_height));
            sizeInterpolator.SetEndSize(new Vector2(0.00, this.m_height));
            sizeInterpolator.SetDuration((sizeF + sizeChangePositive) * this.m_animDuration);
            sizeInterpolator.SetStartDelay(0.00);
            sizeInterpolator.SetType(inkanimInterpolationType.Linear);
            sizeInterpolator.SetMode(inkanimInterpolationMode.EasyIn);
            this.m_changePositive_anim.AddInterpolator(sizeInterpolator);
            visualChangeNegativeMax = MinF(this.m_MaxChangeNegativeBarFlashSize, this.m_width * AbsF(sizeChangeNegative));

            this.m_changeNegative_anim = new inkAnimDef();
            sizeInterpolator = new inkAnimSize();
            sizeInterpolator.SetStartSize(new Vector2(visualChangeNegativeMax, this.m_height));
            sizeInterpolator.SetEndSize(new Vector2(0.00, this.m_height));
            sizeInterpolator.SetDuration((sizeE + sizeChangeNegative) * this.m_animDuration);
            sizeInterpolator.SetStartDelay(0.00);
            sizeInterpolator.SetType(inkanimInterpolationType.Linear);
            sizeInterpolator.SetMode(inkanimInterpolationMode.EasyIn);
            this.m_changeNegative_anim.AddInterpolator(sizeInterpolator);

            if sizeF + sizeChangePositive > 0.00 {
                this.m_full_anim_proxy = this.m_fullBar.PlayAnimation(this.m_full_anim);
                this.m_changePositive_anim_proxy = this.m_changePositiveBar.PlayAnimation(this.m_changePositive_anim);
            };
            if sizeE + sizeChangeNegative > 0.00 {
                this.m_changeNegative_anim_proxy = this.m_changeNegativeBar.PlayAnimation(this.m_changeNegative_anim);
            };
            if sizeF + sizeChangePositive <= 0.00 {
                this.m_fullBar.SetSize(new Vector2(this.m_width * sizeF, this.m_height));
                this.m_changePositiveBar.SetSize(new Vector2(this.m_width * sizeChangePositive, this.m_height));
            };
            if sizeE + sizeChangeNegative <= 0.00 {
                this.m_changeNegativeBar.SetSize(new Vector2(this.m_width * sizeChangeNegative, this.m_height));
            };

            this.EvaluateBarPulse(this.m_currentValue, this.m_previousValue);
        };

        fullBarSize = this.m_fullBar.GetSize();
        negativeMargin.left = fullBarSize.X;
        this.m_changeNegativeBar.SetMargin(negativeMargin);

        DFLogNoSystem(this.debugEnabled, this, "SetProgress m_shouldForceBrightOnNextFadeIn: " + ToString(this.m_shouldForceBrightOnNextFadeIn));
        this.EvaluateBarGroupVisibility(forceMomentaryDisplay, momentaryDisplayIgnoresSceneTier);
    }

    public final func SetProgressEmpty(newValue: Float) {
        this.m_emptyBar.SetSize(new Vector2(this.m_width * newValue, this.m_height));
    }

    private final func EvaluateBarPulse(currentValue: Float, previousValue: Float) -> Void {
        if this.m_continuousPulseAtLowThresholdInCombat && currentValue <= this.m_continuousPulseThreshold && this.m_inDanger {
            this.SetPulse(true);
        } else if previousValue > 0.5 && currentValue <= 0.5 {
            this.SetPulse();
        } else if previousValue > 0.25 && currentValue <= 0.25 {
            this.SetPulse();
        } else {
            this.RegisterForPulseStop();
        }
    }

    public final func SetPulse(opt infinite: Bool) -> Void {
        this.EvaluateBarGroupVisibility(true);

        if !this.m_pulsing {
            this.m_pulsing = true;
            if this.m_currentValue <= 0.25 {
                this.m_pulse_anim.Configure(this.m_barMain, 1.00, 0.10, 0.20);
            } else {
                this.m_pulse_anim.Configure(this.m_barMain, 1.00, 0.10, this.m_currentValue);
            };
            this.m_pulse_anim.Start(false);
            if !infinite {
                this.RegisterForPulseStop();
            }
        }   
    }

    public final func EvaluateBarGroupVisibility(forceMomentaryDisplay: Bool, opt momentaryDisplayIgnoresSceneTier: Bool) -> Void {
        if IsDefined(this.m_barGroup) {
            if this.m_barGroup.displayManagedByParentGroup && IsDefined(this.m_barGroup.needsBarGroupParent) {
                this.m_barGroup.needsBarGroupParent.EvaluateAllBarVisibility(forceMomentaryDisplay, false);
            } else {
                this.m_barGroup.EvaluateAllBarVisibility(forceMomentaryDisplay, false, momentaryDisplayIgnoresSceneTier);
            }
        }
    }

    public final func GetFullSize() -> Vector2 {
        return new Vector2(this.m_width, this.m_height);
    }

    private final func SetFadeIn(fromParent: Bool) -> Void {
        DFLogNoSystem(this.debugEnabled, this, "SetFadeIn name: " + ToString(this.m_setupData.widgetName) + " m_shouldForceBrightOnNextFadeIn: " + ToString(this.m_shouldForceBrightOnNextFadeIn));
        if IsDefined(this.m_barGroup) && this.m_barGroup.displayManagedByParentGroup && !fromParent {
            return;
        }

        this.StopAnimProxyIfDefined(this.m_fadeIn_anim_proxy);

        let targetTransparency: Float;
        if this.m_shouldForceBrightOnNextFadeIn {
            DFLogNoSystem(this.debugEnabled, this, "SetFadeIn: Instant or Force Bright, show bright and recheck");
            targetTransparency = 0.8;
            if IsDefined(this.m_barGroup) {
                this.m_barGroup.RegisterForDisplayRecheckAfterForceBright();
            }
        } else {
            let minOpacity: Float = DFSettings.Get().hudUIMinOpacity / 100.0;
            targetTransparency = this.m_currentValue > 0.85 ? minOpacity : (1.0 + minOpacity) - this.m_currentValue;
        }

        this.m_fadeIn_anim = new inkAnimDef();
        let fadeInInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
        fadeInInterp.SetStartTransparency(this.m_rootWidget.GetOpacity());
        fadeInInterp.SetEndTransparency(targetTransparency);
        fadeInInterp.SetDuration(0.5);
        this.m_fadeIn_anim.AddInterpolator(fadeInInterp);
        this.m_fadeIn_anim_proxy = this.m_rootWidget.PlayAnimation(this.m_fadeIn_anim);
    }

    private final func SetFadeOut() -> Void {
        this.StopAnimProxyIfDefined(this.m_fadeOut_anim_proxy);
        this.StopAnimProxyIfDefined(this.m_fadeIn_anim_proxy);

        this.m_fadeOut_anim = new inkAnimDef();
        let fadeOutInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
        fadeOutInterp.SetStartTransparency(this.m_rootWidget.GetOpacity());
        fadeOutInterp.SetEndTransparency(0.0);
        fadeOutInterp.SetDuration(0.5);
        this.m_fadeOut_anim.AddInterpolator(fadeOutInterp);
        this.m_fadeOut_anim_proxy = this.m_rootWidget.PlayAnimation(this.m_fadeOut_anim);
    }

    private final func CreateAnimations() -> Void {
        this.m_pulse_anim = new PulseAnimation();
    }

    public final func OnPulseStop() -> Void {
        this.m_pulseStopDelayID = GetInvalidDelayID();
        this.m_pulse_anim.Stop();
        this.m_pulsing = false;
    }

    private final func RegisterForPulseStop() -> Void {
        RegisterDFDelayCallback(this.m_barGroup.DelaySystem, DFNeedsHUDBarPulseStopDelayCallback.Create(this), this.m_pulseStopDelayID, this.m_pulseStopDelayInterval);
    }
}
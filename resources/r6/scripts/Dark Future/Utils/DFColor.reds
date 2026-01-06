// -----------------------------------------------------------------------------
// DFColor
// -----------------------------------------------------------------------------
//
// - Utilities for requesting Colors and Color Themes for UI Meters.
//

module DarkFuture.Utils

import DarkFuture.Logging.*

public enum DFHDRColor {
    // Theme Colors
    ActiveRose = 0,
    Rose = 1,
    FaintRose = 2,
    ChangeNegativeRose = 3,
    ChangePositiveRose = 4,

    ActiveHotPink = 5,
    HotPink = 6,
    FaintHotPink = 7,
    ChangeNegativeHotPink = 8,
    ChangePositiveHotPink = 9,

    ActiveAqua = 10,
    Aqua = 11,
    FaintAqua = 12,
    ChangeNegativeAqua = 13,
    ChangePositiveAqua = 14,

    ActiveMainBlue = 15,
    MainBlue = 16,
    FaintMainBlue = 17,
    ChangeNegativeMainBlue = 18,
    ChangePositiveMainBlue = 19,

    ActiveSpringGreen = 20,
    SpringGreen = 21,
    FaintSpringGreen = 22,
    ChangeNegativeSpringGreen = 23,
    ChangePositiveSpringGreen = 24,

    ActivePigeonPost = 25,
    PigeonPost = 26,
    FaintPigeonPost = 27,
    ChangeNegativePigeonPost = 28,
    ChangePositivePigeonPost = 29,

    ActiveYellow = 30,
    Yellow = 31,
    FaintYellow = 32,
    ChangeNegativeYellow = 33,
    ChangePositiveYellow = 34,

    ActiveWhite = 35,
    White = 36,
    FaintWhite = 37,
    ChangeNegativeWhite = 38,
    ChangePositiveWhite = 39,

    ActiveStreetCredGreen = 40,
    StreetCredGreen = 41,
    FaintStreetCredGreen = 42,
    ChangeNegativeStreetCredGreen = 43,
    ChangePositiveStreetCredGreen = 44,

    ActiveMagenta = 45,
    Magenta = 46,
    FaintMagenta = 47,
    ChangeNegativeMagenta = 48,
    ChangePositiveMagenta = 49,

    ActivePanelRed = 50,
    PanelRed = 51,
    FaintPanelRed = 52,
    ChangeNegativePanelRed = 53,
    ChangePositivePanelRed = 54,

    ActiveMainRed = 55,
    MainRed = 56,
    FaintMainRed = 57,
    ChangeNegativeMainRed = 58,
    ChangePositiveMainRed = 59,

    // Misc Colors
    MildRed = 60,
    DarkRed = 61,
    MildWhite = 62,
    ActiveGreen = 63
}

public enum DFBarColorThemeName {
    Rose = 0,
    HotPink = 1,
    PanelRed = 2,
    MainRed = 3,
    Magenta = 4,
    Aqua = 5,
    PigeonPost = 6,
    MainBlue = 7,
    SpringGreen = 8,
    StreetCredGreen = 9,
    Yellow = 10,
    White = 11
}

public struct DFBarColorTheme {
    public let ActiveColor: HDRColor;
    public let MainColor: HDRColor;
    public let FaintColor: HDRColor;            // 70% Shade of Main
    public let ChangeNegativeColor: HDRColor;   // Complement of Main
    public let ChangePositiveColor: HDRColor;   // Split Complement of Main
}

// TODOFUTURE: Reinspect the ChangeNegative colors
public func GetDarkFutureHDRColor(color: DFHDRColor) -> HDRColor {
    //DFProfile();
    switch color {
        // Theme Colors
        case DFHDRColor.ActiveRose:
            return HDRColor(1.33, 0.19800, 0.58627, 1.0);
        case DFHDRColor.Rose:
            return HDRColor(1.0, 0.09800, 0.48627, 1.0); // #ff197c
        case DFHDRColor.FaintRose:
            return HDRColor(0.29803, 0.02745, 0.145098, 1.0);
        case DFHDRColor.ChangeNegativeRose:
            return HDRColor(0.09803, 1.0, 0.611764, 1.0);
        case DFHDRColor.ChangePositiveRose:
            return HDRColor(0.09803, 0.84705, 1.0, 1.0);

        case DFHDRColor.ActiveHotPink:
            return HDRColor(1.3, 0.405, 0.8333, 1.0);
        case DFHDRColor.HotPink:
            return HDRColor(1.0, 0.305, 0.7333, 1.0); // #FF4EBB
        case DFHDRColor.FaintHotPink:
            return HDRColor(0.298, 0.09, 0.2196, 1.0);
        case DFHDRColor.ChangeNegativeHotPink:
            return HDRColor(0.30588, 1.0, 0.57254, 1.0);
        case DFHDRColor.ChangePositiveHotPink:
            return HDRColor(0.30588, 1.0, 0.98823, 1.0);
        
        case DFHDRColor.ActiveAqua:
            return HDRColor(0.19803, 0.94705, 1.3, 1.0);
        case DFHDRColor.Aqua:
            return HDRColor(0.09803, 0.84705, 1.0, 1.0); // #19d8ff
        case DFHDRColor.FaintAqua:
            return HDRColor(0.02745, 0.25490, 0.29803, 1.0);
        case DFHDRColor.ChangeNegativeAqua:
            return HDRColor(1.0, 0.25098, 0.09803, 1.0);
        case DFHDRColor.ChangePositiveAqua:
            return HDRColor(1.0, 0.79215, 0.09803, 1.0);
        
        case DFHDRColor.ActiveMainBlue:
            return HDRColor(0.158299997, 1.30330002, 1.41419995, 1.0);
        case DFHDRColor.MainBlue:
            return HDRColor(0.368627459, 0.964705944, 1.0, 1.0); // #5ef6ff
        case DFHDRColor.FaintMainBlue:
            return HDRColor(0.0901960805, 0.172549024, 0.180392161, 1.0);
        case DFHDRColor.ChangeNegativeMainBlue:
            return HDRColor(1.0, 0.40392, 0.36862, 1.0);
        case DFHDRColor.ChangePositiveMainBlue:
            return HDRColor(1.0, 0.78431, 0.36862, 1.0);
        
        case DFHDRColor.ActiveSpringGreen:
            return HDRColor(0.19803, 1.2, 0.711764, 1.0);
        case DFHDRColor.SpringGreen:
            return HDRColor(0.09803, 1.0, 0.611764, 1.0); // #19FF9C
        case DFHDRColor.FaintSpringGreen:
            return HDRColor(0.02745, 0.298039, 0.184313, 1.0);
        case DFHDRColor.ChangeNegativeSpringGreen:
            return HDRColor(1.0, 0.2509803, 0.098039, 1.0);
        case DFHDRColor.ChangePositiveSpringGreen:
            return HDRColor(0.09803, 0.305882, 1.0, 1.0);

        case DFHDRColor.ActivePigeonPost:
            return HDRColor(0.76666, 0.884313, 1.143137, 1.0);
        case DFHDRColor.PigeonPost:
            return HDRColor(0.66666, 0.784313, 0.843137, 1.0); // #aac8d7
        case DFHDRColor.FaintPigeonPost:
            return HDRColor(0.2, 0.235294, 0.250980, 1.0);
        case DFHDRColor.ChangeNegativePigeonPost:
            return HDRColor(0.84313, 0.725490, 0.666666, 1.0);
        case DFHDRColor.ChangePositivePigeonPost:
            return HDRColor(0.78431, 0.843137, 0.666666, 1.0);
        
        case DFHDRColor.ActiveStreetCredGreen:
            return HDRColor(0.0, 1.2, 0.935294, 1.0);
        case DFHDRColor.StreetCredGreen:
            return HDRColor(0.0, 1.0, 0.835294, 1.0); // #00FFD5
        case DFHDRColor.FaintStreetCredGreen:
            return HDRColor(0.0, 0.298039, 0.250980, 1.0);
        case DFHDRColor.ChangeNegativeStreetCredGreen:
            return HDRColor(1.0, 0.0, 0.164705, 1.0);
        case DFHDRColor.ChangePositiveStreetCredGreen:
            return HDRColor(1.0, 0.435294, 0.0, 1.0);
        
        case DFHDRColor.ActiveMagenta:
            return HDRColor(1.23, 0.198039, 1.037254, 1.0);
        case DFHDRColor.Magenta:
            return HDRColor(1.0, 0.098039, 0.937254, 1.0); // #FF19EF
        case DFHDRColor.FaintMagenta:
            return HDRColor(0.29803, 0.027450, 0.282352, 1.0);
        case DFHDRColor.ChangeNegativeMagenta:
            return HDRColor(1.0, 0.341176, 0.098039, 1.0);
        case DFHDRColor.ChangePositiveMagenta:
            return HDRColor(0.098039, 1.0, 0.701960, 1.0);
        
        case DFHDRColor.ActivePanelRed:
            return HDRColor(1.36979997, 0.443699986, 0.404900014, 1.0);
        case DFHDRColor.PanelRed:
            return HDRColor(1.17610002, 0.380899996, 0.347600013, 1.0); // Main Colors Panel Red
        case DFHDRColor.FaintPanelRed:
            return HDRColor(0.282352954, 0.113725498, 0.137254909, 1.0);
        case DFHDRColor.ChangeNegativePanelRed:
            return HDRColor(1.23, 0.198039, 1.037254, 1.0);
        case DFHDRColor.ChangePositivePanelRed:
            return HDRColor(0.368627459, 0.964705944, 1.0, 1.0);
        
        case DFHDRColor.ActiveYellow:
            return HDRColor(1.33099997, 1.00380003, 0.305000007, 1.0);
        case DFHDRColor.Yellow:
            return HDRColor(1.11919999, 0.844099998, 0.256500006, 1.0);
        case DFHDRColor.FaintYellow:
            return HDRColor(0.258823544, 0.231372565, 0.10980393, 1.0);
        case DFHDRColor.ChangeNegativeYellow:
            return HDRColor(0.545, 0.255, 1.0, 1.0);
        case DFHDRColor.ChangePositiveYellow:
            return HDRColor(0.263, 1.0, 0.255, 1.0);
        
        case DFHDRColor.ActiveWhite:
            return HDRColor(1.5, 1.5, 1.5, 1.0);
        case DFHDRColor.White:
            return HDRColor(1.0, 1.0, 1.0, 1.0);
        case DFHDRColor.FaintWhite:
            return HDRColor(0.45, 0.45, 0.45, 1.0);
        case DFHDRColor.ChangeNegativeWhite:
            return HDRColor(1.23, 0.198039, 1.037254, 1.0);
        case DFHDRColor.ChangePositiveWhite:
            return HDRColor(0.368627459, 0.964705944, 1.0, 1.0);
        
        case DFHDRColor.ActiveMainRed:
            return HDRColor(1.0, 0.203921571, 0.290196091, 1.0);
        case DFHDRColor.MainRed:
            return HDRColor(0.98, 0.165, 0.270588249, 1.0);
        case DFHDRColor.FaintMainRed:
            return HDRColor(0.282352954, 0.113725498, 0.137254909, 1.0);
        case DFHDRColor.ChangeNegativeMainRed:
            return HDRColor(1.23, 0.198039, 1.037254, 1.0);
        case DFHDRColor.ChangePositiveMainRed:
            return HDRColor(0.368627459, 0.964705944, 1.0, 1.0);

        // Misc Colors
        case DFHDRColor.MildRed:
            return HDRColor(0.68235296, 0.231372565, 0.211764723, 1.0);

        case DFHDRColor.DarkRed:
            return HDRColor(0.262745112, 0.0862745121, 0.0941176564, 1.0);

        case DFHDRColor.MildWhite:
            return HDRColor(0.537, 0.651, 0.643, 1.0);
        
        case DFHDRColor.ActiveGreen:
            return HDRColor(0.160899997, 1.31439996, 0.726499975, 1.0);
    }
}

public func GetDarkFutureBarColorTheme(themeName: DFBarColorThemeName) -> DFBarColorTheme {
    //DFProfile();
    let theme: DFBarColorTheme;

    switch themeName {
        case DFBarColorThemeName.Rose:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveRose);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.Rose);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintRose);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeRose);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveRose);
            return theme;
        
        case DFBarColorThemeName.HotPink:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveHotPink);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.HotPink);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintHotPink);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeHotPink);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveHotPink);
            return theme;
        
        case DFBarColorThemeName.Aqua:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveAqua);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.Aqua);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintAqua);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeAqua);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveAqua);
            return theme;
        
        case DFBarColorThemeName.MainBlue:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveMainBlue);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.MainBlue);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintMainBlue);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeMainBlue);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveMainBlue);
            return theme;
        
        case DFBarColorThemeName.SpringGreen:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveSpringGreen);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.SpringGreen);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintSpringGreen);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeSpringGreen);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveSpringGreen);
            return theme;
        
        case DFBarColorThemeName.PigeonPost:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActivePigeonPost);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.PigeonPost);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintPigeonPost);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativePigeonPost);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositivePigeonPost);
            return theme;
        
        case DFBarColorThemeName.StreetCredGreen:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveStreetCredGreen);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.StreetCredGreen);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintStreetCredGreen);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeStreetCredGreen);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveStreetCredGreen);
            return theme;
        
        case DFBarColorThemeName.Magenta:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveMagenta);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.Magenta);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintMagenta);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeMagenta);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveMagenta);
            return theme;
        
        case DFBarColorThemeName.PanelRed:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActivePanelRed);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.PanelRed);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintPanelRed);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativePanelRed);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositivePanelRed);
            return theme;
        
        case DFBarColorThemeName.Yellow:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveYellow);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.Yellow);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintYellow);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeYellow);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveYellow);
            return theme;
        
        case DFBarColorThemeName.White:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveWhite);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.White);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintWhite);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeWhite);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveWhite);
            return theme;
        
        case DFBarColorThemeName.MainRed:
            theme.ActiveColor = GetDarkFutureHDRColor(DFHDRColor.ActiveMainRed);
            theme.MainColor = GetDarkFutureHDRColor(DFHDRColor.MainRed);
            theme.FaintColor = GetDarkFutureHDRColor(DFHDRColor.FaintMainRed);
            theme.ChangeNegativeColor = GetDarkFutureHDRColor(DFHDRColor.ChangeNegativeMainRed);
            theme.ChangePositiveColor = GetDarkFutureHDRColor(DFHDRColor.ChangePositiveMainRed);
            return theme;
    }
}
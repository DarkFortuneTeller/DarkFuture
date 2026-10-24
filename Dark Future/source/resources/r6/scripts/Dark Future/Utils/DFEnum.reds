// -----------------------------------------------------------------------------
// DFEnum
// -----------------------------------------------------------------------------
//
// - Helpers that look up a base-game enum value by its CName.
//

public func DFEnum_gamedataProficiencyType(name: CName) -> gamedataProficiencyType {
    //DFProfile();
    return IntEnum<gamedataProficiencyType>(EnumValueFromName(n"gamedataProficiencyType", name));
}

public func DFEnum_UIInventoryItemWeaponBarsType(name: CName) -> UIInventoryItemWeaponBarsType {
    //DFProfile();
    return IntEnum<UIInventoryItemWeaponBarsType>(EnumValueFromName(n"UIInventoryItemWeaponBarsType", name));
}

public func DFEnum_WeaponBarType(name: CName) -> WeaponBarType {
    //DFProfile();
    return IntEnum<WeaponBarType>(EnumValueFromName(n"WeaponBarType", name));
}

public func DFEnum_gamedataStatType(name: CName) -> gamedataStatType {
    //DFProfile();
    return IntEnum<gamedataStatType>(EnumValueFromName(n"gamedataStatType", name));
}

public func DFEnum_UIMenuNotificationType(name: CName) -> UIMenuNotificationType {
    //DFProfile();
    return IntEnum<UIMenuNotificationType>(EnumValueFromName(n"UIMenuNotificationType", name));
}

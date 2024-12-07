// -----------------------------------------------------------------------------
// DFCommon
// -----------------------------------------------------------------------------
//
// - Catch-all of general utilities, including RunGuard.
//

module DarkFuture.Utils

import DarkFuture.Logging.*
import DarkFuture.System.{
    DFSystem,
    DFSystemState
}
import DarkFuture.Main.DFTimeSkipType

public final static func HoursToGameTimeSeconds(hours: Int32) -> Float {
    return Int32ToFloat(hours) * 3600.0;
}

public final static func GameTimeSecondsToHours(seconds: Float) -> Int32 {
    return FloatToInt32(seconds / 3600.0);
}

public final func Int32ToFloat(value: Int32) -> Float {
    return Cast<Float>(value);
}

public final func FloatToInt32(value: Float) -> Int32 {
    return Cast<Int32>(value);
}

public static func IsCoinFlipSuccessful() -> Bool {
    return RandRange(1, 100) >= 50;
}

public final static func RunGuard(system: ref<DFSystem>, opt suppressLog: Bool) -> Bool {
    //  Protects functions that should only be called when a given system is running.
    //  Typically, these are functions that change state on the player or system,
    //  or retrieve data that relies on system state in order to be valid.
    //
    //	Intended use:
    //  private func MyFunc() -> Void {
    //      if RunGuard(this) { return; }
    //      ...
    //  }
    //
    if NotEquals(system.state, DFSystemState.Running) {
        if !suppressLog {
            //DFLog(true, system, "############## System not running, exiting function call.", DFLogLevel.Warning);
        }
        return true;
    } else {
        return false;
    }
}

public final static func IsSleeping(timeSkipType: DFTimeSkipType) -> Bool {
    return NotEquals(timeSkipType, DFTimeSkipType.TimeSkip);
}

public final static func IsPlayerInBadlands(player: wref<PlayerPuppet>) -> Bool {
    let parentDistrict: String = GetTopLevelParentDistrictName(player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord());
    return Equals(parentDistrict, "Badlands") || Equals(parentDistrict, "SouthBadlands") || Equals(parentDistrict, "NorthBadlands");
}

public final static func GetTopLevelParentDistrictName(districtRecord: wref<District_Record>) -> String {
    return GetTopLevelParentDistrictNameRecursive(districtRecord).EnumName();
}

public final static func GetTopLevelParentDistrictNameRecursive(districtRecord: wref<District_Record>) -> wref<District_Record> {
    let topLevelDistrictRecord: wref<District_Record>;
    
    let parent = districtRecord.ParentDistrict();
    if IsDefined(parent) {
        topLevelDistrictRecord = GetTopLevelParentDistrictNameRecursive(parent);
    } else {
        topLevelDistrictRecord = districtRecord;
    }

    return topLevelDistrictRecord;
}

@if(ModuleExists("RevisedBackpack"))
public final static func IsRevisedBackpackInstalled() -> Bool { return true; }

@if(!ModuleExists("RevisedBackpack"))
public final static func IsRevisedBackpackInstalled() -> Bool { return false; }
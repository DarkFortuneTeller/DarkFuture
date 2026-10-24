// -----------------------------------------------------------------------------
// DFCommon
// -----------------------------------------------------------------------------
//
// - Catch-all of general utilities, including RunGuard.
//

module DarkFuture.Utils

import DarkFuture.Logging.*
import DarkFuture.Main.DFMainSystem
import DarkFuture.System.{
    DFSystem,
    DFSystemState
}
import DarkFuture.Main.DFTimeSkipType

public enum DFGeneralVoiceLine {
    CyberpsychosisExitFromKill = 1,
    CyberpsychosisExitFromImmunosuppressant = 2,
    TherapyFirstSession = 3,
    TherapySecondSession = 4,
    HumanityLossRestoreStreetKid = 5,
    HumanityLossRestoreNomad = 6,
    HumanityLossRestoreCorpoFreshStart = 7,
    HumanityLossRestoreSpeed = 8,
    HumanityLossRestoreConfessionBooth = 9,
    HumanityLossRestoreCancel = 10,
    Blackout = 11,
    BlackoutVehicle = 12,
    Overdose = 13,
    Euphoria = 14,
    HumanityLossRestoreRadio = 15
}

public func HoursToGameTimeSeconds(hours: Int32) -> Float {
    //DFProfile();
    return Int32ToFloat(hours) * 3600.0;
}

public func HoursToGameTimeSeconds(hours: Float) -> Float {
    //DFProfile();
    return hours * 3600.0;
}

public func GameTimeSecondsToHours(seconds: Float) -> Int32 {
    //DFProfile();
    return FloatToInt32(seconds / 3600.0);
}

public func Int32ToFloat(value: Int32) -> Float {
    //DFProfile();
    return Cast<Float>(value);
}

public func FloatToInt32(value: Float) -> Int32 {
    //DFProfile();
    return Cast<Int32>(value);
}

public func IsCoinFlipSuccessful() -> Bool {
    //DFProfile();
    return RandRangeInclusive(1, 100) >= 50;
}

public func RandRangeInclusive(min: Int32, max: Int32) -> Int32 {
    //DFProfile();
    // RandRange secretly omits generating the max value.
    return RandRange(min, max + 1);
}

public func RandRangeInclusive(min: Uint32, max: Uint32) -> Uint32 {
    //DFProfile();
    // RandRange secretly omits generating the max value.
    return Cast<Uint32>(RandRange(Cast<Int32>(min), Cast<Int32>(max + 1u)));
}

public func DFGetPlayer() -> ref<PlayerPuppet> {
    //DFProfile();
    return DFMainSystem.Get().player;
}

public func DFRunGuard(system: ref<DFSystem>, opt suppressLog: Bool) -> Bool {
    //DFProfile();
    //  Protects functions that should only be called when a given system is running.
    //  Typically, these are functions that change state on the player or system,
    //  or retrieve data that relies on system state in order to be valid.
    //
    //	Intended use:
    //  private func MyFunc() -> Void {
    //      if DFRunGuard(this) { return; }
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

public func DFIsSleeping(timeSkipType: DFTimeSkipType) -> Bool {
    //DFProfile();
    return Equals(timeSkipType, DFTimeSkipType.FullSleep) || Equals(timeSkipType, DFTimeSkipType.LimitedSleep) || Equals(timeSkipType, DFTimeSkipType.Blackout);
}

public func IsPlayerInBadlands(player: wref<PlayerPuppet>) -> Bool {
    //DFProfile();
    let parentDistrict: String = GetTopLevelParentDistrictName(player.GetPreventionSystem().GetCurrentDistrict().GetDistrictRecord());
    return Equals(parentDistrict, "Badlands") || Equals(parentDistrict, "SouthBadlands") || Equals(parentDistrict, "NorthBadlands");
}

public func GetTopLevelParentDistrictName(districtRecord: wref<District_Record>) -> String {
    //DFProfile();
    return GetTopLevelParentDistrictNameRecursive(districtRecord).EnumName();
}

public func GetTopLevelParentDistrictNameRecursive(districtRecord: wref<District_Record>) -> wref<District_Record> {
    //DFProfile();
    let topLevelDistrictRecord: wref<District_Record>;
    
    let parent: wref<District_Record> = districtRecord.ParentDistrict();
    if IsDefined(parent) {
        topLevelDistrictRecord = GetTopLevelParentDistrictNameRecursive(parent);
    } else {
        topLevelDistrictRecord = districtRecord;
    }

    return topLevelDistrictRecord;
}

public func DarkFutureSendRadioEvent(player: ref<PlayerPuppet>, toggle: Bool, setStation: Bool, stationIndex: Int32) -> Void {
    //DFProfile();
    let vehicleObj: wref<VehicleObject>;
    VehicleComponent.GetVehicle(GetGameInstance(), player, vehicleObj);

    let vehRadioEvent: ref<VehicleRadioEvent> = new VehicleRadioEvent();
    vehRadioEvent.toggle = toggle;
    vehRadioEvent.setStation = setStation;
    vehRadioEvent.station = stationIndex >= 0 ? EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(stationIndex)) : -1;
    
    if IsDefined(vehicleObj) {
        player.QueueEventForEntityID(vehicleObj.GetEntityID(), vehRadioEvent);
    }
    
    player.QueueEvent(vehRadioEvent);
}

@if(ModuleExists("RevisedBackpack"))
public func IsRevisedBackpackInstalled() -> Bool { return true; }

@if(!ModuleExists("RevisedBackpack"))
public func IsRevisedBackpackInstalled() -> Bool { return false; }
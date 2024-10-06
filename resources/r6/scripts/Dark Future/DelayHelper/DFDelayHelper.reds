// -----------------------------------------------------------------------------
// DFDelayHelper
// -----------------------------------------------------------------------------
//
// - A set of helper functions for more effectively managing Delay Callbacks.
// - Behavior:
//     Delay Callbacks run to completion unless cancelled.
//     Duplicate registration attempts do not result in multiple callbacks.
//     Duplicate registration attempts do not cancel existing pending callbacks unless allowRestart is specifically set.
//
// DFDelayCallback implementation example:
/*
public class MyCallback extends DFDelayCallback {
	public static func Create() -> ref<DFDelayCallback> {
		return new MyCallback();
	}

	public func InvalidateDelayID() -> Void {
		MySystem.Get().InvalidateMyDelayID();
	}

	public func Callback() -> Void {
		MySystem.Get().OnMyCallback();
	}
}
*/

module DarkFuture.DelayHelper

public static func RegisterDFDelayCallback(delaySystem: ref<DelaySystem>, callback: ref<DFDelayCallback>, out delayID: DelayID, delayInterval: Float, opt allowRestart: Bool) -> Void {
    if allowRestart {
        UnregisterDFDelayCallback(delaySystem, delayID);
    }
    
    if delayID == GetInvalidDelayID() {
        delayID = delaySystem.DelayCallback(callback, delayInterval, true);
    }
}

public static func UnregisterDFDelayCallback(delaySystem: ref<DelaySystem>, out delayID: DelayID) -> Void {
    let invalidDelayID = GetInvalidDelayID();
    if delayID != invalidDelayID {
        GameInstance.GetDelaySystem(GetGameInstance()).CancelCallback(delayID);
        delayID = invalidDelayID;
    }
}

public abstract class DFDelayCallback extends DelayCallback {
    public func InvalidateDelayID() -> Void {
        //FTLog("MISSING REQUIRED METHOD OVERRIDE FOR InvalidateDelayID()");
    }
    
    public func Callback() -> Void {
        //FTLog("MISSING REQUIRED METHOD OVERRIDE FOR Callback()");
    }
    
    public func Call() -> Void {
        this.InvalidateDelayID();
        this.Callback();
    }
}

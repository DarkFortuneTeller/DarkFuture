// -----------------------------------------------------------------------------
// DFFactListenerUtils
// -----------------------------------------------------------------------------
//
// - Helper functions for managing DFFactListeners.
//

module DarkFuture.Utils

import DarkFuture.System.DFSystem

public struct DFFactListener {
    public let fact: CName = n"";
    public let id: Uint32 = 0u;
    public let callback: CName = n"";
    public let fireOnceOnly: Bool = false;
}

public func CreateDFFactListener(questsSystem: ref<QuestsSystem>, listener: ref<IScriptable>, registry: script_ref<array<DFFactListener>>, fact: CName, callback: CName, opt fireOnceOnly: Bool) -> Void {
    // Create a DFFactListener, add it to the registry, and register it with the QuestsSystem.
    let newFactListener: DFFactListener;
    newFactListener.fact = fact;
    newFactListener.callback = callback;
    newFactListener.fireOnceOnly = fireOnceOnly;
    
    RegisterDFFactListener(newFactListener, listener, questsSystem);
    ArrayPush(Deref(registry), newFactListener);
}

public func CreateDFActionFactListener(questsSystem: ref<QuestsSystem>, listener: ref<IScriptable>, registry: script_ref<array<DFFactListener>>, fact: CName, callback: CName, opt fireOnceOnly: Bool) -> DFFactListener {
    // "Action Facts" are facts that act as signals to or from Quest Phases or Scenes. It's expected that the receiver reset the value once processing
    // is completed, so we need to return the listener back to the caller for later use.
    let newFactListener: DFFactListener;
    newFactListener.fact = fact;
    newFactListener.callback = callback;
    newFactListener.fireOnceOnly = fireOnceOnly;
    
    RegisterDFFactListener(newFactListener, listener, questsSystem);
    ArrayPush(Deref(registry), newFactListener);

    return newFactListener;
}

public func UnregisterAllDFFactListeners(questsSystem: ref<QuestsSystem>, registry: script_ref<array<DFFactListener>>) -> Void {
    let i: Int32 = 0;
    while i < ArraySize(Deref(registry)) {
        UnregisterDFFactListener(Deref(registry)[i], questsSystem);
        ArrayRemove(Deref(registry), Deref(registry)[i]);
        i += 1;
    }
}

public func DFFactListenerCanRun(value: Int32, registry: script_ref<array<DFFactListener>>, onceOnlyFactsFired: script_ref<array<CName>>) -> Bool {
    // Allow DFFactListeners to run if:
    //     value >= 1, and
    //     not set to fireOnceOnly, or
    //     set to fireOnceOnly, and fact not present in the onceOnlyFactsFired array (if not present, add it now for convenience).

    if value < 1 {
        // Invalid value; fail.
        return false; 
    }

    // Coerce the caller's function name through reflection. Used to look up the DFFactListener in the registry.
    let trace: array<StackTraceEntry> = GetStackTrace(1, true);
    let caller: String = StrBeforeFirst(NameToString(trace[0].function), ";");

    let factIdx: Int32 = FindDFFactListenerIndexInRegistryByCallback(registry, caller);
    if NotEquals(factIdx, -1) {
        if registry[factIdx].fireOnceOnly {
            for fact in Deref(onceOnlyFactsFired) {
                if Equals(fact, registry[factIdx].fact) {
                    // The DFFactListener is set to fireOnceOnly, and the fact was present in the onceOnlyFactsFired array; fail.
                    return false;
                }
            }
            // The DFFactListener is set to fireOnceOnly, but was not in the onceOnlyFactsFired array; add it to the array and succeed.
            ArrayPush(Deref(onceOnlyFactsFired), registry[factIdx].fact);
            return true;
        } else {
            // The DFFactListener was not set to fireOnceOnly; succeed.
            return true;
        }
    } else {
        // The DFFactListener was not found in the registry based on the callback function name; succeed.
        return true;
    }
}

public func FindDFFactListenerIndexInRegistryByCallback(registry: script_ref<array<DFFactListener>>, callbackStr: String) -> Int32 {
    let i: Int32 = 0;
    while i < ArraySize(Deref(registry)) {
        if Equals(NameToString(registry[i].callback), callbackStr) {
            return i;
        }
        i += 1;
    }

    return -1;
}

public func RegisterDFFactListener(out factListener: DFFactListener, listener: ref<IScriptable>, questsSystem: ref<QuestsSystem>) -> Void {
    factListener.id = questsSystem.RegisterListener(factListener.fact, listener, factListener.callback);
}

public func UnregisterDFFactListener(out factListener: DFFactListener, questsSystem: ref<QuestsSystem>) -> Void {
    questsSystem.UnregisterListener(factListener.fact, factListener.id);
    factListener.id = 0u;
}
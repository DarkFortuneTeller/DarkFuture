// -----------------------------------------------------------------------------
// DFLogging
// -----------------------------------------------------------------------------
//
// - Helper function for logging.
//

module DarkFuture.Logging

import DarkFuture.System.DFSystem

public enum DFLogLevel {
    Debug = 0,
    Warning = 1,
    Error = 2
}

// =====================================
// Dark Future Function Profiling Toggle
// =====================================
public func IsDarkFutureProfilingEnabled() -> Bool { return false; }

public func DFProfile() -> Void {
    if IsDarkFutureProfilingEnabled() {
        let entries = GetStackTrace(1, true);
        let entry = entries[0];
        let trace = "";

        if IsDefined(entry.object) {
            trace = s"[CLASS:\(entry.class)][FUNC:\(entry.function)]";
        } else {
            trace = s"[FUNC:\(entry.function)]";
        }
        //FTLog("[DarkFuture][Profile] " + trace);
    }
}

public func DFLog(class: ref<DFSystem>, message: String, opt level: DFLogLevel) -> Void {
    if class.IsDebugEnabled() {
        let entries = GetStackTrace(1, true);
        let entry = entries[0];
        let trace = "";

        if IsDefined(entry.object) {
            trace = s"[\(entry.class)][\(entry.function)]";
        } else {
            trace = s"[\(entry.function)]";
        }
        
        switch level {
            case DFLogLevel.Warning:
                //LogChannelWarning(n"DEBUG", "[DarkFuture]$WARN$ " + trace + ": " + message);
                break;
            case DFLogLevel.Error:
                //LogChannelError(n"DEBUG", "[DarkFuture]!ERR~! " + trace + ": " + message);
                break;
            default:
                //LogChannel(n"DEBUG", "[DarkFuture]#INFO# " + trace + ": " + message);
                break;
        }
    }
}

public func DFLogNoSystem(enabled: Bool, class: ref<IScriptable>, message: String, opt level: DFLogLevel) -> Void {
    if enabled {
        let entries = GetStackTrace(1, true);
        let entry = entries[0];
        let trace = "";

        if IsDefined(entry.object) {
            trace = s"[\(entry.class)][\(entry.function)]";
        } else {
            trace = s"[\(entry.function)]";
        }
        
        switch level {
            case DFLogLevel.Warning:
                //LogChannelWarning(n"DEBUG", "[DarkFuture]$WARN$ " + trace + ": " + message);
                break;
            case DFLogLevel.Error:
                //LogChannelError(n"DEBUG", "[DarkFuture]!ERR~! " + trace + ": " + message);
                break;
            default:
                //LogChannel(n"DEBUG", "[DarkFuture]#INFO# " + trace + ": " + message);
                break;
        }
    }
}
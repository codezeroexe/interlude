import AppKit
import Darwin
import IOKit.pwr_mgt

/// Rules for when standby may start on its own, and which display it uses. Starting it from the menu
/// ignores the rules.
enum StartConditions {
    static let onlyChargingKey = "startOnlyWhileCharging"
    static let skipWhenAwakeKey = "skipWhenDisplayKeptAwake"
    static let displayKey = "standbyDisplay" // a screen's name; empty = the main display

    /// The display standby opens on: the chosen one if it's connected, else the main display.
    @MainActor static var screen: NSScreen? {
        let name = UserDefaults.standard.string(forKey: displayKey) ?? ""
        return NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.main
    }

    /// Whether standby may start now that the Mac is idle.
    @MainActor static func allowAutoStart(pluggedIn: Bool) -> Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: onlyChargingKey), !pluggedIn { return false }
        if d.bool(forKey: skipWhenAwakeKey), anotherAppKeepsDisplayAwake() { return false }
        return true
    }

    /// Apps whose whole job is keeping the Mac awake; they don't mean a call or video is on.
    static let keepAwakeApps: Set<String> = ["Amphetamine", "caffeinate", "KeepingYouAwake", "Lungo", "Theine", "Caffeine", "Owly"]

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    /// True while some other app asks macOS to keep the display on, as video calls, screen sharing,
    /// presentations and video players do.
    static func anotherAppKeepsDisplayAwake() -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return dict.contains { pid, assertions in
            pid.int32Value != me && !keepAwakeApps.contains(processName(pid.int32Value)) && assertions.contains {
                let type = $0[kIOPMAssertionTypeKey] as? String
                return type == kIOPMAssertionTypePreventUserIdleDisplaySleep || type == kIOPMAssertionTypeNoDisplaySleep
            }
        }
    }
}

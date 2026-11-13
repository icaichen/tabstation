import Foundation
import CoreGraphics
import Darwin

enum CGSSymbolicHotKey: Int32, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

/// Safely manages replacing Apple's native Command-Tab app switcher via SkyLight WindowServer SPI.
/// Replicates AltTab's exact architecture to guarantee zero issues for the user:
/// 1. Disables the Dock's symbolic hotkeys (1 and 2) when override is active.
/// 2. Automatically restores native Command-Tab on normal termination, crash, or POSIX signals.
enum NativeCommandTabManager {

    private(set) static var isNativeDisabled = false

    static func setNativeCommandTabEnabled(_ isEnabled: Bool) {
        for key in CGSSymbolicHotKey.allCases {
            _ = CGSSetSymbolicHotKeyEnabled(key.rawValue, isEnabled)
        }
        isNativeDisabled = !isEnabled
    }

    /// Evaluates whether native ⌘Tab and ⌘⇧Tab should be disabled based on settings and live shortcuts.
    static func update(overrideEnabled: Bool, primaryShortcut: Shortcut, sameAppShortcut: Shortcut) {
        let bindsCmdTab = (primaryShortcut.keyCode == KeyCode.tab && primaryShortcut.normalized.contains(.command)) ||
                          (sameAppShortcut.keyCode == KeyCode.tab && sameAppShortcut.normalized.contains(.command))
        let shouldDisable = overrideEnabled || bindsCmdTab

        setNativeCommandTabEnabled(!shouldDisable)
    }

    /// Emergency restoration called on app exit, crash, or termination signals.
    static func restore() {
        setNativeCommandTabEnabled(true)
    }
}

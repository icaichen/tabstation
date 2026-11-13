//
//  Development helper: posts a synthetic ⌥-hold-Tab chord so the switcher can
//  be exercised (and screenshotted) without a human holding keys down.
//
//  Usage: swift Tools/HoldOptionTab.swift [holdSeconds]
//

import Foundation
import CoreGraphics

let holdSeconds = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1.5")!

func post(_ type: CGEventType, keycode: UInt16, flags: CGEventFlags = []) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: type == .keyDown) else { return }
    // For key-up, `flags` should describe the modifiers still held.
    event.flags = type == .keyDown ? flags : []
    event.post(tap: .cghidEventTap)
}

let option: UInt16 = 58
let tab: UInt16 = 48

// Hold ⌥, press Tab once, then sit there so the switcher stays on screen.
print("holding ⌥Tab for \(holdSeconds)s…")
post(.keyDown, keycode: option, flags: [.maskAlternate])
usleep(120_000)
post(.keyDown, keycode: tab, flags: [.maskAlternate])
Thread.sleep(forTimeInterval: holdSeconds)
post(.keyUp, keycode: tab)
usleep(60_000)
post(.keyUp, keycode: option)
print("released")
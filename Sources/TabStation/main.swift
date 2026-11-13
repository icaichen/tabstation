import AppKit
import Darwin

// Ensure native ⌘Tab is always safely restored on exit, crash, or signals
atexit {
    NativeCommandTabManager.restore()
}

NSSetUncaughtExceptionHandler { _ in
    NativeCommandTabManager.restore()
}

let handledSignals = [SIGTERM, SIGINT, SIGHUP, SIGTRAP]
for sig in handledSignals {
    signal(sig) { _ in
        NativeCommandTabManager.restore()
        _exit(0)
    }
}

// TabStation is an LSUIElement (menu-bar-only) agent app: no Dock tile, no
// main window. Everything happens on the non-activating switcher panel.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
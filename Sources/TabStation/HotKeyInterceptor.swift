import AppKit
import Carbon.HIToolbox

enum SwitcherKey {
    case next
    case previous
    case sameAppNext
    case sameAppPrevious
    case closeWindow
    case minimizeWindow
    case quitApp
    case quickLook
    case pinOnTop
    case moveToNextDisplay
    case toggleBrowserTabs
    case escape
    case commit
    case snapLeft
    case snapRight
    case snapUp
    case snapDown
    case snapCenter

    var opensSwitcher: Bool {
        switch self {
        case .next, .previous, .sameAppNext, .sameAppPrevious:
            return true
        case .closeWindow, .minimizeWindow, .quitApp, .quickLook, .pinOnTop, .moveToNextDisplay, .toggleBrowserTabs, .escape, .commit, .snapLeft, .snapRight, .snapUp, .snapDown, .snapCenter:
            return false
        }
    }
}

enum ActiveShortcutRole {
    case none
    case primary
    case sameApp
}

final class HotKeyInterceptor {

    var onKey: ((SwitcherKey) -> Void)?
    /// Runs synchronously when modifier release triggers commit, so the HUD vanishes in <1ms before activation IPC.
    var onImmediateHide: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Carbon HotKey references
    private var carbonHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]

    private enum HotKeyID {
        static let primaryNext: UInt32 = 1
        static let primaryPrev: UInt32 = 2
        static let sameAppNext: UInt32 = 3
        static let sameAppPrev: UInt32 = 4
        static let cmdTabNext: UInt32 = 10
        static let cmdTabPrev: UInt32 = 11
        static let cmdGraveNext: UInt32 = 12
        static let cmdGravePrev: UInt32 = 13
    }

    var primaryShortcut: Shortcut = .optionTab {
        didSet {
            updateCarbonHotKeys()
            updateNativeOverride()
        }
    }
    var sameAppShortcut: Shortcut = Shortcut(modifiers: [.option], keyCode: KeyCode.grave) {
        didSet {
            updateCarbonHotKeys()
            updateNativeOverride()
        }
    }
    var overrideCommandTab: Bool = false {
        didSet {
            updateCarbonHotKeys()
            updateNativeOverride()
        }
    }

    private func updateNativeOverride() {
        NativeCommandTabManager.update(
            overrideEnabled: overrideCommandTab,
            primaryShortcut: primaryShortcut,
            sameAppShortcut: sameAppShortcut
        )
    }

    var shortcut: Shortcut {
        get { primaryShortcut }
        set { primaryShortcut = newValue }
    }

    private var activeRole: ActiveShortcutRole = .none
    private var activeHoldModifier: NSEvent.ModifierFlags = []
    private var holdModifierHeld = false

    private let visibility = Visibility()
    var isSwitcherVisible: Bool {
        get { visibility.value }
        set { visibility.value = newValue }
    }

    final class Visibility: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    private enum VK {
        static let escape: UInt16 = 53
    }

    private static let chordMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let commitMask: NSEvent.ModifierFlags = [.command, .option, .control]

    private let modifierKeyCodes: Set<UInt16> = [55, 56, 57, 58, 59, 60, 61, 62]

    @discardableResult
    func install() -> Bool {
        installCarbonHandler()
        updateCarbonHotKeys()

        guard tap == nil else { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<HotKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            if let swallowed = interceptor.consume(type: type, event: event) {
                return swallowed ? nil : Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoopSource = source
        return true
    }

    func uninstall() {
        stopModifierReleasePolling()
        NativeCommandTabManager.restore()
        for (_, ref) in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
        if let carbonHandler {
            RemoveEventHandler(carbonHandler)
            self.carbonHandler = nil
        }

        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    // MARK: - Carbon HotKeys

    private func installCarbonHandler() {
        guard carbonHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let target = GetEventDispatcherTarget()

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let interceptor = Unmanaged<HotKeyInterceptor>.fromOpaque(userData).takeUnretainedValue()
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            if status == noErr {
                interceptor.handleCarbonHotKey(id: hotkeyID.id)
            }
            return noErr
        }

        InstallEventHandler(target, callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    func updateCarbonHotKeys() {
        for (_, ref) in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()

        let target = GetEventDispatcherTarget()
        let sig = OSType(1414745938) // 'TSHK'

        func register(_ id: UInt32, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
            let carbonMods = carbonModifiers(from: modifiers)
            var ref: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: sig, id: id)
            let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, hotkeyID, target, 0, &ref)
            if status == noErr, let ref {
                registeredHotKeys[id] = ref
            }
        }

        // 1. Primary shortcut
        register(HotKeyID.primaryNext, keyCode: primaryShortcut.keyCode, modifiers: primaryShortcut.normalized)
        register(HotKeyID.primaryPrev, keyCode: primaryShortcut.keyCode, modifiers: primaryShortcut.normalized.union([.shift]))

        // 2. Same-app shortcut
        register(HotKeyID.sameAppNext, keyCode: sameAppShortcut.keyCode, modifiers: sameAppShortcut.normalized)
        register(HotKeyID.sameAppPrev, keyCode: sameAppShortcut.keyCode, modifiers: sameAppShortcut.normalized.union([.shift]))

        // 3. Override ⌘Tab and ⌘`
        if overrideCommandTab {
            register(HotKeyID.cmdTabNext, keyCode: KeyCode.tab, modifiers: [.command])
            register(HotKeyID.cmdTabPrev, keyCode: KeyCode.tab, modifiers: [.command, .shift])
            register(HotKeyID.cmdGraveNext, keyCode: KeyCode.grave, modifiers: [.command])
            register(HotKeyID.cmdGravePrev, keyCode: KeyCode.grave, modifiers: [.command, .shift])
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    private var isRecordingShortcut: Bool {
        guard NSApp.isActive else { return false }
        if let keyWin = NSApp.keyWindow, keyWin.firstResponder is ShortcutRecorderView {
            return true
        }
        return false
    }

    private func handleCarbonHotKey(id: UInt32) {
        if isRecordingShortcut {
            return
        }

        switch id {
        case HotKeyID.primaryNext:
            let scope = ShortcutScopeStore.load(.primary)
            if scope == .activeApp {
                triggerShortcut(role: .sameApp, holdMod: primaryShortcut.normalized.subtracting([.shift]), key: .sameAppNext)
            } else {
                triggerShortcut(role: .primary, holdMod: primaryShortcut.normalized.subtracting([.shift]), key: .next)
            }

        case HotKeyID.primaryPrev:
            let scope = ShortcutScopeStore.load(.primary)
            if scope == .activeApp {
                triggerShortcut(role: .sameApp, holdMod: primaryShortcut.normalized.subtracting([.shift]), key: .sameAppPrevious)
            } else {
                triggerShortcut(role: .primary, holdMod: primaryShortcut.normalized.subtracting([.shift]), key: .previous)
            }

        case HotKeyID.sameAppNext:
            let scope = ShortcutScopeStore.load(.sameApp)
            if scope == .allApps {
                triggerShortcut(role: .primary, holdMod: sameAppShortcut.normalized.subtracting([.shift]), key: .next)
            } else {
                triggerShortcut(role: .sameApp, holdMod: sameAppShortcut.normalized.subtracting([.shift]), key: .sameAppNext)
            }

        case HotKeyID.sameAppPrev:
            let scope = ShortcutScopeStore.load(.sameApp)
            if scope == .allApps {
                triggerShortcut(role: .primary, holdMod: sameAppShortcut.normalized.subtracting([.shift]), key: .previous)
            } else {
                triggerShortcut(role: .sameApp, holdMod: sameAppShortcut.normalized.subtracting([.shift]), key: .sameAppPrevious)
            }

        case HotKeyID.cmdTabNext:
            let scope = ShortcutScopeStore.load(.primary)
            if scope == .activeApp {
                triggerShortcut(role: .sameApp, holdMod: [.command], key: .sameAppNext)
            } else {
                triggerShortcut(role: .primary, holdMod: [.command], key: .next)
            }

        case HotKeyID.cmdTabPrev:
            let scope = ShortcutScopeStore.load(.primary)
            if scope == .activeApp {
                triggerShortcut(role: .sameApp, holdMod: [.command], key: .sameAppPrevious)
            } else {
                triggerShortcut(role: .primary, holdMod: [.command], key: .previous)
            }

        case HotKeyID.cmdGraveNext:
            let scope = ShortcutScopeStore.load(.sameApp)
            if scope == .allApps {
                triggerShortcut(role: .primary, holdMod: [.command], key: .next)
            } else {
                triggerShortcut(role: .sameApp, holdMod: [.command], key: .sameAppNext)
            }

        case HotKeyID.cmdGravePrev:
            let scope = ShortcutScopeStore.load(.sameApp)
            if scope == .allApps {
                triggerShortcut(role: .primary, holdMod: [.command], key: .previous)
            } else {
                triggerShortcut(role: .sameApp, holdMod: [.command], key: .sameAppPrevious)
            }

        default:
            break
        }
    }

    private func triggerShortcut(role: ActiveShortcutRole, holdMod: NSEvent.ModifierFlags, key: SwitcherKey) {
        if isSwitcherVisible {
            dispatch(key)
            return
        }
        activeRole = role
        activeHoldModifier = holdMod
        holdModifierHeld = true
        startModifierReleasePolling()
        dispatch(key)
    }

    // MARK: - Switcher lifecycle callbacks

    func switcherDidOpen(with role: ActiveShortcutRole) {
        activeRole = role
        activeHoldModifier = holdModifierForRole(role)
        holdModifierHeld = true
        isSwitcherVisible = true
        startModifierReleasePolling()
    }

    func switcherDidClose() {
        stopModifierReleasePolling()
        activeRole = .none
        activeHoldModifier = []
        holdModifierHeld = false
        lastDispatchedKey = nil
        isSwitcherVisible = false
    }

    // MARK: - Hardware Modifier Release Poller (60Hz / 15ms)
    // Direct hardware polling of WindowServer modifier state guarantees releasing Command/Option
    // ALWAYS commits instantly, with zero reliance on event tap or OS message delivery.

    private var modifierReleasePollTimer: Timer?

    private func startModifierReleasePolling() {
        stopModifierReleasePolling()
        let timer = Timer(timeInterval: 0.015, repeats: true) { [weak self] _ in
            guard let self, self.isSwitcherVisible else { return }
            let state = CGEventSource.flagsState(.combinedSessionState)
            let cmdHeld = state.contains(.maskCommand)
            let optHeld = state.contains(.maskAlternate)
            let ctrlHeld = state.contains(.maskControl)

            let holdMod = !self.activeHoldModifier.isEmpty ? self.activeHoldModifier : self.holdModifierForRole(self.activeRole)

            var released = false
            if holdMod.contains(.command) && !cmdHeld {
                released = true
            } else if holdMod.contains(.option) && !optHeld {
                released = true
            } else if holdMod.contains(.control) && !ctrlHeld {
                released = true
            } else if !cmdHeld && !optHeld && !ctrlHeld {
                released = true
            }

            if released {
                self.stopModifierReleasePolling()
                self.activeRole = .none
                self.activeHoldModifier = []
                self.holdModifierHeld = false
                self.dispatchCommit()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierReleasePollTimer = timer
    }

    private func stopModifierReleasePolling() {
        modifierReleasePollTimer?.invalidate()
        modifierReleasePollTimer = nil
    }

    // MARK: - CGEventTap processing

    private func consume(type: CGEventType, event: CGEvent) -> Bool? {
        // If a ShortcutRecorderView in Preferences is actively recording, pass keys through to it
        if isRecordingShortcut {
            if let recorder = NSApp.keyWindow?.firstResponder as? ShortcutRecorderView,
               type == .keyDown {
                let keycode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                let flags = (NSEvent(cgEvent: event)?.modifierFlags ?? []).intersection(Self.chordMask)
                if (keycode == KeyCode.tab || keycode == KeyCode.grave) && flags.contains(.command) {
                    DispatchQueue.main.async {
                        recorder.recordCustom(Shortcut(modifiers: flags, keyCode: keycode))
                    }
                    return true
                }
            }
            return nil
        }

        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil

        case .flagsChanged:
            let flags = nsEvent.modifierFlags
            let currentChord = flags.intersection([.command, .option, .control])

            if isSwitcherVisible || activeRole != .none {
                let holdMod = holdModifierForRole(activeRole)
                let holdKeyReleased = currentChord.isEmpty || (!holdMod.isEmpty && flags.intersection(holdMod).isEmpty)

                if holdKeyReleased {
                    stopModifierReleasePolling()
                    activeRole = .none
                    activeHoldModifier = []
                    holdModifierHeld = false
                    dispatchCommit()
                    return nil
                } else {
                    holdModifierHeld = true
                }
            }
            return nil

        case .keyUp:
            let keycode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            if isSwitcherVisible || activeRole != .none {
                if [KeyCode.tab, KeyCode.grave].contains(keycode) {
                    return true
                }
                if [54, 55, 56, 57, 58, 59, 60, 61].contains(keycode) {
                    let currentChord = nsEvent.modifierFlags.intersection([.command, .option, .control])
                    let holdMod = holdModifierForRole(activeRole)
                    let holdKeyReleased = currentChord.isEmpty || (!holdMod.isEmpty && nsEvent.modifierFlags.intersection(holdMod).isEmpty)
                    if holdKeyReleased {
                        stopModifierReleasePolling()
                        activeRole = .none
                        activeHoldModifier = []
                        holdModifierHeld = false
                        dispatchCommit()
                        return nil
                    }
                }
            }
            return nil

        case .keyDown:
            let flags = nsEvent.modifierFlags
            let pressed = flags.intersection(Self.chordMask)
            let keycode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

            if keycode == VK.escape, activeRole != .none || isSwitcherVisible {
                return dispatch(.escape)
            }

            // Quick actions and navigation while switcher is visible / gesture is active
            if activeRole != .none || isSwitcherVisible {
                // Return / Enter: Commit selection immediately
                if keycode == KeyCode.returnKey {
                    return dispatch(.commit)
                }
                // Visual Grid Window Snapping via Arrow keys & C
                if keycode == KeyCode.leftArrow {
                    return dispatch(.snapLeft)
                }
                if keycode == KeyCode.rightArrow {
                    return dispatch(.snapRight)
                }
                if keycode == KeyCode.upArrow {
                    return dispatch(.snapUp)
                }
                if keycode == KeyCode.downArrow {
                    return dispatch(.snapDown)
                }
                if keycode == KeyCode.c {
                    return dispatch(.snapCenter)
                }

                // Window action: Close (W or Delete)
                if keycode == KeyCode.w || keycode == KeyCode.delete {
                    return dispatch(.closeWindow)
                }

                // Window action: Minimize (M)
                if keycode == KeyCode.m {
                    return dispatch(.minimizeWindow)
                }

                // Quick Look: Spacebar
                if keycode == KeyCode.space {
                    return dispatch(.quickLook)
                }

                // Move to next display: D
                if keycode == KeyCode.d {
                    return dispatch(.moveToNextDisplay)
                }

                // Pin on top / Float PiP: P
                if keycode == KeyCode.p {
                    return dispatch(.pinOnTop)
                }

                // Toggle browser tabs: B
                if keycode == KeyCode.b {
                    return dispatch(.toggleBrowserTabs)
                }

                // App action: Quit (⌘Q)
                if keycode == KeyCode.q && (pressed.contains(.command) || !pressed.contains(.option)) {
                    return dispatch(.quitApp)
                }

                // In-flight cycling: match key for currently active role
                if keycode == KeyCode.tab {
                    let key: SwitcherKey = pressed.contains(.shift)
                        ? (activeRole == .sameApp ? .sameAppPrevious : .previous)
                        : (activeRole == .sameApp ? .sameAppNext : .next)
                    return dispatch(key)
                }

                if keycode == KeyCode.grave {
                    return dispatch(pressed.contains(.shift) ? .sameAppPrevious : .sameAppNext)
                }

                if keycode == primaryShortcut.keyCode {
                    return dispatch(pressed.contains(.shift) ? .previous : .next)
                }

                if keycode == sameAppShortcut.keyCode {
                    return dispatch(pressed.contains(.shift) ? .sameAppPrevious : .sameAppNext)
                }

                // Self-healing fallback: activeRole was .none but switcher is actively displayed
                if activeRole == .none {
                    let role: ActiveShortcutRole = (keycode == KeyCode.grave || keycode == sameAppShortcut.keyCode) ? .sameApp : .primary
                    activeRole = role
                    activeHoldModifier = pressed.isEmpty ? (overrideCommandTab ? [.command] : [.option]) : pressed.subtracting([.shift])
                    holdModifierHeld = true
                    if role == .sameApp {
                        return dispatch(pressed.contains(.shift) ? .sameAppPrevious : .sameAppNext)
                    } else {
                        return dispatch(pressed.contains(.shift) ? .previous : .next)
                    }
                }

                // Swallow Tab and Grave while switcher gesture is active
                if keycode == KeyCode.tab || keycode == KeyCode.grave {
                    return true
                }
                return nil
            }

            guard !pressed.isEmpty else { return nil }

            if activeRole == .none || !isSwitcherVisible {
                if let result = matchAny(pressed, keycode) {
                    activeRole = result.role
                    activeHoldModifier = pressed.subtracting([.shift])
                    holdModifierHeld = true
                    return dispatch(result.key)
                }
                if activeRole == .none {
                    return nil
                }
            }

            return nil

        default:
            return nil
        }
    }

    private struct MatchResult {
        let key: SwitcherKey
        let role: ActiveShortcutRole
    }

    /// First press of a gesture, evaluated when switcher is closed.
    private func matchAny(_ pressed: NSEvent.ModifierFlags, _ keycode: UInt16) -> MatchResult? {
        // 1. Configured same-app shortcut
        if keycode == sameAppShortcut.keyCode,
           matchPressed(pressed, against: sameAppShortcut.normalized) {
            let scope = ShortcutScopeStore.load(.sameApp)
            return MatchResult(
                key: pressed.contains(.shift) ? (scope == .allApps ? .previous : .sameAppPrevious) : (scope == .allApps ? .next : .sameAppNext),
                role: scope == .allApps ? .primary : .sameApp
            )
        }
        // 2. ⌘` for same-app when overrideCommandTab is enabled
        if overrideCommandTab && keycode == KeyCode.grave && pressed.contains(.command) {
            let scope = ShortcutScopeStore.load(.sameApp)
            return MatchResult(
                key: pressed.contains(.shift) ? (scope == .allApps ? .previous : .sameAppPrevious) : (scope == .allApps ? .next : .sameAppNext),
                role: scope == .allApps ? .primary : .sameApp
            )
        }
        // 3. Fallback standard ⌥` for same-app
        if keycode == KeyCode.grave && pressed.contains(.option) {
            let scope = ShortcutScopeStore.load(.sameApp)
            return MatchResult(
                key: pressed.contains(.shift) ? (scope == .allApps ? .previous : .sameAppPrevious) : (scope == .allApps ? .next : .sameAppNext),
                role: scope == .allApps ? .primary : .sameApp
            )
        }
        // 4. ⌘Tab override support
        if overrideCommandTab && keycode == KeyCode.tab && pressed.contains(.command) {
            let scope = ShortcutScopeStore.load(.primary)
            return MatchResult(
                key: pressed.contains(.shift) ? (scope == .activeApp ? .sameAppPrevious : .previous) : (scope == .activeApp ? .sameAppNext : .next),
                role: scope == .activeApp ? .sameApp : .primary
            )
        }
        // 5. Primary switcher
        if keycode == primaryShortcut.keyCode,
           matchPressed(pressed, against: primaryShortcut.normalized) {
            let scope = ShortcutScopeStore.load(.primary)
            return MatchResult(
                key: pressed.contains(.shift) ? (scope == .activeApp ? .sameAppPrevious : .previous) : (scope == .activeApp ? .sameAppNext : .next),
                role: scope == .activeApp ? .sameApp : .primary
            )
        }
        return nil
    }

    private func matchPressed(_ pressed: NSEvent.ModifierFlags, against cfg: NSEvent.ModifierFlags) -> Bool {
        if cfg.contains(.shift) {
            return pressed == cfg
        }
        if pressed == cfg { return true }
        var withShift = cfg; withShift.insert(.shift)
        return pressed == withShift
    }

    private func holdModifierForRole(_ role: ActiveShortcutRole) -> NSEvent.ModifierFlags {
        if !activeHoldModifier.isEmpty {
            return activeHoldModifier
        }
        let currentFlags = NSEvent.modifierFlags.intersection(Self.chordMask)
        if currentFlags.contains(.command) { return [.command] }
        if currentFlags.contains(.option) { return [.option] }
        if currentFlags.contains(.control) { return [.control] }

        switch role {
        case .primary:
            if overrideCommandTab { return [.command] }
            return primaryShortcut.normalized.subtracting([.shift])
        case .sameApp:
            if overrideCommandTab && sameAppShortcut.keyCode == KeyCode.grave {
                return [.command]
            }
            return sameAppShortcut.normalized.subtracting([.shift])
        case .none:
            if overrideCommandTab { return [.command] }
            let p = primaryShortcut.normalized.subtracting([.shift])
            return p.isEmpty ? [.command] : p
        }
    }

    private func keycodeIsModifier(_ keycode: UInt16, for modifier: NSEvent.ModifierFlags) -> Bool {
        if modifier.contains(.command), [55, 54].contains(keycode) { return true }
        if modifier.contains(.option), [58, 61].contains(keycode) { return true }
        if modifier.contains(.control), [59, 57].contains(keycode) { return true }
        if modifier.contains(.shift), [56, 60].contains(keycode) { return true }
        return false
    }

    private var lastDispatchTime: TimeInterval = 0
    private var lastDispatchedKey: SwitcherKey?

    private func dispatchCommit() {
        stopModifierReleasePolling()
        guard onKey != nil else { return }
        lastDispatchedKey = .commit
        lastDispatchTime = ProcessInfo.processInfo.systemUptime
        // Immediately pull the HUD panel off-screen synchronously before queuing activation IPC.
        onImmediateHide?()
        // Hop out of the CGEventTap callback for AppKit state cleanup & cross-process activation.
        DispatchQueue.main.async { [weak self] in
            self?.onKey?(.commit)
        }
    }

    @discardableResult
    private func dispatch(_ key: SwitcherKey) -> Bool? {
        if key == .commit {
            dispatchCommit()
            return true
        }

        guard let onKey else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        // Debounce duplicate events within 40ms to prevent double-dispatch
        // if both Carbon HotKey and CGEventTap report the same keystroke.
        if key == lastDispatchedKey && (now - lastDispatchTime) < 0.04 {
            return true
        }
        lastDispatchTime = now
        lastDispatchedKey = key

        if Thread.isMainThread {
            onKey(key)
        } else {
            DispatchQueue.main.async { onKey(key) }
        }
        return true
    }

}

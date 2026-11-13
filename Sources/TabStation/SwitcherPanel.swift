import AppKit

/// A borderless, non-activating panel. It floats above everything, can appear
/// on any Space or over a full-screen app, and never takes focus away from the
/// app you're switching to.
final class SwitcherPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        applyAppearancePreferences()
    }

    func applyAppearancePreferences() {
        appearance = AppearancePreferences.theme.nsAppearance
    }

    /// Deliberately never becomes key: keyboard focus must stay with the app
    /// behind the switcher, otherwise the app would lose its ⌥-chord.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
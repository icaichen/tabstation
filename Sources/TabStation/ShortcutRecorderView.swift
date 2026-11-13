import AppKit

/// A click-to-record shortcut field, in the style of macOS System Settings:
/// click to focus, press a chord, it's captured and validated in place.
final class ShortcutRecorderView: NSView {

    var onChange: ((Shortcut) -> Void)?
    var onInvalid: ((String) -> Void)?

    /// Which of the three shortcuts this field records. Used for validation
    /// (collision checks against the other two).
    var role: ShortcutRole = .primary

    /// Live snapshot of the other shortcuts, for collision detection.
    var othersProvider: (() -> [ShortcutRole: Shortcut])?

    private(set) var shortcut: Shortcut = .optionTab
    private var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private var placeholder: String { L10n.t("Record…", "请按键…") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setShortcut(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        updateAppearance()
    }

    // MARK: - Appearance

    private func updateAppearance() {
        if isRecording {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.5
            label.stringValue = placeholder
            label.textColor = .controlAccentColor
        } else {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 0.5
            label.stringValue = shortcut.displayString
            label.textColor = .labelColor
        }
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 8, dy: 2)
    }

    // MARK: - Focus

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        updateAppearance()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateAppearance()
        return true
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: layer?.cornerRadius ?? 6, yRadius: layer?.cornerRadius ?? 6).fill()
    }

    // MARK: - Recording

    override func keyDown(with event: NSEvent) {
        // Esc cancels recording without modifying the existing shortcut
        if event.keyCode == KeyCode.escape {
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // A bare modifier press isn't a shortcut — it would be indistinguishable
        // from finishing the recording.
        if modifiers.isEmpty && KeyCode.modifierKeys.contains(event.keyCode) {
            NSSound.beep()
            return
        }

        let candidate = Shortcut(modifiers: modifiers, keyCode: event.keyCode)

        if let reason = ShortcutValidator.validate(candidate, for: role) {
            NSSound.beep()
            onInvalid?(reason)
            return
        }

        shortcut = candidate
        onChange?(candidate)
        window?.makeFirstResponder(nil)
    }

    func recordCustom(_ candidate: Shortcut) {
        if let reason = ShortcutValidator.validate(candidate, for: role) {
            NSSound.beep()
            onInvalid?(reason)
            return
        }
        shortcut = candidate
        updateAppearance()
        onChange?(candidate)
        window?.makeFirstResponder(nil)
    }

    /// Pure modifier presses don't commit, but they preview what is about to be
    /// recorded so the field feels responsive.
    override func flagsChanged(with event: NSEvent) {
        guard isRecording, let window else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        label.stringValue = flags.isEmpty ? placeholder : (Shortcut.glyphs(for: flags) + "…")
        window.makeFirstResponder(self)
    }
}
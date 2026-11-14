import AppKit

/// One entry in the switcher grid.
struct SwitcherItem {
    let window: WindowInfo
    let caption: String
    let icon: NSImage?
}

/// Pure multi-row balanced grid layout calculator for thumbnails and app icons.
struct SwitcherGridLayout {
    let frames: [CGRect]
    let contentSize: CGSize
    let scale: CGFloat
    let imageHeight: CGFloat
    let minCellWidth: CGFloat
    let maxCellWidth: CGFloat
    let rowCount: Int

    static func compute(
        aspectRatios: [CGFloat],
        style: DisplayStyle,
        size: ThumbnailSize,
        autoAdjustSize: Bool,
        maxContentWidth: CGFloat,
        maxContentHeight: CGFloat
    ) -> SwitcherGridLayout {
        guard !aspectRatios.isEmpty else {
            return SwitcherGridLayout(
                frames: [],
                contentSize: CGSize(width: 200, height: 80),
                scale: 1.0,
                imageHeight: style == .iconsOnly ? size.iconDimension : size.baseHeight,
                minCellWidth: size.minWidth,
                maxCellWidth: size.maxWidth,
                rowCount: 0
            )
        }

        let scales: [CGFloat] = autoAdjustSize
            ? [1.0, 0.92, 0.85, 0.78, 0.72, 0.66, 0.60, 0.54, 0.48]
            : [1.0]

        var chosen = layoutAtScale(
            scales[0],
            aspectRatios: aspectRatios,
            style: style,
            size: size,
            maxContentWidth: maxContentWidth
        )

        if autoAdjustSize {
            for candidateScale in scales {
                let candidate = layoutAtScale(
                    candidateScale,
                    aspectRatios: aspectRatios,
                    style: style,
                    size: size,
                    maxContentWidth: maxContentWidth
                )
                chosen = candidate
                if candidate.contentSize.height <= maxContentHeight {
                    break
                }
            }
        }

        return chosen
    }

    private static func layoutAtScale(
        _ scale: CGFloat,
        aspectRatios: [CGFloat],
        style: DisplayStyle,
        size: ThumbnailSize,
        maxContentWidth: CGFloat
    ) -> SwitcherGridLayout {
        let spacingX: CGFloat = max(6, ((style == .iconsOnly ? 10 : 12) * scale).rounded())
        let spacingY: CGFloat = max(6, ((style == .iconsOnly ? 10 : 12) * scale).rounded())

        let imgHeight: CGFloat
        let minW: CGFloat
        let maxW: CGFloat
        let cellHeight: CGFloat

        if style == .iconsOnly {
            let dim = max(40, (size.iconDimension * scale).rounded())
            imgHeight = dim
            minW = dim
            maxW = dim
            cellHeight = dim
        } else {
            imgHeight = max(56, (size.baseHeight * scale).rounded())
            minW = max(52, (size.minWidth * scale).rounded())
            maxW = max(minW + 16, (size.maxWidth * scale).rounded())
            cellHeight = imgHeight + Theme.cellShadowHeadroom + WindowItemView.captionHeight(for: style)
        }

        let widths: [CGFloat] = aspectRatios.map { ratio in
            if style == .iconsOnly { return minW }
            let raw = (imgHeight * max(0.35, min(3.0, ratio))).rounded()
            return min(maxW, max(minW, raw))
        }

        let effectiveMaxW = max(maxW, maxContentWidth)
        let rows = packBalancedRows(widths: widths, spacing: spacingX, maxRowWidth: effectiveMaxW)

        var rowWidths: [CGFloat] = []
        for row in rows {
            let sumW = row.reduce(CGFloat(0)) { $0 + widths[$1] }
            let totalGap = spacingX * CGFloat(max(0, row.count - 1))
            rowWidths.append(sumW + totalGap)
        }

        let totalGridWidth = max(rowWidths.max() ?? 0, 1)
        let totalGridHeight = CGFloat(rows.count) * cellHeight
            + spacingY * CGFloat(max(0, rows.count - 1))

        var frames = Array(repeating: CGRect.zero, count: aspectRatios.count)
        var y: CGFloat = 0
        for (rowIdx, row) in rows.enumerated() {
            let rowW = rowWidths[rowIdx]
            var x = ((totalGridWidth - rowW) / 2).rounded()
            for itemIdx in row {
                let w = widths[itemIdx]
                frames[itemIdx] = CGRect(x: x, y: y, width: w, height: cellHeight)
                x += w + spacingX
            }
            y += cellHeight + spacingY
        }

        return SwitcherGridLayout(
            frames: frames,
            contentSize: CGSize(width: totalGridWidth.rounded(.up), height: totalGridHeight.rounded(.up)),
            scale: scale,
            imageHeight: imgHeight,
            minCellWidth: minW,
            maxCellWidth: maxW,
            rowCount: rows.count
        )
    }

    private static func packBalancedRows(
        widths: [CGFloat],
        spacing: CGFloat,
        maxRowWidth: CGFloat
    ) -> [[Int]] {
        let greedy = packGreedy(widths: widths, spacing: spacing, limit: maxRowWidth)
        guard greedy.count > 1 else { return greedy }

        let targetRows = greedy.count
        var low = widths.max() ?? maxRowWidth
        var high = maxRowWidth

        for _ in 0..<14 {
            let mid = ((low + high) / 2).rounded(.down)
            let trial = packGreedy(widths: widths, spacing: spacing, limit: mid)
            if trial.count <= targetRows {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return packGreedy(widths: widths, spacing: spacing, limit: high)
    }

    private static func packGreedy(
        widths: [CGFloat],
        spacing: CGFloat,
        limit: CGFloat
    ) -> [[Int]] {
        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var currentWidth: CGFloat = 0

        for (index, w) in widths.enumerated() {
            let addedWidth = currentRow.isEmpty ? w : (spacing + w)
            if !currentRow.isEmpty && (currentWidth + addedWidth > limit) {
                rows.append(currentRow)
                currentRow = [index]
                currentWidth = w
            } else {
                currentRow.append(index)
                currentWidth += addedWidth
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

private final class FlippedGridDocumentView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The switcher's content view: translucent customizable HUD panel with an auto-scaling,
/// multi-row balanced grid and crisp single-line footer/title strip.
final class SwitcherView: NSView {

    private let surfaceView = GlassSurfaceView(cornerRadius: Theme.panelCornerRadius)

    private let scrollView = NSScrollView()
    private let documentView = FlippedGridDocumentView()

    private let selectedTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.isHidden = true
        return label
    }()

    private let footerLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.isHidden = true
        return label
    }()

    private let noticeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.isHidden = true
        return label
    }()

    private var cells: [WindowItemView] = []
    private var items: [SwitcherItem] = []
    private var selectedIndex = 0
    private var currentStyle: DisplayStyle = .current
    private var currentSize: ThumbnailSize = .current

    private var gridLayout = SwitcherGridLayout(
        frames: [],
        contentSize: .zero,
        scale: 1.0,
        imageHeight: 155,
        minCellWidth: 94,
        maxCellWidth: 310,
        rowCount: 0
    )

    private var lastAvailableWidth: CGFloat = 1280
    private var lastAvailableHeight: CGFloat = 800
    private var mouseAnchorOnPresent: NSPoint = .zero
    private var hasMouseMovedSincePresent = true

    var onActivate: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    var onCloseWindow: ((Int) -> Void)?
    var onSnapLeft: ((Int) -> Void)?
    var onSnapRight: ((Int) -> Void)?
    var onSnapPopover: ((Int, NSView) -> Void)?
    var onPinWindow: ((Int) -> Void)?

    var notices: [String] = [] {
        didSet {
            updateChromeLabels()
            needsLayout = true
        }
    }

    var hints: [String] = [] {
        didSet {
            updateChromeLabels()
            needsLayout = true
        }
    }

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        addSubview(surfaceView)
        let host = surfaceView.contentContainer

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        host.addSubview(scrollView)

        host.addSubview(selectedTitleLabel)
        host.addSubview(noticeLabel)
        host.addSubview(footerLabel)

        applyBackgroundPreferences()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackgroundPreferences()
        cells.forEach { $0.applyPalette() }
        updateChromeLabels()
    }

    func applyBackgroundPreferences() {
        appearance = Theme.resolvedAppearance(for: self)
        surfaceView.applyAppearance()
    }

    // MARK: - Content

    func configure(
        items: [SwitcherItem],
        availableHeight: CGFloat,
        availableWidth: CGFloat = 1280,
        notice: [String],
        style: DisplayStyle = .current,
        size: ThumbnailSize = .current
    ) {
        self.items = items
        self.notices = notice
        self.currentStyle = style
        self.currentSize = size
        self.lastAvailableHeight = availableHeight
        self.lastAvailableWidth = availableWidth

        let padX = horizontalPadding
        let maxPanelW = min((availableWidth * 0.86).rounded(), 1380)
        let maxGridW = max(240, maxPanelW - padX * 2)
        let maxPanelH = (availableHeight * 0.82).rounded()
        let chromeH = chromeVerticalOverhead(itemCount: items.count, noticeCount: notice.count)
        let maxGridH = max(120, maxPanelH - chromeH)

        gridLayout = SwitcherGridLayout.compute(
            aspectRatios: items.map(\.window.aspectRatio),
            style: style,
            size: size,
            autoAdjustSize: AppearancePreferences.autoAdjustSize,
            maxContentWidth: maxGridW,
            maxContentHeight: maxGridH
        )

        applyBackgroundPreferences()
        rebuildCells()
        updateChromeLabels()
    }

    private var horizontalPadding: CGFloat {
        if currentStyle == .iconsOnly {
            return items.count <= 4 ? 14 : 18
        }
        return items.count <= 3 ? 16 : 20
    }

    private var topPadding: CGFloat {
        currentStyle == .iconsOnly ? 14 : 16
    }

    private var bottomPadding: CGFloat {
        currentStyle == .iconsOnly ? 14 : 14
    }

    private func chromeVerticalOverhead(itemCount: Int, noticeCount: Int) -> CGFloat {
        var total = topPadding + bottomPadding
        if noticeCount > 0 {
            total += 20
        }
        if shouldShowFooterHints {
            total += 20
        }
        return total
    }

    private var shouldShowFooterHints: Bool {
        currentStyle != .iconsOnly && AppearancePreferences.showFooterHints
    }

    private func rebuildCells() {
        cells.forEach { $0.removeFromSuperview() }
        cells = items.enumerated().map { index, item in
            let cell = WindowItemView(
                info: item.window,
                caption: item.caption,
                appIcon: item.icon,
                style: currentStyle
            )
            cell.onActivate = { [weak self] in self?.onActivate?(index) }
            cell.canActivateHover = { [weak self] in
                self?.allowMouseHover() ?? true
            }
            cell.onHover = { [weak self] _ in
                guard let self, self.allowMouseHover(), self.selectedIndex != index else { return }
                self.setSelection(index, animated: false)
                self.onHover?(index)
            }
            cell.onClose = { [weak self] in self?.onCloseWindow?(index) }
            cell.onSnapLeft = { [weak self] in self?.onSnapLeft?(index) }
            cell.onSnapRight = { [weak self] in self?.onSnapRight?(index) }
            cell.onSnapPopover = { [weak self] anchor in self?.onSnapPopover?(index, anchor) }
            cell.onPin = { [weak self] in self?.onPinWindow?(index) }
            documentView.addSubview(cell)
            return cell
        }
        applySelection(animated: false)
        needsLayout = true
    }

    var thumbnailMetrics: (height: CGFloat, maxWidth: CGFloat, minWidth: CGFloat) {
        (gridLayout.imageHeight, gridLayout.maxCellWidth, gridLayout.minCellWidth)
    }

    func preferredSize(for screen: NSScreen) -> CGSize {
        let visible = screen.visibleFrame
        let padX = horizontalPadding
        let maxPanelW = min((visible.width * 0.86).rounded(), 1380)
        let maxPanelH = (visible.height * 0.82).rounded()

        let chromeH = chromeVerticalOverhead(itemCount: items.count, noticeCount: notices.count)
        let maxGridH = max(120, maxPanelH - chromeH)
        let visibleGridH = min(gridLayout.contentSize.height, maxGridH)

        // Snug natural width around items without unnecessary empty padding
        let gridWidth = max(100, gridLayout.contentSize.width)
        let needsVerticalScroll = gridLayout.contentSize.height > maxGridH + 0.5
        let scrollerReserve: CGFloat = needsVerticalScroll ? 12 : 0
        let width = min(maxPanelW, gridWidth + padX * 2 + scrollerReserve)
        let height = min(maxPanelH, visibleGridH + chromeH)

        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    // MARK: - Selection

    func setSelection(_ index: Int, animated: Bool = true) {
        guard !cells.isEmpty else { return }
        let newIndex = min(max(0, index), cells.count - 1)
        let oldIndex = selectedIndex
        selectedIndex = newIndex

        if oldIndex != newIndex {
            if oldIndex >= 0 && oldIndex < cells.count {
                cells[oldIndex].setSelected(false, filteredOut: false)
            }
            if newIndex >= 0 && newIndex < cells.count {
                cells[newIndex].setSelected(true, filteredOut: false)
            }
        } else {
            cells[newIndex].setSelected(true, filteredOut: false)
        }

        scrollSelectionIntoView(animated: animated)
        updateChromeLabels()
    }

    /// Returns the selected cell's rect in global screen coordinates for anchoring dwell previews.
    func selectedCellScreenRect() -> NSRect? {
        guard let window, selectedIndex >= 0, selectedIndex < cells.count else { return nil }
        let cell = cells[selectedIndex]
        let rectInWindow = cell.convert(cell.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private func applySelection(animated: Bool) {
        for (index, cell) in cells.enumerated() {
            cell.setSelected(index == selectedIndex, filteredOut: false)
        }
        scrollSelectionIntoView(animated: animated)
    }

    private func scrollSelectionIntoView(animated: Bool) {
        guard selectedIndex >= 0, selectedIndex < gridLayout.frames.count else { return }
        let targetRect = gridLayout.frames[selectedIndex].insetBy(dx: -8, dy: -8)
        let clipBounds = scrollView.contentView.bounds
        guard documentView.frame.height > clipBounds.height + 0.5 else {
            if clipBounds.origin.y != 0 {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            return
        }

        if !animated && clipBounds.contains(gridLayout.frames[selectedIndex]) {
            return
        }

        var nextY = clipBounds.origin.y
        if targetRect.minY < clipBounds.minY {
            nextY = max(0, targetRect.minY)
        } else if targetRect.maxY > clipBounds.maxY {
            nextY = min(documentView.frame.height - clipBounds.height, targetRect.maxY - clipBounds.height)
        }

        guard abs(nextY - clipBounds.origin.y) > 0.5 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.selection
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: nextY))
            }
        } else {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: nextY))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Chrome Labels

    private func updateChromeLabels() {
        selectedTitleLabel.stringValue = ""
        selectedTitleLabel.isHidden = true

        if let noticeText = notices.first(where: { !$0.isEmpty }) {
            noticeLabel.stringValue = noticeText
            noticeLabel.textColor = noticeText.contains("Screen Recording")
                ? .systemOrange
                : .secondaryLabelColor
            noticeLabel.isHidden = false
        } else {
            noticeLabel.stringValue = ""
            noticeLabel.isHidden = true
        }

        if shouldShowFooterHints && bounds.width > 0 {
            let maxTextW = max(120, bounds.width - horizontalPadding * 2)
            footerLabel.attributedStringValue = fittedFooterAttributedString(maxWidth: maxTextW)
            footerLabel.isHidden = footerLabel.attributedStringValue.length == 0
        } else if !shouldShowFooterHints {
            footerLabel.isHidden = true
        }
    }

    private func fittedFooterAttributedString(maxWidth: CGFloat) -> NSAttributedString {
        let baseHints = hints.isEmpty
            ? ["⌥Tab next", "←/→ snap", "W close", "esc cancel"]
            : hints + ["esc cancel"]

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let separator = NSAttributedString(
            string: "   ·   ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.quaternaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )

        let combined = NSMutableAttributedString()
        for hint in baseHints {
            let candidate = formatHint(hint, paragraph: paragraph)
            let trial = NSMutableAttributedString(attributedString: combined)
            if trial.length > 0 {
                trial.append(separator)
            }
            trial.append(candidate)
            if trial.size().width <= maxWidth {
                combined.setAttributedString(trial)
            } else {
                break
            }
        }
        return combined
    }

    private func formatHint(_ text: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                    .foregroundColor: Theme.footerText,
                    .paragraphStyle: paragraph
                ]
            )
        }
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: String(parts[0]) + " ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        ))
        result.append(NSAttributedString(
            string: String(parts[1]),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: Theme.footerText,
                .paragraphStyle: paragraph
            ]
        ))
        return result
    }

    // MARK: - Mouse Hover Guard & Clicks

    /// Prevents a stationary cursor resting beneath the newly opened switcher panel
    /// from hijacking selection before the user actually moves the mouse.
    func armMouseHoverGuard() {
        mouseAnchorOnPresent = NSEvent.mouseLocation
        hasMouseMovedSincePresent = false
    }

    private func allowMouseHover() -> Bool {
        if hasMouseMovedSincePresent { return true }
        let current = NSEvent.mouseLocation
        if hypot(current.x - mouseAnchorOnPresent.x, current.y - mouseAnchorOnPresent.y) > 4.0 {
            hasMouseMovedSincePresent = true
            return true
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        let pointInDoc = documentView.convert(event.locationInWindow, from: nil)
        for (index, cell) in cells.enumerated() where cell.frame.contains(pointInDoc) {
            setSelection(index)
            onActivate?(index)
            return
        }
    }

    // MARK: - Thumbnails

    func applyThumbnail(_ image: NSImage?, at index: Int, windowID: CGWindowID) {
        if index >= 0, index < cells.count, cells[index].info.id == windowID {
            let cell = cells[index]
            if let image {
                cell.setThumbnail(image)
            } else {
                cell.showFallbackIcon()
            }
            return
        }
        applyThumbnail(image, toWindowID: windowID)
    }

    func applyThumbnail(_ image: NSImage?, toWindowID id: CGWindowID) {
        for cell in cells where cell.info.id == id {
            if let image {
                cell.setThumbnail(image)
            } else {
                cell.showFallbackIcon()
            }
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        surfaceView.frame = bounds
        surfaceView.layoutSubtreeIfNeeded()

        let padX = horizontalPadding
        let contentW = max(1, bounds.width - padX * 2)

        // Lay out bottom chrome upward
        var curBottomY = bottomPadding

        if shouldShowFooterHints {
            footerLabel.frame = NSRect(x: padX, y: curBottomY, width: contentW, height: 16)
            let maxTextW = max(120, contentW)
            footerLabel.attributedStringValue = fittedFooterAttributedString(maxWidth: maxTextW)
            footerLabel.isHidden = footerLabel.attributedStringValue.length == 0
            curBottomY += 20
        } else {
            footerLabel.isHidden = true
        }

        if let noticeText = notices.first(where: { !$0.isEmpty }) {
            noticeLabel.stringValue = noticeText
            noticeLabel.frame = NSRect(x: padX, y: curBottomY, width: contentW, height: 16)
            noticeLabel.isHidden = false
            curBottomY += 20
        } else {
            noticeLabel.isHidden = true
        }

        selectedTitleLabel.isHidden = true

        let scrollTop = bounds.height - topPadding
        let availScrollH = max(40, scrollTop - curBottomY)
        let scrollH = min(availScrollH, max(gridLayout.contentSize.height, 1))
        let scrollY = curBottomY + max(0, (availScrollH - scrollH) / 2)

        scrollView.frame = NSRect(x: padX, y: scrollY, width: contentW, height: scrollH)
        let docWidth = max(contentW, gridLayout.contentSize.width)
        let docHeight = max(scrollH, gridLayout.contentSize.height)
        documentView.frame = NSRect(x: 0, y: 0, width: docWidth, height: docHeight)

        let needsScroll = gridLayout.contentSize.height > scrollH + 0.5
        scrollView.hasVerticalScroller = needsScroll

        let offsetX = max(0, ((docWidth - gridLayout.contentSize.width) / 2).rounded())
        for (index, cell) in cells.enumerated() where index < gridLayout.frames.count {
            var frame = gridLayout.frames[index]
            frame.origin.x += offsetX
            cell.frame = frame
        }
    }
}

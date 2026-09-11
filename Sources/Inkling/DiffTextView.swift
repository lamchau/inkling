import AppKit
import InklingDiff
import SwiftUI

@MainActor
final class FileDropTargetView: NSView {
    var onTargetChange: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Bool = { _ in false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        return NSPasteboard(name: .drag).canReadObject(
            forClasses: [NSURL.self],
            options: options
        ) ? self : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard fileURLs(from: sender).count == 1 else { return [] }
        onTargetChange(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChange(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargetChange(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargetChange(false)
        let urls = fileURLs(from: sender)
        return urls.count == 1 && onDrop(urls)
    }

    private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        return (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []
    }
}

@MainActor
final class DiffEditorContainerView: NSView {
    let scrollView: NSScrollView
    let gutterView: LineNumberGutterView
    let dropTargetView = FileDropTargetView()
    var showsLineNumbers = false {
        didSet {
            gutterView.isHidden = !showsLineNumbers
            needsLayout = true
        }
    }

    init(scrollView: NSScrollView, gutterView: LineNumberGutterView) {
        self.scrollView = scrollView
        self.gutterView = gutterView
        super.init(frame: .zero)
        addSubview(gutterView)
        addSubview(scrollView)
        addSubview(dropTargetView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let gutterWidth = showsLineNumbers ? LineNumberGutterView.width : 0
        gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(
            x: gutterWidth,
            y: 0,
            width: max(0, bounds.width - gutterWidth),
            height: bounds.height
        )
        dropTargetView.frame = bounds
    }
}

struct DiffTextView: NSViewRepresentable {
    @Binding var text: String
    let highlights: [TextHighlight]
    let currentChangeRange: NSRange?
    let navigationOffset: Int
    let navigationRevision: Int
    let side: DiffSide
    let showLineNumbers: Bool
    let highlightStyle: HighlightStyle
    let palette: DiffPalette
    let syncScrolling: Bool
    let syncCaret: Bool
    @Binding var sharedScrollOrigin: CGPoint
    @Binding var sharedCaret: CaretPosition?
    @Binding var isDropTargeted: Bool
    let onDrop: ([URL]) -> Bool
    let onEditorChange: (NSTextView?) -> Void
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DiffEditorContainerView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.alignment = .left
        textView.baseWritingDirection = .leftToRight
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView
        Self.replaceTextWithoutUndo(text, in: textView)
        let gutterView = LineNumberGutterView(
            scrollView: scrollView,
            textView: textView
        )
        let containerView = DiffEditorContainerView(
            scrollView: scrollView,
            gutterView: gutterView
        )
        context.coordinator.scrollView = scrollView
        context.coordinator.gutterView = gutterView
        context.coordinator.observeScroll()
        context.coordinator.observeTextStorage()
        onEditorChange(textView)
        configureDropTarget(containerView, context: context)
        updateLineNumbers(containerView)
        Self.applyHighlights(
            highlights,
            currentChangeRange: currentChangeRange,
            style: highlightStyle,
            palette: palette,
            to: textView
        )
        return containerView
    }

    func updateNSView(_ containerView: DiffEditorContainerView, context: Context) {
        context.coordinator.parent = self
        let scrollView = containerView.scrollView
        guard let textView = context.coordinator.textView else { return }
        configureDropTarget(containerView, context: context)
        if textView.string != text {
            context.coordinator.isApplyingUpdate = true
            Self.replaceTextPreservingSelection(text, in: textView)
            context.coordinator.isApplyingUpdate = false
            context.coordinator.gutterView?.refresh()
        }
        updateLineNumbers(containerView)
        scrollView.contentView.scroll(to: CGPoint(
            x: 0,
            y: scrollView.contentView.bounds.origin.y
        ))
        Self.applyHighlights(
            highlights,
            currentChangeRange: currentChangeRange,
            style: highlightStyle,
            palette: palette,
            to: textView
        )

        if context.coordinator.lastNavigationRevision != navigationRevision {
            context.coordinator.lastNavigationRevision = navigationRevision
            context.coordinator.lastNavigationOffset = navigationOffset
            let safeOffset = min(navigationOffset, textView.string.utf16.count)
            center(safeOffset, in: textView, scrollView: scrollView)
            if let currentRange = Self.currentDisplayRange(
                currentChangeRange,
                fallbackOffset: safeOffset,
                textLength: textView.string.utf16.count
            ) {
                textView.showFindIndicator(for: currentRange)
            }
        }

        if syncScrolling,
           !context.coordinator.isPublishingScroll,
           scrollView.contentView.bounds.origin.y != sharedScrollOrigin.y
        {
            context.coordinator.isApplyingScroll = true
            scrollView.contentView.scroll(to: CGPoint(
                x: 0,
                y: sharedScrollOrigin.y
            ))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.isApplyingScroll = false
        }

        if syncCaret,
           let sharedCaret,
           sharedCaret.source != context.coordinator.side,
           context.coordinator.lastAppliedCaret != sharedCaret
        {
            context.coordinator.lastAppliedCaret = sharedCaret
            let offset = offset(
                line: sharedCaret.line,
                column: sharedCaret.column,
                in: textView.string
            )
            context.coordinator.isApplyingCaret = true
            textView.setSelectedRange(NSRange(location: offset, length: 0))
            textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            context.coordinator.isApplyingCaret = false
        }
    }

    static func dismantleNSView(_ nsView: DiffEditorContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.parent.onEditorChange(nil)
    }

    static func applyHighlights(
        _ highlights: [TextHighlight],
        currentChangeRange: NSRange? = nil,
        style: HighlightStyle = .foreground,
        palette: DiffPalette = .default,
        to textView: NSTextView
    ) {
        guard let storage = textView.textStorage, let layoutManager = textView.layoutManager else {
            return
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.baseWritingDirection = .leftToRight
        paragraphStyle.lineBreakMode = .byWordWrapping
        storage.beginEditing()
        storage.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)
        storage.endEditing()
        textView.alignment = .left
        textView.baseWritingDirection = .leftToRight
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
        ]

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        for highlight in highlights.sorted(by: {
            highlightPriority($0.kind) < highlightPriority($1.kind)
        }) {
            let range = NSIntersectionRange(highlight.range, fullRange)
            guard range.length > 0 else { continue }
            let color = palette.color(for: highlight.kind.category).nsColor
            switch style {
            case .foreground:
                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: color,
                    forCharacterRange: range
                )
                if highlight.kind.category == .character {
                    layoutManager.addTemporaryAttributes([
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: color,
                    ], forCharacterRange: range)
                }
            case .background:
                let isCharacter = highlight.kind.category == .character
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: color.withAlphaComponent(isCharacter ? 0.9 : 0.4),
                    forCharacterRange: range
                )
                if isCharacter {
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: NSColor.white,
                        forCharacterRange: range
                    )
                }
            }
        }
        if let currentRange = currentDisplayRange(
            currentChangeRange,
            fallbackOffset: 0,
            textLength: storage.length
        ) {
            layoutManager.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.double.rawValue,
                .underlineColor: NSColor.controlAccentColor,
            ], forCharacterRange: currentRange)
        }
        textView.needsDisplay = true
    }

    static func replaceTextPreservingSelection(_ text: String, in textView: NSTextView) {
        let selectedRanges = textView.selectedRanges
        replaceTextWithoutUndo(text, in: textView)
        let textLength = text.utf16.count
        let restoredRanges = selectedRanges.compactMap { value -> NSValue? in
            let range = value.rangeValue
            guard range.location != NSNotFound else { return nil }
            let location = min(range.location, textLength)
            let length = min(range.length, textLength - location)
            return NSValue(range: NSRange(location: location, length: length))
        }
        textView.selectedRanges = restoredRanges.isEmpty
            ? [NSValue(range: NSRange(location: textLength, length: 0))]
            : restoredRanges
    }

    static func replaceTextWithoutUndo(_ text: String, in textView: NSTextView) {
        let undoManager = textView.undoManager
        let undoWasEnabled = undoManager?.isUndoRegistrationEnabled == true
        if undoWasEnabled {
            undoManager?.disableUndoRegistration()
        }
        textView.string = text
        if undoWasEnabled {
            undoManager?.enableUndoRegistration()
        }
    }

    private static func highlightPriority(_ kind: HighlightKind) -> Int {
        switch kind.category {
        case .phrase, .addition, .deletion: 0
        case .word: 1
        case .character: 2
        }
    }

    private static func currentDisplayRange(
        _ range: NSRange?,
        fallbackOffset: Int,
        textLength: Int
    ) -> NSRange? {
        guard let range else { return nil }
        if range.length > 0, NSMaxRange(range) <= textLength {
            return range
        }
        guard textLength > 0 else { return nil }
        return NSRange(
            location: min(fallbackOffset, textLength - 1),
            length: 1
        )
    }

    private func updateLineNumbers(_ containerView: DiffEditorContainerView) {
        containerView.showsLineNumbers = showLineNumbers
        containerView.gutterView.needsDisplay = true
    }

    private func configureDropTarget(
        _ containerView: DiffEditorContainerView,
        context: Context
    ) {
        containerView.dropTargetView.onTargetChange = { isTargeted in
            context.coordinator.parent.isDropTargeted = isTargeted
        }
        containerView.dropTargetView.onDrop = { urls in
            context.coordinator.parent.onDrop(urls)
        }
    }

    private func center(_ offset: Int, in textView: NSTextView, scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              layoutManager.numberOfGlyphs > 0
        else { return }
        let glyph = min(
            layoutManager.numberOfGlyphs - 1,
            layoutManager.glyphIndexForCharacter(at: min(offset, max(0, textView.string.utf16.count - 1)))
        )
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 0),
            in: textContainer
        )
        let targetY = max(
            0,
            rect.midY + textView.textContainerInset.height
                - scrollView.contentView.bounds.height / 2
        )
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func offset(line: Int, column: Int, in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        let safeLine = min(max(0, line), max(0, lines.count - 1))
        let prefix = lines.prefix(safeLine).reduce(0) { $0 + $1.utf16.count + 1 }
        return prefix + min(column, lines[safeLine].utf16.count)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DiffTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var gutterView: LineNumberGutterView?
        let side: DiffSide
        var isApplyingUpdate = false
        var isApplyingScroll = false
        var isPublishingScroll = false
        var isApplyingCaret = false
        var lastNavigationOffset = -1
        var lastNavigationRevision = -1
        var lastAppliedCaret: CaretPosition?

        init(parent: DiffTextView) {
            self.parent = parent
            side = parent.side
        }

        func observeScroll() {
            guard let contentView = scrollView?.contentView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollDidChange),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        func observeTextStorage() {
            guard let textStorage = textView?.textStorage else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(storageEditingProcessed),
                name: NSTextStorage.didProcessEditingNotification,
                object: textStorage
            )
        }

        @objc private func scrollDidChange() {
            guard !isApplyingScroll, let scrollView else { return }
            isPublishingScroll = true
            parent.sharedScrollOrigin = CGPoint(
                x: 0,
                y: scrollView.contentView.bounds.origin.y
            )
            gutterView?.needsDisplay = true
            isPublishingScroll = false
        }

        @objc private func storageEditingProcessed(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textStorage = notification.object as? NSTextStorage,
                  textStorage.editedMask.contains(.editedCharacters)
            else {
                return
            }
            publishTextChange()
        }

        func textDidChange(_ notification: Notification) {
            publishTextChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.onFocus()
            guard parent.syncCaret, !isApplyingCaret, let textView else { return }
            let location = textView.selectedRange().location
            let nsText = textView.string as NSString
            let lineRange = nsText.lineRange(
                for: NSRange(location: min(location, nsText.length), length: 0)
            )
            let prefix = nsText.substring(to: lineRange.location)
            let line = prefix.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            parent.sharedCaret = CaretPosition(
                line: line,
                column: location - lineRange.location,
                source: side
            )
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus()
        }

        private func publishTextChange() {
            guard !isApplyingUpdate,
                  let textView,
                  parent.text != textView.string
            else {
                return
            }
            parent.text = textView.string
            gutterView?.refresh()
        }
    }
}

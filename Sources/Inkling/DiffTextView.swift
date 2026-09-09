import AppKit
import SwiftUI

struct DiffTextView: NSViewRepresentable {
    @Binding var text: String
    let highlights: [TextHighlight]
    let navigationOffset: Int
    let navigationRevision: Int
    let side: DiffSide
    let showLineNumbers: Bool
    let syncScrolling: Bool
    let syncCaret: Bool
    @Binding var sharedScrollOrigin: CGPoint
    @Binding var sharedCaret: CaretPosition?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = LineNumberRulerView(
            scrollView: scrollView,
            textView: textView
        )
        context.coordinator.observeScroll()
        updateRuler(scrollView, coordinator: context.coordinator)
        Self.applyHighlights(highlights, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.isApplyingUpdate = true
            textView.string = text
            textView.selectedRanges = selectedRanges.filter {
                NSMaxRange($0.rangeValue) <= text.utf16.count
            }
            context.coordinator.isApplyingUpdate = false
            context.coordinator.rulerView?.refresh()
        }
        updateRuler(scrollView, coordinator: context.coordinator)
        Self.applyHighlights(highlights, to: textView)

        if context.coordinator.lastNavigationRevision != navigationRevision {
            context.coordinator.lastNavigationRevision = navigationRevision
            context.coordinator.lastNavigationOffset = navigationOffset
            let safeOffset = min(navigationOffset, textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: safeOffset, length: 0))
            center(safeOffset, in: textView, scrollView: scrollView)
        }

        if syncScrolling,
           !context.coordinator.isPublishingScroll,
           scrollView.contentView.bounds.origin.y != sharedScrollOrigin.y
        {
            context.coordinator.isApplyingScroll = true
            scrollView.contentView.scroll(to: CGPoint(
                x: scrollView.contentView.bounds.origin.x,
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

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    static func applyHighlights(_ highlights: [TextHighlight], to textView: NSTextView) {
        guard let storage = textView.textStorage, let layoutManager = textView.layoutManager else {
            return
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)
        storage.endEditing()

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
        for highlight in highlights {
            let range = NSIntersectionRange(highlight.range, fullRange)
            guard range.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: color(for: highlight.kind),
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                forCharacterRange: range
            )
        }
        textView.needsDisplay = true
    }

    private static func color(for kind: HighlightKind) -> NSColor {
        switch kind {
        case .addition:
            return .systemGreen
        case .deletion:
            return .systemRed
        case let .character(index):
            return alternating([.systemPink, .systemPurple], index: index)
        case let .word(index):
            return alternating([.systemOrange, .systemYellow], index: index)
        case let .phrase(index):
            return alternating([.systemBlue, .systemTeal], index: index)
        }
    }

    private static func alternating(_ colors: [NSColor], index: Int) -> NSColor {
        colors[index % colors.count]
    }

    private func updateRuler(_ scrollView: NSScrollView, coordinator: Coordinator) {
        scrollView.verticalRulerView = coordinator.rulerView
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
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
        var rulerView: LineNumberRulerView?
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

        @objc private func scrollDidChange() {
            guard !isApplyingScroll, let scrollView else { return }
            isPublishingScroll = true
            parent.sharedScrollOrigin = CGPoint(
                x: 0,
                y: scrollView.contentView.bounds.origin.y
            )
            isPublishingScroll = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView else { return }
            parent.text = textView.string
            rulerView?.refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
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
    }
}

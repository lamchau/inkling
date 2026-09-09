import AppKit

@MainActor
final class LineNumberGutterView: NSView {
    static let width: CGFloat = 44

    override var isFlipped: Bool { true }

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    private var lineStarts: [Int] = [0]

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
        refresh()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        guard let textView else { return }
        lineStarts = [0]
        for (offset, character) in textView.string.utf16.enumerated() where character == 10 {
            lineStarts.append(offset + 1)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager
        else { return }

        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        for (index, characterIndex) in lineStarts.enumerated() {
            guard characterIndex < textView.string.utf16.count else { continue }
            let glyphIndex = min(
                layoutManager.numberOfGlyphs,
                layoutManager.glyphIndexForCharacter(at: characterIndex)
            )
            guard glyphIndex < layoutManager.numberOfGlyphs else { continue }
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            let y = lineRect.minY + textView.textContainerInset.height - visibleRect.minY
            guard y >= dirtyRect.minY - lineRect.height, y <= dirtyRect.maxY else { continue }

            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: bounds.width - size.width - 8, y: y),
                withAttributes: attributes
            )
        }

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.width - 0.5, y: dirtyRect.minY))
        separator.line(to: NSPoint(x: bounds.width - 0.5, y: dirtyRect.maxY))
        separator.stroke()
    }
}

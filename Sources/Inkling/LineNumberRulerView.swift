import AppKit

@MainActor
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
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

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager
        else { return }

        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
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
            guard y >= rect.minY - lineRect.height, y <= rect.maxY else { continue }

            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 8, y: y),
                withAttributes: attributes
            )
        }

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: ruleThickness - 0.5, y: rect.minY))
        separator.line(to: NSPoint(x: ruleThickness - 0.5, y: rect.maxY))
        separator.stroke()
    }
}

import AppKit
import Testing
@testable import Inkling

@Suite("Diff text rendering")
@MainActor
struct DiffTextViewTests {
    @Test("diff colors are installed as temporary layout attributes")
    func temporaryColors() {
        let textView = NSTextView()
        textView.string = "alpha beta"
        let highlight = TextHighlight(
            range: NSRange(location: 6, length: 4),
            kind: .word(0)
        )

        DiffTextView.applyHighlights([highlight], to: textView)

        let foreground = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 7,
            effectiveRange: nil
        ) as? NSColor
        #expect(foreground != nil)
        #expect(foreground?.alphaComponent == 1)
    }
}

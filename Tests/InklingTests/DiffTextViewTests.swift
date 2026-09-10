import AppKit
import Testing
@testable import Inkling

@Suite("Diff text rendering")
@MainActor
struct DiffTextViewTests {
    @Test("comparison panes always have equal widths")
    func equalPaneWidths() {
        let totalWidth: CGFloat = 1_200
        let paneWidth = EditorLayout.paneWidth(totalWidth: totalWidth)

        #expect(
            paneWidth * 2
                + EditorLayout.railWidth
                + EditorLayout.dividerWidth * 2 == totalWidth
        )
    }

    @Test("diff colors are installed as temporary layout attributes")
    func temporaryColors() {
        let textView = NSTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 100)
        textView.textContainer?.containerSize = NSSize(width: 320, height: 100)
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
        let baseColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 1,
            effectiveRange: nil
        ) as? NSColor
        #expect(baseColor == .textColor)
        let font = textView.textStorage?.attribute(
            .font,
            at: 1,
            effectiveRange: nil
        ) as? NSFont
        #expect(font?.pointSize == 13)
        let paragraph = textView.textStorage?.attribute(
            .paragraphStyle,
            at: 1,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraph?.alignment == .left)
        #expect(paragraph?.baseWritingDirection == .leftToRight)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        #expect((textView.layoutManager?.numberOfGlyphs ?? 0) == textView.string.count)
        let glyphRect = textView.layoutManager?.boundingRect(
            forGlyphRange: NSRange(location: 0, length: textView.string.count),
            in: textView.textContainer!
        )
        #expect(glyphRect?.width ?? 0 > 0)
        #expect(glyphRect?.height ?? 0 > 0)
    }

    @Test("background mode installs blocks without foreground colors")
    func backgroundColors() {
        let textView = NSTextView()
        textView.string = "alpha beta"
        let highlight = TextHighlight(
            range: NSRange(location: 6, length: 4),
            kind: .word(0)
        )

        DiffTextView.applyHighlights(
            [highlight],
            style: .background,
            to: textView
        )

        let background = textView.layoutManager?.temporaryAttribute(
            .backgroundColor,
            atCharacterIndex: 7,
            effectiveRange: nil
        ) as? NSColor
        let foreground = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 7,
            effectiveRange: nil
        ) as? NSColor
        #expect(background?.alphaComponent == 0.4)
        #expect(foreground == nil)
    }

    @Test("character blocks remain visible inside word blocks")
    func nestedCharacterBackground() {
        let textView = NSTextView()
        textView.string = "tempora"
        let character = TextHighlight(
            range: NSRange(location: 6, length: 1),
            kind: .character(0)
        )
        let word = TextHighlight(
            range: NSRange(location: 0, length: 7),
            kind: .word(0)
        )

        DiffTextView.applyHighlights(
            [character, word],
            style: .background,
            to: textView
        )

        let wordBackground = textView.layoutManager?.temporaryAttribute(
            .backgroundColor,
            atCharacterIndex: 2,
            effectiveRange: nil
        ) as? NSColor
        let characterBackground = textView.layoutManager?.temporaryAttribute(
            .backgroundColor,
            atCharacterIndex: 6,
            effectiveRange: nil
        ) as? NSColor
        let characterForeground = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 6,
            effectiveRange: nil
        ) as? NSColor

        #expect(wordBackground?.alphaComponent == 0.4)
        #expect(characterBackground?.alphaComponent == 0.9)
        #expect(characterForeground == .white)
    }

    @Test("character foregrounds remain distinct inside word colors")
    func nestedCharacterForeground() {
        let textView = NSTextView()
        textView.string = "tempora"
        let character = TextHighlight(
            range: NSRange(location: 6, length: 1),
            kind: .character(0)
        )
        let word = TextHighlight(
            range: NSRange(location: 0, length: 7),
            kind: .word(0)
        )

        DiffTextView.applyHighlights([character, word], to: textView)

        let wordForeground = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 2,
            effectiveRange: nil
        ) as? NSColor
        let characterForeground = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 6,
            effectiveRange: nil
        ) as? NSColor
        let underline = textView.layoutManager?.temporaryAttribute(
            .underlineStyle,
            atCharacterIndex: 6,
            effectiveRange: nil
        ) as? Int

        #expect(wordForeground == .systemOrange)
        #expect(characterForeground == .systemPink)
        #expect(underline == NSUnderlineStyle.thick.rawValue)
    }

    @Test("AppKit editor keeps text at the leading edge with line numbers")
    func editorGeometry() {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.string = String(repeating: "visible text ", count: 100)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        let gutterView = LineNumberGutterView(
            scrollView: scrollView,
            textView: textView
        )
        let containerView = DiffEditorContainerView(
            scrollView: scrollView,
            gutterView: gutterView
        )
        containerView.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        containerView.showsLineNumbers = true

        containerView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 0))

        #expect(scrollView.hasVerticalRuler == false)
        #expect(gutterView.frame.width == LineNumberGutterView.width)
        #expect(scrollView.frame.minX == LineNumberGutterView.width)
        #expect(scrollView.contentView.bounds.origin.x == 0)
        #expect(textView.frame.minX == 0)
        #expect(textView.frame.width > 500)
        #expect((textView.layoutManager?.numberOfGlyphs ?? 0) > 0)
    }
}

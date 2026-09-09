import Foundation
import Testing
@testable import Inkling

@Suite("Diff engine")
struct DiffEngineTests {
    @Test("identical text has no changes")
    func identical() {
        let result = DiffEngine.compare(
            left: "one\ntwo\n",
            right: "one\ntwo\n",
            ignoreWhitespace: false
        )

        #expect(result == .empty)
    }

    @Test("dissimilar words stay as meaningful word blocks")
    func wordReplacement() {
        let result = DiffEngine.compare(
            left: "let color = blue",
            right: "let color = green",
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 1)
        #expect(result.leftHighlights.count == 1)
        #expect(result.rightHighlights.count == 1)
        #expect(result.leftHighlights[0].range == NSRange(location: 12, length: 4))
        #expect(result.rightHighlights[0].range == NSRange(location: 12, length: 5))
        #expect(result.rightHighlights.allSatisfy {
            $0.kind == result.leftHighlights[0].kind
        })
    }

    @Test("similar changed words refine to characters")
    func characterRefinement() {
        let result = DiffEngine.compare(
            left: "color",
            right: "colour",
            ignoreWhitespace: false
        )

        #expect(result.leftHighlights.isEmpty)
        #expect(result.rightHighlights.map(\.range) == [
            NSRange(location: 4, length: 1),
        ])
    }

    @Test("inserted line is semantic addition")
    func insertion() {
        let result = DiffEngine.compare(
            left: "one\nthree",
            right: "one\ntwo\nthree",
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].leftRange.isEmpty)
        #expect(result.hunks[0].rightRange == 1..<2)
        #expect(result.rightHighlights == [
            TextHighlight(range: NSRange(location: 4, length: 3), kind: .addition),
        ])
    }

    @Test("whitespace-only edits can be ignored")
    func ignoreWhitespace() {
        let strict = DiffEngine.compare(
            left: "let value = 1",
            right: "let  value=1",
            ignoreWhitespace: false
        )
        let ignored = DiffEngine.compare(
            left: "let value = 1",
            right: "let  value=1",
            ignoreWhitespace: true
        )

        #expect(strict.hunks.count == 1)
        #expect(ignored.hunks.isEmpty)
        #expect(ignored.leftHighlights.isEmpty)
        #expect(ignored.rightHighlights.isEmpty)
    }

    @Test("UTF-16 offsets are safe for native text storage")
    func unicodeOffsets() {
        let result = DiffEngine.compare(
            left: "hello 👋 world",
            right: "hello 🌎 world",
            ignoreWhitespace: false
        )

        #expect(result.leftHighlights[0].range == NSRange(location: 6, length: 2))
        #expect(result.rightHighlights[0].range == NSRange(location: 6, length: 2))
    }

    @Test("multiple hunks remain independently navigable")
    func multipleHunks() {
        let result = DiffEngine.compare(
            left: "alpha\nsame\nomega",
            right: "ALPHA\nsame\nOMEGA",
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 2)
        #expect(result.hunks.map(\.leftRange) == [0..<1, 2..<3])
        #expect(result.hunks.map(\.rightRange) == [0..<1, 2..<3])
    }

    @Test("replacement lines still avoid whole-line highlights")
    func dissimilarReplacementChunks() {
        let result = DiffEngine.compare(
            left: "alpha beta",
            right: "gamma delta",
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 1)
        #expect(!result.leftHighlights.isEmpty)
        #expect(!result.rightHighlights.isEmpty)
        #expect(result.leftHighlights.contains { $0.range.length < "alpha beta".utf16.count })
        #expect(result.rightHighlights.contains { $0.range.length < "gamma delta".utf16.count })
    }

    @Test("unchanged words split long prose edits into separate blocks")
    func proseBlocks() {
        let result = DiffEngine.compare(
            left: "one alpha shared omega four",
            right: "one beta shared delta four",
            ignoreWhitespace: false
        )

        #expect(result.leftHighlights.map(\.range) == [
            NSRange(location: 4, length: 5),
            NSRange(location: 17, length: 5),
        ])
        #expect(result.rightHighlights.map(\.range) == [
            NSRange(location: 4, length: 4),
            NSRange(location: 16, length: 5),
        ])
    }

    @Test("algorithms expose distinct levels of detail")
    func algorithms() {
        let left = "color shared alpha"
        let right = "colour shared beta"
        let semantic = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false,
            algorithm: .semantic
        )
        let word = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false,
            algorithm: .word
        )
        let character = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false,
            algorithm: .character
        )
        let line = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false,
            algorithm: .line
        )

        #expect(semantic.leftHighlights.contains { $0.kind.category == .word })
        #expect(semantic.rightHighlights.contains { $0.kind.category == .character })
        #expect(word.leftHighlights.allSatisfy {
            $0.kind.category == .word || $0.kind.category == .phrase
        })
        #expect(character.leftHighlights.allSatisfy { $0.kind.category == .character })
        #expect(line.leftHighlights.map(\.range) == [
            NSRange(location: 0, length: left.utf16.count),
        ])
    }
}

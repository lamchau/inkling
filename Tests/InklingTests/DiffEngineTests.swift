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
        #expect(result.changes.count == 1)
    }

    @Test("similar changed words refine to characters")
    func characterRefinement() {
        let result = DiffEngine.compare(
            left: "color",
            right: "colour",
            ignoreWhitespace: false
        )

        #expect(result.leftHighlights.contains {
            $0.range == NSRange(location: 0, length: 5)
                && $0.kind.category == .word
        })
        #expect(result.rightHighlights.contains {
            $0.range == NSRange(location: 0, length: 6)
                && $0.kind.category == .word
        })
        #expect(result.rightHighlights.contains {
            $0.range == NSRange(location: 4, length: 1)
                && $0.kind.category == .character
        })
    }

    @Test("semantic diff pairs a word with a one-character suffix")
    func semanticWordSuffix() {
        let result = DiffEngine.compare(
            left: "sed do eiusmod tempor incididunt",
            right: "sed do eiusmod tempora incididunt",
            ignoreWhitespace: false
        )

        #expect(result.leftHighlights == [
            TextHighlight(range: NSRange(location: 15, length: 6), kind: .word(0)),
        ])
        #expect(result.rightHighlights.contains {
            $0.range == NSRange(location: 15, length: 7)
                && $0.kind.category == .word
        })
        #expect(result.rightHighlights.contains {
            $0.range == NSRange(location: 21, length: 1)
                && $0.kind.category == .character
        })
        #expect(result.changes.count == 1)
        #expect(result.changes[0].leftNavigationOffset == 15)
        #expect(result.changes[0].rightNavigationOffset == 15)
    }

    @Test("semantic anchors remain local in long prose")
    func semanticLongProse() {
        let prefix = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod "
        let left = prefix
            + "tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam."
        let right = prefix
            + "tempora incididunt ut labore et dolore magna aliqua, quod saepe numero occurrit. "
            + "Ut enim ad minim veniam."
        let result = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false
        )
        let temporRange = NSRange(location: prefix.utf16.count, length: 6)

        #expect(result.leftHighlights.contains {
            $0.range == temporRange && $0.kind.category == .word
        })
        #expect(!result.leftHighlights.contains {
            $0.range.location < temporRange.location
        })
        #expect(result.rightHighlights.contains {
            $0.range == NSRange(location: NSMaxRange(temporRange), length: 1)
                && $0.kind.category == .character
        })
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
        #expect(result.hunks.count == 1)
        #expect(result.changes.count == 2)
        #expect(result.changes.map(\.leftNavigationOffset) == [4, 17])
        #expect(result.changes.map(\.rightNavigationOffset) == [4, 16])
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

    @Test("character alignment groups competing edits")
    func groupedCharacterAlignment() {
        let result = DiffEngine.compare(
            left: "ab",
            right: "ba",
            ignoreWhitespace: false,
            algorithm: .character
        )

        #expect(result.leftHighlights.map(\.range) == [
            NSRange(location: 0, length: 1),
        ])
        #expect(result.rightHighlights.map(\.range) == [
            NSRange(location: 1, length: 1),
        ])
    }

    @Test("large comparisons retain unique interior anchors")
    func largePatienceAnchors() {
        let shared = (0..<600).map { "line \($0)" }
        let result = DiffEngine.compare(
            left: shared.joined(separator: "\n"),
            right: (["inserted first"] + shared + ["inserted last"])
                .joined(separator: "\n"),
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 2)
        #expect(result.leftHighlights.isEmpty)
        #expect(result.rightHighlights.count == 2)
        #expect(result.rightHighlights.allSatisfy { $0.kind.category == .addition })
    }

    @Test("large repeated inputs use linear-space alignment")
    func largeLinearSpaceAlignment() {
        let left = (0..<600).map { $0.isMultiple(of: 2) ? "alpha" : "beta" }
        let right = Array(left.dropFirst()) + [left[0]]
        let result = DiffEngine.compare(
            left: left.joined(separator: "\n"),
            right: right.joined(separator: "\n"),
            ignoreWhitespace: false
        )

        #expect(result.hunks.count == 2)
        #expect(result.leftHighlights.count == 1)
        #expect(result.rightHighlights.count == 1)
    }
}

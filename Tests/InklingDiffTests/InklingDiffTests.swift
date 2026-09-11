import Foundation
import InklingDiff
import Testing

@Suite("InklingDiff public contract")
struct InklingDiffTests {
    @Test("all small character comparisons match an exhaustive LCS oracle")
    func exhaustiveCharacterOracle() throws {
        let values = strings(alphabet: ["a", "b", "c"], maximumLength: 5)

        for left in values {
            for right in values {
                let result = DiffEngine.compare(
                    left: left,
                    right: right,
                    ignoreWhitespace: false,
                    strategy: .character
                )
                try result.validate(left: left, right: right)

                let shared = lcsLength(Array(left), Array(right))
                #expect(result.leftHighlights.count == left.count - shared)
                #expect(result.rightHighlights.count == right.count - shared)
                #expect(
                    unchangedUTF16(left, excluding: result.leftHighlights)
                        == unchangedUTF16(right, excluding: result.rightHighlights)
                )
                #expect(
                    unchangedUTF16(left, excluding: result.leftHighlights).count
                        == shared
                )
                #expect(result.diagnostics.quality == .exact)
            }
        }
    }

    @Test("public result is deterministic and symmetric")
    func deterministicSymmetry() throws {
        var generator = SeededGenerator(seed: 0x1A2B3C4D)
        for _ in 0..<1_000 {
            let left = randomString(using: &generator)
            let right = randomString(using: &generator)
            let forward = DiffEngine.compare(
                left: left,
                right: right,
                ignoreWhitespace: false,
                strategy: .semantic
            )
            let repeated = DiffEngine.compare(
                left: left,
                right: right,
                ignoreWhitespace: false,
                strategy: .semantic
            )
            let reverse = DiffEngine.compare(
                left: right,
                right: left,
                ignoreWhitespace: false,
                strategy: .semantic
            )

            #expect(forward == repeated)
            #expect(forward.leftHighlights == reverse.rightHighlights)
            #expect(forward.rightHighlights == reverse.leftHighlights)
            try forward.validate(left: left, right: right)
            try reverse.validate(left: right, right: left)
        }
    }

    @Test("validation rejects ranges outside source text")
    func rejectsInvalidRange() {
        let result = DiffResult(
            leftHighlights: [
                TextHighlight(
                    range: NSRange(location: 2, length: 1),
                    kind: .deletion
                ),
            ],
            rightHighlights: [],
            hunks: [],
            changes: []
        )

        #expect(throws: DiffValidationError.invalidRange(.left)) {
            try result.validate(left: "a", right: "")
        }
    }

    @Test("validation rejects ranges that split a Unicode scalar")
    func rejectsSplitUTF16Range() {
        let result = DiffResult(
            leftHighlights: [
                TextHighlight(
                    range: NSRange(location: 1, length: 1),
                    kind: .deletion
                ),
            ],
            rightHighlights: [],
            hunks: [],
            changes: []
        )

        #expect(throws: DiffValidationError.invalidRange(.left)) {
            try result.validate(left: "🙂", right: "")
        }
    }

    @Test("validation accepts scalar boundaries inside a grapheme cluster")
    func acceptsScalarBoundaryInsideGrapheme() throws {
        let text = "e\u{301}"
        let result = DiffResult(
            leftHighlights: [
                TextHighlight(
                    range: NSRange(location: 0, length: 1),
                    kind: .character(0)
                ),
            ],
            rightHighlights: [],
            hunks: [],
            changes: []
        )

        try result.validate(left: text, right: "")
    }

    @Test("validation rejects navigation inside a surrogate pair")
    func rejectsSplitUTF16NavigationOffset() {
        let result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 0..<1,
                    rightRange: 0..<1,
                    leftNavigationOffset: 1,
                    rightNavigationOffset: 0
                ),
            ],
            changes: []
        )

        #expect(throws: DiffValidationError.invalidNavigationOffset(.left)) {
            try result.validate(left: "🙂", right: "")
        }
    }

    @Test("final newline differences produce valid ranges")
    func validatesFinalNewlineDifference() throws {
        for strategy in DiffStrategy.allCases {
            let removed = DiffEngine.compare(
                left: "\n",
                right: "",
                ignoreWhitespace: false,
                strategy: strategy
            )
            let added = DiffEngine.compare(
                left: "",
                right: "\n",
                ignoreWhitespace: false,
                strategy: strategy
            )

            try removed.validate(left: "\n", right: "")
            try added.validate(left: "", right: "\n")
        }
    }

    @Test("validation rejects hunk lines outside source text")
    func rejectsInvalidLineRange() {
        let result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 0..<2,
                    rightRange: 0..<1,
                    leftNavigationOffset: 0,
                    rightNavigationOffset: 0
                ),
            ],
            changes: []
        )

        #expect(throws: DiffValidationError.invalidLineRange(.left)) {
            try result.validate(left: "one", right: "one")
        }
    }

    @Test("configuration rejects invalid thresholds without trapping")
    func rejectsInvalidConfiguration() {
        for threshold in [-0.1, 1.1, .infinity, .nan] {
            #expect(throws: DiffConfigurationError.self) {
                try DiffConfiguration(linePairingThreshold: threshold)
            }
        }
    }

    private func strings(alphabet: [Character], maximumLength: Int) -> [String] {
        var values = [""]
        var frontier = [""]
        for _ in 0..<maximumLength {
            frontier = frontier.flatMap { prefix in
                alphabet.map { prefix + String($0) }
            }
            values += frontier
        }
        return values
    }

    private func unchangedUTF16(
        _ text: String,
        excluding highlights: [TextHighlight]
    ) -> [UInt16] {
        let changedOffsets = Set(highlights.flatMap { highlight in
            highlight.range.location..<NSMaxRange(highlight.range)
        })
        return text.utf16.enumerated().compactMap { offset, codeUnit in
            changedOffsets.contains(offset) ? nil : codeUnit
        }
    }

    private func lcsLength(_ left: [Character], _ right: [Character]) -> Int {
        var previous = Array(repeating: 0, count: right.count + 1)
        for leftCharacter in left {
            var current = Array(repeating: 0, count: right.count + 1)
            for rightIndex in right.indices {
                current[rightIndex + 1] = leftCharacter == right[rightIndex]
                    ? previous[rightIndex] + 1
                    : max(previous[rightIndex + 1], current[rightIndex])
            }
            previous = current
        }
        return previous[right.count]
    }

    private func randomString(using generator: inout SeededGenerator) -> String {
        let alphabet = Array("ab c_🙂")
        let length = Int.random(in: 0...12, using: &generator)
        return String((0..<length).map { _ in
            alphabet.randomElement(using: &generator)!
        })
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

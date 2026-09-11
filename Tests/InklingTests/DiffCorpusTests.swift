import Foundation
import InklingDiff
import Testing
@testable import Inkling

@Suite("Diff corpus")
struct DiffCorpusTests {
    private static let fixtureNames = [
        "a-vs-b",
        "single-character",
        "semantic-phrases",
        "line-insertion",
        "whitespace",
        "unicode",
    ]

    @Test("reports comparison metrics")
    func reportMetrics() throws {
        for fixtureName in Self.fixtureNames {
            let fixture = try loadFixture(named: fixtureName)
            for algorithm in DiffAlgorithm.allCases {
                let start = ContinuousClock.now
                let result = DiffEngine.compare(
                    left: fixture.left,
                    right: fixture.right,
                    ignoreWhitespace: false,
                    algorithm: algorithm
                )
                let duration = start.duration(to: .now)
                validate(result, left: fixture.left, right: fixture.right)
                print(reportLine(
                    fixture: fixtureName,
                    algorithm: algorithm,
                    result: result,
                    duration: duration
                ))
            }

        }
    }

    @Test("semantic prose modes retain distinct coverage")
    func semanticProseCoverage() throws {
        let fixture = try loadFixture(named: "semantic-phrases")
        let character = resultMetrics(
            DiffEngine.compare(
                left: fixture.left,
                right: fixture.right,
                ignoreWhitespace: false,
                algorithm: .character
            )
        )
        let word = resultMetrics(
            DiffEngine.compare(
                left: fixture.left,
                right: fixture.right,
                ignoreWhitespace: false,
                algorithm: .word
            )
        )
        let line = resultMetrics(
            DiffEngine.compare(
                left: fixture.left,
                right: fixture.right,
                ignoreWhitespace: false,
                algorithm: .line
            )
        )

        #expect(character.leftCoverage < word.leftCoverage)
        #expect(word.leftCoverage < line.leftCoverage)
        #expect(character.rightCoverage < word.rightCoverage)
        #expect(word.rightCoverage < line.rightCoverage)
    }

    private func loadFixture(named name: String) throws -> CorpusFixture {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test-files", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let leftURL = root.appendingPathComponent("left.txt")
        let rightURL = root.appendingPathComponent("right.txt")
        return try CorpusFixture(
            leftURL: leftURL,
            rightURL: rightURL,
            left: String(contentsOf: leftURL, encoding: .utf8),
            right: String(contentsOf: rightURL, encoding: .utf8)
        )
    }

    private func validate(_ result: DiffResult, left: String, right: String) {
        for highlight in result.leftHighlights {
            #expect(NSMaxRange(highlight.range) <= left.utf16.count)
        }
        for highlight in result.rightHighlights {
            #expect(NSMaxRange(highlight.range) <= right.utf16.count)
        }
        #expect(result.changes.allSatisfy { $0.hunkID < result.hunks.count })
    }

    private func reportLine(
        fixture: String,
        algorithm: DiffAlgorithm,
        result: DiffResult,
        duration: Duration
    ) -> String {
        let metrics = resultMetrics(result)
        return "CORPUS fixture=\(fixture) algorithm=\(algorithm.rawValue) "
            + "left_coverage=\(metrics.leftCoverage) "
            + "right_coverage=\(metrics.rightCoverage) "
            + "left_spans=\(metrics.leftSpans) "
            + "right_spans=\(metrics.rightSpans) "
            + "character_spans=\(metrics.characterSpans) "
            + "word_spans=\(metrics.wordSpans) "
            + "phrase_spans=\(metrics.phraseSpans) "
            + "paired_hunks=\(metrics.pairedHunks) "
            + "changes=\(result.changes.count) hunks=\(result.hunks.count) "
            + "duration_us=\(microseconds(duration))"
    }

    private func resultMetrics(_ result: DiffResult) -> CorpusMetrics {
        let leftRanges = mergedRanges(result.leftHighlights.map(\.range))
        let rightRanges = mergedRanges(result.rightHighlights.map(\.range))
        return CorpusMetrics(
            leftCoverage: leftRanges.reduce(0) { $0 + $1.length },
            rightCoverage: rightRanges.reduce(0) { $0 + $1.length },
            leftSpans: leftRanges.count,
            rightSpans: rightRanges.count,
            characterSpans: categoryCount(.character, in: result),
            wordSpans: categoryCount(.word, in: result),
            phraseSpans: categoryCount(.phrase, in: result),
            pairedHunks: result.hunks.count {
                !$0.leftRange.isEmpty && !$0.rightRange.isEmpty
            }
        )
    }

    private func categoryCount(_ category: ChangeCategory, in result: DiffResult) -> Int {
        (result.leftHighlights + result.rightHighlights).count {
            $0.kind.category == category
        }
    }

    private func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: {
            $0.location < $1.location
                || ($0.location == $1.location && $0.length < $1.length)
        }) {
            guard let last = merged.last, range.location <= NSMaxRange(last) else {
                merged.append(range)
                continue
            }
            merged[merged.count - 1].length = max(
                NSMaxRange(last),
                NSMaxRange(range)
            ) - last.location
        }
        return merged
    }

    private func microseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000_000
            + Int64(components.attoseconds / 1_000_000_000_000)
    }
}

private struct CorpusFixture {
    let leftURL: URL
    let rightURL: URL
    let left: String
    let right: String
}

private struct CorpusMetrics {
    let leftCoverage: Int
    let rightCoverage: Int
    let leftSpans: Int
    let rightSpans: Int
    let characterSpans: Int
    let wordSpans: Int
    let phraseSpans: Int
    let pairedHunks: Int
}

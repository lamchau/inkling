import Foundation

/// Controls how aggressively changed lines are paired for inline refinement.
public struct DiffConfiguration: Equatable, Sendable {
    public static let `default` = DiffConfiguration(validatedLinePairingThreshold: 0.5)

    /// The minimum similarity required to pair two changed lines.
    public let linePairingThreshold: Double

    /// Creates a configuration with a finite threshold between zero and one.
    public init(linePairingThreshold: Double = 0.5) throws {
        guard linePairingThreshold.isFinite,
              (0...1).contains(linePairingThreshold)
        else {
            throw DiffConfigurationError.invalidLinePairingThreshold(
                linePairingThreshold
            )
        }
        self.linePairingThreshold = linePairingThreshold
    }

    private init(validatedLinePairingThreshold linePairingThreshold: Double) {
        self.linePairingThreshold = linePairingThreshold
    }
}

public enum DiffConfigurationError: Error, Equatable, Sendable {
    case invalidLinePairingThreshold(Double)
}

/// Computes deterministic, UTF-16-addressed differences between two strings.
public enum DiffEngine {
    private static let matrixCellLimit = 1_000_000
    private static let alignmentCellBudget = 8_000_000
    private static let wordPairingThreshold = 0.5
    private static let editCost = 2
    private static let gapOpeningCost = 1

    /// Compares two strings using the requested display strategy.
    public static func compare(
        left leftText: String,
        right rightText: String,
        ignoreWhitespace: Bool,
        strategy: DiffStrategy = .semantic,
        configuration: DiffConfiguration = .default
    ) -> DiffResult {
        var context = ComparisonContext(
            matrixCellLimit: matrixCellLimit,
            initialCellBudget: alignmentCellBudget,
            remainingCells: alignmentCellBudget
        )
        let left = TextLines(leftText)
        let right = TextLines(rightText)
        let leftKeys = left.lines.map { normalized($0, ignoreWhitespace: ignoreWhitespace) }
        let rightKeys = right.lines.map { normalized($0, ignoreWhitespace: ignoreWhitespace) }
        let matches = orderedMatches(leftKeys, rightKeys, context: &context)

        var leftHighlights: [TextHighlight] = []
        var rightHighlights: [TextHighlight] = []
        var hunks: [DiffHunk] = []
        var changes: [DiffChange] = []
        var previousLeft = 0
        var previousRight = 0
        var nextPairColor = 0

        for matchIndex in 0...matches.count {
            let match = matchIndex < matches.count ? matches[matchIndex] : nil
            let leftEnd = match?.left ?? left.lines.count
            let rightEnd = match?.right ?? right.lines.count

            if previousLeft < leftEnd || previousRight < rightEnd {
                let hunkID = hunks.count
                let leftRange = previousLeft..<leftEnd
                let rightRange = previousRight..<rightEnd
                let leftHighlightStart = leftHighlights.count
                let rightHighlightStart = rightHighlights.count
                let pairs = pairLines(
                    left: Array(left.lines[leftRange]),
                    right: Array(right.lines[rightRange]),
                    ignoreWhitespace: ignoreWhitespace,
                    pairingThreshold: configuration.linePairingThreshold,
                    context: &context
                )
                var pairedLeft = Set<Int>()
                var pairedRight = Set<Int>()

                for pair in pairs {
                    let leftLineIndex = leftRange.lowerBound + pair.left
                    let rightLineIndex = rightRange.lowerBound + pair.right
                    pairedLeft.insert(leftLineIndex)
                    pairedRight.insert(rightLineIndex)
                    let color = nextPairColor % 6
                    nextPairColor += 1
                    let pairLeftHighlights = characterHighlights(
                        source: left.lines[leftLineIndex],
                        other: right.lines[rightLineIndex],
                        lineOffset: left.offsets[leftLineIndex],
                        color: color,
                        strategy: strategy,
                        ignoreWhitespace: ignoreWhitespace,
                        context: &context
                    )
                    let pairRightHighlights = characterHighlights(
                        source: right.lines[rightLineIndex],
                        other: left.lines[leftLineIndex],
                        lineOffset: right.offsets[rightLineIndex],
                        color: color,
                        strategy: strategy,
                        ignoreWhitespace: ignoreWhitespace,
                        context: &context
                    )
                    leftHighlights += pairLeftHighlights
                    rightHighlights += pairRightHighlights
                    changes += makeChanges(
                        leftHighlights: pairLeftHighlights,
                        rightHighlights: pairRightHighlights,
                        hunkID: hunkID,
                        leftFallback: left.offsets[leftLineIndex],
                        rightFallback: right.offsets[rightLineIndex]
                    )
                }

                for lineIndex in leftRange where !pairedLeft.contains(lineIndex) {
                    if !ignoreWhitespace || !leftKeys[lineIndex].isEmpty {
                        let highlight = fullLineHighlight(
                            line: left.lines[lineIndex],
                            offset: left.offsets[lineIndex],
                            documentLength: leftText.utf16.count,
                            kind: .deletion
                        )
                        leftHighlights.append(highlight)
                        changes += makeChanges(
                            leftHighlights: [highlight],
                            rightHighlights: [],
                            hunkID: hunkID,
                            leftFallback: left.offsets[lineIndex],
                            rightFallback: right.offset(at: rightRange.lowerBound)
                        )
                    }
                }
                for lineIndex in rightRange where !pairedRight.contains(lineIndex) {
                    if !ignoreWhitespace || !rightKeys[lineIndex].isEmpty {
                        let highlight = fullLineHighlight(
                            line: right.lines[lineIndex],
                            offset: right.offsets[lineIndex],
                            documentLength: rightText.utf16.count,
                            kind: .addition
                        )
                        rightHighlights.append(highlight)
                        changes += makeChanges(
                            leftHighlights: [],
                            rightHighlights: [highlight],
                            hunkID: hunkID,
                            leftFallback: left.offset(at: leftRange.lowerBound),
                            rightFallback: right.offsets[lineIndex]
                        )
                    }
                }

                if leftHighlights.count > leftHighlightStart
                    || rightHighlights.count > rightHighlightStart {
                    hunks.append(DiffHunk(
                        id: hunkID,
                        leftRange: leftRange,
                        rightRange: rightRange,
                        leftNavigationOffset: left.offset(at: leftRange.lowerBound),
                        rightNavigationOffset: right.offset(at: rightRange.lowerBound)
                    ))
                }
            }

            if let match {
                previousLeft = match.left + 1
                previousRight = match.right + 1
            }
        }

        let orderedChanges = changes
            .sorted {
                if $0.hunkID != $1.hunkID {
                    return $0.hunkID < $1.hunkID
                }
                return min($0.leftNavigationOffset, $0.rightNavigationOffset)
                    < min($1.leftNavigationOffset, $1.rightNavigationOffset)
            }
            .enumerated()
            .map { index, change in
                DiffChange(
                    id: index,
                    hunkID: change.hunkID,
                    leftRange: change.leftRange,
                    rightRange: change.rightRange,
                    leftNavigationOffset: change.leftNavigationOffset,
                    rightNavigationOffset: change.rightNavigationOffset
                )
            }
        return DiffResult(
            leftHighlights: leftHighlights.filter { $0.range.length > 0 },
            rightHighlights: rightHighlights.filter { $0.range.length > 0 },
            hunks: hunks,
            changes: orderedChanges,
            diagnostics: context.diagnostics
        )
    }

    private static func makeChanges(
        leftHighlights: [TextHighlight],
        rightHighlights: [TextHighlight],
        hunkID: Int,
        leftFallback: Int,
        rightFallback: Int
    ) -> [DiffChange] {
        let leftRanges = topLevelRanges(in: leftHighlights)
        let rightRanges = topLevelRanges(in: rightHighlights)
        let count = max(leftRanges.count, rightRanges.count)
        return (0..<count).map { index in
            let leftRange = leftRanges.indices.contains(index) ? leftRanges[index] : nil
            let rightRange = rightRanges.indices.contains(index) ? rightRanges[index] : nil
            return DiffChange(
                id: 0,
                hunkID: hunkID,
                leftRange: leftRange,
                rightRange: rightRange,
                leftNavigationOffset: leftRange?.location ?? leftFallback,
                rightNavigationOffset: rightRange?.location ?? rightFallback
            )
        }
    }

    private static func topLevelRanges(in highlights: [TextHighlight]) -> [NSRange] {
        let ranges = highlights.reduce(into: [NSRange]()) { ranges, highlight in
            if !ranges.contains(highlight.range) {
                ranges.append(highlight.range)
            }
        }
        return ranges
            .filter { candidate in
                !ranges.contains {
                    $0 != candidate
                        && NSLocationInRange(candidate.location, $0)
                        && NSMaxRange(candidate) <= NSMaxRange($0)
                }
            }
            .sorted { $0.location < $1.location }
    }

    private static func normalized(_ line: String, ignoreWhitespace: Bool) -> String {
        guard ignoreWhitespace else { return line }
        return line.filter { !$0.isWhitespace }
    }

    private static func orderedMatches(
        _ left: [String],
        _ right: [String],
        context: inout ComparisonContext
    ) -> [Match] {
        return boundedMatches(
            left,
            right,
            leftRange: left.indices,
            rightRange: right.indices,
            context: &context
        )
    }

    private static func boundedMatches(
        _ left: [String],
        _ right: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        context: inout ComparisonContext
    ) -> [Match] {
        guard !leftRange.isEmpty, !rightRange.isEmpty else { return [] }

        var leftStart = leftRange.lowerBound
        var rightStart = rightRange.lowerBound
        var prefix: [Match] = []
        while leftStart < leftRange.upperBound,
              rightStart < rightRange.upperBound,
              left[leftStart] == right[rightStart]
        {
            prefix.append(Match(left: leftStart, right: rightStart))
            leftStart += 1
            rightStart += 1
        }

        var leftEnd = leftRange.upperBound
        var rightEnd = rightRange.upperBound
        var suffix: [Match] = []
        while leftEnd > leftStart,
              rightEnd > rightStart,
              left[leftEnd - 1] == right[rightEnd - 1]
        {
            leftEnd -= 1
            rightEnd -= 1
            suffix.append(Match(left: leftEnd, right: rightEnd))
        }

        let coreLeft = leftStart..<leftEnd
        let coreRight = rightStart..<rightEnd
        guard !coreLeft.isEmpty, !coreRight.isEmpty else {
            return prefix + suffix.reversed()
        }

        let cellCount = boundedCellCount(coreLeft.count, coreRight.count)
        if let cellCount,
           cellCount <= context.matrixCellLimit,
           cellCount <= context.remainingCells
        {
            context.remainingCells -= cellCount
            return prefix
                + matrixMatches(
                    left,
                    right,
                    leftRange: coreLeft,
                    rightRange: coreRight
                )
                + suffix.reversed()
        }

        let anchors = patienceAnchors(
            left,
            right,
            leftRange: coreLeft,
            rightRange: coreRight
        )
        if !anchors.isEmpty {
            context.usedPatienceAnchors = true
            var matches = prefix
            var nextLeft = coreLeft.lowerBound
            var nextRight = coreRight.lowerBound
            for anchor in anchors {
                matches += boundedMatches(
                    left,
                    right,
                    leftRange: nextLeft..<anchor.left,
                    rightRange: nextRight..<anchor.right,
                    context: &context
                )
                matches.append(anchor)
                nextLeft = anchor.left + 1
                nextRight = anchor.right + 1
            }
            matches += boundedMatches(
                left,
                right,
                leftRange: nextLeft..<coreLeft.upperBound,
                rightRange: nextRight..<coreRight.upperBound,
                context: &context
            )
            return matches + suffix.reversed()
        }

        if let cellCount, cellCount <= context.remainingCells {
            context.remainingCells -= cellCount
            context.usedLinearSpaceAlignment = true
            return prefix
                + linearSpaceMatches(
                    left,
                    right,
                    leftRange: coreLeft,
                    rightRange: coreRight
                )
                + suffix.reversed()
        }

        context.exhaustedWorkBudget = true
        return prefix + suffix.reversed()
    }

    private static func matrixMatches(
        _ left: [String],
        _ right: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) -> [Match] {
        let leftCount = leftRange.count
        let rightCount = rightRange.count

        var lengths = Array(
            repeating: Array(repeating: 0, count: rightCount + 1),
            count: leftCount + 1
        )
        for leftIndex in 1...leftCount {
            for rightIndex in 1...rightCount {
                if left[leftRange.lowerBound + leftIndex - 1]
                    == right[rightRange.lowerBound + rightIndex - 1]
                {
                    lengths[leftIndex][rightIndex] = lengths[leftIndex - 1][rightIndex - 1] + 1
                } else {
                    lengths[leftIndex][rightIndex] = max(
                        lengths[leftIndex - 1][rightIndex],
                        lengths[leftIndex][rightIndex - 1]
                    )
                }
            }
        }

        var matches: [Match] = []
        var leftIndex = leftCount
        var rightIndex = rightCount
        while leftIndex > 0, rightIndex > 0 {
            if left[leftRange.lowerBound + leftIndex - 1]
                == right[rightRange.lowerBound + rightIndex - 1]
            {
                matches.append(Match(
                    left: leftRange.lowerBound + leftIndex - 1,
                    right: rightRange.lowerBound + rightIndex - 1
                ))
                leftIndex -= 1
                rightIndex -= 1
            } else if lengths[leftIndex - 1][rightIndex] >= lengths[leftIndex][rightIndex - 1] {
                leftIndex -= 1
            } else {
                rightIndex -= 1
            }
        }
        return matches.reversed()
    }

    private static func linearSpaceMatches(
        _ left: [String],
        _ right: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) -> [Match] {
        guard !leftRange.isEmpty, !rightRange.isEmpty else { return [] }
        if leftRange.count == 1 {
            guard let rightIndex = rightRange.first(where: {
                right[$0] == left[leftRange.lowerBound]
            }) else {
                return []
            }
            return [Match(left: leftRange.lowerBound, right: rightIndex)]
        }

        let leftMiddle = leftRange.lowerBound + leftRange.count / 2
        let forward = lcsLengths(
            left,
            right,
            leftRange: leftRange.lowerBound..<leftMiddle,
            rightRange: rightRange,
            reversed: false
        )
        let backward = lcsLengths(
            left,
            right,
            leftRange: leftMiddle..<leftRange.upperBound,
            rightRange: rightRange,
            reversed: true
        )
        var rightSplitOffset = 0
        var bestLength = -1
        for offset in 0...rightRange.count {
            let length = forward[offset] + backward[rightRange.count - offset]
            if length > bestLength {
                bestLength = length
                rightSplitOffset = offset
            }
        }
        let rightMiddle = rightRange.lowerBound + rightSplitOffset
        return linearSpaceMatches(
            left,
            right,
            leftRange: leftRange.lowerBound..<leftMiddle,
            rightRange: rightRange.lowerBound..<rightMiddle
        ) + linearSpaceMatches(
            left,
            right,
            leftRange: leftMiddle..<leftRange.upperBound,
            rightRange: rightMiddle..<rightRange.upperBound
        )
    }

    private static func lcsLengths(
        _ left: [String],
        _ right: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        reversed: Bool
    ) -> [Int] {
        var previous = Array(repeating: 0, count: rightRange.count + 1)
        var current = previous
        for leftOffset in 0..<leftRange.count {
            current[0] = 0
            let leftIndex = reversed
                ? leftRange.upperBound - leftOffset - 1
                : leftRange.lowerBound + leftOffset
            for rightOffset in 1...rightRange.count {
                let rightIndex = reversed
                    ? rightRange.upperBound - rightOffset
                    : rightRange.lowerBound + rightOffset - 1
                if left[leftIndex] == right[rightIndex] {
                    current[rightOffset] = previous[rightOffset - 1] + 1
                } else {
                    current[rightOffset] = max(
                        previous[rightOffset],
                        current[rightOffset - 1]
                    )
                }
            }
            swap(&previous, &current)
        }
        return previous
    }

    private static func patienceAnchors(
        _ left: [String],
        _ right: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) -> [Match] {
        var leftOccurrences: [String: [Int]] = [:]
        var rightOccurrences: [String: [Int]] = [:]
        for index in leftRange {
            leftOccurrences[left[index], default: []].append(index)
        }
        for index in rightRange {
            rightOccurrences[right[index], default: []].append(index)
        }
        let candidates = leftOccurrences.compactMap { value, leftIndices -> Match? in
            guard leftIndices.count == 1,
                  let rightIndices = rightOccurrences[value],
                  rightIndices.count == 1
            else {
                return nil
            }
            return Match(left: leftIndices[0], right: rightIndices[0])
        }
        .sorted { $0.left < $1.left }
        guard !candidates.isEmpty else { return [] }

        var tailRightIndices: [Int] = []
        var tailCandidateIndices: [Int] = []
        var predecessors = Array(repeating: -1, count: candidates.count)
        for (candidateIndex, candidate) in candidates.enumerated() {
            var lower = 0
            var upper = tailRightIndices.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if tailRightIndices[middle] < candidate.right {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            if lower > 0 {
                predecessors[candidateIndex] = tailCandidateIndices[lower - 1]
            }
            if lower == tailRightIndices.count {
                tailRightIndices.append(candidate.right)
                tailCandidateIndices.append(candidateIndex)
            } else {
                tailRightIndices[lower] = candidate.right
                tailCandidateIndices[lower] = candidateIndex
            }
        }

        var anchors: [Match] = []
        var candidateIndex = tailCandidateIndices.last ?? -1
        while candidateIndex >= 0 {
            anchors.append(candidates[candidateIndex])
            candidateIndex = predecessors[candidateIndex]
        }
        return anchors.reversed()
    }

    private static func boundedCellCount(_ leftCount: Int, _ rightCount: Int) -> Int? {
        guard leftCount > 0, rightCount <= Int.max / leftCount else { return nil }
        return leftCount * rightCount
    }

    private static func pairLines(
        left: [String],
        right: [String],
        ignoreWhitespace: Bool,
        pairingThreshold: Double,
        context: inout ComparisonContext
    ) -> [ScoredMatch] {
        guard !left.isEmpty, !right.isEmpty else { return [] }
        guard fitsMatrix(left.count, right.count, limit: context.matrixCellLimit) else {
            context.usedPositionalFallback = true
            return zip(left.indices, right.indices).map { leftIndex, rightIndex in
                ScoredMatch(left: leftIndex, right: rightIndex)
            }
        }

        let preferredPairs = similarPairs(
            left.map { normalized($0, ignoreWhitespace: ignoreWhitespace) },
            right.map { normalized($0, ignoreWhitespace: ignoreWhitespace) },
            threshold: pairingThreshold,
            context: &context
        )
        return fillUnpairedLines(
            in: preferredPairs,
            leftCount: left.count,
            rightCount: right.count
        )
    }

    private static func similarPairs(
        _ left: [String],
        _ right: [String],
        threshold: Double,
        context: inout ComparisonContext
    ) -> [ScoredMatch] {
        guard !left.isEmpty, !right.isEmpty else { return [] }
        guard fitsMatrix(left.count, right.count, limit: context.matrixCellLimit) else {
            context.usedPositionalFallback = true
            return zip(left.indices, right.indices).compactMap { leftIndex, rightIndex in
                similarity(left[leftIndex], right[rightIndex], context: &context) >= threshold
                    ? ScoredMatch(left: leftIndex, right: rightIndex)
                    : nil
            }
        }

        var cells = Array(
            repeating: Array(repeating: PairCell(), count: right.count + 1),
            count: left.count + 1
        )
        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                var best = cells[leftIndex - 1][rightIndex]
                best.choice = .left
                let skipRight = cells[leftIndex][rightIndex - 1]
                if isBetter(skipRight, than: best) {
                    best = skipRight
                    best.choice = .right
                }

                let score = similarity(
                    left[leftIndex - 1],
                    right[rightIndex - 1],
                    context: &context
                )
                if score >= threshold {
                    var paired = cells[leftIndex - 1][rightIndex - 1]
                    paired.score += score
                    paired.count += 1
                    paired.choice = .pair
                    if isBetter(paired, than: best) {
                        best = paired
                    }
                }
                cells[leftIndex][rightIndex] = best
            }
        }

        var pairs: [ScoredMatch] = []
        var leftIndex = left.count
        var rightIndex = right.count
        while leftIndex > 0, rightIndex > 0 {
            switch cells[leftIndex][rightIndex].choice {
            case .pair:
                pairs.append(ScoredMatch(
                    left: leftIndex - 1,
                    right: rightIndex - 1
                ))
                leftIndex -= 1
                rightIndex -= 1
            case .left:
                leftIndex -= 1
            case .right:
                rightIndex -= 1
            case .none:
                leftIndex = 0
                rightIndex = 0
            }
        }
        return pairs.reversed()
    }

    private static func fillUnpairedLines(
        in preferredPairs: [ScoredMatch],
        leftCount: Int,
        rightCount: Int
    ) -> [ScoredMatch] {
        var pairs: [ScoredMatch] = []
        var nextLeft = 0
        var nextRight = 0

        for preferred in preferredPairs {
            pairs += zip(nextLeft..<preferred.left, nextRight..<preferred.right).map {
                ScoredMatch(left: $0.0, right: $0.1)
            }
            pairs.append(preferred)
            nextLeft = preferred.left + 1
            nextRight = preferred.right + 1
        }

        pairs += zip(nextLeft..<leftCount, nextRight..<rightCount).map {
            ScoredMatch(left: $0.0, right: $0.1)
        }
        return pairs
    }

    private static func isBetter(_ candidate: PairCell, than current: PairCell) -> Bool {
        candidate.score > current.score + 0.000_000_000_001
            || (abs(candidate.score - current.score) <= 0.000_000_000_001
                && candidate.count > current.count)
    }

    private static func similarity(
        _ left: String,
        _ right: String,
        context: inout ComparisonContext
    ) -> Double {
        if left == right { return 1 }
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        guard !leftCharacters.isEmpty, !rightCharacters.isEmpty else { return 0 }
        guard fitsMatrix(
            leftCharacters.count,
            rightCharacters.count,
            limit: context.matrixCellLimit
        ) else {
            context.usedPrefixSimilarityFallback = true
            let sharedPrefix = zip(leftCharacters, rightCharacters).prefix { $0 == $1 }.count
            return (2 * Double(sharedPrefix)) / Double(leftCharacters.count + rightCharacters.count)
        }
        let matches = orderedMatches(
            leftCharacters.map(String.init),
            rightCharacters.map(String.init),
            context: &context
        ).count
        return (2 * Double(matches)) / Double(leftCharacters.count + rightCharacters.count)
    }

    private static func characterHighlights(
        source: String,
        other: String,
        lineOffset: Int,
        color: Int,
        strategy: DiffStrategy,
        ignoreWhitespace: Bool,
        context: inout ComparisonContext
    ) -> [TextHighlight] {
        let ranges: [ClassifiedRange]
        switch strategy {
        case .semantic:
            ranges = semanticChangedRanges(
                source: source,
                other: other,
                ignoreWhitespace: ignoreWhitespace,
                context: &context
            )
        case .word:
            ranges = tokenChangedRanges(
                source: source,
                other: other,
                ignoreWhitespace: ignoreWhitespace,
                context: &context
            )
        case .character:
            ranges = changedCharacterRanges(
                source: source,
                other: other,
                offset: 0,
                context: &context
            )
                .map { ClassifiedRange(range: $0, category: .character) }
        case .line:
            ranges = [
                ClassifiedRange(
                    range: NSRange(location: 0, length: source.utf16.count),
                    category: .phrase
                ),
            ]
        }

        return ranges.map {
            TextHighlight(
                range: NSRange(
                    location: lineOffset + $0.range.location,
                    length: $0.range.length
                ),
                kind: highlightKind(for: $0.category, color: color)
            )
        }
    }

    private static func semanticChangedRanges(
        source: String,
        other: String,
        ignoreWhitespace: Bool,
        context: inout ComparisonContext
    ) -> [ClassifiedRange] {
        let sourceTokens = tokens(in: source, ignoreWhitespace: ignoreWhitespace)
        let otherTokens = tokens(in: other, ignoreWhitespace: ignoreWhitespace)
        let matches = wordMatches(sourceTokens, otherTokens, context: &context)

        var ranges: [ClassifiedRange] = []
        var sourceStart = 0
        var otherStart = 0
        for matchIndex in 0...matches.count {
            let match = matchIndex < matches.count ? matches[matchIndex] : nil
            let sourceEnd = match?.left ?? sourceTokens.count
            let otherEnd = match?.right ?? otherTokens.count
            ranges += changedTokenRanges(
                source: sourceTokens,
                other: otherTokens,
                sourceRange: sourceStart..<sourceEnd,
                otherRange: otherStart..<otherEnd,
                context: &context
            )

            if let match {
                sourceStart = match.left + 1
                otherStart = match.right + 1
            }
        }
        return mergeClassified(ranges)
    }

    private static func changedTokenRanges(
        source: [DiffToken],
        other: [DiffToken],
        sourceRange: Range<Int>,
        otherRange: Range<Int>,
        context: inout ComparisonContext
    ) -> [ClassifiedRange] {
        let sourceWords = sourceRange.filter { source[$0].kind == .word }
        let otherWords = otherRange.filter { other[$0].kind == .word }
        let wordPairs = similarPairs(
            sourceWords.map { source[$0].text },
            otherWords.map { other[$0].text },
            threshold: wordPairingThreshold,
            context: &context
        )
        var pairedSource = Set<Int>()
        var ranges: [ClassifiedRange] = []

        for pair in wordPairs {
            let sourceIndex = sourceWords[pair.left]
            let otherIndex = otherWords[pair.right]
            pairedSource.insert(sourceIndex)
            ranges.append(ClassifiedRange(
                range: source[sourceIndex].range,
                category: .word
            ))
            ranges += changedCharacterRanges(
                source: source[sourceIndex].text,
                other: other[otherIndex].text,
                offset: source[sourceIndex].range.location,
                context: &context
            ).map { ClassifiedRange(range: $0, category: .character) }
        }

        let sourceNonWords = sourceRange.filter { source[$0].kind != .word }
        let otherNonWords = otherRange.filter { other[$0].kind != .word }
        for match in orderedMatches(
            sourceNonWords.map { source[$0].key },
            otherNonWords.map { other[$0].key },
            context: &context
        ) {
            pairedSource.insert(sourceNonWords[match.left])
        }

        let unpairedWordCount = sourceWords.count {
            !pairedSource.contains($0)
        }
        for index in sourceRange where !pairedSource.contains(index) {
            let category: ChangeCategory
            if source[index].kind == .word {
                category = unpairedWordCount > 1 ? .phrase : .word
            } else {
                category = .phrase
            }
            ranges.append(ClassifiedRange(
                range: source[index].range,
                category: category
            ))
        }
        return ranges
    }

    private static func tokenChangedRanges(
        source: String,
        other: String,
        ignoreWhitespace: Bool,
        context: inout ComparisonContext
    ) -> [ClassifiedRange] {
        let sourceTokens = tokens(in: source, ignoreWhitespace: ignoreWhitespace)
        let otherTokens = tokens(in: other, ignoreWhitespace: ignoreWhitespace)
        let matches = wordMatches(sourceTokens, otherTokens, context: &context)

        var ranges: [ClassifiedRange] = []
        var sourceStart = 0
        var otherStart = 0
        for matchIndex in 0...matches.count {
            let match = matchIndex < matches.count ? matches[matchIndex] : nil
            let sourceEnd = match?.left ?? sourceTokens.count
            let otherEnd = match?.right ?? otherTokens.count
            ranges += unmatchedTokenRanges(
                source: sourceTokens,
                other: otherTokens,
                sourceRange: sourceStart..<sourceEnd,
                otherRange: otherStart..<otherEnd,
                context: &context
            )

            if let match {
                sourceStart = match.left + 1
                otherStart = match.right + 1
            }
        }
        return mergeClassified(ranges)
    }

    private static func unmatchedTokenRanges(
        source: [DiffToken],
        other: [DiffToken],
        sourceRange: Range<Int>,
        otherRange: Range<Int>,
        context: inout ComparisonContext
    ) -> [ClassifiedRange] {
        let sourceNonWords = sourceRange.filter { source[$0].kind != .word }
        let otherNonWords = otherRange.filter { other[$0].kind != .word }
        let matchedSource = Set(orderedMatches(
            sourceNonWords.map { source[$0].key },
            otherNonWords.map { other[$0].key },
            context: &context
        ).map { sourceNonWords[$0.left] })

        return sourceRange
            .filter { !matchedSource.contains($0) }
            .map {
                ClassifiedRange(
                    range: source[$0].range,
                    category: source[$0].kind == .word ? .word : .phrase
                )
            }
    }

    private static func highlightKind(
        for category: ChangeCategory,
        color: Int
    ) -> HighlightKind {
        switch category {
        case .character: .character(color)
        case .word: .word(color)
        case .phrase: .phrase(color)
        case .addition: .addition
        case .deletion: .deletion
        }
    }

    private static func wordMatches(
        _ source: [DiffToken],
        _ other: [DiffToken],
        context: inout ComparisonContext
    ) -> [Match] {
        groupedMatches(
            source.map(\.key),
            other.map(\.key),
            context: &context
        ).compactMap {
            guard source[$0.left].kind == .word else { return nil }
            return $0
        }
    }

    private static func mergeClassified(_ ranges: [ClassifiedRange]) -> [ClassifiedRange] {
        var merged: [ClassifiedRange] = []
        for item in ranges.sorted(by: { $0.range.location < $1.range.location }) {
            if let last = merged.last,
               last.category == item.category,
               NSMaxRange(last.range) == item.range.location
            {
                merged[merged.count - 1].range.length += item.range.length
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    private static func changedCharacterRanges(
        source: String,
        other: String,
        offset: Int,
        context: inout ComparisonContext
    ) -> [NSRange] {
        let sourceUnits = characterUnits(source, ignoreWhitespace: false)
        let otherUnits = characterUnits(other, ignoreWhitespace: false)
        let matches = groupedMatches(
            sourceUnits.map(\.value),
            otherUnits.map(\.value),
            context: &context
        )
        let matchedSource = Set(matches.map(\.left))
        return sourceUnits.indices
            .filter { !matchedSource.contains($0) }
            .map {
                NSRange(
                    location: offset + sourceUnits[$0].range.location,
                    length: sourceUnits[$0].range.length
                )
            }
    }

    private static func tokens(in value: String, ignoreWhitespace: Bool) -> [DiffToken] {
        var tokens: [DiffToken] = []
        var utf16Offset = 0

        for character in value {
            let text = String(character)
            let length = text.utf16.count
            let kind = tokenKind(character)
            defer { utf16Offset += length }
            if ignoreWhitespace, kind == .whitespace {
                continue
            }

            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1].text += text
                tokens[tokens.count - 1].range.length += length
            } else {
                tokens.append(DiffToken(
                    kind: kind,
                    text: text,
                    range: NSRange(location: utf16Offset, length: length)
                ))
            }
        }
        return tokens
    }

    private static func tokenKind(_ character: Character) -> TokenKind {
        if character.isWhitespace {
            return .whitespace
        }
        if character.unicodeScalars.allSatisfy({
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
        }) {
            return .punctuation
        }
        return .word
    }

    private static func characterUnits(
        _ value: String,
        ignoreWhitespace: Bool
    ) -> [(value: String, range: NSRange)] {
        var units: [(String, NSRange)] = []
        var utf16Offset = 0
        for character in value {
            let text = String(character)
            let length = text.utf16.count
            if !ignoreWhitespace || !character.isWhitespace {
                units.append((text, NSRange(location: utf16Offset, length: length)))
            }
            utf16Offset += length
        }
        return units
    }

    private static func fullLineHighlight(
        line: String,
        offset: Int,
        documentLength: Int,
        kind: HighlightKind
    ) -> TextHighlight {
        let range: NSRange
        if !line.isEmpty {
            range = NSRange(location: offset, length: line.utf16.count)
        } else if offset < documentLength {
            range = NSRange(location: offset, length: 1)
        } else if offset > 0 {
            range = NSRange(location: offset - 1, length: 1)
        } else {
            range = NSRange(location: 0, length: 0)
        }
        return TextHighlight(
            range: range,
            kind: kind
        )
    }

    private static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: {
            $0.location < $1.location
                || ($0.location == $1.location && $0.length < $1.length)
        }) {
            if let last = merged.last, NSMaxRange(last) == range.location {
                merged[merged.count - 1].length += range.length
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func groupedMatches(
        _ left: [String],
        _ right: [String],
        context: inout ComparisonContext
    ) -> [Match] {
        if right.lexicographicallyPrecedes(left) {
            return groupedMatchesInCanonicalOrder(right, left, context: &context).map {
                Match(left: $0.right, right: $0.left)
            }
        }
        return groupedMatchesInCanonicalOrder(left, right, context: &context)
    }

    private static func groupedMatchesInCanonicalOrder(
        _ left: [String],
        _ right: [String],
        context: inout ComparisonContext
    ) -> [Match] {
        guard !left.isEmpty, !right.isEmpty else { return [] }
        guard fitsMatrix(left.count, right.count, limit: context.matrixCellLimit) else {
            return orderedMatches(left, right, context: &context)
        }

        var cells = Array(
            repeating: Array(repeating: EditCell(), count: right.count + 1),
            count: left.count + 1
        )
        for leftIndex in 1...left.count {
            cells[leftIndex][0] = EditCell(
                cost: leftIndex * editCost + gapOpeningCost,
                operation: .deletion
            )
        }
        for rightIndex in 1...right.count {
            cells[0][rightIndex] = EditCell(
                cost: rightIndex * editCost + gapOpeningCost,
                operation: .insertion
            )
        }

        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                let deletion = EditCell(
                    cost: mismatchCost(
                        from: cells[leftIndex - 1][rightIndex],
                        baseCost: editCost
                    ),
                    operation: .deletion
                )
                let insertion = EditCell(
                    cost: mismatchCost(
                        from: cells[leftIndex][rightIndex - 1],
                        baseCost: editCost
                    ),
                    operation: .insertion
                )
                var best = insertion.cost <= deletion.cost ? insertion : deletion
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    let match = EditCell(
                        cost: cells[leftIndex - 1][rightIndex - 1].cost,
                        operation: .match
                    )
                    if match.cost < best.cost {
                        best = match
                    }
                }
                cells[leftIndex][rightIndex] = best
            }
        }

        var matches: [Match] = []
        var leftIndex = left.count
        var rightIndex = right.count
        while leftIndex > 0 || rightIndex > 0 {
            switch cells[leftIndex][rightIndex].operation {
            case .match:
                matches.append(Match(left: leftIndex - 1, right: rightIndex - 1))
                leftIndex -= 1
                rightIndex -= 1
            case .deletion:
                leftIndex -= 1
            case .insertion:
                rightIndex -= 1
            case .none:
                leftIndex = 0
                rightIndex = 0
            }
        }
        return matches.reversed()
    }

    private static func mismatchCost(from cell: EditCell, baseCost: Int) -> Int {
        let opensGap = cell.operation == .match || cell.operation == .none
        return cell.cost + baseCost + (opensGap ? gapOpeningCost : 0)
    }

    private static func fitsMatrix(
        _ leftCount: Int,
        _ rightCount: Int,
        limit: Int
    ) -> Bool {
        boundedCellCount(leftCount, rightCount).map { $0 <= limit } == true
    }
}

private struct ComparisonContext {
    let matrixCellLimit: Int
    let initialCellBudget: Int
    var remainingCells: Int
    var usedPatienceAnchors = false
    var usedLinearSpaceAlignment = false
    var usedPositionalFallback = false
    var usedPrefixSimilarityFallback = false
    var exhaustedWorkBudget = false

    var diagnostics: DiffDiagnostics {
        let bounded = exhaustedWorkBudget
            || usedPositionalFallback
            || usedPrefixSimilarityFallback
        return DiffDiagnostics(
            quality: bounded ? .bounded : (usedPatienceAnchors ? .anchored : .exact),
            usedPatienceAnchors: usedPatienceAnchors,
            usedLinearSpaceAlignment: usedLinearSpaceAlignment,
            exhaustedWorkBudget: exhaustedWorkBudget,
            usedPositionalFallback: usedPositionalFallback,
            usedPrefixSimilarityFallback: usedPrefixSimilarityFallback,
            exactMatrixCellLimit: matrixCellLimit,
            workCellBudget: initialCellBudget
        )
    }
}

private struct TextLines {
    let lines: [String]
    let offsets: [Int]

    init(_ text: String) {
        lines = text.components(separatedBy: "\n")
        var nextOffset = 0
        var computedOffsets: [Int] = []
        for line in lines {
            computedOffsets.append(nextOffset)
            nextOffset += line.utf16.count + 1
        }
        offsets = computedOffsets
    }

    func offset(at line: Int) -> Int {
        guard line < offsets.count else {
            return max(0, offsets.last.map { $0 + lines.last!.utf16.count } ?? 0)
        }
        return offsets[line]
    }
}

private struct Match {
    let left: Int
    let right: Int
}

private struct ScoredMatch {
    let left: Int
    let right: Int
}

private enum TokenKind: String {
    case word
    case punctuation
    case whitespace
}

private struct DiffToken {
    let kind: TokenKind
    var text: String
    var range: NSRange

    var key: String {
        kind.rawValue + "\0" + text
    }
}

private struct ClassifiedRange {
    var range: NSRange
    let category: ChangeCategory
}

private enum Choice {
    case none
    case left
    case right
    case pair
}

private struct PairCell {
    var score = 0.0
    var count = 0
    var choice = Choice.none
}

private enum EditOperation {
    case none
    case match
    case deletion
    case insertion
}

private struct EditCell {
    var cost = 0
    var operation = EditOperation.none
}

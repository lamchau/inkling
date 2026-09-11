import Foundation

/// Selects the level of detail used to present changed text.
public enum DiffStrategy: String, CaseIterable, Sendable {
    case semantic
    case word
    case character
    case line
}

@available(*, deprecated, renamed: "DiffStrategy")
public typealias DiffAlgorithm = DiffStrategy

/// Describes the visual and semantic role of a highlighted UTF-16 range.
public enum HighlightKind: Equatable, Sendable {
    case addition
    case deletion
    case character(Int)
    case word(Int)
    case phrase(Int)

    public var category: ChangeCategory {
        switch self {
        case .addition: .addition
        case .deletion: .deletion
        case .character: .character
        case .word: .word
        case .phrase: .phrase
        }
    }
}

/// A stable category suitable for palettes, legends, and filtering.
public enum ChangeCategory: String, CaseIterable, Sendable {
    case character
    case word
    case phrase
    case addition
    case deletion
}

/// A UTF-16 range and its diff classification.
public struct TextHighlight: Equatable, Sendable {
    public let range: NSRange
    public let kind: HighlightKind

    public init(range: NSRange, kind: HighlightKind) {
        self.range = range
        self.kind = kind
    }
}

/// A whole-line changed region suitable for block-level operations.
public struct DiffHunk: Identifiable, Equatable, Sendable {
    public let id: Int
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>
    public let leftNavigationOffset: Int
    public let rightNavigationOffset: Int

    public init(
        id: Int,
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        leftNavigationOffset: Int,
        rightNavigationOffset: Int
    ) {
        self.id = id
        self.leftRange = leftRange
        self.rightRange = rightRange
        self.leftNavigationOffset = leftNavigationOffset
        self.rightNavigationOffset = rightNavigationOffset
    }
}

/// A navigable semantic change associated with a line hunk.
public struct DiffChange: Identifiable, Equatable, Sendable {
    public let id: Int
    public let hunkID: Int
    public let leftRange: NSRange?
    public let rightRange: NSRange?
    public let leftNavigationOffset: Int
    public let rightNavigationOffset: Int

    public init(
        id: Int,
        hunkID: Int,
        leftRange: NSRange?,
        rightRange: NSRange?,
        leftNavigationOffset: Int,
        rightNavigationOffset: Int
    ) {
        self.id = id
        self.hunkID = hunkID
        self.leftRange = leftRange
        self.rightRange = rightRange
        self.leftNavigationOffset = leftNavigationOffset
        self.rightNavigationOffset = rightNavigationOffset
    }
}

/// The complete comparison output for two source strings.
public struct DiffResult: Equatable, Sendable {
    public let leftHighlights: [TextHighlight]
    public let rightHighlights: [TextHighlight]
    public let hunks: [DiffHunk]
    public let changes: [DiffChange]
    public let diagnostics: DiffDiagnostics

    public init(
        leftHighlights: [TextHighlight],
        rightHighlights: [TextHighlight],
        hunks: [DiffHunk],
        changes: [DiffChange],
        diagnostics: DiffDiagnostics = .exact
    ) {
        self.leftHighlights = leftHighlights
        self.rightHighlights = rightHighlights
        self.hunks = hunks
        self.changes = changes
        self.diagnostics = diagnostics
    }

    public static let empty = DiffResult(
        leftHighlights: [],
        rightHighlights: [],
        hunks: [],
        changes: []
    )

    /// Verifies that this result is structurally valid for its source strings.
    public func validate(left: String, right: String) throws {
        let leftUTF16 = left as NSString
        let rightUTF16 = right as NSString
        let leftLineCount = left.components(separatedBy: "\n").count
        let rightLineCount = right.components(separatedBy: "\n").count

        for highlight in leftHighlights {
            try Self.validate(
                highlight.range,
                in: leftUTF16,
                side: .left
            )
        }
        for highlight in rightHighlights {
            try Self.validate(
                highlight.range,
                in: rightUTF16,
                side: .right
            )
        }
        for (index, hunk) in hunks.enumerated() {
            guard hunk.id == index else {
                throw DiffValidationError.nonSequentialHunkID(hunk.id)
            }
            guard hunk.leftRange.lowerBound >= 0,
                  hunk.leftRange.upperBound <= leftLineCount
            else {
                throw DiffValidationError.invalidLineRange(.left)
            }
            guard hunk.rightRange.lowerBound >= 0,
                  hunk.rightRange.upperBound <= rightLineCount
            else {
                throw DiffValidationError.invalidLineRange(.right)
            }
            try Self.validateNavigationOffset(
                hunk.leftNavigationOffset,
                in: leftUTF16,
                side: .left
            )
            try Self.validateNavigationOffset(
                hunk.rightNavigationOffset,
                in: rightUTF16,
                side: .right
            )
        }
        for (index, change) in changes.enumerated() {
            guard change.id == index else {
                throw DiffValidationError.nonSequentialChangeID(change.id)
            }
            guard hunks.indices.contains(change.hunkID) else {
                throw DiffValidationError.unknownHunkID(change.hunkID)
            }
            if let range = change.leftRange {
                try Self.validate(
                    range,
                    in: leftUTF16,
                    side: .left
                )
            }
            if let range = change.rightRange {
                try Self.validate(
                    range,
                    in: rightUTF16,
                    side: .right
                )
            }
            try Self.validateNavigationOffset(
                change.leftNavigationOffset,
                in: leftUTF16,
                side: .left
            )
            try Self.validateNavigationOffset(
                change.rightNavigationOffset,
                in: rightUTF16,
                side: .right
            )
        }
    }

    private static func validate(
        _ range: NSRange,
        in text: NSString,
        side: DiffValidationError.Side
    ) throws {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.length,
              range.length <= text.length - range.location,
              isUTF16ScalarBoundary(range.location, in: text),
              isUTF16ScalarBoundary(range.location + range.length, in: text)
        else {
            throw DiffValidationError.invalidRange(side)
        }
    }

    private static func validateNavigationOffset(
        _ offset: Int,
        in text: NSString,
        side: DiffValidationError.Side
    ) throws {
        guard offset >= 0,
              offset <= text.length,
              isUTF16ScalarBoundary(offset, in: text)
        else {
            throw DiffValidationError.invalidNavigationOffset(side)
        }
    }

    private static func isUTF16ScalarBoundary(
        _ offset: Int,
        in text: NSString
    ) -> Bool {
        guard offset >= 0, offset <= text.length else { return false }
        guard offset > 0, offset < text.length else { return true }
        return !(
            text.character(at: offset - 1).isHighSurrogate
                && text.character(at: offset).isLowSurrogate
        )
    }
}

private extension UInt16 {
    var isHighSurrogate: Bool {
        (0xD800...0xDBFF).contains(self)
    }

    var isLowSurrogate: Bool {
        (0xDC00...0xDFFF).contains(self)
    }
}

/// A structural validation failure in a diff result.
public enum DiffValidationError: Error, Equatable, Sendable {
    public enum Side: Sendable {
        case left
        case right
    }

    case invalidRange(Side)
    case invalidLineRange(Side)
    case invalidNavigationOffset(Side)
    case nonSequentialHunkID(Int)
    case nonSequentialChangeID(Int)
    case unknownHunkID(Int)
}

/// Reports the matching path and any accuracy-preserving bounds used.
public struct DiffDiagnostics: Equatable, Sendable {
    /// The strongest guarantee available for the completed comparison.
    public enum Quality: String, Equatable, Sendable {
        /// Matching completed without a coarse fallback.
        case exact
        /// Stable unique anchors partitioned a large comparison.
        case anchored
        /// At least one region required a coarse bounded fallback.
        case bounded
    }

    public let quality: Quality
    public let usedPatienceAnchors: Bool
    public let usedLinearSpaceAlignment: Bool
    public let exhaustedWorkBudget: Bool
    public let usedPositionalFallback: Bool
    public let usedPrefixSimilarityFallback: Bool
    public let exactMatrixCellLimit: Int
    public let workCellBudget: Int

    public init(
        quality: Quality,
        usedPatienceAnchors: Bool,
        usedLinearSpaceAlignment: Bool,
        exhaustedWorkBudget: Bool,
        usedPositionalFallback: Bool = false,
        usedPrefixSimilarityFallback: Bool = false,
        exactMatrixCellLimit: Int = 1_000_000,
        workCellBudget: Int = 8_000_000
    ) {
        self.quality = quality
        self.usedPatienceAnchors = usedPatienceAnchors
        self.usedLinearSpaceAlignment = usedLinearSpaceAlignment
        self.exhaustedWorkBudget = exhaustedWorkBudget
        self.usedPositionalFallback = usedPositionalFallback
        self.usedPrefixSimilarityFallback = usedPrefixSimilarityFallback
        self.exactMatrixCellLimit = exactMatrixCellLimit
        self.workCellBudget = workCellBudget
    }

    public static let exact = DiffDiagnostics(
        quality: .exact,
        usedPatienceAnchors: false,
        usedLinearSpaceAlignment: false,
        exhaustedWorkBudget: false
    )
}

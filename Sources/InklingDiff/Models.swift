import Foundation

public enum DiffAlgorithm: String, CaseIterable, Sendable {
    case semantic
    case word
    case character
    case line
}

public typealias DiffStrategy = DiffAlgorithm

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

public enum ChangeCategory: String, CaseIterable, Sendable {
    case character
    case word
    case phrase
    case addition
    case deletion
}

public struct TextHighlight: Equatable, Sendable {
    public let range: NSRange
    public let kind: HighlightKind

    public init(range: NSRange, kind: HighlightKind) {
        self.range = range
        self.kind = kind
    }
}

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

public struct DiffResult: Equatable, Sendable {
    public let leftHighlights: [TextHighlight]
    public let rightHighlights: [TextHighlight]
    public let hunks: [DiffHunk]
    public let changes: [DiffChange]
    public let diagnostics: DiffDiagnostics
    public let documentRevision: Int

    public init(
        leftHighlights: [TextHighlight],
        rightHighlights: [TextHighlight],
        hunks: [DiffHunk],
        changes: [DiffChange],
        diagnostics: DiffDiagnostics = .exact,
        documentRevision: Int = 0
    ) {
        self.leftHighlights = leftHighlights
        self.rightHighlights = rightHighlights
        self.hunks = hunks
        self.changes = changes
        self.diagnostics = diagnostics
        self.documentRevision = documentRevision
    }

    public func stamped(with documentRevision: Int) -> DiffResult {
        DiffResult(
            leftHighlights: leftHighlights,
            rightHighlights: rightHighlights,
            hunks: hunks,
            changes: changes,
            diagnostics: diagnostics,
            documentRevision: documentRevision
        )
    }

    public static let empty = DiffResult(
        leftHighlights: [],
        rightHighlights: [],
        hunks: [],
        changes: []
    )
}

public struct DiffDiagnostics: Equatable, Sendable {
    public enum Quality: String, Equatable, Sendable {
        case exact
        case anchored
        case bounded
    }

    public let quality: Quality
    public let usedPatienceAnchors: Bool
    public let usedLinearSpaceAlignment: Bool
    public let exhaustedWorkBudget: Bool

    public init(
        quality: Quality,
        usedPatienceAnchors: Bool,
        usedLinearSpaceAlignment: Bool,
        exhaustedWorkBudget: Bool
    ) {
        self.quality = quality
        self.usedPatienceAnchors = usedPatienceAnchors
        self.usedLinearSpaceAlignment = usedLinearSpaceAlignment
        self.exhaustedWorkBudget = exhaustedWorkBudget
    }

    public static let exact = DiffDiagnostics(
        quality: .exact,
        usedPatienceAnchors: false,
        usedLinearSpaceAlignment: false,
        exhaustedWorkBudget: false
    )
}

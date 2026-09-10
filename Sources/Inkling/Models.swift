import AppKit
import Foundation

enum DiffSide: Sendable {
    case left
    case right
}

enum HighlightKind: Equatable, Sendable {
    case addition
    case deletion
    case character(Int)
    case word(Int)
    case phrase(Int)

    var category: ChangeCategory {
        switch self {
        case .addition: .addition
        case .deletion: .deletion
        case .character: .character
        case .word: .word
        case .phrase: .phrase
        }
    }
}

enum ChangeCategory: String, CaseIterable, Identifiable, Sendable {
    case character
    case word
    case phrase
    case addition
    case deletion

    var id: Self { self }

    var title: String {
        switch self {
        case .character: L10n.string("Character")
        case .word: L10n.string("Word")
        case .phrase: L10n.string("Phrase")
        case .addition: L10n.string("Addition")
        case .deletion: L10n.string("Deletion")
        }
    }
}

struct TextHighlight: Equatable, Sendable {
    let range: NSRange
    let kind: HighlightKind
}

struct CaretPosition: Equatable {
    let line: Int
    let column: Int
    let source: DiffSide
}

struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: Int
    let leftRange: Range<Int>
    let rightRange: Range<Int>
    let leftNavigationOffset: Int
    let rightNavigationOffset: Int
}

struct DiffChange: Identifiable, Equatable, Sendable {
    let id: Int
    let hunkID: Int
    let leftRange: NSRange?
    let rightRange: NSRange?
    let leftNavigationOffset: Int
    let rightNavigationOffset: Int
}

struct DiffResult: Equatable, Sendable {
    let leftHighlights: [TextHighlight]
    let rightHighlights: [TextHighlight]
    let hunks: [DiffHunk]
    let changes: [DiffChange]
    let documentRevision: Int

    init(
        leftHighlights: [TextHighlight],
        rightHighlights: [TextHighlight],
        hunks: [DiffHunk],
        changes: [DiffChange],
        documentRevision: Int = 0
    ) {
        self.leftHighlights = leftHighlights
        self.rightHighlights = rightHighlights
        self.hunks = hunks
        self.changes = changes
        self.documentRevision = documentRevision
    }

    func stamped(with documentRevision: Int) -> DiffResult {
        DiffResult(
            leftHighlights: leftHighlights,
            rightHighlights: rightHighlights,
            hunks: hunks,
            changes: changes,
            documentRevision: documentRevision
        )
    }

    static let empty = DiffResult(
        leftHighlights: [],
        rightHighlights: [],
        hunks: [],
        changes: []
    )
}

struct LoadedTextFile: Sendable {
    let url: URL
    let text: String
}

enum InklingError: LocalizedError {
    case unreadable(URL, Error)
    case unwritable(URL, Error)
    case tooLarge(URL)
    case binary(URL)
    case sameFile
    case requiresTwoFiles
    case staleDiff

    var errorDescription: String? {
        switch self {
        case let .unreadable(url, error):
            L10n.string(
                "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            )
        case let .unwritable(url, error):
            L10n.string(
                "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            )
        case let .tooLarge(url):
            L10n.string("\(url.lastPathComponent) is larger than the 5 MiB limit.")
        case let .binary(url):
            L10n.string(
                "\(url.lastPathComponent) contains binary data and cannot be compared."
            )
        case .sameFile:
            L10n.string("Choose 2 different files.")
        case .requiresTwoFiles:
            L10n.string("2 files are required to start a comparison.")
        case .staleDiff:
            L10n.string(
                "The comparison is out of date. Wait for it to refresh before copying a change."
            )
        }
    }
}

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
        rawValue.capitalized
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

struct DiffResult: Equatable, Sendable {
    let leftHighlights: [TextHighlight]
    let rightHighlights: [TextHighlight]
    let hunks: [DiffHunk]

    static let empty = DiffResult(leftHighlights: [], rightHighlights: [], hunks: [])
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

    var errorDescription: String? {
        switch self {
        case let .unreadable(url, error):
            "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        case let .unwritable(url, error):
            "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
        case let .tooLarge(url):
            "\(url.lastPathComponent) is larger than the 5 MiB limit."
        case let .binary(url):
            "\(url.lastPathComponent) contains binary data and cannot be compared."
        case .sameFile:
            "Choose two different files."
        case .requiresTwoFiles:
            "Select exactly two files to start a comparison."
        }
    }
}

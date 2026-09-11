import AppKit
import Foundation
import InklingDiff

enum DiffSide: Sendable {
    case left
    case right
}

extension ChangeCategory: Identifiable {
    public var id: Self { self }

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

struct CaretPosition: Equatable {
    let line: Int
    let column: Int
    let source: DiffSide
}

struct LoadedTextFile: Sendable {
    let url: URL
    let text: String
    let byteCount: Int

    init(url: URL, text: String, byteCount: Int? = nil) {
        self.url = url
        self.text = text
        self.byteCount = byteCount ?? text.utf8.count
    }
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

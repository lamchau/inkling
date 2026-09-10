import AppKit
import Observation
import SwiftUI

enum DiffAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case semantic
    case word
    case character
    case line

    var id: Self { self }

    var title: String {
        switch self {
        case .semantic: "Semantic"
        case .word: "Word"
        case .character: "Character"
        case .line: "Line"
        }
    }

    var detail: String {
        switch self {
        case .semantic: "Stable word anchors, phrase blocks, and exact character edits"
        case .word: "Whole changed words and punctuation"
        case .character: "Smallest character-level differences"
        case .line: "Complete changed lines"
        }
    }
}

enum HighlightStyle: String, CaseIterable, Identifiable {
    case foreground
    case background

    var id: Self { self }

    var title: String {
        switch self {
        case .foreground: "Foreground"
        case .background: "Background"
        }
    }
}

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case commandOptionArrows
    case commandBrackets
    case controlBrackets
    case optionJK

    var id: Self { self }

    var title: String {
        switch self {
        case .commandOptionArrows: "⌘⌥↑ / ⌘⌥↓"
        case .commandBrackets: "⌘[ / ⌘]"
        case .controlBrackets: "⌃[ / ⌃]"
        case .optionJK: "⌥K / ⌥J"
        }
    }

    var previousKey: KeyEquivalent {
        switch self {
        case .commandOptionArrows: .upArrow
        case .commandBrackets, .controlBrackets: "["
        case .optionJK: "k"
        }
    }

    var nextKey: KeyEquivalent {
        switch self {
        case .commandOptionArrows: .downArrow
        case .commandBrackets, .controlBrackets: "]"
        case .optionJK: "j"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .commandOptionArrows: [.command, .option]
        case .commandBrackets: .command
        case .controlBrackets: .control
        case .optionJK: .option
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let algorithm = "diffAlgorithm"
        static let showLineNumbers = "showLineNumbers"
        static let syncScrolling = "syncScrolling"
        static let syncCaret = "syncCaret"
        static let shortcuts = "navigationShortcuts"
        static let highlightStyle = "highlightStyle"
    }

    var algorithm: DiffAlgorithm {
        didSet { defaults.set(algorithm.rawValue, forKey: Key.algorithm) }
    }
    var showLineNumbers: Bool {
        didSet { defaults.set(showLineNumbers, forKey: Key.showLineNumbers) }
    }
    var syncScrolling: Bool {
        didSet { defaults.set(syncScrolling, forKey: Key.syncScrolling) }
    }
    var syncCaret: Bool {
        didSet { defaults.set(syncCaret, forKey: Key.syncCaret) }
    }
    var shortcuts: ShortcutPreset {
        didSet { defaults.set(shortcuts.rawValue, forKey: Key.shortcuts) }
    }
    var highlightStyle: HighlightStyle {
        didSet { defaults.set(highlightStyle.rawValue, forKey: Key.highlightStyle) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        algorithm = DiffAlgorithm(
            rawValue: defaults.string(forKey: Key.algorithm) ?? ""
        ) ?? .semantic
        showLineNumbers = defaults.object(forKey: Key.showLineNumbers) as? Bool ?? true
        syncScrolling = defaults.object(forKey: Key.syncScrolling) as? Bool ?? true
        syncCaret = defaults.object(forKey: Key.syncCaret) as? Bool ?? false
        shortcuts = ShortcutPreset(
            rawValue: defaults.string(forKey: Key.shortcuts) ?? ""
        ) ?? .commandOptionArrows
        highlightStyle = HighlightStyle(
            rawValue: defaults.string(forKey: Key.highlightStyle) ?? ""
        ) ?? .foreground
    }
}

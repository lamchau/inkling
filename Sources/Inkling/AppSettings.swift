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
        case .semantic: L10n.string("Semantic")
        case .word: L10n.string("Word")
        case .character: L10n.string("Character")
        case .line: L10n.string("Line")
        }
    }

    var detail: String {
        switch self {
        case .semantic:
            L10n.string("Stable word anchors, phrase blocks, and exact character edits")
        case .word:
            L10n.string("Whole changed words and punctuation")
        case .character:
            L10n.string("Smallest character-level differences")
        case .line:
            L10n.string("Complete changed lines")
        }
    }
}

enum HighlightStyle: String, CaseIterable, Identifiable {
    case foreground
    case background

    var id: Self { self }

    var title: String {
        switch self {
        case .foreground: L10n.string("Foreground")
        case .background: L10n.string("Background")
        }
    }
}

enum ComparisonLayout: String, CaseIterable, Identifiable, Sendable {
    case sideBySide
    case topAndBottom

    var id: Self { self }

    var title: String {
        switch self {
        case .sideBySide: L10n.string("Side by Side")
        case .topAndBottom: L10n.string("Top and Bottom")
        }
    }

    var systemImage: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .topAndBottom: "rectangle.split.1x2"
        }
    }
}

struct PaletteColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let color = color.usingColorSpace(.sRGB) ?? color
        red = Double(color.redComponent)
        green = Double(color.greenComponent)
        blue = Double(color.blueComponent)
        alpha = Double(color.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

struct DiffPalette: Codable, Equatable, Sendable {
    var character = PaletteColor(NSColor.systemPink)
    var word = PaletteColor(NSColor.systemOrange)
    var phrase = PaletteColor(NSColor.systemBlue)
    var addition = PaletteColor(NSColor.systemGreen)
    var deletion = PaletteColor(NSColor.systemRed)

    static let `default` = DiffPalette()

    func color(for category: ChangeCategory) -> PaletteColor {
        switch category {
        case .character: character
        case .word: word
        case .phrase: phrase
        case .addition: addition
        case .deletion: deletion
        }
    }

    mutating func setColor(_ color: PaletteColor, for category: ChangeCategory) {
        switch category {
        case .character: character = color
        case .word: word = color
        case .phrase: phrase = color
        case .addition: addition = color
        case .deletion: deletion = color
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
        static let palette = "diffPalette"
        static let comparisonLayout = "comparisonLayout"
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
    var palette: DiffPalette {
        didSet {
            defaults.set(try? JSONEncoder().encode(palette), forKey: Key.palette)
        }
    }
    var comparisonLayout: ComparisonLayout {
        didSet { defaults.set(comparisonLayout.rawValue, forKey: Key.comparisonLayout) }
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
        palette = defaults.data(forKey: Key.palette)
            .flatMap { try? JSONDecoder().decode(DiffPalette.self, from: $0) }
            ?? .default
        comparisonLayout = ComparisonLayout(
            rawValue: defaults.string(forKey: Key.comparisonLayout) ?? ""
        ) ?? .sideBySide
    }

    func color(for category: ChangeCategory) -> NSColor {
        palette.color(for: category).nsColor
    }

    func setColor(_ color: NSColor, for category: ChangeCategory) {
        palette.setColor(PaletteColor(color), for: category)
    }

    func resetPalette() {
        palette = .default
    }
}

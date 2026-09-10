import AppKit
import Foundation
import Testing
@testable import Inkling

@Suite("App settings")
@MainActor
struct AppSettingsTests {
    @Test("editor and navigation preferences persist")
    func persistence() {
        let suite = "InklingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.algorithm = .character
        settings.showLineNumbers = false
        settings.syncScrolling = false
        settings.syncCaret = true
        settings.shortcuts = .optionJK
        settings.highlightStyle = .background
        settings.comparisonLayout = .topAndBottom
        settings.setColor(
            NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            for: .character
        )

        let restored = AppSettings(defaults: defaults)
        #expect(restored.algorithm == .character)
        #expect(restored.showLineNumbers == false)
        #expect(restored.syncScrolling == false)
        #expect(restored.syncCaret == true)
        #expect(restored.shortcuts == .optionJK)
        #expect(restored.highlightStyle == .background)
        #expect(restored.comparisonLayout == .topAndBottom)
        #expect(restored.palette.character == settings.palette.character)
    }
}

import InklingDiff
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            Form {
                Picker(L10n.string("Comparison strategy"), selection: $settings.strategy) {
                    ForEach(DiffStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                Text(settings.strategy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.string("Highlight colors"), selection: $settings.highlightStyle) {
                    ForEach(HighlightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker(L10n.string("Change navigation"), selection: $settings.shortcuts) {
                    ForEach(ShortcutPreset.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(L10n.string("Diff"), systemImage: "arrow.left.arrow.right")
            }

            Form {
                Picker(
                    L10n.string("Comparison layout"),
                    selection: $settings.comparisonLayout
                ) {
                    ForEach(ComparisonLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.systemImage)
                            .tag(layout)
                    }
                }

                Toggle(L10n.string("Show line numbers"), isOn: $settings.showLineNumbers)
                Toggle(L10n.string("Synchronize scrolling"), isOn: $settings.syncScrolling)
                Toggle(L10n.string("Synchronize caret position"), isOn: $settings.syncCaret)
                Text(
                    L10n.string(
                        "Caret synchronization follows the same logical line and column."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label(L10n.string("Editor"), systemImage: "text.cursor")
            }
        }
        .padding(12)
        .frame(width: 520, height: 300)
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            Form {
                Picker("Diff algorithm", selection: $settings.algorithm) {
                    ForEach(DiffAlgorithm.allCases) { algorithm in
                        Text(algorithm.title).tag(algorithm)
                    }
                }
                Text(settings.algorithm.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Highlight colors", selection: $settings.highlightStyle) {
                    ForEach(HighlightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Change navigation", selection: $settings.shortcuts) {
                    ForEach(ShortcutPreset.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Diff", systemImage: "arrow.left.arrow.right")
            }

            Form {
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Synchronize scrolling", isOn: $settings.syncScrolling)
                Toggle("Synchronize caret position", isOn: $settings.syncCaret)
                Text("Caret synchronization follows the same logical line and column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Editor", systemImage: "text.cursor")
            }
        }
        .padding(12)
        .frame(width: 520, height: 300)
    }
}

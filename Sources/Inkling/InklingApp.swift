import SwiftUI

@main
struct InklingApp: App {
    @State private var settings: AppSettings
    @State private var session: DiffSession

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _session = State(initialValue: DiffSession(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(settings)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1260, height: 780)
        .commands {
            InklingCommands(session: session, settings: settings)
        }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}

struct InklingCommands: Commands {
    let session: DiffSession
    let settings: AppSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Comparison…") {
                session.chooseFiles()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Choose Left File…") {
                session.chooseFile(for: .left)
            }

            Button("Choose Right File…") {
                session.chooseFile(for: .right)
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Both") {
                session.saveBoth()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!session.canSave)
        }

        CommandMenu("Compare") {
            Button("Previous Change") {
                session.previousHunk()
            }
            .keyboardShortcut(
                settings.shortcuts.previousKey,
                modifiers: settings.shortcuts.modifiers
            )
            .disabled(session.result.hunks.isEmpty)

            Button("Next Change") {
                session.nextHunk()
            }
            .keyboardShortcut(
                settings.shortcuts.nextKey,
                modifiers: settings.shortcuts.modifiers
            )
            .disabled(session.result.hunks.isEmpty)

            Divider()

            Button("Copy Left to Right") {
                session.applyCurrentHunk(from: .left)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(session.currentHunk == nil)

            Button("Copy Right to Left") {
                session.applyCurrentHunk(from: .right)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(session.currentHunk == nil)

            Divider()

            Toggle("Ignore Whitespace", isOn: Binding(
                get: { session.ignoreWhitespace },
                set: { session.ignoreWhitespace = $0 }
            ))
            .keyboardShortcut("w", modifiers: [.command, .option])

            Button("Swap Sides") {
                session.swapSides()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}

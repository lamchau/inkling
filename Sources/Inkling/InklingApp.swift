import AppKit
import SwiftUI

@main
struct InklingApp: App {
    @NSApplicationDelegateAdaptor(InklingAppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var session: DiffSession

    init() {
        let settings = AppSettings()
        let session = DiffSession(settings: settings)
        _settings = State(initialValue: settings)
        _session = State(initialValue: session)
        appDelegate.session = session
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
            Button(L10n.string("Open Comparison…")) {
                session.chooseFiles()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(
                settings.comparisonLayout == .sideBySide
                    ? L10n.string("Choose Left File…")
                    : L10n.string("Choose Top File…")
            ) {
                session.chooseFile(for: .left)
            }

            Button(
                settings.comparisonLayout == .sideBySide
                    ? L10n.string("Choose Right File…")
                    : L10n.string("Choose Bottom File…")
            ) {
                session.chooseFile(for: .right)
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button(L10n.string("Save")) {
                session.saveFocusedSide()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!session.canSaveFocusedSide)

            Button(
                settings.comparisonLayout == .sideBySide
                    ? L10n.string("Save Left")
                    : L10n.string("Save Top")
            ) {
                session.save(.left)
            }
            .disabled(!session.leftIsDirty)

            Button(
                settings.comparisonLayout == .sideBySide
                    ? L10n.string("Save Right")
                    : L10n.string("Save Bottom")
            ) {
                session.save(.right)
            }
            .disabled(!session.rightIsDirty)

            Button(L10n.string("Save Both")) {
                session.saveBoth()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!session.canSave)
        }

        CommandMenu(L10n.string("Compare")) {
            Button(L10n.string("Previous Change")) {
                session.previousChange()
            }
            .keyboardShortcut(
                settings.shortcuts.previousKey,
                modifiers: settings.shortcuts.modifiers
            )
            .disabled(session.result.changes.isEmpty)

            Button(L10n.string("Next Change")) {
                session.nextChange()
            }
            .keyboardShortcut(
                settings.shortcuts.nextKey,
                modifiers: settings.shortcuts.modifiers
            )
            .disabled(session.result.changes.isEmpty)

            Divider()

            Button(session.copyBlockActionTitle(from: .left)) {
                session.copyCurrentBlock(from: .left)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(session.currentHunk == nil)

            Button(session.copyBlockActionTitle(from: .right)) {
                session.copyCurrentBlock(from: .right)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(session.currentHunk == nil)

            Divider()

            Toggle(L10n.string("Ignore Whitespace"), isOn: Binding(
                get: { session.ignoreWhitespace },
                set: { session.ignoreWhitespace = $0 }
            ))
            .keyboardShortcut("w", modifiers: [.command, .option])

            Button(L10n.string("Swap Sides")) {
                session.swapSides()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}

@MainActor
final class InklingAppDelegate: NSObject, NSApplicationDelegate {
    weak var session: DiffSession?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session?.requestWindowClose() == false ? .terminateCancel : .terminateNow
    }
}

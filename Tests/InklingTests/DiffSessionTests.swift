import AppKit
import Foundation
import Testing
@testable import Inkling

@Suite("Diff navigation")
@MainActor
struct DiffSessionTests {
    @Test("next and previous recenter on semantic changes")
    func changeNavigation() {
        let session = DiffSession()
        session.result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 1..<2,
                    rightRange: 1..<2,
                    leftNavigationOffset: 0,
                    rightNavigationOffset: 0
                ),
            ],
            changes: [
                DiffChange(
                    id: 0,
                    hunkID: 0,
                    leftRange: NSRange(location: 10, length: 5),
                    rightRange: NSRange(location: 12, length: 4),
                    leftNavigationOffset: 10,
                    rightNavigationOffset: 12
                ),
                DiffChange(
                    id: 1,
                    hunkID: 0,
                    leftRange: NSRange(location: 80, length: 5),
                    rightRange: NSRange(location: 90, length: 5),
                    leftNavigationOffset: 80,
                    rightNavigationOffset: 90
                ),
            ]
        )

        session.nextChange()
        #expect(session.currentChangeIndex == 0)
        #expect(session.leftNavigationOffset == 10)
        #expect(session.rightNavigationOffset == 12)
        let firstRevision = session.navigationRevision

        session.nextChange()
        #expect(session.currentChangeIndex == 1)
        #expect(session.leftNavigationOffset == 80)
        #expect(session.rightNavigationOffset == 90)
        #expect(session.navigationRevision == firstRevision + 1)
        #expect(session.currentHunk?.id == 0)

        session.previousChange()
        #expect(session.currentChangeIndex == 0)
    }

    @Test("background refresh does not navigate")
    func refreshPreservesNavigation() async throws {
        let session = DiffSession()
        session.leftText = "alpha\nsame\nomega"
        session.rightText = "ALPHA\nsame\nOMEGA"
        session.result = DiffEngine.compare(
            left: session.leftText,
            right: session.rightText,
            ignoreWhitespace: false
        ).stamped(with: session.documentRevision)
        session.nextChange()
        session.nextChange()
        let navigationRevision = session.navigationRevision
        let leftOffset = session.leftNavigationOffset
        let rightOffset = session.rightNavigationOffset

        session.rightText = "ALPHA\nsame\nOMEGA!"
        session.refreshImmediately()
        try await waitForCurrentResult(session)

        #expect(session.navigationRevision == navigationRevision)
        #expect(session.leftNavigationOffset == leftOffset)
        #expect(session.rightNavigationOffset == rightOffset)
    }

    @Test("stale hunk apply is rejected")
    func staleApply() {
        let (session, leftEditor, rightEditor) = makeTransferSession(
            left: "one\nleft",
            right: "one\nright"
        )
        let staleResult = DiffEngine.compare(
            left: session.leftText,
            right: session.rightText,
            ignoreWhitespace: false
        ).stamped(with: session.documentRevision)
        session.rightText = "one\nnewer"
        session.result = staleResult
        session.nextChange()

        session.copyCurrentBlock(from: .left)

        #expect(session.rightText == "one\nnewer")
        #expect(rightEditor.string == "one\nright")
        #expect(!rightEditor.testUndoManager.canUndo)
        #expect(leftEditor.string == "one\nleft")
        #expect(
            session.statusMessage
                == "Copy Block skipped: left → right into right.txt; comparison is out of date."
        )
        #expect(session.errorMessage == InklingError.staleDiff.localizedDescription)
    }

    @Test("left-to-right Copy Block is one named native undo operation")
    func copyBlockLeftToRight() {
        let originalTarget = "😀 one\nright A\nright B\nfour"
        let (session, _, rightEditor) = makeTransferSession(
            left: "😀 one\nleft A\nleft B\nfour",
            right: originalTarget
        )
        #expect(session.copyBlockActionTitle(from: .left) == "Copy Block Left to Right — right.txt")
        #expect(session.copyBlockHelp(from: .left) == "Copy Block left → right into right.txt")

        session.copyCurrentBlock(from: .left)

        #expect(session.rightText == session.leftText)
        #expect(rightEditor.string == session.leftText)
        #expect(session.errorMessage == nil)
        #expect(session.statusMessage == "Copy Block completed: left → right into right.txt.")
        #expect(rightEditor.shouldChangeCount == 1)
        #expect(rightEditor.didChangeCount == 1)
        #expect(rightEditor.testUndoManager.canUndo)
        #expect(rightEditor.testUndoManager.undoActionName == "Copy Block")

        rightEditor.testUndoManager.undo()

        #expect(rightEditor.string == originalTarget)
        #expect(session.rightText == originalTarget)
        #expect(!rightEditor.testUndoManager.canUndo)
        #expect(rightEditor.testUndoManager.canRedo)
    }

    @Test("stacked layout describes vertical block transfers")
    func stackedCopyBlockLabels() {
        let suite = "InklingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let (session, _, _) = makeTransferSession(
            left: "one\nupper\nthree",
            right: "one\nlower\nthree",
            settings: settings
        )
        session.settings.comparisonLayout = .topAndBottom

        #expect(
            session.copyBlockActionTitle(from: .left)
                == "Copy Block Top to Bottom — right.txt"
        )
        #expect(
            session.copyBlockHelp(from: .right)
                == "Copy Block bottom → top into left.txt"
        )
    }

    @Test("right-to-left Copy Block replaces the complete hunk")
    func copyBlockRightToLeft() {
        let (session, leftEditor, _) = makeTransferSession(
            left: "one\nleft\nthree",
            right: "one\nright\nthree"
        )

        session.copyCurrentBlock(from: .right)

        #expect(session.leftText == session.rightText)
        #expect(leftEditor.string == session.rightText)
        #expect(session.statusMessage == "Copy Block completed: right → left into left.txt.")
        #expect(leftEditor.testUndoManager.undoActionName == "Copy Block")
    }

    @Test("invalid Copy Block ranges are a safe no-op")
    func invalidCopyBlockRange() {
        let (session, _, rightEditor) = makeTransferSession(
            left: "one\nleft",
            right: "one\nright"
        )
        session.result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 1..<9,
                    rightRange: 1..<2,
                    leftNavigationOffset: 0,
                    rightNavigationOffset: 0
                ),
            ],
            changes: [
                DiffChange(
                    id: 0,
                    hunkID: 0,
                    leftRange: nil,
                    rightRange: nil,
                    leftNavigationOffset: 0,
                    rightNavigationOffset: 0
                ),
            ],
            documentRevision: session.documentRevision
        )
        session.currentChangeIndex = 0

        session.copyCurrentBlock(from: .left)

        #expect(session.rightText == "one\nright")
        #expect(rightEditor.string == "one\nright")
        #expect(!rightEditor.testUndoManager.canUndo)
        #expect(
            session.statusMessage
                == "Copy Block skipped: left → right into right.txt; source or destination range is invalid."
        )
    }

    @Test("loading a file clears the replaced editor undo history")
    func loadClearsUndo() {
        let (session, _, rightEditor) = makeTransferSession(
            left: "one\nleft",
            right: "one\nright"
        )
        session.copyCurrentBlock(from: .left)
        #expect(rightEditor.testUndoManager.canUndo)

        session.load(replacementURL, for: .right)
        DiffTextView.replaceTextWithoutUndo(session.rightText, in: rightEditor)

        #expect(!rightEditor.testUndoManager.canUndo)
        #expect(!rightEditor.testUndoManager.canRedo)
        #expect(session.rightText == "replacement")
        #expect(rightEditor.string == "replacement")
    }

    @Test("dirty state follows each saved baseline")
    func dirtyTransitions() {
        let session = makeSession()
        session.openDroppedFiles([leftURL, rightURL])

        #expect(!session.leftIsDirty)
        #expect(!session.rightIsDirty)

        session.leftText = "edited left"
        #expect(session.leftIsDirty)
        #expect(!session.rightIsDirty)

        session.leftText = "left"
        #expect(!session.leftIsDirty)

        session.rightText = "edited right"
        _ = session.save(.right)
        #expect(!session.rightIsDirty)

        session.rightText = "right"
        #expect(session.rightIsDirty)
    }

    @Test("single-file drops fill each requested side")
    func singleFileDrops() {
        let session = makeSession()

        session.openDroppedFiles([leftURL], on: .left)
        session.openDroppedFiles([rightURL], on: .right)

        #expect(session.leftURL == leftURL)
        #expect(session.rightURL == rightURL)
        #expect(session.leftText == "left")
        #expect(session.rightText == "right")
        #expect(session.hasBothFiles)
    }

    @Test("focused save writes only the focused dirty side")
    func focusedSave() {
        var savedURLs: [URL] = []
        let session = makeSession(saveFile: { _, url in
            savedURLs.append(url)
        })
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "edited left"
        session.rightText = "edited right"
        session.focusedSide = .left

        let outcome = session.saveFocusedSide()

        #expect(savedURLs == [leftURL])
        #expect(outcome.saved == [.left])
        #expect(!session.leftIsDirty)
        #expect(session.rightIsDirty)
    }

    @Test("save both skips clean panes")
    func saveBothSkipsCleanSide() {
        var savedURLs: [URL] = []
        let session = makeSession(saveFile: { _, url in
            savedURLs.append(url)
        })
        session.openDroppedFiles([leftURL, rightURL])
        session.rightText = "edited right"

        let outcome = session.saveBoth()

        #expect(savedURLs == [rightURL])
        #expect(outcome.saved == [.right])
        #expect(outcome.failed.isEmpty)
    }

    @Test("cancelling replacement preserves pane state")
    func cancelledReplacement() {
        let session = makeSession(decision: .cancel)
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "unsaved"

        session.load(replacementURL, for: .left)

        #expect(session.leftURL == leftURL)
        #expect(session.leftText == "unsaved")
        #expect(session.leftIsDirty)
    }

    @Test("cancelling comparison replacement preserves both panes")
    func cancelledComparisonReplacement() {
        let session = makeSession(decision: .cancel)
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "unsaved left"
        session.rightText = "unsaved right"

        session.openDroppedFiles([
            replacementURL,
            URL(fileURLWithPath: "/fixtures/other.txt"),
        ])

        #expect(session.leftURL == leftURL)
        #expect(session.rightURL == rightURL)
        #expect(session.leftText == "unsaved left")
        #expect(session.rightText == "unsaved right")
    }

    @Test("cancelling close preserves all state")
    func cancelledClose() {
        let session = makeSession(decision: .cancel)
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "unsaved left"
        session.rightText = "unsaved right"

        #expect(!session.requestWindowClose())
        #expect(session.leftURL == leftURL)
        #expect(session.rightURL == rightURL)
        #expect(session.leftText == "unsaved left")
        #expect(session.rightText == "unsaved right")
    }

    @Test("discarding on close does not rewrite buffers")
    func discardedClosePreservesBuffers() {
        let session = makeSession(decision: .discard)
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "unsaved left"
        session.rightText = "unsaved right"

        #expect(session.requestWindowClose())
        #expect(session.leftText == "unsaved left")
        #expect(session.rightText == "unsaved right")
    }

    @Test("save both reports partial failure and keeps failed pane dirty")
    func partialSaveFailure() {
        let session = makeSession(saveFile: { _, url in
            if url == leftURL {
                throw SaveFailure.expected
            }
        })
        session.openDroppedFiles([leftURL, rightURL])
        session.leftText = "edited left"
        session.rightText = "edited right"

        let outcome = session.saveBoth()

        #expect(outcome.saved == [.right])
        #expect(outcome.failed == [.left])
        #expect(session.leftIsDirty)
        #expect(!session.rightIsDirty)
        #expect(session.statusMessage == "Saved right; could not save left.")
        #expect(session.errorMessage == SaveFailure.expected.localizedDescription)
    }

    private func waitForCurrentResult(_ session: DiffSession) async throws {
        for _ in 0..<100 {
            if session.result.documentRevision == session.documentRevision,
               !session.result.changes.isEmpty
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the current diff result.")
    }

    private var leftURL: URL {
        URL(fileURLWithPath: "/fixtures/left.txt")
    }

    private var rightURL: URL {
        URL(fileURLWithPath: "/fixtures/right.txt")
    }

    private var replacementURL: URL {
        URL(fileURLWithPath: "/fixtures/replacement.txt")
    }

    private func makeSession(
        saveFile: @escaping DiffSession.SaveFile = { _, _ in },
        decision: DiffSession.UnsavedChangesDecision = .discard
    ) -> DiffSession {
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "InklingTests.DiffSession")!
        )
        settings.comparisonLayout = .sideBySide
        return DiffSession(
            settings: settings,
            loadFile: { url in
                let text = switch url.lastPathComponent {
                case "left.txt": "left"
                case "right.txt": "right"
                default: "replacement"
                }
                return LoadedTextFile(url: url, text: text)
            },
            saveFile: saveFile,
            decisionProvider: { _, _ in decision }
        )
    }

    private func makeTransferSession(
        left: String,
        right: String,
        settings: AppSettings? = nil
    ) -> (DiffSession, TestTextView, TestTextView) {
        let resolvedSettings: AppSettings
        if let settings {
            resolvedSettings = settings
        } else {
            resolvedSettings = AppSettings(
                defaults: UserDefaults(suiteName: "InklingTests.DiffSession")!
            )
            resolvedSettings.comparisonLayout = .sideBySide
        }
        let session = DiffSession(
            settings: resolvedSettings,
            loadFile: { url in
                let text = switch url.lastPathComponent {
                case "left.txt": left
                case "right.txt": right
                default: "replacement"
                }
                return LoadedTextFile(url: url, text: text)
            },
            saveFile: { _, _ in },
            decisionProvider: { _, _ in .discard }
        )
        session.openDroppedFiles([leftURL, rightURL])
        let leftEditor = TestTextView()
        leftEditor.string = left
        leftEditor.allowsUndo = true
        leftEditor.onChange = { session.leftText = $0 }
        leftEditor.delegate = leftEditor
        leftEditor.observeStorageChanges()
        let rightEditor = TestTextView()
        rightEditor.string = right
        rightEditor.allowsUndo = true
        rightEditor.onChange = { session.rightText = $0 }
        rightEditor.delegate = rightEditor
        rightEditor.observeStorageChanges()
        session.registerEditor(leftEditor, for: .left)
        session.registerEditor(rightEditor, for: .right)
        session.result = DiffEngine.compare(
            left: left,
            right: right,
            ignoreWhitespace: false
        ).stamped(with: session.documentRevision)
        session.nextChange()
        return (session, leftEditor, rightEditor)
    }

    private enum SaveFailure: LocalizedError {
        case expected

        var errorDescription: String? {
            "Expected save failure."
        }
    }

    private final class TestTextView: NSTextView, NSTextViewDelegate {
        let testUndoManager = UndoManager()
        var onChange: ((String) -> Void)?
        var shouldChangeCount = 0
        var didChangeCount = 0

        override var undoManager: UndoManager? {
            testUndoManager
        }

        func observeStorageChanges() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(storageEditingProcessed),
                name: NSTextStorage.didProcessEditingNotification,
                object: textStorage
            )
        }

        override func shouldChangeText(
            in affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            shouldChangeCount += 1
            return super.shouldChangeText(
                in: affectedCharRange,
                replacementString: replacementString
            )
        }

        override func didChangeText() {
            didChangeCount += 1
            super.didChangeText()
        }

        func textDidChange(_ notification: Notification) {
            onChange?(string)
        }

        @objc private func storageEditingProcessed(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage,
                  storage.editedMask.contains(.editedCharacters)
            else {
                return
            }
            onChange?(string)
        }
    }
}

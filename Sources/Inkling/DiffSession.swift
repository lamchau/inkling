import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiffSession {
    enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

    enum UnsavedChangesReason {
        case replacing(DiffSide?)
        case closing
    }

    struct SaveOutcome: Equatable {
        let saved: [DiffSide]
        let failed: [DiffSide]

        var succeeded: Bool {
            failed.isEmpty
        }
    }

    typealias LoadFile = (URL) throws -> LoadedTextFile
    typealias SaveFile = (String, URL) throws -> Void
    typealias DecisionProvider = @MainActor (
        [DiffSide],
        UnsavedChangesReason
    ) -> UnsavedChangesDecision

    private let loadFile: LoadFile
    private let saveFile: SaveFile
    private let decisionProvider: DecisionProvider
    private var refreshTask: Task<Void, Never>?
    private var refreshRevision = 0
    private weak var leftEditor: NSTextView?
    private weak var rightEditor: NSTextView?
    let settings: AppSettings

    init(
        settings: AppSettings = AppSettings(),
        loadFile: @escaping LoadFile = { try TextFileService().load($0) },
        saveFile: @escaping SaveFile = { try TextFileService().save($0, to: $1) },
        decisionProvider: @escaping DecisionProvider = DiffSession.presentUnsavedChangesAlert
    ) {
        self.settings = settings
        self.loadFile = loadFile
        self.saveFile = saveFile
        self.decisionProvider = decisionProvider
    }

    var leftURL: URL?
    var rightURL: URL?
    private var leftSavedText = ""
    private var rightSavedText = ""
    var leftText = "" {
        didSet {
            guard leftText != oldValue else { return }
            documentRevision += 1
            scheduleRefresh()
        }
    }
    var rightText = "" {
        didSet {
            guard rightText != oldValue else { return }
            documentRevision += 1
            scheduleRefresh()
        }
    }
    var ignoreWhitespace = false {
        didSet { scheduleRefresh() }
    }
    var result = DiffResult.empty
    var currentChangeIndex: Int?
    var leftNavigationOffset = 0
    var rightNavigationOffset = 0
    var navigationRevision = 0
    private(set) var documentRevision = 0
    var focusedSide: DiffSide?
    var errorMessage: String?
    var statusMessage = L10n.string("Choose 2 text files to begin.")

    var canSave: Bool {
        isDirty(.left) || isDirty(.right)
    }

    var canSaveFocusedSide: Bool {
        focusedSide.map(isDirty) ?? false
    }

    var hasBothFiles: Bool {
        leftURL != nil && rightURL != nil
    }

    var leftIsDirty: Bool {
        isDirty(.left)
    }

    var rightIsDirty: Bool {
        isDirty(.right)
    }

    var currentChange: DiffChange? {
        guard let currentChangeIndex,
              result.changes.indices.contains(currentChangeIndex)
        else {
            return nil
        }
        return result.changes[currentChangeIndex]
    }

    var currentHunk: DiffHunk? {
        guard let currentChange,
              result.hunks.indices.contains(currentChange.hunkID)
        else {
            return nil
        }
        return result.hunks[currentChange.hunkID]
    }

    func chooseFile(for side: DiffSide) {
        let panel = NSOpenPanel()
        switch (settings.comparisonLayout, side) {
        case (.sideBySide, .left):
            panel.title = L10n.string("Choose Left File")
        case (.sideBySide, .right):
            panel.title = L10n.string("Choose Right File")
        case (.topAndBottom, .left):
            panel.title = L10n.string("Choose Top File")
        case (.topAndBottom, .right):
            panel.title = L10n.string("Choose Bottom File")
        }
        panel.prompt = L10n.string("Choose")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url, for: side)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose 2 Files to Compare")
        panel.message = L10n.string("Select exactly 2 text files.")
        panel.prompt = L10n.string("Compare")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        openComparison(panel.urls)
    }

    func openDroppedFiles(_ urls: [URL], on side: DiffSide? = nil) {
        if urls.count == 2, side == nil {
            openComparison(urls)
            return
        }
        guard urls.count == 1, let url = urls.first else {
            present(InklingError.requiresTwoFiles)
            return
        }
        if let side {
            load(url, for: side)
        } else if leftURL == nil {
            load(url, for: .left)
        } else {
            load(url, for: .right)
        }
    }

    func load(_ url: URL, for side: DiffSide) {
        do {
            let loaded = try loadFile(url)
            let otherURL = side == .left ? rightURL : leftURL
            guard loaded.url != otherURL else {
                throw InklingError.sameFile
            }
            guard confirmReplacement(of: [side], reason: .replacing(side)) else {
                return
            }
            switch side {
            case .left:
                leftURL = loaded.url
                leftText = loaded.text
                leftSavedText = loaded.text
            case .right:
                rightURL = loaded.url
                rightText = loaded.text
                rightSavedText = loaded.text
            }
            clearUndoHistory(for: side)
            statusMessage = L10n.string("Loaded \(loaded.url.lastPathComponent).")
        } catch {
            present(error)
        }
    }

    private func openComparison(_ urls: [URL]) {
        guard urls.count == 2 else {
            present(InklingError.requiresTwoFiles)
            return
        }
        do {
            let left = try loadFile(urls[0])
            let right = try loadFile(urls[1])
            guard left.url != right.url else {
                throw InklingError.sameFile
            }
            guard confirmReplacement(
                of: [.left, .right],
                reason: .replacing(nil)
            ) else {
                return
            }
            leftURL = left.url
            rightURL = right.url
            leftText = left.text
            rightText = right.text
            leftSavedText = left.text
            rightSavedText = right.text
            clearUndoHistory(for: .left)
            clearUndoHistory(for: .right)
            statusMessage = L10n.string(
                "Comparing \(left.url.lastPathComponent) and \(right.url.lastPathComponent)."
            )
        } catch {
            present(error)
        }
    }

    @discardableResult
    func saveFocusedSide() -> SaveOutcome {
        guard let focusedSide else {
            statusMessage = L10n.string("Choose an editor before saving.")
            return SaveOutcome(saved: [], failed: [])
        }
        return save(focusedSide)
    }

    @discardableResult
    func save(_ side: DiffSide) -> SaveOutcome {
        save([side])
    }

    @discardableResult
    func saveBoth() -> SaveOutcome {
        save([.left, .right])
    }

    func requestWindowClose() -> Bool {
        let dirtySides = dirtySides(in: [.left, .right])
        guard !dirtySides.isEmpty else { return true }

        switch decisionProvider(dirtySides, .closing) {
        case .save:
            return save(dirtySides).succeeded
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func nextChange() {
        navigate(by: 1)
    }

    func previousChange() {
        navigate(by: -1)
    }

    func registerEditor(_ editor: NSTextView?, for side: DiffSide) {
        switch side {
        case .left:
            leftEditor = editor
        case .right:
            rightEditor = editor
        }
        editor?.undoManager?.removeAllActions()
    }

    func copyBlockActionTitle(from source: DiffSide) -> String {
        let destination = opposite(of: source)
        let direction: String
        switch (settings.comparisonLayout, source) {
        case (.sideBySide, .left):
            direction = L10n.string("Left to Right")
        case (.sideBySide, .right):
            direction = L10n.string("Right to Left")
        case (.topAndBottom, .left):
            direction = L10n.string("Top to Bottom")
        case (.topAndBottom, .right):
            direction = L10n.string("Bottom to Top")
        }
        guard let filename = url(for: destination)?.lastPathComponent else {
            return L10n.string("Copy Block \(direction)")
        }
        return L10n.string("Copy Block \(direction) — \(filename)")
    }

    func copyBlockHelp(from source: DiffSide) -> String {
        L10n.string("Copy Block \(copyBlockRoute(from: source))")
    }

    func copyCurrentBlock(from source: DiffSide) {
        let route = copyBlockRoute(from: source)
        guard result.documentRevision == documentRevision else {
            statusMessage = L10n.string(
                "Copy Block skipped: \(route); comparison is out of date."
            )
            present(InklingError.staleDiff)
            return
        }
        guard let hunk = currentHunk else { return }
        let destination = opposite(of: source)
        let sourceText = text(for: source)
        let targetText = text(for: destination)
        let sourceRange = source == .left ? hunk.leftRange : hunk.rightRange
        let targetRange = source == .left ? hunk.rightRange : hunk.leftRange
        guard let replacement = Self.replacement(
            sourceText: sourceText,
            sourceLineRange: sourceRange,
            targetText: targetText,
            targetLineRange: targetRange
        ) else {
            statusMessage = L10n.string(
                "Copy Block skipped: \(route); source or destination range is invalid."
            )
            return
        }
        guard let sourceEditor = editor(for: source),
              let targetEditor = editor(for: destination),
              sourceEditor.string == sourceText,
              targetEditor.string == targetText,
              let textStorage = targetEditor.textStorage,
              NSMaxRange(replacement.range) <= textStorage.length
        else {
            statusMessage = L10n.string(
                "Copy Block skipped: \(route); an editor is out of date."
            )
            return
        }
        guard replacement.result != targetText else {
            statusMessage = L10n.string("Copy Block made no changes: \(route).")
            return
        }
        guard let undoManager = targetEditor.undoManager else {
            statusMessage = L10n.string(
                "Copy Block skipped: \(route); undo is unavailable."
            )
            return
        }
        guard targetEditor.shouldChangeText(
            in: replacement.range,
            replacementString: replacement.text
        ) else {
            statusMessage = L10n.string("Copy Block was not allowed: \(route).")
            return
        }
        targetEditor.breakUndoCoalescing()
        targetEditor.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
        targetEditor.didChangeText()
        if text(for: destination) != targetEditor.string {
            setText(targetEditor.string, for: destination)
        }
        undoManager.setActionName(L10n.string("Copy Block"))
        undoManager.endUndoGrouping()
        targetEditor.breakUndoCoalescing()

        statusMessage = L10n.string("Copy Block completed: \(route).")
    }

    func swapSides() {
        swap(&leftURL, &rightURL)
        swap(&leftText, &rightText)
        swap(&leftSavedText, &rightSavedText)
        currentChangeIndex = nil
        statusMessage = L10n.string("Swapped sides.")
        refreshImmediately()
    }

    func refreshImmediately() {
        refreshTask?.cancel()
        refreshRevision += 1
        let refreshRevision = refreshRevision
        let documentRevision = documentRevision
        let leftText = leftText
        let rightText = rightText
        let ignoreWhitespace = ignoreWhitespace
        let algorithm = settings.algorithm
        refreshTask = Task {
            let computed = await Task.detached(priority: .userInitiated) {
                DiffEngine.compare(
                    left: leftText,
                    right: rightText,
                    ignoreWhitespace: ignoreWhitespace,
                    algorithm: algorithm
                )
            }.value
            guard !Task.isCancelled else { return }
            guard refreshRevision == self.refreshRevision,
                  documentRevision == self.documentRevision
            else {
                return
            }
            result = computed.stamped(with: documentRevision)
            reconcileNavigation()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshRevision += 1
        let refreshRevision = refreshRevision
        let documentRevision = documentRevision
        guard hasBothFiles else {
            result = .empty.stamped(with: documentRevision)
            return
        }
        let leftText = leftText
        let rightText = rightText
        let ignoreWhitespace = ignoreWhitespace
        let algorithm = settings.algorithm
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let computed = await Task.detached(priority: .userInitiated) {
                DiffEngine.compare(
                    left: leftText,
                    right: rightText,
                    ignoreWhitespace: ignoreWhitespace,
                    algorithm: algorithm
                )
            }.value
            guard !Task.isCancelled else { return }
            guard refreshRevision == self.refreshRevision,
                  documentRevision == self.documentRevision
            else {
                return
            }
            result = computed.stamped(with: documentRevision)
            reconcileNavigation()
        }
    }

    private func navigate(by delta: Int) {
        guard !result.changes.isEmpty else { return }
        let current = currentChangeIndex ?? (delta > 0 ? -1 : 0)
        currentChangeIndex = (current + delta + result.changes.count) % result.changes.count
        revealCurrentChange()
    }

    private func reconcileNavigation() {
        if result.changes.isEmpty {
            currentChangeIndex = nil
            statusMessage = L10n.string("Files are identical.")
        } else {
            if let currentChangeIndex {
                self.currentChangeIndex = min(
                    currentChangeIndex,
                    result.changes.count - 1
                )
            }
            let count = result.changes.count
            statusMessage = count == 1
                ? L10n.string("1 change.")
                : L10n.string("\(count) changes.")
        }
    }

    private func revealCurrentChange() {
        guard let currentChange else { return }
        leftNavigationOffset = currentChange.leftNavigationOffset
        rightNavigationOffset = currentChange.rightNavigationOffset
        navigationRevision += 1
    }

    private func isDirty(_ side: DiffSide) -> Bool {
        switch side {
        case .left:
            leftURL != nil && leftText != leftSavedText
        case .right:
            rightURL != nil && rightText != rightSavedText
        }
    }

    private func dirtySides(in sides: [DiffSide]) -> [DiffSide] {
        sides.filter(isDirty)
    }

    private func confirmReplacement(
        of sides: [DiffSide],
        reason: UnsavedChangesReason
    ) -> Bool {
        let dirtySides = dirtySides(in: sides)
        guard !dirtySides.isEmpty else { return true }

        switch decisionProvider(dirtySides, reason) {
        case .save:
            return save(dirtySides).succeeded
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func save(_ sides: [DiffSide]) -> SaveOutcome {
        let dirtySides = dirtySides(in: sides)
        guard !dirtySides.isEmpty else {
            statusMessage = L10n.string("No changes to save.")
            return SaveOutcome(saved: [], failed: [])
        }

        var saved: [DiffSide] = []
        var failed: [DiffSide] = []
        var errors: [String] = []
        errorMessage = nil
        for side in dirtySides {
            guard let url = url(for: side) else { continue }
            do {
                let text = text(for: side)
                try saveFile(text, url)
                setSavedText(text, for: side)
                saved.append(side)
            } catch {
                failed.append(side)
                errors.append(error.localizedDescription)
            }
        }

        let outcome = SaveOutcome(saved: saved, failed: failed)
        updateSaveStatus(outcome)
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
        return outcome
    }

    private func url(for side: DiffSide) -> URL? {
        side == .left ? leftURL : rightURL
    }

    private func text(for side: DiffSide) -> String {
        side == .left ? leftText : rightText
    }

    private func editor(for side: DiffSide) -> NSTextView? {
        side == .left ? leftEditor : rightEditor
    }

    private func opposite(of side: DiffSide) -> DiffSide {
        side == .left ? .right : .left
    }

    private func copyBlockRoute(from source: DiffSide) -> String {
        let destination = opposite(of: source)
        let direction: String
        switch (settings.comparisonLayout, source) {
        case (.sideBySide, .left):
            direction = L10n.string("left → right")
        case (.sideBySide, .right):
            direction = L10n.string("right → left")
        case (.topAndBottom, .left):
            direction = L10n.string("top → bottom")
        case (.topAndBottom, .right):
            direction = L10n.string("bottom → top")
        }
        guard let filename = url(for: destination)?.lastPathComponent else {
            return direction
        }
        return L10n.string("\(direction) into \(filename)")
    }

    private func setText(_ text: String, for side: DiffSide) {
        switch side {
        case .left:
            leftText = text
        case .right:
            rightText = text
        }
    }

    private func clearUndoHistory(for side: DiffSide) {
        editor(for: side)?.undoManager?.removeAllActions()
    }

    private struct TextReplacement {
        let range: NSRange
        let text: String
        let result: String
    }

    private static func replacement(
        sourceText: String,
        sourceLineRange: Range<Int>,
        targetText: String,
        targetLineRange: Range<Int>
    ) -> TextReplacement? {
        let sourceLines = sourceText.components(separatedBy: "\n")
        let targetLines = targetText.components(separatedBy: "\n")
        guard sourceLineRange.lowerBound >= 0,
              sourceLineRange.upperBound <= sourceLines.count,
              targetLineRange.lowerBound >= 0,
              targetLineRange.upperBound <= targetLines.count
        else {
            return nil
        }

        var resultLines = targetLines
        resultLines.replaceSubrange(
            targetLineRange,
            with: sourceLines[sourceLineRange]
        )
        let result = resultLines.joined(separator: "\n")
        let old = targetText as NSString
        let new = result as NSString
        var prefixLength = 0
        while prefixLength < old.length,
              prefixLength < new.length,
              old.character(at: prefixLength) == new.character(at: prefixLength)
        {
            prefixLength += 1
        }
        var suffixLength = 0
        while suffixLength < old.length - prefixLength,
              suffixLength < new.length - prefixLength,
              old.character(at: old.length - suffixLength - 1)
                == new.character(at: new.length - suffixLength - 1)
        {
            suffixLength += 1
        }
        let range = NSRange(
            location: prefixLength,
            length: old.length - prefixLength - suffixLength
        )
        let replacementRange = NSRange(
            location: prefixLength,
            length: new.length - prefixLength - suffixLength
        )
        guard NSMaxRange(range) <= old.length,
              NSMaxRange(replacementRange) <= new.length
        else {
            return nil
        }
        let replacementText = new.substring(with: replacementRange)
        guard old.replacingCharacters(in: range, with: replacementText) == result else {
            return nil
        }
        return TextReplacement(range: range, text: replacementText, result: result)
    }

    private func setSavedText(_ text: String, for side: DiffSide) {
        switch side {
        case .left:
            leftSavedText = text
        case .right:
            rightSavedText = text
        }
    }

    private func updateSaveStatus(_ outcome: SaveOutcome) {
        let savedNames = sideNames(outcome.saved)
        let failedNames = sideNames(outcome.failed)
        if failedNames.isEmpty {
            statusMessage = L10n.string("Saved \(savedNames).")
        } else if savedNames.isEmpty {
            statusMessage = L10n.string("Could not save \(failedNames).")
        } else {
            statusMessage = L10n.string(
                "Saved \(savedNames); could not save \(failedNames)."
            )
        }
    }

    private func sideNames(_ sides: [DiffSide]) -> String {
        let names = [DiffSide.left, .right]
            .filter(sides.contains)
            .map {
                switch (settings.comparisonLayout, $0) {
                case (.sideBySide, .left):
                    L10n.string("left")
                case (.sideBySide, .right):
                    L10n.string("right")
                case (.topAndBottom, .left):
                    L10n.string("top")
                case (.topAndBottom, .right):
                    L10n.string("bottom")
                }
            }
        return names.joined(separator: L10n.string(" and "))
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private static func presentUnsavedChangesAlert(
        sides: [DiffSide],
        reason: UnsavedChangesReason
    ) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch reason {
        case let .replacing(side):
            if let side {
                let sideName = side == .left
                    ? L10n.string("left")
                    : L10n.string("right")
                alert.messageText = L10n.string(
                    "Save changes to the \(sideName) file?"
                )
            } else {
                alert.messageText = L10n.string(
                    "Save changes before replacing both files?"
                )
            }
            alert.informativeText = L10n.string(
                "Unsaved changes will be lost if you discard them."
            )
        case .closing:
            alert.messageText = L10n.string("Save changes before closing?")
            alert.informativeText = L10n.string(
                "Unsaved changes will be lost if you discard them."
            )
        }
        alert.addButton(withTitle: L10n.string("Save"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.addButton(withTitle: L10n.string("Discard"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

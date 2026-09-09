import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiffSession {
    private let files = TextFileService()
    private var refreshTask: Task<Void, Never>?
    let settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    var leftURL: URL?
    var rightURL: URL?
    var leftText = "" {
        didSet { scheduleRefresh() }
    }
    var rightText = "" {
        didSet { scheduleRefresh() }
    }
    var ignoreWhitespace = false {
        didSet { scheduleRefresh() }
    }
    var result = DiffResult.empty
    var currentHunkIndex: Int?
    var leftNavigationOffset = 0
    var rightNavigationOffset = 0
    var navigationRevision = 0
    var errorMessage: String?
    var statusMessage = "Choose two text files to begin."

    var canSave: Bool {
        leftURL != nil || rightURL != nil
    }

    var hasBothFiles: Bool {
        leftURL != nil && rightURL != nil
    }

    var currentHunk: DiffHunk? {
        guard let currentHunkIndex, result.hunks.indices.contains(currentHunkIndex) else {
            return nil
        }
        return result.hunks[currentHunkIndex]
    }

    func chooseFile(for side: DiffSide) {
        let panel = NSOpenPanel()
        panel.title = side == .left ? "Choose Left File" : "Choose Right File"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url, for: side)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose Two Files to Compare"
        panel.message = "Select exactly two text files."
        panel.prompt = "Compare"
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
            let loaded = try files.load(url)
            let otherURL = side == .left ? rightURL : leftURL
            guard loaded.url != otherURL else {
                throw InklingError.sameFile
            }
            switch side {
            case .left:
                leftURL = loaded.url
                leftText = loaded.text
            case .right:
                rightURL = loaded.url
                rightText = loaded.text
            }
            statusMessage = "Loaded \(loaded.url.lastPathComponent)."
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
            let left = try files.load(urls[0])
            let right = try files.load(urls[1])
            guard left.url != right.url else {
                throw InklingError.sameFile
            }
            leftURL = left.url
            rightURL = right.url
            leftText = left.text
            rightText = right.text
            statusMessage = "Comparing \(left.url.lastPathComponent) and \(right.url.lastPathComponent)."
        } catch {
            present(error)
        }
    }

    func saveBoth() {
        do {
            if let leftURL {
                try files.save(leftText, to: leftURL)
            }
            if let rightURL {
                try files.save(rightText, to: rightURL)
            }
            statusMessage = "Saved."
        } catch {
            present(error)
        }
    }

    func nextHunk() {
        navigate(by: 1)
    }

    func previousHunk() {
        navigate(by: -1)
    }

    func applyCurrentHunk(from source: DiffSide) {
        guard let hunk = currentHunk else { return }
        var leftLines = leftText.components(separatedBy: "\n")
        var rightLines = rightText.components(separatedBy: "\n")
        switch source {
        case .left:
            rightLines.replaceSubrange(hunk.rightRange, with: leftLines[hunk.leftRange])
            rightText = rightLines.joined(separator: "\n")
            statusMessage = "Copied change from left to right."
        case .right:
            leftLines.replaceSubrange(hunk.leftRange, with: rightLines[hunk.rightRange])
            leftText = leftLines.joined(separator: "\n")
            statusMessage = "Copied change from right to left."
        }
    }

    func swapSides() {
        swap(&leftURL, &rightURL)
        swap(&leftText, &rightText)
        currentHunkIndex = nil
        statusMessage = "Swapped sides."
        refreshImmediately()
    }

    func refreshImmediately() {
        refreshTask?.cancel()
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
            result = computed
            reconcileNavigation()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard hasBothFiles else {
            result = .empty
            return
        }
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let leftText = leftText
            let rightText = rightText
            let ignoreWhitespace = ignoreWhitespace
            let algorithm = settings.algorithm
            let computed = await Task.detached(priority: .userInitiated) {
                DiffEngine.compare(
                    left: leftText,
                    right: rightText,
                    ignoreWhitespace: ignoreWhitespace,
                    algorithm: algorithm
                )
            }.value
            guard !Task.isCancelled else { return }
            result = computed
            reconcileNavigation()
        }
    }

    private func navigate(by delta: Int) {
        guard !result.hunks.isEmpty else { return }
        let current = currentHunkIndex ?? (delta > 0 ? -1 : 0)
        currentHunkIndex = (current + delta + result.hunks.count) % result.hunks.count
        revealCurrentHunk()
    }

    private func reconcileNavigation() {
        if result.hunks.isEmpty {
            currentHunkIndex = nil
            statusMessage = "Files are identical."
        } else {
            if let currentHunkIndex {
                self.currentHunkIndex = min(currentHunkIndex, result.hunks.count - 1)
            }
            statusMessage = "\(result.hunks.count) change\(result.hunks.count == 1 ? "" : "s")."
            revealCurrentHunk()
        }
    }

    private func revealCurrentHunk() {
        guard let currentHunk else { return }
        leftNavigationOffset = currentHunk.leftNavigationOffset
        rightNavigationOffset = currentHunk.rightNavigationOffset
        navigationRevision += 1
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

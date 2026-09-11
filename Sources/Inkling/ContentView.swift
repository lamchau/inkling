import AppKit
import InklingDiff
import SwiftUI

enum EditorLayout {
    static let railThickness: CGFloat = 52
    static let railWidth = railThickness
    static let railHeight = railThickness
    static let dividerWidth: CGFloat = 1

    static func paneExtent(totalExtent: CGFloat) -> CGFloat {
        max(0, (totalExtent - railThickness - dividerWidth * 2) / 2)
    }

    static func paneWidth(totalWidth: CGFloat) -> CGFloat {
        paneExtent(totalExtent: totalWidth)
    }

    static func paneHeight(totalHeight: CGFloat) -> CGFloat {
        paneExtent(totalExtent: totalHeight)
    }
}

struct ContentView: View {
    @Environment(DiffSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var sharedScrollOrigin = CGPoint.zero
    @State private var sharedCaret: CaretPosition?
    @State private var showsPalette = false
    @State private var targetedDropSide: DiffSide?

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            header
            Divider()
            if session.hasBothFiles {
                editors
            } else {
                welcome
            }
            Divider()
            statusBar
        }
        .background(.background)
        .background {
            WindowCloseGuard {
                session.requestWindowClose()
            }
        }
        .onChange(of: settings.algorithm) {
            session.refreshImmediately()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 2 else { return false }
            session.openDroppedFiles(urls)
            return true
        }
        .alert(
            "Inkling",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            fileButton(side: .left, url: session.leftURL)
                .frame(maxWidth: .infinity, alignment: .leading)

            paletteButton
            layoutPicker

            fileButton(side: .right, url: session.rightURL)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var editors: some View {
        GeometryReader { proxy in
            if settings.comparisonLayout == .sideBySide {
                let paneWidth = EditorLayout.paneWidth(totalWidth: proxy.size.width)

                HSplitView {
                    editor(for: .left)
                        .frame(
                            minWidth: paneWidth,
                            idealWidth: paneWidth,
                            maxWidth: paneWidth
                        )
                    centerRail
                        .frame(
                            minWidth: EditorLayout.railWidth,
                            idealWidth: EditorLayout.railWidth,
                            maxWidth: EditorLayout.railWidth
                        )
                    editor(for: .right)
                        .frame(
                            minWidth: paneWidth,
                            idealWidth: paneWidth,
                            maxWidth: paneWidth
                        )
                }
            } else {
                let paneHeight = EditorLayout.paneHeight(totalHeight: proxy.size.height)

                VSplitView {
                    editor(for: .left)
                        .frame(
                            minHeight: paneHeight,
                            idealHeight: paneHeight,
                            maxHeight: paneHeight
                        )
                    centerRail
                        .frame(
                            minHeight: EditorLayout.railHeight,
                            idealHeight: EditorLayout.railHeight,
                            maxHeight: EditorLayout.railHeight
                        )
                    editor(for: .right)
                        .frame(
                            minHeight: paneHeight,
                            idealHeight: paneHeight,
                            maxHeight: paneHeight
                        )
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Label(
                L10n.string("Compare 2 Files"),
                systemImage: "rectangle.split.2x1"
            )
            .font(.title2.weight(.semibold))

            Text(
                L10n.string(
                    "Drop 2 files, or choose each side independently. Inkling never saves changes automatically."
                )
            )
            .foregroundStyle(.secondary)

            emptyDropWells
                .frame(
                    maxWidth: 760,
                    maxHeight: settings.comparisonLayout == .sideBySide ? 280 : 420
                )

            Button(L10n.string("Choose 2 Files…")) {
                session.chooseFiles()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyDropWell(for side: DiffSide) -> some View {
        let isTargeted = targetedDropSide == side
        let url = side == .left ? session.leftURL : session.rightURL

        return VStack(spacing: 12) {
            Image(systemName: url == nil ? "arrow.down.doc" : "doc.text.fill")
                .font(.system(size: 34))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text(fileTitle(for: side))
                .font(.headline)

            Text(url?.lastPathComponent ?? L10n.string("Choose or drop a file"))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(L10n.string("Choose File…")) {
                session.chooseFile(for: side)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            isTargeted
                ? Color.accentColor.opacity(0.15)
                : Color.secondary.opacity(0.04)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [9, 7])
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .dropDestination(
            for: URL.self,
            action: { urls, _ in
                guard urls.count == 1 || urls.count == 2 else { return false }
                if urls.count == 2 {
                    session.openDroppedFiles(urls)
                } else {
                    session.openDroppedFiles(urls, on: side)
                }
                return true
            },
            isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) {
                    if targeted {
                        targetedDropSide = side
                    } else if targetedDropSide == side {
                        targetedDropSide = nil
                    }
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fileTitle(for: side))
    }

    @ViewBuilder
    private var emptyDropWells: some View {
        if settings.comparisonLayout == .sideBySide {
            HStack(spacing: 16) {
                emptyDropWell(for: .left)
                emptyDropWell(for: .right)
            }
        } else {
            VStack(spacing: 16) {
                emptyDropWell(for: .left)
                emptyDropWell(for: .right)
            }
        }
    }

    private var layoutPicker: some View {
        Picker(
            L10n.string("Comparison layout"),
            selection: Binding(
                get: { settings.comparisonLayout },
                set: { settings.comparisonLayout = $0 }
            )
        ) {
            ForEach(ComparisonLayout.allCases) { layout in
                Label(layout.title, systemImage: layout.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(layout)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 72)
        .help(settings.comparisonLayout.title)
        .accessibilityLabel(L10n.string("Comparison layout"))
    }

    private var paletteButton: some View {
        Button {
            showsPalette.toggle()
        } label: {
            HStack(spacing: 5) {
                HStack(spacing: -2) {
                    ForEach(ChangeCategory.allCases) { category in
                        Circle()
                            .fill(Color(nsColor: settings.color(for: category)))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.background, lineWidth: 1))
                    }
                }
                Text(L10n.string("\(session.result.changes.count) changes"))
                    .font(.caption.monospacedDigit())
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            ChangePaletteView(
                result: session.result,
                currentChange: session.currentChangeIndex,
                settings: settings,
                highlightStyle: Binding(
                    get: { settings.highlightStyle },
                    set: { settings.highlightStyle = $0 }
                )
            )
        }
    }

    private var hunkLabel: String {
        guard let index = session.currentChangeIndex else {
            return L10n.string("\(session.result.changes.count) changes")
        }
        return L10n.string("\(index + 1) of \(session.result.changes.count)")
    }

    private var statusBar: some View {
        HStack {
            Toggle(L10n.string("Ignore whitespace"), isOn: Binding(
                get: { session.ignoreWhitespace },
                set: { session.ignoreWhitespace = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle(L10n.string("Sync scroll"), isOn: Binding(
                get: { settings.syncScrolling },
                set: { settings.syncScrolling = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle(L10n.string("Sync caret"), isOn: Binding(
                get: { settings.syncCaret },
                set: { settings.syncCaret = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle(L10n.string("Line numbers"), isOn: Binding(
                get: { settings.showLineNumbers },
                set: { settings.showLineNumbers = $0 }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            Text(session.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .trailing)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private var centerRail: some View {
        if settings.comparisonLayout == .sideBySide {
            verticalCenterRail
        } else {
            horizontalCenterRail
        }
    }

    private var verticalCenterRail: some View {
        VStack(spacing: 8) {
            Button {
                session.previousChange()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help(
                L10n.string(
                    "Previous change (\(settings.shortcuts.title.components(separatedBy: " / ").first ?? ""))"
                )
            )
            .disabled(session.result.changes.isEmpty)

            Text(hunkLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                session.nextChange()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help(
                L10n.string(
                    "Next change (\(settings.shortcuts.title.components(separatedBy: " / ").last ?? ""))"
                )
            )
            .disabled(session.result.changes.isEmpty)

            Divider()
                .padding(.vertical, 4)

            Button {
                session.copyCurrentBlock(from: .right)
            } label: {
                Image(systemName: "arrow.left")
            }
            .help(session.copyBlockHelp(from: .right))
            .disabled(session.currentHunk == nil)

            Button {
                session.copyCurrentBlock(from: .left)
            } label: {
                Image(systemName: "arrow.right")
            }
            .help(session.copyBlockHelp(from: .left))
            .disabled(session.currentHunk == nil)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("Settings"))
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var horizontalCenterRail: some View {
        HStack(spacing: 8) {
            Button {
                session.previousChange()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(
                L10n.string(
                    "Previous change (\(settings.shortcuts.title.components(separatedBy: " / ").first ?? ""))"
                )
            )
            .disabled(session.result.changes.isEmpty)

            Text(hunkLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                session.nextChange()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(
                L10n.string(
                    "Next change (\(settings.shortcuts.title.components(separatedBy: " / ").last ?? ""))"
                )
            )
            .disabled(session.result.changes.isEmpty)

            Divider()
                .padding(.horizontal, 4)

            Button {
                session.copyCurrentBlock(from: .right)
            } label: {
                Image(systemName: "arrow.up")
            }
            .help(session.copyBlockHelp(from: .right))
            .disabled(session.currentHunk == nil)

            Button {
                session.copyCurrentBlock(from: .left)
            } label: {
                Image(systemName: "arrow.down")
            }
            .help(session.copyBlockHelp(from: .left))
            .disabled(session.currentHunk == nil)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("Settings"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func editor(for side: DiffSide) -> some View {
        ZStack {
            DiffTextView(
                text: Binding(
                    get: { side == .left ? session.leftText : session.rightText },
                    set: {
                        if side == .left {
                            if session.leftText != $0 {
                                session.leftText = $0
                            }
                        } else {
                            if session.rightText != $0 {
                                session.rightText = $0
                            }
                        }
                    }
                ),
                highlights: side == .left
                    ? session.result.leftHighlights
                    : session.result.rightHighlights,
                currentChangeRange: currentRange(for: side),
                navigationOffset: side == .left
                    ? session.leftNavigationOffset
                    : session.rightNavigationOffset,
                navigationRevision: session.navigationRevision,
                side: side,
                showLineNumbers: settings.showLineNumbers,
                highlightStyle: settings.highlightStyle,
                palette: settings.palette,
                syncScrolling: settings.syncScrolling,
                syncCaret: settings.syncCaret,
                sharedScrollOrigin: $sharedScrollOrigin,
                sharedCaret: $sharedCaret,
                isDropTargeted: Binding(
                    get: { targetedDropSide == side },
                    set: { isTargeted in
                        withAnimation(.easeOut(duration: 0.12)) {
                            if isTargeted {
                                targetedDropSide = side
                            } else if targetedDropSide == side {
                                targetedDropSide = nil
                            }
                        }
                    }
                ),
                onDrop: { urls in
                    guard urls.count == 1 else { return false }
                    session.openDroppedFiles(urls, on: side)
                    return true
                },
                onEditorChange: { textView in
                    session.registerEditor(textView, for: side)
                },
                onFocus: {
                    session.focusedSide = side
                }
            )

            if targetedDropSide == side {
                dropZone(for: side)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(editorTitle(for: side))
    }

    private func dropZone(for side: DiffSide) -> some View {
        ZStack {
            Color.accentColor.opacity(0.15)

            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, dash: [9, 7])
                )

            Label(
                dropTitle(for: side),
                systemImage: "arrow.down.doc"
            )
            .font(.title2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentRange(for side: DiffSide) -> NSRange? {
        guard let change = session.currentChange else { return nil }
        switch side {
        case .left:
            return change.leftRange
                ?? NSRange(location: change.leftNavigationOffset, length: 0)
        case .right:
            return change.rightRange
                ?? NSRange(location: change.rightNavigationOffset, length: 0)
        }
    }

    private func fileButton(side: DiffSide, url: URL?) -> some View {
        Button {
            session.chooseFile(for: side)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(
                    url?.lastPathComponent
                        ?? chooseFileTitle(for: side)
                )
                    .lineLimit(1)
                if (side == .left ? session.leftIsDirty : session.rightIsDirty) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(L10n.string("Unsaved changes"))
                }
            }
        }
        .buttonStyle(.borderless)
        .help(url?.path ?? L10n.string("Choose a file"))
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1 else { return false }
            session.openDroppedFiles(urls, on: side)
            return true
        }
    }

    private func fileTitle(for side: DiffSide) -> String {
        switch (settings.comparisonLayout, side) {
        case (.sideBySide, .left):
            L10n.string("Left file")
        case (.sideBySide, .right):
            L10n.string("Right file")
        case (.topAndBottom, .left):
            L10n.string("Top file")
        case (.topAndBottom, .right):
            L10n.string("Bottom file")
        }
    }

    private func chooseFileTitle(for side: DiffSide) -> String {
        switch (settings.comparisonLayout, side) {
        case (.sideBySide, .left):
            L10n.string("Choose left file…")
        case (.sideBySide, .right):
            L10n.string("Choose right file…")
        case (.topAndBottom, .left):
            L10n.string("Choose top file…")
        case (.topAndBottom, .right):
            L10n.string("Choose bottom file…")
        }
    }

    private func editorTitle(for side: DiffSide) -> String {
        switch (settings.comparisonLayout, side) {
        case (.sideBySide, .left):
            L10n.string("Left file editor")
        case (.sideBySide, .right):
            L10n.string("Right file editor")
        case (.topAndBottom, .left):
            L10n.string("Top file editor")
        case (.topAndBottom, .right):
            L10n.string("Bottom file editor")
        }
    }

    private func dropTitle(for side: DiffSide) -> String {
        switch (settings.comparisonLayout, side) {
        case (.sideBySide, .left):
            L10n.string("Drop file on left")
        case (.sideBySide, .right):
            L10n.string("Drop file on right")
        case (.topAndBottom, .left):
            L10n.string("Drop file on top")
        case (.topAndBottom, .right):
            L10n.string("Drop file on bottom")
        }
    }

    private struct WindowCloseGuard: NSViewRepresentable {
        let shouldClose: () -> Bool

        func makeCoordinator() -> Coordinator {
            Coordinator(shouldClose: shouldClose)
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.hostView = view
            DispatchQueue.main.async {
                context.coordinator.install()
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.shouldClose = shouldClose
            context.coordinator.install()
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.uninstall()
        }

        @MainActor
        final class Coordinator: NSObject, NSWindowDelegate {
            var shouldClose: () -> Bool
            weak var hostView: NSView?
            weak var window: NSWindow?
            nonisolated(unsafe) var previousDelegate: (any NSWindowDelegate)?

            init(shouldClose: @escaping () -> Bool) {
                self.shouldClose = shouldClose
            }

            func install() {
                guard let candidate = hostView?.window else { return }
                if candidate === window {
                    if candidate.delegate !== self {
                        previousDelegate = candidate.delegate
                        candidate.delegate = self
                    }
                    return
                }
                uninstall()
                window = candidate
                previousDelegate = candidate.delegate
                candidate.delegate = self
            }

            func uninstall() {
                if let window, window.delegate === self {
                    window.delegate = previousDelegate
                }
                window = nil
                previousDelegate = nil
            }

            func windowShouldClose(_ sender: NSWindow) -> Bool {
                guard shouldClose() else { return false }
                return previousDelegate?.windowShouldClose?(sender) ?? true
            }

            override func responds(to selector: Selector!) -> Bool {
                super.responds(to: selector)
                    || previousDelegate?.responds(to: selector) == true
            }

            override func forwardingTarget(for selector: Selector!) -> Any? {
                if previousDelegate?.responds(to: selector) == true {
                    return previousDelegate
                }
                return super.forwardingTarget(for: selector)
            }
        }
    }

    private struct ChangePaletteView: View {
        let result: DiffResult
        let currentChange: Int?
        let settings: AppSettings
        @Binding var highlightStyle: HighlightStyle

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.string("Change Palette"))
                        .font(.headline)
                    Spacer()
                    Text(L10n.string("\(result.changes.count) total"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Picker(L10n.string("Highlight colors"), selection: $highlightStyle) {
                    ForEach(HighlightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                ForEach(ChangeCategory.allCases) { category in
                    HStack {
                        ColorPicker(
                            "",
                            selection: colorBinding(for: category),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 30)
                        Text(category.title)
                        Spacer()
                        Text("\(count(category))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Button(L10n.string("Reset Colors")) {
                    settings.resetPalette()
                }

                if let currentChange {
                    Divider()
                    Text(
                        L10n.string(
                            "Viewing change \(currentChange + 1) of \(result.changes.count)"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 280)
        }

        private func count(_ category: ChangeCategory) -> Int {
            (result.leftHighlights + result.rightHighlights)
                .count { $0.kind.category == category }
        }

        private func colorBinding(for category: ChangeCategory) -> Binding<Color> {
            Binding(
                get: { Color(nsColor: settings.color(for: category)) },
                set: { settings.setColor(NSColor($0), for: category) }
            )
        }
    }
}

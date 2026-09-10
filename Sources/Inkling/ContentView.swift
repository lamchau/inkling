import SwiftUI

enum EditorLayout {
    static let railWidth: CGFloat = 52
    static let dividerWidth: CGFloat = 1

    static func paneWidth(totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - railWidth - dividerWidth * 2) / 2)
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
        .onChange(of: settings.algorithm) {
            session.refreshImmediately()
        }
        .dropDestination(for: URL.self) { urls, _ in
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            fileButton(side: .left, url: session.leftURL)
                .frame(maxWidth: .infinity, alignment: .leading)

            paletteButton

            fileButton(side: .right, url: session.rightURL)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var editors: some View {
        GeometryReader { proxy in
            let paneWidth = EditorLayout.paneWidth(totalWidth: proxy.size.width)

            HSplitView {
                editor(for: .left)
                    .frame(minWidth: paneWidth, idealWidth: paneWidth, maxWidth: paneWidth)
                centerRail
                    .frame(
                        minWidth: EditorLayout.railWidth,
                        idealWidth: EditorLayout.railWidth,
                        maxWidth: EditorLayout.railWidth
                    )
                editor(for: .right)
                    .frame(minWidth: paneWidth, idealWidth: paneWidth, maxWidth: paneWidth)
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Compare Two Files", systemImage: "rectangle.split.2x1")
        } description: {
            Text("Choose or drop two text files. Inkling never saves changes automatically.")
        } actions: {
            Button("Choose Two Files…") {
                session.chooseFiles()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paletteButton: some View {
        Button {
            showsPalette.toggle()
        } label: {
            HStack(spacing: 5) {
                HStack(spacing: -2) {
                    ForEach(ChangeCategory.allCases) { category in
                        Circle()
                            .fill(color(for: category))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.background, lineWidth: 1))
                    }
                }
                Text("\(session.result.changes.count) changes")
                    .font(.caption.monospacedDigit())
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            ChangePaletteView(
                result: session.result,
                currentChange: session.currentChangeIndex,
                highlightStyle: Binding(
                    get: { settings.highlightStyle },
                    set: { settings.highlightStyle = $0 }
                )
            )
        }
    }

    private var hunkLabel: String {
        guard let index = session.currentChangeIndex else {
            return "\(session.result.changes.count) changes"
        }
        return "\(index + 1) of \(session.result.changes.count)"
    }

    private var statusBar: some View {
        HStack {
            Toggle("Ignore whitespace", isOn: Binding(
                get: { session.ignoreWhitespace },
                set: { session.ignoreWhitespace = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle("Sync scroll", isOn: Binding(
                get: { settings.syncScrolling },
                set: { settings.syncScrolling = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle("Sync caret", isOn: Binding(
                get: { settings.syncCaret },
                set: { settings.syncCaret = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle("Line numbers", isOn: Binding(
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

    private var centerRail: some View {
        VStack(spacing: 8) {
            Button {
                session.previousChange()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Previous change (\(settings.shortcuts.title.components(separatedBy: " / ").first ?? ""))")
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
            .help("Next change (\(settings.shortcuts.title.components(separatedBy: " / ").last ?? ""))")
            .disabled(session.result.changes.isEmpty)

            Divider()
                .padding(.vertical, 4)

            Button {
                session.applyCurrentHunk(from: .right)
            } label: {
                Image(systemName: "arrow.left")
            }
            .help("Copy change to left")
            .disabled(session.currentHunk == nil)

            Button {
                session.applyCurrentHunk(from: .left)
            } label: {
                Image(systemName: "arrow.right")
            }
            .help("Copy change to right")
            .disabled(session.currentHunk == nil)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 12)
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
                            session.leftText = $0
                        } else {
                            session.rightText = $0
                        }
                    }
                ),
                highlights: side == .left
                    ? session.result.leftHighlights
                    : session.result.rightHighlights,
                navigationOffset: side == .left
                    ? session.leftNavigationOffset
                    : session.rightNavigationOffset,
                navigationRevision: session.navigationRevision,
                side: side,
                showLineNumbers: settings.showLineNumbers,
                highlightStyle: settings.highlightStyle,
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
                }
            )

            if targetedDropSide == side {
                dropZone(for: side)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(side == .left ? "Left file editor" : "Right file editor")
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
                side == .left ? "Drop file on left" : "Drop file on right",
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

    private func color(for category: ChangeCategory) -> Color {
        switch category {
        case .character: .pink
        case .word: .orange
        case .phrase: .blue
        case .addition: .green
        case .deletion: .red
        }
    }

    private func fileButton(side: DiffSide, url: URL?) -> some View {
        Button {
            session.chooseFile(for: side)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(url?.lastPathComponent ?? (side == .left ? "Choose left file…" : "Choose right file…"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .help(url?.path ?? "Choose a file")
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1 else { return false }
            session.openDroppedFiles(urls, on: side)
            return true
        }
    }

    private struct ChangePaletteView: View {
        let result: DiffResult
        let currentChange: Int?
        @Binding var highlightStyle: HighlightStyle

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Change Palette")
                        .font(.headline)
                    Spacer()
                    Text("\(result.changes.count) total")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Picker("Highlight colors", selection: $highlightStyle) {
                    ForEach(HighlightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                ForEach(ChangeCategory.allCases) { category in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: category))
                            .frame(width: 28, height: 14)
                        Text(category.title)
                        Spacer()
                        Text("\(count(category))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let currentChange {
                    Divider()
                    Text("Viewing change \(currentChange + 1) of \(result.changes.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 250)
        }

        private func count(_ category: ChangeCategory) -> Int {
            (result.leftHighlights + result.rightHighlights)
                .count { $0.kind.category == category }
        }

        private func color(for category: ChangeCategory) -> Color {
            switch category {
            case .character: .pink
            case .word: .orange
            case .phrase: .blue
            case .addition: .green
            case .deletion: .red
            }
        }
    }
}

import AppKit
import SwiftUI
import SwiftData

// MARK: - Manager

@MainActor
final class DictionaryQuickAddManager {
    static let shared = DictionaryQuickAddManager()
    private init() {}

    private var panel: DictionaryQuickAddPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(modelContainer: ModelContainer) {
        isVisible ? hide() : show(modelContainer: modelContainer)
    }

    func show(modelContainer: ModelContainer) {
        guard !isVisible else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        let initialSize = NSSize(width: 500, height: DictionaryQuickAddView.Mode.vocabulary.panelHeight)
        let newPanel = DictionaryQuickAddPanel(manager: self, size: initialSize)

        let view = DictionaryQuickAddView(
            onDismiss: { [weak self] in self?.hide() },
            onResize: { [weak self] height in
                self?.panel?.resize(to: NSSize(width: 500, height: height))
            }
        )
        .modelContainer(modelContainer)

        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let controller = NSHostingController(rootView: AnyView(AccentObserving { view }))
        newPanel.contentView = controller.view
        hostingController = controller
        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        previousApp?.activate(options: .activateIgnoringOtherApps)
        previousApp = nil
    }
}

// MARK: - Panel

class DictionaryQuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private weak var manager: DictionaryQuickAddManager?

    init(manager: DictionaryQuickAddManager, size: NSSize) {
        self.manager = manager
        let origin = DictionaryQuickAddPanel.centeredOrigin(for: size)
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            manager?.hide()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            self?.manager?.hide()
        }
    }

    func resize(to size: NSSize) {
        let currentFrame = frame
        let x = currentFrame.midX - size.width / 2
        let y = currentFrame.maxY - size.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
    }

    private static func centeredOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.midY - size.height / 2 + 60
        return NSPoint(x: x, y: y)
    }
}

// MARK: - View

struct DictionaryQuickAddView: View {
    enum Mode: CaseIterable {
        case vocabulary, replacement

        var label: String {
            switch self {
            case .vocabulary: return "Vocabulary"
            case .replacement: return "Word Replacement"
            }
        }

        var icon: String {
            switch self {
            case .vocabulary: return "character.book.closed.fill"
            case .replacement: return "arrow.2.squarepath"
            }
        }

        var panelHeight: CGFloat {
            switch self {
            case .vocabulary: return 130
            case .replacement: return 164
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyWords: [VocabularyWord]
    @Query private var wordReplacements: [WordReplacement]

    @State private var mode: Mode = .vocabulary
    @State private var wordInput = ""
    @State private var originalInput = ""
    @State private var replacementInput = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case word, original, replacement }

    let onDismiss: () -> Void
    let onResize: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider().overlay(Palette.mtLine)
            inputArea
            if let errorMessage {
                Text(errorMessage)
                    .font(.mono(11))
                    .foregroundStyle(Palette.stateFail)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            Divider().overlay(Palette.mtLine)
            hintBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.mtRaise)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(Palette.mtLine, lineWidth: 1)
        )
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear {
            DispatchQueue.main.async { focusedField = .word }
        }
        .onChange(of: mode) { _, newMode in
            wordInput = ""
            originalInput = ""
            replacementInput = ""
            errorMessage = nil
            DispatchQueue.main.async {
                focusedField = newMode == .vocabulary ? .word : .original
            }
            onResize(newMode.panelHeight)
        }
        .onChange(of: errorMessage) { _, newError in
            let height = mode.panelHeight + (newError != nil ? 24 : 0)
            onResize(height)
        }
    }

    // MARK: - Mode Bar

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(Animation.haloPhaseCrossfade) { mode = m }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(m.label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(mode == m ? Palette.phosphor : Palette.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(mode == m ? Palette.mtRaise2 : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Input Area

    @ViewBuilder
    private var inputArea: some View {
        if mode == .vocabulary {
            vocabularyInput
        } else {
            replacementInputView
        }
    }

    private var vocabularyInput: some View {
        HStack(spacing: 11) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
            matteField($wordInput, prompt: "e.g. Priyanshu, Sotto", field: .word, onSubmit: submitVocabulary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var replacementInputView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 56, alignment: .trailing)
                matteField($originalInput, prompt: "e.g. my email, my mail", field: .original, onSubmit: { focusedField = .replacement })
            }

            HStack(spacing: 10) {
                Text("With")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 56, alignment: .trailing)
                matteField($replacementInput, prompt: "e.g. name@example.com", field: .replacement, onSubmit: submitReplacement)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func matteField(_ text: Binding<String>, prompt: String, field: Field, onSubmit: @escaping () -> Void) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundColor(Palette.inkSecondary))
            .textFieldStyle(.plain)
            .font(.mono(14))
            .foregroundStyle(Palette.inkPrimary)
            .focused($focusedField, equals: field)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.mtRaise2)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.mtLine, lineWidth: 1)
                    )
            )
    }

    // MARK: - Hint Bar

    private var hintBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    KeyHint("↵")
                    Text("Add")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkSecondary)
                }
                HStack(spacing: 4) {
                    KeyHint("esc")
                    Text("Dismiss")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func submitVocabulary() {
        let input = wordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(input, existing: Array(vocabularyWords), context: modelContext) {
            errorMessage = error
            return
        }
        onDismiss()
    }

    private func submitReplacement() {
        let original = originalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return }
        // Match the in-row Add path in WordReplacementView: push new entry to
        // the bottom of the manual order (currentMax + 1) so quick-add rows
        // don't collapse to sortOrder 0 alongside legacy/unordered entries.
        let nextOrder = (wordReplacements.map(\.sortOrder).max() ?? 0) + 1
        if let error = DictionaryService.addWordReplacement(
            original: original,
            replacement: replacement,
            existing: Array(wordReplacements),
            context: modelContext,
            sortOrder: nextOrder
        ) {
            errorMessage = error
            return
        }
        onDismiss()
    }
}

// MARK: - Key Hint

private struct KeyHint: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.mono(10, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.mtRaise2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.mtLine, lineWidth: 1)
                    )
            )
    }
}

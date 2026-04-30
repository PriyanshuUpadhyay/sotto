import SwiftUI
import SwiftData
import AppKit

/// W12.E root view. Multi-tab chrome with custom strip, ⌘T new, ⌘W close,
/// ⌘1-⌘9 jump. Capped at 10 user-created tabs (paste-fallback bypasses the
/// cap). See plan `docs/superpowers/plans/W12E-scratchpad.md` §Migration
/// policy #2.
struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.4)
            if let active = activeDocument {
                ScratchpadTabEditor(document: active, store: store)
                    .id(active.id)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveGlassBackground(intensity: .panel)
        .background(KeyShortcutCatcher(store: store))
    }

    private var activeDocument: ScratchpadDocument? {
        store.documents.first { $0.id == store.activeTabId }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text("No tabs. Press ⌘T to create one.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(store.documents.enumerated()), id: \.element.id) { _, doc in
                    tabCell(doc)
                }
                addTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func tabCell(_ doc: ScratchpadDocument) -> some View {
        let isActive = doc.id == store.activeTabId
        return HStack(spacing: 6) {
            Text(doc.title.isEmpty ? "Untitled" : doc.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Button(action: { store.closeTab(doc) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Palette.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairlineSoft, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Capture the previous tab's state on switch.
            if let prev = activeDocument, prev.id != doc.id {
                store.captureVersion(prev, force: true)
            }
            store.activeTabId = doc.id
        }
    }

    private var addTabButton: some View {
        Button(action: { _ = store.createTab() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(store.documents.count >= ScratchpadStore.maxTabs)
        .opacity(store.documents.count >= ScratchpadStore.maxTabs ? 0.4 : 1.0)
    }
}

/// W12.E keyboard chord routing. SwiftUI's `.keyboardShortcut(...)` doesn't
/// reliably bubble through `TextEditor`'s consumed-events, so we use a
/// hidden `NSView`-backed event monitor that fires on the local event queue
/// only when the Scratchpad window is key.
private struct KeyShortcutCatcher: NSViewRepresentable {
    @ObservedObject var store: ScratchpadStore

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            // Only consume chords when the Scratchpad is the key window —
            // avoids stealing ⌘T / ⌘W from other windows in the same app.
            guard let host = NSApp.keyWindow,
                  host.identifier?.rawValue == "com.prakashjoshipax.voiceink.scratchpadWindow" else {
                return event
            }
            switch event.charactersIgnoringModifiers {
            case "t":
                Task { @MainActor in _ = store.createTab() }
                return nil
            case "w":
                Task { @MainActor in
                    if let active = store.documents.first(where: { $0.id == store.activeTabId }) {
                        store.closeTab(active)
                    }
                }
                return nil
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n),
                   n - 1 < store.documents.count {
                    let target = store.documents[n - 1]
                    Task { @MainActor in
                        if let prev = store.documents.first(where: { $0.id == store.activeTabId }),
                           prev.id != target.id {
                            store.captureVersion(prev, force: true)
                        }
                        store.activeTabId = target.id
                    }
                    return nil
                }
                return event
            }
        }
        context.coordinator.monitor = monitor
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
    }
}

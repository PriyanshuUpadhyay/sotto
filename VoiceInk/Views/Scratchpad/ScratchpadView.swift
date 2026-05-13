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
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.white.opacity(0.42))
            Text("NO TABS")
                .font(.system(size: 13, design: .monospaced).weight(.bold))
                .tracking(0.16 * 13)
                .foregroundStyle(Color.white.opacity(0.42))
            Text("⌘T to create one")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42).opacity(0.6))
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
        return HStack(spacing: 5) {
            Text(doc.title.isEmpty ? "UNTITLED" : doc.title.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(isActive ? .bold : .regular))
                .tracking(0.16 * 10)
                .foregroundStyle(isActive ? Palette.brandAcid : Color.white.opacity(0.42))
                .lineLimit(1)
            Button(action: { store.closeTab(doc) }) {
                Text("✕")
                    .font(.system(size: 8, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.42).opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tab \(doc.title.isEmpty ? "Untitled" : doc.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isActive ? Palette.brandAcid.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isActive ? Palette.brandAcid.opacity(0.35) : Palette.hairlineSoft, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Capture the previous tab's state on switch.
            if let prev = activeDocument, prev.id != doc.id {
                store.captureVersion(prev, force: true)
            }
            store.activeTabId = doc.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(doc.title.isEmpty ? "Untitled tab" : doc.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var addTabButton: some View {
        Button(action: { _ = store.createTab() }) {
            Text("+")
                .font(.system(size: 12, design: .monospaced).weight(.bold))
                .foregroundStyle(store.documents.count >= ScratchpadStore.maxTabs
                                 ? Color.white.opacity(0.42).opacity(0.3)
                                 : Palette.brandAcid)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(store.documents.count >= ScratchpadStore.maxTabs)
        .accessibilityLabel("New tab")
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

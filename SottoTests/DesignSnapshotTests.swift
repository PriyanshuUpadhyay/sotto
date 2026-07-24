import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import Sotto

/// Headless design-iteration harness. Renders SwiftUI views to PNGs on disk via
/// ImageRenderer (in-process, no Screen-Recording permission, no focus steal),
/// so the design loop can SEE structure/layout/type/color and regress on it.
///
/// Caveat: NSVisualEffectView (vibrancy/native Liquid Glass) does NOT composite
/// inside ImageRenderer — translucent layers render blank. Judge layout, spacing,
/// typography, color, and grounding here; judge live glass in the running app.
enum SnapshotRenderer {
    static let dir = URL(fileURLWithPath: "/tmp/sotto-snapshots", isDirectory: true)

    @MainActor
    static func render<V: View>(_ view: V, name: String, scale: CGFloat = 2) throws -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageRenderer produced no image for \(name)"])
        }
        let url = dir.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }
}

@MainActor
final class DesignSnapshotTests: XCTestCase {
    /// Snapshot tests are a DESIGN-ITERATION TOOL, not a correctness gate. They
    /// render AppKit-backed SwiftUI offscreen via ImageRenderer, which is
    /// non-deterministic under the parallel `make test` run (nsImage can come
    /// back nil when the suite saturates the machine). Gate them behind an env
    /// var so `make test` stays green; run on demand with SOTTO_SNAPSHOTS=1.
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
    }

    /// Proves the headless render loop works end-to-end.
    func test_smoke_rendersPNG() throws {
        let view = ZStack {
            Color.black
            Text("Sotto")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 480, height: 200)

        let url = try SnapshotRenderer.render(view, name: "smoke")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    /// In-memory SwiftData container seeded with realistic history rows, so the
    /// real app views render with data (not empty state) in the headless harness.
    @MainActor
    static func seededContainer() throws -> ModelContainer {
        let schema = Schema([
            Transcription.self, SessionMetric.self,
            VocabularyWord.self, WordReplacement.self, Snippet.self,
            ScratchpadDocument.self, ScratchpadVersion.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let ctx = container.mainContext
        let samples: [(String, TimeInterval, String)] = [
            ("Let's ship the recorder relocation today and circle back on the glass.", 6.2, "Parakeet"),
            ("Remind me to review the council's remediation plan before standup.", 4.1, "Whisper Turbo"),
            ("The quick brown fox jumps over the lazy dog near the riverbank.", 3.5, "Parakeet"),
            ("Draft a reply: thanks for the feedback, I'll push the fix by EOD.", 5.0, "Distil"),
        ]
        for (text, dur, model) in samples {
            let t = Transcription(text: text, duration: dur, transcriptionModelName: model,
                                  transcriptionStatus: .completed)
            ctx.insert(t)
            ctx.insert(SessionMetric(
                transcriptionId: t.id,
                wordCount: text.split(separator: " ").count,
                audioDuration: dur,
                transcriptionModelName: model,
                transcriptionDuration: dur * 0.3,
                speedFactor: 3.0,
                powerModeName: nil,
                aiEnhancementModelName: nil,
                enhancementDuration: nil
            ))
        }
        try? ctx.save()
        return container
    }

    /// Redesigned top bar (pure SwiftUI → renders cleanly headless).
    func test_redesign_topBar() throws {
        let view = VStack(spacing: 0) {
            TopBarSnapshotHost()
            ZStack {
                Palette.surfaceBase
                Text("history cards render below on the base surface")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: 900, height: 200)
        .environment(\.colorScheme, .dark)

        let url = try SnapshotRenderer.render(view, name: "redesign_topbar")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    /// Baseline "before": the current InlineHistoryView (top bar is the complaint).
    func test_baseline_inlineHistory() throws {
        let container = try Self.seededContainer()
        let view = InlineHistoryView()
            .frame(width: 920, height: 600)
            .modelContainer(container)
        let url = try SnapshotRenderer.render(view, name: "baseline_history")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    /// A realistic command set assembled from the PURE builders (no engine
    /// needed), mirroring what `CommandRegistry.all` produces in the running app.
    @MainActor
    static func seededPaletteModel(query: String) -> CommandPaletteModel {
        let quick = CommandRegistry.quickActionCommands(pasteLast: {}, pasteLastEnhancement: {}, retryLast: {})
        let models = CommandRegistry.modelCommands(
            modelNames: ["Parakeet v3", "Whisper Turbo", "Distil Large v3"],
            activeName: "Parakeet v3", setActive: { _ in })
        let transcripts = CommandRegistry.transcriptCommands(
            rows: [(id: UUID(), raw: "Let's ship the recorder relocation today and circle back.",
                    enhanced: nil, preview: "Let's ship the recorder relocation today and circle back."),
                   (id: UUID(), raw: "Remind me to review the council's remediation plan.",
                    enhanced: nil, preview: "Remind me to review the council's remediation plan.")])
        let nav = CommandRegistry.navigationCommands(index: SettingsSearch.index)
        let model = CommandPaletteModel()
        model.setSource(quick + transcripts + models + nav)
        model.applyQuery(query)
        return model
    }

    /// Default-open palette (empty query → full command list, first row selected).
    /// This is the "what you see when you press ⌘K" shot. Pure solid-color onyx
    /// card (no NSVisualEffectView) so it composites cleanly headless.
    func test_redesign_commandPalette_default() throws {
        let model = Self.seededPaletteModel(query: "")
        let view = ZStack {
            Palette.surfaceBase.opacity(0.9)
            CommandPalette(model: model, onRun: { _, _ in }, onClose: {})
        }
        .frame(width: 720, height: 560)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "command_palette_default")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    /// Filtered palette (query ranks the three model rows; first row carries the
    /// acid selection ring). Verifies row layout, category labels, and selection.
    func test_redesign_commandPalette_filtered() throws {
        let model = Self.seededPaletteModel(query: "switch model")
        let view = ZStack {
            Palette.surfaceBase.opacity(0.9)
            CommandPalette(model: model, onRun: { _, _ in }, onClose: {})
        }
        .frame(width: 720, height: 420)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "command_palette_filtered")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    /// P0.5 — the regression guard every later phase leans on. Renders a
    /// representative windowed card (`SettingsRow`) on `Theme.windowBackground`
    /// in BOTH light and dark, proving the appearance-adaptive token ladder
    /// actually flips (the light shot must be light, not onyx).
    func test_theme_windowedCard_lightAndDark() throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = WindowedCardSnapshotHost()
                .frame(width: 420, height: 120)
                .environment(\.colorScheme, scheme)
            let suffix = scheme == .light ? "light" : "dark"
            let url = try SnapshotRenderer.render(view, name: "theme_windowed_card-\(suffix)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            print("SNAPSHOT_WRITTEN \(url.path)")
        }
    }

    /// P5 — the recorder HUD on its native Liquid Glass substrate, one shot per
    /// state (armed / recording / transcribing / enhancing / done) in BOTH the
    /// onyx (dark) and light glass variants over a wallpaper-tone backdrop.
    /// NOTE: the live `.glassEffect` / vibrancy substrate does NOT composite in
    /// ImageRenderer (harness caveat) — these shots judge the tint scrim, inner
    /// strokes, state-keyed halo, and chip content/layout, NOT the glass blur.
    func test_hud_states_onyxAndLight() throws {
        let states: [(HaloPhase, String)] = [
            (.armed, "armed"),
            (.recording, "recording"),
            (.transcribing, "transcribing"),
            (.enhancing, "enhancing"),
            (.done, "done"),
        ]
        for (phase, name) in states {
            for appearance in [GlassAppearance.onyx, .light] {
                let view = HUDStateSnapshotHost(phase: phase, appearance: appearance)
                let suffix = appearance == .light ? "light" : "dark"
                let url = try SnapshotRenderer.render(view, name: "hud_\(name)-\(suffix)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                print("SNAPSHOT_WRITTEN \(url.path)")
            }
        }
    }
}

/// One recorder-HUD state rendered on the real `HaloMaterial` substrate (the
/// chip capsule material), over a wallpaper-tone backdrop matching the glass
/// variant. Mirrors the live anchor chip: a state dot + monospaced label.
private struct HUDStateSnapshotHost: View {
    let phase: HaloPhase
    let appearance: GlassAppearance

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.hud, style: .continuous)
        return ZStack {
            // Backdrop standing in for the desktop wallpaper the glass sits over.
            (appearance == .light ? Color(white: 0.93) : Palette.onyxBg)
            HaloMaterial(
                shape: shape,
                phase: phase,
                breathePulse: phase == .enhancing ? 0.6 : 0,
                showInnerSheen: phase == .enhancing,
                appearance: appearance
            )
            .frame(width: 230, height: 40)
            .overlay {
                HStack(spacing: 6) {
                    Circle()
                        .fill(phase.glowColor)
                        .frame(width: 7, height: 7)
                    Text(Self.label(for: phase))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(appearance == .light ? Color.black.opacity(0.82) : Palette.onyxFg)
                }
            }
        }
        .frame(width: 320, height: 120)
    }

    private static func label(for phase: HaloPhase) -> String {
        switch phase {
        case .armed:                 return "LISTENING"
        case .recording, .liveText:  return "REC"
        case .transcribing:          return "TRANSCRIBING"
        case .enhancing:             return "ENHANCING"
        case .done:                  return "PASTED"
        case .failed:                return "FAIL"
        case .hidden:                return ""
        }
    }
}

/// A representative windowed card: a `SettingsRow` on the adaptive
/// `Theme.windowBackground` surface, tinted with the lime `Brand.tint`.
private struct WindowedCardSnapshotHost: View {
    @State private var on = true
    var body: some View {
        ZStack {
            Theme.windowBackground
            SettingsRow(
                iconSystemName: "speaker.wave.2.fill",
                label: "Sound Feedback",
                subtitle: "Play a cue on commit.",
                iconTint: Brand.tint
            ) {
                Toggle("", isOn: $on).labelsHidden()
            }
            .brandAccented()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Theme.elevated)
            )
            .padding(20)
        }
    }
}

/// Owns a `@FocusState` so the snapshot can render `HistoryTopBar`, whose
/// `searchFocused` parameter is a `FocusState<Bool>.Binding` that can only
/// originate inside a View.
private struct TopBarSnapshotHost: View {
    @FocusState private var searchFocused: Bool
    var body: some View {
        HistoryTopBar(searchText: .constant(""), searchFocused: $searchFocused)
    }
}

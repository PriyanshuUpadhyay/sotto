import XCTest
import SwiftUI
@testable import Sotto

final class SettingsMatteSnapshotTests: XCTestCase {
    // MARK: - Snapshots (gated; a representative pane)

    @MainActor
    func test_settings_pane_snapshot() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        let view = ZStack {
            Theme.canvas
            SettingsMattePaneSnapshotHost()
                .padding(24)
        }
        .frame(width: 720, height: 320)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "settings_pane")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }
}

/// A representative matte Settings pane assembled from the shared components
/// (`SettingsCard` + `SettingsSectionHeader` + `SettingsRow`) so the restyle is
/// visible headless without a real tab's EnvironmentObjects.
private struct SettingsMattePaneSnapshotHost: View {
    @State private var on = true
    var body: some View {
        SettingsCard(
            iconSystemName: "command",
            iconTint: Brand.tint,
            title: "Shortcuts",
            subtitle: "Trigger recording from anywhere.",
            statusText: "1 active"
        ) {
            SettingsRow(
                iconSystemName: "1.circle",
                label: "Shortcut 1",
                subtitle: "Hold to record, release to send.",
                iconTint: Brand.tint
            ) {
                Text("⌘⇧V")
                    .font(.mono(12))
                    .foregroundColor(Palette.inkSecondary)
            }
            SettingsRow(
                iconSystemName: "speaker.wave.2.fill",
                label: "Sound Feedback",
                iconTint: Brand.tint
            ) {
                Toggle("", isOn: $on).labelsHidden()
            }
        }
    }
}

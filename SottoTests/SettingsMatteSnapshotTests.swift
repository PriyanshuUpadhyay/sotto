import XCTest
import SwiftUI
@testable import Sotto

final class SettingsMatteSnapshotTests: XCTestCase {
    // The matte rail selection no longer paints the row Brand.tint with black
    // text; it uses mtRaise2 fill + phosphor glyph + inkPrimary label.
    func testRailSelectionFillIsMatteNotAccent() {
        XCTAssertEqual(
            SettingsRailRowStyle.selectedFill.resolvedNSColor(),
            Palette.mtRaise2.resolvedNSColor()
        )
        XCTAssertEqual(
            SettingsRailRowStyle.selectedGlyph.resolvedNSColor(),
            Palette.phosphor.resolvedNSColor()
        )
        XCTAssertNotEqual(
            SettingsRailRowStyle.selectedFill.resolvedNSColor(),
            Brand.tint.resolvedNSColor()
        )
    }

    // Idle/hover stay matte (no accent fill on unselected rows).
    func testRailIdleAndHoverAreMatte() {
        XCTAssertEqual(SettingsRailRowStyle.label.resolvedNSColor(), Palette.inkPrimary.resolvedNSColor())
        XCTAssertEqual(
            SettingsRailRowStyle.idleLabel.resolvedNSColor(),
            Palette.inkSecondary.resolvedNSColor()
        )
        XCTAssertEqual(SettingsRailRowStyle.hoverFill.resolvedNSColor(), Palette.mtRaise.resolvedNSColor())
    }

    // MARK: - Snapshots (gated; rail selected+idle + a representative pane)

    @MainActor
    func test_settings_rail_snapshot() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        let view = ZStack {
            Theme.canvas
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsRailRow(tab: tab, isSelected: tab == .general) {}
                }
            }
            .padding(10)
        }
        .frame(width: 210, height: 320)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "settings_rail")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

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

import XCTest
import SwiftUI
@testable import Sotto

final class SettingsMatteSnapshotTests: XCTestCase {
    // The window's ONE selection language: the selected sidebar row is a matte
    // mtRaise2 fill + a phosphor tick and label, never a Brand.tint-filled row.
    func testSidebarSelectionFillIsMatteNotAccent() {
        XCTAssertEqual(
            SottoSidebarRowStyle.selectedFill.resolvedNSColor(),
            Palette.mtRaise2.resolvedNSColor()
        )
        XCTAssertEqual(
            SottoSidebarRowStyle.selectedLabel.resolvedNSColor(),
            Palette.phosphor.resolvedNSColor()
        )
        XCTAssertNotEqual(
            SottoSidebarRowStyle.selectedFill.resolvedNSColor(),
            Brand.tint.resolvedNSColor()
        )
    }

    // Idle/hover stay matte (no accent fill on unselected rows).
    func testSidebarIdleAndHoverAreMatte() {
        XCTAssertEqual(
            SottoSidebarRowStyle.hoverLabel.resolvedNSColor(),
            Palette.inkPrimary.resolvedNSColor()
        )
        XCTAssertEqual(
            SottoSidebarRowStyle.idleLabel.resolvedNSColor(),
            Palette.inkSecondary.resolvedNSColor()
        )
        XCTAssertEqual(SottoSidebarRowStyle.hoverFill.resolvedNSColor(), Palette.mtRaise.resolvedNSColor())
    }

    // MARK: - Snapshots (gated; sidebar selected+idle + a representative pane)

    @MainActor
    func test_sidebar_snapshot() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        let view = ZStack {
            Theme.canvas
            VStack(spacing: 2) {
                ForEach(SottoWindowTab.allCases, id: \.self) { tab in
                    SottoSidebarRow(tab: tab, isSelected: tab == .general) {}
                }
            }
            .padding(10)
        }
        .frame(width: 200, height: 320)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "sotto_sidebar")
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

import SwiftUI

// MARK: - Section scroll-to + highlight (shared by all five tabs)

extension View {
    /// A phosphor ring drawn around a section the search jumped to. Animated
    /// fade under normal motion; instant under reduceMotion.
    @ViewBuilder
    func settingsSectionHighlight(active: Bool, reduceMotion: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.phosphor, lineWidth: 2)
                .opacity(active ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: active)
                .allowsHitTesting(false)
        )
    }
}

/// Handles a `.selectSettingsSection` notification inside a tab: if the target
/// tab is this one, scroll its first section whose `searchLabel` matches, and
/// set a brief highlight. `sections`/`label` keep it generic over each tab's
/// own section enum.
@MainActor
func handleSettingsSectionJump<S: Hashable>(
    _ notification: Notification,
    thisTab: SettingsTab,
    sections: [S],
    label: (S) -> String,
    proxy: ScrollViewProxy,
    reduceMotion: Bool,
    highlight: Binding<S?>
) {
    guard notification.userInfo?["tab"] as? SettingsTab == thisTab,
          let targetLabel = notification.userInfo?["label"] as? String,
          let section = sections.first(where: { label($0) == targetLabel })
    else { return }

    if reduceMotion {
        proxy.scrollTo(section, anchor: .top)
    } else {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(section, anchor: .top)
        }
    }

    highlight.wrappedValue = section
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        if highlight.wrappedValue == section {
            highlight.wrappedValue = nil
        }
    }
}

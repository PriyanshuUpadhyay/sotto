import SwiftUI
import SwiftData
import AppKit

extension InlineHistoryView {
    // MARK: - Empty State

    @ViewBuilder
    var emptyStateView: some View {
        if searchText.isEmpty {
            coachingEmptyState
        } else {
            searchEmptyState
        }
    }

    /// Failed-search variant — distinct from first-run coaching: no hotkey
    /// teaching, just a "narrow your query" nudge on semantic ink tokens.
    var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Theme.inkTertiary)
            Text("No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Text("Try a different search term")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Genuinely-empty history → first-run activation surface. Teaches the core
    /// press·speak·release gesture against the user's *actual* bound dictation
    /// hotkey (rendered as KeyCaps). If no hotkey is bound, swaps the lesson for
    /// an Acid-Lime CTA that deep-links to Shortcuts settings.
    var coachingEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(Theme.inkTertiary)

            VStack(spacing: 6) {
                Text("Start dictating")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Your transcriptions will appear here.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if dictationGlyphs.isEmpty {
                Button {
                    openShortcutsSettings()
                } label: {
                    Text("Set a dictation shortcut")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(LimeFillButtonStyle())
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Hold")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        KeyCombo(keys: dictationGlyphs)
                        Text("to dictate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("press · speak · release")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.inkSecondary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Unicode key-cap glyphs for the *primary* dictation hotkey
    /// (`selectedHotkey1`). Empty ⇒ no hotkey bound. Shared with the onboarding
    /// shortcut step and the first-run reminder toast.
    var dictationGlyphs: [String] {
        HotkeyManager.dictationGlyphs(for: hotkeyManager.selectedHotkey1)
    }

    func openShortcutsSettings() {
        // Staged via the coordinator — a bare notification is lossy when
        // SettingsContentView isn't mounted yet.
        SottoWindowCoordinator.shared.open(settingsTab: .shortcuts)
    }
}

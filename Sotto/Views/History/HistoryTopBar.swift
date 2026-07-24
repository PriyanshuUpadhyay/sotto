import SwiftUI

/// History header. A native chrome band (`.bar` material + bottom separator)
/// over the window body. Search sits on a grouped-background control. Stats
/// moved to the today-scoped HistoryStatsBand above this bar (2026-07 revamp).
struct HistoryTopBar: View {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            searchField
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkTertiary)
            // Mono input — ⌘K/search is machine data (spec §1 typography).
            TextField("Search transcriptions", text: $searchText)
                .textFieldStyle(.plain)
                .font(.mono(13))
                .foregroundStyle(Palette.inkPrimary)
                .focused(searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(controlSurface)
        .frame(maxWidth: 360)
    }

    private var controlSurface: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Theme.selectedRow)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

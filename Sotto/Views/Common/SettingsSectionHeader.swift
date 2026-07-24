import SwiftUI

// MARK: - SettingsSectionHeader
//
// Hero-style section header — rounded icon tile + title + subtitle + optional
// status pill. Drop-in replacement for `Text("Section Name")` in `Section`
// headers. Doesn't break the surrounding `Form` structure.

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let accent: Color
    var statusText: String? = nil
    var statusTone: StatusTone = .neutral

    enum StatusTone {
        case neutral, positive, warning

        var color: Color {
            switch self {
            case .neutral:  return Palette.neutral
            case .positive: return Palette.success
            case .warning:  return Palette.warn
            }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon tile
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(accent.opacity(0.32), lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accent)
                )
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.inkPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let statusText {
                Text(statusText)
                    .font(.microlabel(10))
                    .tracking(0.06 * 10)
                    .textCase(.uppercase)
                    .foregroundColor(statusTone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(statusTone.color.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(statusTone.color.opacity(0.32), lineWidth: 0.5)
                    )
            }
        }
        .padding(.bottom, 4)
        // Forms in macOS use uppercased small headers — opt back into normal case here.
        .textCase(nil)
    }
}

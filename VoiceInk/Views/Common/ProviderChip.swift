import SwiftUI

// MARK: - ProviderChip
//
// Compact identity chip for an AI provider — small tinted square + provider
// name + (optional) model name + connection dot. Used in EnhancementSettings
// and the menu bar to replace bare-text provider/model labels.

struct ProviderChip: View {
    let provider: AIProvider
    var model: String? = nil
    var connected: Bool = false
    var compact: Bool = false   // hide model name; just the mark + provider name

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            providerMark
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(tint.opacity(0.32), lineWidth: 0.5)
                )
                .overlay(alignment: .topTrailing) {
                    if connected {
                        Circle()
                            .fill(Palette.success)
                            .frame(width: 5, height: 5)
                            .offset(x: 2, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !compact, let m = model, !m.isEmpty {
                    Text(displayModel(m))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Provider visuals
    //
    // Symbol / tint / displayName all forward to `ProviderChipStyle` (single
    // source of truth shared with `ProviderCard`). Never re-introduce private
    // switch tables here — extend `ProviderChipStyle` instead.

    private var providerMark: some View {
        Image(systemName: ProviderChipStyle.symbol(for: provider))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
    }

    private var tint: Color {
        ProviderChipStyle.tint(for: provider)
    }

    private var displayName: String {
        ProviderChipStyle.displayName(for: provider)
    }

    /// Strip provider prefix and tighten model labels.
    private func displayModel(_ raw: String) -> String {
        var s = raw
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        if s.hasPrefix("models/") { s.removeFirst("models/".count) }
        return s
    }
}

import SwiftUI
import AppKit

// MARK: - Native Apple Model Card View
struct NativeAppleModelCardView: View {
    let model: NativeAppleModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void
    
    var body: some View {
        OnyxSurfaceCard(cornerRadius: Radius.control, padding: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Main Content
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action Controls
                actionSection
            }
        }
        // Selection ring only — OnyxSurfaceCard already strokes its own
        // hairline, and the radius stays concentric with the card around it.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Brand.tint.opacity(isCurrent ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.ui(13, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)
            
            Spacer()
        }
    }
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Native Apple
            Label("Native Apple", systemImage: "apple.logo")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // On-Device
            Label("On-Device", systemImage: "checkmark.shield")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Requires macOS 26+
            Label("macOS 26+", systemImage: "macbook")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
        }
        .lineLimit(1)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.ui(11))
            .foregroundColor(Palette.inkSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.ui(12))
                    .foregroundColor(Palette.inkSecondary)
            } else {
                Button(action: setDefaultAction) {
                    Text("Set as Default")
                        .font(.ui(12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
} 

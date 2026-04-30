import SwiftUI

/// W12.E version-history sheet. Lists up to 50 most-recent snapshots; user
/// taps Restore to capture-then-replace (Migration policy #8). Preview-only
/// in v1; diff-render is deferred per lead's locked answer Q7. See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Task 6.
struct ScratchpadVersionHistorySheet: View {
    @Bindable var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore
    @Environment(\.dismiss) private var dismiss

    private var sortedVersions: [ScratchpadVersion] {
        document.versions.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            if sortedVersions.isEmpty {
                Spacer()
                Text("No versions captured yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedVersions, id: \.id) { v in
                            row(v)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func row(_ v: ScratchpadVersion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.formatter.string(from: v.capturedAt))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(v.content.isEmpty ? "(empty)" : String(v.content.prefix(120)))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Restore") {
                store.restoreVersion(v, in: document)
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.06))
        )
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}

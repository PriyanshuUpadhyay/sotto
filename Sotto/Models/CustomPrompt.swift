import Foundation
import SwiftUI

typealias PromptIcon = String

extension PromptIcon {
    static let allCases: [PromptIcon] = [
        // Document & Text
        "doc.text.fill",
        "textbox",
        "checkmark.seal.fill",
        
        // Communication
        "bubble.left.and.bubble.right.fill",
        "message.fill",
        "envelope.fill",
        
        // Professional
        "person.2.fill",
        "person.wave.2.fill",
        "briefcase.fill",
        
        // Technical
        "curlybraces",
        "terminal.fill",
        "gearshape.fill",
        
        // Content
        "doc.text.image.fill",
        "note",
        "book.fill",
        "bookmark.fill",
        "pencil.circle.fill",
        
        // Media & Creative
        "video.fill",
        "mic.fill",
        "music.note",
        "photo.fill",
        "paintbrush.fill",
        
        // Productivity & Time
        "clock.fill",
        "calendar",
        "list.bullet",
        "checkmark.circle.fill",
        "timer",
        "hourglass",
        "star.fill",
        "flag.fill",
        "tag.fill",
        "folder.fill",
        "paperclip",
        "tray.fill",
        "chart.bar.fill",
        "flame.fill",
        "target",
        "list.clipboard.fill",
        "brain.head.profile",
        "lightbulb.fill",
        "megaphone.fill",
        "heart.fill",
        "map.fill",
        "house.fill",
        "camera.fill",
        "figure.walk",
        "dumbbell.fill",
        "cart.fill",
        "creditcard.fill",
        "graduationcap.fill",
        "airplane",
        "leaf.fill",
        "hand.raised.fill",
        "hand.thumbsup.fill"
    ]
}

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    var isActive: Bool
    let icon: PromptIcon
    let description: String?
    let isPredefined: Bool
    let triggerWords: [String]

    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: PromptIcon = "doc.text.fill",
        description: String? = nil,
        isPredefined: Bool = false,
        triggerWords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
        self.triggerWords = triggerWords
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, isActive, icon, description, isPredefined, triggerWords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        icon = try container.decode(PromptIcon.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPredefined = try container.decode(Bool.self, forKey: .isPredefined)
        triggerWords = try container.decode([String].self, forKey: .triggerWords)
    }
}

// MARK: - UI Extensions
extension CustomPrompt {
    func promptIcon(isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil, onDelete: ((CustomPrompt) -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            // Flat glass tile — selection ring + accent glow shadow per
            // spec §1.X.W13.5 (family-aligned strokes).
            GlassCard(cornerRadius: 14, padding: 0) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? Palette.brandAcid : Palette.inkPrimary)
                    .frame(width: 48, height: 48)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Palette.brandAcid : Palette.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? Palette.brandAcid.opacity(0.55) : .clear,
                radius: 18, x: 0, y: 0
            )
            .frame(width: 48, height: 48)

            // Title + trigger words — type stays.
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)

                // Trigger word section with consistent height
                ZStack(alignment: .center) {
                    if !triggerWords.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 7))
                                .foregroundColor(isSelected ? Palette.brandAcid : Palette.inkSecondary)

                            if triggerWords.count == 1 {
                                Text("\"\(triggerWords[0])...\"")
                                    .font(.system(size: 8, weight: .regular))
                                    .foregroundColor(isSelected ? Palette.brandAcid : Palette.inkSecondary)
                                    .lineLimit(1)
                            } else {
                                Text("\"\(triggerWords[0])...\" +\(triggerWords.count - 1)")
                                    .font(.system(size: 8, weight: .regular))
                                    .foregroundColor(isSelected ? Palette.brandAcid : Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: 70)
                    }
                }
                .frame(height: 16)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .onTapGesture(count: 2) {
            // Double tap to edit
            if let onEdit = onEdit {
                onEdit(self)
            }
        }
        .onTapGesture(count: 1) {
            // Single tap to select
            onTap()
        }
        .contextMenu {
            if onEdit != nil || onDelete != nil {
                if let onEdit = onEdit {
                    Button {
                        onEdit(self)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                
                if let onDelete = onDelete, !isPredefined {
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = "Delete Prompt?"
                        alert.informativeText = "Are you sure you want to delete '\(self.title)' prompt? This action cannot be undone."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")
                        
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            onDelete(self)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
    
    // Static method to create an "Add New" button with the same styling as the prompt icons
    static func addNewButton(action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            // Mirrors `promptIcon` rest-state tile vocabulary —
            // GlassCard + hairline stroke + accent plus glyph.
            GlassCard(cornerRadius: 14, padding: 0) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Palette.brandAcid)
                    .frame(width: 48, height: 48)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
            .frame(width: 48, height: 48)

            // Text label with matching styling
            VStack(spacing: 2) {
                Text("Add New")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)

                // Empty space matching the trigger word area height
                Spacer()
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: DictionarySection = .replacements
    @State private var isShowingSettings = false
    let whisperPrompt: WhisperPrompt
    
    enum DictionarySection: String, CaseIterable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"
        
        var description: String {
            switch self {
            case .spellings:
                return "Add words to help VoiceInk recognize them properly"
            case .replacements:
                return "Automatically replace specific words/phrases with custom formatted text "
            }
        }
        
        var icon: String {
            switch self {
            case .spellings:
                return "character.book.closed.fill"
            case .replacements:
                return "arrow.2.squarepath"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .adaptiveGlassBackground()
        .slidingPanel(isPresented: $isShowingSettings, width: 400) {
            DictionarySettingsPanel {
                withAnimation(.smooth(duration: 0.3)) {
                    isShowingSettings = false
                }
            }
        }
    }
    
    private var heroSection: some View {
        CompactHeroSection(
            icon: "brain.filled.head.profile",
            title: "Dictionary Settings",
            description: "Enhance VoiceInk's transcription accuracy by teaching it your vocabulary",
            maxDescriptionWidth: 500
        )
    }
    
    private var mainContent: some View {
        VStack(spacing: 40) {
            sectionSelector
            selectedSectionContent
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var sectionSelector: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Select Section")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Dictionary settings")
            }

            HStack(spacing: 20) {
                ForEach(DictionarySection.allCases, id: \.self) { section in
                    SectionCard(
                        section: section,
                        isSelected: selectedSection == section,
                        action: { selectedSection = section }
                    )
                }
            }
        }
    }
    
    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedSection {
            case .spellings:
                VocabularyView(whisperPrompt: whisperPrompt)
                    .modifier(GlassChip(cornerRadius: 16, paddingH: 0, paddingV: 0))
            case .replacements:
                // P3.D: entries already wear individual GlassCards — drop
                // the redundant outer chrome so cards breathe against the
                // section background.
                WordReplacementView()
            }
        }
    }
}

struct SectionCard: View {
    let section: DictionarySettingsView.DictionarySection
    let isSelected: Bool
    let action: () -> Void

    let accent: Color = Palette.accent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                // Rounded icon tile in the section's accent — mirrors
                // SettingsSectionHeader's icon treatment.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.20 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accent.opacity(isSelected ? 0.40 : 0.22), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: section.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(accent)
                    )
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.rawValue)
                        .font(.system(size: 15, weight: .semibold))

                    Text(section.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .modifier(GlassChip(cornerRadius: 16, paddingH: 0, paddingV: 0))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(isSelected ? 0.5 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

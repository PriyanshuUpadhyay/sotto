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
                return "Add words to help Sotto recognize them properly"
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
                withAnimation(Animation.haloExpand) {
                    isShowingSettings = false
                }
            }
        }
    }
    
    private var heroSection: some View {
        CompactHeroSection(
            icon: "brain.filled.head.profile",
            title: "Dictionary Settings",
            description: "Enhance Sotto's transcription accuracy by teaching it your vocabulary",
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
                HStack(spacing: 4) {
                    Text("›")
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.brandAcid)
                        .accessibilityHidden(true)
                    Text("SELECT SECTION")
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 12)
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                Spacer()

                Button {
                    withAnimation(Animation.haloExpand) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Text("⚙")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(isShowingSettings ? Palette.brandAcid : Color.white.opacity(0.42))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictionary settings")
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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.brandAcid.opacity(isSelected ? 0.18 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Palette.brandAcid.opacity(isSelected ? 0.40 : 0.16), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: section.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Palette.brandAcid)
                    )
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.rawValue.uppercased())
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 12)
                        .foregroundStyle(isSelected ? Palette.brandAcid : .primary)

                    Text(section.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .modifier(GlassChip(cornerRadius: 4, paddingH: 0, paddingV: 0))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.brandAcid.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

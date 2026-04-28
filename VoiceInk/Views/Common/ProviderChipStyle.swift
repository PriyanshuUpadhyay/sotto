import SwiftUI

// MARK: - ProviderChipStyle
//
// Single source of truth for provider visuals — symbol, tint, display name.
// Consumed by both `ProviderChip` (small inline chip) and `ProviderCard`
// (gallery cell) so they stay in lockstep without duplicated switch tables.
//
// Add a new provider:
//   1. Add a case to `AIProvider` (Services/AIEnhancement/AIService.swift).
//   2. Add a row in each switch below.
// Both chip and gallery-cell pick up the new style automatically.

enum ProviderChipStyle {
    static func symbol(for provider: AIProvider) -> String {
        switch provider {
        case .openAI:           return "circle.dotted"
        case .anthropic:        return "asterisk"
        case .gemini:           return "sparkle"
        case .groq:             return "bolt.fill"
        case .cerebras:         return "cpu"
        case .openRouter:       return "arrow.triangle.branch"
        case .mistral:          return "wind"
        case .ollama:           return "shippingbox"
        case .localCLI:         return "terminal"
        case .foundationModels: return "applelogo"
        case .mlx:              return "hexagon"
        case .custom:           return "slider.horizontal.3"
        case .elevenLabs:       return "waveform"
        case .deepgram:         return "waveform.path.ecg"
        case .soniox:           return "waveform.circle"
        case .speechmatics:     return "waveform.badge.mic"
        }
    }

    static func tint(for provider: AIProvider) -> Color {
        switch provider {
        case .openAI:           return Palette.neutral
        case .anthropic:        return Palette.warn
        case .gemini:           return Palette.transcribe
        case .groq:             return Palette.warn
        case .cerebras:         return Palette.recording
        case .openRouter:       return Palette.enhance
        case .mistral:          return Palette.transcribe
        case .ollama:           return Palette.enhance
        case .localCLI:         return Palette.success
        case .foundationModels: return Palette.neutral
        case .mlx:              return Palette.success
        case .custom:           return Palette.neutral
        case .elevenLabs, .deepgram, .soniox, .speechmatics:
            return Palette.transcribe
        }
    }

    static func displayName(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic:        return "Claude"
        case .foundationModels: return "Apple"
        case .mlx:              return "MLX"
        default:                return provider.rawValue
        }
    }
}

import Foundation

struct TranscriptionModelManifest: Codable {
    let schema_version: Int
    let channel: String
    let manifest_generated_at: String
    let models: [TranscriptionModelEntry]
}

struct TranscriptionModelEntry: Codable {
    let id: String
    let family: String
    let display_name: String
    let description: String
    let framework: String
    let weights: TranscriptionModelWeights
    let license: String
    let license_url: String
    let languages: [String]
    let is_multilingual: Bool
    let wer: [String: Double?]
    let wer_source: String
    let rtf_p50: [String: Double?]
    let rtf_p50_source: String
    let first_token_ms_p50: Double?
    let peak_ram_mb: Int?
    let supports_streaming: Bool
    let supports_word_timestamps: Bool
    let supports_translation: Bool
    let min_macos: String
    let is_default: Bool
    let is_experimental: Bool
    let is_deprecated: Bool
    let release_date: String
    let notes: String
}

struct TranscriptionModelWeights: Codable {
    let size_gb: Double
    let source_url: String
    let checksum_sha256: String?
}

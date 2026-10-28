#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Guided-generation output shape. One field, so the model's only legal answer
/// is the cleaned transcript — a conversational preamble or a sign-off has
/// nowhere to go. `stripPreamble` still runs downstream, now as a belt for the
/// plain-text path and for a model that ignores the schema.
@available(macOS 26.0, *)
@Generable
struct CleanedTranscript {
    @Guide(description: "The transcript, cleaned. The same words, nothing added and nothing explained.")
    var cleaned: String
}
#endif

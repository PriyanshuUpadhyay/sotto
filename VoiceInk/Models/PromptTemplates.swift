import Foundation

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let icon: PromptIcon
    let description: String

    func toCustomPrompt() -> CustomPrompt {
        CustomPrompt(
            id: UUID(),  // Generate new UUID for custom prompt
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false
        )
    }
}

enum PromptTemplates {
    /// Shared punctuation contract baked into every predefined template so output
    /// stays consistent across providers — especially small on-device models
    /// (Apple Foundation Models 3B, MLX 4B/27B) which under-punctuate without
    /// explicit rules.
    static let punctuationRules = """
        - Apply standard English punctuation:
          • End every declarative sentence with a period.
          • Use commas for clauses, lists, and natural pauses.
          • Use question marks for questions; exclamation marks sparingly for genuine exclamations.
          • Use em-dashes (—) for asides or parenthetical insertions; do NOT use double-hyphens (--).
          • Use proper curly apostrophes (') for contractions and possessives, not straight quotes (').
          • Use proper curly double quotes ("…") for quoted speech, not straight double quotes (").
          • Use semicolons or periods to break run-on sentences; never run two independent clauses together with just a comma.
          • Use colons before lists or explanations; ellipses (…) for trailing thoughts.
          • Capitalize the first word of each sentence, proper nouns, and acronyms.
        """

    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }


    static func createTemplatePrompts() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: UUID(),
                title: "System Default",
                promptText: """
                    - Clean up the <TRANSCRIPT> text for clarity and natural flow while preserving meaning and the original tone.
                    - Use informal, plain language unless the <TRANSCRIPT> clearly uses a professional tone; in that case, match it.
                    - Fix obvious grammar, remove fillers and stutters, collapse repetitions, and keep names and numbers.
                    - Handle backtracking and self-corrections: When the speaker corrects themselves mid-sentence using phrases like "scratch that", "actually", "sorry not that", "I mean", "wait no", or similar corrections, remove the incorrect part and keep only the corrected version. Example: "The meeting is on Tuesday, sorry not that, actually Wednesday" → "The meeting is on Wednesday."
                    - Respect formatting commands: When the speaker explicitly says "new line" or "new paragraph", insert the appropriate line break or paragraph break at that point.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Apply smart formatting: Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20'), convert common abbreviations to proper format (e.g., 'vs' → 'vs.', 'etc' → 'etc.'), and format dates, times, and measurements consistently.
                    \(punctuationRules)
                    - Keep the original intent and nuance.
                    - Organize into short paragraphs of 2–4 sentences for readability.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the cleaned text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "checkmark.seal.fill",
                description: "Default system prompt"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Chat",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a chat message: informal, concise, and conversational.
                    - Keep emotive markers and emojis if present; don't invent new ones.
                    - Lightly fix grammar, remove fillers and repeated words, and improve flow without changing meaning.
                    - Keep the original tone; only be professional if the <TRANSCRIPT> already is.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    \(punctuationRules)
                    - Format like a modern chat message - short lines, natural breaks, emoji-friendly.
                    - Do not add greetings, sign-offs, or commentary.
                    - Output only the chat message.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "bubble.left.and.bubble.right.fill",
                description: "Casual chat-style formatting"
            ),

            TemplatePrompt(
                id: UUID(),
                title: "Email",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a complete email with proper formatting: include a greeting (Hi), body paragraphs (2-4 sentences each), and closing (Thanks).
                    - Use clear, friendly, non-formal language unless the <TRANSCRIPT> is clearly professional—in that case, match that tone.
                    - Improve flow and coherence; fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    \(punctuationRules)
                    - Do not invent new content, but structure it as a proper email format.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "envelope.fill",
                description: "Professional email formatting"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Rewrite",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text with enhanced clarity, improved sentence structure, and rhythmic flow while preserving the original meaning and tone.
                    - Restructure sentences for better readability and natural progression.
                    - Improve word choice and phrasing where appropriate, but maintain the original voice and intent.
                    - Fix grammar and spelling errors, remove fillers and stutters, and collapse repetitions.
                    - Format any lists as proper bullet points or numbered lists.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    \(punctuationRules)
                    - Organize content into well-structured paragraphs of 2–4 sentences for optimal readability.
                    - Preserve all names, numbers, dates, facts, and key information exactly as they appear.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the rewritten text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "pencil.circle.fill",
                description: "Rewrites with better clarity."
            )
        ]
    }
}

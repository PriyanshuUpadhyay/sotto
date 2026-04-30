import Foundation
import SwiftData
import os

/// W12.C pre-enhance pipeline pass. Replaces `\b<trigger>\b` occurrences in
/// the raw transcript with the user's expansion text BEFORE the AI cleanup
/// pass runs. See plan
/// `docs/superpowers/plans/W12C-voice-snippets.md` §Migration policy #2.
///
/// Threading: `@MainActor` because all callers (TranscriptionPipeline + UI
/// CRUD) are MainActor-bound. The cache lives in-memory; SwiftData itself
/// owns the persistence.
@MainActor
final class SnippetExpansionService {
    static let shared = SnippetExpansionService()

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SnippetExpansionService"
    )

    /// Cached active-snippet entries (filtered to `isEnabled == true`).
    /// Refilled on every cache-miss. See plan §Migration policy #7.
    private var cache: [CacheEntry] = []
    private var cacheVersion: Int = -1
    private var cachedFetchCount: Int = -1

    private struct CacheEntry {
        let trigger: String
        let expansion: String
        let regex: NSRegularExpression
    }

    private init() {}

    /// Manually invalidate the cache. Called from CRUD UI (Add / Edit / Delete)
    /// + ImportExportService import path so the next pipeline call reflects
    /// the change immediately. See plan §Migration policy #7.
    func invalidateCache() {
        cache.removeAll()
        cacheVersion = -1
        cachedFetchCount = -1
    }

    /// Returns the input text with all enabled-snippet triggers expanded,
    /// plus the count of triggers that matched. When zero snippets are
    /// defined OR none match, returns `(text, 0)` unchanged.
    /// Per plan §Migration policy #2 the no-match path MUST NOT log.
    func expand(text: String, modelContext: ModelContext) -> (expanded: String, expandedCount: Int) {
        refreshCacheIfNeeded(modelContext: modelContext)

        guard !cache.isEmpty else { return (text, 0) }

        var working = text
        var totalCount = 0

        for entry in cache {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            let matches = entry.regex.numberOfMatches(in: working, options: [], range: range)
            guard matches > 0 else { continue }
            working = entry.regex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.expansion)
            )
            totalCount += matches
        }

        return (working, totalCount)
    }

    private func refreshCacheIfNeeded(modelContext: ModelContext) {
        // Lightweight version probe: SwiftData fetchCount is a small query and
        // changes whenever the table changes (insert / delete). Editor-sheet
        // saves additionally call invalidateCache() to cover same-count edits
        // (e.g. trigger or expansion body changes). See plan §Risks #5.
        let descriptor = FetchDescriptor<Snippet>()
        let liveCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        if liveCount == cachedFetchCount && cacheVersion >= 0 { return }

        let snippets = (try? modelContext.fetch(descriptor)) ?? []
        let active = snippets
            .filter { $0.isEnabled && !$0.trigger.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }

        cache = active.compactMap { snippet in
            guard let regex = compileRegex(for: snippet.trigger) else { return nil }
            return CacheEntry(trigger: snippet.trigger, expansion: snippet.expansion, regex: regex)
        }
        cacheVersion += 1
        cachedFetchCount = liveCount
    }

    /// Build a word-boundary regex that handles triggers starting OR ending
    /// with non-word characters (`;sig`, `:date`). Uses lookbehind / lookahead
    /// + alternation so a `;` directly preceded by whitespace OR string-edge
    /// is treated as a boundary. Per plan §Migration policy #9.
    ///
    /// Pattern: `(?:\b|^|(?<=\s))<escaped-trigger>(?:\b|$|(?=\s))`
    /// - Leading anchor fires on word-boundary OR string-start OR
    ///   after-whitespace (so ` ;sig` and `;sig` at start both match).
    /// - Trailing anchor is symmetric.
    /// - Pure-alphanumeric triggers (`sig`) collapse to plain `\b…\b`.
    /// - Trigger embedded inside a longer word (e.g. `;sig` in
    ///   `assignment;sigh`) is correctly skipped — neither anchor fires.
    private func compileRegex(for trigger: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: trigger)
        let pattern = #"(?:\b|^|(?<=\s))"# + escaped + #"(?:\b|$|(?=\s))"#
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            logger.error("snippet regex compile failed for trigger \(trigger, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

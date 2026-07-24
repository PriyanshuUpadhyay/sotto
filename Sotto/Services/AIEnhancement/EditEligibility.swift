import Foundation

enum EditEligibility {
    /// Returns the EditKind if `final` is a learnable correction of `enhanced`,
    /// else nil (drop). Inputs need NOT be pre-normalized — normalized internally.
    static func classify(enhanced rawEnhanced: String, final rawFinal: String) -> EditKind? {
        let enhanced = EditTextNormalizer.normalize(rawEnhanced)
        let final = EditTextNormalizer.normalize(rawFinal)

        guard !enhanced.isEmpty, !final.isEmpty else { return nil }
        guard enhanced != final else { return nil }                         // whitespace-only / identical

        // Pure duplication: final is enhanced concatenated N>=2 times. A paste /
        // capture artifact (no human correction), and the missing space at the
        // seam ("operations.Redo") defeats the token-prefix guard below, so it
        // must be caught on the whitespace-stripped form first.
        let eBare = enhanced.filter { !$0.isWhitespace }
        let fBare = final.filter { !$0.isWhitespace }
        if !eBare.isEmpty, fBare.count > eBare.count, fBare.count % eBare.count == 0,
           String(repeating: eBare, count: fBare.count / eBare.count) == fBare { return nil }

        let eTok = enhanced.split(separator: " ").map(String.init)
        let fTok = final.split(separator: " ").map(String.init)

        // Compare append/prepend on "core" tokens (edge punctuation stripped,
        // lowercased) so a trailing "." or casing shift at the boundary doesn't
        // mask a pure continuation ("migrations." vs "migrations and …").
        let eCore = eTok.map(coreToken)
        let fCore = fTok.map(coreToken)
        // Pure append: final == enhanced + trailing tokens (continuation typing)
        if fCore.count > eCore.count, Array(fCore.prefix(eCore.count)) == eCore { return nil }
        // Pure prepend: final == leading tokens + enhanced
        if fCore.count > eCore.count, Array(fCore.suffix(eCore.count)) == eCore { return nil }

        // Whole-text divergence: Jaccard overlap of token sets too low → not a correction
        let eSet = Set(eTok.map { $0.lowercased() })
        let fSet = Set(fTok.map { $0.lowercased() })
        let overlap = Double(eSet.intersection(fSet).count) / Double(max(eSet.union(fSet).count, 1))
        guard overlap >= 0.6 else { return nil }

        // Classification (coarse; the analyzer refines). Casing/spelling token swaps
        // with high overlap → spelling/style; large length delta within overlap → style.
        let lenDelta = abs(enhanced.count - final.count)
        if lenDelta <= 4 { return .spelling }
        return .style
    }

    /// Lowercased token with leading/trailing punctuation trimmed, so boundary
    /// punctuation/casing doesn't defeat the append/prepend equality checks.
    private static func coreToken(_ t: String) -> String {
        t.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}

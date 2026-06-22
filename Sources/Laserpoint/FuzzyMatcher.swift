import Foundation

/// A lightweight fuzzy subsequence matcher in the spirit of Sublime Text / fzf.
///
/// `query` matches `candidate` if every character of `query` appears in
/// `candidate` in order (case-insensitively). A score rewards matches that are
/// contiguous, sit at word boundaries, or start the string, so that typing
/// "ps" ranks "Photoshop" above "Pages".
enum FuzzyMatcher {
    /// Returns a score if `query` is a subsequence of `candidate`, else `nil`.
    /// Higher is better. An empty query matches everything with score 0.
    static func score(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }

        let q = Array(query.lowercased())
        let c = Array(candidate)
        let cl = Array(candidate.lowercased())

        var qi = 0
        var score = 0
        var lastMatch = -1
        var consecutive = 0

        for ci in 0..<c.count {
            guard qi < q.count else { break }
            guard cl[ci] == q[qi] else { continue }

            var bonus = 0

            // Bonus for matching at the very start.
            if ci == 0 { bonus += 15 }

            // Bonus for matching at a word boundary (after space, separator, or
            // a lower→upper case transition like "shОp" in "PhotoShop").
            if ci > 0 {
                let prev = c[ci - 1]
                if prev == " " || prev == "-" || prev == "_" || prev == "." {
                    bonus += 10
                } else if c[ci].isUppercase && prev.isLowercase {
                    bonus += 10
                }
            }

            // Bonus for consecutive matches.
            if lastMatch == ci - 1 {
                consecutive += 1
                bonus += 5 * consecutive
            } else {
                consecutive = 0
            }

            score += 10 + bonus
            lastMatch = ci
            qi += 1
        }

        // Only a match if every query character was consumed.
        guard qi == q.count else { return nil }

        // Prefer shorter candidates when scores are otherwise close.
        score -= c.count / 4

        return score
    }
}

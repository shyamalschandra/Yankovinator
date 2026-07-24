// Copyright (C) 2025, Shyamal Suhana Chandra
// Unsupervised lexical substitution via NLEmbedding + syllable constraints

import Foundation
import NaturalLanguage

/// Unsupervised MLM-style lexical substitution.
/// Finds syllable-matched neighbors of a word using Apple's word embeddings
/// (no labeled paraphrase data required).
public struct LexicalSubstitutionEngine {

    public struct Substitution: Equatable {
        public let original: String
        public let candidate: String
        public let syllables: Int
        public let distance: Double

        public init(original: String, candidate: String, syllables: Int, distance: Double) {
            self.original = original
            self.candidate = candidate
            self.syllables = syllables
            self.distance = distance
        }
    }

    private let embedding: NLEmbedding?
    private let syllableCounter: SyllableCounter.Type
    private let maxDistance: Double

    public init(
        maxDistance: Double = 1.15,
        syllableCounter: SyllableCounter.Type = SyllableCounter.self
    ) {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
        self.syllableCounter = syllableCounter
        self.maxDistance = maxDistance
    }

    /// Whether embedding-backed substitution is available on this system.
    public var isAvailable: Bool {
        embedding != nil
    }

    /// Suggest syllable-matched substitutes for a single word.
    public func substitutes(
        for word: String,
        requiredSyllables: Int? = nil,
        excludeWords: Set<String> = [],
        theme: [String] = [],
        maxResults: Int = 10
    ) -> [Substitution] {
        let cleaned = normalize(word)
        guard !cleaned.isEmpty else { return [] }

        let targetSyllables = requiredSyllables ?? syllableCounter.countSyllables(in: cleaned)
        guard targetSyllables > 0 else { return [] }

        var ranked: [Substitution] = []
        var seen = excludeWords.union([cleaned])

        if let embedding, embedding.contains(cleaned) {
            // neighbors(for:) can crash for OOV tokens; only query in-vocabulary words.
            let neighborNames = embedding.neighbors(for: cleaned, maximumCount: max(40, maxResults * 6))
            for (neighbor, distance) in neighborNames {
                let candidate = normalize(neighbor)
                guard !candidate.isEmpty, !seen.contains(candidate) else { continue }
                guard embedding.contains(candidate) else { continue }
                guard distance <= maxDistance else { continue }

                let syllables = syllableCounter.countSyllables(in: candidate)
                guard syllables == targetSyllables else { continue }

                seen.insert(candidate)
                ranked.append(
                    Substitution(
                        original: cleaned,
                        candidate: candidate,
                        syllables: syllables,
                        distance: distance
                    )
                )
            }
        }

        // Theme-biased re-rank: prefer neighbors near theme keywords in embedding space.
        if !theme.isEmpty, let embedding {
            ranked.sort { lhs, rhs in
                themeAffinity(lhs.candidate, theme: theme, embedding: embedding) >
                themeAffinity(rhs.candidate, theme: theme, embedding: embedding)
            }
        } else {
            ranked.sort { $0.distance < $1.distance }
        }

        return Array(ranked.prefix(maxResults))
    }

    /// Build per-position substitution lists for a lyric line (word-by-word).
    public func substitutesForLine(
        _ line: String,
        excludeWords: Set<String> = [],
        theme: [String] = [],
        maxPerPosition: Int = 8
    ) -> [[Substitution]] {
        let words = syllableCounter.analyzeWordSyllables(in: line)
        return words.map { item in
            substitutes(
                for: item.word,
                requiredSyllables: item.syllables,
                excludeWords: excludeWords,
                theme: theme,
                maxResults: maxPerPosition
            )
        }
    }

    /// Convert substitutions into the dictionary suggestion shape used by ParodyGenerator.
    public func asWordSuggestions(
        for line: String,
        excludeWords: Set<String> = [],
        theme: [String] = [],
        maxPerPosition: Int = 8
    ) -> [[(word: String, definition: String)]] {
        substitutesForLine(
            line,
            excludeWords: excludeWords,
            theme: theme,
            maxPerPosition: maxPerPosition
        ).map { position in
            position.map { sub in
                (
                    word: sub.candidate,
                    definition: "unsupervised embedding neighbor of '\(sub.original)' (d=\(String(format: "%.3f", sub.distance)))"
                )
            }
        }
    }

    private func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter }
    }

    private func themeAffinity(
        _ word: String,
        theme: [String],
        embedding: NLEmbedding
    ) -> Double {
        var best = -Double.infinity
        for themeWord in theme {
            let cleaned = normalize(themeWord)
            guard !cleaned.isEmpty else { continue }
            guard embedding.contains(word), embedding.contains(cleaned) else { continue }
            let distance = embedding.distance(between: word, and: cleaned)
            // Smaller distance => higher affinity
            best = max(best, -distance)
        }
        return best
    }
}

// Copyright (C) 2025, Shyamal Suhana Chandra
// Unsupervised next-line surprise / coherence critic

import Foundation
import NaturalLanguage

/// Scores how well a candidate line continues previous context.
/// Combines a local unsupervised embedding signal with an optional Ollama surprise probe.
public struct CoherenceCritic {

    public struct Score: Equatable {
        /// Higher is better coherence in [0, 1].
        public let coherence: Double
        /// Approximate surprise / unpredictability in [0, 1] (higher = more surprising).
        public let surprise: Double
        public let method: String
        public let notes: String

        public init(coherence: Double, surprise: Double, method: String, notes: String = "") {
            self.coherence = coherence
            self.surprise = surprise
            self.method = method
            self.notes = notes
        }
    }

    private let embedding: NLEmbedding?
    private let ollamaClient: OllamaClient?
    /// Preferred coherence band: not too predictable, not random.
    public var minCoherence: Double
    public var maxSurprise: Double

    public init(
        ollamaClient: OllamaClient? = nil,
        minCoherence: Double = 0.35,
        maxSurprise: Double = 0.85
    ) {
        // Prefer sentence embeddings when available; fall back to word embeddings.
        if #available(macOS 13.0, iOS 16.0, *) {
            self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
                ?? NLEmbedding.wordEmbedding(for: .english)
        } else {
            self.embedding = NLEmbedding.wordEmbedding(for: .english)
        }
        self.ollamaClient = ollamaClient
        self.minCoherence = minCoherence
        self.maxSurprise = maxSurprise
    }

    /// Local unsupervised score using sentence/word embeddings (no LLM required).
    public func scoreLocally(
        candidate: String,
        previousLines: [String],
        keywords: [String: String] = [:]
    ) -> Score {
        let context = previousLines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !context.isEmpty else {
            return Score(coherence: 0.7, surprise: 0.4, method: "local-bootstrap", notes: "no prior context")
        }

        guard let embedding else {
            let overlap = lexicalOverlap(candidate, context: context, keywords: keywords)
            return Score(
                coherence: overlap,
                surprise: 1.0 - overlap,
                method: "lexical-overlap",
                notes: "embedding unavailable"
            )
        }

        let contextText = context.suffix(6).joined(separator: " ")
        let distance: Double
        if embedding.contains(contextText), embedding.contains(candidate) {
            distance = embedding.distance(between: contextText, and: candidate)
        } else {
            // Fall back to averaged word distances
            distance = averageWordDistance(candidate, context: contextText, embedding: embedding)
        }

        // Map distance to coherence/surprise. Typical NL distances are small for related text.
        let normalized = min(max(distance / 1.8, 0.0), 1.0)
        let coherence = 1.0 - normalized
        let themeBoost = themeOverlapBoost(candidate, keywords: keywords)
        let adjusted = min(max(coherence + themeBoost, 0.0), 1.0)

        return Score(
            coherence: adjusted,
            surprise: 1.0 - adjusted,
            method: "embedding-distance",
            notes: "distance=\(String(format: "%.3f", distance))"
        )
    }

    /// Full critic: local score, optionally refined by Ollama surprise probe.
    public func score(
        candidate: String,
        previousLines: [String],
        keywords: [String: String] = [:]
    ) async -> Score {
        let local = scoreLocally(candidate: candidate, previousLines: previousLines, keywords: keywords)
        guard let ollamaClient else { return local }

        do {
            let llmSurprise = try await ollamaClient.estimateNextLineSurprise(
                previousLines: previousLines,
                candidateLine: candidate,
                keywords: keywords
            )
            let blendedSurprise = (local.surprise * 0.45) + (llmSurprise * 0.55)
            let blendedCoherence = 1.0 - blendedSurprise
            return Score(
                coherence: min(max(blendedCoherence, 0.0), 1.0),
                surprise: min(max(blendedSurprise, 0.0), 1.0),
                method: "embedding+ollama",
                notes: local.notes
            )
        } catch {
            return local
        }
    }

    /// Whether the candidate should be regenerated.
    public func shouldReject(_ score: Score) -> Bool {
        score.coherence < minCoherence || score.surprise > maxSurprise
    }

    private func lexicalOverlap(
        _ candidate: String,
        context: [String],
        keywords: [String: String]
    ) -> Double {
        let candidateWords = tokenize(candidate)
        guard !candidateWords.isEmpty else { return 0.0 }
        let contextWords = Set(context.flatMap { tokenize($0) })
        let keywordWords = Set(keywords.keys.map { $0.lowercased() })
        let overlap = candidateWords.intersection(contextWords.union(keywordWords)).count
        return min(Double(overlap) / Double(max(candidateWords.count, 1)), 1.0)
    }

    private func themeOverlapBoost(_ candidate: String, keywords: [String: String]) -> Double {
        guard !keywords.isEmpty else { return 0.0 }
        let lower = candidate.lowercased()
        let hits = keywords.keys.filter { lower.contains($0.lowercased()) }.count
        return min(Double(hits) * 0.08, 0.24)
    }

    private func averageWordDistance(
        _ candidate: String,
        context: String,
        embedding: NLEmbedding
    ) -> Double {
        let candidateWords = Array(tokenize(candidate))
        let contextWords = Array(tokenize(context))
        guard !candidateWords.isEmpty, !contextWords.isEmpty else { return 1.0 }

        var total = 0.0
        var count = 0.0
        for word in candidateWords.prefix(12) {
            var best = 1.5
            for contextWord in contextWords.prefix(24) {
                if embedding.contains(word), embedding.contains(contextWord) {
                    best = min(best, embedding.distance(between: word, and: contextWord))
                }
            }
            total += best
            count += 1.0
        }
        return count > 0 ? total / count : 1.0
    }

    private func tokenize(_ text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: Set<String> = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased().filter { $0.isLetter }
            if word.count > 2 {
                words.insert(word)
            }
            return true
        }
        return words
    }
}

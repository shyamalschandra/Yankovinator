// Copyright (C) 2025, Shyamal Suhana Chandra
// Unsupervised rhyme clustering from ending phonetic + embedding features

import Foundation
import NaturalLanguage

/// Discovers rhyme groups by clustering line-final words without labeled rhyme data.
public struct UnsupervisedRhymeClustering {

    public struct ClusterResult: Equatable {
        public let rhymeGroups: [String]
        public let scheme: String
        public let lastWords: [String]
        public let method: String

        public init(rhymeGroups: [String], scheme: String, lastWords: [String], method: String) {
            self.rhymeGroups = rhymeGroups
            self.scheme = scheme
            self.lastWords = lastWords
            self.method = method
        }
    }

    private let embedding: NLEmbedding?
    private let distanceThreshold: Double

    public init(distanceThreshold: Double = 0.42) {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
        self.distanceThreshold = distanceThreshold
    }

    /// Cluster rhyme scheme for non-empty lyric lines.
    public func clusterRhymeScheme(from lyrics: [String]) -> ClusterResult {
        guard !lyrics.isEmpty else {
            return ClusterResult(rhymeGroups: [], scheme: "", lastWords: [], method: "empty")
        }

        let lastWords = lyrics.map { Self.extractLastWord(from: $0) }
        var assignments = Array(repeating: -1, count: lastWords.count)
        var nextCluster = 0

        for i in 0..<lastWords.count {
            if assignments[i] != -1 { continue }

            assignments[i] = nextCluster
            for j in (i + 1)..<lastWords.count where assignments[j] == -1 {
                if rhymeDistance(lastWords[i], lastWords[j]) <= distanceThreshold {
                    assignments[j] = nextCluster
                }
            }
            nextCluster += 1
        }

        let letters = assignments.map { index -> String in
            let scalar = UnicodeScalar(65 + (index % 26))!
            let base = String(scalar)
            let cycle = index / 26
            return cycle == 0 ? base : "\(base)\(cycle)"
        }

        return ClusterResult(
            rhymeGroups: letters,
            scheme: letters.joined(),
            lastWords: lastWords,
            method: embedding == nil ? "phonetic" : "phonetic+embedding"
        )
    }

    /// Convenience matching `RhymeSchemeAnalyzer.detectRhymeScheme` shape.
    public static func detectRhymeScheme(from lyrics: [String]) -> (rhymeGroups: [String], scheme: String) {
        let result = UnsupervisedRhymeClustering().clusterRhymeScheme(from: lyrics)
        return (result.rhymeGroups, result.scheme)
    }

    /// Distance in [0, 1+], lower means stronger rhyme affinity.
    public func rhymeDistance(_ word1: String, _ word2: String) -> Double {
        let a = Self.normalize(word1)
        let b = Self.normalize(word2)
        guard !a.isEmpty, !b.isEmpty else { return 2.0 }
        if a == b { return 0.0 }

        // Strong phonetic family match (e.g. high/sky, light/night)
        if Self.rhymeFamiliesMatch(a, b) {
            return 0.12
        }

        var score = 0.0
        var weight = 0.0

        // Suffix identity (classic orthographic rhyme cue)
        let suffixLen = min(4, min(a.count, b.count))
        let suffixA = String(a.suffix(suffixLen))
        let suffixB = String(b.suffix(suffixLen))
        let suffixScore = suffixA == suffixB ? 0.0 : (Self.sharedSuffixLength(a, b) >= 2 ? 0.25 : 0.7)
        score += suffixScore * 0.45
        weight += 0.45

        // Vowel coda similarity
        let vowelsA = String(a.filter { "aeiouy".contains($0) }.suffix(2))
        let vowelsB = String(b.filter { "aeiouy".contains($0) }.suffix(2))
        let vowelScore: Double
        if vowelsA.isEmpty || vowelsB.isEmpty {
            vowelScore = 0.5
        } else if vowelsA == vowelsB {
            vowelScore = 0.0
        } else if vowelsA.suffix(1) == vowelsB.suffix(1) {
            vowelScore = 0.3
        } else {
            vowelScore = 0.8
        }
        score += vowelScore * 0.25
        weight += 0.25

        // Embedding neighborhood (unsupervised semantic/phonetic proxy)
        if let embedding, embedding.contains(a), embedding.contains(b) {
            let d = embedding.distance(between: a, and: b)
            // NLEmbedding distances are typically small for related words; clamp.
            let embScore = min(max(d / 1.5, 0.0), 1.0)
            score += embScore * 0.30
            weight += 0.30
        }

        return weight > 0 ? score / weight : 1.0
    }

    /// Coarse grapheme rhyme families used when exact suffixes diverge.
    private static func rhymeFamiliesMatch(_ a: String, _ b: String) -> Bool {
        let families: [[String]] = [
            ["igh", "y", "ie", "ye"],
            ["ight", "ite", "yte"],
            ["ough", "uff", "off"],
            ["ation", "otion"],
            ["ar", "ahr"],
            ["oo", "ue", "ew"]
        ]
        for family in families {
            let aHit = family.contains { a.hasSuffix($0) }
            let bHit = family.contains { b.hasSuffix($0) }
            if aHit && bHit {
                return true
            }
        }
        return false
    }

    private static func sharedSuffixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        for (ca, cb) in zip(a.reversed(), b.reversed()) {
            if ca == cb {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter }
    }

    private static func extractLastWord(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        var words: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            words.append(String(trimmed[range]))
            return true
        }
        return normalize(words.last ?? "")
    }
}

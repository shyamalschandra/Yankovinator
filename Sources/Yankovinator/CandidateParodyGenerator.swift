// Copyright (C) 2025, Shyamal Suhana Chandra
// Multi-candidate parody generation with coherence ranking

import Foundation

/// One scored parody candidate.
public struct ParodyCandidateResult: Sendable, Equatable {
    public let index: Int
    public let lines: [String]
    /// Mean line-to-line local coherence in [0, 1]; higher is better.
    public let score: Double

    public init(index: Int, lines: [String], score: Double) {
        self.index = index
        self.lines = lines
        self.score = score
    }

    public var text: String {
        lines.joined(separator: "\n")
    }
}

/// Generates multiple independent parodies for the same song/theme and ranks them.
public enum CandidateParodyGenerator {
    public static let defaultCandidates = 1
    public static let recommendedCandidates = 10
    public static let maxCandidates = 32

    public static func clampCandidates(_ requested: Int) -> Int {
        max(1, min(requested, maxCandidates))
    }

    public static func validateCandidates(_ requested: Int) throws {
        guard requested >= 1, requested <= maxCandidates else {
            throw ParallelJobError.invalidCandidateCount(requested, max: maxCandidates)
        }
    }

    /// Score a full parody (global objective favors the weakest line).
    public static func scoreParody(
        lines: [String],
        keywords: [String: String],
        originalLyrics: [String]? = nil,
        dictionary: OEDDictionary? = nil,
        critic: CoherenceCritic = CoherenceCritic()
    ) -> Double {
        guard let originalLyrics, originalLyrics.count == lines.count else {
            return legacyCoherenceOnly(lines: lines, keywords: keywords, critic: critic)
        }
        let summary = ParodyFitScorer.scoreSong(
            originalLyrics: originalLyrics,
            parodyLines: lines,
            keywords: keywords,
            dictionary: dictionary
        )
        return summary.globalScore
    }

    private static func legacyCoherenceOnly(
        lines: [String],
        keywords: [String: String],
        critic: CoherenceCritic
    ) -> Double {
        var previous: [String] = []
        var total = 0.0
        var count = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                previous.append(line)
                continue
            }
            let score = critic.scoreLocally(
                candidate: trimmed,
                previousLines: previous,
                keywords: keywords
            )
            total += score.coherence
            count += 1
            previous.append(trimmed)
        }

        return count > 0 ? total / Double(count) : 0.0
    }

    /// Generate `candidates` parodies in parallel (capped by `workers`), rank by coherence, return best + all.
    public static func generateRanked(
        originalLyrics: [String],
        keywords: [String: String],
        candidates: Int,
        workers: Int,
        showProgress: Bool = false,
        ollamaURL: String = "http://localhost:11434",
        ollamaModel: String = "llama3.2:3b",
        refinementPasses: Int = 2
    ) async throws -> (best: ParodyCandidateResult, all: [ParodyCandidateResult]) {
        let count = clampCandidates(candidates)
        let indexes = Array(1...count)

        let results: [ParodyCandidateResult] = try await ParallelJobRunner.map(
            items: indexes,
            workers: workers,
            showProgress: showProgress,
            progressLabel: "Candidates"
        ) { index in
            let generator = ParodyGenerator(
                ollamaBaseURL: ollamaURL,
                ollamaModel: ollamaModel
            )
            let lines = try await generator.generateParody(
                originalLyrics: originalLyrics,
                keywords: keywords,
                refinementPasses: refinementPasses,
                verbose: false
            )
            let score = scoreParody(lines: lines, keywords: keywords, originalLyrics: originalLyrics)
            return ParodyCandidateResult(index: index, lines: lines, score: score)
        }

        let ranked = results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
        guard let best = ranked.first else {
            throw ParallelJobError.noCandidatesProduced
        }
        return (best: best, all: ranked)
    }
}

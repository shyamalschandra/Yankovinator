// Copyright (C) 2025, Shyamal Suhana Chandra
// Multi-constraint fit scoring for parody lines and full songs

import Foundation

/// Per-line fitness in \[0, 1\] across syllables, POS, coherence, and theme.
public struct ParodyFitScore: Sendable, Equatable {
    public let lineTotalSyllables: Double
    public let wordSyllablePattern: Double
    public let wordCountMatch: Double
    public let partOfSpeech: Double
    public let coherence: Double
    public let theme: Double
    public let dictionaryUsage: Double
    public let composite: Double

    public static let defaultCorrectnessThreshold = 0.90

    public var fitsCorrectly: Bool {
        composite >= Self.defaultCorrectnessThreshold
            && wordSyllablePattern >= 0.95
            && lineTotalSyllables >= 0.98
            && wordCountMatch >= 0.99
            && partOfSpeech >= 0.80
            && coherence >= 0.25
    }

    public init(
        lineTotalSyllables: Double,
        wordSyllablePattern: Double,
        wordCountMatch: Double,
        partOfSpeech: Double,
        coherence: Double,
        theme: Double,
        dictionaryUsage: Double,
        composite: Double
    ) {
        self.lineTotalSyllables = lineTotalSyllables
        self.wordSyllablePattern = wordSyllablePattern
        self.wordCountMatch = wordCountMatch
        self.partOfSpeech = partOfSpeech
        self.coherence = coherence
        self.theme = theme
        self.dictionaryUsage = dictionaryUsage
        self.composite = composite
    }
}

public enum ParodyFitScorer {
    private static let critic = CoherenceCritic()

    /// Score one parody line against its original (and prior parody context).
    public static func scoreLine(
        original: String,
        parody: String,
        previousParodyLines: [String],
        keywords: [String: String],
        dictionary: OEDDictionary? = nil
    ) -> ParodyFitScore {
        let oTrim = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let pTrim = parody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !oTrim.isEmpty else {
            return perfectIfEmptyParody(pTrim.isEmpty)
        }
        guard !pTrim.isEmpty else {
            return zeroFit
        }

        let targetLineSyllables = SyllableCounter.countSyllablesInLine(oTrim)
        let parodyLineSyllables = SyllableCounter.countSyllablesInLine(pTrim)
        let lineTotal = syllableCloseness(target: targetLineSyllables, actual: parodyLineSyllables)

        let origWords = SyllableCounter.analyzeWordSyllablesUnsafe(in: oTrim)
        let paraWords = SyllableCounter.analyzeWordSyllablesUnsafe(in: pTrim)
        let wordPattern = wordSyllablePatternScore(original: origWords.map(\.syllables), parody: paraWords.map(\.syllables))
        let wordCount = wordCountScore(originalCount: origWords.count, parodyCount: paraWords.count)

        let pos = PartOfSpeechAnalyzer.lineAlignmentScore(original: oTrim, parody: pTrim)
        let coherence = critic.scoreLocally(
            candidate: pTrim,
            previousLines: previousParodyLines,
            keywords: keywords
        ).coherence
        let theme = themeScore(line: pTrim, keywords: keywords)
        let dictUsage = dictionaryUsageScore(line: pTrim, dictionary: dictionary)

        let composite =
            0.22 * lineTotal
            + 0.24 * wordPattern
            + 0.10 * wordCount
            + 0.22 * pos
            + 0.12 * coherence
            + 0.06 * theme
            + 0.04 * dictUsage

        return ParodyFitScore(
            lineTotalSyllables: lineTotal,
            wordSyllablePattern: wordPattern,
            wordCountMatch: wordCount,
            partOfSpeech: pos,
            coherence: coherence,
            theme: theme,
            dictionaryUsage: dictUsage,
            composite: min(max(composite, 0.0), 1.0)
        )
    }

    /// Song-level score; `globalScore` weights the weakest line heavily (maximin).
    public static func scoreSong(
        originalLyrics: [String],
        parodyLines: [String],
        keywords: [String: String],
        dictionary: OEDDictionary? = nil
    ) -> (lineScores: [ParodyFitScore?], meanComposite: Double, minComposite: Double, globalScore: Double, allFit: Bool) {
        guard originalLyrics.count == parodyLines.count else {
            return ([], 0, 0, 0, false)
        }

        var lineScores: [ParodyFitScore?] = []
        lineScores.reserveCapacity(originalLyrics.count)
        var previous: [String] = []
        var composites: [Double] = []

        for (orig, parody) in zip(originalLyrics, parodyLines) {
            let oTrim = orig.trimmingCharacters(in: .whitespacesAndNewlines)
            if oTrim.isEmpty {
                lineScores.append(nil)
                previous.append(parody)
                continue
            }
            let prior = previous.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let score = scoreLine(
                original: orig,
                parody: parody,
                previousParodyLines: prior,
                keywords: keywords,
                dictionary: dictionary
            )
            lineScores.append(score)
            composites.append(score.composite)
            previous.append(parody)
        }

        guard !composites.isEmpty else {
            return (lineScores, 0, 0, 0, true)
        }

        let mean = composites.reduce(0, +) / Double(composites.count)
        let minC = composites.min() ?? 0
        let global = 0.35 * mean + 0.65 * minC
        let allFit = lineScores.compactMap { $0 }.allSatisfy(\.fitsCorrectly)
        return (lineScores, mean, minC, global, allFit)
    }

    private static func syllableCloseness(target: Int, actual: Int) -> Double {
        guard target > 0 else { return actual == 0 ? 1.0 : 0.0 }
        let diff = abs(target - actual)
        if diff == 0 { return 1.0 }
        return max(0.0, 1.0 - Double(diff) / Double(max(target, 1)))
    }

    private static func wordCountScore(originalCount: Int, parodyCount: Int) -> Double {
        guard originalCount > 0 else { return parodyCount == 0 ? 1.0 : 0.0 }
        if originalCount == parodyCount { return 1.0 }
        let diff = abs(originalCount - parodyCount)
        return max(0.0, 1.0 - Double(diff) / Double(originalCount))
    }

    private static func wordSyllablePatternScore(original: [Int], parody: [Int]) -> Double {
        guard !original.isEmpty else { return parody.isEmpty ? 1.0 : 0.0 }
        let pairs = min(original.count, parody.count)
        guard pairs > 0 else { return 0.0 }
        var matches = 0
        for i in 0..<pairs where original[i] == parody[i] {
            matches += 1
        }
        let positional = Double(matches) / Double(original.count)
        let countPenalty = wordCountScore(originalCount: original.count, parodyCount: parody.count)
        return 0.85 * positional + 0.15 * countPenalty
    }

    private static func themeScore(line: String, keywords: [String: String]) -> Double {
        guard !keywords.isEmpty else { return 0.7 }
        let lower = line.lowercased()
        let hits = keywords.keys.filter { lower.contains($0.lowercased()) }.count
        if hits == 0 { return 0.35 }
        return min(1.0, 0.55 + Double(hits) * 0.15)
    }

    private static func dictionaryUsageScore(line: String, dictionary: OEDDictionary?) -> Double {
        guard let dictionary, dictionary.isLoaded() else { return 0.5 }
        let words = SyllableCounter.analyzeWordSyllablesUnsafe(in: line)
        let content = words.map(\.word).filter { w in
            let letters = w.filter(\.isLetter)
            return letters.count > 2
        }
        guard !content.isEmpty else { return 0.0 }
        var hits = 0
        for w in content {
            if dictionary.lookup(w) != nil { hits += 1 }
        }
        return Double(hits) / Double(content.count)
    }

    private static var zeroFit: ParodyFitScore {
        ParodyFitScore(
            lineTotalSyllables: 0,
            wordSyllablePattern: 0,
            wordCountMatch: 0,
            partOfSpeech: 0,
            coherence: 0,
            theme: 0,
            dictionaryUsage: 0,
            composite: 0
        )
    }

    private static func perfectIfEmptyParody(_ parodyEmpty: Bool) -> ParodyFitScore {
        if parodyEmpty {
            return ParodyFitScore(
                lineTotalSyllables: 1,
                wordSyllablePattern: 1,
                wordCountMatch: 1,
                partOfSpeech: 1,
                coherence: 1,
                theme: 1,
                dictionaryUsage: 1,
                composite: 1
            )
        }
        return zeroFit
    }
}

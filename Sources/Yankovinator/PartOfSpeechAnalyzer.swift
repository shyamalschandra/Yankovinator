// Copyright (C) 2025, Shyamal Suhana Chandra
// Word-by-word part-of-speech analysis (aligned with SyllableCounter tokenization)

import Foundation
import NaturalLanguage

/// Coarse part of speech for lyric slots (NaturalLanguage lexical class).
public enum PartOfSpeechTag: String, Sendable, Equatable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case preposition
    case conjunction
    case determiner
    case particle
    case interjection
    case number
    case other
    case unknown

    public var promptLabel: String {
        switch self {
        case .noun: return "noun"
        case .verb: return "verb"
        case .adjective: return "adjective"
        case .adverb: return "adverb"
        case .pronoun: return "pronoun"
        case .preposition: return "preposition"
        case .conjunction: return "conjunction"
        case .determiner: return "determiner"
        case .particle: return "particle"
        case .interjection: return "interjection"
        case .number: return "number"
        case .other: return "other"
        case .unknown: return "word"
        }
    }

    public static func from(_ tag: NLTag?) -> PartOfSpeechTag {
        guard let tag else { return .unknown }
        switch tag {
        case .noun: return .noun
        case .verb: return .verb
        case .adjective: return .adjective
        case .adverb: return .adverb
        case .pronoun: return .pronoun
        case .preposition: return .preposition
        case .conjunction: return .conjunction
        case .determiner: return .determiner
        case .particle: return .particle
        case .interjection: return .interjection
        case .number: return .number
        case .other, .classifier, .word: return .other
        default: return .unknown
        }
    }

    /// Whether a substitute may occupy the same slot as the original.
    public static func compatible(required original: PartOfSpeechTag, candidate: PartOfSpeechTag) -> Bool {
        if original == .unknown || candidate == .unknown { return true }
        if original == candidate { return true }
        // Allow close functional classes (e.g. determiner ↔ pronoun in lyrics).
        switch (original, candidate) {
        case (.determiner, .pronoun), (.pronoun, .determiner): return true
        case (.particle, .preposition), (.preposition, .particle): return true
        case (.other, _), (_, .other): return true
        default: return false
        }
    }

    /// Match Webster/OED headword tags (e.g. `n.`, `v. t.`, `adj.`).
    public static func matchesOEDTag(_ oedPOS: String?, required: PartOfSpeechTag) -> Bool {
        guard let oedPOS, !oedPOS.isEmpty else { return true }
        let lower = oedPOS.lowercased()
        switch required {
        case .noun: return lower.hasPrefix("n.")
        case .verb: return lower.hasPrefix("v.")
        case .adjective: return lower.contains("adj.")
        case .adverb: return lower.hasPrefix("adv.")
        case .pronoun: return lower.contains("pron.")
        case .preposition: return lower.contains("prep.")
        case .conjunction: return lower.contains("conj.")
        case .interjection: return lower.contains("interj.")
        case .determiner: return lower.contains("art.") || lower.contains("def.")
        case .number: return lower.contains("num.")
        case .particle, .other, .unknown: return true
        }
    }
}

public struct WordPartOfSpeech: Sendable, Equatable {
    public let word: String
    public let syllables: Int
    public let partOfSpeech: PartOfSpeechTag

    public init(word: String, syllables: Int, partOfSpeech: PartOfSpeechTag) {
        self.word = word
        self.syllables = syllables
        self.partOfSpeech = partOfSpeech
    }
}

public enum PartOfSpeechAnalyzer {
    /// Tokenize like `SyllableCounter.analyzeWordSyllables` and attach lexical class per word.
    public static func analyzeLine(_ line: String) -> [WordPartOfSpeech] {
        NLConcurrency.synchronized {
            analyzeLineUnsafe(line)
        }
    }

    private static func analyzeLineUnsafe(_ line: String) -> [WordPartOfSpeech] {
        let syllables = SyllableCounter.analyzeWordSyllablesUnsafe(in: line)
        guard !syllables.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = line
        tagger.setLanguage(.english, range: line.startIndex..<line.endIndex)

        var tagged: [WordPartOfSpeech] = []
        tagged.reserveCapacity(syllables.count)

        for item in syllables {
            let tag = lexicalClass(for: item.word, in: line, tagger: tagger)
            tagged.append(
                WordPartOfSpeech(
                    word: item.word,
                    syllables: item.syllables,
                    partOfSpeech: PartOfSpeechTag.from(tag)
                )
            )
        }
        return tagged
    }

    public static func promptPattern(from analysis: [WordPartOfSpeech]) -> String {
        analysis.map { "\($0.word)(\($0.partOfSpeech.promptLabel))" }.joined(separator: " ")
    }

    /// Tag a single token (for filtering dictionary / embedding substitutes).
    public static func tagWord(_ word: String) -> PartOfSpeechTag {
        NLConcurrency.synchronized {
            tagWordUnsafe(word)
        }
    }

    private static func tagWordUnsafe(_ word: String) -> PartOfSpeechTag {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .unknown }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = cleaned
        tagger.setLanguage(.english, range: cleaned.startIndex..<cleaned.endIndex)
        return PartOfSpeechTag.from(lexicalClass(for: cleaned, in: cleaned, tagger: tagger))
    }

    /// Mean positional POS compatibility in \[0, 1\] (aligned non-empty lines, word index).
    public static func meanAlignmentScore(originalLines: [String], parodyLines: [String]) -> Double {
        guard originalLines.count == parodyLines.count else { return 0.0 }
        var total = 0.0
        var count = 0
        for (orig, parody) in zip(originalLines, parodyLines) {
            let oTrim = orig.trimmingCharacters(in: .whitespacesAndNewlines)
            let pTrim = parody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oTrim.isEmpty, !pTrim.isEmpty else { continue }
            total += lineAlignmentScore(original: oTrim, parody: pTrim)
            count += 1
        }
        return count > 0 ? total / Double(count) : 0.0
    }

    public static func lineAlignmentScore(original: String, parody: String) -> Double {
        let orig = analyzeLine(original)
        let para = analyzeLine(parody)
        guard !orig.isEmpty, !para.isEmpty else { return 0.0 }
        let pairs = min(orig.count, para.count)
        guard pairs > 0 else { return 0.0 }
        var matches = 0
        for i in 0..<pairs {
            if PartOfSpeechTag.compatible(required: orig[i].partOfSpeech, candidate: para[i].partOfSpeech) {
                matches += 1
            }
        }
        return Double(matches) / Double(pairs)
    }

    private static func lexicalClass(for token: String, in line: String, tagger: NLTagger) -> NLTag? {
        var found: NLTag?
        let needle = token.trimmingCharacters(in: .punctuationCharacters)
        tagger.enumerateTags(
            in: line.startIndex..<line.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            let piece = String(line[range])
            let pieceLetters = piece.filter { $0.isLetter }
            let tokenLetters = needle.filter { $0.isLetter }
            if pieceLetters.lowercased() == tokenLetters.lowercased() {
                found = tag
                return false
            }
            return true
        }
        return found
    }
}

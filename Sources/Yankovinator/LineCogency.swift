// Copyright (C) 2025, Shyamal Suhana Chandra
// Hard gate: a parody line must read as a grammatical sentence or lyric clause.

import Foundation
import NaturalLanguage

public struct LineCogencyVerdict: Equatable, Sendable {
    public let accepted: Bool
    public let reasons: [String]

    public init(accepted: Bool, reasons: [String]) {
        self.accepted = accepted
        self.reasons = reasons
    }
}

public struct ParodyCogencyError: Error, CustomStringConvertible, Sendable {
    public let lineNumber: Int
    public let reasons: [String]

    public init(lineNumber: Int, reasons: [String]) {
        self.lineNumber = lineNumber
        self.reasons = reasons
    }

    public var description: String {
        let why = reasons.isEmpty ? "it did not read as a sentence" : reasons.joined(separator: "; ")
        return "Line \(lineNumber) was rejected because \(why)."
    }
}

/// Repairs punctuation and rejects lines that are not cogent verse.
public enum LineCogency {

    private static let functionTags: Set<PartOfSpeechTag> = [
        .determiner, .preposition, .conjunction, .pronoun, .particle
    ]

    /// Copy the original's capitalization and punctuation onto the new words.
    /// When the word counts differ, sentence punctuation stays at the end of the line.
    public static func repair(_ generated: String, matching original: String) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGenerated = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGenerated.isEmpty else { return trimmedGenerated }

        let originalSpans = spans(in: trimmedOriginal)
        let generatedCores = spans(in: trimmedGenerated).map(\.core).filter { !$0.isEmpty }
        guard !generatedCores.isEmpty else { return trimmedGenerated }

        if originalSpans.count == generatedCores.count, !originalSpans.isEmpty {
            var result = ""
            for (index, span) in originalSpans.enumerated() {
                result += applyCase(generatedCores[index], capitalized: span.capitalized)
                result += span.trailing
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var words = generatedCores.map { applyCase($0, capitalized: false) }
        if let first = originalSpans.first, !words.isEmpty {
            words[0] = applyCase(words[0], capitalized: first.capitalized)
        }
        var result = words.joined(separator: " ")
        let ending = terminalMark(trimmedOriginal)
        if !ending.isEmpty {
            while let last = result.last, ".!?…".contains(last) {
                result.removeLast()
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines) + ending
        }
        return result
    }

    public static func assess(
        line: String,
        original: String,
        previousLines: [String] = []
    ) -> LineCogencyVerdict {
        var reasons: [String] = []
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.contains(where: \.isNewline) {
            reasons.append("the line is empty or contains a line break")
        }

        let words = PartOfSpeechAnalyzer.analyzeLine(trimmed)
        if words.isEmpty {
            reasons.append("the line has no words")
        }

        let originalWords = PartOfSpeechAnalyzer.analyzeLine(originalTrimmed)
        if !words.isEmpty, !originalWords.isEmpty {
            let originalHasVerb = originalWords.contains { $0.partOfSpeech == .verb }
            let lineHasVerb = words.contains { $0.partOfSpeech == .verb }
            if originalWords.count >= 3, originalHasVerb, !lineHasVerb {
                reasons.append("it has no verb, so it is not a clause")
            }

            let originalHasNominal = originalWords.contains {
                $0.partOfSpeech == .noun || $0.partOfSpeech == .pronoun
            }
            let lineHasNominal = words.contains {
                $0.partOfSpeech == .noun || $0.partOfSpeech == .pronoun
            }
            if originalWords.count >= 3, originalHasNominal, !lineHasNominal {
                reasons.append("it has no noun or pronoun")
            }

            if originalWords.count >= 5,
               originalWords.contains(where: { functionTags.contains($0.partOfSpeech) }),
               !words.contains(where: { functionTags.contains($0.partOfSpeech) }) {
                reasons.append("it is a word list with no words holding the sentence together")
            }

            let drift = abs(originalWords.count - words.count)
            if originalWords.count >= 4, drift > max(2, originalWords.count / 2) {
                reasons.append("it does not follow the shape of the verse line")
            }
        }

        if sentenceBreakCount(trimmed) > sentenceBreakCount(originalTrimmed) {
            reasons.append("punctuation splits it into extra sentences")
        }
        if terminalMark(originalTrimmed) != terminalMark(trimmed) {
            reasons.append("ending punctuation does not match the original line")
        }
        if let originalLetter = firstLetter(originalTrimmed),
           let lineLetter = firstLetter(trimmed),
           originalLetter.isUppercase != lineLetter.isUppercase {
            reasons.append("the opening capitalization does not match the verse")
        }
        if sentenceCount(trimmed) > max(sentenceCount(originalTrimmed), 1) {
            reasons.append("it is more than one sentence")
        }

        let commas = trimmed.filter { $0 == "," }.count
        let lineHasVerb = words.contains { $0.partOfSpeech == .verb }
        if commas >= 2, words.count >= 3, !lineHasVerb {
            reasons.append("it is a comma-separated word list, not a sentence")
        }

        if words.count >= 4 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            if let language = recognizer.dominantLanguage, language != .english {
                reasons.append("it is not an English sentence")
            }
        }

        let context = previousLines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !context.isEmpty, !trimmed.isEmpty {
            let score = CoherenceCritic(loadEmbeddings: true).scoreLocally(
                candidate: trimmed,
                previousLines: context,
                keywords: [:]
            )
            if score.method == "embedding-distance", score.coherence < 0.28 {
                reasons.append("it does not continue the verse in a way that makes sense")
            }
        }

        return LineCogencyVerdict(accepted: reasons.isEmpty, reasons: reasons)
    }

    /// Longest leading prefix that still reads as cogent verse. Later lines are regenerated.
    public static func acceptablePrefix(lines: [String], originalLyrics: [String]) -> [String] {
        var kept: [String] = []
        var previous: [String] = []
        for (index, line) in lines.enumerated() {
            guard index < originalLyrics.count else { break }
            let original = originalLyrics[index]
            if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
                kept.append("")
                previous.append("")
                continue
            }
            let repaired = repair(line, matching: original)
            let verdict = assess(line: repaired, original: original, previousLines: previous)
            guard verdict.accepted else { break }
            kept.append(repaired)
            previous.append(repaired)
        }
        return kept
    }

    private struct Span {
        var core: String
        var capitalized: Bool
        var trailing: String
    }

    private static func spans(in line: String) -> [Span] {
        NLConcurrency.synchronized {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = line
            var ranges: [Range<String.Index>] = []
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
                ranges.append(range)
                return true
            }
            var result: [Span] = []
            for (index, range) in ranges.enumerated() {
                let token = String(line[range])
                let core = coreWord(token)
                guard !core.isEmpty else { continue }
                let capitalized = core.first(where: \.isLetter)?.isUppercase ?? false
                let trailingEnd = range.upperBound
                let nextStart = index + 1 < ranges.count ? ranges[index + 1].lowerBound : line.endIndex
                let trailing = trailingEnd < nextStart ? String(line[trailingEnd..<nextStart]) : ""
                result.append(Span(core: core, capitalized: capitalized, trailing: trailing))
            }
            return result
        }
    }

    private static func coreWord(_ token: String) -> String {
        var word = token
        while let first = word.first, !first.isLetter, first != "'" {
            word.removeFirst()
        }
        while let last = word.last, !last.isLetter, last != "'" {
            word.removeLast()
        }
        return word
    }

    private static func applyCase(_ word: String, capitalized: Bool) -> String {
        guard let index = word.firstIndex(where: \.isLetter) else { return word }
        var updated = word
        let letter = capitalized
            ? String(updated[index]).uppercased()
            : String(updated[index]).lowercased()
        updated.replaceSubrange(index...index, with: letter)
        return updated
    }

    static func terminalMark(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var marks: [Character] = []
        for character in trimmed.reversed() {
            if character.isWhitespace || "\"'”’".contains(character) { continue }
            if ".!?…".contains(character) {
                marks.append(character)
                continue
            }
            break
        }
        return String(marks.reversed())
    }

    private static func sentenceBreakCount(_ line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        var end = trimmed.endIndex
        while end > trimmed.startIndex {
            let previous = trimmed.index(before: end)
            let character = trimmed[previous]
            if character.isWhitespace || "\"'”’".contains(character) || ".!?…".contains(character) {
                end = previous
                continue
            }
            break
        }
        return trimmed[..<end].filter { ".!?".contains($0) }.count
    }

    private static func firstLetter(_ line: String) -> Character? {
        line.first(where: \.isLetter)
    }

    private static func sentenceCount(_ line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return NLConcurrency.synchronized {
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = trimmed
            var count = 0
            tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { _, _ in
                count += 1
                return true
            }
            return count
        }
    }
}

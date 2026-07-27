// Copyright (C) 2025, Shyamal Suhana Chandra
// Rhyming scheme detection and analysis

import Foundation
import NaturalLanguage

/// RhymeSchemeAnalyzer detects rhyming patterns in lyrics
public struct RhymeSchemeAnalyzer {
    
    /// Detect rhyming scheme from lyrics
    /// - Parameter lyrics: Array of lyric lines (non-empty lines only)
    /// - Returns: Array of rhyme group identifiers (A, B, C, etc.) and the detected scheme pattern
    public static func detectRhymeScheme(from lyrics: [String]) -> (rhymeGroups: [String], scheme: String) {
        NLConcurrency.synchronized {
            detectRhymeSchemeUnsafe(from: lyrics)
        }
    }

    private static func detectRhymeSchemeUnsafe(from lyrics: [String]) -> (rhymeGroups: [String], scheme: String) {
        guard !lyrics.isEmpty else {
            return ([], "")
        }
        
        // Extract last words from each line
        let lastWords = lyrics.map { extractLastWord(from: $0) }
        
        // Group lines by rhyming
        var rhymeGroups: [String] = []
        var wordToGroup: [String: String] = [:]
        var nextGroupLetter = "A"
        
        for (index, word) in lastWords.enumerated() {
            // Check if this word rhymes with any previous word
            var foundGroup: String? = nil
            
            for (prevIndex, prevWord) in lastWords.enumerated() {
                if prevIndex < index && rhymes(word, prevWord) {
                    // Found a rhyme, use the same group
                    foundGroup = rhymeGroups[prevIndex]
                    break
                }
            }
            
            if let group = foundGroup {
                rhymeGroups.append(group)
                wordToGroup[word] = group
            } else {
                // New rhyme group — stay in A…Z then A1, B1, … (never walk past 'Z' into punctuation).
                rhymeGroups.append(nextGroupLetter)
                wordToGroup[word] = nextGroupLetter
                nextGroupLetter = Self.nextRhymeLabel(after: nextGroupLetter)
            }
        }
        
        // Build scheme string (e.g., "ABAB", "AABB")
        let scheme = rhymeGroups.joined()
        
        return (rhymeGroups, scheme)
    }

    private static func nextRhymeLabel(after label: String) -> String {
        if label.count == 1, let scalar = label.unicodeScalars.first {
            let value = scalar.value
            if value >= 65 && value < 90 { // A..<Z
                return String(UnicodeScalar(value + 1)!)
            }
            return "A1"
        }
        // Forms like A1, B2, …
        let letter = label.first.map(String.init) ?? "A"
        let cycle = Int(label.dropFirst()) ?? 1
        if letter == "Z" {
            return "A\(cycle + 1)"
        }
        if let scalar = letter.unicodeScalars.first {
            return String(UnicodeScalar(scalar.value + 1)!) + String(cycle)
        }
        return "A\(cycle + 1)"
    }
    
    /// Extract the last word from a line
    /// - Parameter line: The line of text
    /// - Returns: The last word (lowercased, punctuation removed)
    private static func extractLastWord(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use NaturalLanguage tokenizer to get words
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        
        var words: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { tokenRange, _ in
            let word = String(trimmed[tokenRange])
            words.append(word)
            return true
        }
        
        guard let lastWord = words.last else {
            return ""
        }
        
        // Clean the word: lowercase and remove punctuation
        return lastWord.lowercased().filter { $0.isLetter }
    }
    
    /// Check if two words rhyme
    /// - Parameters:
    ///   - word1: First word
    ///   - word2: Second word
    /// - Returns: True if words rhyme
    private static func rhymes(_ word1: String, _ word2: String) -> Bool {
        let w1 = word1.lowercased().filter { $0.isLetter }
        let w2 = word2.lowercased().filter { $0.isLetter }
        
        guard !w1.isEmpty && !w2.isEmpty else { return false }
        
        // If words are identical, they rhyme
        if w1 == w2 {
            return true
        }
        
        // Extract last syllable(s) for rhyming comparison
        // Use last 2-4 characters as a simple approximation
        let minLength = min(w1.count, w2.count)
        guard minLength >= 2 else { return false }
        
        // Compare last 2-4 characters (depending on word length)
        let compareLength = min(4, minLength)
        let suffix1 = String(w1.suffix(compareLength))
        let suffix2 = String(w2.suffix(compareLength))
        
        // Exact match on suffix
        if suffix1 == suffix2 {
            return true
        }
        
        // Phonetic approximation: check if vowel patterns match
        // Extract vowel sequences from the end
        let vowels1 = extractVowelSequence(from: w1)
        let vowels2 = extractVowelSequence(from: w2)
        
        if !vowels1.isEmpty && !vowels2.isEmpty {
            // Check if vowel sequences match (at least last 2 vowels)
            let minVowelLength = min(vowels1.count, vowels2.count)
            if minVowelLength >= 2 {
                let suffixVowels1 = String(vowels1.suffix(2))
                let suffixVowels2 = String(vowels2.suffix(2))
                if suffixVowels1 == suffixVowels2 {
                    // Also check consonant patterns after vowels
                    let consonants1 = extractConsonantsAfterVowels(from: w1)
                    let consonants2 = extractConsonantsAfterVowels(from: w2)
                    if consonants1 == consonants2 {
                        return true
                    }
                }
            }
        }
        
        // Additional check: common rhyming patterns
        return checkCommonRhymePatterns(w1, w2)
    }
    
    /// Extract vowel sequence from the end of a word
    private static func extractVowelSequence(from word: String) -> String {
        let vowels = "aeiouy"
        return word.filter { vowels.contains($0) }
    }
    
    /// Extract consonants that come after the last vowel sequence
    private static func extractConsonantsAfterVowels(from word: String) -> String {
        let vowels = "aeiouy"
        var consonants: [Character] = []
        var foundVowel = false
        
        // Work backwards from the end
        for char in word.reversed() {
            if vowels.contains(char) {
                foundVowel = true
            } else if foundVowel {
                consonants.insert(char, at: 0)
            }
        }
        
        return String(consonants)
    }
    
    /// Check common rhyming patterns
    private static func checkCommonRhymePatterns(_ word1: String, _ word2: String) -> Bool {
        // Common endings that rhyme
        let commonRhymes: [String] = [
            "ing", "tion", "sion", "ness", "ment", "ly", "ed", "er", "est",
            "ight", "ite", "ate", "ake", "oke", "eak", "ook", "ank", "ink"
        ]
        
        for pattern in commonRhymes {
            if word1.hasSuffix(pattern) && word2.hasSuffix(pattern) {
                // Check if the part before the pattern is similar
                let prefix1 = String(word1.dropLast(pattern.count))
                let prefix2 = String(word2.dropLast(pattern.count))
                
                // If prefixes end with similar sounds, they rhyme
                if prefix1.suffix(1) == prefix2.suffix(1) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Determine the rhyme group for a line position
    /// - Parameters:
    ///   - index: Line index (0-based)
    ///   - rhymeGroups: Array of rhyme group identifiers
    /// - Returns: The rhyme group identifier for this line
    public static func getRhymeGroup(for index: Int, in rhymeGroups: [String]) -> String {
        guard index >= 0 && index < rhymeGroups.count else {
            return "A"
        }
        return rhymeGroups[index]
    }
    
    /// Get all line indices that should rhyme with the given line
    /// - Parameters:
    ///   - index: Current line index
    ///   - rhymeGroups: Array of rhyme group identifiers
    /// - Returns: Array of indices that should rhyme with this line
    public static func getRhymingLineIndices(for index: Int, in rhymeGroups: [String]) -> [Int] {
        guard index >= 0 && index < rhymeGroups.count else {
            return []
        }
        
        let currentGroup = rhymeGroups[index]
        var rhymingIndices: [Int] = []
        
        for (i, group) in rhymeGroups.enumerated() {
            if group == currentGroup && i != index {
                rhymingIndices.append(i)
            }
        }
        
        return rhymingIndices
    }
}

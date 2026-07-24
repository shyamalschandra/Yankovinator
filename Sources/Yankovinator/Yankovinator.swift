// Copyright (C) 2025, Shyamal Suhana Chandra
// Main Yankovinator library entry point

import Foundation
import NaturalLanguage

/// Yankovinator: Convert songs into parodies with theme-based keyword constraints
/// Uses NaturalLanguage framework and Ollama for intelligent parody generation
public struct Yankovinator {
    
    /// Generate a parody from original lyrics
    /// - Parameters:
    ///   - originalLyrics: Array of original song lines
    ///   - keywords: Dictionary mapping keywords to their definitions/meanings
    ///   - ollamaURL: Optional Ollama API base URL (default: http://localhost:11434)
    ///   - ollamaModel: Optional Ollama model name (default: llama3.2:3b)
    ///   - useUnsupervisedNLP: Enable embedding substitution, rhyme clustering, coherence critic
    /// - Returns: Array of parody lines matching syllable structure
    public static func generateParody(
        originalLyrics: [String],
        keywords: [String: String],
        ollamaURL: String = "http://localhost:11434",
        ollamaModel: String = "llama3.2:3b",
        useUnsupervisedNLP: Bool = true
    ) async throws -> [String] {
        let generator = ParodyGenerator(
            ollamaBaseURL: ollamaURL,
            ollamaModel: ollamaModel,
            useUnsupervisedNLP: useUnsupervisedNLP
        )
        return try await generator.generateParody(originalLyrics: originalLyrics, keywords: keywords)
    }
    
    /// Count syllables in text using NaturalLanguage
    /// - Parameter text: Text to analyze
    /// - Returns: Syllable count
    public static func countSyllables(_ text: String) -> Int {
        return SyllableCounter.countSyllablesInLine(text)
    }
    
    /// Analyze song structure
    /// - Parameter lyrics: Array of lyric lines
    /// - Returns: Array of syllable counts per line
    public static func analyzeStructure(_ lyrics: [String]) -> [Int] {
        return SyllableCounter.analyzeSongStructure(lyrics)
    }

    /// Unsupervised rhyme clustering over lyric lines.
    public static func clusterRhymeScheme(from lyrics: [String]) -> UnsupervisedRhymeClustering.ClusterResult {
        UnsupervisedRhymeClustering().clusterRhymeScheme(from: lyrics)
    }

    /// Unsupervised syllable-matched lexical substitutes for a word.
    public static func lexicalSubstitutes(
        for word: String,
        requiredSyllables: Int? = nil,
        theme: [String] = [],
        maxResults: Int = 10
    ) -> [LexicalSubstitutionEngine.Substitution] {
        LexicalSubstitutionEngine().substitutes(
            for: word,
            requiredSyllables: requiredSyllables,
            theme: theme,
            maxResults: maxResults
        )
    }

    /// Local unsupervised coherence score (no Ollama required).
    public static func scoreCoherence(
        candidate: String,
        previousLines: [String],
        keywords: [String: String] = [:]
    ) -> CoherenceCritic.Score {
        CoherenceCritic().scoreLocally(
            candidate: candidate,
            previousLines: previousLines,
            keywords: keywords
        )
    }
}


// Copyright (C) 2025, Shyamal Suhana Chandra
// Main parody generation engine

import Foundation
import NaturalLanguage

/// ParodyGenerator orchestrates the conversion of songs into parodies
public class ParodyGenerator {
    private let ollamaClient: OllamaClient
    private let syllableCounter: SyllableCounter.Type
    private let dictionary: OEDDictionary?
    private let lexicalSubstitution: LexicalSubstitutionEngine?
    private let rhymeClustering: UnsupervisedRhymeClustering?
    private let coherenceCritic: CoherenceCritic?
    private let useUnsupervisedNLP: Bool
    
    /// Initialize the parody generator
    /// - Parameters:
    ///   - ollamaBaseURL: Base URL for Ollama API
    ///   - ollamaModel: Model name to use (default: llama3.2:3b)
    ///   - dictionaryPath: Optional path to dictionary file
    ///   - useDictionary: Whether to use OED dictionary for better word choices (default: true)
    ///   - useUnsupervisedNLP: Enable embedding substitution, rhyme clustering, coherence critic (default: true)
    ///   - skipLLMCoherenceCritic: Batch mode — local embedding critic only (no extra Ollama surprise probes)
    public init(
        ollamaBaseURL: String = "http://localhost:11434",
        ollamaModel: String = "llama3.2:3b",
        dictionaryPath: String? = nil,
        useDictionary: Bool = true,
        useUnsupervisedNLP: Bool = true,
        skipLLMCoherenceCritic: Bool = false
    ) {
        let client = OllamaClient(baseURL: ollamaBaseURL, model: ollamaModel)
        self.ollamaClient = client
        self.syllableCounter = SyllableCounter.self
        self.useUnsupervisedNLP = useUnsupervisedNLP
        // Avoid N× concurrent NLEmbedding loads from batch workers when unsupervised NLP is off.
        if useUnsupervisedNLP {
            self.lexicalSubstitution = LexicalSubstitutionEngine()
            self.rhymeClustering = UnsupervisedRhymeClustering()
            self.coherenceCritic = CoherenceCritic(
                ollamaClient: skipLLMCoherenceCritic ? nil : client,
                loadEmbeddings: true
            )
        } else {
            self.lexicalSubstitution = nil
            self.rhymeClustering = nil
            self.coherenceCritic = nil
        }
        
        // Initialize dictionary if requested (shared instance — avoids N× download/parse in batch workers).
        if useDictionary {
            self.dictionary = dictionaryPath.map { OEDDictionary(dictionaryPath: $0) } ?? OEDDictionary.shared
        } else {
            self.dictionary = nil
        }
    }
    
    /// Generate a parody of a song
    /// - Parameters:
    ///   - originalLyrics: Array of original song lines (preserves empty lines)
    ///   - keywords: Dictionary of theme keywords and their definitions
    ///   - progressCallback: Optional callback for progress updates
    ///   - refinementPasses: Number of refinement passes for punctuation correction (default: 2)
    ///   - enableCoherenceRegeneration: When false, skips an extra full-line Ollama retry from the critic (batch fast path)
    ///   - optimizeFit: Hill-climb each line toward syllable/POS/coherence targets (extra Ollama only when needed)
    ///   - fitTargetScore: Stop line optimization when composite fit reaches this value
    ///   - maxFitAttemptsPerLine: Max regenerate/refine attempts per line during fit optimization
    ///   - verbose: Whether to print verbose messages
    /// - Returns: Array of parody lines with preserved empty lines
    public func generateParody(
        originalLyrics: [String],
        keywords: [String: String],
        progressCallback: ((Int, Int) -> Void)? = nil,
        refinementPasses: Int = 2,
        enableCoherenceRegeneration: Bool = true,
        optimizeFit: Bool = true,
        fitTargetScore: Double = ParodyFitScore.defaultCorrectnessThreshold,
        maxFitAttemptsPerLine: Int = 4,
        fitPolishRounds: Int = 2,
        verbose: Bool = false
    ) async throws -> [String] {
        // Verify model once per CLI run (batch workers share this flag).
        if !OllamaClient.isModelVerified(baseURL: ollamaClient.policyBaseURL, model: ollamaClient.policyModel) {
            try await verifyModel()
            OllamaClient.markModelVerified(baseURL: ollamaClient.policyBaseURL, model: ollamaClient.policyModel)
        }

        // Optional dictionary: brief wait only (never block batch workers for seconds).
        dictionary?.waitUntilLoaded(timeoutSeconds: 0.05)
        
        // Track which lines are empty to preserve structure
        let emptyLineIndices = Set(originalLyrics.enumerated().compactMap { index, line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? index : nil
        })
        
        // Filter out empty lines for processing
        let nonEmptyLyrics = originalLyrics.enumerated().compactMap { index, line -> (Int, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (index, line)
        }
        
        // Analyze original song structure (only non-empty lines)
        let nonEmptyTexts = nonEmptyLyrics.map { $0.1 }
        let syllableStructure = syllableCounter.analyzeSongStructure(nonEmptyTexts)
        
        // Detect rhyming scheme (unsupervised clustering when enabled)
        let rhymeGroups: [String]
        let rhymeScheme: String
        if useUnsupervisedNLP, let rhymeClustering {
            let clustered = rhymeClustering.clusterRhymeScheme(from: nonEmptyTexts)
            rhymeGroups = clustered.rhymeGroups
            rhymeScheme = clustered.scheme
            if verbose {
                Self.verbosePrintOnce(
                    key: "rhyme:\(rhymeScheme):\(clustered.method)",
                    "Detected rhyme scheme: \(rhymeScheme) [\(clustered.method)]"
                )
            }
        } else {
            let detected = RhymeSchemeAnalyzer.detectRhymeScheme(from: nonEmptyTexts)
            rhymeGroups = detected.rhymeGroups
            rhymeScheme = detected.scheme
            if verbose {
                Self.verbosePrintOnce(
                    key: "rhyme:\(rhymeScheme)",
                    "Detected rhyme scheme: \(rhymeScheme)"
                )
            }
        }
        
        var parodyLines: [String] = []
        var nonEmptyParodyLines: [String] = [] // Track non-empty lines separately for rhyming
        let totalLines = originalLyrics.count
        var nonEmptyIndex = 0
        var usedWords: Set<String> = [] // Track words used across lines to avoid repetition
        
        // Generate each line, preserving empty lines
        for (index, originalLine) in originalLyrics.enumerated() {
            if emptyLineIndices.contains(index) {
                // Preserve empty lines
                parodyLines.append("")
                continue
            }
            
            let syllableCount = syllableStructure[nonEmptyIndex]
            nonEmptyIndex += 1
            
            progressCallback?(index + 1, totalLines)
            
            // Get rhyming constraints for this line
            // nonEmptyIndex is 1-based at this point (we increment after), so use nonEmptyIndex - 1 for 0-based
            let currentLineIndex = nonEmptyIndex - 1
            let currentRhymeGroup = RhymeSchemeAnalyzer.getRhymeGroup(for: currentLineIndex, in: rhymeGroups)
            let rhymingLineIndices = RhymeSchemeAnalyzer.getRhymingLineIndices(for: currentLineIndex, in: rhymeGroups)
            
            // Get lines that should rhyme with this one (from already generated non-empty parody lines)
            var rhymingLines: [String] = []
            for rhymingIndex in rhymingLineIndices {
                if rhymingIndex < nonEmptyParodyLines.count {
                    rhymingLines.append(nonEmptyParodyLines[rhymingIndex])
                }
            }
            
            // Analyze word-by-word syllable structure of original line
            let wordSyllables = syllableCounter.analyzeWordSyllables(in: originalLine)
            let wordSyllablePattern = wordSyllables.map { "\($0.word)(\($0.syllables))" }.joined(separator: " ")
            let wordPOS = PartOfSpeechAnalyzer.analyzeLine(originalLine)
            let wordPartOfSpeechPattern = PartOfSpeechAnalyzer.promptPattern(from: wordPOS)

            // Merge OED + unsupervised embedding substitutions
            let wordSuggestions = getWordSuggestions(
                originalLine: originalLine,
                wordAnalysis: wordPOS,
                theme: Array(keywords.keys),
                excludeWords: usedWords
            )
            
            // Generate parody line matching syllable count and rhyming requirements
            // Use more context lines (up to 8) for better semantic coherence
            let contextLines = Array(parodyLines.suffix(8).filter { !$0.isEmpty })
            var parodyLine: String
            do {
                parodyLine = try await ollamaClient.generateParodyLine(
                    originalLine: originalLine,
                    syllableCount: syllableCount,
                    keywords: keywords,
                    previousLines: contextLines, // More context for semantic coherence
                    rhymeGroup: currentRhymeGroup,
                    rhymingLines: rhymingLines,
                    rhymeScheme: rhymeScheme,
                    wordSyllablePattern: wordSyllablePattern,
                    wordSyllables: wordSyllables.map { $0.syllables },
                    wordPartOfSpeechPattern: wordPartOfSpeechPattern,
                    usedWords: usedWords,
                    wordSuggestions: wordSuggestions
                )
            } catch let error as OllamaError {
                // If generation fails, provide helpful error
                if verbose {
                    Self.verbosePrint("\nError generating line \(index + 1): \(error.description)")
                }
                throw error // Re-throw to be caught by outer handler
            } catch {
                // Unexpected error
                if verbose {
                    Self.verbosePrint("\nUnexpected error generating line \(index + 1): \(error.localizedDescription)")
                }
                throw OllamaError.networkError(error)
            }
            
            // Refinement passes for word-by-word syllable matching, semantic coherence, and punctuation correction
            // Always run semantic coherence if we have previous lines (unless it's the first line)
            let shouldRunSemanticCoherence = !contextLines.isEmpty && nonEmptyIndex > 1
            
            // Track which refinement types we've done
            var hasDoneWordSyllableRefinement = false
            var hasDoneSemanticRefinement = false
            
            if refinementPasses >= 1 {
            for pass in 1...refinementPasses {
                do {
                    // First pass: verify and refine word-by-word syllable matching with semantic coherence
                    if pass == 1 && !hasDoneWordSyllableRefinement {
                        parodyLine = try await refineWordSyllableMatching(
                            line: parodyLine,
                            originalLine: originalLine,
                            syllableCount: syllableCount,
                            keywords: keywords,
                            wordSyllables: wordSyllables.map { $0.syllables },
                            rhymeGroup: currentRhymeGroup,
                            rhymingLines: rhymingLines,
                            rhymeScheme: rhymeScheme,
                            previousLines: contextLines,
                            usedWords: usedWords
                        )
                        hasDoneWordSyllableRefinement = true
                    } else if shouldRunSemanticCoherence && !hasDoneSemanticRefinement {
                        // Semantic coherence refinement - prioritize this for theme advancement
                        parodyLine = try await refineSemanticCoherence(
                            line: parodyLine,
                            originalLine: originalLine,
                            syllableCount: syllableCount,
                            keywords: keywords,
                            previousLines: contextLines,
                            rhymeGroup: currentRhymeGroup,
                            rhymingLines: rhymingLines,
                            rhymeScheme: rhymeScheme,
                            wordSyllables: wordSyllables.map { $0.syllables },
                            usedWords: usedWords
                        )
                        hasDoneSemanticRefinement = true
                    } else {
                        // Subsequent passes: punctuation correction
                        parodyLine = try await refineLinePunctuation(
                            line: parodyLine,
                            originalLine: originalLine,
                            syllableCount: syllableCount,
                            keywords: keywords,
                            pass: pass
                        )
                    }
                } catch {
                    // If refinement fails, use the original generated line
                    // Log but don't fail the entire generation
                    if verbose {
                        Self.verbosePrint("Warning: Refinement pass \(pass) failed for line \(index + 1), using original line")
                    }
                    // Continue with the line we have, don't break
                }
            }
            }
            
            // If we haven't run semantic coherence yet and we should, run it now
            if refinementPasses >= 1 && shouldRunSemanticCoherence && !hasDoneSemanticRefinement {
                do {
                    parodyLine = try await refineSemanticCoherence(
                        line: parodyLine,
                        originalLine: originalLine,
                        syllableCount: syllableCount,
                        keywords: keywords,
                        previousLines: contextLines,
                        rhymeGroup: currentRhymeGroup,
                        rhymingLines: rhymingLines,
                        rhymeScheme: rhymeScheme,
                        wordSyllables: wordSyllables.map { $0.syllables },
                        usedWords: usedWords
                    )
                } catch {
                    if verbose {
                        Self.verbosePrint("Warning: Semantic coherence refinement failed for line \(index + 1), using current line")
                    }
                }
            }

            // Unsupervised coherence critic: regenerate once if next-line surprise is too high
            if enableCoherenceRegeneration && useUnsupervisedNLP, let coherenceCritic, !contextLines.isEmpty {
                let criticScore = await coherenceCritic.score(
                    candidate: parodyLine,
                    previousLines: contextLines,
                    keywords: keywords
                )
                if verbose {
                    Self.verbosePrint(
                        "Coherence critic line \(index + 1): " +
                        "coherence=\(String(format: "%.2f", criticScore.coherence)) " +
                        "surprise=\(String(format: "%.2f", criticScore.surprise)) " +
                        "[\(criticScore.method)]"
                    )
                }
                if coherenceCritic.shouldReject(criticScore) {
                    do {
                        if verbose {
                            Self.verbosePrint("Regenerating line \(index + 1) after coherence reject")
                        }
                        let retry = try await ollamaClient.generateParodyLine(
                            originalLine: originalLine,
                            syllableCount: syllableCount,
                            keywords: keywords,
                            previousLines: contextLines,
                            rhymeGroup: currentRhymeGroup,
                            rhymingLines: rhymingLines,
                            rhymeScheme: rhymeScheme,
                            wordSyllablePattern: wordSyllablePattern,
                            wordSyllables: wordSyllables.map { $0.syllables },
                            wordPartOfSpeechPattern: wordPartOfSpeechPattern,
                            usedWords: usedWords,
                            wordSuggestions: wordSuggestions
                        )
                        let retryScore = await coherenceCritic.score(
                            candidate: retry,
                            previousLines: contextLines,
                            keywords: keywords
                        )
                        if retryScore.coherence >= criticScore.coherence {
                            parodyLine = retry
                        }
                    } catch {
                        if verbose {
                            Self.verbosePrint("Warning: coherence retry failed for line \(index + 1)")
                        }
                    }
                }
            }

            if optimizeFit && maxFitAttemptsPerLine > 0 {
                parodyLine = try await optimizeLineForFit(
                    line: parodyLine,
                    originalLine: originalLine,
                    syllableCount: syllableCount,
                    keywords: keywords,
                    contextLines: contextLines,
                    wordSyllables: wordSyllables.map { $0.syllables },
                    wordSyllablePattern: wordSyllablePattern,
                    wordPartOfSpeechPattern: wordPartOfSpeechPattern,
                    wordSuggestions: wordSuggestions,
                    rhymeGroup: currentRhymeGroup,
                    rhymingLines: rhymingLines,
                    rhymeScheme: rhymeScheme,
                    usedWords: usedWords,
                    targetScore: fitTargetScore,
                    maxAttempts: maxFitAttemptsPerLine,
                    verbose: verbose
                )
            }

            // Extract words from the generated line and add to usedWords set
            let wordsInLine = extractWords(from: parodyLine)
            usedWords.formUnion(wordsInLine)
            
            // Apply capitalization and punctuation matching from original line
            parodyLine = applyCapitalizationAndPunctuation(
                to: parodyLine,
                from: originalLine
            )
            
            parodyLines.append(parodyLine)
            nonEmptyParodyLines.append(parodyLine) // Track for rhyming
        }

        if optimizeFit {
            let rounds = max(0, fitPolishRounds)
            for _ in 0..<rounds {
                try await polishWeakestLinesForFit(
                    originalLyrics: originalLyrics,
                    parodyLines: &parodyLines,
                    keywords: keywords,
                    syllableStructure: syllableStructure,
                    rhymeGroups: rhymeGroups,
                    rhymeScheme: rhymeScheme,
                    emptyLineIndices: emptyLineIndices,
                    fitTargetScore: fitTargetScore,
                    maxLinesToPolish: 4,
                    verbose: verbose
                )
                let check = ParodyFitScorer.scoreSong(
                    originalLyrics: originalLyrics,
                    parodyLines: parodyLines,
                    keywords: keywords,
                    dictionary: dictionary
                )
                if check.allFit { break }
            }
        }

        return parodyLines
    }
    
    /// Extract words from a line (for tracking usage)
    private func extractWords(from line: String) -> Set<String> {
        NLConcurrency.synchronized {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = line
            var words: Set<String> = []
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { tokenRange, _ in
                let word = String(line[tokenRange]).lowercased().filter { $0.isLetter }
                if !word.isEmpty {
                    words.insert(word)
                }
                return true
            }
            return words
        }
    }
    
    /// Get word suggestions from OED + unsupervised embedding substitution.
    private func getWordSuggestions(
        originalLine: String,
        wordAnalysis: [WordPartOfSpeech],
        theme: [String],
        excludeWords: Set<String>
    ) -> [[(word: String, definition: String)]] {
        var dictionarySuggestions: [[(word: String, definition: String)]] = []
        if let dict = dictionary, dict.isLoaded() {
            for item in wordAnalysis {
                dictionarySuggestions.append(
                    dict.getWordSuggestions(
                        syllableCount: item.syllables,
                        theme: theme,
                        excludeWords: excludeWords,
                        maxResults: 8,
                        similarTo: item.word,
                        requiredPartOfSpeech: item.partOfSpeech
                    )
                )
            }
        }

        guard useUnsupervisedNLP, let lexicalSubstitution else {
            return dictionarySuggestions
        }

        let unsupervised = lexicalSubstitution.asWordSuggestions(
            for: originalLine,
            excludeWords: excludeWords,
            theme: theme,
            maxPerPosition: 6
        )

        if dictionarySuggestions.isEmpty {
            return unsupervised
        }

        // Merge position-wise, dictionary first then embedding neighbors.
        let count = max(dictionarySuggestions.count, unsupervised.count)
        var merged: [[(word: String, definition: String)]] = []
        for i in 0..<count {
            var bucket: [(word: String, definition: String)] = []
            var seen = Set<String>()
            let left = i < dictionarySuggestions.count ? dictionarySuggestions[i] : []
            let right = i < unsupervised.count ? unsupervised[i] : []
            for item in left + right {
                let key = item.word.lowercased()
                if seen.insert(key).inserted {
                    bucket.append(item)
                }
            }
            merged.append(Array(bucket.prefix(12)))
        }
        return merged
    }
    
    /// Refine word-by-word syllable matching
    private func refineWordSyllableMatching(
        line: String,
        originalLine: String,
        syllableCount: Int,
        keywords: [String: String],
        wordSyllables: [Int],
        rhymeGroup: String,
        rhymingLines: [String],
        rhymeScheme: String,
        previousLines: [String] = [],
        usedWords: Set<String> = []
    ) async throws -> String {
        // Analyze the generated line's word syllables
        let generatedWordSyllables = syllableCounter.analyzeWordSyllables(in: line)
        let generatedSyllableCounts = generatedWordSyllables.map { $0.syllables }
        
        // Check if word-by-word matching is correct
        var needsRefinement = false
        if generatedSyllableCounts.count == wordSyllables.count {
            for (genCount, origCount) in zip(generatedSyllableCounts, wordSyllables) {
                if genCount != origCount {
                    needsRefinement = true
                    break
                }
            }
        } else {
            needsRefinement = true
        }
        
        // If matching is correct, return as is
        if !needsRefinement {
            return line
        }
        
        // Request refinement from Ollama
        let keywordDescriptions = keywords.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let wordPattern = wordSyllables.map { String($0) }.joined(separator: "-")
        let generatedPattern = generatedSyllableCounts.map { String($0) }.joined(separator: "-")
        let posPattern = PartOfSpeechAnalyzer.promptPattern(from: PartOfSpeechAnalyzer.analyzeLine(originalLine))
        
        var rhymingInfo = ""
        if !rhymingLines.isEmpty {
            rhymingInfo = "\nLines that must rhyme with this: \(rhymingLines.joined(separator: ", "))"
        }
        
        var semanticContext = ""
        if !previousLines.isEmpty {
            semanticContext = """
            
            SEMANTIC COHERENCE:
            - The line must semantically connect with previous lines: \(previousLines.joined(separator: " | "))
            - Build upon the theme and narrative established so far
            - Ensure the line contributes meaningfully to the overall story/theme
            - Maintain logical flow and progression from previous lines
            """
        }
        
        var wordAvoidance = ""
        if !usedWords.isEmpty {
            let usedWordsList = Array(usedWords).sorted().prefix(50).joined(separator: ", ")
            wordAvoidance = """
            
            WORD USAGE ENTROPY REQUIREMENT:
            - DO NOT use any of these words that have already been used in previous lines: \(usedWordsList)
            - Increase word entropy by using different, fresh vocabulary
            - Only reuse words if they appear in the same line (repetition within a line is acceptable)
            - Use synonyms, alternative phrasing, and varied word choices to avoid repetition
            """
        }
        
        let prompt = """
        Refine this parody line to match the EXACT word-by-word syllable pattern of the original while maintaining semantic coherence.
        
        Original line: "\(originalLine)"
        Required syllable pattern (one number per word): \(wordPattern)
        Current line: "\(line)"
        Current syllable pattern: \(generatedPattern)
        
        Requirements:
        1. Each word must have the EXACT SAME number of syllables as the corresponding word in the original
        2. Each word must match the SAME part of speech as the corresponding original word (pattern: \(posPattern))
        3. Total syllables: \(syllableCount)
        4. Theme: \(keywordDescriptions) - STRONGLY EMBRACE and ADVANCE this theme in the line's meaning
        5. Rhyme group: \(rhymeGroup) in \(rhymeScheme) scheme\(rhymingInfo)
        6. IN-LINE RHYMES: Include internal rhymes within the line, separated by commas. For example: "bright, light, night" or "dream, stream, seem". These comma-separated words should rhyme with each other and appear naturally in the line.
        7. The line must make COGENT SENSE and have ARTISTIC STYLE that AMAZES
        8. PARODY COMEDY: witty, surprising, theme-aware humor—not nonsense; use unabridged-dictionary-defensible English
        9. Use vivid imagery, clever wordplay, and evocative language
        10. The line should flow naturally like professional song lyrics
        11. Use proper contractions with apostrophes (e.g., "don't", "can't", "it's", "won't") when appropriate for natural speech
        12. SEMANTICALLY ADVANCE THE THEME: Make the theme keywords integral to the line's meaning\(semanticContext)\(wordAvoidance)
        
        Generate a refined line that matches the syllable pattern EXACTLY while maintaining semantic coherence, meaning, style, and quality.
        Return ONLY the refined line, nothing else:
        """
        
        let refined = try await ollamaClient.generateParodyLine(
            originalLine: originalLine,
            syllableCount: syllableCount,
            keywords: keywords,
            previousLines: [],
            customPrompt: prompt,
            rhymeGroup: rhymeGroup,
            rhymingLines: rhymingLines,
            rhymeScheme: rhymeScheme,
            wordSyllablePattern: nil,
            wordSyllables: wordSyllables,
            usedWords: usedWords,
            wordSuggestions: []
        )
        
        // Validate the refined line has correct syllable count
        let refinedSyllables = syllableCounter.countSyllablesInLine(refined)
        if abs(refinedSyllables - syllableCount) > 2 {
            // If refinement changed syllable count too much, use original
            return line
        }
        
        return refined
    }
    
    /// Refine semantic coherence to ensure the line works with previous lines and advances the theme
    private func refineSemanticCoherence(
        line: String,
        originalLine: String,
        syllableCount: Int,
        keywords: [String: String],
        previousLines: [String],
        rhymeGroup: String,
        rhymingLines: [String],
        rhymeScheme: String,
        wordSyllables: [Int],
        usedWords: Set<String> = []
    ) async throws -> String {
        // If no previous lines, skip semantic refinement
        guard !previousLines.isEmpty else {
            return line
        }
        
        // Analyze word-by-word syllable structure to maintain constraints
        let wordSyllablePattern = wordSyllables.map { String($0) }.joined(separator: "-")
        
        // Request semantic coherence refinement from Ollama
        let keywordDescriptions = keywords.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        
        var rhymingInfo = ""
        if !rhymingLines.isEmpty {
            rhymingInfo = "\nLines that must rhyme with this: \(rhymingLines.joined(separator: ", "))"
        }
        
        var wordAvoidance = ""
        if !usedWords.isEmpty {
            let usedWordsList = Array(usedWords).sorted().prefix(50).joined(separator: ", ")
            wordAvoidance = """
            
            WORD USAGE ENTROPY REQUIREMENT:
            - DO NOT use any of these words that have already been used in previous lines: \(usedWordsList)
            - Increase word entropy by using different, fresh vocabulary
            - Only reuse words if they appear in the same line (repetition within a line is acceptable)
            - Use synonyms, alternative phrasing, and varied word choices to avoid repetition
            """
        }
        
        let prompt = """
        Refine this parody line to ensure STRONG SEMANTIC COHERENCE with previous lines while maintaining all constraints.
        
        Theme keywords: \(keywordDescriptions)
        Original line: "\(originalLine)"
        Current line: "\(line)"
        Required syllable pattern (one number per word): \(wordSyllablePattern)
        Total syllables: \(syllableCount)
        Rhyme group: \(rhymeGroup) in \(rhymeScheme) scheme\(rhymingInfo)
        
        Previous lines for semantic context:
        \(previousLines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        
        CRITICAL REQUIREMENTS:
        1. The line must SEMANTICALLY CONNECT and BUILD UPON the previous lines
        2. Maintain the EXACT syllable pattern: \(wordSyllablePattern) (one number per word position)
        3. STRONGLY EMBRACE and ADVANCE the theme: \(keywordDescriptions)
           - Make the theme keywords integral to the line's meaning
           - Use imagery, metaphors, and concepts that develop the theme
           - Push the theme forward, don't just mention it
        4. Ensure the line contributes meaningfully to the overall narrative/story
        5. Maintain logical flow and progression from previous lines
        6. Use consistent imagery, metaphors, and thematic elements
        7. The line must make COGENT SENSE in context
        8. Maintain artistic style with vivid imagery and clever wordplay
        9. Preserve rhyme requirements
        10. Use proper contractions when appropriate
        11. IN-LINE RHYMES: Include internal rhymes within the line, separated by commas. For example: "bright, light, night" or "dream, stream, seem". These comma-separated words should rhyme with each other and appear naturally in the line.\(wordAvoidance)
        
        Generate a refined line that:
        - Maintains the exact syllable pattern
        - Strongly advances the theme semantically
        - Connects meaningfully with previous lines
        - Contributes to the overall narrative arc
        
        Return ONLY the refined line, nothing else:
        """
        
        let refined = try await ollamaClient.generateParodyLine(
            originalLine: originalLine,
            syllableCount: syllableCount,
            keywords: keywords,
            previousLines: previousLines,
            customPrompt: prompt,
            rhymeGroup: rhymeGroup,
            rhymingLines: rhymingLines,
            rhymeScheme: rhymeScheme,
            wordSyllablePattern: nil,
            wordSyllables: wordSyllables,
            usedWords: usedWords,
            wordSuggestions: []
        )
        
        // Validate the refined line has correct syllable count
        let refinedSyllables = syllableCounter.countSyllablesInLine(refined)
        if abs(refinedSyllables - syllableCount) > 2 {
            // If refinement changed syllable count too much, use original
            return line
        }
        
        // Validate word-by-word syllable matching is still correct
        let refinedWordSyllables = syllableCounter.analyzeWordSyllables(in: refined)
        let refinedSyllableCounts = refinedWordSyllables.map { $0.syllables }
        
        if refinedSyllableCounts.count == wordSyllables.count {
            var matches = true
            for (refinedCount, requiredCount) in zip(refinedSyllableCounts, wordSyllables) {
                if refinedCount != requiredCount {
                    matches = false
                    break
                }
            }
            if !matches {
                // If word-by-word matching is broken, use original
                return line
            }
        } else {
            // If word count changed, use original
            return line
        }
        
        return refined
    }
    
    /// Refine line punctuation and capitalization to match original style
    private func refineLinePunctuation(
        line: String,
        originalLine: String,
        syllableCount: Int,
        keywords: [String: String],
        pass: Int
    ) async throws -> String {
        // Extract punctuation and capitalization patterns from original line
        let originalPunctuation = extractPunctuation(from: originalLine)
        let originalCapitalization = extractCapitalizationPattern(from: originalLine)
        
        // Extract patterns from current line
        let linePunctuation = extractPunctuation(from: line)
        let lineCapitalization = extractCapitalizationPattern(from: line)
        
        // Check if patterns already match
        let punctuationMatches = originalPunctuation == linePunctuation || originalPunctuation.isEmpty
        let capitalizationMatches = originalCapitalization == lineCapitalization
        
        if punctuationMatches && capitalizationMatches {
            return line // Already matches
        }
        
        // Build capitalization pattern description
        let capPattern = originalCapitalization.map { $0 ? "U" : "L" }.joined(separator: "-")
        
        // Request refinement from Ollama
        let keywordDescriptions = keywords.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        
        var patternDescription = ""
        if !punctuationMatches {
            patternDescription += "Punctuation pattern: \(originalPunctuation)\n"
        }
        if !capitalizationMatches {
            patternDescription += "Capitalization pattern (U=uppercase, L=lowercase per word): \(capPattern)\n"
        }
        
        let prompt = """
        Refine this parody line to match the EXACT punctuation and capitalization style of the original.
        Keep exactly \(syllableCount) syllables.
        Maintain the theme: \(keywordDescriptions)
        
        Original line: "\(originalLine)"
        \(patternDescription)
        Current parody line: "\(line)"
        
        CRITICAL: Match the EXACT capitalization (which words are uppercase/lowercase) and punctuation of the original line.
        Keep the same words and meaning, but adjust capitalization and punctuation to match exactly.
        Use proper contractions with apostrophes (e.g., "don't", "can't", "it's", "won't") when appropriate.
        Return ONLY the refined line, nothing else:
        """
        
        let refined = try await ollamaClient.generateParodyLine(
            originalLine: originalLine,
            syllableCount: syllableCount,
            keywords: keywords,
            previousLines: [],
            customPrompt: prompt,
            wordSuggestions: []
        )
        
        // Validate the refined line has similar syllable count
        let refinedSyllables = syllableCounter.countSyllablesInLine(refined)
        if abs(refinedSyllables - syllableCount) > 2 {
            // If refinement changed syllable count too much, use original
            return line
        }
        
        // Apply capitalization and punctuation programmatically as a fallback
        let finalRefined = applyCapitalizationAndPunctuation(to: refined, from: originalLine)
        
        return finalRefined
    }
    
    /// Extract punctuation pattern from a line
    private func extractPunctuation(from line: String) -> String {
        let punctuation = line.filter { ".,!?;:'\"-()[]{}".contains($0) }
        return punctuation.isEmpty ? "" : "Contains: \(punctuation)"
    }
    
    /// Extract capitalization pattern from a line
    /// Returns an array of booleans indicating which words should be capitalized
    private func extractCapitalizationPattern(from line: String) -> [Bool] {
        NLConcurrency.synchronized {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = line

            var capitalizationPattern: [Bool] = []
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { tokenRange, _ in
                let word = String(line[tokenRange])
                let firstChar = word.first { $0.isLetter }
                if let char = firstChar {
                    capitalizationPattern.append(char.isUppercase)
                } else {
                    capitalizationPattern.append(false)
                }
                return true
            }

            return capitalizationPattern
        }
    }

    /// Apply capitalization and punctuation pattern from original line to generated line
    private func applyCapitalizationAndPunctuation(to generatedLine: String, from originalLine: String) -> String {
        NLConcurrency.synchronized {
            applyCapitalizationAndPunctuationUnsafe(to: generatedLine, from: originalLine)
        }
    }

    private func applyCapitalizationAndPunctuationUnsafe(to generatedLine: String, from originalLine: String) -> String {
        // Collect ranges first — nested enumerateTokens on the same NLTokenizer is unsafe.
        let originalTokenizer = NLTokenizer(unit: .word)
        originalTokenizer.string = originalLine
        var originalRanges: [Range<String.Index>] = []
        originalTokenizer.enumerateTokens(in: originalLine.startIndex..<originalLine.endIndex) { tokenRange, _ in
            originalRanges.append(tokenRange)
            return true
        }

        var originalWords: [(word: String, isCapitalized: Bool, afterWord: String)] = []
        for (i, tokenRange) in originalRanges.enumerated() {
            let word = String(originalLine[tokenRange])
            let afterWordEnd = tokenRange.upperBound
            let nextWordStart = (i + 1 < originalRanges.count) ? originalRanges[i + 1].lowerBound : originalLine.endIndex

            var afterWord = ""
            if nextWordStart > afterWordEnd {
                afterWord = String(originalLine[afterWordEnd..<nextWordStart])
            } else if afterWordEnd < originalLine.endIndex {
                afterWord = String(originalLine[afterWordEnd...])
            }

            let firstChar = word.first { $0.isLetter }
            let isCapitalized = firstChar?.isUppercase ?? false
            originalWords.append((word: word, isCapitalized: isCapitalized, afterWord: afterWord))
        }
        
        let generatedTokenizer = NLTokenizer(unit: .word)
        generatedTokenizer.string = generatedLine
        var generatedWords: [String] = []
        generatedTokenizer.enumerateTokens(in: generatedLine.startIndex..<generatedLine.endIndex) { tokenRange, _ in
            generatedWords.append(String(generatedLine[tokenRange]))
            return true
        }
        
        // Apply capitalization and punctuation pattern
        var result = ""
        let minCount = min(originalWords.count, generatedWords.count)
        
        for i in 0..<minCount {
            var word = generatedWords[i]
            
            // Apply capitalization
            if originalWords[i].isCapitalized {
                // Capitalize first letter
                if let firstLetterIndex = word.firstIndex(where: { $0.isLetter }) {
                    let firstLetter = word[firstLetterIndex]
                    let capitalized = String(firstLetter.uppercased())
                    word.replaceSubrange(firstLetterIndex...firstLetterIndex, with: capitalized)
                }
            } else {
                // Lowercase first letter
                if let firstLetterIndex = word.firstIndex(where: { $0.isLetter }) {
                    let firstLetter = word[firstLetterIndex]
                    let lowercased = String(firstLetter.lowercased())
                    word.replaceSubrange(firstLetterIndex...firstLetterIndex, with: lowercased)
                }
            }
            
            result += word
            result += originalWords[i].afterWord
        }
        
        // If there are more generated words, add them with default spacing
        if generatedWords.count > minCount {
            for i in minCount..<generatedWords.count {
                if i == minCount && result.last?.isWhitespace == false {
                    result += " "
                }
                result += generatedWords[i]
                if i < generatedWords.count - 1 {
                    result += " "
                }
            }
        }
        
        return result
    }

    private func optimizeLineForFit(
        line: String,
        originalLine: String,
        syllableCount: Int,
        keywords: [String: String],
        contextLines: [String],
        wordSyllables: [Int],
        wordSyllablePattern: String,
        wordPartOfSpeechPattern: String,
        wordSuggestions: [[(word: String, definition: String)]],
        rhymeGroup: String,
        rhymingLines: [String],
        rhymeScheme: String,
        usedWords: Set<String>,
        targetScore: Double,
        maxAttempts: Int,
        verbose: Bool
    ) async throws -> String {
        func measure(_ candidate: String) -> ParodyFitScore {
            ParodyFitScorer.scoreLine(
                original: originalLine,
                parody: candidate,
                previousParodyLines: contextLines,
                keywords: keywords,
                dictionary: dictionary
            )
        }

        var best = line
        var bestMetrics = measure(best)
        if bestMetrics.fitsCorrectly || bestMetrics.composite >= targetScore || maxAttempts <= 0 {
            return best
        }

        for attempt in 1...maxAttempts {
            if bestMetrics.fitsCorrectly || bestMetrics.composite >= targetScore { break }

            var candidate = best
            do {
                if bestMetrics.wordSyllablePattern < 0.95
                    || bestMetrics.wordCountMatch < 0.99
                    || bestMetrics.lineTotalSyllables < 0.98
                    || bestMetrics.partOfSpeech < 0.85 {
                    candidate = try await refineWordSyllableMatching(
                        line: best,
                        originalLine: originalLine,
                        syllableCount: syllableCount,
                        keywords: keywords,
                        wordSyllables: wordSyllables,
                        rhymeGroup: rhymeGroup,
                        rhymingLines: rhymingLines,
                        rhymeScheme: rhymeScheme,
                        previousLines: contextLines,
                        usedWords: usedWords
                    )
                } else {
                    candidate = try await ollamaClient.generateParodyLine(
                        originalLine: originalLine,
                        syllableCount: syllableCount,
                        keywords: keywords,
                        previousLines: contextLines,
                        rhymeGroup: rhymeGroup,
                        rhymingLines: rhymingLines,
                        rhymeScheme: rhymeScheme,
                        wordSyllablePattern: wordSyllablePattern,
                        wordSyllables: wordSyllables,
                        wordPartOfSpeechPattern: wordPartOfSpeechPattern,
                        usedWords: usedWords,
                        wordSuggestions: wordSuggestions
                    )
                }
            } catch {
                if verbose {
                    Self.verbosePrint("Fit attempt \(attempt) failed: \(error)")
                }
                continue
            }

            let metrics = measure(candidate)
            if metrics.composite > bestMetrics.composite {
                best = candidate
                bestMetrics = metrics
            }
            if verbose {
                Self.verbosePrint(
                    "Fit line attempt \(attempt): composite=\(String(format: "%.3f", metrics.composite)) " +
                    "syll=\(String(format: "%.2f", metrics.wordSyllablePattern)) " +
                    "pos=\(String(format: "%.2f", metrics.partOfSpeech))"
                )
            }
        }

        return best
    }

    private func polishWeakestLinesForFit(
        originalLyrics: [String],
        parodyLines: inout [String],
        keywords: [String: String],
        syllableStructure: [Int],
        rhymeGroups: [String],
        rhymeScheme: String,
        emptyLineIndices: Set<Int>,
        fitTargetScore: Double,
        maxLinesToPolish: Int,
        verbose: Bool
    ) async throws {
        let summary = ParodyFitScorer.scoreSong(
            originalLyrics: originalLyrics,
            parodyLines: parodyLines,
            keywords: keywords,
            dictionary: dictionary
        )
        if summary.allFit { return }

        var weak: [(index: Int, composite: Double)] = []
        for (index, score) in summary.lineScores.enumerated() {
            guard let score, !score.fitsCorrectly else { continue }
            weak.append((index, score.composite))
        }
        weak.sort { $0.composite < $1.composite }
        let indices = weak.prefix(maxLinesToPolish).map(\.index).sorted()

        var nonEmptyParodyLines: [String] = []
        var nonEmptyIndexByLineIndex: [Int: Int] = [:]
        for (lineIndex, line) in parodyLines.enumerated() {
            if emptyLineIndices.contains(lineIndex) { continue }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            nonEmptyIndexByLineIndex[lineIndex] = nonEmptyParodyLines.count
            nonEmptyParodyLines.append(line)
        }

        for lineIndex in indices {
            let originalLine = originalLyrics[lineIndex]
            guard let nonEmptyIndex = nonEmptyIndexByLineIndex[lineIndex] else { continue }
            let syllableCount = syllableStructure[nonEmptyIndex]
            let wordSyllables = syllableCounter.analyzeWordSyllables(in: originalLine)
            let currentRhymeGroup = RhymeSchemeAnalyzer.getRhymeGroup(for: nonEmptyIndex, in: rhymeGroups)
            let rhymingLineIndices = RhymeSchemeAnalyzer.getRhymingLineIndices(for: nonEmptyIndex, in: rhymeGroups)

            var rhymingLines: [String] = []
            for rhymingIndex in rhymingLineIndices where rhymingIndex < nonEmptyParodyLines.count {
                rhymingLines.append(nonEmptyParodyLines[rhymingIndex])
            }

            let contextLines = parodyLines.prefix(lineIndex).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let current = parodyLines[lineIndex]
            let before = ParodyFitScorer.scoreLine(
                original: originalLine,
                parody: current,
                previousParodyLines: Array(contextLines),
                keywords: keywords,
                dictionary: dictionary
            )

            let refined = try await refineWordSyllableMatching(
                line: current,
                originalLine: originalLine,
                syllableCount: syllableCount,
                keywords: keywords,
                wordSyllables: wordSyllables.map(\.syllables),
                rhymeGroup: currentRhymeGroup,
                rhymingLines: rhymingLines,
                rhymeScheme: rhymeScheme,
                previousLines: Array(contextLines),
                usedWords: []
            )
            let polished = applyCapitalizationAndPunctuation(to: refined, from: originalLine)
            let after = ParodyFitScorer.scoreLine(
                original: originalLine,
                parody: polished,
                previousParodyLines: Array(contextLines),
                keywords: keywords,
                dictionary: dictionary
            )

            if after.composite > before.composite {
                parodyLines[lineIndex] = polished
                nonEmptyParodyLines[nonEmptyIndex] = polished
                if verbose {
                    Self.verbosePrint(
                        "Polished line \(lineIndex + 1): \(String(format: "%.3f", before.composite)) → " +
                        "\(String(format: "%.3f", after.composite))"
                    )
                }
            }
        }

        let finalSummary = ParodyFitScorer.scoreSong(
            originalLyrics: originalLyrics,
            parodyLines: parodyLines,
            keywords: keywords,
            dictionary: dictionary
        )
        if verbose {
            Self.verbosePrint(
                "Song fit: global=\(String(format: "%.3f", finalSummary.globalScore)) " +
                "min=\(String(format: "%.3f", finalSummary.minComposite)) " +
                "allFit=\(finalSummary.allFit)"
            )
        }
        _ = fitTargetScore
    }
    
    /// Parse `keyword: definition` lines from a theme file (no Ollama / dictionary init).
    public static func parseKeywords(from text: String) -> [String: String] {
        var keywords: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let keyword = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !keyword.isEmpty && !definition.isEmpty {
                    keywords[keyword] = definition
                }
            }
        }
        return keywords
    }

    /// Extract keywords and definitions from text using NaturalLanguage
    /// - Parameter text: Text containing keywords and definitions
    /// - Returns: Dictionary of keywords and their definitions
    public func extractKeywords(from text: String) -> [String: String] {
        Self.parseKeywords(from: text)
    }
    
    /// Validate that Ollama is available and model exists
    /// - Returns: True if Ollama is reachable and model is available
    public func validateOllamaConnection() async throws -> Bool {
        return try await ollamaClient.checkAvailability()
    }
    
    /// Verify model is available before generation
    /// - Throws: OllamaError if model is not available
    public func verifyModel() async throws {
        try await ollamaClient.verifyModel()
    }

    /// Serialize stdout logging from parallel workers (avoids interleaved / corrupted verbose spam).
    private static func verbosePrint(_ message: String) {
        NLConcurrency.synchronized {
            print(message)
        }
    }

    /// Print identical verbose lines at most once per process (e.g. rhyme scheme under high parallelism).
    private static var verboseOnceKeys = Set<String>()
    private static func verbosePrintOnce(key: String, _ message: String) {
        NLConcurrency.synchronized {
            guard verboseOnceKeys.insert(key).inserted else { return }
            print(message)
        }
    }
}


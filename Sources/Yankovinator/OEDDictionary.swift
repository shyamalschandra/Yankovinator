// Copyright (C) 2025, Shyamal Suhana Chandra
// Oxford English Dictionary (1913) / Webster's Unabridged Dictionary lookup for better word choices

import Foundation
import NaturalLanguage

/// Dictionary entry containing word information
public struct DictionaryEntry {
    public let word: String
    public let definitions: [String]
    public let partOfSpeech: String?
    public let etymology: String?
    
    public init(word: String, definitions: [String], partOfSpeech: String? = nil, etymology: String? = nil) {
        self.word = word
        self.definitions = definitions
        self.partOfSpeech = partOfSpeech
        self.etymology = etymology
    }
}

/// OEDDictionary provides word lookup and suggestions using the 1913 Oxford/Webster's Dictionary
public class OEDDictionary {
    private var wordIndex: [String: DictionaryEntry] = [:]
    private var wordList: [String] = []
    private let syllableCounter: SyllableCounter.Type
    
    /// Initialize dictionary from a dictionary file path or URL
    /// - Parameters:
    ///   - dictionaryPath: Path to dictionary file (optional)
    ///   - dictionaryURL: URL to download dictionary from (optional, defaults to Project Gutenberg)
    ///   - syllableCounter: Syllable counter instance
    public init(
        dictionaryPath: String? = nil,
        dictionaryURL: String? = nil,
        syllableCounter: SyllableCounter.Type = SyllableCounter.self
    ) {
        self.syllableCounter = syllableCounter
        
        // If dictionary path provided, load it
        if let path = dictionaryPath, FileManager.default.fileExists(atPath: path) {
            loadDictionary(from: path)
        } else {
            // Try to download and cache dictionary
            let urlString = dictionaryURL ?? "https://www.gutenberg.org/cache/epub/673/pg673.txt"
            Task {
                await downloadAndLoadDictionary(from: urlString)
            }
        }
    }
    
    /// Download and load dictionary from URL
    /// - Parameter urlString: URL to download from
    @MainActor
    private func downloadAndLoadDictionary(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        // Check cache first
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheFile = cacheDir.appendingPathComponent("webster_dictionary_1913.txt")
        
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            loadDictionary(from: cacheFile.path)
            return
        }
        
        // Download dictionary
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: cacheFile)
            loadDictionary(from: cacheFile.path)
        } catch {
            // Silently fail - dictionary is optional
        }
    }
    
    /// Load dictionary from file
    /// - Parameter path: Path to dictionary file
    private func loadDictionary(from path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else {
            return
        }
        
        parseDictionary(content: content)
    }
    
    /// Parse dictionary content and build index
    /// - Parameter content: Dictionary file content
    private func parseDictionary(content: String) {
        // Parse Webster's dictionary format
        // Format: <h1>Word</h1> or <hw>Word</hw> followed by definitions
        let lines = content.components(separatedBy: .newlines)
        var currentWord: String? = nil
        var currentDefinitions: [String] = []
        var currentPartOfSpeech: String? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for headword markers
            if let h1Match = trimmed.range(of: #"<h1>([^<]+)</h1>"#, options: .regularExpression) {
                // Save previous entry
                if let word = currentWord, !currentDefinitions.isEmpty {
                    let entry = DictionaryEntry(word: word, definitions: currentDefinitions, partOfSpeech: currentPartOfSpeech)
                    wordIndex[word.lowercased()] = entry
                    wordList.append(word.lowercased())
                }
                
                // Extract word from <h1> tag
                let wordWithTags = String(trimmed[h1Match])
                currentWord = wordWithTags.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                currentDefinitions = []
                currentPartOfSpeech = nil
            } else if let hwMatch = trimmed.range(of: #"<hw>([^<]+)</hw>"#, options: .regularExpression) {
                // Alternative headword format
                let wordWithTags = String(trimmed[hwMatch])
                let extractedWord = wordWithTags.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[*#()]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                
                // Only set as current word if it looks like a valid word entry
                if !extractedWord.isEmpty && extractedWord.count < 50 {
                    if currentWord == nil || extractedWord.lowercased() != currentWord?.lowercased() {
                        // Save previous entry
                        if let word = currentWord, !currentDefinitions.isEmpty {
                            let entry = DictionaryEntry(word: word, definitions: currentDefinitions, partOfSpeech: currentPartOfSpeech)
                            wordIndex[word.lowercased()] = entry
                            wordList.append(word.lowercased())
                        }
                        currentWord = extractedWord
                        currentDefinitions = []
                    }
                }
            } else if trimmed.contains("<tt>v.") || trimmed.contains("<tt>n.") || trimmed.contains("<tt>adj.") || trimmed.contains("<tt>adv.") {
                // Extract part of speech
                if let posMatch = trimmed.range(of: #"<tt>([^<]+)</tt>"#, options: .regularExpression) {
                    currentPartOfSpeech = String(trimmed[posMatch]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                }
            } else if trimmed.contains("<def>") {
                // Extract definition
                let defPattern = #"<def>([^<]+)</def>"#
                let regex = try? NSRegularExpression(pattern: defPattern, options: [])
                if let regex = regex {
                    let nsLine = trimmed as NSString
                    let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsLine.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let defRange = match.range(at: 1)
                            if defRange.location != NSNotFound {
                                let definition = nsLine.substring(with: defRange)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !definition.isEmpty && definition.count < 500 {
                                    currentDefinitions.append(definition)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Save last entry
        if let word = currentWord, !currentDefinitions.isEmpty {
            let entry = DictionaryEntry(word: word, definitions: currentDefinitions, partOfSpeech: currentPartOfSpeech)
            wordIndex[word.lowercased()] = entry
            wordList.append(word.lowercased())
        }
    }
    
    /// Look up a word in the dictionary
    /// - Parameter word: Word to look up
    /// - Returns: Dictionary entry if found
    public func lookup(_ word: String) -> DictionaryEntry? {
        return wordIndex[word.lowercased()]
    }
    
    /// Find words with similar meanings (synonyms) based on definition overlap
    /// - Parameters:
    ///   - word: Word to find synonyms for
    ///   - maxResults: Maximum number of results
    /// - Returns: Array of similar words
    public func findSynonyms(for word: String, maxResults: Int = 10) -> [String] {
        guard let entry = lookup(word) else { return [] }
        
        // Extract key terms from definitions
        let keyTerms = extractKeyTerms(from: entry.definitions)
        
        // Find words with overlapping key terms
        var candidates: [(word: String, score: Int)] = []
        
        for (candidateWord, candidateEntry) in wordIndex {
            if candidateWord.lowercased() == word.lowercased() { continue }
            
            let candidateTerms = extractKeyTerms(from: candidateEntry.definitions)
            let overlap = Set(keyTerms).intersection(Set(candidateTerms)).count
            if overlap > 0 {
                candidates.append((candidateWord, overlap))
            }
        }
        
        return candidates
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { $0.word }
    }
    
    /// Extract key terms from definitions
    /// - Parameter definitions: Array of definition strings
    /// - Returns: Set of key terms
    private func extractKeyTerms(from definitions: [String]) -> Set<String> {
        var terms: Set<String> = []
        
        for definition in definitions {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = definition
            
            tokenizer.enumerateTokens(in: definition.startIndex..<definition.endIndex) { tokenRange, _ in
                let word = String(definition[tokenRange]).lowercased().filter { $0.isLetter }
                if word.count > 3 && !isCommonWord(word) {
                    terms.insert(word)
                }
                return true
            }
        }
        
        return terms
    }
    
    /// Check if a word is a common stop word
    /// - Parameter word: Word to check
    /// - Returns: True if common word
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = ["the", "and", "for", "are", "but", "not", "you", "all", "can", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "way", "who", "boy", "did", "its", "let", "put", "say", "she", "too", "use"]
        return commonWords.contains(word)
    }
    
    /// Find words matching syllable count and semantic similarity
    /// - Parameters:
    ///   - targetSyllables: Target syllable count
    ///   - similarTo: Word to find similar words to (optional)
    ///   - excludeWords: Words to exclude
    ///   - maxResults: Maximum number of results
    /// - Returns: Array of suggested words
    public func findWords(
        withSyllables targetSyllables: Int,
        similarTo: String? = nil,
        excludeWords: Set<String> = [],
        maxResults: Int = 20
    ) -> [String] {
        var candidates: [(word: String, score: Int)] = []
        
        // If similarTo is provided, start with synonyms
        var searchWords = wordList
        if let similar = similarTo {
            let synonyms = findSynonyms(for: similar, maxResults: 50)
            searchWords = synonyms + wordList
        }
        
        for word in searchWords {
            // Skip excluded words
            if excludeWords.contains(word.lowercased()) { continue }
            
            // Check syllable count
            let syllables = syllableCounter.countSyllablesInLine(word)
            if syllables == targetSyllables {
                // Score based on how well it matches
                var score = 10
                
                // Bonus for being in dictionary (already verified)
                score += 5
                
                candidates.append((word, score))
            }
        }
        
        return candidates
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { $0.word }
    }
    
    /// Get word suggestions for poetry generation
    /// - Parameters:
    ///   - syllableCount: Required syllable count
    ///   - theme: Theme keywords for semantic matching
    ///   - excludeWords: Words to avoid
    ///   - maxResults: Maximum suggestions
    /// - Returns: Array of suggested words with definitions
    public func getWordSuggestions(
        syllableCount: Int,
        theme: [String] = [],
        excludeWords: Set<String> = [],
        maxResults: Int = 15
    ) -> [(word: String, definition: String)] {
        var suggestions: [(word: String, definition: String, score: Int)] = []
        
        // If theme keywords provided, prioritize words related to theme
        for word in wordList {
            if excludeWords.contains(word.lowercased()) { continue }
            
            let syllables = syllableCounter.countSyllablesInLine(word)
            if syllables == syllableCount {
                guard let entry = lookup(word) else { continue }
                
                var score = 5 // Base score for matching syllables
                
                // Check if word relates to theme
                if !theme.isEmpty {
                    let wordDef = entry.definitions.joined(separator: " ").lowercased()
                    for themeWord in theme {
                        if wordDef.contains(themeWord.lowercased()) {
                            score += 10
                        }
                    }
                }
                
                let definition = entry.definitions.first ?? "No definition available"
                suggestions.append((word, definition, score))
            }
        }
        
        return suggestions
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { (word: $0.word, definition: $0.definition) }
    }
    
    /// Check if dictionary is loaded
    /// - Returns: True if dictionary has entries
    public func isLoaded() -> Bool {
        return !wordIndex.isEmpty
    }
    
    /// Get count of words in dictionary
    /// - Returns: Number of words indexed
    public func wordCount() -> Int {
        return wordIndex.count
    }
}

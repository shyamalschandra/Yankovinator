// Copyright (C) 2025, Shyamal Suhana Chandra
// Oxford English Dictionary (1913) / Webster's Unabridged Dictionary lookup for better word choices

import Foundation
import NaturalLanguage

/// Dictionary entry containing word information
public struct DictionaryEntry: Sendable {
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

/// OEDDictionary provides word lookup and suggestions using the 1913 Oxford/Webster's Dictionary.
/// Thread-safe: background load cannot race with generation-time lookups.
public final class OEDDictionary: @unchecked Sendable {
    private var wordIndex: [String: DictionaryEntry] = [:]
    private var wordList: [String] = []
    private let lock = NSLock()
    private let syllableCounter: SyllableCounter.Type
    private let loadGroup = DispatchGroup()
    
    /// Shared dictionary loader (one background download / parse per process).
    public static let shared = OEDDictionary()

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
        
        if let path = dictionaryPath, FileManager.default.fileExists(atPath: path) {
            loadDictionary(from: path)
        } else {
            let urlString = dictionaryURL ?? "https://www.gutenberg.org/cache/epub/673/pg673.txt"
            loadGroup.enter()
            Task.detached(priority: .utility) { [weak self] in
                defer { self?.loadGroup.leave() }
                await self?.downloadAndLoadDictionary(from: urlString)
            }
        }
    }
    
    /// Block briefly for a background load (optional; generation may proceed without it).
    public func waitUntilLoaded(timeoutSeconds: TimeInterval = 2.0) {
        _ = loadGroup.wait(timeout: .now() + timeoutSeconds)
    }
    
    /// Download and load dictionary from URL
    private func downloadAndLoadDictionary(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let cacheFile = cacheDir?.appendingPathComponent("webster_dictionary_1913.txt")
        
        if let cacheFile, FileManager.default.fileExists(atPath: cacheFile.path) {
            loadDictionary(from: cacheFile.path)
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let cacheFile {
                try? data.write(to: cacheFile)
                loadDictionary(from: cacheFile.path)
            } else if let content = String(data: data, encoding: .utf8) {
                let parsed = Self.parseDictionaryContent(content: content)
                replaceIndex(with: parsed.index, list: parsed.list)
            }
        } catch {
            // Dictionary is optional; keep empty index.
        }
    }
    
    /// Load dictionary from file
    private func loadDictionary(from path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else {
            return
        }
        let parsed = Self.parseDictionaryContent(content: content)
        replaceIndex(with: parsed.index, list: parsed.list)
    }

    private func replaceIndex(with index: [String: DictionaryEntry], list: [String]) {
        lock.lock()
        wordIndex = index
        wordList = list
        lock.unlock()
    }

    private func snapshot() -> (index: [String: DictionaryEntry], list: [String]) {
        lock.lock()
        let index = wordIndex
        let list = wordList
        lock.unlock()
        return (index, list)
    }
    
    /// Parse dictionary content and build index (pure; no shared mutation).
    private static func parseDictionaryContent(content: String) -> (index: [String: DictionaryEntry], list: [String]) {
        let lines = content.components(separatedBy: .newlines)
        var currentWord: String? = nil
        var currentDefinitions: [String] = []
        var currentPartOfSpeech: String? = nil
        var index: [String: DictionaryEntry] = [:]
        var list: [String] = []

        func commit() {
            if let word = currentWord, !currentDefinitions.isEmpty {
                let entry = DictionaryEntry(word: word, definitions: currentDefinitions, partOfSpeech: currentPartOfSpeech)
                let key = word.lowercased()
                index[key] = entry
                list.append(key)
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if let h1Match = trimmed.range(of: #"<h1>([^<]+)</h1>"#, options: .regularExpression) {
                commit()
                let wordWithTags = String(trimmed[h1Match])
                currentWord = wordWithTags.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                currentDefinitions = []
                currentPartOfSpeech = nil
            } else if let hwMatch = trimmed.range(of: #"<hw>([^<]+)</hw>"#, options: .regularExpression) {
                let wordWithTags = String(trimmed[hwMatch])
                let extractedWord = wordWithTags.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[*#()]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                
                if !extractedWord.isEmpty && extractedWord.count < 50 {
                    if currentWord == nil || extractedWord.lowercased() != currentWord?.lowercased() {
                        commit()
                        currentWord = extractedWord
                        currentDefinitions = []
                    }
                }
            } else if trimmed.contains("<tt>v.") || trimmed.contains("<tt>n.") || trimmed.contains("<tt>adj.") || trimmed.contains("<tt>adv.") {
                if let posMatch = trimmed.range(of: #"<tt>([^<]+)</tt>"#, options: .regularExpression) {
                    currentPartOfSpeech = String(trimmed[posMatch]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                }
            } else if trimmed.contains("<def>") {
                let defPattern = #"<def>([^<]+)</def>"#
                if let regex = try? NSRegularExpression(pattern: defPattern, options: []) {
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
        
        commit()
        return (index, list)
    }
    
    /// Look up a word in the dictionary
    public func lookup(_ word: String) -> DictionaryEntry? {
        let key = word.lowercased()
        lock.lock()
        let entry = wordIndex[key]
        lock.unlock()
        return entry
    }
    
    /// Find words with similar meanings (synonyms) based on definition overlap
    public func findSynonyms(for word: String, maxResults: Int = 10) -> [String] {
        guard let entry = lookup(word) else { return [] }
        
        let keyTerms = extractKeyTerms(from: entry.definitions)
        let (_, list) = snapshot()
        var candidates: [(word: String, score: Int)] = []
        
        for candidateWord in list {
            if candidateWord == word.lowercased() { continue }
            guard let candidateEntry = lookup(candidateWord) else { continue }
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
    
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = ["the", "and", "for", "are", "but", "not", "you", "all", "can", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "way", "who", "boy", "did", "let", "put", "say", "she", "too", "use"]
        return commonWords.contains(word)
    }
    
    /// Find words matching syllable count and semantic similarity
    public func findWords(
        withSyllables targetSyllables: Int,
        similarTo: String? = nil,
        excludeWords: Set<String> = [],
        maxResults: Int = 20
    ) -> [String] {
        var candidates: [(word: String, score: Int)] = []
        let (_, list) = snapshot()
        
        var searchWords = list
        if let similar = similarTo {
            let synonyms = findSynonyms(for: similar, maxResults: 50)
            searchWords = synonyms + list
        }
        
        for word in searchWords {
            if excludeWords.contains(word.lowercased()) { continue }
            let syllables = syllableCounter.countSyllablesInLine(word)
            if syllables == targetSyllables {
                candidates.append((word, 15))
            }
        }
        
        return candidates
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { $0.word }
    }
    
    /// Get word suggestions for poetry generation
    public func getWordSuggestions(
        syllableCount: Int,
        theme: [String] = [],
        excludeWords: Set<String> = [],
        maxResults: Int = 15
    ) -> [(word: String, definition: String)] {
        let (index, list) = snapshot()
        var suggestions: [(word: String, definition: String, score: Int)] = []
        
        for word in list {
            if excludeWords.contains(word.lowercased()) { continue }
            
            let syllables = syllableCounter.countSyllablesInLine(word)
            if syllables == syllableCount {
                guard let entry = index[word.lowercased()] else { continue }
                
                var score = 5
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
    public func isLoaded() -> Bool {
        lock.lock()
        let loaded = !wordIndex.isEmpty
        lock.unlock()
        return loaded
    }
    
    /// Get count of words in dictionary
    public func wordCount() -> Int {
        lock.lock()
        let count = wordIndex.count
        lock.unlock()
        return count
    }
}

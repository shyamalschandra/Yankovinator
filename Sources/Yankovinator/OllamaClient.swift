// Copyright (C) 2025, Shyamal Suhana Chandra
// Ollama API client for generating parody lyrics

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

/// Client for interacting with Ollama API
public class OllamaClient {
    // Shared HTTP client for all OllamaClient instances
    // This ensures proper lifecycle management and avoids connection issues
    private static var sharedHTTPClient: HTTPClient?
    private static let clientLock = NSLock()

    /// Per-request timeouts (seconds). Override via `applyRuntimePolicy` / CLI `--ollama-timeout`.
    public static var generateTimeoutSeconds = 180
    public static var surpriseTimeoutSeconds = 90
    public static var keywordsTimeoutSeconds = 180
    public static var tagsTimeoutSeconds = 10

    private static var workerConnectionHint = 16
    private static var cloudConcurrencyLimit = 0
    private static var maxRetryAttempts = OllamaRetryPolicy.defaultMaxAttempts
    /// Optional hard ceiling on retries (used by cloud preflight to fail fast).
    private static var maxRetryAttemptsCeiling: Int?
    private static var verifiedModelKeys: Set<String> = []
    private static let verificationLock = NSLock()
    private static let cloudGate = CloudRequestGate()

    /// Mark model as already verified for this process (skips per-job `/api/tags` checks).
    public static func markModelVerified(baseURL: String, model: String) {
        verificationLock.lock()
        verifiedModelKeys.insert(modelVerificationKey(baseURL: baseURL, model: model))
        verificationLock.unlock()
    }

    public static func isModelVerified(baseURL: String, model: String) -> Bool {
        verificationLock.lock()
        defer { verificationLock.unlock() }
        return verifiedModelKeys.contains(modelVerificationKey(baseURL: baseURL, model: model))
    }

    private static func modelVerificationKey(baseURL: String, model: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)|\(model)"
    }

    /// Tune HTTP client for parallel workers and cloud models. Call before the first Ollama request in a run.
    public static func applyRuntimePolicy(
        model: String,
        workers: Int,
        ollamaNumParallel: Int? = nil,
        timeoutOverride: Int? = nil,
        applyCloudPrescription: Bool = true
    ) {
        clientLock.lock()
        defer { clientLock.unlock() }

        let isCloud = CloudBatchPrescription.isCloudModel(model)
        let concurrent = ParallelJobRunner.consumerPoolSize(
            requestedWorkers: workers,
            ollamaNumParallel: ollamaNumParallel,
            model: model,
            applyCloudPrescription: applyCloudPrescription,
            consumerOverride: nil
        )

        if isCloud {
            // Prefer connection reuse; concurrency already reflects prescription / --workers.
            // Base attempts for 429/ordinary 502; DNS/connectivity dynamically extends to cloudDNSMaxAttempts.
            workerConnectionHint = max(4, min(concurrent + 2, 32))
            cloudConcurrencyLimit = max(1, concurrent)
            maxRetryAttempts = OllamaRetryPolicy.defaultMaxAttempts
        } else {
            workerConnectionHint = max(8, min(concurrent + 12, 512))
            cloudConcurrencyLimit = 0
            maxRetryAttempts = OllamaRetryPolicy.localMaxAttempts
        }

        Task {
            await cloudGate.reconfigure(limit: cloudConcurrencyLimit)
        }

        if let existing = sharedHTTPClient {
            try? existing.syncShutdown()
            sharedHTTPClient = nil
        }

        if let timeout = timeoutOverride {
            generateTimeoutSeconds = timeout
            surpriseTimeoutSeconds = max(45, timeout / 2)
            keywordsTimeoutSeconds = timeout
        } else if isCloud {
            generateTimeoutSeconds = CloudBatchPrescription.isHeavyCloudModel(model)
                ? CloudBatchPrescription.heavyCloudTimeoutSeconds
                : 300
            surpriseTimeoutSeconds = CloudBatchPrescription.isHeavyCloudModel(model) ? 150 : 120
            keywordsTimeoutSeconds = generateTimeoutSeconds
        } else {
            generateTimeoutSeconds = 180
            surpriseTimeoutSeconds = 90
            keywordsTimeoutSeconds = 180
        }
    }

    private static func sharedConfiguration() -> HTTPClient.Configuration {
        var configuration = HTTPClient.Configuration()
        // Read timeout must exceed per-request execute timeout (especially for cloud models).
        configuration.timeout = HTTPClient.Configuration.Timeout(
            connect: .seconds(60),
            read: .seconds(600)
        )
        // Keep connections warm so parallel workers reuse sockets instead of exhausting ephemeral ports.
        configuration.connectionPool.idleTimeout = .seconds(180)
        configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit =
            max(4, workerConnectionHint)
        return configuration
    }
    
    private let baseURL: String
    private let model: String
    private let httpClient: HTTPClient

    /// Base URL and model for runtime policy / verification caching.
    var policyBaseURL: String { baseURL }
    var policyModel: String { model }
    
    /// Initialize Ollama client
    /// - Parameters:
    ///   - baseURL: Base URL for Ollama API (default: http://localhost:11434)
    ///   - model: Model name to use (default: llama3.2:3b)
    public init(baseURL: String = "http://localhost:11434", model: String = "llama3.2:3b") {
        self.baseURL = baseURL
        self.model = model
        
        // Use a shared HTTP client instance to avoid lifecycle issues
        // This ensures the event loop is properly initialized and connections are reused
        Self.clientLock.lock()
        defer { Self.clientLock.unlock() }
        
        if Self.sharedHTTPClient == nil {
            Self.sharedHTTPClient = HTTPClient(
                eventLoopGroupProvider: .singleton,
                configuration: Self.sharedConfiguration()
            )
        }
        
        // Use the shared HTTP client instance
        self.httpClient = Self.sharedHTTPClient!
    }

    /// Execute an HTTP request with retries for transient network errors and 429/502/503/504.
    /// DNS/connectivity upstream failures (ollama.com lookup) get longer backoff and more attempts on cloud.
    /// Returns the successful response and fully collected body (body is drained so connections can be reused).
    private func executeWithRetry(
        timeoutSeconds: Int,
        makeRequest: () throws -> HTTPClientRequest
    ) async throws -> (HTTPClientResponse, Data) {
        await Self.cloudGate.acquire()
        do {
            let result = try await executeWithRetryUnlocked(
                timeoutSeconds: timeoutSeconds,
                makeRequest: makeRequest
            )
            await Self.cloudGate.release()
            return result
        } catch {
            await Self.cloudGate.release()
            throw error
        }
    }

    private func executeWithRetryUnlocked(
        timeoutSeconds: Int,
        makeRequest: () throws -> HTTPClientRequest
    ) async throws -> (HTTPClientResponse, Data) {
        let isCloud = Self.cloudConcurrencyLimit > 0
        let ceiling = Self.maxRetryAttemptsCeiling
        var effectiveMax = Self.maxRetryAttempts
        if let ceiling { effectiveMax = min(effectiveMax, ceiling) }
        var lastError: Error?
        var attempt = 1
        while attempt <= effectiveMax {
            do {
                let request = try makeRequest()
                let response = try await httpClient.execute(
                    request,
                    timeout: .seconds(Int64(timeoutSeconds))
                )
                var responseData = Data()
                for try await buffer in response.body {
                    responseData.append(contentsOf: buffer.readableBytesView)
                }

                let statusCode = Int(response.status.code)
                if statusCode == 200 || !OllamaRetryPolicy.isRetryableHTTPStatus(statusCode) {
                    return (response, responseData)
                }

                let bodyText = String(data: responseData, encoding: .utf8) ?? ""
                let isDNS = OllamaRetryPolicy.isDNSConnectivityHTTPFailure(
                    statusCode: statusCode,
                    bodyOrMessage: bodyText
                )
                if isDNS, ceiling == nil {
                    effectiveMax = max(
                        effectiveMax,
                        OllamaRetryPolicy.maxAttempts(isCloud: isCloud, isDNSConnectivity: true)
                    )
                }

                if attempt >= effectiveMax {
                    return (response, responseData)
                }

                let retryAfterHeader = response.headers.first(name: "Retry-After")
                    ?? response.headers.first(name: "retry-after")
                let retryAfter = OllamaRetryPolicy.parseRetryAfterSeconds(retryAfterHeader)
                let delay = OllamaRetryPolicy.backoffNanoseconds(
                    attempt: attempt,
                    retryAfterSeconds: retryAfter,
                    isDNSConnectivity: isDNS && ceiling == nil
                )
                lastError = OllamaError.httpError(
                    statusCode: statusCode,
                    message: " (retry \(attempt)/\(effectiveMax))"
                )
                try await Task.sleep(nanoseconds: delay)
                attempt += 1
                continue
            } catch {
                lastError = error
                let isDNS = OllamaRetryPolicy.isDNSConnectivityFailure(
                    String(describing: error) + " " + error.localizedDescription
                )
                if isDNS, ceiling == nil {
                    effectiveMax = max(
                        effectiveMax,
                        OllamaRetryPolicy.maxAttempts(isCloud: isCloud, isDNSConnectivity: true)
                    )
                }
                if attempt < effectiveMax, OllamaRetryPolicy.isTransientNetworkError(error) {
                    let delay = OllamaRetryPolicy.backoffNanoseconds(
                        attempt: attempt,
                        isDNSConnectivity: isDNS && ceiling == nil
                    )
                    try await Task.sleep(nanoseconds: delay)
                    attempt += 1
                    continue
                }
                throw error
            }
        }
        if let lastError {
            throw lastError
        }
        throw OllamaError.invalidResponse
    }
    
    deinit {
        // Don't shutdown the shared HTTP client - it will be cleaned up on process exit
        // Shutting it down here would break other instances
    }
    
    /// Generate parody line matching syllable count and theme
    /// - Parameters:
    ///   - originalLine: Original song line
    ///   - syllableCount: Target syllable count
    ///   - keywords: Theme keywords and their definitions
    ///   - previousLines: Previous lines for context
    ///   - customPrompt: Optional custom prompt (overrides default)
    ///   - rhymeGroup: Rhyme group identifier (A, B, C, etc.) for this line
    ///   - rhymingLines: Lines that should rhyme with this one
    ///   - rhymeScheme: The overall rhyme scheme pattern (e.g., "ABAB", "AABB")
    ///   - wordSyllablePattern: Pattern showing word-by-word syllable counts (e.g., "hello(2) world(1)")
    ///   - wordSyllables: Array of syllable counts per word position
    ///   - usedWords: Set of words already used in previous lines (to avoid repetition)
    ///   - wordSuggestions: Array of word suggestions per position from OED dictionary
    /// - Returns: Generated parody line
    public func generateParodyLine(
        originalLine: String,
        syllableCount: Int,
        keywords: [String: String],
        previousLines: [String] = [],
        customPrompt: String? = nil,
        rhymeGroup: String? = nil,
        rhymingLines: [String] = [],
        rhymeScheme: String? = nil,
        wordSyllablePattern: String? = nil,
        wordSyllables: [Int]? = nil,
        wordPartOfSpeechPattern: String? = nil,
        usedWords: Set<String> = [],
        wordSuggestions: [[(word: String, definition: String)]] = []
    ) async throws -> String {
        let keywordDescriptions = keywords.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let context = previousLines.isEmpty ? "" : "Previous lines:\n\(previousLines.joined(separator: "\n"))\n\n"
        
        // Build word-by-word syllable matching instructions
        var wordSyllableInstructions = ""
        if let wordPattern = wordSyllablePattern, let wordSylls = wordSyllables, !wordSylls.isEmpty {
            wordSyllableInstructions = """
            
            CRITICAL: Word-by-word syllable matching required!
            Original line syllable pattern: \(wordPattern)
            You MUST substitute each word with a word that has the EXACT SAME number of syllables in the same position.
            For example, if the original has "hello(2) world(1)", your line must have a 2-syllable word followed by a 1-syllable word.
            The syllable pattern must be: \(wordSylls.map { String($0) }.joined(separator: "-"))
            """
        }

        var partOfSpeechInstructions = ""
        if let posPattern = wordPartOfSpeechPattern, !posPattern.isEmpty {
            partOfSpeechInstructions = """

            CRITICAL: Word-by-word part-of-speech matching (same grammatical slot as the original):
            Original POS pattern: \(posPattern)
            Each word in your parody MUST match the part of speech of the corresponding original word (noun→noun, verb→verb, adjective→adjective, etc.).
            Do not turn verbs into nouns or adjectives into adverbs unless the original word is the same class.
            """
        }

        let comedyAndOEDInstructions = """

        PARODY COMEDY & UNABRIDGED OED ENGLISH:
        - Write a PARODY with genuine comedic value: wit, ironic twist, exaggeration, or surprise—but the line must still read clearly.
        - Word choices must make sense in context and sound like deliberate lyric writing, not random tokens.
        - Prefer dictionary-defensible senses from the 1913 Oxford/Webster's Unabridged suggestions when provided (standard literary English usage).
        - Humor should come from theme juxtaposition and clever substitution, not from breaking grammar or nonsense words.
        """
        
        // Build rhyming instructions
        var rhymingInstructions = ""
        if let rhymeGroup = rhymeGroup, let scheme = rhymeScheme {
            rhymingInstructions = "\n6. MUST RHYME with rhyme group '\(rhymeGroup)' in the \(scheme) rhyme scheme"
            if !rhymingLines.isEmpty {
                rhymingInstructions += "\n   The following lines rhyme with this one (use them as reference for the ending sound):"
                for rhymingLine in rhymingLines {
                    rhymingInstructions += "\n   - \(rhymingLine)"
                }
                rhymingInstructions += "\n   Your line must end with a word that rhymes with the ending words of these lines."
            } else {
                rhymingInstructions += "\n   This is the first line in rhyme group '\(rhymeGroup)'. Future lines in this group will need to rhyme with your line."
            }
        }
        
        // Build in-line rhyme instructions
        let inlineRhymeInstructions = """
        
        7. IN-LINE RHYMES (CRITICAL): Include internal rhymes within the line, separated by commas.
           - Add comma-separated rhyming words that appear naturally in the line
           - Examples: "bright, light, night" or "dream, stream, seem" or "flow, glow, show"
           - These rhyming words should be integrated naturally into the line's meaning
           - The comma-separated words should rhyme with each other
           - This creates rich internal rhyme patterns within each verse
        """
        
        // Build word avoidance instructions
        var wordAvoidanceInstructions = ""
        if !usedWords.isEmpty {
            let usedWordsList = Array(usedWords).sorted().prefix(50).joined(separator: ", ")
            wordAvoidanceInstructions = """
            
            8. WORD USAGE ENTROPY (CRITICAL): Increase vocabulary diversity by avoiding word repetition.
               - DO NOT use any of these words that have already been used in previous lines: \(usedWordsList)
               - Use synonyms, alternative phrasing, and varied word choices
               - Only reuse words if they appear in the same line (repetition within a line is acceptable)
               - This increases the entropy and richness of word usage across the poetry
            """
        } else {
            wordAvoidanceInstructions = """
            
            8. WORD USAGE ENTROPY: Use diverse vocabulary and avoid unnecessary repetition across different lines.
            """
        }
        
        // Build OED dictionary word suggestions
        var dictionarySuggestions = ""
        if !wordSuggestions.isEmpty && !wordSuggestions.allSatisfy({ $0.isEmpty }) {
            dictionarySuggestions = """
            
            9. OED DICTIONARY WORD SUGGESTIONS (from 1913 Oxford/Webster's Dictionary):
               Use these curated words from the Oxford English Dictionary for superior word choice.
               These words are verified, have the correct syllable counts, and relate to your theme:
            """
            
            for (index, suggestions) in wordSuggestions.enumerated() {
                if !suggestions.isEmpty {
                    let syllableCount = wordSyllables?[index] ?? 0
                    dictionarySuggestions += "\n   Position \(index + 1) (\(syllableCount) syllables; keep same part of speech as original):"
                    for suggestion in suggestions.prefix(5) {
                        dictionarySuggestions += "\n     - \(suggestion.word): \(suggestion.definition)"
                    }
                }
            }
            
            dictionarySuggestions += """
            
               - PREFER these dictionary words when they fit naturally
               - These words are from the authoritative 1913 Oxford/Webster's Dictionary
               - They provide richer, more precise vocabulary than common alternatives
               - Use them to elevate the artistic quality and precision of your poetry
            """
        }
        
        // Use custom prompt if provided, otherwise use default
        let prompt: String
        if let customPrompt = customPrompt {
            prompt = customPrompt
        } else {
            // Build enhanced context with semantic coherence emphasis
            var semanticContext = ""
            if !previousLines.isEmpty {
                semanticContext = """
                
                SEMANTIC COHERENCE REQUIREMENTS:
                - The line must SEMANTICALLY CONNECT with the previous lines above
                - Build upon the narrative, theme, and emotional arc established so far
                - Use consistent imagery, metaphors, and thematic elements throughout
                - Ensure the line contributes meaningfully to the overall story/theme
                - Maintain logical flow and progression from previous lines
                - If previous lines establish a scene, emotion, or concept, continue or develop it naturally
                
                Previous lines for context:
                \(previousLines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                """
            }
            
            prompt = """
            You are an exceptional creative parody writer crafting lyrics that amaze with artistic brilliance.
            Generate a single line of parody poetry that:
            
            1. Has exactly \(syllableCount) syllables total\(wordSyllableInstructions)
            2. STRONGLY EMBRACES and ADVANCES the theme of these keywords: \(keywordDescriptions)
               - Weave the theme keywords naturally into the line's meaning
               - Use imagery, metaphors, and concepts related to the theme
               - Make the theme central to the line's semantic content, not just mentioned
            3. Maintains the rhythm and style of the original: "\(originalLine)"
            4. Preserves punctuation style similar to the original
            5. Is creative, humorous, and appropriate\(rhymingInstructions)\(inlineRhymeInstructions)\(wordAvoidanceInstructions)\(dictionarySuggestions)\(partOfSpeechInstructions)\(comedyAndOEDInstructions)
            
            CRITICAL QUALITY REQUIREMENTS:
            - The line must make COGENT SENSE - it must be grammatically correct and semantically meaningful
            - The line must have ARTISTIC STYLE that AMAZES - use vivid imagery, clever wordplay, poetic devices, and evocative language
            - Each word substitution should be thoughtful and enhance the artistic quality
            - The line should flow naturally and sound like it belongs in a professional song
            - Avoid awkward phrasing or forced rhymes - prioritize natural, beautiful language
            - Use proper contractions with apostrophes (e.g., "don't", "can't", "it's", "won't") when appropriate for natural speech
            - SEMANTICALLY ADVANCE THE THEME: The line should push forward the chosen theme, not just mention it
            - THEME INTEGRATION: Make the theme keywords feel integral to the line's meaning, not forced or superficial\(semanticContext)
            
            \(context)Generate ONLY the parody line, nothing else. No explanations, no quotes, just the line:
            """
        }
        
        // Ensure baseURL doesn't have trailing slash
        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiURL = "\(cleanBaseURL)/api/generate"
        
        // Validate and construct URL properly
        guard let url = URL(string: apiURL) else {
            throw OllamaError.invalidURL
        }
        
        // Add options - Ollama API format
        let options: [String: Any] = [
            "temperature": 0.8,
            "top_p": 0.9,
            "num_predict": 100
        ]
        let requestBody = Self.ollamaGenerateRequestBody(model: model, prompt: prompt, options: options)
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Execute request with detailed logging
        let response: HTTPClientResponse
        let responseData: Data
        do {
            let jsonDataForRequest = jsonData
            (response, responseData) = try await executeWithRetry(timeoutSeconds: Self.generateTimeoutSeconds) {
                var request = HTTPClientRequest(url: apiURL)
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")
                request.headers.add(name: "Accept", value: "application/json")
                request.headers.add(name: "Connection", value: "keep-alive")
                request.body = .bytes(ByteBuffer(data: jsonDataForRequest))
                return request
            }
        } catch {
            // Network-level error
            throw OllamaError.networkError(error)
        }
        
        // Check response status
        let statusCode = Int(response.status.code)
        guard response.status == .ok else {
            // Parse error from response body
            var errorMessage = ""
            var isModelNotFound = false
            var responseText = ""
            
            if !responseData.isEmpty {
                responseText = String(data: responseData, encoding: .utf8) ?? ""
                
                // Try to parse as JSON
                if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                    if let error = json["error"] as? String {
                        errorMessage = ": \(error)"
                        // Check if error indicates model not found
                        let lowerError = error.lowercased()
                        if lowerError.contains("model") && (lowerError.contains("not found") || lowerError.contains("does not exist") || lowerError.contains("not available")) {
                            isModelNotFound = true
                        }
                    } else {
                        // No error field, but status is not OK
                        errorMessage = ": Unexpected response format"
                    }
                } else {
                    // If not JSON, include the raw response
                    let preview = String(responseText.prefix(200))
                    errorMessage = ": \(preview)"
                }
            } else {
                errorMessage = ": Empty response body"
            }
            
            // Check for 404 status or model not found error
            // For 404, always treat as model not found (Ollama returns 404 for missing models)
            if statusCode == 404 {
                // Parse the actual error message from Ollama
                if !responseText.isEmpty, let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let error = json["error"] as? String {
                    // Use the actual error message from Ollama
                    throw OllamaError.modelNotFound(model: model)
                } else {
                    // Fallback if we can't parse
                    throw OllamaError.modelNotFound(model: model)
                }
            }
            
            if isModelNotFound {
                throw OllamaError.modelNotFound(model: model)
            }
            
            // For other errors, include detailed debugging info (DNS tips added in OllamaError.description).
            throw OllamaError.httpError(
                statusCode: statusCode,
                message: "\(errorMessage) (URL: \(apiURL), Model: \(model), Status: \(statusCode))"
            )
        }
        
        guard !responseData.isEmpty else {
            throw OllamaError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            // Log the actual response for debugging
            let responseText = String(data: responseData, encoding: .utf8) ?? "Unknown"
            throw OllamaError.invalidResponse
        }
        
        return try Self.parseParodyLineFromGenerateJSON(json)
    }

    /// Request body for `/api/generate`. `think: false` avoids empty `response` on thinking models (e.g. deepseek-v4-pro:cloud).
    static func ollamaGenerateRequestBody(model: String, prompt: String, options: [String: Any]) -> [String: Any] {
        [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "think": false,
            "options": options
        ]
    }

    /// Strip wrapping quotes from a single-line model output.
    static func cleanLineResponse(_ responseText: String) -> String {
        var cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        if cleaned.hasPrefix("'") && cleaned.hasSuffix("'") && cleaned.count > 1 {
            let middle = String(cleaned.dropFirst().dropLast())
            if !middle.contains("'") {
                cleaned = middle
            }
        }

        return cleaned
    }

    /// Parse `/api/generate` JSON into one parody line; rejects empty `response` (common when thinking models omit `think: false`).
    static func parseParodyLineFromGenerateJSON(_ json: [String: Any]) throws -> String {
        guard let responseText = json["response"] as? String else {
            if let error = json["error"] as? String {
                throw OllamaError.httpError(statusCode: 500, message: ": \(error)")
            }
            throw OllamaError.invalidResponse
        }

        let cleaned = cleanLineResponse(responseText)
        guard !cleaned.isEmpty else {
            throw OllamaError.emptyGenerateResponse
        }
        return cleaned
    }

    /// Unsupervised next-line surprise probe in \[0, 1\] (1 = highly surprising / incoherent).
    /// Asks the model for a numeric score; no labeled coherence data required.
    public func estimateNextLineSurprise(
        previousLines: [String],
        candidateLine: String,
        keywords: [String: String] = [:]
    ) async throws -> Double {
        let context = previousLines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let contextBlock = context.isEmpty ? "(none)" : context.suffix(6).joined(separator: "\n")
        let theme = keywords.isEmpty
            ? "(none)"
            : keywords.map { "\($0.key): \($0.value)" }.joined(separator: "; ")

        let prompt = """
        You are a coherence critic. Score how surprising/incoherent the candidate next line is given prior lines.
        Return ONLY a decimal number between 0.0 and 1.0 inclusive.
        0.0 = perfectly expected continuation, 1.0 = random/incoherent break.

        Theme keywords: \(theme)

        Previous lines:
        \(contextBlock)

        Candidate next line:
        \(candidateLine)

        Surprise score:
        """

        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiURL = "\(cleanBaseURL)/api/generate"
        guard URL(string: apiURL) != nil else {
            throw OllamaError.invalidURL
        }

        let requestBody = Self.ollamaGenerateRequestBody(
            model: model,
            prompt: prompt,
            options: [
                "temperature": 0.0,
                "top_p": 0.1,
                "num_predict": 8
            ]
        )

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        let response: HTTPClientResponse
        let responseData: Data
        do {
            let payload = jsonData
            (response, responseData) = try await executeWithRetry(timeoutSeconds: Self.surpriseTimeoutSeconds) {
                var request = HTTPClientRequest(url: apiURL)
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")
                request.headers.add(name: "Accept", value: "application/json")
                request.body = .bytes(ByteBuffer(data: payload))
                return request
            }
        } catch {
            throw OllamaError.networkError(error)
        }

        guard response.status == .ok,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let text = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }

        return Self.parseUnitInterval(from: text)
    }

    /// Parse the first 0...1 decimal found in model output.
    static func parseUnitInterval(from text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"0?\.\d+|1(?:\.0+)?|0"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range, in: trimmed),
           let value = Double(trimmed[range]) {
            return min(max(value, 0.0), 1.0)
        }
        return 0.5
    }
    
    /// Check if Ollama is available and model exists
    /// - Returns: True if Ollama is reachable and model is available
    public func checkAvailability() async throws -> Bool {
        let checkURL = "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/tags"
        
        guard URL(string: checkURL) != nil else {
            return false
        }
        
        do {
            let (response, responseData) = try await executeWithRetry(timeoutSeconds: Self.tagsTimeoutSeconds) {
                var request = HTTPClientRequest(url: checkURL)
                request.method = .GET
                request.headers.add(name: "Connection", value: "keep-alive")
                return request
            }
            
            guard response.status == .ok else {
                return false
            }
            
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                // Check if our model is in the list
                for modelInfo in models {
                    if let modelName = modelInfo["name"] as? String {
                        if modelName == model || modelName.hasPrefix("\(model):") {
                            return true
                        }
                    }
                }
            }
            
            // If we can't parse, assume it's available (backward compatibility)
            return true
        } catch {
            return false
        }
    }
    
    /// Verify model exists and is available
    /// - Throws: OllamaError if model is not available
    public func verifyModel() async throws {
        let isAvailable = try await checkAvailability()
        if !isAvailable {
            throw OllamaError.modelNotFound(model: model)
        }
    }

    /// Lightweight `/api/generate` probe for `:cloud` models before a heavy batch.
    /// Surfaces DNS/connectivity failures to ollama.com with an actionable message.
    /// Uses a small attempt budget so preflight fails fast when DNS is down.
    /// - Throws: `OllamaError` when the upstream is unreachable or returns a hard failure.
    public func probeCloudUpstreamConnectivity(timeoutSeconds: Int = 45) async throws {
        guard CloudBatchPrescription.isCloudModel(model) else { return }

        let apiURL = "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/generate"
        guard URL(string: apiURL) != nil else {
            throw OllamaError.invalidURL
        }

        let body: [String: Any] = Self.ollamaGenerateRequestBody(
            model: model,
            prompt: "Reply with exactly: OK",
            options: ["num_predict": 4, "temperature": 0]
        )
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw OllamaError.invalidResponse
        }

        // Fail fast on preflight — batch path still uses full DNS retry budget.
        Self.clientLock.lock()
        let savedCeiling = Self.maxRetryAttemptsCeiling
        Self.maxRetryAttemptsCeiling = 2
        Self.clientLock.unlock()
        defer {
            Self.clientLock.lock()
            Self.maxRetryAttemptsCeiling = savedCeiling
            Self.clientLock.unlock()
        }

        let response: HTTPClientResponse
        let responseData: Data
        do {
            let jsonDataForRequest = jsonData
            (response, responseData) = try await executeWithRetry(timeoutSeconds: timeoutSeconds) {
                var request = HTTPClientRequest(url: apiURL)
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")
                request.headers.add(name: "Accept", value: "application/json")
                request.headers.add(name: "Connection", value: "keep-alive")
                request.body = .bytes(ByteBuffer(data: jsonDataForRequest))
                return request
            }
        } catch {
            let wrapped = OllamaError.networkError(error)
            if OllamaRetryPolicy.isDNSConnectivityFailure(wrapped.description) {
                throw OllamaError.httpError(
                    statusCode: 502,
                    message: ": dial tcp: lookup ollama.com failed (\(error.localizedDescription))"
                )
            }
            throw wrapped
        }

        let statusCode = Int(response.status.code)
        guard response.status == .ok else {
            let preview = String(data: responseData, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
            var message = preview.isEmpty ? "" : ": \(preview)"
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let error = json["error"] as? String {
                message = ": \(error)"
            }
            throw OllamaError.httpError(statusCode: statusCode, message: "\(message) (cloud preflight)")
        }
    }
    
    /// Generate keywords with definitions from subjects
    /// - Parameters:
    ///   - subjects: Array of subjects or topics to generate keywords for
    ///   - count: Number of keyword pairs to generate (default: 10)
    /// - Returns: Dictionary mapping keywords to their definitions
    public func generateKeywords(
        from subjects: [String],
        count: Int = 10
    ) async throws -> [String: String] {
        let subjectsList = subjects.joined(separator: ", ")
        
        let prompt = """
        Generate \(count) keyword:definition pairs related to the following subject(s): \(subjectsList)
        
        Requirements:
        1. Each keyword should be a single word or short phrase (1-3 words max)
        2. Each definition should be a clear, concise explanation (one sentence)
        3. Keywords should be relevant to the given subject(s)
        4. Format your response EXACTLY as: keyword: definition (one per line)
        5. Do not include any additional text, explanations, or formatting
        6. Do not number the items
        7. Do not use quotes around keywords or definitions
        
        Example format:
        keyword1: definition of keyword1
        keyword2: definition of keyword2
        keyword3: definition of keyword3
        
        Generate \(count) keyword:definition pairs now:
        """
        
        // Ensure baseURL doesn't have trailing slash
        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiURL = "\(cleanBaseURL)/api/generate"
        
        guard let url = URL(string: apiURL) else {
            throw OllamaError.invalidURL
        }
        
        let options: [String: Any] = [
            "temperature": 0.7,
            "top_p": 0.9,
            "num_predict": 500
        ]
        let requestBody = Self.ollamaGenerateRequestBody(model: model, prompt: prompt, options: options)
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let response: HTTPClientResponse
        let responseData: Data
        do {
            let payload = jsonData
            (response, responseData) = try await executeWithRetry(timeoutSeconds: Self.keywordsTimeoutSeconds) {
                var request = HTTPClientRequest(url: apiURL)
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")
                request.headers.add(name: "Accept", value: "application/json")
                request.headers.add(name: "Connection", value: "keep-alive")
                request.body = .bytes(ByteBuffer(data: payload))
                return request
            }
        } catch let error as HTTPClientError {
            throw OllamaError.networkError(error)
        } catch {
            throw OllamaError.networkError(error)
        }
        
        guard response.status == .ok else {
            let statusCode = Int(response.status.code)
            var errorMessage = ""
            
            if !responseData.isEmpty {
                if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = ": \(error)"
                } else {
                    let responseText = String(data: responseData, encoding: .utf8) ?? ""
                    let preview = String(responseText.prefix(200))
                    errorMessage = ": \(preview)"
                }
            }
            
            if statusCode == 404 {
                throw OllamaError.modelNotFound(model: model)
            }
            
            throw OllamaError.httpError(statusCode: statusCode, message: errorMessage)
        }
        
        guard !responseData.isEmpty else {
            throw OllamaError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }
        
        // Parse the response into keyword:definition pairs
        let lines = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var keywords: [String: String] = [:]
        
        for line in lines {
            // Look for the pattern "keyword: definition"
            if let colonIndex = line.firstIndex(of: ":") {
                let keyword = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove quotes if present
                let cleanKeyword = keyword.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let cleanDefinition = definition.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                
                if !cleanKeyword.isEmpty && !cleanDefinition.isEmpty {
                    keywords[cleanKeyword] = cleanDefinition
                }
            }
        }
        
        return keywords
    }
}

/// Errors for Ollama client
public enum OllamaError: Error, CustomStringConvertible {
    case invalidURL
    case httpError(statusCode: Int, message: String = "")
    case invalidResponse
    case emptyGenerateResponse
    case networkError(Error)
    case modelNotFound(model: String)
    
    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid Ollama URL"
        case .httpError(let statusCode, let message):
            var tip = ""
            if statusCode == 429 {
                tip = " Rate limited — Yankovinator retries with backoff; lower --workers (cloud default ≤\(CloudBatchPrescription.cloudMaxConsumers)) if this persists."
            } else if OllamaRetryPolicy.isDNSConnectivityHTTPFailure(statusCode: statusCode, bodyOrMessage: message)
                        || OllamaRetryPolicy.isDNSConnectivityFailure(message) {
                tip = OllamaRetryPolicy.dnsConnectivityUserTip
            } else if statusCode == 502 || statusCode == 503 || statusCode == 504 {
                tip = " Upstream gateway error — retried with backoff; reduce concurrency if it keeps failing."
            }
            return "HTTP error \(statusCode)\(message)\(tip)"
        case .invalidResponse:
            return "Invalid response from Ollama API"
        case .emptyGenerateResponse:
            return """
            Ollama returned an empty line (no text in the `response` field). \
            Thinking models such as deepseek-v4-pro:cloud often put tokens into `thinking` instead. \
            Yankovinator sends `think: false` on generate requests; if you still see this, retry or use a non-thinking model.
            """
        case .networkError(let error):
            // Provide more detailed error information for AsyncHTTPClient errors
            let errorString = String(describing: error)
            let errorType = String(describing: type(of: error))
            let localizedDesc = error.localizedDescription
            
            // Build a comprehensive error message
            var errorDescription = "\(errorType)"
            if !localizedDesc.isEmpty && localizedDesc != errorString {
                errorDescription += ": \(localizedDesc)"
            } else if !errorString.isEmpty {
                errorDescription += ": \(errorString)"
            }
            
            // Add helpful suggestions based on error patterns
            var suggestions = ""
            if OllamaRetryPolicy.isDNSConnectivityFailure(errorString + " " + localizedDesc) {
                suggestions = OllamaRetryPolicy.dnsConnectivityUserTip
            } else if errorString.lowercased().contains("timeout") || errorString.lowercased().contains("deadline") {
                suggestions = " This may indicate Ollama is taking too long to respond. Try increasing the timeout or checking if Ollama is processing a large request."
            } else if errorString.lowercased().contains("can't assign requested address")
                        || errorString.lowercased().contains("cannot assign requested address") {
                suggestions = " Ephemeral ports were exhausted under high concurrency. Lower --workers (cloud default cap is \(CloudBatchPrescription.cloudMaxConsumers)) or wait and retry."
            } else if errorString.lowercased().contains("connection") && (errorString.lowercased().contains("close") || errorString.lowercased().contains("refused")) {
                suggestions = " This may indicate Ollama stopped responding or is not accessible. Ensure Ollama is running: 'ollama serve'"
            } else if errorString.contains("error 1") || errorString.contains("HTTPClientError") {
                suggestions = " Often caused by too many parallel cloud requests or a short timeout. Retry with --workers \(CloudBatchPrescription.cloudMaxConsumers), fewer --candidates, or --ollama-timeout 600."
            }
            
            return "Network error: \(errorDescription).\(suggestions) Please verify Ollama is running: 'ollama serve'"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please ensure the model is installed: ollama pull \(model)"
        }
    }
}

/// Limits in-flight Ollama HTTP calls for `:cloud` models (0 = unlimited / local).
actor CloudRequestGate {
    private var limit = 0
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func reconfigure(limit newLimit: Int) {
        limit = max(0, newLimit)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func acquire() async {
        guard limit > 0 else { return }
        while inFlight >= limit {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
        inFlight += 1
    }

    func release() {
        guard limit > 0 else { return }
        inFlight = max(0, inFlight - 1)
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }
}


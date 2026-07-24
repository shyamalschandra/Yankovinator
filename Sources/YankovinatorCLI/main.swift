// Copyright (C) 2025, Shyamal Suhana Chandra
// Command-line interface for Yankovinator

import Foundation
import ArgumentParser
import Yankovinator

@main
struct YankovinatorCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yankovinator",
        abstract: "Convert songs into parodies with theme-based constraints",
        discussion: """
        Yankovinator uses Apple's NaturalLanguage framework and Ollama to generate
        parodies that match the syllable structure of the original song while
        following theme keywords and their definitions.
        
        Example usage:
          swift run yankovinator lyrics.txt --keywords themes.txt --output parody.txt
        
        Note: If using line breaks, use backslashes:
          swift run yankovinator lyrics.txt \\
            --keywords themes.txt \\
            --output parody.txt
        """
    )
    
    @Argument(help: "Path to file containing original song lyrics (one line per verse)")
    var lyricsFile: String
    
    @Option(name: .shortAndLong, help: "Path to file containing keywords and definitions (format: keyword: definition)")
    var keywords: String?
    
    @Option(name: [.long, .customShort("u")], help: "Ollama API base URL")
    var ollamaURL: String = "http://localhost:11434"
    
    @Option(name: .shortAndLong, help: "Ollama model name (default: llama3.2:3b)")
    var model: String = "llama3.2:3b"
    
    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?
    
    // Validate options after parsing
    mutating func validate() throws {
        // Trim and validate lyrics file
        let originalLyricsFile = lyricsFile
        lyricsFile = lyricsFile.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for common issues
        if originalLyricsFile != lyricsFile && originalLyricsFile.contains(where: { $0.isWhitespace && !$0.isNewline }) {
            throw ValidationError("""
            Lyrics file path contains unexpected whitespace: "\(originalLyricsFile)"
            
            This often happens when:
            1. The command is split across lines without backslashes
            2. There are trailing spaces in the command
            3. The command was copied with extra whitespace
            
            Please ensure the command is on a single line, or use backslashes for line continuation.
            """)
        }
        
        guard !lyricsFile.isEmpty else {
            throw ValidationError("""
            Lyrics file path cannot be empty.
            
            Usage: yankovinator <lyrics-file> [options]
            
            Example:
              swift run yankovinator data/example_lyrics.txt --keywords data/example_keywords.txt
            """)
        }
        
        // Trim and validate Ollama URL
        ollamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ollamaURL.isEmpty else {
            throw ValidationError("Ollama URL cannot be empty")
        }
        
        // Trim and validate model name
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ValidationError("Model name cannot be empty")
        }
        
        // Trim and validate keywords file if provided
        if let keywordsFile = keywords {
            let trimmed = keywordsFile.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("Keywords file path cannot be empty. Omit --keywords if not needed.")
            }
            keywords = trimmed
        }
        
        // Trim and validate output file if provided
        if let outputPath = output {
            let trimmed = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("""
                Output file path cannot be empty or another flag.
                Omit --output to print to stdout, or provide a path:
                  yankovinator lyrics.txt --keywords themes.txt --output parody.txt
                """)
            }
            output = trimmed
        }

        // Guard against `--model` accidentally capturing a flag like `-a`
        if model.hasPrefix("-") {
            throw ValidationError("""
            Invalid model name "\(model)".
            If you meant defaults, omit --model entirely:
              yankovinator lyrics.txt --keywords themes.txt -a -v
            """)
        }
    }
    
    @Flag(name: .shortAndLong, help: "Show syllable analysis")
    var analyze: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    func run() async throws {
        if verbose {
            print("Yankovinator - Parody Generator")
            print("Copyright (C) 2025, Shyamal Suhana Chandra")
            print("")
        }
        
        // Read lyrics (already validated and trimmed in validate())
        guard let lyricsContent = try? String(contentsOfFile: lyricsFile, encoding: .utf8) else {
            throw ValidationError("Could not read lyrics file: \(lyricsFile)")
        }
        
        // Preserve empty lines to maintain song structure
        let originalLyrics = lyricsContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Check if there are any non-empty lines
        let nonEmptyLines = originalLyrics.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else {
            throw ValidationError("No lyrics found in file")
        }
        
        if verbose {
            print("Loaded \(originalLyrics.count) lines from \(lyricsFile)")
        }
        
        // Analyze structure if requested
        if analyze {
            // Only analyze non-empty lines
            let nonEmptyLyrics = originalLyrics.filter { !$0.isEmpty }
            let structure = Yankovinator.analyzeStructure(nonEmptyLyrics)
            print("\nSyllable Analysis:")
            print("=" * 50)
            var structureIndex = 0
            for (index, line) in originalLyrics.enumerated() {
                if line.isEmpty {
                    print("Line \(index + 1): (empty line)")
                    print("  ")
                } else {
                    let count = structure[structureIndex]
                    print("Line \(index + 1): \(count) syllables")
                    print("  \(line)")
                    structureIndex += 1
                }
            }
            print("=" * 50)
            print("")
        }
        
        // Read keywords
        var keywordsDict: [String: String] = [:]
        
        if let keywordsFile = keywords {
            // Already validated and trimmed in validate()
            guard let keywordsContent = try? String(contentsOfFile: keywordsFile, encoding: .utf8) else {
                throw ValidationError("Could not read keywords file: \(keywordsFile)")
            }
            
            let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
            keywordsDict = generator.extractKeywords(from: keywordsContent)
            
            if verbose {
                print("Loaded \(keywordsDict.count) keywords:")
                for (key, value) in keywordsDict {
                    print("  \(key): \(value)")
                }
                print("")
            }
        } else {
            if verbose {
                print("No keywords file provided. Using default theme.")
            }
            keywordsDict = ["parody": "humorous imitation", "creative": "original and imaginative"]
        }
        
        // Check Ollama connection
        if verbose {
            print("Checking Ollama connection...")
        }
        
        let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
        let isAvailable = try await generator.validateOllamaConnection()
        
        if !isAvailable {
            // Try to get more specific error
            do {
                try await generator.verifyModel()
            } catch let error as OllamaError {
                throw ValidationError("""
                \(error.description)
                
                To fix this:
                1. Ensure Ollama is running: ollama serve
                2. Install the model: ollama pull \(model)
                3. Verify model exists: ollama list
                """)
            } catch {
                throw ValidationError("""
                Ollama is not available at \(ollamaURL).
                Please ensure Ollama is running and accessible.
                Error: \(error.localizedDescription)
                """)
            }
        }
        
        if verbose {
            print("Ollama connection successful!")
            print("Generating parody...")
            print("")
        }
        
        // Generate parody
        let parodyLines: [String]
        do {
            parodyLines = try await generator.generateParody(
                originalLyrics: originalLyrics,
                keywords: keywordsDict,
                progressCallback: { line, total in
                    if verbose {
                        print("Progress: \(line)/\(total)", terminator: "\r")
                        fflush(stdout)
                    }
                },
                refinementPasses: 2,
                verbose: verbose
            )
            
            if verbose {
                print("\n")
            }
        } catch let error as OllamaError {
            var errorMsg = error.description
            
            // Provide helpful suggestions based on error type
            if case .modelNotFound(let modelName) = error {
                errorMsg += "\n\n"
                errorMsg += "To fix this:\n"
                errorMsg += "1. Check available models: ollama list\n"
                errorMsg += "2. Install the model: ollama pull \(modelName)\n"
                errorMsg += "   (Note: Model names may include tags like 'llama3.2:3b')\n"
                errorMsg += "3. Or use an existing model with --model flag\n"
                errorMsg += "   Example: --model llama3.2:3b\n"
            } else if case .httpError(let statusCode, let message) = error {
                errorMsg += "\n\n"
                errorMsg += "HTTP Error \(statusCode)\(message)\n"
                errorMsg += "To fix this:\n"
                errorMsg += "1. Ensure Ollama is running: ollama serve\n"
                errorMsg += "2. Verify Ollama is accessible at: \(ollamaURL)\n"
                errorMsg += "3. Check if the model exists: ollama list\n"
                errorMsg += "4. Try a different model: --model <model-name>\n"
            } else {
                errorMsg += "\n\n"
                errorMsg += "To fix this:\n"
                errorMsg += "1. Ensure Ollama is running: ollama serve\n"
                errorMsg += "2. Verify Ollama is accessible at: \(ollamaURL)\n"
                errorMsg += "3. Check Ollama logs for more details\n"
            }
            
            throw ValidationError(errorMsg)
        } catch {
            // Catch any other errors
            throw ValidationError("""
            Unexpected error during parody generation: \(error.localizedDescription)
            
            To fix this:
            1. Ensure Ollama is running: ollama serve
            2. Check Ollama logs for details
            3. Verify the model exists: ollama list
            """)
        }
        
        // Output results
        let outputText = parodyLines.joined(separator: "\n")
        
        if let outputPath = output {
            try outputText.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if verbose {
                print("Parody saved to: \(outputPath)")
            }
        } else {
            print("\nGenerated Parody:")
            print("=" * 50)
            print(outputText)
            print("=" * 50)
        }
    }
}

// Helper extension for string repetition
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}


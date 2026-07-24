// Copyright (C) 2025, Shyamal Suhana Chandra
// Command-line interface for generating keywords with definitions using Ollama

import Foundation
import ArgumentParser
import Yankovinator

@main
struct KeywordGeneratorCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyword-generator",
        abstract: "Generate keyword:definition pairs from subjects using Ollama LLM",
        discussion: """
        Keyword Generator uses Ollama's LLM (llama3.2:3b by default) to generate
        keyword:definition pairs based on one or more subjects you provide.

        The output is formatted as keyword: definition (one per line), suitable for
        use with the Yankovinator parody generator.

        Example usage:
          swift run keyword-generator "artificial intelligence" "machine learning" --output keywords.txt
          swift run keyword-generator "space exploration" --count 15 --output space_keywords.txt

        Parallel subjects against cloud Ollama:
          swift run keyword-generator "ai" "space" "music" --workers 10 \\
            --ollama-url https://ollama.example.com --output keywords.txt
        """
    )

    @Argument(help: "Subject(s) to generate keywords for (can specify multiple)")
    var subjects: [String]

    @Option(name: .shortAndLong, help: "Number of keyword pairs to generate (default: 10)")
    var count: Int = 10

    @Option(name: [.long, .customShort("u")], help: "Ollama API base URL (local or cloud)")
    var ollamaURL: String = "http://localhost:11434"

    @Option(name: .shortAndLong, help: "Ollama model name (default: llama3.2:3b)")
    var model: String = "llama3.2:3b"

    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?

    @Option(
        name: [.customLong("workers"), .customLong("jobs")],
        help: "Max parallel subject jobs against Ollama (1-32; default 1; use 10 for cloud)"
    )
    var workers: Int = 1

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    // Validate options after parsing
    mutating func validate() throws {
        subjects = subjects.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !subjects.isEmpty else {
            throw ValidationError("""
            At least one subject must be provided.

            Usage: keyword-generator <subject1> [subject2] [subject3] ... [options]

            Example:
              swift run keyword-generator "artificial intelligence" --count 10
              swift run keyword-generator "space" "exploration" "NASA" --workers 3 --output keywords.txt
            """)
        }

        guard count > 0 else {
            throw ValidationError("Count must be greater than 0")
        }

        guard count <= 100 else {
            throw ValidationError("Count cannot exceed 100 (to avoid excessive generation)")
        }

        do {
            try ParallelJobRunner.validateWorkers(workers)
        } catch let error as ParallelJobError {
            throw ValidationError(error.description)
        }

        ollamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ollamaURL.isEmpty else {
            throw ValidationError("Ollama URL cannot be empty")
        }

        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ValidationError("Model name cannot be empty")
        }

        if let outputPath = output {
            let trimmed = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw ValidationError("Output file path cannot be empty. Omit --output to print to stdout.")
            }
            output = trimmed
        }
    }

    func run() async throws {
        if verbose {
            print("Keyword Generator - Using Ollama LLM")
            print("Copyright (C) 2025, Shyamal Suhana Chandra")
            print("")
            print("Subjects: \(subjects.joined(separator: ", "))")
            print("Count: \(count)")
            print("Model: \(model)")
            print("Ollama URL: \(ollamaURL)")
            print("Workers: \(workers)")
            print("")
        }

        let client = OllamaClient(baseURL: ollamaURL, model: model)

        if verbose {
            print("Checking Ollama connection...")
        }

        let isAvailable = try await client.checkAvailability()

        if !isAvailable {
            do {
                try await client.verifyModel()
            } catch let error as OllamaError {
                throw ValidationError("""
                \(error.description)

                To fix this:
                1. Ensure Ollama is running or reachable at \(ollamaURL)
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
            print("Generating keywords...")
            print("")
        }

        let keywords: [String: String]
        do {
            if workers > 1 && subjects.count > 1 {
                keywords = try await generateInParallel(client: client)
            } else {
                keywords = try await client.generateKeywords(from: subjects, count: count)
            }
        } catch let error as OllamaError {
            throw ValidationError(formatOllamaError(error))
        } catch let error as ParallelJobError {
            throw ValidationError(error.description)
        } catch {
            throw ValidationError("""
            Unexpected error during keyword generation: \(error.localizedDescription)

            To fix this:
            1. Ensure Ollama is running or reachable at \(ollamaURL)
            2. Check Ollama logs for details
            3. Verify the model exists: ollama list
            """)
        }

        guard !keywords.isEmpty else {
            throw ValidationError("""
            No keywords were generated. This might indicate:
            1. The LLM response format was unexpected
            2. The model needs better prompting
            3. Try increasing the count or using different subjects
            """)
        }

        if verbose {
            print("Generated \(keywords.count) keyword:definition pairs")
            print("")
        }

        let outputLines = keywords.map { "\($0.key): \($0.value)" }
            .sorted()
        let outputText = outputLines.joined(separator: "\n")

        if let outputPath = output {
            try outputText.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if verbose {
                print("Keywords saved to: \(outputPath)")
            } else {
                print("Generated \(keywords.count) keywords and saved to: \(outputPath)")
            }
        } else {
            if verbose {
                print("Generated Keywords:")
                print("=" * 50)
            }
            print(outputText)
            if verbose {
                print("=" * 50)
            }
        }
    }

    /// One parallel job per subject; merge unique keyword pairs.
    private func generateInParallel(client: OllamaClient) async throws -> [String: String] {
        let perSubjectCount = max(1, count / subjects.count)
        let log = JobLog()
        let verbose = self.verbose

        if verbose {
            print("Parallel mode: \(subjects.count) subject job(s), \(workers) worker(s), ~\(perSubjectCount) keywords each")
        }

        let partials: [[String: String]] = try await ParallelJobRunner.map(
            items: subjects,
            workers: workers,
            progress: { completed, total in
                if verbose {
                    Task { await log.printLine("Subject jobs completed: \(completed)/\(total)") }
                }
            }
        ) { subject in
            if verbose {
                await log.printLine("[\(subject)] generating…")
            }
            return try await client.generateKeywords(from: [subject], count: perSubjectCount)
        }

        var merged: [String: String] = [:]
        for dict in partials {
            for (key, value) in dict {
                if merged[key] == nil {
                    merged[key] = value
                }
            }
        }

        // If parallel merge undershot the requested count, top up with one combined call.
        if merged.count < count {
            let remaining = count - merged.count
            if verbose {
                print("Topping up \(remaining) more keyword(s) to reach --count \(count)…")
            }
            let extra = try await client.generateKeywords(from: subjects, count: remaining)
            for (key, value) in extra where merged[key] == nil {
                merged[key] = value
            }
        }

        return merged
    }

    private func formatOllamaError(_ error: OllamaError) -> String {
        var errorMsg = error.description

        if case .modelNotFound(let modelName) = error {
            errorMsg += "\n\n"
            errorMsg += "To fix this:\n"
            errorMsg += "1. Check available models: ollama list\n"
            errorMsg += "2. Install the model: ollama pull \(modelName)\n"
            errorMsg += "3. Or use an existing model with --model flag\n"
        } else if case .httpError(let statusCode, let message) = error {
            errorMsg += "\n\n"
            errorMsg += "HTTP Error \(statusCode)\(message)\n"
            errorMsg += "To fix this:\n"
            errorMsg += "1. Ensure Ollama is running or the cloud endpoint is reachable\n"
            errorMsg += "2. Verify Ollama is accessible at: \(ollamaURL)\n"
        }

        return errorMsg
    }
}

// Helper extension for string repetition
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

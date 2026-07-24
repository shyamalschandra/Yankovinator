// Copyright (C) 2025, Shyamal Suhana Chandra
// Command-line interface for benchmarking Yankovinator performance

import Foundation
import ArgumentParser
import Yankovinator

@main
struct BenchmarkCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Benchmark Yankovinator performance with Ollama",
        discussion: """
        Benchmark tool to measure Yankovinator's performance using Ollama.

        Example usage:
          swift run benchmark --lyrics data/example_lyrics.txt --keywords data/example_keywords.txt

        Parallel iterations against cloud Ollama:
          swift run benchmark --lyrics data/example_lyrics.txt --iterations 10 \\
            --workers 10 --ollama-url https://ollama.example.com --verbose
        """
    )

    @Option(name: .shortAndLong, help: "Path to lyrics file")
    var lyrics: String

    @Option(name: .shortAndLong, help: "Path to keywords file")
    var keywords: String?

    @Option(name: [.long, .customShort("u")], help: "Ollama base URL (local or cloud; default: http://localhost:11434)")
    var ollamaURL: String = "http://localhost:11434"

    @Option(name: .shortAndLong, help: "Ollama model name (default: llama3.2:3b)")
    var model: String = "llama3.2:3b"

    @Option(name: .shortAndLong, help: "Number of iterations (default: 1)")
    var iterations: Int = 1

    @Option(
        name: [.customLong("workers"), .customLong("jobs")],
        help: "Max parallel benchmark iterations (1-32; default 1; use 10 for cloud)"
    )
    var workers: Int = 1

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    mutating func validate() throws {
        guard iterations >= 1 else {
            throw ValidationError("Iterations must be at least 1")
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
    }

    func run() async throws {
        print("=== Yankovinator Benchmark ===")
        print("Framework: Ollama")
        print("")

        guard let lyricsContent = try? String(contentsOfFile: lyrics, encoding: .utf8) else {
            throw ValidationError("Could not read lyrics file: \(lyrics)")
        }

        let lyricsLines = lyricsContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lyricsLines.isEmpty else {
            throw ValidationError("No lyrics found in file")
        }

        var keywordsDict: [String: String] = [:]
        if let keywordsFile = keywords {
            guard let keywordsContent = try? String(contentsOfFile: keywordsFile, encoding: .utf8) else {
                throw ValidationError("Could not read keywords file: \(keywordsFile)")
            }

            let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
            keywordsDict = generator.extractKeywords(from: keywordsContent)
        } else {
            keywordsDict = ["parody": "humorous imitation", "creative": "original and imaginative"]
        }

        if verbose {
            print("Test Configuration:")
            print("  Lyrics: \(lyricsLines.count) lines")
            print("  Keywords: \(keywordsDict.count) keywords")
            print("  Ollama URL: \(ollamaURL)")
            print("  Model: \(model)")
            print("  Iterations: \(iterations)")
            print("  Workers: \(workers)")
            print("")
        }

        let runner = BenchmarkRunner(
            lyrics: lyricsLines,
            keywords: keywordsDict,
            ollamaBaseURL: ollamaURL,
            ollamaModel: model
        )

        let iterationIndexes = Array(1...iterations)
        let log = JobLog()
        let verbose = self.verbose
        let wallStart = Date()

        let results: [BenchmarkResults] = try await ParallelJobRunner.map(
            items: iterationIndexes,
            workers: workers,
            progress: { completed, total in
                if verbose {
                    Task { await log.printLine("Iterations completed: \(completed)/\(total)") }
                }
            }
        ) { i in
            if verbose {
                await log.printLine("Running iteration \(i)/\(iterations)…")
            }
            let result = try await runner.benchmarkOllama()
            if verbose {
                await log.printLine("  Iteration \(i): \(String(format: "%.2f", result.totalTime))s (avg \(String(format: "%.2f", result.averageTimePerLine))s/line)")
            }
            return result
        }

        let wallTime = Date().timeIntervalSince(wallStart)
        let avgTotalTime = results.map { $0.totalTime }.reduce(0, +) / Double(results.count)
        let avgPerLine = results.map { $0.averageTimePerLine }.reduce(0, +) / Double(results.count)

        print("")
        print("=== Benchmark Results ===")
        print("Framework: Ollama")
        print("Iterations: \(iterations)")
        print("Workers: \(workers)")
        print("Wall-clock Time: \(String(format: "%.2f", wallTime))s")
        print("Average Total Time (per iteration): \(String(format: "%.2f", avgTotalTime))s")
        print("Average Time per Line: \(String(format: "%.2f", avgPerLine))s")
        print("Total Lines: \(lyricsLines.count)")
        print("")

        if iterations > 1 {
            let minTime = results.map { $0.totalTime }.min() ?? 0
            let maxTime = results.map { $0.totalTime }.max() ?? 0
            print("Min Iteration Time: \(String(format: "%.2f", minTime))s")
            print("Max Iteration Time: \(String(format: "%.2f", maxTime))s")
        }
    }
}

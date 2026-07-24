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

        Single-file example:
          swift run yankovinator lyrics.txt --keywords themes.txt --output parody.txt

        Parallel batch (one theme, many songs):
          swift run yankovinator --input-dir ./songs --output-dir ./out \\
            --keywords themes.txt --ollama-url https://ollama.example.com \\
            --workers 10 --verbose

        Combinatorial batch (every song × every theme):
          swift run yankovinator --input-dir ./songs --themes-dir ./themes \\
            --output-dir ./out --workers 10 --verbose
          # Outputs: out/<theme>/<song>.parody.txt
          # If songs×themes > 100, add --force

        Note: If using line breaks, use backslashes:
          swift run yankovinator lyrics.txt \\
            --keywords themes.txt \\
            --output parody.txt
        """
    )

    @Argument(help: "Path to a lyrics file (omit when using --input-dir)")
    var lyricsFile: String?

    @Option(name: .shortAndLong, help: "Path to file containing keywords and definitions (format: keyword: definition)")
    var keywords: String?

    @Option(name: [.long, .customShort("u")], help: "Ollama API base URL (local or cloud)")
    var ollamaURL: String = "http://localhost:11434"

    @Option(name: .shortAndLong, help: "Ollama model name (default: llama3.2:3b)")
    var model: String = "llama3.2:3b"

    @Option(name: .shortAndLong, help: "Output file path for single-file mode (default: stdout)")
    var output: String?

    @Option(name: .long, help: "Directory of .txt lyrics files to process as parallel jobs")
    var inputDir: String?

    @Option(name: .long, help: "Directory of .txt theme/keyword files; with --input-dir builds songs × themes jobs")
    var themesDir: String?

    @Option(name: .long, help: "Directory for batch parody outputs (required for batch / cross-product modes)")
    var outputDir: String?

    @Option(
        name: [.customLong("workers"), .customLong("jobs")],
        help: "Max parallel Ollama jobs (1-32; default 1; use 10 for cloud batch)"
    )
    var workers: Int = 1

    @Flag(name: .long, help: "Allow songs×themes cross-products larger than 100 jobs")
    var force: Bool = false

    @Flag(name: .shortAndLong, help: "Show syllable analysis")
    var analyze: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    // Validate options after parsing
    mutating func validate() throws {
        if let file = lyricsFile {
            let original = file
            let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
            if original != trimmed && original.contains(where: { $0.isWhitespace && !$0.isNewline }) {
                throw ValidationError("""
                Lyrics file path contains unexpected whitespace: "\(original)"

                This often happens when:
                1. The command is split across lines without backslashes
                2. There are trailing spaces in the command
                3. The command was copied with extra whitespace

                Please ensure the command is on a single line, or use backslashes for line continuation.
                """)
            }
            lyricsFile = trimmed.isEmpty ? nil : trimmed
        }

        if let dir = inputDir {
            let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("--input-dir cannot be empty.")
            }
            inputDir = trimmed
        }

        if let dir = themesDir {
            let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("--themes-dir cannot be empty.")
            }
            themesDir = trimmed
        }

        if let dir = outputDir {
            let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("--output-dir cannot be empty.")
            }
            outputDir = trimmed
        }

        let hasFile = lyricsFile != nil
        let hasSongsDir = inputDir != nil
        let hasThemesDir = themesDir != nil

        guard hasFile || hasSongsDir else {
            throw ValidationError("""
            Provide a lyrics file or --input-dir for batch jobs.

            Single file:
              yankovinator lyrics.txt --keywords themes.txt --output parody.txt

            Many songs, one theme:
              yankovinator --input-dir ./songs --output-dir ./out --keywords themes.txt --workers 10

            Every song × every theme:
              yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out --workers 10
            """)
        }

        if hasFile && hasSongsDir {
            throw ValidationError("Use either a lyrics file or --input-dir, not both.")
        }

        if hasThemesDir && keywords != nil {
            throw ValidationError("Use either --keywords or --themes-dir, not both.")
        }

        let needsOutputDir = hasSongsDir || (hasFile && hasThemesDir)
        if needsOutputDir && outputDir == nil {
            throw ValidationError(ParallelJobError.missingOutputDirectory.description)
        }

        if hasThemesDir && !hasSongsDir && !hasFile {
            throw ValidationError("--themes-dir requires a lyrics file or --input-dir.")
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

        if model.hasPrefix("-") {
            throw ValidationError("""
            Invalid model name "\(model)".
            If you meant defaults, omit --model entirely:
              yankovinator lyrics.txt --keywords themes.txt -a -v
            """)
        }

        if let keywordsFile = keywords {
            let trimmed = keywordsFile.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("-") {
                throw ValidationError("Keywords file path cannot be empty. Omit --keywords if not needed.")
            }
            keywords = trimmed
        }

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
    }

    func run() async throws {
        if verbose {
            print("Yankovinator - Parody Generator")
            print("Copyright (C) 2025, Shyamal Suhana Chandra")
            print("")
            print("Ollama URL: \(ollamaURL)")
            print("Model: \(model)")
            print("Workers: \(workers)")
            print("")
        }

        let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
        try await ensureOllamaReady(generator)

        if let inputDir, let outputDir, let themesDir {
            let jobs = try buildJobs {
                try ParodyBatchJobBuilder.crossProductJobs(
                    inputDir: inputDir,
                    themesDir: themesDir,
                    outputDir: outputDir,
                    force: force
                )
            }
            try await runJobs(jobs, sharedKeywords: nil, label: "songs × themes")
        } else if let inputDir, let outputDir {
            let shared = try loadKeywords()
            let jobs = try buildJobs {
                try ParodyBatchJobBuilder.jobs(inputDir: inputDir, outputDir: outputDir)
            }
            try await runJobs(jobs, sharedKeywords: shared, label: "songs (shared theme)")
        } else if let lyricsFile, let themesDir, let outputDir {
            let jobs = try buildJobs {
                try ParodyBatchJobBuilder.jobs(
                    lyricsPath: lyricsFile,
                    themesDir: themesDir,
                    outputDir: outputDir,
                    force: force
                )
            }
            try await runJobs(jobs, sharedKeywords: nil, label: "one song × themes")
        } else if let lyricsFile {
            if workers > 1 && verbose {
                print("Note: --workers applies to batch / cross-product modes. Running a single job.")
                print("")
            }
            let keywordsDict = try loadKeywords()
            try await runSingleFile(lyricsFile: lyricsFile, keywordsDict: keywordsDict, generator: generator)
        }
    }

    // MARK: - Modes

    private func buildJobs(_ builder: () throws -> [ParodyBatchJob]) throws -> [ParodyBatchJob] {
        do {
            return try builder()
        } catch let error as ParallelJobError {
            throw ValidationError(error.description)
        }
    }

    private func runSingleFile(
        lyricsFile: String,
        keywordsDict: [String: String],
        generator: ParodyGenerator
    ) async throws {
        let originalLyrics = try readLyrics(from: lyricsFile)

        if verbose {
            print("Loaded \(originalLyrics.count) lines from \(lyricsFile)")
        }

        if analyze {
            printSyllableAnalysis(originalLyrics)
        }

        if verbose {
            print("Generating parody...")
            print("")
        }

        let parodyLines = try await generateParodyLines(
            generator: generator,
            originalLyrics: originalLyrics,
            keywords: keywordsDict,
            jobLabel: nil
        )

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

    private func runJobs(
        _ jobs: [ParodyBatchJob],
        sharedKeywords: [String: String]?,
        label: String
    ) async throws {
        if verbose {
            print("Batch mode (\(label)): \(jobs.count) job(s), up to \(workers) parallel worker(s)")
            for job in jobs.prefix(20) {
                let themeNote = job.themeId.map { " theme=\($0)" } ?? ""
                print("  • \(job.id)\(themeNote) → \(job.outputPath)")
            }
            if jobs.count > 20 {
                print("  … and \(jobs.count - 20) more")
            }
            print("")
        }

        let log = JobLog()
        let ollamaURL = self.ollamaURL
        let model = self.model
        let analyze = self.analyze
        let verbose = self.verbose
        let defaultKeywords = sharedKeywords
            ?? ["parody": "humorous imitation", "creative": "original and imaginative"]

        let outcomes: [(id: String, outputPath: String)] = try await ParallelJobRunner.map(
            items: jobs,
            workers: workers,
            progress: { completed, total in
                if verbose {
                    Task { await log.printLine("Jobs completed: \(completed)/\(total)") }
                }
            }
        ) { job in
            let lyrics = try Self.readLyricsStatic(from: job.lyricsPath)
            let keywordsDict: [String: String]
            if let keywordsPath = job.keywordsPath {
                keywordsDict = try Self.loadKeywordsFileStatic(
                    path: keywordsPath,
                    ollamaURL: ollamaURL,
                    model: model
                )
            } else {
                keywordsDict = defaultKeywords
            }

            if analyze {
                await log.printLine("[\(job.id)] syllable analysis (\(lyrics.filter { !$0.isEmpty }.count) non-empty lines)")
            }

            let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
            if verbose {
                await log.printLine("[\(job.id)] generating (\(keywordsDict.count) keywords)…")
            }

            let parodyLines = try await generator.generateParody(
                originalLyrics: lyrics,
                keywords: keywordsDict,
                progressCallback: { line, total in
                    if verbose {
                        Task { await log.printLine("[\(job.id)] line \(line)/\(total)") }
                    }
                },
                refinementPasses: 2,
                verbose: false
            )

            let outputText = parodyLines.joined(separator: "\n")
            try outputText.write(toFile: job.outputPath, atomically: true, encoding: .utf8)

            if verbose {
                await log.printLine("[\(job.id)] saved → \(job.outputPath)")
            }

            return (id: job.id, outputPath: job.outputPath)
        }

        print("Completed \(outcomes.count) parallel job(s) with \(workers) worker(s) (\(label)).")
        for outcome in outcomes.prefix(50) {
            print("  \(outcome.id): \(outcome.outputPath)")
        }
        if outcomes.count > 50 {
            print("  … and \(outcomes.count - 50) more")
        }
    }

    // MARK: - Shared helpers

    private func loadKeywords() throws -> [String: String] {
        if let keywordsFile = keywords {
            return try Self.loadKeywordsFileStatic(
                path: keywordsFile,
                ollamaURL: ollamaURL,
                model: model,
                verbose: verbose
            )
        }

        if verbose {
            print("No keywords file provided. Using default theme.")
            print("")
        }
        return ["parody": "humorous imitation", "creative": "original and imaginative"]
    }

    private static func loadKeywordsFileStatic(
        path: String,
        ollamaURL: String,
        model: String,
        verbose: Bool = false
    ) throws -> [String: String] {
        guard let keywordsContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ValidationError("Could not read keywords file: \(path)")
        }

        let extractor = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
        let keywordsDict = extractor.extractKeywords(from: keywordsContent)
        if verbose {
            print("Loaded \(keywordsDict.count) keywords from \(path):")
            for (key, value) in keywordsDict {
                print("  \(key): \(value)")
            }
            print("")
        }
        return keywordsDict
    }

    private func ensureOllamaReady(_ generator: ParodyGenerator) async throws {
        if verbose {
            print("Checking Ollama connection...")
        }

        let isAvailable = try await generator.validateOllamaConnection()
        if !isAvailable {
            do {
                try await generator.verifyModel()
            } catch let error as OllamaError {
                throw ValidationError("""
                \(error.description)

                To fix this:
                1. Ensure Ollama is running (local) or reachable (cloud): \(ollamaURL)
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
            print("")
        }
    }

    private func readLyrics(from path: String) throws -> [String] {
        try Self.readLyricsStatic(from: path)
    }

    private static func readLyricsStatic(from path: String) throws -> [String] {
        guard let lyricsContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ValidationError("Could not read lyrics file: \(path)")
        }

        let originalLyrics = lyricsContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let nonEmptyLines = originalLyrics.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else {
            throw ValidationError("No lyrics found in file: \(path)")
        }
        return originalLyrics
    }

    private func printSyllableAnalysis(_ originalLyrics: [String]) {
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

    private func generateParodyLines(
        generator: ParodyGenerator,
        originalLyrics: [String],
        keywords: [String: String],
        jobLabel: String?
    ) async throws -> [String] {
        do {
            return try await generator.generateParody(
                originalLyrics: originalLyrics,
                keywords: keywords,
                progressCallback: { line, total in
                    if verbose {
                        if let jobLabel {
                            print("[\(jobLabel)] Progress: \(line)/\(total)", terminator: "\r")
                        } else {
                            print("Progress: \(line)/\(total)", terminator: "\r")
                        }
                        fflush(stdout)
                    }
                },
                refinementPasses: 2,
                verbose: verbose
            )
        } catch let error as OllamaError {
            throw ValidationError(formatOllamaError(error))
        } catch {
            throw ValidationError("""
            Unexpected error during parody generation: \(error.localizedDescription)

            To fix this:
            1. Ensure Ollama is running / reachable at \(ollamaURL)
            2. Check Ollama logs for details
            3. Verify the model exists: ollama list
            """)
        }
    }

    private func formatOllamaError(_ error: OllamaError) -> String {
        var errorMsg = error.description

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
            errorMsg += "1. Ensure Ollama is running or the cloud endpoint is reachable\n"
            errorMsg += "2. Verify Ollama is accessible at: \(ollamaURL)\n"
            errorMsg += "3. Check if the model exists: ollama list\n"
            errorMsg += "4. Try a different model: --model <model-name>\n"
        } else {
            errorMsg += "\n\n"
            errorMsg += "To fix this:\n"
            errorMsg += "1. Ensure Ollama is running or the cloud endpoint is reachable\n"
            errorMsg += "2. Verify Ollama is accessible at: \(ollamaURL)\n"
            errorMsg += "3. Check Ollama logs for more details\n"
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

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

        Batch (every song × every theme × N candidates):
          swift run yankovinator --input-dir ./songs --themes-dir ./themes \\
            --output-dir ./out --workers 10 --candidates 10 --verbose
          # Outputs best: out/<theme>/<song>.parody.txt
          # Optional: --keep-candidates writes ranked variants
          # If songs×themes×candidates > 100, add --force
          # Stop/restart: progress is checkpointed under --output-dir/.yankovinator (use --fresh-batch to reset)
        """
    )

    @Option(name: [.long, .customShort("u")], help: "Ollama API base URL (local or cloud)")
    var ollamaURL: String = "http://localhost:11434"

    @Option(name: .shortAndLong, help: "Ollama model name (default: llama3.2:3b)")
    var model: String = "llama3.2:3b"

    @Option(name: .long, help: "Per-request Ollama HTTP timeout in seconds (30-900; default 300 for :cloud models, 180 otherwise)")
    var ollamaTimeout: Int?

    @Option(
        name: [.long, .customLong("ollama-num-workers")],
        help: "Ollama server OLLAMA_NUM_PARALLEL (docs.ollama.com/faq). Default: env OLLAMA_NUM_PARALLEL on localhost; caps consumers. Alias: --ollama-num-workers."
    )
    var ollamaNumParallel: Int?

    @Option(name: .long, help: "Directory of .txt lyrics files to process as parallel jobs")
    var inputDir: String?

    @Option(name: .long, help: "Directory of .txt theme/keyword files (keyword: definition per line)")
    var themesDir: String?

    @Option(name: .long, help: "Directory for batch parody outputs (layout: <theme>/<song>.parody.txt)")
    var outputDir: String?

    @Option(
        name: [.customLong("workers"), .customLong("jobs")],
        help: "Parallel Ollama worker count (1-\(ParallelJobRunner.maxWorkers); default 1). Match OLLAMA_NUM_PARALLEL on the server."
    )
    var workers: Int = 1

    @Option(
        name: .long,
        help: "Cap in-flight consumer tasks (defaults to --workers; 1-\(ParallelJobRunner.maxConcurrentConsumers))"
    )
    var consumers: Int?

    @Option(
        name: .long,
        help: "Parody candidates per song×theme (1-\(CandidateParodyGenerator.maxCandidates); default 1; use 10 to rank and keep the best)"
    )
    var candidates: Int = 1

    @Flag(name: .long, help: "Write all ranked candidate files under <song>.candidates/")
    var keepCandidates: Bool = false

    @Flag(name: .long, help: "Allow songs×themes×candidates totals larger than 100 generations")
    var force: Bool = false

    @Flag(name: .shortAndLong, help: "Show syllable analysis")
    var analyze: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Disable stderr progress bar for batch / multi-candidate runs")
    var noProgress: Bool = false

    @Flag(name: .long, help: "Play lightweight MIDI cues per worker progress bar (interactive terminal only)")
    var midiProgress: Bool = false

    @Flag(name: .long, help: "Disable auto cloud batch prescription (worker cap, timeout, fast coherence)")
    var noCloudPrescription: Bool = false

    @Flag(name: .long, help: "Extra Ollama hill-climbing per line in batch (syllables/POS/coherence); slower but higher fit scores")
    var fitOptimize: Bool = false

    @Flag(name: .long, help: "Discard saved batch checkpoint in --output-dir/.yankovinator and regenerate all jobs")
    var freshBatch: Bool = false

    // Validate options after parsing
    mutating func validate() throws {
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

        guard inputDir != nil else {
            throw ValidationError("""
            --input-dir is required (directory of .txt lyrics files).

            Example:
              yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \\
                --workers 10 --candidates 10
            """)
        }

        guard themesDir != nil else {
            throw ValidationError("""
            --themes-dir is required (directory of .txt theme keyword files).

            Example:
              yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \\
                --workers 10 --candidates 10
            """)
        }

        guard outputDir != nil else {
            throw ValidationError(ParallelJobError.missingOutputDirectory.description)
        }

        do {
            try CandidateParodyGenerator.validateCandidates(candidates)
        } catch let error as ParallelJobError {
            throw ValidationError(error.description)
        }

        do {
            try ParallelJobRunner.validateWorkers(workers)
        } catch let error as ParallelJobError {
            throw ValidationError(error.description)
        }

        if let consumers {
            guard consumers >= 1, consumers <= ParallelJobRunner.maxConcurrentConsumers else {
                throw ValidationError(
                    "Consumers must be between 1 and \(ParallelJobRunner.maxConcurrentConsumers) (got \(consumers))."
                )
            }
        }

        if let timeout = ollamaTimeout {
            guard timeout >= 30, timeout <= 900 else {
                throw ValidationError("Ollama timeout must be between 30 and 900 seconds.")
            }
        }

        if let parallel = ollamaNumParallel, parallel < 1 {
            throw ValidationError("OLLAMA_NUM_PARALLEL must be at least 1 (got \(parallel)).")
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
            If you meant defaults, omit --model entirely.
            """)
        }
    }

    private func resolvedOllamaNumParallel() -> Int? {
        if let ollamaNumParallel { return ollamaNumParallel }
        guard ParallelJobRunner.isLocalOllamaHost(ollamaURL) else { return nil }
        return OllamaParallelPolicy.serverNumParallelFromEnvironment()
    }

    private func consumerPoolSize(effectiveRequestedWorkers: Int? = nil) -> Int {
        ParallelJobRunner.consumerPoolSize(
            requestedWorkers: effectiveRequestedWorkers ?? workers,
            ollamaNumParallel: resolvedOllamaNumParallel(),
            model: model,
            applyCloudPrescription: !noCloudPrescription && effectiveRequestedWorkers == nil,
            consumerOverride: consumers
        )
    }

    func run() async throws {
        let serverParallel = resolvedOllamaNumParallel()
        OllamaParallelPolicy.printServerParallelHintIfNeeded(
            baseURL: ollamaURL,
            requestedWorkers: workers,
            ollamaNumParallel: serverParallel,
            verbose: verbose
        )

        if verbose {
            print("Yankovinator - Parody Generator")
            print("Copyright (C) 2025, Shyamal Suhana Chandra")
            print("")
            print("Ollama URL: \(ollamaURL)")
            print("Model: \(model)")
            print("Workers: \(workers) (consumer pool: \(consumerPoolSize()))")
            if let serverParallel {
                print("OLLAMA_NUM_PARALLEL (server): \(serverParallel)")
            }
            print("Candidates: \(candidates)")
            if let ollamaTimeout {
                print("Ollama timeout: \(ollamaTimeout)s")
            } else if model.lowercased().contains("cloud") {
                let heavy = CloudBatchPrescription.isHeavyCloudModel(model)
                print("Ollama timeout: \(heavy ? CloudBatchPrescription.heavyCloudTimeoutSeconds : 300)s (cloud model default)")
            }
            print("")
        }

        OllamaClient.applyRuntimePolicy(
            model: model,
            workers: workers,
            ollamaNumParallel: serverParallel,
            timeoutOverride: ollamaTimeout
        )

        let generator = ParodyGenerator(ollamaBaseURL: ollamaURL, ollamaModel: model)
        try await ensureOllamaReady(generator)

        guard let inputDir, let outputDir, let themesDir else {
            return
        }

        let jobs = try buildJobs {
            try ParodyBatchJobBuilder.crossProductJobs(
                inputDir: inputDir,
                themesDir: themesDir,
                outputDir: outputDir,
                force: true // effective songs×themes×candidates checked below
            )
        }
        try enforceGenerationBudget(baseJobs: jobs.count, songCountHint: nil, themeCountHint: nil)
        try await runJobs(jobs, outputRoot: outputDir, label: "songs × themes × candidates")
    }

    private func enforceGenerationBudget(
        baseJobs: Int,
        songCountHint: Int?,
        themeCountHint: Int?
    ) throws {
        let total = baseJobs * candidates
        if total > ParallelJobRunner.crossProductForceThreshold && !force {
            throw ValidationError(
                ParallelJobError.crossProductRequiresForce(
                    songCount: songCountHint ?? baseJobs,
                    themeCount: themeCountHint ?? 1,
                    candidates: candidates,
                    total: total,
                    threshold: ParallelJobRunner.crossProductForceThreshold
                ).description
            )
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

    private struct ExpandedCandidateJob: Sendable {
        let job: ParodyBatchJob
        let candidateIndex: Int
    }

    private struct ScoredExpansion: Sendable {
        let job: ParodyBatchJob
        let result: ParodyCandidateResult
    }

    private func runJobs(
        _ jobs: [ParodyBatchJob],
        outputRoot: String,
        label: String
    ) async throws {
        let generations = jobs.count * candidates
        if verbose {
            print("Batch mode (\(label)): \(jobs.count) base job(s) × \(candidates) candidate(s) = \(generations) generation(s)")
            print("Workers: \(workers) (consumer pool: \(consumerPoolSize()))")
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
        let keepCandidates = self.keepCandidates
        let defaultKeywords = ["parody": "humorous imitation", "creative": "original and imaginative"]

        var expanded: [ExpandedCandidateJob] = []
        expanded.reserveCapacity(generations)
        for job in jobs {
            for candidateIndex in 1...candidates {
                expanded.append(ExpandedCandidateJob(job: job, candidateIndex: candidateIndex))
            }
        }

        let jobsFingerprint = BatchResumeStore.jobsFingerprint(jobs: jobs, candidates: candidates, model: model)
        let resumeManifest = BatchResumeManifest(
            model: model,
            candidates: candidates,
            jobsFingerprint: jobsFingerprint
        )
        let resumeStore: BatchResumeStore
        do {
            resumeStore = try BatchResumeStore(outputRoot: outputRoot, manifest: resumeManifest, fresh: freshBatch)
        } catch let error as BatchResumeError {
            throw ValidationError(error.description)
        }

        var scoredPreloaded: [ScoredExpansion] = []
        var pendingExpanded: [ExpandedCandidateJob] = []
        pendingExpanded.reserveCapacity(expanded.count)
        for item in expanded {
            if await resumeStore.isComplete(jobID: item.job.id, candidateIndex: item.candidateIndex),
               let restored = await resumeStore.restoredResult(jobID: item.job.id, candidateIndex: item.candidateIndex) {
                scoredPreloaded.append(ScoredExpansion(job: item.job, result: restored))
            } else {
                pendingExpanded.append(item)
            }
        }

        let restoredCount = scoredPreloaded.count
        let pendingGenerations = pendingExpanded.count

        var lyricsByPath: [String: [String]] = [:]
        var keywordsByPath: [String: [String: String]] = [:]
        lyricsByPath.reserveCapacity(jobs.count)
        for job in jobs {
            if lyricsByPath[job.lyricsPath] == nil {
                lyricsByPath[job.lyricsPath] = try Self.readLyricsStatic(from: job.lyricsPath)
            }
            if let path = job.keywordsPath, keywordsByPath[path] == nil {
                keywordsByPath[path] = try Self.loadKeywordsFileStatic(path: path)
            }
        }
        // Touch shared dictionary once (background load) instead of per worker.
        _ = OEDDictionary.shared

        let rx = CloudBatchPrescription.plan(
            model: model,
            requestedWorkers: workers,
            ollamaTimeout: ollamaTimeout,
            enabled: !noCloudPrescription
        )
        CloudBatchPrescription.printPlan(rx)
        if let timeout = rx.appliedTimeoutSeconds {
            OllamaClient.applyRuntimePolicy(
                model: model,
                workers: rx.effectiveWorkers,
                ollamaNumParallel: resolvedOllamaNumParallel(),
                timeoutOverride: timeout
            )
        }

        let showProgress = !noProgress && generations > 1 && pendingGenerations > 0
        let poolSize = consumerPoolSize(effectiveRequestedWorkers: rx.effectiveWorkers)
        let serverParallel = resolvedOllamaNumParallel()
        let progressHandle: CLIWorkerPoolProgress? =
            (showProgress && TerminalProgress.isInteractive && poolSize > 1)
            ? CLIWorkerPoolProgress(
                total: pendingGenerations,
                workerCount: poolSize,
                label: "Generations",
                enableMIDI: midiProgress
            )
            : nil

        if restoredCount > 0 {
            let msg = "Resume: skipping \(restoredCount) finished generation(s) from \(outputRoot)/\(BatchResumeStore.stateDirectoryName)/"
            if verbose {
                print(msg)
            } else if let progressHandle {
                Task { await progressHandle.postMessage(msg) }
            } else {
                StderrGate.writeLine("ℹ️  \(msg)")
            }
        }

        if showProgress && TerminalProgress.isInteractive {
            let startMsg = "🚀 Starting \(pendingGenerations) generations (\(poolSize) cloud workers)…"
            if let progressHandle {
                Task { await progressHandle.postMessage(startMsg) }
            } else {
                StderrGate.writeLine(startMsg)
            }
        }
        if candidates > 1 || fitOptimize {
            let batchHint =
                "ℹ️  Batch: one `/api/generate` per lyric line; POS+OED prompts; global fit scoring" +
                (fitOptimize ? "; --fit-optimize hill-climbs weak lines" : "") +
                "; checkpoints under .yankovinator/ and .parody.txt as candidates finish."
            if progressHandle != nil {
                Task { await progressHandle?.postMessage(batchHint) }
            } else {
                StderrGate.writeLine(batchHint)
            }
        }

        let useTUIStatus = progressHandle != nil
        let skipLLMCoherence = true
        let batchRefinementPasses = 0
        let enableCoherenceRegeneration = false
        let checkpoint = BatchOutputCheckpoint()
        let scoredNew: [ScoredExpansion]
        if pendingExpanded.isEmpty {
            scoredNew = []
        } else {
            scoredNew = try await ParallelJobRunner.map(
            items: pendingExpanded,
            workers: rx.effectiveWorkers,
            showProgress: showProgress,
            progressLabel: "Generations",
            ollamaNumParallel: serverParallel,
            progressHandle: progressHandle,
            enableMIDIProgress: midiProgress,
            model: model,
            applyCloudPrescription: false,
            progress: { completed, total in
                if verbose {
                    if useTUIStatus {
                        Task { await progressHandle?.postMessage("completed \(completed)/\(total)") }
                    } else {
                        Task { await log.printLine("Generations completed: \(completed)/\(total)") }
                    }
                }
            }
        ) { item in
            guard let lyrics = lyricsByPath[item.job.lyricsPath] else {
                throw ValidationError("Missing preloaded lyrics for \(item.job.lyricsPath)")
            }
            let keywordsDict: [String: String]
            if let keywordsPath = item.job.keywordsPath {
                guard let cached = keywordsByPath[keywordsPath] else {
                    throw ValidationError("Missing preloaded keywords for \(keywordsPath)")
                }
                keywordsDict = cached
            } else {
                keywordsDict = defaultKeywords
            }

            if analyze && item.candidateIndex == 1 {
                let msg = "[\(item.job.id)] syllable analysis (\(lyrics.filter { !$0.isEmpty }.count) non-empty lines)"
                if useTUIStatus {
                    await progressHandle?.postMessage(msg)
                } else {
                    await log.printLine(msg)
                }
            }

            if verbose {
                let msg = "[\(item.job.id)#c\(item.candidateIndex)] generating…"
                if useTUIStatus {
                    await progressHandle?.postMessage(msg)
                } else {
                    await log.printLine(msg)
                }
            }

            let generator = ParodyGenerator(
                ollamaBaseURL: ollamaURL,
                ollamaModel: model,
                useDictionary: true,
                useUnsupervisedNLP: false,
                skipLLMCoherenceCritic: skipLLMCoherence
            )
            let parodyLines = try await generator.generateParody(
                originalLyrics: lyrics,
                keywords: keywordsDict,
                progressCallback: { line, total in
                    guard useTUIStatus, let ctx = WorkerJobContext.current else { return }
                    Task {
                        await progressHandle?.postWorkerLineProgress(
                            workerID: ctx.workerID,
                            line: line,
                            total: total
                        )
                    }
                },
                refinementPasses: batchRefinementPasses,
                enableCoherenceRegeneration: enableCoherenceRegeneration,
                optimizeFit: fitOptimize,
                fitTargetScore: ParodyFitScore.defaultCorrectnessThreshold,
                maxFitAttemptsPerLine: fitOptimize ? 2 : 0,
                fitPolishRounds: fitOptimize ? 1 : 0,
                verbose: verbose
            )
            let score = CandidateParodyGenerator.scoreParody(
                lines: parodyLines,
                keywords: keywordsDict,
                originalLyrics: lyrics,
                dictionary: OEDDictionary.shared
            )
            let result = ParodyCandidateResult(index: item.candidateIndex, lines: parodyLines, score: score)

            try await resumeStore.record(job: item.job, result: result)

            if candidates > 1 {
                try await checkpoint.consider(job: item.job, result: result) { message in
                    if useTUIStatus {
                        Task { await progressHandle?.postMessage(message) }
                    } else if verbose {
                        Task { await log.printLine(message) }
                    }
                }
            }

            if verbose {
                let fit = ParodyFitScorer.scoreSong(
                    originalLyrics: lyrics,
                    parodyLines: parodyLines,
                    keywords: keywordsDict,
                    dictionary: OEDDictionary.shared
                )
                let msg =
                    "[\(item.job.id)#c\(item.candidateIndex)] score=\(String(format: "%.3f", score)) " +
                    "minLine=\(String(format: "%.3f", fit.minComposite)) allFit=\(fit.allFit)"
                if useTUIStatus {
                    await progressHandle?.postMessage(msg)
                } else {
                    await log.printLine(msg)
                }
            }

            return ScoredExpansion(job: item.job, result: result)
        }
        }

        let scored = scoredPreloaded + scoredNew

        // Group by job id, pick best candidate, write outputs.
        var byJob: [String: [ScoredExpansion]] = [:]
        for item in scored {
            byJob[item.job.id, default: []].append(item)
        }

        var outcomes: [(id: String, outputPath: String, score: Double)] = []
        for job in jobs {
            guard let group = byJob[job.id], !group.isEmpty else { continue }
            let ranked = group.map(\.result).sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            guard let best = ranked.first else { continue }

            try best.text.write(toFile: job.outputPath, atomically: true, encoding: .utf8)
            if keepCandidates && candidates > 1 {
                try Self.writeCandidateBundle(best: best, all: ranked, outputPath: job.outputPath)
            }
            if verbose {
                await log.printLine("[\(job.id)] best=c\(best.index) score=\(String(format: "%.3f", best.score)) → \(job.outputPath)")
            }
            outcomes.append((id: job.id, outputPath: job.outputPath, score: best.score))
        }

        print("Completed \(outcomes.count) base job(s) / \(generations) generation(s) with \(workers) worker(s) (\(label)).")
        for outcome in outcomes.prefix(50) {
            print("  \(outcome.id): \(outcome.outputPath) (score=\(String(format: "%.3f", outcome.score)))")
        }
        if outcomes.count > 50 {
            print("  … and \(outcomes.count - 50) more")
        }
    }

    private static func writeCandidateBundle(
        best: ParodyCandidateResult,
        all: [ParodyCandidateResult],
        outputPath: String
    ) throws {
        let fm = FileManager.default
        let parent = (outputPath as NSString).deletingLastPathComponent
        let stem = ((outputPath as NSString).lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: ".parody", with: "")
        let dir = (parent as NSString).appendingPathComponent("\(stem).candidates")
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var scoreLines: [String] = ["# ranked candidates (best first)", "best: c\(String(format: "%02d", best.index)) score=\(String(format: "%.6f", best.score))"]
        for item in all {
            let name = String(format: "c%02d.parody.txt", item.index)
            let path = (dir as NSString).appendingPathComponent(name)
            try item.text.write(toFile: path, atomically: true, encoding: .utf8)
            let marker = item.index == best.index ? "BEST" : "    "
            scoreLines.append("\(marker) \(name) score=\(String(format: "%.6f", item.score))")
        }
        try scoreLines.joined(separator: "\n").write(
            toFile: (dir as NSString).appendingPathComponent("scores.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Shared helpers

    private static func loadKeywordsFileStatic(
        path: String,
        verbose: Bool = false
    ) throws -> [String: String] {
        guard let keywordsContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ValidationError("Could not read keywords file: \(path)")
        }

        let keywordsDict = ParodyGenerator.parseKeywords(from: keywordsContent)
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
                OllamaClient.markModelVerified(baseURL: ollamaURL, model: model)
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
        } else {
            OllamaClient.markModelVerified(baseURL: ollamaURL, model: model)
        }

        if verbose {
            print("Ollama connection successful!")
            print("")
        }
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

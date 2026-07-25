// Copyright (C) 2025, Shyamal Suhana Chandra
// Bounded parallel job execution for concurrent Ollama workloads

import Foundation

/// Runs independent async jobs with a capped number of concurrent workers.
///
/// Use this for multi-song / multi-iteration workloads against a local or cloud
/// Ollama endpoint. Intra-song line generation stays sequential (rhyme/context).
public enum ParallelJobRunner {
    /// Default concurrency (sequential).
    public static let defaultWorkers = 1

    /// Suggested worker count for cloud Ollama batch runs.
    public static let recommendedCloudWorkers = 10

    /// Hard upper bound for CLI `--workers` (queue can hold more; consumers stay capped).
    public static let maxWorkers = 32

    /// Maximum concurrent consumer workers (producer-consumer pool size).
    public static let maxConcurrentConsumers = 10

    /// Effective consumer count: at most `maxConcurrentConsumers` workers run at once.
    /// When `ollamaNumParallel` is set (Ollama server `OLLAMA_NUM_PARALLEL`), consumers are capped to match.
    public static func consumerPoolSize(
        requestedWorkers: Int,
        ollamaNumParallel: Int? = nil,
        model: String? = nil,
        applyCloudPrescription: Bool = true
    ) -> Int {
        var requested = clampWorkers(requestedWorkers)
        if applyCloudPrescription, let model, CloudBatchPrescription.isHeavyCloudModel(model) {
            requested = min(requested, CloudBatchPrescription.heavyCloudMaxConsumers)
        }
        let base = min(requested, maxConcurrentConsumers)
        guard let ollamaNumParallel, ollamaNumParallel >= 1 else { return base }
        return min(base, ollamaNumParallel)
    }

    /// True when the Ollama base URL points at this machine (server env vars apply).
    public static func isLocalOllamaHost(_ baseURL: String) -> Bool {
        let lower = baseURL.lowercased()
        return lower.contains("localhost")
            || lower.contains("127.0.0.1")
            || lower.hasPrefix("http://127.")
            || lower.hasPrefix("https://127.")
    }

    /// Effective generation counts (songs × themes × candidates) above this require `--force`.
    public static let crossProductForceThreshold = 100

    /// Clamp a requested worker count into `[1, maxWorkers]`.
    public static func clampWorkers(_ requested: Int) -> Int {
        max(1, min(requested, maxWorkers))
    }

    /// Validate a CLI-facing worker count.
    /// - Throws: `ParallelJobError.invalidWorkerCount` when out of range.
    public static func validateWorkers(_ requested: Int) throws {
        guard requested >= 1, requested <= maxWorkers else {
            throw ParallelJobError.invalidWorkerCount(requested, max: maxWorkers)
        }
    }

    /// Map `items` through `operation` using a producer-consumer queue.
    ///
    /// - Producer: enqueues all items in order.
    /// - Consumers: fixed pool of size `consumerPoolSize(workers)` (max 10) pulls jobs concurrently.
    /// - Results preserve input order.
    public static func map<Item: Sendable, Result: Sendable>(
        items: [Item],
        workers: Int,
        showProgress: Bool = false,
        progressLabel: String = "Jobs",
        ollamaNumParallel: Int? = nil,
        progressHandle: CLIWorkerPoolProgress? = nil,
        enableMIDIProgress: Bool = false,
        model: String? = nil,
        applyCloudPrescription: Bool = true,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        operation: @escaping @Sendable (Item) async throws -> Result
    ) async throws -> [Result] {
        guard !items.isEmpty else { return [] }

        let poolSize = consumerPoolSize(
            requestedWorkers: workers,
            ollamaNumParallel: ollamaNumParallel,
            model: model,
            applyCloudPrescription: applyCloudPrescription
        )
        let showUI = showProgress && TerminalProgress.isInteractive && items.count > 1
        let simpleBar: CLIProgressBar? = (showUI && poolSize == 1)
            ? CLIProgressBar(total: items.count, label: progressLabel, enableMIDI: enableMIDIProgress)
            : nil
        let workerPool: CLIWorkerPoolProgress?
        if showUI && poolSize > 1 {
            workerPool = progressHandle ?? CLIWorkerPoolProgress(
                total: items.count,
                workerCount: poolSize,
                label: progressLabel,
                enableMIDI: enableMIDIProgress
            )
        } else {
            workerPool = progressHandle
        }

        if poolSize == 1 || items.count == 1 {
            var results: [Result] = []
            results.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                results.append(try await operation(item))
                progress?(index + 1, items.count)
                if let simpleBar { await simpleBar.advance() }
            }
            if let simpleBar { await simpleBar.finish() }
            return results
        }

        return try await mapProducerConsumer(
            items: items,
            consumerCount: poolSize,
            workerPool: workerPool,
            progress: progress,
            operation: operation
        )
    }

    /// Producer-consumer executor (OS-style bounded worker pool).
    private static func mapProducerConsumer<Item: Sendable, Result: Sendable>(
        items: [Item],
        consumerCount: Int,
        workerPool: CLIWorkerPoolProgress?,
        progress: (@Sendable (Int, Int) -> Void)?,
        operation: @escaping @Sendable (Item) async throws -> Result
    ) async throws -> [Result] {
        let store = OrderedResultStore<Result>(capacity: items.count)
        let counter = CompletionCounter(total: items.count)

        let (stream, continuation) = AsyncStream<(Int, Item)>.makeStream()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for (index, item) in items.enumerated() {
                    continuation.yield((index, item))
                }
                continuation.finish()
            }

            for workerID in 0..<consumerCount {
                group.addTask {
                    for await (index, item) in stream {
                        if let workerPool {
                            await workerPool.beginJob(workerID: workerID, jobNumber: index + 1)
                            await workerPool.postMessage("W\(String(format: "%02d", workerID + 1)) → job #\(index + 1)")
                        }
                        let value = try await WorkerJobContext.$current.withValue(
                            WorkerJobContext.State(workerID: workerID, jobNumber: index + 1)
                        ) {
                            try await operation(item)
                        }
                        await store.put(index: index, value: value)
                        let (done, total) = await counter.increment()
                        progress?(done, total)
                        if let workerPool {
                            await workerPool.postMessage("done \(done)/\(total)")
                            await workerPool.completeJob(workerID: workerID)
                        }
                    }
                }
            }

            try await group.waitForAll()
        }

        if let workerPool {
            await workerPool.finish()
        }
        return try await store.orderedResults()
    }
}

// MARK: - Producer-consumer helpers

private actor OrderedResultStore<Result: Sendable> {
    private var slots: [Result?]

    init(capacity: Int) {
        slots = Array(repeating: nil, count: capacity)
    }

    func put(index: Int, value: Result) {
        slots[index] = value
    }

    func orderedResults() throws -> [Result] {
        try slots.enumerated().map { offset, value in
            guard let value else {
                throw ParallelJobError.missingProducerConsumerResult(index: offset)
            }
            return value
        }
    }
}

private actor CompletionCounter {
    private var completed = 0
    let total: Int

    init(total: Int) {
        self.total = total
    }

    func increment() -> (Int, Int) {
        completed += 1
        return (completed, total)
    }
}

// MARK: - Ollama server parallelism (OLLAMA_NUM_PARALLEL)

/// Aligns client worker pools with Ollama server parallelism (see https://docs.ollama.com/faq).
public enum OllamaParallelPolicy {
    /// Reads `OLLAMA_NUM_PARALLEL` from the environment (must be set before starting `ollama serve`).
    public static func serverNumParallelFromEnvironment() -> Int? {
        guard let raw = ProcessInfo.processInfo.environment["OLLAMA_NUM_PARALLEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let value = Int(raw),
            value >= 1
        else { return nil }
        return value
    }

    /// Suggested value for `OLLAMA_NUM_PARALLEL` on the server for a given `--workers` request.
    public static func recommendedServerNumParallel(requestedWorkers: Int) -> Int {
        ParallelJobRunner.consumerPoolSize(requestedWorkers: requestedWorkers, ollamaNumParallel: nil)
    }

    /// Print setup guidance when local Ollama may queue excess parallel requests (default server parallel is often 1).
    public static func printServerParallelHintIfNeeded(
        baseURL: String,
        requestedWorkers: Int,
        ollamaNumParallel: Int?,
        verbose: Bool
    ) {
        guard ParallelJobRunner.isLocalOllamaHost(baseURL), requestedWorkers > 1 else { return }
        let pool = ParallelJobRunner.consumerPoolSize(
            requestedWorkers: requestedWorkers,
            ollamaNumParallel: ollamaNumParallel
        )
        let recommended = recommendedServerNumParallel(requestedWorkers: requestedWorkers)

        if let ollamaNumParallel {
            if pool < recommended && (verbose || requestedWorkers > 1) {
                fputs(
                    """
                    ⚠️  OLLAMA_NUM_PARALLEL=\(ollamaNumParallel) caps consumers at \(pool) \
                    (requested pool without cap: \(recommended)). \
                    Increase server parallelism or lower --workers. See https://docs.ollama.com/faq

                    """,
                    stderr
                )
            }
            return
        }

        fputs(
            """
            ℹ️  For \(recommended) parallel client workers, start Ollama with \
            OLLAMA_NUM_PARALLEL=\(recommended) (then restart `ollama serve`). \
            See https://docs.ollama.com/faq — RAM ∝ OLLAMA_NUM_PARALLEL × context length.

            """,
            stderr
        )
    }
}

/// Errors from parallel job configuration / discovery.
public enum ParallelJobError: Error, CustomStringConvertible, Sendable {
    case invalidWorkerCount(Int, max: Int)
    case invalidCandidateCount(Int, max: Int)
    case emptyInputDirectory(String)
    case emptyThemesDirectory(String)
    case missingOutputDirectory
    case cannotCreateOutputDirectory(String)
    case crossProductRequiresForce(songCount: Int, themeCount: Int, candidates: Int, total: Int, threshold: Int)
    case noCandidatesProduced
    case missingProducerConsumerResult(index: Int)

    public var description: String {
        switch self {
        case .invalidWorkerCount(let requested, let max):
            return "Workers must be between 1 and \(max) (got \(requested)). Concurrent consumers are capped at \(ParallelJobRunner.maxConcurrentConsumers) (producer-consumer queue)."
        case .invalidCandidateCount(let requested, let max):
            return "Candidates must be between 1 and \(max) (got \(requested)). For combinatorial ranking, try --candidates \(CandidateParodyGenerator.recommendedCandidates)."
        case .emptyInputDirectory(let path):
            return "No .txt lyrics files found in input directory: \(path)"
        case .emptyThemesDirectory(let path):
            return "No .txt theme/keyword files found in themes directory: \(path)"
        case .missingOutputDirectory:
            return "--output-dir is required for batch jobs (--input-dir and/or --themes-dir)."
        case .cannotCreateOutputDirectory(let path):
            return "Could not create output directory: \(path)"
        case .crossProductRequiresForce(let songCount, let themeCount, let candidates, let total, let threshold):
            return """
            Combinatorial batch would create \(total) generations (\(songCount) songs × \(themeCount) themes × \(candidates) candidates), which exceeds the safety threshold of \(threshold).
            Re-run with --force if you really want that explosion.
            """
        case .noCandidatesProduced:
            return "No parody candidates were produced."
        case .missingProducerConsumerResult(let index):
            return "Internal error: missing result for queued job at index \(index)."
        }
    }
}

/// One lyrics → parody batch job for parallel processing.
public struct ParodyBatchJob: Sendable {
    public let id: String
    public let songId: String
    public let themeId: String?
    public let lyricsPath: String
    /// Theme keywords file for this job. `nil` means use the shared CLI `--keywords` / default theme.
    public let keywordsPath: String?
    public let outputPath: String

    public init(
        id: String,
        songId: String,
        themeId: String? = nil,
        lyricsPath: String,
        keywordsPath: String? = nil,
        outputPath: String
    ) {
        self.id = id
        self.songId = songId
        self.themeId = themeId
        self.lyricsPath = lyricsPath
        self.keywordsPath = keywordsPath
        self.outputPath = outputPath
    }
}

/// Async-safe logger for parallel worker progress lines.
public actor JobLog {
    public init() {}

    public func printLine(_ message: String) {
        print(message)
    }
}

/// Discovers parody batch jobs from lyrics (and optional theme) directories.
public enum ParodyBatchJobBuilder {
    /// Build jobs from `*.txt` lyrics in `inputDir` with one shared theme.
    ///
    /// Output files are named `<song>.parody.txt`.
    public static func jobs(
        inputDir: String,
        outputDir: String
    ) throws -> [ParodyBatchJob] {
        try ensureDirectory(outputDir)
        let songs = try listTxtFiles(in: inputDir, emptyError: .emptyInputDirectory(inputDir))

        return songs.map { song in
            let outputPath = (outputDir as NSString).appendingPathComponent("\(song.stem).parody.txt")
            return ParodyBatchJob(
                id: song.stem,
                songId: song.stem,
                themeId: nil,
                lyricsPath: song.path,
                keywordsPath: nil,
                outputPath: outputPath
            )
        }
    }

    /// Build the cartesian product of lyrics files × theme keyword files.
    ///
    /// Outputs are nested as `<outputDir>/<theme>/<song>.parody.txt`.
    ///
    /// - Parameters:
    ///   - inputDir: Directory of song `.txt` files.
    ///   - themesDir: Directory of theme keyword `.txt` files (`keyword: definition`).
    ///   - outputDir: Root output directory.
    ///   - force: Required when `songs × themes` exceeds `ParallelJobRunner.crossProductForceThreshold`.
    public static func crossProductJobs(
        inputDir: String,
        themesDir: String,
        outputDir: String,
        force: Bool = false
    ) throws -> [ParodyBatchJob] {
        try ensureDirectory(outputDir)
        let songs = try listTxtFiles(in: inputDir, emptyError: .emptyInputDirectory(inputDir))
        let themes = try listTxtFiles(in: themesDir, emptyError: .emptyThemesDirectory(themesDir))

        let total = songs.count * themes.count
        if total > ParallelJobRunner.crossProductForceThreshold && !force {
            throw ParallelJobError.crossProductRequiresForce(
                songCount: songs.count,
                themeCount: themes.count,
                candidates: 1,
                total: total,
                threshold: ParallelJobRunner.crossProductForceThreshold
            )
        }

        var jobs: [ParodyBatchJob] = []
        jobs.reserveCapacity(total)

        for theme in themes {
            let themeOutDir = (outputDir as NSString).appendingPathComponent(theme.stem)
            try ensureDirectory(themeOutDir)

            for song in songs {
                let outputPath = (themeOutDir as NSString).appendingPathComponent("\(song.stem).parody.txt")
                jobs.append(
                    ParodyBatchJob(
                        id: "\(song.stem)×\(theme.stem)",
                        songId: song.stem,
                        themeId: theme.stem,
                        lyricsPath: song.path,
                        keywordsPath: theme.path,
                        outputPath: outputPath
                    )
                )
            }
        }

        return jobs
    }

    /// Build jobs for one lyrics file against every theme in `themesDir`.
    public static func jobs(
        lyricsPath: String,
        themesDir: String,
        outputDir: String,
        force: Bool = false
    ) throws -> [ParodyBatchJob] {
        try ensureDirectory(outputDir)
        let themes = try listTxtFiles(in: themesDir, emptyError: .emptyThemesDirectory(themesDir))
        let songStem = ((lyricsPath as NSString).lastPathComponent as NSString).deletingPathExtension

        let total = themes.count
        if total > ParallelJobRunner.crossProductForceThreshold && !force {
            throw ParallelJobError.crossProductRequiresForce(
                songCount: 1,
                themeCount: themes.count,
                candidates: 1,
                total: total,
                threshold: ParallelJobRunner.crossProductForceThreshold
            )
        }

        var jobs: [ParodyBatchJob] = []
        jobs.reserveCapacity(themes.count)
        for theme in themes {
            let themeOutDir = (outputDir as NSString).appendingPathComponent(theme.stem)
            try ensureDirectory(themeOutDir)
            let outputPath = (themeOutDir as NSString).appendingPathComponent("\(songStem).parody.txt")
            jobs.append(
                ParodyBatchJob(
                    id: "\(songStem)×\(theme.stem)",
                    songId: songStem,
                    themeId: theme.stem,
                    lyricsPath: lyricsPath,
                    keywordsPath: theme.path,
                    outputPath: outputPath
                )
            )
        }
        return jobs
    }

    // MARK: - Helpers

    private struct TxtFile {
        let stem: String
        let path: String
    }

    private static func listTxtFiles(in directory: String, emptyError: ParallelJobError) throws -> [TxtFile] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw emptyError
        }

        let contents = try fm.contentsOfDirectory(atPath: directory)
        let files = contents
            .filter { $0.lowercased().hasSuffix(".txt") && !$0.hasPrefix(".") }
            .sorted()
            .map { filename -> TxtFile in
                let stem = (filename as NSString).deletingPathExtension
                let path = (directory as NSString).appendingPathComponent(filename)
                return TxtFile(stem: stem, path: path)
            }

        guard !files.isEmpty else { throw emptyError }
        return files
    }

    private static func ensureDirectory(_ path: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return }
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw ParallelJobError.cannotCreateOutputDirectory(path)
        }
    }
}

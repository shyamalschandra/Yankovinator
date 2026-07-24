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

    /// Hard upper bound to avoid overwhelming remote hosts.
    public static let maxWorkers = 32

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

    /// Map `items` through `operation` with at most `workers` concurrent tasks.
    /// Results are returned in the same order as `items`.
    ///
    /// - Parameters:
    ///   - items: Work items (each item is one independent job).
    ///   - workers: Maximum concurrent jobs (clamped to `maxWorkers`).
    ///   - progress: Optional callback `(completed, total)` after each job finishes.
    ///   - operation: Async work for a single item.
    public static func map<Item: Sendable, Result: Sendable>(
        items: [Item],
        workers: Int,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        operation: @escaping @Sendable (Item) async throws -> Result
    ) async throws -> [Result] {
        let workerCount = clampWorkers(workers)
        guard !items.isEmpty else { return [] }

        if workerCount == 1 || items.count == 1 {
            var results: [Result] = []
            results.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                results.append(try await operation(item))
                progress?(index + 1, items.count)
            }
            return results
        }

        return try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var nextIndex = 0
            var results = Array<Result?>(repeating: nil, count: items.count)
            var completed = 0

            func enqueue() {
                while nextIndex < items.count && nextIndex < completed + workerCount {
                    let index = nextIndex
                    let item = items[index]
                    nextIndex += 1
                    group.addTask {
                        let value = try await operation(item)
                        return (index, value)
                    }
                }
            }

            enqueue()

            for try await (index, value) in group {
                results[index] = value
                completed += 1
                progress?(completed, items.count)
                enqueue()
            }

            return results.map { result in
                guard let result else {
                    preconditionFailure("ParallelJobRunner missing result slot")
                }
                return result
            }
        }
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

    public var description: String {
        switch self {
        case .invalidWorkerCount(let requested, let max):
            return "Workers must be between 1 and \(max) (got \(requested)). For cloud Ollama batch jobs, try --workers \(ParallelJobRunner.recommendedCloudWorkers)."
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

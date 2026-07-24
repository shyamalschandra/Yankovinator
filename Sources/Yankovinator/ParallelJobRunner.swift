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
    case emptyInputDirectory(String)
    case missingOutputDirectory
    case cannotCreateOutputDirectory(String)

    public var description: String {
        switch self {
        case .invalidWorkerCount(let requested, let max):
            return "Workers must be between 1 and \(max) (got \(requested)). For cloud Ollama batch jobs, try --workers \(ParallelJobRunner.recommendedCloudWorkers)."
        case .emptyInputDirectory(let path):
            return "No .txt lyrics files found in input directory: \(path)"
        case .missingOutputDirectory:
            return "--output-dir is required when using --input-dir for parallel batch jobs."
        case .cannotCreateOutputDirectory(let path):
            return "Could not create output directory: \(path)"
        }
    }
}

/// One lyrics → parody batch job for parallel processing.
public struct ParodyBatchJob: Sendable {
    public let id: String
    public let lyricsPath: String
    public let outputPath: String

    public init(id: String, lyricsPath: String, outputPath: String) {
        self.id = id
        self.lyricsPath = lyricsPath
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

/// Discovers parody batch jobs from a directory of lyrics files.
public enum ParodyBatchJobBuilder {
    /// Build jobs from `*.txt` files in `inputDir`, writing to `outputDir`.
    ///
    /// Output files are named `<stem>.parody.txt`.
    public static func jobs(
        inputDir: String,
        outputDir: String
    ) throws -> [ParodyBatchJob] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: inputDir, isDirectory: &isDir), isDir.boolValue else {
            throw ParallelJobError.emptyInputDirectory(inputDir)
        }

        if !fm.fileExists(atPath: outputDir) {
            do {
                try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            } catch {
                throw ParallelJobError.cannotCreateOutputDirectory(outputDir)
            }
        }

        let contents = try fm.contentsOfDirectory(atPath: inputDir)
        let lyricsFiles = contents
            .filter { $0.lowercased().hasSuffix(".txt") && !$0.hasPrefix(".") }
            .sorted()

        guard !lyricsFiles.isEmpty else {
            throw ParallelJobError.emptyInputDirectory(inputDir)
        }

        return lyricsFiles.map { filename in
            let stem = (filename as NSString).deletingPathExtension
            let lyricsPath = (inputDir as NSString).appendingPathComponent(filename)
            let outputPath = (outputDir as NSString).appendingPathComponent("\(stem).parody.txt")
            return ParodyBatchJob(id: stem, lyricsPath: lyricsPath, outputPath: outputPath)
        }
    }
}

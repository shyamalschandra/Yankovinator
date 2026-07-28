// Copyright (C) 2025, Shyamal Suhana Chandra
// Durable batch resume checkpoints under <output-dir>/.yankovinator/
//
// Disk is the source of truth: append-only completed.jsonl + per-candidate files.
// In-memory state holds completion keys + score/path metadata only; candidate
// texts are paged in lazily through a bounded LRU cache.

import CryptoKit
import Foundation

public struct BatchResumeUnitKey: Hashable, Sendable, Codable {
    public let jobID: String
    public let candidateIndex: Int

    public init(jobID: String, candidateIndex: Int) {
        self.jobID = jobID
        self.candidateIndex = candidateIndex
    }
}

public struct BatchResumeManifest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var model: String
    public var candidates: Int
    public var jobsFingerprint: String
    public var startedAt: Date
    public var updatedAt: Date

    public init(model: String, candidates: Int, jobsFingerprint: String, startedAt: Date = Date(), updatedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.model = model
        self.candidates = candidates
        self.jobsFingerprint = jobsFingerprint
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public struct BatchResumeRecord: Codable, Sendable, Equatable {
    public let jobID: String
    public let candidateIndex: Int
    public let score: Double
    public let artifactRelativePath: String
    public let outputPath: String
    public let finishedAt: Date
}

/// Lightweight score index for ranking without loading candidate text.
public struct BatchResumeCandidateSummary: Sendable, Equatable {
    public let jobID: String
    public let candidateIndex: Int
    public let score: Double

    public init(jobID: String, candidateIndex: Int, score: Double) {
        self.jobID = jobID
        self.candidateIndex = candidateIndex
        self.score = score
    }
}

/// Append-only JSONL log + per-candidate artifacts for resuming interrupted batches.
public actor BatchResumeStore {
    public static let stateDirectoryName = ".yankovinator"
    public static let manifestFileName = "manifest.json"
    public static let logFileName = "completed.jsonl"
    /// Default bound on in-memory candidate texts (scores/keys are unbounded but tiny).
    public static let defaultTextCacheLimit = 16
    private static let jsonlReadChunkBytes = 64 * 1024

    private let rootURL: URL
    private let candidatesURL: URL
    private let manifestURL: URL
    private let logURL: URL
    private let textCacheLimit: Int
    private var manifest: BatchResumeManifest
    private var completedKeys: Set<BatchResumeUnitKey> = []
    /// Score + path metadata only — never the full parody text.
    private var recordsByKey: [BatchResumeUnitKey: BatchResumeRecord] = [:]
    private var textCache: [BatchResumeUnitKey: ParodyCandidateResult] = [:]
    private var textCacheOrder: [BatchResumeUnitKey] = []
    /// Manifest rewrite cadence (JSONL is the completion source of truth).
    private var recordsSinceManifestFlush = 0
    private static let manifestFlushEvery = 8

    public init(
        outputRoot: String,
        manifest: BatchResumeManifest,
        fresh: Bool,
        textCacheLimit: Int = BatchResumeStore.defaultTextCacheLimit
    ) throws {
        let root = URL(fileURLWithPath: outputRoot, isDirectory: true)
            .appendingPathComponent(Self.stateDirectoryName, isDirectory: true)
        self.rootURL = root
        self.candidatesURL = root.appendingPathComponent("candidates", isDirectory: true)
        self.manifestURL = root.appendingPathComponent(Self.manifestFileName)
        self.logURL = root.appendingPathComponent(Self.logFileName)
        self.manifest = manifest
        self.textCacheLimit = max(0, textCacheLimit)

        let fm = FileManager.default
        if fresh, fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
        try fm.createDirectory(at: candidatesURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: manifestURL.path) {
            let loaded = try Self.loadCheckpointMetadata(
                manifestURL: manifestURL,
                logURL: logURL,
                expected: manifest
            )
            self.manifest = loaded.manifest
            self.completedKeys = loaded.completedKeys
            self.recordsByKey = loaded.recordsByKey
        } else {
            try Self.writeManifestFile(manifest, to: manifestURL)
        }
    }

    private struct LoadedCheckpoint {
        var manifest: BatchResumeManifest
        var completedKeys: Set<BatchResumeUnitKey>
        var recordsByKey: [BatchResumeUnitKey: BatchResumeRecord]
    }

    /// Stream `completed.jsonl` for keys + scores only — does not read candidate text files.
    private static func loadCheckpointMetadata(
        manifestURL: URL,
        logURL: URL,
        expected: BatchResumeManifest
    ) throws -> LoadedCheckpoint {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let onDisk = try decoder.decode(BatchResumeManifest.self, from: data)
        guard onDisk.version == BatchResumeManifest.currentVersion,
              onDisk.jobsFingerprint == expected.jobsFingerprint,
              onDisk.candidates == expected.candidates,
              onDisk.model == expected.model
        else {
            throw BatchResumeError.manifestMismatch(
                expectedFingerprint: expected.jobsFingerprint,
                foundFingerprint: onDisk.jobsFingerprint
            )
        }
        var completedKeys: Set<BatchResumeUnitKey> = []
        var recordsByKey: [BatchResumeUnitKey: BatchResumeRecord] = [:]
        if FileManager.default.fileExists(atPath: logURL.path) {
            let lineDecoder = JSONDecoder()
            lineDecoder.dateDecodingStrategy = .iso8601
            try Self.forEachJSONLRecord(at: logURL) { lineData in
                let record = try lineDecoder.decode(BatchResumeRecord.self, from: lineData)
                let key = BatchResumeUnitKey(jobID: record.jobID, candidateIndex: record.candidateIndex)
                completedKeys.insert(key)
                recordsByKey[key] = record
            }
        }
        return LoadedCheckpoint(manifest: onDisk, completedKeys: completedKeys, recordsByKey: recordsByKey)
    }

    /// Append-friendly streaming reader: pages the log in chunks without loading the whole file as one String.
    private static func forEachJSONLRecord(at url: URL, body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: jsonlReadChunkBytes) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                if !lineData.isEmpty {
                    try body(lineData)
                }
            }
        }
        if !buffer.isEmpty {
            try body(buffer)
        }
    }

    private static func writeManifestFile(_ manifest: BatchResumeManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    public static func jobsFingerprint(jobs: [ParodyBatchJob], candidates: Int, model: String) -> String {
        let body = jobs.map { "\($0.id)\t\($0.outputPath)\t\($0.lyricsPath)" }.sorted().joined(separator: "\n")
        let payload = "v\(BatchResumeManifest.currentVersion)\nmodel:\(model)\ncandidates:\(candidates)\n\(body)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func isComplete(jobID: String, candidateIndex: Int) -> Bool {
        completedKeys.contains(BatchResumeUnitKey(jobID: jobID, candidateIndex: candidateIndex))
    }

    /// Number of completed generations known from the on-disk JSONL index (keys only).
    public var restoredCount: Int {
        completedKeys.count
    }

    /// How many full candidate texts are currently held in the LRU page cache.
    public var cachedTextCount: Int {
        textCache.count
    }

    public var textCacheCapacity: Int {
        textCacheLimit
    }

    public func score(jobID: String, candidateIndex: Int) -> Double? {
        recordsByKey[BatchResumeUnitKey(jobID: jobID, candidateIndex: candidateIndex)]?.score
    }

    /// Score metadata for one job, ordered by candidate index — no text I/O.
    public func candidateSummaries(jobID: String) -> [BatchResumeCandidateSummary] {
        recordsByKey.values
            .filter { $0.jobID == jobID }
            .sorted { $0.candidateIndex < $1.candidateIndex }
            .map {
                BatchResumeCandidateSummary(
                    jobID: $0.jobID,
                    candidateIndex: $0.candidateIndex,
                    score: $0.score
                )
            }
    }

    /// Pick the best candidate for a job using on-disk scores, then page in only that text.
    public func bestResult(jobID: String) throws -> ParodyCandidateResult? {
        let summaries = candidateSummaries(jobID: jobID)
        guard let best = summaries.max(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.candidateIndex > rhs.candidateIndex
        }) else {
            return nil
        }
        return try loadResult(jobID: jobID, candidateIndex: best.candidateIndex)
    }

    /// Lazy load one candidate from its on-disk artifact (LRU-cached).
    public func restoredResult(jobID: String, candidateIndex: Int) -> ParodyCandidateResult? {
        try? loadResult(jobID: jobID, candidateIndex: candidateIndex)
    }

    public func loadResult(jobID: String, candidateIndex: Int) throws -> ParodyCandidateResult? {
        let key = BatchResumeUnitKey(jobID: jobID, candidateIndex: candidateIndex)
        if let cached = textCacheGet(key) {
            return cached
        }
        guard let record = recordsByKey[key] else { return nil }
        let artifactURL = rootURL.appendingPathComponent(record.artifactRelativePath)
        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            throw BatchResumeError.missingArtifact(path: record.artifactRelativePath)
        }
        let fileText = try String(contentsOf: artifactURL, encoding: .utf8)
        let lines = fileText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let result = ParodyCandidateResult(index: record.candidateIndex, lines: lines, score: record.score)
        textCachePut(key, result)
        return result
    }

    /// Page in every candidate for a job (for `--keep-candidates`). Prefer `exportCandidateBundle` when possible.
    public func loadAllResults(jobID: String) throws -> [ParodyCandidateResult] {
        var out: [ParodyCandidateResult] = []
        for summary in candidateSummaries(jobID: jobID) {
            if let result = try loadResult(jobID: jobID, candidateIndex: summary.candidateIndex) {
                out.append(result)
            }
        }
        return out.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
    }

    /// Copy on-disk candidate artifacts into a ranked bundle dir without buffering all texts at once.
    public func exportCandidateBundle(jobID: String, outputPath: String) throws -> ParodyCandidateResult? {
        let summaries = candidateSummaries(jobID: jobID).sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidateIndex < rhs.candidateIndex
        }
        guard let bestSummary = summaries.first else { return nil }
        guard let best = try loadResult(jobID: jobID, candidateIndex: bestSummary.candidateIndex) else {
            return nil
        }

        let fm = FileManager.default
        let parent = (outputPath as NSString).deletingLastPathComponent
        let stem = ((outputPath as NSString).lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: ".parody", with: "")
        let dir = (parent as NSString).appendingPathComponent("\(stem).candidates")
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var scoreLines: [String] = [
            "# ranked candidates (best first)",
            "best: c\(String(format: "%02d", best.index)) score=\(String(format: "%.6f", best.score))"
        ]
        for summary in summaries {
            let key = BatchResumeUnitKey(jobID: jobID, candidateIndex: summary.candidateIndex)
            guard let record = recordsByKey[key] else { continue }
            let src = rootURL.appendingPathComponent(record.artifactRelativePath)
            let name = String(format: "c%02d.parody.txt", summary.candidateIndex)
            let dest = (dir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: dest) {
                try fm.removeItem(atPath: dest)
            }
            try fm.copyItem(atPath: src.path, toPath: dest)
            let marker = summary.candidateIndex == best.index ? "BEST" : "    "
            scoreLines.append("\(marker) \(name) score=\(String(format: "%.6f", summary.score))")
        }
        try scoreLines.joined(separator: "\n").write(
            toFile: (dir as NSString).appendingPathComponent("scores.txt"),
            atomically: true,
            encoding: .utf8
        )
        return best
    }

    @discardableResult
    public func record(job: ParodyBatchJob, result: ParodyCandidateResult) throws -> BatchResumeRecord {
        let key = BatchResumeUnitKey(jobID: job.id, candidateIndex: result.index)
        guard !completedKeys.contains(key) else {
            if let existing = recordsByKey[key] {
                return existing
            }
            throw BatchResumeError.duplicateRecord(jobID: job.id, candidateIndex: result.index)
        }

        let relative = relativeArtifactPath(jobID: job.id, candidateIndex: result.index)
        let artifactURL = rootURL.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Durable page: write artifact first, then append JSONL (crash between leaves an orphan file, not a false complete).
        try result.text.write(to: artifactURL, atomically: true, encoding: .utf8)

        let record = BatchResumeRecord(
            jobID: job.id,
            candidateIndex: result.index,
            score: result.score,
            artifactRelativePath: relative,
            outputPath: job.outputPath,
            finishedAt: Date()
        )
        try appendRecordDurable(record)

        completedKeys.insert(key)
        recordsByKey[key] = record
        textCachePut(key, result)

        recordsSinceManifestFlush += 1
        if recordsSinceManifestFlush >= Self.manifestFlushEvery {
            try flushManifest()
        }
        return record
    }

    /// Force manifest `updatedAt` to disk (also called periodically from `record`).
    public func flushManifest() throws {
        manifest.updatedAt = Date()
        try Self.writeManifestFile(manifest, to: manifestURL)
        recordsSinceManifestFlush = 0
    }

    private func appendRecordDurable(_ record: BatchResumeRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard var line = String(data: data, encoding: .utf8) else {
            throw BatchResumeError.encodingFailed
        }
        line.append("\n")
        let payload = Data(line.utf8)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.synchronize()
        } else {
            try payload.write(to: logURL, options: .atomic)
        }
    }

    private func textCacheGet(_ key: BatchResumeUnitKey) -> ParodyCandidateResult? {
        guard textCacheLimit > 0, let value = textCache[key] else { return nil }
        if let idx = textCacheOrder.firstIndex(of: key) {
            textCacheOrder.remove(at: idx)
            textCacheOrder.append(key)
        }
        return value
    }

    private func textCachePut(_ key: BatchResumeUnitKey, _ value: ParodyCandidateResult) {
        guard textCacheLimit > 0 else { return }
        if textCache[key] != nil, let idx = textCacheOrder.firstIndex(of: key) {
            textCacheOrder.remove(at: idx)
        }
        textCache[key] = value
        textCacheOrder.append(key)
        while textCache.count > textCacheLimit, let evict = textCacheOrder.first {
            textCacheOrder.removeFirst()
            textCache.removeValue(forKey: evict)
        }
    }

    private func relativeArtifactPath(jobID: String, candidateIndex: Int) -> String {
        let safe = Self.safePathComponent(jobID)
        return "candidates/\(safe)/c\(String(format: "%02d", candidateIndex)).parody.txt"
    }

    public static func safePathComponent(_ jobID: String) -> String {
        let trimmed = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "×", with: "x")
        if replaced.isEmpty { return "job" }
        if replaced.count <= 120 { return replaced }
        let digest = SHA256.hash(data: Data(trimmed.utf8)).prefix(8)
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return String(replaced.prefix(80)) + "-" + suffix
    }
}

public enum BatchResumeError: Error, CustomStringConvertible {
    case manifestMismatch(expectedFingerprint: String, foundFingerprint: String)
    case duplicateRecord(jobID: String, candidateIndex: Int)
    case encodingFailed
    case missingArtifact(path: String)

    public var description: String {
        switch self {
        case .manifestMismatch(let expected, let found):
            return """
            Batch checkpoint in --output-dir does not match this run (different songs, themes, model, or --candidates).
            Expected fingerprint \(expected.prefix(12))…, found \(found.prefix(12))….
            Re-run with --fresh-batch to discard the checkpoint and start over.
            """
        case .duplicateRecord(let jobID, let index):
            return "Duplicate resume record for \(jobID) candidate \(index)."
        case .encodingFailed:
            return "Could not encode batch resume record."
        case .missingArtifact(let path):
            return "Batch checkpoint references missing candidate file: \(path)"
        }
    }
}

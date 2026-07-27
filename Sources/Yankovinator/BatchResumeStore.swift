// Copyright (C) 2025, Shyamal Suhana Chandra
// Durable batch resume checkpoints under <output-dir>/.yankovinator/

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

public struct BatchResumeRecord: Codable, Sendable {
    public let jobID: String
    public let candidateIndex: Int
    public let score: Double
    public let artifactRelativePath: String
    public let outputPath: String
    public let finishedAt: Date
}

/// Append-only JSONL log + per-candidate artifacts for resuming interrupted batches.
public actor BatchResumeStore {
    public static let stateDirectoryName = ".yankovinator"
    public static let manifestFileName = "manifest.json"
    public static let logFileName = "completed.jsonl"

    private let rootURL: URL
    private let candidatesURL: URL
    private let manifestURL: URL
    private let logURL: URL
    private var manifest: BatchResumeManifest
    private var completedKeys: Set<BatchResumeUnitKey> = []
    private var cachedResults: [BatchResumeUnitKey: ParodyCandidateResult] = [:]

    public init(outputRoot: String, manifest: BatchResumeManifest, fresh: Bool) throws {
        let root = URL(fileURLWithPath: outputRoot, isDirectory: true)
            .appendingPathComponent(Self.stateDirectoryName, isDirectory: true)
        self.rootURL = root
        self.candidatesURL = root.appendingPathComponent("candidates", isDirectory: true)
        self.manifestURL = root.appendingPathComponent(Self.manifestFileName)
        self.logURL = root.appendingPathComponent(Self.logFileName)
        self.manifest = manifest

        let fm = FileManager.default
        if fresh, fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
        try fm.createDirectory(at: candidatesURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: manifestURL.path) {
            let loaded = try Self.loadCheckpoint(
                manifestURL: manifestURL,
                logURL: logURL,
                rootURL: rootURL,
                expected: manifest
            )
            self.manifest = loaded.manifest
            self.completedKeys = loaded.completedKeys
            self.cachedResults = loaded.cachedResults
        } else {
            try Self.writeManifestFile(manifest, to: manifestURL)
        }
    }

    private struct LoadedCheckpoint {
        var manifest: BatchResumeManifest
        var completedKeys: Set<BatchResumeUnitKey>
        var cachedResults: [BatchResumeUnitKey: ParodyCandidateResult]
    }

    private static func loadCheckpoint(
        manifestURL: URL,
        logURL: URL,
        rootURL: URL,
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
        var cachedResults: [BatchResumeUnitKey: ParodyCandidateResult] = [:]
        if FileManager.default.fileExists(atPath: logURL.path) {
            let text = try String(contentsOf: logURL, encoding: .utf8)
            let lineDecoder = JSONDecoder()
            lineDecoder.dateDecodingStrategy = .iso8601
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                let record = try lineDecoder.decode(BatchResumeRecord.self, from: lineData)
                let key = BatchResumeUnitKey(jobID: record.jobID, candidateIndex: record.candidateIndex)
                completedKeys.insert(key)
                let artifactURL = rootURL.appendingPathComponent(record.artifactRelativePath)
                guard let fileText = try? String(contentsOf: artifactURL, encoding: .utf8) else { continue }
                let lines = fileText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                cachedResults[key] = ParodyCandidateResult(index: record.candidateIndex, lines: lines, score: record.score)
            }
        }
        return LoadedCheckpoint(manifest: onDisk, completedKeys: completedKeys, cachedResults: cachedResults)
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

    public func restoredResult(jobID: String, candidateIndex: Int) -> ParodyCandidateResult? {
        cachedResults[BatchResumeUnitKey(jobID: jobID, candidateIndex: candidateIndex)]
    }

    public var restoredCount: Int {
        completedKeys.count
    }

    @discardableResult
    public func record(job: ParodyBatchJob, result: ParodyCandidateResult) throws -> BatchResumeRecord {
        let key = BatchResumeUnitKey(jobID: job.id, candidateIndex: result.index)
        guard !completedKeys.contains(key) else {
            if let cached = cachedResults[key] {
                return BatchResumeRecord(
                    jobID: job.id,
                    candidateIndex: result.index,
                    score: cached.score,
                    artifactRelativePath: relativeArtifactPath(jobID: job.id, candidateIndex: result.index),
                    outputPath: job.outputPath,
                    finishedAt: Date()
                )
            }
            throw BatchResumeError.duplicateRecord(jobID: job.id, candidateIndex: result.index)
        }

        let relative = relativeArtifactPath(jobID: job.id, candidateIndex: result.index)
        let artifactURL = rootURL.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try result.text.write(to: artifactURL, atomically: true, encoding: .utf8)

        let record = BatchResumeRecord(
            jobID: job.id,
            candidateIndex: result.index,
            score: result.score,
            artifactRelativePath: relative,
            outputPath: job.outputPath,
            finishedAt: Date()
        )
        try appendRecord(record)

        completedKeys.insert(key)
        cachedResults[key] = result
        manifest.updatedAt = Date()
        try Self.writeManifestFile(manifest, to: manifestURL)
        return record
    }

    private func appendRecord(_ record: BatchResumeRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard var line = String(data: data, encoding: .utf8) else {
            throw BatchResumeError.encodingFailed
        }
        line.append("\n")
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: logURL, atomically: true, encoding: .utf8)
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
        }
    }
}

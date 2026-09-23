// Copyright (C) 2025, Shyamal Suhana Chandra
// Per-line parody checkpoints under <output-dir>/.yankovinator/lines/
//
// A batch resume record is written only after a whole song finishes. This store
// saves each completed line so an interrupted generation continues at the next line.

import CryptoKit
import Foundation

public struct ParodyLineCheckpointFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var fingerprint: String
    public var lineCount: Int
    public var lines: [String]
    public var finished: Bool

    public init(fingerprint: String, lineCount: Int, lines: [String], finished: Bool) {
        self.version = Self.currentVersion
        self.fingerprint = fingerprint
        self.lineCount = lineCount
        self.lines = lines
        self.finished = finished
    }
}

/// Durable prefix of a parody, one file per song×theme×candidate.
public actor ParodyLineCheckpointStore {
    public static let directoryName = "lines"

    private let rootURL: URL

    public init(outputRoot: String) throws {
        let root = URL(fileURLWithPath: outputRoot, isDirectory: true)
            .appendingPathComponent(BatchResumeStore.stateDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.rootURL = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Identity for a generation. A lyric, theme, model, or fit-setting change will not resume a stale prefix.
    public static func fingerprint(
        lyrics: [String],
        keywords: [String: String],
        model: String,
        refinementPasses: Int,
        enableCoherenceRegeneration: Bool,
        optimizeFit: Bool,
        fitTargetScore: Double,
        maxFitAttemptsPerLine: Int,
        fitPolishRounds: Int
    ) -> String {
        let keywordLines = keywords.keys.sorted().map { key in
            "\(key)\t\(keywords[key] ?? "")"
        }
        let payload = """
        v\(ParodyLineCheckpointFile.currentVersion)
        model:\(model)
        refinement:\(refinementPasses)
        coherenceRegen:\(enableCoherenceRegeneration)
        optimizeFit:\(optimizeFit)
        fitTarget:\(String(format: "%.6f", fitTargetScore))
        maxFitAttempts:\(maxFitAttemptsPerLine)
        fitPolishRounds:\(fitPolishRounds)
        lyrics:
        \(lyrics.joined(separator: "\n"))
        keywords:
        \(keywordLines.joined(separator: "\n"))
        """
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when `lines` is a prefix that keeps blank lines in the same places as the original.
    public static func prefixMatchesStructure(_ lines: [String], originalLyrics: [String]) -> Bool {
        guard lines.count <= originalLyrics.count else { return false }
        for (saved, original) in zip(lines, originalLyrics) {
            let originalBlank = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let savedBlank = saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if originalBlank != savedBlank { return false }
        }
        return true
    }

    /// Load a resumable prefix. A fingerprint, length, or blank-line mismatch deletes the file and returns nil.
    public func load(
        jobID: String,
        candidateIndex: Int,
        fingerprint: String,
        originalLyrics: [String]
    ) throws -> (lines: [String], finished: Bool)? {
        let url = fileURL(jobID: jobID, candidateIndex: candidateIndex)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(ParodyLineCheckpointFile.self, from: data) else {
            try removeFile(at: url)
            return nil
        }
        let usable = file.version == ParodyLineCheckpointFile.currentVersion
            && file.fingerprint == fingerprint
            && file.lineCount == originalLyrics.count
            && file.lines.count <= originalLyrics.count
            && Self.prefixMatchesStructure(file.lines, originalLyrics: originalLyrics)
            && (!file.finished || file.lines.count == originalLyrics.count)
        guard usable else {
            try removeFile(at: url)
            return nil
        }
        return (file.lines, file.finished)
    }

    public func save(
        jobID: String,
        candidateIndex: Int,
        fingerprint: String,
        lineCount: Int,
        lines: [String],
        finished: Bool
    ) throws {
        let url = fileURL(jobID: jobID, candidateIndex: candidateIndex)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = ParodyLineCheckpointFile(
            fingerprint: fingerprint,
            lineCount: lineCount,
            lines: lines,
            finished: finished
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    public func remove(jobID: String, candidateIndex: Int) throws {
        try removeFile(at: fileURL(jobID: jobID, candidateIndex: candidateIndex))
    }

    private func fileURL(jobID: String, candidateIndex: Int) -> URL {
        let safe = BatchResumeStore.safePathComponent(jobID)
        let name = "c\(String(format: "%02d", candidateIndex)).json"
        return rootURL.appendingPathComponent(safe, isDirectory: true).appendingPathComponent(name)
    }

    private func removeFile(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

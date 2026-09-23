// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class ParodyLineCheckpointTests: XCTestCase {

    private func tempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-lines-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fingerprint(
        lyrics: [String] = ["Hello world", "", "Good night"],
        keywords: [String: String] = ["space": "beyond earth"]
    ) -> String {
        ParodyLineCheckpointStore.fingerprint(
            lyrics: lyrics,
            keywords: keywords,
            model: "llama3.2:3b",
            refinementPasses: 0,
            enableCoherenceRegeneration: false,
            optimizeFit: false,
            fitTargetScore: 0.9,
            maxFitAttemptsPerLine: 0,
            fitPolishRounds: 0
        )
    }

    func testPartialLinesResumeAfterReopen() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["Hello world", "", "Good night"]
        let fp = fingerprint(lyrics: lyrics)

        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "song×theme",
            candidateIndex: 2,
            fingerprint: fp,
            lineCount: lyrics.count,
            lines: ["Hi there", ""],
            finished: false
        )

        let reopened = try ParodyLineCheckpointStore(outputRoot: dir.path)
        let loaded = try await reopened.load(
            jobID: "song×theme",
            candidateIndex: 2,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertEqual(loaded?.lines, ["Hi there", ""])
        XCTAssertEqual(loaded?.finished, false)
        let otherCandidate = try await reopened.load(
            jobID: "song×theme",
            candidateIndex: 1,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertNil(otherCandidate)
    }

    func testFinishedCheckpointRoundTrips() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["One", "Two"]
        let fp = fingerprint(lyrics: lyrics)
        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            lineCount: 2,
            lines: ["Uno", "Dos"],
            finished: true
        )
        let loaded = try await store.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertEqual(loaded?.finished, true)
        XCTAssertEqual(loaded?.lines, ["Uno", "Dos"])
    }

    func testFingerprintMismatchDiscardsCheckpoint() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["One", "Two"]
        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fingerprint(lyrics: lyrics, keywords: ["a": "b"]),
            lineCount: 2,
            lines: ["Uno"],
            finished: false
        )
        let loaded = try await store.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fingerprint(lyrics: lyrics, keywords: ["a": "changed"]),
            originalLyrics: lyrics
        )
        XCTAssertNil(loaded)
        let again = try await store.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fingerprint(lyrics: lyrics, keywords: ["a": "b"]),
            originalLyrics: lyrics
        )
        XCTAssertNil(again)
    }

    func testBlankLineMismatchDiscardsCheckpoint() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["One", "", "Three"]
        let fp = fingerprint(lyrics: lyrics)
        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            lineCount: lyrics.count,
            lines: ["Uno", "not blank"],
            finished: false
        )
        let loaded = try await store.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertNil(loaded)
    }

    func testRemoveDropsResumeFile() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["One"]
        let fp = fingerprint(lyrics: lyrics)
        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            lineCount: 1,
            lines: ["Uno"],
            finished: true
        )
        try await store.remove(jobID: "job", candidateIndex: 1)
        let loaded = try await store.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertNil(loaded)
    }

    func testFreshBatchRemovesLineCheckpoints() async throws {
        let dir = try tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lyrics = ["One"]
        let fp = fingerprint(lyrics: lyrics)
        let store = try ParodyLineCheckpointStore(outputRoot: dir.path)
        try await store.save(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            lineCount: 1,
            lines: ["Uno"],
            finished: false
        )

        let job = ParodyBatchJob(
            id: "job",
            songId: "job",
            themeId: "t",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("t/job.parody.txt").path
        )
        let manifest = BatchResumeManifest(
            model: "m",
            candidates: 1,
            jobsFingerprint: BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 1, model: "m")
        )
        _ = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: true)

        let reopened = try ParodyLineCheckpointStore(outputRoot: dir.path)
        let loaded = try await reopened.load(
            jobID: "job",
            candidateIndex: 1,
            fingerprint: fp,
            originalLyrics: lyrics
        )
        XCTAssertNil(loaded)
    }
}

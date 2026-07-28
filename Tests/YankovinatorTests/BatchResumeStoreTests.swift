// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class BatchResumeStoreTests: XCTestCase {

    func testResumeSkipsCompletedGenerations() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let job = ParodyBatchJob(
            id: "song×theme",
            songId: "song",
            themeId: "theme",
            lyricsPath: "/tmp/x.txt",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("theme/song.parody.txt").path
        )
        let fp = BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 2, model: "m1")
        let manifest = BatchResumeManifest(model: "m1", candidates: 2, jobsFingerprint: fp)
        let store = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false)

        let first = ParodyCandidateResult(index: 1, lines: ["one"], score: 0.3)
        _ = try await store.record(job: job, result: first)
        let complete1 = await store.isComplete(jobID: job.id, candidateIndex: 1)
        let complete2 = await store.isComplete(jobID: job.id, candidateIndex: 2)
        XCTAssertTrue(complete1)
        XCTAssertFalse(complete2)

        let store2 = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false)
        let restoredCount = await store2.restoredCount
        XCTAssertEqual(restoredCount, 1)
        // Open is metadata-only: no candidate texts paged in yet.
        let cachedAtOpen = await store2.cachedTextCount
        XCTAssertEqual(cachedAtOpen, 0)
        let restored = await store2.restoredResult(jobID: job.id, candidateIndex: 1)
        XCTAssertEqual(restored?.text, "one")
        let cachedAfterLoad = await store2.cachedTextCount
        XCTAssertEqual(cachedAfterLoad, 1)
    }

    func testFreshBatchRemovesCheckpoint() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let job = ParodyBatchJob(
            id: "a",
            songId: "a",
            themeId: "t",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("t/a.parody.txt").path
        )
        let manifest = BatchResumeManifest(
            model: "m",
            candidates: 1,
            jobsFingerprint: BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 1, model: "m")
        )
        let store = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false)
        _ = try await store.record(job: job, result: ParodyCandidateResult(index: 1, lines: ["x"], score: 1))

        let fresh = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: true)
        let freshCount = await fresh.restoredCount
        XCTAssertEqual(freshCount, 0)
    }

    func testIncrementalDiskWritesSurviveReopen() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-incr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let job = ParodyBatchJob(
            id: "job",
            songId: "s",
            themeId: "t",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("t/s.parody.txt").path
        )
        let fp = BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 5, model: "m")
        let manifest = BatchResumeManifest(model: "m", candidates: 5, jobsFingerprint: fp)

        let store = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false, textCacheLimit: 2)
        for i in 1...3 {
            _ = try await store.record(
                job: job,
                result: ParodyCandidateResult(index: i, lines: ["line-\(i)"], score: Double(i))
            )
            // Each completion must be durable on disk immediately (not held until batch end).
            let logURL = dir
                .appendingPathComponent(BatchResumeStore.stateDirectoryName)
                .appendingPathComponent(BatchResumeStore.logFileName)
            let logText = try String(contentsOf: logURL, encoding: .utf8)
            XCTAssertEqual(logText.split(separator: "\n").count, i)
            let artifact = dir
                .appendingPathComponent(BatchResumeStore.stateDirectoryName)
                .appendingPathComponent("candidates/job/c\(String(format: "%02d", i)).parody.txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path))
        }

        // LRU bound: recording 3 with limit 2 must not retain all texts.
        let cached = await store.cachedTextCount
        XCTAssertLessThanOrEqual(cached, 2)

        let reopened = try BatchResumeStore(
            outputRoot: dir.path,
            manifest: manifest,
            fresh: false,
            textCacheLimit: 2
        )
        let count = await reopened.restoredCount
        XCTAssertEqual(count, 3)
        let cachedAtOpen = await reopened.cachedTextCount
        XCTAssertEqual(cachedAtOpen, 0)

        let summaries = await reopened.candidateSummaries(jobID: job.id)
        XCTAssertEqual(summaries.map(\.candidateIndex), [1, 2, 3])
        XCTAssertEqual(summaries.map(\.score), [1.0, 2.0, 3.0])
        // Summaries must not page texts in.
        let cachedAfterSummaries = await reopened.cachedTextCount
        XCTAssertEqual(cachedAfterSummaries, 0)

        let best = try await reopened.bestResult(jobID: job.id)
        XCTAssertEqual(best?.index, 3)
        XCTAssertEqual(best?.text, "line-3")
        let stillComplete = await reopened.isComplete(jobID: job.id, candidateIndex: 2)
        XCTAssertTrue(stillComplete)
    }

    func testBoundedTextCacheDoesNotHoldAllCandidates() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let job = ParodyBatchJob(
            id: "big",
            songId: "s",
            themeId: "t",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("out.parody.txt").path
        )
        let n = 24
        let fp = BatchResumeStore.jobsFingerprint(jobs: [job], candidates: n, model: "m")
        let manifest = BatchResumeManifest(model: "m", candidates: n, jobsFingerprint: fp)
        let store = try BatchResumeStore(
            outputRoot: dir.path,
            manifest: manifest,
            fresh: false,
            textCacheLimit: 4
        )
        for i in 1...n {
            _ = try await store.record(
                job: job,
                result: ParodyCandidateResult(index: i, lines: [String(repeating: "x", count: 200), "c\(i)"], score: Double(i))
            )
        }
        let storedCount = await store.restoredCount
        let storedCache = await store.cachedTextCount
        XCTAssertEqual(storedCount, n)
        XCTAssertLessThanOrEqual(storedCache, 4)

        let again = try BatchResumeStore(
            outputRoot: dir.path,
            manifest: manifest,
            fresh: false,
            textCacheLimit: 4
        )
        let againCount = await again.restoredCount
        let againCacheOpen = await again.cachedTextCount
        XCTAssertEqual(againCount, n)
        XCTAssertEqual(againCacheOpen, 0)
        // Touch every candidate — cache stays capped.
        for i in 1...n {
            let loaded = try await again.loadResult(jobID: job.id, candidateIndex: i)
            XCTAssertEqual(loaded?.index, i)
        }
        let againCacheAfter = await again.cachedTextCount
        let lastComplete = await again.isComplete(jobID: job.id, candidateIndex: n)
        XCTAssertLessThanOrEqual(againCacheAfter, 4)
        XCTAssertTrue(lastComplete)
    }

    func testExportCandidateBundleCopiesFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("theme/song.parody.txt")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let job = ParodyBatchJob(
            id: "songxtheme",
            songId: "song",
            themeId: "theme",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: out.path
        )
        let fp = BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 3, model: "m")
        let manifest = BatchResumeManifest(model: "m", candidates: 3, jobsFingerprint: fp)
        let store = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false, textCacheLimit: 1)
        _ = try await store.record(job: job, result: ParodyCandidateResult(index: 1, lines: ["a"], score: 0.2))
        _ = try await store.record(job: job, result: ParodyCandidateResult(index: 2, lines: ["b"], score: 0.9))
        _ = try await store.record(job: job, result: ParodyCandidateResult(index: 3, lines: ["c"], score: 0.5))

        let reopened = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false, textCacheLimit: 1)
        let best = try await reopened.exportCandidateBundle(jobID: job.id, outputPath: out.path)
        XCTAssertEqual(best?.index, 2)
        let bundle = out.deletingLastPathComponent().appendingPathComponent("song.candidates")
        XCTAssertEqual(try String(contentsOf: bundle.appendingPathComponent("c02.parody.txt"), encoding: .utf8), "b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("scores.txt").path))
        // Export may page the winner only (limit 1).
        let exportCache = await reopened.cachedTextCount
        XCTAssertLessThanOrEqual(exportCache, 1)
    }

    func testManifestMismatchPreserved() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-resume-mismatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let job = ParodyBatchJob(
            id: "a",
            songId: "a",
            themeId: "t",
            lyricsPath: "/x",
            keywordsPath: nil,
            outputPath: dir.appendingPathComponent("a.parody.txt").path
        )
        let fp = BatchResumeStore.jobsFingerprint(jobs: [job], candidates: 2, model: "m1")
        let manifest = BatchResumeManifest(model: "m1", candidates: 2, jobsFingerprint: fp)
        let store = try BatchResumeStore(outputRoot: dir.path, manifest: manifest, fresh: false)
        _ = try await store.record(job: job, result: ParodyCandidateResult(index: 1, lines: ["x"], score: 1))

        let other = BatchResumeManifest(model: "m1", candidates: 3, jobsFingerprint: fp)
        XCTAssertThrowsError(try BatchResumeStore(outputRoot: dir.path, manifest: other, fresh: false)) { error in
            guard case BatchResumeError.manifestMismatch = error else {
                return XCTFail("expected manifestMismatch, got \(error)")
            }
        }
    }
}

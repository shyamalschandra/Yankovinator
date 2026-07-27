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
        let restored = await store2.restoredResult(jobID: job.id, candidateIndex: 1)
        XCTAssertEqual(restored?.text, "one")
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
}

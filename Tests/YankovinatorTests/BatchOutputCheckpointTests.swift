// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class BatchOutputCheckpointTests: XCTestCase {

    func testCheckpointKeepsBestScoreOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-checkpoint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("song.parody.txt").path
        let job = ParodyBatchJob(
            id: "song×theme",
            songId: "song",
            themeId: "theme",
            lyricsPath: "/tmp/x.txt",
            keywordsPath: nil,
            outputPath: out
        )
        let low = ParodyCandidateResult(index: 1, lines: ["low"], score: 0.2)
        let high = ParodyCandidateResult(index: 2, lines: ["high"], score: 0.9)

        let checkpoint = BatchOutputCheckpoint()
        let wroteLow = try await checkpoint.consider(job: job, result: low)
        let wroteHigh = try await checkpoint.consider(job: job, result: high)
        let wroteLowAgain = try await checkpoint.consider(job: job, result: low)
        XCTAssertTrue(wroteLow)
        XCTAssertTrue(wroteHigh)
        XCTAssertFalse(wroteLowAgain)
        let text = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("high"))
    }
}

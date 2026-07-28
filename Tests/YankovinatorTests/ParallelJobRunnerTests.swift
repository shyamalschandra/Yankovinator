// Copyright (C) 2025, Shyamal Suhana Chandra
// Unit tests for parallel Ollama job workers

import XCTest
@testable import Yankovinator

final class ParallelJobRunnerTests: XCTestCase {

    func testClampWorkers() {
        XCTAssertEqual(ParallelJobRunner.clampWorkers(0), 1)
        XCTAssertEqual(ParallelJobRunner.clampWorkers(-3), 1)
        XCTAssertEqual(ParallelJobRunner.clampWorkers(10), 10)
        XCTAssertEqual(ParallelJobRunner.clampWorkers(100), ParallelJobRunner.maxWorkers)
        XCTAssertEqual(ParallelJobRunner.clampWorkers(200), ParallelJobRunner.maxWorkers)
    }

    func testValidateWorkers() throws {
        try ParallelJobRunner.validateWorkers(1)
        try ParallelJobRunner.validateWorkers(10)
        try ParallelJobRunner.validateWorkers(ParallelJobRunner.maxWorkers)

        XCTAssertThrowsError(try ParallelJobRunner.validateWorkers(0))
        XCTAssertThrowsError(try ParallelJobRunner.validateWorkers(ParallelJobRunner.maxWorkers + 1))
    }

    func testMapPreservesOrderWithParallelWorkers() async throws {
        let items = Array(0..<20)
        let results = try await ParallelJobRunner.map(items: items, workers: 10) { value in
            try await Task.sleep(nanoseconds: UInt64((20 - value) * 1_000_000))
            return value * 2
        }
        XCTAssertEqual(results, items.map { $0 * 2 })
    }

    func testMapRespectsWorkerCap() async throws {
        actor Counter {
            var inFlight = 0
            var peak = 0
            func enter() {
                inFlight += 1
                peak = max(peak, inFlight)
            }
            func leave() {
                inFlight -= 1
            }
            func peakValue() -> Int { peak }
        }

        let counter = Counter()
        let workers = 4
        let items = Array(0..<16)

        _ = try await ParallelJobRunner.map(items: items, workers: workers) { _ in
            await counter.enter()
            try await Task.sleep(nanoseconds: 20_000_000)
            await counter.leave()
            return true
        }

        let peak = await counter.peakValue()
        XCTAssertLessThanOrEqual(peak, workers)
        XCTAssertGreaterThan(peak, 1)
    }

    func testRecommendedCloudWorkersAndLicenseCap() {
        XCTAssertEqual(ParallelJobRunner.recommendedCloudWorkers, 4)
        XCTAssertEqual(ParallelJobRunner.maxWorkers, 10)
        XCTAssertEqual(ParallelJobRunner.maxConcurrentConsumers, 10)
        XCTAssertEqual(ParallelJobRunner.licenseMaxConcurrentConsumers, 10)
    }

    func testConsumerPoolSizeCapsAtTen() {
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 1), 1)
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 10), 10)
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 128), 10)
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 200), 10)
    }

    func testConsumerPoolRespectsOllamaNumParallel() {
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 10, ollamaNumParallel: 4), 4)
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 3, ollamaNumParallel: 10), 3)
        // Server parallel above license max cannot raise consumers above 10
        XCTAssertEqual(ParallelJobRunner.consumerPoolSize(requestedWorkers: 10, ollamaNumParallel: 64), 10)
    }

    func testMapNeverExceedsTenConcurrentConsumers() async throws {
        actor Counter {
            var inFlight = 0
            var peak = 0
            func enter() {
                inFlight += 1
                peak = max(peak, inFlight)
            }
            func leave() {
                inFlight -= 1
            }
            func peakValue() -> Int { peak }
        }

        let counter = Counter()
        let items = Array(0..<40)

        _ = try await ParallelJobRunner.map(items: items, workers: 64) { _ in
            await counter.enter()
            try await Task.sleep(nanoseconds: 15_000_000)
            await counter.leave()
            return true
        }

        let peak = await counter.peakValue()
        XCTAssertLessThanOrEqual(peak, ParallelJobRunner.maxConcurrentConsumers)
        XCTAssertLessThanOrEqual(peak, ParallelJobRunner.licenseMaxConcurrentConsumers)
        XCTAssertGreaterThan(peak, 1)
    }

    func testBatchJobBuilderDiscoversTxtFiles() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("yankovinator-batch-\(UUID().uuidString)")
        let input = temp.appendingPathComponent("in")
        let output = temp.appendingPathComponent("out")
        try fm.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        try "line one\n".write(to: input.appendingPathComponent("song_a.txt"), atomically: true, encoding: .utf8)
        try "line two\n".write(to: input.appendingPathComponent("song_b.txt"), atomically: true, encoding: .utf8)
        try "ignore".write(to: input.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let jobs = try ParodyBatchJobBuilder.jobs(
            inputDir: input.path,
            outputDir: output.path
        )

        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs.map(\.id), ["song_a", "song_b"])
        XCTAssertTrue(jobs[0].outputPath.hasSuffix("song_a.parody.txt"))
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: output.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testBatchJobBuilderEmptyDirectoryThrows() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("yankovinator-empty-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        XCTAssertThrowsError(
            try ParodyBatchJobBuilder.jobs(inputDir: temp.path, outputDir: temp.appendingPathComponent("out").path)
        )
    }

    func testCrossProductJobsSongsTimesThemes() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("yankovinator-cross-\(UUID().uuidString)")
        let songs = temp.appendingPathComponent("songs")
        let themes = temp.appendingPathComponent("themes")
        let output = temp.appendingPathComponent("out")
        try fm.createDirectory(at: songs, withIntermediateDirectories: true)
        try fm.createDirectory(at: themes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        try "lyric a\n".write(to: songs.appendingPathComponent("stay.txt"), atomically: true, encoding: .utf8)
        try "lyric b\n".write(to: songs.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try "space: cosmos\n".write(to: themes.appendingPathComponent("space.txt"), atomically: true, encoding: .utf8)
        try "food: cuisine\n".write(to: themes.appendingPathComponent("food.txt"), atomically: true, encoding: .utf8)
        try "pets: animals\n".write(to: themes.appendingPathComponent("pets.txt"), atomically: true, encoding: .utf8)

        let jobs = try ParodyBatchJobBuilder.crossProductJobs(
            inputDir: songs.path,
            themesDir: themes.path,
            outputDir: output.path
        )

        XCTAssertEqual(jobs.count, 6) // 2 songs × 3 themes
        XCTAssertEqual(Set(jobs.map(\.songId)), ["hello", "stay"])
        XCTAssertEqual(Set(jobs.compactMap(\.themeId)), ["food", "pets", "space"])
        XCTAssertTrue(jobs.allSatisfy { $0.keywordsPath != nil })
        XCTAssertTrue(jobs.contains { $0.outputPath.hasSuffix("/space/stay.parody.txt") })
        XCTAssertTrue(jobs.contains { $0.outputPath.hasSuffix("/food/hello.parody.txt") })
    }

    func testCrossProductRequiresForceAboveThreshold() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("yankovinator-force-\(UUID().uuidString)")
        let songs = temp.appendingPathComponent("songs")
        let themes = temp.appendingPathComponent("themes")
        let output = temp.appendingPathComponent("out")
        try fm.createDirectory(at: songs, withIntermediateDirectories: true)
        try fm.createDirectory(at: themes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        // 10 × 11 = 110 > 100 threshold
        for i in 0..<10 {
            try "song \(i)\n".write(to: songs.appendingPathComponent("s\(i).txt"), atomically: true, encoding: .utf8)
        }
        for i in 0..<11 {
            try "k\(i): d\(i)\n".write(to: themes.appendingPathComponent("t\(i).txt"), atomically: true, encoding: .utf8)
        }

        XCTAssertThrowsError(
            try ParodyBatchJobBuilder.crossProductJobs(
                inputDir: songs.path,
                themesDir: themes.path,
                outputDir: output.path,
                force: false
            )
        ) { error in
            guard let jobError = error as? ParallelJobError else {
                XCTFail("Expected ParallelJobError")
                return
            }
            if case .crossProductRequiresForce(_, _, let candidates, let total, _) = jobError {
                XCTAssertEqual(candidates, 1)
                XCTAssertEqual(total, 110)
            } else {
                XCTFail("Unexpected ParallelJobError: \(jobError)")
            }
        }

        let forced = try ParodyBatchJobBuilder.crossProductJobs(
            inputDir: songs.path,
            themesDir: themes.path,
            outputDir: output.path,
            force: true
        )
        XCTAssertEqual(forced.count, 110)
    }

    func testOneSongTimesThemes() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("yankovinator-one-\(UUID().uuidString)")
        let themes = temp.appendingPathComponent("themes")
        let output = temp.appendingPathComponent("out")
        try fm.createDirectory(at: themes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let lyrics = temp.appendingPathComponent("anthem.txt")
        try "line\n".write(to: lyrics, atomically: true, encoding: .utf8)
        try "a: one\n".write(to: themes.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "b: two\n".write(to: themes.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)

        let jobs = try ParodyBatchJobBuilder.jobs(
            lyricsPath: lyrics.path,
            themesDir: themes.path,
            outputDir: output.path
        )
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(Set(jobs.map(\.songId)), ["anthem"])
        XCTAssertEqual(Set(jobs.compactMap(\.themeId)), ["alpha", "beta"])
    }
}

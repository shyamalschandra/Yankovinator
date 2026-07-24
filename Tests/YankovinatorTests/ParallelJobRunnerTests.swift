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

    func testRecommendedCloudWorkersIsTen() {
        XCTAssertEqual(ParallelJobRunner.recommendedCloudWorkers, 10)
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
}

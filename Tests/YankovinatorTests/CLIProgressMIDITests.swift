// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class CLIProgressMIDITests: XCTestCase {

    func testWorkerProgramsAreDistinctWithinPool() {
        let programs = (0..<10).map { CLIProgressMIDINotes.workerProgram(workerID: $0) }
        XCTAssertEqual(Set(programs).count, programs.count)
    }

    func testPulseNotesStayInMidiRange() {
        for worker in 0..<10 {
            for tick in stride(from: 0, to: 120, by: 12) {
                let note = CLIProgressMIDINotes.pulseNote(workerID: worker, globalTick: tick)
                XCTAssertGreaterThanOrEqual(note, 48)
                XCTAssertLessThanOrEqual(note, 96)
            }
        }
    }

    func testShouldPulseIsSparse() {
        var hits = 0
        for tick in 0..<120 {
            if CLIProgressMIDINotes.shouldPulse(workerID: 0, globalTick: tick) { hits += 1 }
        }
        XCTAssertEqual(hits, 10)
    }

    func testBatchCompleteNotesCount() {
        XCTAssertEqual(CLIProgressMIDINotes.batchCompleteNotes(workerCount: 10).count, 4)
    }
}

// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class CLIProgressFormattingTests: XCTestCase {

    func testOverallLineShowsFractionAndPercent() {
        let line = CLIProgressFormatting.overallLine(
            label: "Generations",
            completed: 5,
            total: 20,
            width: 12,
            theme: .plain,
            framed: false
        )
        XCTAssertTrue(line.contains("Generations"))
        XCTAssertTrue(line.contains("5/20"))
        XCTAssertTrue(line.contains("(25%)"))
        XCTAssertTrue(line.contains("█") || line.contains("▌") || line.contains("░"))
    }

    func testUnicodeDeterminateBarUsesBlockGlyphs() {
        let bar = CLIProgressFormatting.unicodeDeterminateBar(ratio: 0.5, width: 8, theme: .plain)
        XCTAssertTrue(bar.contains("█") || bar.contains("▉") || bar.contains("▌"))
        XCTAssertTrue(bar.contains("░"))
    }

    func testWorkerPoolLinesIncludeEachWorker() {
        let slots: [CLIProgressFormatting.WorkerSlot] = [
            .working(jobNumber: 3, tick: 2, spentSeconds: 125, etaSeconds: 240),
            .idle(spentSeconds: 40, etaSeconds: 600),
        ]
        let lines = CLIProgressFormatting.workerPoolLines(
            label: "Generations",
            completed: 1,
            total: 10,
            overallWidth: 12,
            workerCount: 2,
            workerBarWidth: 8,
            tick: 0,
            theme: .plain,
            batchSpentSeconds: 200,
            batchEtaSeconds: 900,
            slots: slots
        )
        let visible = lines.map { CLIProgressFormatting.visibleText($0) }
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(visible[1].contains("cloud worker"))
        XCTAssertTrue(visible[2].contains("W01"))
        XCTAssertTrue(visible[2].contains("#3"))
        XCTAssertTrue(visible[2].contains("spent"))
        XCTAssertTrue(visible[2].contains("ETA"))
        XCTAssertTrue(visible[3].contains("W02"))
        XCTAssertTrue(visible[3].contains("idle"))
    }

    func testFormatDurationAndETA() {
        XCTAssertEqual(CLIProgressFormatting.formatDuration(45), "45s")
        XCTAssertEqual(CLIProgressFormatting.formatDuration(125), "2m05s")
        XCTAssertEqual(CLIProgressFormatting.formatETA(90), "~1m30s")
        XCTAssertEqual(CLIProgressFormatting.formatETA(nil), "…")
    }

    func testLiveThemeIncludesEmojiWhenEnabled() {
        let line = CLIProgressFormatting.overallLine(
            label: "Generations",
            completed: 1,
            total: 4,
            width: 8,
            theme: TUITheme(useColor: false, useEmoji: true),
            framed: true
        )
        XCTAssertTrue(line.contains("📊"))
        XCTAssertTrue(line.contains("☁️"))
    }
}

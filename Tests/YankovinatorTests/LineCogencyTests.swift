// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class LineCogencyTests: XCTestCase {

    func testRepairKeepsEndingPunctuationWhenWordCountsDiffer() {
        let repaired = LineCogency.repair("Dogs. purr loudly", matching: "Cats sleep.")
        XCTAssertEqual(repaired, "Dogs purr loudly.")
        XCTAssertFalse(repaired.contains(". "))
    }

    func testRepairCopiesCommasWhenWordCountsMatch() {
        let repaired = LineCogency.repair("goodbye friend", matching: "Hello, world!")
        XCTAssertEqual(repaired, "Goodbye, friend!")
    }

    func testRejectsWordListAndWordSalad() {
        let original = "The cat sat on the mat."
        let list = LineCogency.assess(line: "bright, light, night", original: original)
        XCTAssertFalse(list.accepted)

        let salad = LineCogency.assess(
            line: "Banana stapler ontology waffle",
            original: original,
            previousLines: ["We sail beyond the silent sea"]
        )
        XCTAssertFalse(salad.accepted)
    }

    func testAcceptsGrammaticalVerseLine() {
        let verdict = LineCogency.assess(
            line: "The ship sailed past the moon.",
            original: "The cat sat on the mat."
        )
        XCTAssertTrue(verdict.accepted, verdict.reasons.joined(separator: "; "))
    }

    func testAcceptsClauseWithInternalCommas() {
        let verdict = LineCogency.assess(
            line: "We came, we saw, we sang.",
            original: "We came, we saw, we left."
        )
        XCTAssertTrue(verdict.accepted, verdict.reasons.joined(separator: "; "))
    }

    func testPrefixStopsAtFirstIncoherentLine() {
        let original = ["The cat sat on the mat.", "I tip my little hat."]
        let lines = ["The ship sailed past the moon.", "bright, light, night"]
        let kept = LineCogency.acceptablePrefix(lines: lines, originalLyrics: original)
        XCTAssertEqual(kept, ["The ship sailed past the moon."])
    }
}

// Copyright (C) 2025, Shyamal Suhana Chandra
// Unit tests for multi-candidate parody ranking

import XCTest
@testable import Yankovinator

final class CandidateParodyGeneratorTests: XCTestCase {

    func testValidateAndClampCandidates() throws {
        try CandidateParodyGenerator.validateCandidates(1)
        try CandidateParodyGenerator.validateCandidates(10)
        try CandidateParodyGenerator.validateCandidates(CandidateParodyGenerator.maxCandidates)
        XCTAssertThrowsError(try CandidateParodyGenerator.validateCandidates(0))
        XCTAssertThrowsError(try CandidateParodyGenerator.validateCandidates(100))
        XCTAssertEqual(CandidateParodyGenerator.clampCandidates(0), 1)
        XCTAssertEqual(CandidateParodyGenerator.clampCandidates(10), 10)
        XCTAssertEqual(CandidateParodyGenerator.clampCandidates(99), CandidateParodyGenerator.maxCandidates)
        XCTAssertEqual(CandidateParodyGenerator.recommendedCandidates, 10)
    }

    func testScoreParodyReturnsBoundedValues() {
        let themed = [
            "Twinkle twinkle little star",
            "How I wonder what you are",
            "Up above the world so high"
        ]
        let score = CandidateParodyGenerator.scoreParody(
            lines: themed,
            keywords: ["space": "cosmos beyond Earth", "star": "luminous body"]
        )
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func testCandidateResultRankingOrder() {
        let a = ParodyCandidateResult(index: 1, lines: ["a"], score: 0.4)
        let b = ParodyCandidateResult(index: 2, lines: ["b"], score: 0.9)
        let c = ParodyCandidateResult(index: 3, lines: ["c"], score: 0.9)
        let ranked = [a, b, c].sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
        XCTAssertEqual(ranked.map(\.index), [2, 3, 1])
    }

    func testScoreParodyHandlesEmptyLines() {
        let lines = ["Hello world", "", "Another line"]
        let score = CandidateParodyGenerator.scoreParody(lines: lines, keywords: [:])
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
}

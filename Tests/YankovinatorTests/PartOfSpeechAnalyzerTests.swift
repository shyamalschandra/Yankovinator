import XCTest
@testable import Yankovinator

final class PartOfSpeechAnalyzerTests: XCTestCase {
    func testAnalyzeLineAlignsWithSyllableTokenCount() {
        let analysis = PartOfSpeechAnalyzer.analyzeLine("I wanna dance with somebody")
        XCTAssertEqual(analysis.count, 5)
        XCTAssertEqual(analysis.map(\.syllables), [1, 2, 1, 1, 4])
    }

    func testPromptPatternIncludesLabels() {
        let analysis = PartOfSpeechAnalyzer.analyzeLine("hello world")
        let pattern = PartOfSpeechAnalyzer.promptPattern(from: analysis)
        XCTAssertTrue(pattern.contains("hello("))
        XCTAssertTrue(pattern.contains("world("))
    }

    func testLineAlignmentPerfectWhenSameStructure() {
        let score = PartOfSpeechAnalyzer.lineAlignmentScore(
            original: "I love you",
            parody: "We need peace"
        )
        XCTAssertGreaterThan(score, 0.5)
    }

    func testOEDTagMatchesNoun() {
        XCTAssertTrue(PartOfSpeechTag.matchesOEDTag("n.", required: .noun))
        XCTAssertFalse(PartOfSpeechTag.matchesOEDTag("v. t.", required: .noun))
    }

    func testCompatibleAllowsUnknown() {
        XCTAssertTrue(PartOfSpeechTag.compatible(required: .unknown, candidate: .verb))
        XCTAssertTrue(PartOfSpeechTag.compatible(required: .noun, candidate: .noun))
        XCTAssertFalse(PartOfSpeechTag.compatible(required: .noun, candidate: .verb))
    }
}

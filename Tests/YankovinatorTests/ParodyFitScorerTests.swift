import XCTest
@testable import Yankovinator

final class ParodyFitScorerTests: XCTestCase {
    func testPerfectStructuralMatchScoresHigh() {
        let score = ParodyFitScorer.scoreLine(
            original: "Hello world today",
            parody: "Prayerful soul alway",
            previousParodyLines: [],
            keywords: ["soul": "spirit"]
        )
        XCTAssertGreaterThan(score.composite, 0.4)
        XCTAssertGreaterThan(score.wordCountMatch, 0.9)
    }

    func testEmptyParodyScoresZero() {
        let score = ParodyFitScorer.scoreLine(
            original: "Hello world",
            parody: "",
            previousParodyLines: [],
            keywords: [:]
        )
        XCTAssertEqual(score.composite, 0.0)
    }

    func testGlobalScoreUsesMinLine() {
        let originals = ["Line one here", "Line two here"]
        let good = ["Theme one near", "Theme two near"]
        let mixed = ["Theme one near", ""]
        let goodSummary = ParodyFitScorer.scoreSong(
            originalLyrics: originals,
            parodyLines: good,
            keywords: ["theme": "topic"]
        )
        let mixedSummary = ParodyFitScorer.scoreSong(
            originalLyrics: originals,
            parodyLines: mixed,
            keywords: ["theme": "topic"]
        )
        XCTAssertGreaterThan(goodSummary.globalScore, mixedSummary.globalScore)
        XCTAssertLessThan(mixedSummary.minComposite, goodSummary.minComposite)
    }

    func testFitsCorrectlyRequiresMultipleConstraints() {
        let strict = ParodyFitScore(
            lineTotalSyllables: 1,
            wordSyllablePattern: 0.96,
            wordCountMatch: 1,
            partOfSpeech: 0.9,
            coherence: 0.5,
            theme: 0.6,
            dictionaryUsage: 0.5,
            composite: 0.91
        )
        XCTAssertTrue(strict.fitsCorrectly)

        let weakPOS = ParodyFitScore(
            lineTotalSyllables: 1,
            wordSyllablePattern: 0.96,
            wordCountMatch: 1,
            partOfSpeech: 0.5,
            coherence: 0.5,
            theme: 0.6,
            dictionaryUsage: 0.5,
            composite: 0.91
        )
        XCTAssertFalse(weakPOS.fitsCorrectly)
    }
}

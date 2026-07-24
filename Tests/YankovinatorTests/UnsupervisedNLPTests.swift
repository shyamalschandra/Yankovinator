// Copyright (C) 2025, Shyamal Suhana Chandra
// Tests for unsupervised NLP / NLU helpers

import XCTest
@testable import Yankovinator

final class UnsupervisedNLPTests: XCTestCase {

    func testUnsupervisedRhymeClusteringAABB() {
        let lyrics = [
            "The cat sat on the mat",
            "I tip my little hat",
            "We dance until the night",
            "Beneath the glowing light"
        ]
        let result = UnsupervisedRhymeClustering().clusterRhymeScheme(from: lyrics)
        XCTAssertEqual(result.rhymeGroups.count, 4)
        XCTAssertFalse(result.scheme.isEmpty)
        // mat/hat and night/light should form two pairs
        XCTAssertEqual(result.rhymeGroups[0], result.rhymeGroups[1], "mat/hat should cluster: \(result)")
        XCTAssertEqual(result.rhymeGroups[2], result.rhymeGroups[3], "night/light should cluster: \(result)")
        XCTAssertNotEqual(result.rhymeGroups[0], result.rhymeGroups[2])
    }

    func testRhymeDistanceIdenticalWords() {
        let clustering = UnsupervisedRhymeClustering()
        XCTAssertEqual(clustering.rhymeDistance("star", "star"), 0.0, accuracy: 0.0001)
        XCTAssertLessThan(clustering.rhymeDistance("light", "night"), clustering.rhymeDistance("light", "table"))
    }

    func testLexicalSubstitutionSyllableMatch() {
        let engine = LexicalSubstitutionEngine()
        // If embeddings are unavailable in the test environment, skip gracefully.
        guard engine.isAvailable else {
            print("⚠️  NLEmbedding unavailable - skipping lexical substitution test")
            return
        }

        let subs = engine.substitutes(for: "star", requiredSyllables: 1, maxResults: 8)
        for sub in subs {
            XCTAssertEqual(sub.syllables, 1)
            XCTAssertEqual(SyllableCounter.countSyllables(in: sub.candidate), 1)
            XCTAssertNotEqual(sub.candidate, "star")
        }
    }

    func testLexicalSubstitutionLinePositions() {
        let engine = LexicalSubstitutionEngine()
        let line = "Twinkle twinkle little star"
        let positions = engine.substitutesForLine(line, maxPerPosition: 3)
        XCTAssertEqual(positions.count, SyllableCounter.analyzeWordSyllables(in: line).count)
    }

    func testCoherenceCriticPrefersRelatedContinuation() {
        let critic = CoherenceCritic()
        let previous = [
            "We sail beyond the silent sea",
            "Where silver moons and planets gleam"
        ]
        let coherent = critic.scoreLocally(
            candidate: "Our rocket climbs through cosmic dream",
            previousLines: previous,
            keywords: ["space": "beyond earth", "stars": "lights"]
        )
        let incoherent = critic.scoreLocally(
            candidate: "Banana stapler ontology waffle",
            previousLines: previous,
            keywords: ["space": "beyond earth"]
        )
        XCTAssertGreaterThan(coherent.coherence, incoherent.coherence)
        XCTAssertGreaterThan(incoherent.surprise, coherent.surprise)
    }

    func testCoherenceCriticRejectThreshold() {
        let critic = CoherenceCritic(minCoherence: 0.9, maxSurprise: 0.2)
        let weak = CoherenceCritic.Score(coherence: 0.2, surprise: 0.9, method: "test")
        XCTAssertTrue(critic.shouldReject(weak))
        let strong = CoherenceCritic.Score(coherence: 0.95, surprise: 0.1, method: "test")
        XCTAssertFalse(critic.shouldReject(strong))
    }

    func testOllamaSurpriseParser() {
        XCTAssertEqual(OllamaClient.parseUnitInterval(from: "0.73"), 0.73, accuracy: 0.0001)
        XCTAssertEqual(OllamaClient.parseUnitInterval(from: "Surprise: 1.0"), 1.0, accuracy: 0.0001)
        XCTAssertEqual(OllamaClient.parseUnitInterval(from: "no number"), 0.5, accuracy: 0.0001)
    }

    func testYankovinatorFacadeUnsupervisedHelpers() {
        let clustered = Yankovinator.clusterRhymeScheme(from: [
            "The night is bright",
            "We take our flight"
        ])
        XCTAssertEqual(clustered.rhymeGroups.count, 2)

        let score = Yankovinator.scoreCoherence(
            candidate: "Across the sky of endless light",
            previousLines: ["The night is bright"],
            keywords: ["sky": "above"]
        )
        XCTAssertGreaterThanOrEqual(score.coherence, 0.0)
        XCTAssertLessThanOrEqual(score.coherence, 1.0)
    }
}

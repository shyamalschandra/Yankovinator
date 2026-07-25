// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class BatchFastGeneratorTests: XCTestCase {

    func testSlimGeneratorProducesLineWithOllama() async throws {
        let generator = ParodyGenerator(
            useDictionary: false,
            useUnsupervisedNLP: false,
            skipLLMCoherenceCritic: true
        )
        guard try await generator.validateOllamaConnection() else {
            throw XCTSkip("Ollama unavailable")
        }
        let lyrics = ["Twinkle twinkle little star"]
        let keywords = ["space": "the universe"]
        let lines = try await generator.generateParody(
            originalLyrics: lyrics,
            keywords: keywords,
            refinementPasses: 0,
            enableCoherenceRegeneration: false
        )
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(lines[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

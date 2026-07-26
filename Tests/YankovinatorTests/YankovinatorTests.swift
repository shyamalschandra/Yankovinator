// Copyright (C) 2025, Shyamal Suhana Chandra
// Integration tests for Yankovinator

import XCTest
@testable import Yankovinator

final class YankovinatorTests: XCTestCase {
    
    func testSyllableCounting() {
        let text = "Hello world"
        let count = Yankovinator.countSyllables(text)
        XCTAssertGreaterThan(count, 0)
    }
    
    func testStructureAnalysis() {
        let lyrics = [
            "Row row row your boat",
            "Gently down the stream",
            "Merrily merrily merrily merrily",
            "Life is but a dream"
        ]
        
        let structure = Yankovinator.analyzeStructure(lyrics)
        XCTAssertEqual(structure.count, lyrics.count)
        
        for count in structure {
            XCTAssertGreaterThan(count, 0, "Each line should have at least one syllable")
        }
    }
    
    func testBatchFastPathRhymeAndStructure() {
        let lyrics = [
            "Twinkle twinkle little star",
            "How I wonder what you are",
        ]
        let detected = RhymeSchemeAnalyzer.detectRhymeScheme(from: lyrics)
        XCTAssertEqual(detected.rhymeGroups.count, lyrics.count)
        let structure = SyllableCounter.analyzeSongStructure(lyrics)
        XCTAssertEqual(structure.count, lyrics.count)
    }

    func testConcurrentNaturalLanguageAccess() async {
        let lyrics = [
            "Twinkle twinkle little star",
            "How I wonder what you are",
        ]
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    _ = RhymeSchemeAnalyzer.detectRhymeScheme(from: lyrics)
                    _ = PartOfSpeechAnalyzer.analyzeLine(lyrics[0])
                    _ = SyllableCounter.countSyllablesInLine(lyrics[1])
                }
            }
        }
    }

    func testParodyGeneration() async throws {
        // This is an integration test that requires Ollama
        // Skip if Ollama is not available
        
        let lyrics = [
            "Twinkle twinkle little star",
            "How I wonder what you are"
        ]
        
        let keywords = [
            "space": "the physical universe beyond Earth",
            "stars": "luminous celestial bodies"
        ]
        
        // Check if Ollama is available first
        let generator = ParodyGenerator()
        
        do {
            let isAvailable = try await generator.validateOllamaConnection()
            
            guard isAvailable else {
                print("⚠️  Ollama not available - skipping integration test")
                return
            }
            
            let parody = try await Yankovinator.generateParody(
                originalLyrics: lyrics,
                keywords: keywords
            )
            
            XCTAssertEqual(parody.count, lyrics.count, "Parody should have same number of lines")
            
            for line in parody {
                XCTAssertFalse(line.isEmpty, "Parody lines should not be empty")
            }
        } catch {
            // Ollama not available or connection error - skip test
            print("⚠️  Ollama connection failed - skipping integration test: \(error)")
            return
        }
    }
}


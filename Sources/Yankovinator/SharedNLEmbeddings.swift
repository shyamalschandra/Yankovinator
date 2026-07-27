// Copyright (C) 2025, Shyamal Suhana Chandra
// Process-wide NLEmbedding cache — concurrent wordEmbedding(for:) loads segfault on macOS.

import Foundation
import NaturalLanguage

public enum SharedNLEmbeddings {
    private static var word: NLEmbedding?
    private static var sentence: NLEmbedding?

    /// Shared English word embedding (loaded once under `NLConcurrency`).
    public static func wordEmbedding() -> NLEmbedding? {
        NLConcurrency.synchronized {
            if word == nil {
                word = NLEmbedding.wordEmbedding(for: .english)
            }
            return word
        }
    }

    /// Shared English sentence embedding when available, else word embedding.
    public static func sentenceOrWordEmbedding() -> NLEmbedding? {
        NLConcurrency.synchronized {
            if #available(macOS 13.0, iOS 16.0, *) {
                if sentence == nil {
                    sentence = NLEmbedding.sentenceEmbedding(for: .english)
                }
                if let sentence { return sentence }
            }
            if word == nil {
                word = NLEmbedding.wordEmbedding(for: .english)
            }
            return word
        }
    }

    /// Run an embedding query under the NaturalLanguage lock.
    static func withWordEmbedding<T>(_ body: (NLEmbedding) -> T) -> T? {
        NLConcurrency.synchronized {
            if word == nil {
                word = NLEmbedding.wordEmbedding(for: .english)
            }
            guard let word else { return nil }
            return body(word)
        }
    }
}

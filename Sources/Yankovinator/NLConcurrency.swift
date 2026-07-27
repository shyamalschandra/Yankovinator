// Copyright (C) 2025, Shyamal Suhana Chandra
// NaturalLanguage tokenizers/taggers/embeddings are not safe across concurrent Swift tasks.

import Foundation

enum NLConcurrency {
    /// Recursive so fit-scoring / POS / embedding helpers can nest safely on one worker.
    private static let lock = NSRecursiveLock()

    static func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

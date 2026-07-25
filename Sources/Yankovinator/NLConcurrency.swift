// Copyright (C) 2025, Shyamal Suhana Chandra
// NaturalLanguage tokenizers/taggers are not safe across concurrent Swift tasks on all OS builds.

import Foundation

enum NLConcurrency {
    private static let lock = NSLock()

    static func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

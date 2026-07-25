// Copyright (C) 2025, Shyamal Suhana Chandra
// Terminal progress bar for long-running batch jobs

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Whether stderr is an interactive terminal (progress bar safe).
public enum TerminalProgress {
    public static var isInteractive: Bool {
        isatty(STDERR_FILENO) != 0
    }
}

/// Async-safe progress bar written to stderr (single updating line).
public actor CLIProgressBar {
    private let total: Int
    private let label: String
    private let width: Int
    private var completed: Int = 0
    private var finished = false

    public init(total: Int, label: String = "Jobs", width: Int = 40) {
        self.total = max(1, total)
        self.label = label
        self.width = max(10, width)
    }

    public func advance(by amount: Int = 1) {
        guard !finished, amount > 0 else { return }
        completed = min(total, completed + amount)
        render()
    }

    public func finish() {
        guard !finished else { return }
        finished = true
        completed = total
        render()
        fputs("\n", stderr)
        fflush(stderr)
    }

    private func render() {
        let ratio = Double(completed) / Double(total)
        let filled = min(width - 1, Int(ratio * Double(width)))
        let empty = max(0, width - filled - 1)
        let bar = String(repeating: "=", count: filled) + ">" + String(repeating: " ", count: empty)
        let pct = Int((ratio * 100).rounded())
        let line = "\(label) [\(bar)] \(completed)/\(total) (\(pct)%)"
        fputs("\r\(line)", stderr)
        fflush(stderr)
    }
}

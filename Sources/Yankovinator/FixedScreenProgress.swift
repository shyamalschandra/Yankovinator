// Copyright (C) 2025, Shyamal Suhana Chandra
// Fixed alternate-screen TUI on stderr (ANSI): full UTF-8, color, emoji; no scrollback growth.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reference-counted alternate-screen batch progress (interactive stderr TTY only).
enum FixedScreenProgress {
    private static let queue = DispatchQueue(label: "com.yankovinator.fixed-screen-tui")
    private static var referenceCount = 0
    private static var isActive = false

    /// Enter the alternate screen. Returns false when not a TTY (caller uses inline ANSI fallback).
    static func acquire() -> Bool {
        queue.sync {
            referenceCount += 1
            guard referenceCount == 1 else { return isActive }
            guard TerminalProgress.isInteractive else {
                isActive = false
                return false
            }
            // Alternate buffer + hidden cursor; preserves SGR/UTF-8 (unlike ncurses addstr).
            fputs("\u{001B}[?1049h\u{001B}[?25l", stderr)
            fflush(stderr)
            isActive = true
            return true
        }
    }

    static func release() {
        queue.sync {
            guard referenceCount > 0 else { return }
            referenceCount -= 1
            guard referenceCount == 0, isActive else { return }
            fputs("\u{001B}[?25h\u{001B}[?1049l", stderr)
            fflush(stderr)
            isActive = false
        }
    }

    /// Draw lines at fixed row positions without growing scrollback. Returns false if inactive.
    static func render(lines: [String]) -> Bool {
        queue.sync {
            guard isActive else { return false }
            let columns = max(40, TerminalProgress.columns)
            for (index, line) in lines.enumerated() {
                let row = index + 1
                let trimmed = truncatePreservingANSI(line, maxVisible: columns)
                fputs("\u{001B}[\(row);1H\u{001B}[2K\(trimmed)", stderr)
            }
            if lines.count < 64 {
                fputs("\u{001B}[\(lines.count + 1);1H\u{001B}[J", stderr)
            }
            fflush(stderr)
            return true
        }
    }

    private static func truncatePreservingANSI(_ line: String, maxVisible: Int) -> String {
        let visible = CLIProgressFormatting.visibleText(line)
        guard visible.count > maxVisible else { return line }
        // Plain truncate on visible width; drop trailing ANSI reset if we stripped tail.
        let suffix = "…"
        var budget = max(1, maxVisible - suffix.count)
        var result = ""
        var visibleCount = 0
        var index = line.startIndex
        while index < line.endIndex, visibleCount < budget {
            if line[index] == "\u{001B}", let end = line[index...].range(of: "m")?.upperBound {
                result.append(contentsOf: line[index..<end])
                index = end
                continue
            }
            result.append(line[index])
            visibleCount += 1
            index = line.index(after: index)
        }
        return result + suffix + ANSI.reset
    }
}

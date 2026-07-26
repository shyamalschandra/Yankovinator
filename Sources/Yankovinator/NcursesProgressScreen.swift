// Copyright (C) 2025, Shyamal Suhana Chandra
// Reference-counted ncurses alternate screen for batch progress (macOS).

import Foundation

#if os(macOS)
import YankovinatorNcurses

enum NcursesProgressScreen {
    private static let queue = DispatchQueue(label: "com.yankovinator.ncurses")
    private static var referenceCount = 0
    private static var isActive = false

    /// Enter fixed-screen ncurses mode (returns false → use ANSI fallback).
    static func acquire() -> Bool {
        queue.sync {
            referenceCount += 1
            guard referenceCount == 1 else { return isActive }
            isActive = yank_ncurses_begin()
            return isActive
        }
    }

    static func release() {
        queue.sync {
            guard referenceCount > 0 else { return }
            referenceCount -= 1
            guard referenceCount == 0, isActive else { return }
            yank_ncurses_end()
            isActive = false
        }
    }

    /// Render visible lines on a fixed panel (no terminal scroll). Returns false if inactive.
    static func render(lines: [String]) -> Bool {
        queue.sync {
            guard isActive else { return false }
            let columns = max(40, TerminalProgress.columns)
            let visible = lines.map { plainLine($0, maxColumns: columns) }
            let joined = visible.joined(separator: "\n")
            joined.withCString { cText in
                yank_ncurses_render_multiline(cText)
            }
            return true
        }
    }

    private static func plainLine(_ line: String, maxColumns: Int) -> String {
        let stripped = CLIProgressFormatting.visibleText(line)
        return CLIProgressFormatting.truncate(stripped, maxVisible: maxColumns)
    }
}

#else

enum NcursesProgressScreen {
    static func acquire() -> Bool { false }
    static func release() {}
    static func render(lines: [String]) -> Bool { false }
}

#endif

// Copyright (C) 2025, Shyamal Suhana Chandra
// TUI progress for batch / cloud worker jobs (Unicode blocks, color, emoji)

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

    /// Rich TUI when stderr is a TTY; plain text otherwise (logs, CI).
    public static var tuiTheme: TUITheme {
        isInteractive ? .live : .plain
    }
}

/// Controls ANSI color and emoji in progress output.
public struct TUITheme: Sendable, Equatable {
    public var useColor: Bool
    public var useEmoji: Bool

    public static let live = TUITheme(useColor: true, useEmoji: true)
    public static let plain = TUITheme(useColor: false, useEmoji: false)

    func wrap(_ text: String, _ code: String) -> String {
        guard useColor else { return text }
        return "\(code)\(text)\(ANSI.reset)"
    }
}

enum ANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let fgCyan = "\u{001B}[36m"
    static let fgGreen = "\u{001B}[32m"
    static let fgYellow = "\u{001B}[33m"
    static let fgBlue = "\u{001B}[34m"
    static let fgMagenta = "\u{001B}[35m"
    static let fgWhite = "\u{001B}[37m"
}

/// Async-safe single-line progress bar written to stderr.
public actor CLIProgressBar {
    private let total: Int
    private let label: String
    private let width: Int
    private let theme: TUITheme
    private var completed: Int = 0
    private var animationTick: Int = 0
    private var finished = false

    public init(total: Int, label: String = "Jobs", width: Int = 28, theme: TUITheme = TerminalProgress.tuiTheme) {
        self.total = max(1, total)
        self.label = label
        self.width = max(8, width)
        self.theme = theme
    }

    public func advance(by amount: Int = 1) {
        guard !finished, amount > 0 else { return }
        completed = min(total, completed + amount)
        animationTick += 1
        render()
    }

    public func finish() {
        guard !finished else { return }
        finished = true
        completed = total
        render()
        if theme.useEmoji {
            fputs("\(theme.wrap("✅ Done", ANSI.fgGreen))\n", stderr)
        } else {
            fputs("\n", stderr)
        }
        fflush(stderr)
    }

    private func render() {
        let line = CLIProgressFormatting.overallLine(
            label: label,
            completed: completed,
            total: total,
            width: width,
            tick: animationTick,
            theme: theme,
            framed: false
        )
        fputs("\r\u{001B}[2K\(line)", stderr)
        fflush(stderr)
    }
}

/// Overall progress plus one live bar per consumer worker (cloud Ollama pool).
public actor CLIWorkerPoolProgress {
    private enum Slot: Sendable {
        case idle
        case working(jobNumber: Int, tick: Int)
    }

    private let total: Int
    private let workerCount: Int
    private let label: String
    private let overallWidth: Int
    private let workerBarWidth: Int
    private let theme: TUITheme
    private var completed: Int = 0
    private var slots: [Slot]
    private var animationTick: Int = 0
    private var finished = false
    private var previousLineCount = 0

    public init(
        total: Int,
        workerCount: Int,
        label: String = "Generations",
        overallWidth: Int = 24,
        workerBarWidth: Int = 16,
        theme: TUITheme = TerminalProgress.tuiTheme
    ) {
        self.total = max(1, total)
        self.workerCount = max(1, workerCount)
        self.label = label
        self.overallWidth = max(8, overallWidth)
        self.workerBarWidth = max(8, workerBarWidth)
        self.theme = theme
        self.slots = Array(repeating: .idle, count: self.workerCount)
    }

    public func beginJob(workerID: Int, jobNumber: Int) {
        guard !finished, workerID >= 0, workerID < workerCount else { return }
        slots[workerID] = .working(jobNumber: jobNumber, tick: animationTick)
        render()
    }

    public func completeJob(workerID: Int) {
        guard !finished, workerID >= 0, workerID < workerCount else { return }
        slots[workerID] = .idle
        completed = min(total, completed + 1)
        animationTick += 1
        render()
    }

    public func finish() {
        guard !finished else { return }
        finished = true
        completed = total
        slots = Array(repeating: .idle, count: workerCount)
        render()
        let doneLine = theme.useEmoji
            ? theme.wrap("✅ All generations complete", ANSI.fgGreen + ANSI.bold)
            : "Done."
        fputs("\(doneLine)\n", stderr)
        fflush(stderr)
    }

    private func render() {
        let lines = CLIProgressFormatting.workerPoolLines(
            label: label,
            completed: completed,
            total: total,
            overallWidth: overallWidth,
            workerCount: workerCount,
            workerBarWidth: workerBarWidth,
            tick: animationTick,
            theme: theme,
            slots: slots.map { slot in
                switch slot {
                case .idle:
                    return CLIProgressFormatting.WorkerSlot.idle
                case .working(let jobNumber, let tick):
                    return .working(jobNumber: jobNumber, tick: tick)
                }
            }
        )
        CLIProgressFormatting.writeMultiline(lines, previousLineCount: &previousLineCount)
    }
}

// MARK: - Formatting (testable)

enum CLIProgressFormatting {
    enum WorkerSlot: Equatable {
        case idle
        case working(jobNumber: Int, tick: Int)
    }

    /// Partial block glyphs (1/8 … 7/8) plus full and empty.
    private static let partialBlocks: [Character] = ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]
    private static let emptyBlock: Character = "░"
    private static let fullBlock: Character = "█"

    static func overallLine(
        label: String,
        completed: Int,
        total: Int,
        width: Int,
        tick: Int = 0,
        theme: TUITheme = .plain,
        framed: Bool = true
    ) -> String {
        let ratio = Double(completed) / Double(max(1, total))
        let bar = unicodeDeterminateBar(ratio: ratio, width: width, theme: theme)
        let pct = Int((ratio * 100).rounded())
        let emoji = theme.useEmoji ? "📊 " : ""
        let title = theme.wrap("\(emoji)\(label)", ANSI.bold + ANSI.fgCyan)
        let counts = theme.wrap("\(completed)/\(total)", ANSI.fgWhite)
        let percent = theme.wrap("(\(pct)%)", ANSI.fgGreen)
        let core = "\(title) \(boxAround(bar, theme: theme)) \(counts) \(percent)"
        if framed && theme.useEmoji {
            return "╭─ \(theme.wrap("☁️", ANSI.fgBlue)) \(core)"
        }
        return core
    }

    static func workerPoolLines(
        label: String,
        completed: Int,
        total: Int,
        overallWidth: Int,
        workerCount: Int,
        workerBarWidth: Int,
        tick: Int,
        theme: TUITheme,
        slots: [WorkerSlot]
    ) -> [String] {
        var lines: [String] = []
        lines.append(overallLine(
            label: label,
            completed: completed,
            total: total,
            width: overallWidth,
            tick: tick,
            theme: theme,
            framed: true
        ))
        let headerEmoji = theme.useEmoji ? "🧵 " : ""
        let header = "\(headerEmoji)\(workerCount) cloud worker(s)"
        lines.append(theme.wrap("├─ \(header)", ANSI.dim + ANSI.fgMagenta))

        for workerID in 0..<workerCount {
            let slot = workerID < slots.count ? slots[workerID] : .idle
            let id = String(format: "W%02d", workerID + 1)
            let workerLabel = theme.wrap(id, ANSI.bold + ANSI.fgYellow)

            switch slot {
            case .idle:
                let bar = unicodeDeterminateBar(ratio: 0, width: workerBarWidth, theme: theme)
                let stateEmoji = theme.useEmoji ? "💤 " : ""
                let state = theme.wrap("\(stateEmoji)idle", ANSI.dim)
                lines.append("│ \(workerLabel) \(boxAround(bar, theme: theme)) \(state)")
            case .working(let jobNumber, let slotTick):
                let bar = unicodeIndeterminateBar(tick: slotTick + tick, width: workerBarWidth, theme: theme)
                let stateEmoji = theme.useEmoji ? "⚡ " : ""
                let state = theme.wrap("\(stateEmoji)#\(jobNumber)", ANSI.fgYellow)
                lines.append("│ \(workerLabel) \(boxAround(bar, theme: theme)) \(state)")
            }
        }
        lines.append(theme.wrap("╰────────────────────────────────────", ANSI.dim + ANSI.fgCyan))
        return lines
    }

    static func boxAround(_ bar: String, theme: TUITheme) -> String {
        let inner = theme.wrap(bar, ANSI.fgGreen)
        if theme.useColor {
            return theme.wrap("▐", ANSI.fgCyan) + inner + theme.wrap("▌", ANSI.fgCyan)
        }
        return "[\(bar)]"
    }

    static func unicodeDeterminateBar(ratio: Double, width: Int, theme: TUITheme) -> String {
        guard width > 0 else { return "" }
        let clamped = min(1, max(0, ratio))
        let totalUnits = width * 8
        let filledUnits = Int(clamped * Double(totalUnits))
        var chars: [Character] = []
        chars.reserveCapacity(width)
        for index in 0..<width {
            let unitStart = index * 8
            let level = min(8, max(0, filledUnits - unitStart))
            switch level {
            case 8:
                chars.append(fullBlock)
            case 0:
                chars.append(emptyBlock)
            default:
                chars.append(partialBlocks[level - 1])
            }
        }
        let raw = String(chars)
        return theme.useColor ? raw : raw
    }

    static func unicodeIndeterminateBar(tick: Int, width: Int, theme: TUITheme) -> String {
        guard width > 0 else { return "" }
        var chars = Array(repeating: emptyBlock, count: width)
        let pulseLength = min(4, width)
        let origin = tick % (width + pulseLength)
        let pulseGlyphs: [Character] = theme.useEmoji
            ? [fullBlock, "▓", "▒", "░"]
            : [fullBlock, "▓", "▒", "░"]
        for offset in 0..<pulseLength {
            let index = origin - offset
            if index >= 0 && index < width {
                chars[index] = pulseGlyphs[min(offset, pulseGlyphs.count - 1)]
            }
        }
        // Trailing sparkle animation on leading edge
        let head = (origin + pulseLength - 1) % width
        if head >= 0 && head < width {
            chars[head] = theme.useEmoji ? "✨" as Character : fullBlock
        }
        return String(chars)
    }

    static func writeMultiline(_ lines: [String], previousLineCount: inout Int) {
        if previousLineCount > 0 {
            fputs("\u{001B}[\(previousLineCount)A", stderr)
        }
        for line in lines {
            fputs("\u{001B}[2K\r\(line)\n", stderr)
        }
        fflush(stderr)
        previousLineCount = lines.count
    }

    /// Strip ANSI escapes for stable test assertions.
    static func visibleText(_ string: String) -> String {
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            if string[index] == "\u{001B}", let end = string[index...].range(of: "m")?.upperBound {
                index = end
                continue
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        return result
    }
}

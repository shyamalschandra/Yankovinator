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

    /// Terminal width for stderr (used to size the status rail).
    public static var columns: Int {
        var size = winsize()
        #if canImport(Darwin)
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        #endif
        return 100
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

// MARK: - Async coalesced redraw

/// Coalesces rapid progress events into ~30fps redraws (avoids tearing / lost text).
private actor CLITUIRefreshLoop {
    private var generation: UInt64 = 0
    private var redraw: (@Sendable () async -> Void)?

    func setRedrawHandler(_ handler: @escaping @Sendable () async -> Void) {
        redraw = handler
    }

    func scheduleRedraw() {
        generation &+= 1
        let token = generation
        Task {
            try? await Task.sleep(nanoseconds: 35_000_000)
            await self.flushIfLatest(token: token)
        }
    }

    private func flushIfLatest(token: UInt64) async {
        guard token == generation else { return }
        await redraw?()
    }

    func cancelPending() {
        generation &+= 1
    }
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
    private var latestStatus: String = ""
    private let refresh = CLITUIRefreshLoop()
    private let midi: CLIProgressMIDISoundboard?
    private let usesNcurses: Bool

    public init(
        total: Int,
        label: String = "Jobs",
        width: Int = 28,
        theme: TUITheme = TerminalProgress.tuiTheme,
        enableMIDI: Bool = false
    ) {
        self.total = max(1, total)
        self.label = label
        self.width = max(8, width)
        self.theme = theme
        self.midi = enableMIDI && TerminalProgress.isInteractive ? CLIProgressMIDISoundboard.shared : nil
        self.usesNcurses = TerminalProgress.isInteractive && NcursesProgressScreen.acquire()
        Task { await refresh.setRedrawHandler { [weak self] in await self?.renderNow() } }
    }

    public func postMessage(_ message: String) {
        guard !message.isEmpty else { return }
        latestStatus = message
        Task { await refresh.scheduleRedraw() }
    }

    public func advance(by amount: Int = 1) {
        guard !finished, amount > 0 else { return }
        completed = min(total, completed + amount)
        animationTick += 1
        if let midi {
            let done = completed
            Task { await midi.playOverallMilestone(completed: done, total: total) }
        }
        Task { await refresh.scheduleRedraw() }
    }

    public func finish() async {
        guard !finished else { return }
        finished = true
        completed = total
        await refresh.cancelPending()
        renderNow()
        if let midi {
            await midi.playBatchComplete(workerCount: 1)
            await midi.shutdown()
        }
        if usesNcurses {
            NcursesProgressScreen.release()
        }
        if theme.useEmoji {
            fputs("\(theme.wrap("✅ Done", ANSI.fgGreen))\n", stderr)
        } else {
            fputs("\n", stderr)
        }
        fflush(stderr)
    }

    private func renderNow() {
        let line = CLIProgressFormatting.overallLine(
            label: label,
            completed: completed,
            total: total,
            width: width,
            tick: animationTick,
            theme: theme,
            framed: false,
            statusRail: latestStatus
        )
        if usesNcurses {
            _ = NcursesProgressScreen.render(lines: [line])
        } else {
            fputs("\r\u{001B}[2K\(line)", stderr)
            fflush(stderr)
        }
    }
}

/// Overall progress plus one live bar per consumer worker (cloud Ollama pool).
public actor CLIWorkerPoolProgress {
    private enum Slot: Sendable {
        case idle
        case working(jobNumber: Int, tick: Int, startedAt: Date, line: Int?, lineTotal: Int?)
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
    private var latestStatus: String = ""
    private var statusHistory: [String] = []
    private var workerBusySeconds: [TimeInterval]
    private var averageJobSeconds: TimeInterval?
    private let batchStartedAt: Date
    private let refresh = CLITUIRefreshLoop()
    private var animationTask: Task<Void, Never>?
    private let midi: CLIProgressMIDISoundboard?
    private let usesNcurses: Bool

    public init(
        total: Int,
        workerCount: Int,
        label: String = "Generations",
        overallWidth: Int = 24,
        workerBarWidth: Int = 16,
        theme: TUITheme = TerminalProgress.tuiTheme,
        enableMIDI: Bool = false
    ) {
        self.total = max(1, total)
        self.workerCount = max(1, workerCount)
        self.label = label
        self.overallWidth = max(8, overallWidth)
        self.workerBarWidth = max(8, workerBarWidth)
        self.theme = theme
        self.slots = Array(repeating: .idle, count: self.workerCount)
        self.workerBusySeconds = Array(repeating: 0, count: self.workerCount)
        self.batchStartedAt = Date()
        self.midi = enableMIDI && TerminalProgress.isInteractive ? CLIProgressMIDISoundboard.shared : nil
        self.usesNcurses = TerminalProgress.isInteractive && NcursesProgressScreen.acquire()

        if TerminalProgress.isInteractive {
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await self?.animationHeartbeat()
                }
            }
        }
        Task { await refresh.setRedrawHandler { [weak self] in await self?.renderNow() } }
    }

    /// Append a status line (retained in memory; shown on the right rail + feed line).
    public func postMessage(_ message: String) {
        guard !message.isEmpty else { return }
        statusHistory.append(message)
        if statusHistory.count > 500 {
            statusHistory.removeFirst(statusHistory.count - 500)
        }
        latestStatus = message
        Task { await refresh.scheduleRedraw() }
    }

    public func beginJob(workerID: Int, jobNumber: Int) {
        guard !finished, workerID >= 0, workerID < workerCount else { return }
        slots[workerID] = .working(jobNumber: jobNumber, tick: animationTick, startedAt: Date(), line: nil, lineTotal: nil)
        if let midi {
            Task { await midi.playWorkerStart(workerID: workerID) }
        }
        Task { await refresh.scheduleRedraw() }
    }

    /// Live line counter while a worker generates a song (cheap TUI update, coalesced redraw).
    public func postWorkerLineProgress(workerID: Int, line: Int, total: Int) {
        guard !finished, workerID >= 0, workerID < workerCount else { return }
        guard case .working(let jobNumber, let tick, let startedAt, let prevLine, let prevTotal) = slots[workerID] else {
            return
        }
        if prevLine == line, prevTotal == total { return }
        slots[workerID] = .working(
            jobNumber: jobNumber,
            tick: tick,
            startedAt: startedAt,
            line: line,
            lineTotal: total
        )
        Task { await refresh.scheduleRedraw() }
    }

    public func completeJob(workerID: Int) {
        guard !finished, workerID >= 0, workerID < workerCount else { return }
        if case .working(_, _, let startedAt, _, _) = slots[workerID] {
            recordJobFinished(workerID: workerID, duration: Date().timeIntervalSince(startedAt))
        }
        slots[workerID] = .idle
        completed = min(total, completed + 1)
        animationTick += 1
        if let midi {
            let done = completed
            Task { await midi.playWorkerComplete(workerID: workerID) }
            Task { await midi.playOverallMilestone(completed: done, total: total) }
        }
        Task { await refresh.scheduleRedraw() }
    }

    private func recordJobFinished(workerID: Int, duration: TimeInterval) {
        let clamped = max(0, duration)
        workerBusySeconds[workerID] += clamped
        if let averageJobSeconds {
            self.averageJobSeconds = averageJobSeconds * 0.75 + clamped * 0.25
        } else {
            averageJobSeconds = clamped
        }
    }

    public func finish() async {
        guard !finished else { return }
        finished = true
        animationTask?.cancel()
        animationTask = nil
        completed = total
        slots = Array(repeating: .idle, count: workerCount)
        await refresh.cancelPending()
        renderNow()
        if let midi {
            await midi.playBatchComplete(workerCount: workerCount)
            await midi.shutdown()
        }
        if usesNcurses {
            NcursesProgressScreen.release()
        }
        let doneLine = theme.useEmoji
            ? theme.wrap("✅ All generations complete", ANSI.fgGreen + ANSI.bold)
            : "Done."
        fputs("\(doneLine)\n", stderr)
        fflush(stderr)
    }

    private func animationHeartbeat() {
        guard !finished else { return }
        var workingIDs: [Int] = []
        for (workerID, slot) in slots.enumerated() {
            if case .working = slot { workingIDs.append(workerID) }
        }
        guard !workingIDs.isEmpty else { return }
        animationTick &+= 1
        if let midi {
            let tick = animationTick
            for workerID in workingIDs {
                Task { await midi.playWorkerPulse(workerID: workerID, globalTick: tick) }
            }
        }
        Task { await refresh.scheduleRedraw() }
    }

    private func renderNow() {
        let now = Date()
        let formattedSlots: [CLIProgressFormatting.WorkerSlot] = (0..<workerCount).map { workerID in
            let slot = workerID < slots.count ? slots[workerID] : .idle
            let spent = spentSeconds(workerID: workerID, slot: slot, now: now)
            let remaining = estimatedRemainingSeconds(workerID: workerID, slot: slot, now: now)
            switch slot {
            case .idle:
                return .idle(spentSeconds: spent, etaSeconds: remaining)
            case .working(let jobNumber, let tick, _, let line, let lineTotal):
                return .working(
                    jobNumber: jobNumber,
                    tick: tick,
                    spentSeconds: spent,
                    etaSeconds: remaining,
                    line: line,
                    lineTotal: lineTotal
                )
            }
        }

        let batchSpent = now.timeIntervalSince(batchStartedAt)
        let batchETA = estimatedBatchRemaining(now: now)

        let lines = CLIProgressFormatting.workerPoolLines(
            label: label,
            completed: completed,
            total: total,
            overallWidth: overallWidth,
            workerCount: workerCount,
            workerBarWidth: workerBarWidth,
            tick: animationTick,
            theme: theme,
            statusRail: latestStatus,
            recentMessages: Array(statusHistory.suffix(2)),
            batchSpentSeconds: batchSpent,
            batchEtaSeconds: batchETA,
            slots: formattedSlots
        )
        CLIProgressFormatting.writeMultiline(lines, previousLineCount: &previousLineCount, useNcurses: usesNcurses)
    }

    private func spentSeconds(workerID: Int, slot: Slot, now: Date) -> TimeInterval {
        var total = workerBusySeconds[workerID]
        if case .working(_, _, let startedAt, _, _) = slot {
            total += max(0, now.timeIntervalSince(startedAt))
        }
        return total
    }

    private func estimatedRemainingSeconds(workerID: Int, slot: Slot, now: Date) -> TimeInterval? {
        _ = workerID
        let jobsLeft = max(0, total - completed)
        guard jobsLeft > 0 else { return 0 }
        guard let avg = averageJobSeconds else { return nil }

        let queueShare = (Double(jobsLeft) / Double(workerCount)) * avg

        switch slot {
        case .idle:
            return queueShare
        case .working(_, _, let startedAt, _, _):
            let elapsed = max(0, now.timeIntervalSince(startedAt))
            let currentJobLeft = max(0, avg - elapsed)
            let futureJobs = max(0, Double(jobsLeft - 1) / Double(workerCount)) * avg
            return currentJobLeft + futureJobs
        }
    }

    private func estimatedBatchRemaining(now: Date) -> TimeInterval? {
        let jobsLeft = max(0, total - completed)
        guard jobsLeft > 0, let avg = averageJobSeconds else { return nil }
        let active = max(1, slots.filter {
            if case .working = $0 { return true }
            return false
        }.count)
        return (Double(jobsLeft) / Double(active)) * avg
    }
}

// MARK: - Formatting (testable)

enum CLIProgressFormatting {
    enum WorkerSlot: Equatable {
        case idle(spentSeconds: TimeInterval, etaSeconds: TimeInterval?)
        case working(
            jobNumber: Int,
            tick: Int,
            spentSeconds: TimeInterval,
            etaSeconds: TimeInterval?,
            line: Int? = nil,
            lineTotal: Int? = nil
        )
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 1 { return "<1s" }
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let secs = total % 60
        if minutes < 60 { return "\(minutes)m\(String(format: "%02d", secs))s" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h\(String(format: "%02d", mins))m"
    }

    static func formatETA(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "…" }
        if seconds <= 0 { return "0s" }
        return "~\(formatDuration(seconds))"
    }

    static func workerTimingLabel(spent: TimeInterval, eta: TimeInterval?, theme: TUITheme) -> String {
        let spentEmoji = theme.useEmoji ? "⏱ " : "spent "
        let etaEmoji = theme.useEmoji ? "⌛ " : "ETA "
        let spentText = theme.wrap("\(spentEmoji)\(formatDuration(spent))", ANSI.fgWhite)
        let etaText = theme.wrap("\(etaEmoji)\(formatETA(eta))", ANSI.fgGreen)
        return "\(spentText) \(etaText)"
    }

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
        framed: Bool = true,
        statusRail: String = ""
    ) -> String {
        let ratio = Double(completed) / Double(max(1, total))
        let bar = unicodeDeterminateBar(ratio: ratio, width: width, theme: theme)
        let pct = Int((ratio * 100).rounded())
        let emoji = theme.useEmoji ? "📊 " : ""
        let title = theme.wrap("\(emoji)\(label)", ANSI.bold + ANSI.fgCyan)
        let counts = theme.wrap("\(completed)/\(total)", ANSI.fgWhite)
        let percent = theme.wrap("(\(pct)%)", ANSI.fgGreen)
        var core = "\(title) \(boxAround(bar, theme: theme)) \(counts) \(percent)"
        if framed && theme.useEmoji {
            core = "╭─ \(theme.wrap("☁️", ANSI.fgBlue)) \(core)"
        }
        return appendStatusRail(to: core, statusRail: statusRail, theme: theme)
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
        statusRail: String = "",
        recentMessages: [String] = [],
        batchSpentSeconds: TimeInterval = 0,
        batchEtaSeconds: TimeInterval? = nil,
        slots: [WorkerSlot]
    ) -> [String] {
        var lines: [String] = []
        let batchTiming = theme.useEmoji
            ? theme.wrap(
                "⏱ \(formatDuration(batchSpentSeconds))  ⌛ \(formatETA(batchEtaSeconds))",
                ANSI.dim + ANSI.fgCyan
            )
            : theme.wrap(
                "spent \(formatDuration(batchSpentSeconds))  ETA \(formatETA(batchEtaSeconds))",
                ANSI.dim + ANSI.fgCyan
            )
        let overallRail = statusRail.isEmpty ? batchTiming : "\(statusRail)  ·  \(batchTiming)"
        lines.append(overallLine(
            label: label,
            completed: completed,
            total: total,
            width: overallWidth,
            tick: tick,
            theme: theme,
            framed: true,
            statusRail: overallRail
        ))

        if !recentMessages.isEmpty {
            for (offset, message) in recentMessages.enumerated().reversed() {
                let prefix = offset == 0
                    ? (theme.useEmoji ? "├─ 💬 " : "├─ ")
                    : (theme.useEmoji ? "│    ↳ " : "│    ")
                let styled = theme.wrap(truncate(message, maxVisible: 72), offset == 0 ? ANSI.fgWhite : ANSI.dim)
                lines.append("\(prefix)\(styled)")
            }
        } else {
            let headerEmoji = theme.useEmoji ? "🧵 " : ""
            let header = "\(headerEmoji)\(workerCount) cloud worker(s)"
            lines.append(theme.wrap("├─ \(header)", ANSI.dim + ANSI.fgMagenta))
        }

        for workerID in 0..<workerCount {
            let slot = workerID < slots.count ? slots[workerID] : .idle(spentSeconds: 0, etaSeconds: nil)
            let id = String(format: "W%02d", workerID + 1)
            let workerLabel = theme.wrap(id, ANSI.bold + ANSI.fgYellow)

            switch slot {
            case .idle(let spent, let eta):
                let bar = unicodeDeterminateBar(ratio: 0, width: workerBarWidth, theme: theme)
                let stateEmoji = theme.useEmoji ? "💤 " : ""
                let state = theme.wrap("\(stateEmoji)idle", ANSI.dim)
                let timing = workerTimingLabel(spent: spent, eta: eta, theme: theme)
                lines.append("│ \(workerLabel) \(boxAround(bar, theme: theme)) \(state)  \(timing)")
            case .working(let jobNumber, let slotTick, let spent, let eta, let line, let lineTotal):
                let bar = unicodeIndeterminateBar(tick: slotTick + tick, width: workerBarWidth, theme: theme)
                let stateEmoji = theme.useEmoji ? "⚡ " : ""
                var state = theme.wrap("\(stateEmoji)#\(jobNumber)", ANSI.fgYellow)
                if let line, let lineTotal, lineTotal > 0 {
                    let lineLabel = theme.wrap(" L\(line)/\(lineTotal)", ANSI.fgCyan)
                    state += lineLabel
                }
                let timing = workerTimingLabel(spent: spent, eta: eta, theme: theme)
                lines.append("│ \(workerLabel) \(boxAround(bar, theme: theme)) \(state)  \(timing)")
            }
        }
        lines.append(theme.wrap("╰────────────────────────────────────", ANSI.dim + ANSI.fgCyan))
        return lines
    }

    static func appendStatusRail(to line: String, statusRail: String, theme: TUITheme) -> String {
        guard !statusRail.isEmpty else { return line }
        let sep = theme.wrap(" │ ", ANSI.dim + ANSI.fgCyan)
        let prefix = theme.useEmoji ? "💬 " : ""
        let visibleLeft = visibleText(line).count
        let columns = TerminalProgress.columns
        let maxRail = max(12, columns - visibleLeft - visibleText(sep).count - 2)
        let body = truncate("\(prefix)\(statusRail)", maxVisible: maxRail)
        return line + sep + theme.wrap(body, ANSI.fgYellow)
    }

    static func truncate(_ text: String, maxVisible: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxVisible > 1, trimmed.count > maxVisible else { return trimmed }
        return String(trimmed.prefix(max(1, maxVisible - 1))) + "…"
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
        return String(chars)
    }

    static func unicodeIndeterminateBar(tick: Int, width: Int, theme: TUITheme) -> String {
        guard width > 0 else { return "" }
        var chars = Array(repeating: emptyBlock, count: width)
        let pulseLength = min(4, width)
        let origin = tick % (width + pulseLength)
        let pulseGlyphs: [Character] = [fullBlock, "▓", "▒", "░"]
        for offset in 0..<pulseLength {
            let index = origin - offset
            if index >= 0 && index < width {
                chars[index] = pulseGlyphs[min(offset, pulseGlyphs.count - 1)]
            }
        }
        let head = (origin + pulseLength - 1) % width
        if head >= 0 && head < width {
            chars[head] = theme.useEmoji ? "✨" as Character : fullBlock
        }
        return String(chars)
    }

    static func writeMultiline(_ lines: [String], previousLineCount: inout Int, useNcurses: Bool = false) {
        if useNcurses, NcursesProgressScreen.render(lines: lines) {
            previousLineCount = lines.count
            return
        }

        if previousLineCount > 0 {
            fputs("\u{001B}[\(previousLineCount)A", stderr)
        }
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            fputs("\u{001B}[2K\r\(line)", stderr)
            if !isLast {
                fputs("\n", stderr)
            }
        }
        fflush(stderr)
        previousLineCount = lines.count
    }

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

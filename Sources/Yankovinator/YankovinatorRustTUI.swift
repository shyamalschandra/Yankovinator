// Copyright (C) 2025, Shyamal Suhana Chandra
// Rust ratatui sidecar for batch progress (UTF-8 / emoji / color without Swift terminal races).

import Foundation

/// Locates and drives `yankovinator-tui` (built from `tui/`).
public enum YankovinatorRustTUI {
    /// When `false`, never spawn the Rust TUI (Swift stderr fallback only).
    public static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["YANKOVINATOR_RUST_TUI"] == "0" { return false }
        return true
    }

    public static func locateExecutable() -> String? {
        if let override = ProcessInfo.processInfo.environment["YANKOVINATOR_TUI_PATH"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let argv0 = CommandLine.arguments[0]
        let binDir = (argv0 as NSString).deletingLastPathComponent
        let sibling = (binDir as NSString).appendingPathComponent("yankovinator-tui")
        if FileManager.default.isExecutableFile(atPath: sibling) {
            return sibling
        }
        let cwdRelative = FileManager.default.currentDirectoryPath + "/.build/debug/yankovinator-tui"
        if FileManager.default.isExecutableFile(atPath: cwdRelative) {
            return cwdRelative
        }
        let releaseRelative = FileManager.default.currentDirectoryPath + "/.build/release/yankovinator-tui"
        if FileManager.default.isExecutableFile(atPath: releaseRelative) {
            return releaseRelative
        }
        let tuiCrate = FileManager.default.currentDirectoryPath + "/tui/target/debug/yankovinator-tui"
        if FileManager.default.isExecutableFile(atPath: tuiCrate) {
            return tuiCrate
        }
        let tuiRelease = FileManager.default.currentDirectoryPath + "/tui/target/release/yankovinator-tui"
        if FileManager.default.isExecutableFile(atPath: tuiRelease) {
            return tuiRelease
        }
        return nil
    }
}

struct RustTUIWorkerSnap: Encodable {
    var idle: Bool
    var job_number: UInt32
    var line: UInt32?
    var line_total: UInt32?
    var spent_secs: Double
    var eta_secs: Double?
    var slot_tick: UInt32
}

private struct RustTUIInitEvent: Encodable {
    let t = "init"
    let total: UInt32
    let workers: UInt32
    let label: String
}

public struct RustTUISnapshot: Encodable {
    let t = "snapshot"
    let completed: UInt32
    let tick: UInt64
    let batch_spent_secs: Double
    let batch_eta_secs: Double?
    let status: String
    let messages: [String]
    let workers: [RustTUIWorkerSnap]
}

private struct RustTUIQuitEvent: Encodable {
    let t = "quit"
}

/// Child process + stdin pipe; process starts on first `initialize` (after MIDI prewarm).
public actor RustTUIProcess {
    private let executablePath: String
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var started = false
    private var closed = false

    public init?(executablePath: String) {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { return nil }
        self.executablePath = executablePath
    }

    public func initialize(total: Int, workers: Int, label: String) throws {
        guard !started, !closed else { return }
        try launchIfNeeded()
        started = true
        try sendInit(total: total, workers: workers, label: label)
    }

    public func sendSnapshot(_ snap: RustTUISnapshot) throws {
        guard !closed else { return }
        if !started {
            try launchIfNeeded()
            started = true
        }
        try writeJSON(snap)
    }

    public func shutdown() {
        guard !closed else { return }
        closed = true
        try? writeJSON(RustTUIQuitEvent())
        try? stdinHandle?.close()
        if let process, process.isRunning {
            process.waitUntilExit()
        }
        process = nil
        stdinHandle = nil
    }

    private func launchIfNeeded() throws {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        process.environment = env
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = nil
        try process.run()
        self.process = process
        self.stdinHandle = pipe.fileHandleForWriting
    }

    private func sendInit(total: Int, workers: Int, label: String) throws {
        try writeJSON(
            RustTUIInitEvent(
                total: UInt32(max(1, total)),
                workers: UInt32(max(1, workers)),
                label: label
            )
        )
    }

    private func writeJSON<T: Encodable>(_ value: T) throws {
        guard let stdinHandle else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)
    }
}

/// While active, non-TUI stderr writes are suppressed (they corrupt alternate-screen UIs).
public enum StderrGate {
    private static let lock = NSLock()
    private static var suppressPlainStderr = false

    public static func setRustTUIActive(_ active: Bool) {
        lock.lock()
        suppressPlainStderr = active
        lock.unlock()
    }

    public static func writeLine(_ string: String) {
        lock.lock()
        let suppress = suppressPlainStderr
        lock.unlock()
        guard !suppress else { return }
        fputs(string.hasSuffix("\n") ? string : string + "\n", stderr)
        fflush(stderr)
    }
}

extension RustTUISnapshot {
    static func fromWorkerPool(
        label: String,
        completed: Int,
        total: Int,
        tick: Int,
        status: String,
        messages: [String],
        batchSpent: TimeInterval,
        batchETA: TimeInterval?,
        slots: [CLIProgressFormatting.WorkerSlot]
    ) -> RustTUISnapshot {
        let workers: [RustTUIWorkerSnap] = slots.map { slot in
            switch slot {
            case .idle(let spent, let eta):
                return RustTUIWorkerSnap(
                    idle: true,
                    job_number: 0,
                    line: nil,
                    line_total: nil,
                    spent_secs: spent,
                    eta_secs: eta,
                    slot_tick: 0
                )
            case .working(let jobNumber, let slotTick, let spent, let eta, let line, let lineTotal):
                return RustTUIWorkerSnap(
                    idle: false,
                    job_number: UInt32(jobNumber),
                    line: line.map { UInt32($0) },
                    line_total: lineTotal.map { UInt32($0) },
                    spent_secs: spent,
                    eta_secs: eta,
                    slot_tick: UInt32(slotTick)
                )
            }
        }
        return RustTUISnapshot(
            completed: UInt32(completed),
            tick: UInt64(max(0, tick)),
            batch_spent_secs: batchSpent,
            batch_eta_secs: batchETA,
            status: status,
            messages: messages,
            workers: workers
        )
    }
}

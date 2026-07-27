// Copyright (C) 2025, Shyamal Suhana Chandra
// Optional lightweight MIDI cues for worker progress bars (macOS only)

import Foundation

/// Pure note/program mapping (testable, no audio I/O).
public enum CLIProgressMIDINotes {
    /// General MIDI melodic programs — one per worker slot for timbral variety.
    public static let workerPrograms: [UInt8] = [0, 4, 5, 9, 11, 12, 24, 40, 46, 56]

    public static func workerProgram(workerID: Int) -> UInt8 {
        workerPrograms[workerID % workerPrograms.count]
    }

    public static func workerChannel(workerID: Int) -> UInt8 {
        UInt8(workerID % 16)
    }

    public static func startNote(workerID: Int) -> UInt8 {
        UInt8(60 + (workerID % 12) * 2)
    }

    public static func pulseNote(workerID: Int, globalTick: Int) -> UInt8 {
        let pentatonic: [UInt8] = [0, 2, 4, 7, 9]
        let degree = (globalTick / 12 + workerID) % pentatonic.count
        let octave = (workerID / pentatonic.count) % 2
        return UInt8(64 + Int(pentatonic[degree]) + octave * 12)
    }

    public static func completeNote(workerID: Int) -> UInt8 {
        UInt8(72 + (workerID % 8))
    }

    public static func batchCompleteNotes(workerCount: Int) -> [UInt8] {
        let base: [UInt8] = [60, 64, 67, 72]
        return (0..<min(workerCount, 4)).map { base[$0] + UInt8($0 % 2) * 12 }
    }

    /// Gate indeterminate-bar pulses (~1.4s at 120ms heartbeat when all workers align).
    public static func shouldPulse(workerID: Int, globalTick: Int) -> Bool {
        (globalTick + workerID * 5) % 12 == 0
    }
}

#if os(macOS)
import AVFoundation

/// AVAudioEngine must run on the main thread; keep all sampler I/O here.
@MainActor
final class CLIProgressMIDIEngine {
    static let shared = CLIProgressMIDIEngine()

    private var sampler: AVAudioUnitSampler?
    private var engine: AVAudioEngine?
    private var isReady = false
    private var noteGeneration: UInt64 = 0

    private let dlsPath =
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"

    private init() {}

    func prewarm() {
        ensureReady()
    }

    func play(
        workerID: Int,
        note: UInt8,
        velocity: UInt8,
        durationMs: Int,
        useWorkerProgram: Bool
    ) {
        ensureReady()
        guard isReady, let sampler else { return }
        noteGeneration &+= 1
        let generation = noteGeneration
        let channel = CLIProgressMIDINotes.workerChannel(workerID: workerID)
        if useWorkerProgram {
            let program = CLIProgressMIDINotes.workerProgram(workerID: workerID)
            sampler.sendProgramChange(
                program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                onChannel: channel
            )
        }
        sampler.startNote(note, withVelocity: velocity, onChannel: channel)
        let stopNote = note
        let stopChannel = channel
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)
            guard generation == self.noteGeneration, self.isReady, let sampler = self.sampler else { return }
            sampler.stopNote(stopNote, onChannel: stopChannel)
        }
    }

    func playBatchComplete(workerCount: Int) {
        ensureReady()
        guard isReady, let sampler else { return }
        let notes = CLIProgressMIDINotes.batchCompleteNotes(workerCount: workerCount)
        for (index, note) in notes.enumerated() {
            let channel = UInt8(index)
            sampler.sendProgramChange(
                0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                onChannel: channel
            )
            sampler.startNote(note, withVelocity: 92, onChannel: channel)
            let n = note
            let ch = channel
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard self.isReady, let sampler = self.sampler else { return }
                sampler.stopNote(n, onChannel: ch)
            }
        }
    }

    func shutdown() {
        noteGeneration &+= 1
        engine?.stop()
        engine = nil
        sampler = nil
        isReady = false
    }

    private func ensureReady() {
        guard !isReady else { return }
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.28
        let url = URL(fileURLWithPath: dlsPath)
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: CLIProgressMIDINotes.workerPrograms[0],
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            try engine.start()
            self.engine = engine
            self.sampler = sampler
            isReady = true
        } catch {
            isReady = false
        }
    }
}

/// Shared DLS synth; lazy start; notes scheduled on the main actor.
public actor CLIProgressMIDISoundboard {
    public static let shared = CLIProgressMIDISoundboard()

    private var lastPulseTick: [Int: Int] = [:]
    private var lastOverallMilestone = -1
    private var isShutdown = false

    private init() {}

    public func prewarm() async {
        guard !isShutdown else { return }
        await MainActor.run {
            CLIProgressMIDIEngine.shared.prewarm()
        }
    }

    public func playWorkerStart(workerID: Int) async {
        guard !isShutdown else { return }
        await MainActor.run {
            CLIProgressMIDIEngine.shared.play(
                workerID: workerID,
                note: CLIProgressMIDINotes.startNote(workerID: workerID),
                velocity: 88,
                durationMs: 110,
                useWorkerProgram: true
            )
        }
    }

    public func playWorkerPulse(workerID: Int, globalTick: Int) async {
        guard !isShutdown else { return }
        guard CLIProgressMIDINotes.shouldPulse(workerID: workerID, globalTick: globalTick) else { return }
        if lastPulseTick[workerID] == globalTick { return }
        lastPulseTick[workerID] = globalTick
        await MainActor.run {
            CLIProgressMIDIEngine.shared.play(
                workerID: workerID,
                note: CLIProgressMIDINotes.pulseNote(workerID: workerID, globalTick: globalTick),
                velocity: 42,
                durationMs: 55,
                useWorkerProgram: false
            )
        }
    }

    public func playWorkerComplete(workerID: Int) async {
        guard !isShutdown else { return }
        await MainActor.run {
            CLIProgressMIDIEngine.shared.play(
                workerID: workerID,
                note: CLIProgressMIDINotes.completeNote(workerID: workerID),
                velocity: 76,
                durationMs: 140,
                useWorkerProgram: true
            )
        }
    }

    public func playBatchComplete(workerCount: Int) async {
        guard !isShutdown else { return }
        await MainActor.run {
            CLIProgressMIDIEngine.shared.playBatchComplete(workerCount: workerCount)
        }
    }

    public func playOverallMilestone(completed: Int, total: Int) async {
        guard !isShutdown, total > 0 else { return }
        let milestone = (completed * 10) / total
        guard milestone > lastOverallMilestone, completed > 0 else { return }
        lastOverallMilestone = milestone
        await MainActor.run {
            CLIProgressMIDIEngine.shared.play(
                workerID: 0,
                note: UInt8(48 + milestone * 2),
                velocity: 50,
                durationMs: 70,
                useWorkerProgram: false
            )
        }
    }

    public func shutdown() async {
        isShutdown = true
        await MainActor.run {
            CLIProgressMIDIEngine.shared.shutdown()
        }
    }
}

#else

public actor CLIProgressMIDISoundboard {
    public static let shared = CLIProgressMIDISoundboard()
    public func prewarm() async {}
    public func playWorkerStart(workerID: Int) async {}
    public func playWorkerPulse(workerID: Int, globalTick: Int) async {}
    public func playWorkerComplete(workerID: Int) async {}
    public func playBatchComplete(workerCount: Int) async {}
    public func playOverallMilestone(completed: Int, total: Int) async {}
    public func shutdown() async {}
}

#endif

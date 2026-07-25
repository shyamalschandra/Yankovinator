// Copyright (C) 2025, Shyamal Suhana Chandra
// Auto-tuning for large cloud Ollama models (avoids 10× queue stalls)

import Foundation

/// Recommended runtime adjustments when batching against heavy `:cloud` models.
public enum CloudBatchPrescription: Sendable {
    /// Max concurrent consumer workers for heavy cloud models (client-side cap; model may be fast).
    public static let heavyCloudMaxConsumers = 4

    /// Per-request timeout when CLI did not pass `--ollama-timeout`.
    public static let heavyCloudTimeoutSeconds = 600

    public struct Plan: Sendable {
        public let requestedWorkers: Int
        public let effectiveWorkers: Int
        public let appliedWorkerCap: Bool
        public let appliedTimeoutSeconds: Int?
        public let skipLLMCoherenceInBatch: Bool
        public let batchRefinementPasses: Int
        public let enableCoherenceRegeneration: Bool
        public let incrementalCheckpoints: Bool
        public let messages: [String]
    }

    public static func isHeavyCloudModel(_ model: String) -> Bool {
        let m = model.lowercased()
        guard m.contains("cloud") else { return false }
        if m.contains("397") || m.contains("405") || m.contains("340") || m.contains("235") {
            return true
        }
        if m.contains("qwen3") || m.contains("qwen3.5") { return true }
        return false
    }

    public static func plan(
        model: String,
        requestedWorkers: Int,
        ollamaTimeout: Int?,
        enabled: Bool
    ) -> Plan {
        let clamped = ParallelJobRunner.clampWorkers(requestedWorkers)
        guard enabled, isHeavyCloudModel(model) else {
            return Plan(
                requestedWorkers: clamped,
                effectiveWorkers: clamped,
                appliedWorkerCap: false,
                appliedTimeoutSeconds: nil,
                skipLLMCoherenceInBatch: false,
                batchRefinementPasses: 2,
                enableCoherenceRegeneration: true,
                incrementalCheckpoints: false,
                messages: []
            )
        }

        let capped = min(clamped, heavyCloudMaxConsumers)
        let appliedCap = capped < clamped
        var messages: [String] = []
        if appliedCap {
            messages.append(
                "Rx: Cap workers \(clamped)→\(capped) — limits parallel in-flight HTTP jobs (not model speed). Use --no-cloud-prescription for \(clamped)."
            )
        }

        var appliedTimeout: Int?
        if ollamaTimeout == nil {
            appliedTimeout = heavyCloudTimeoutSeconds
            messages.append(
                "Rx: Ollama timeout \(heavyCloudTimeoutSeconds)s for heavy cloud model (or set --ollama-timeout)."
            )
        }

        messages.append(
            "Rx: One generate call per lyric line in batch (refinement/coherence LLM loops off); checkpoints after each candidate."
        )

        return Plan(
            requestedWorkers: clamped,
            effectiveWorkers: capped,
            appliedWorkerCap: appliedCap,
            appliedTimeoutSeconds: appliedTimeout,
            skipLLMCoherenceInBatch: true,
            batchRefinementPasses: 0,
            enableCoherenceRegeneration: false,
            incrementalCheckpoints: true,
            messages: messages
        )
    }

    public static func printPlan(_ plan: Plan) {
        guard !plan.messages.isEmpty else { return }
        for line in plan.messages {
            fputs("ℹ️  \(line)\n", stderr)
        }
        fflush(stderr)
    }
}

/// Current producer-consumer worker slot (for line-level TUI + progress).
public enum WorkerJobContext {
    public struct State: Sendable {
        public let workerID: Int
        public let jobNumber: Int
    }

    @TaskLocal public static var current: State?
}

// Copyright (C) 2025, Shyamal Suhana Chandra
// Auto-tuning for cloud Ollama models (rate limits, connection exhaustion)

import Foundation

/// Recommended runtime adjustments when batching against `:cloud` models.
public enum CloudBatchPrescription: Sendable {
    /// Soft max concurrent consumer workers for any `:cloud` model (rate-limit safe default).
    public static let cloudMaxConsumers = 4

    /// Soft max for very large `:cloud` models (still conservative vs. prior 64).
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

    public static func isCloudModel(_ model: String) -> Bool {
        model.lowercased().contains("cloud")
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

    /// Effective consumer cap for a cloud model under prescription.
    public static func maxConsumers(for model: String) -> Int {
        isHeavyCloudModel(model) ? heavyCloudMaxConsumers : cloudMaxConsumers
    }

    public static func plan(
        model: String,
        requestedWorkers: Int,
        ollamaTimeout: Int?,
        enabled: Bool
    ) -> Plan {
        let clamped = ParallelJobRunner.clampWorkers(requestedWorkers)
        guard enabled, isCloudModel(model) else {
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

        let cap = maxConsumers(for: model)
        let capped = min(clamped, cap)
        let appliedCap = capped < clamped
        let heavy = isHeavyCloudModel(model)
        var messages: [String] = []
        if appliedCap {
            messages.append(
                "Rx: Cap workers \(clamped)→\(capped) for :cloud rate limits (avoids 429 / port exhaustion). Use --no-cloud-prescription for \(clamped)."
            )
        } else {
            messages.append(
                "Rx: Cloud batch — keep --workers ≤\(cap) (or --consumers \(cap)) to stay under Ollama cloud rate limits."
            )
        }

        var appliedTimeout: Int?
        if ollamaTimeout == nil {
            if heavy {
                appliedTimeout = heavyCloudTimeoutSeconds
                messages.append(
                    "Rx: Ollama timeout \(heavyCloudTimeoutSeconds)s for heavy cloud model (or set --ollama-timeout)."
                )
            }
        }

        messages.append(
            "Rx: Retries with backoff on 429/502/503; one generate call per lyric line; checkpoints after each candidate."
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

// Copyright (C) 2025, Shyamal Suhana Chandra
// Writes best-so-far parody files during long batch runs (not only at the end).

import Foundation

/// Keeps the highest-scoring candidate per job on disk as generations finish.
public actor BatchOutputCheckpoint {
    private var bestScoreByJobID: [String: Double] = [:]
    private var completedCandidates = 0

    public init() {}

    /// Restore best-known scores from the resume index without loading candidate text.
    public func seedScore(jobID: String, score: Double) {
        let prior = bestScoreByJobID[jobID] ?? -.infinity
        if score > prior {
            bestScoreByJobID[jobID] = score
        }
    }

    @discardableResult
    public func consider(
        job: ParodyBatchJob,
        result: ParodyCandidateResult,
        notify: (@Sendable (String) -> Void)? = nil
    ) throws -> Bool {
        completedCandidates += 1
        let prior = bestScoreByJobID[job.id] ?? -.infinity
        guard result.score > prior else { return false }
        bestScoreByJobID[job.id] = result.score
        try result.text.write(toFile: job.outputPath, atomically: true, encoding: .utf8)
        let message =
            "checkpoint \(job.id) c\(result.index) score=\(String(format: "%.3f", result.score)) → \(job.outputPath)"
        notify?(message)
        return true
    }

    public func snapshot() -> (jobsWritten: Int, candidatesFinished: Int) {
        (bestScoreByJobID.count, completedCandidates)
    }
}

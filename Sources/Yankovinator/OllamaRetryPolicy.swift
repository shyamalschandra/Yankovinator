// Copyright (C) 2025, Shyamal Suhana Chandra
// Classify retryable Ollama / cloud HTTP failures and compute backoff delays.

import Foundation

/// Pure helpers for Ollama HTTP retry decisions (unit-tested without a live server).
public enum OllamaRetryPolicy: Sendable {
    /// Default max attempts for generate / tags / keywords requests.
    public static let defaultMaxAttempts = 6

    /// HTTP statuses that should be retried with backoff (rate limits + bad gateways).
    public static let retryableStatusCodes: Set<Int> = [429, 502, 503, 504]

    /// Whether an HTTP status code is worth retrying.
    public static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        retryableStatusCodes.contains(statusCode)
    }

    /// Whether a transport / connection error is transient (including ephemeral-port exhaustion).
    public static func isTransientNetworkError(_ error: Error) -> Bool {
        let s = String(describing: error).lowercased()
        let localized = error.localizedDescription.lowercased()
        let combined = s + " " + localized

        // Timeouts are not retried — cloud models may legitimately run near the limit.
        if combined.contains("timeout") || combined.contains("deadline") || combined.contains("timed out") {
            return false
        }

        // Ephemeral port / socket exhaustion under high cloud concurrency.
        if combined.contains("can't assign requested address")
            || combined.contains("cannot assign requested address")
            || combined.contains("address already in use")
            || combined.contains("too many open files")
            || combined.contains("no buffer space")
            || combined.contains("resource temporarily unavailable")
        {
            return true
        }

        if combined.contains("connection") {
            if combined.contains("reset")
                || combined.contains("closed")
                || combined.contains("refused")
                || combined.contains("not connected")
                || combined.contains("reset by peer")
                || combined.contains("broken pipe")
            {
                return true
            }
        }

        if combined.contains("network is unreachable")
            || combined.contains("host is down")
            || combined.contains("temporarily unavailable")
            || combined.contains("try again")
        {
            return true
        }

        // AsyncHTTPClient opaque codes seen under cloud fan-out.
        if combined.contains("httpclienterror") || combined.contains("error 1") {
            return true
        }

        return false
    }

    /// Parse `Retry-After` (delay-seconds or HTTP-date). Returns seconds ≥ 0, or nil.
    public static func parseRetryAfterSeconds(
        _ value: String?,
        now: Date = Date()
    ) -> Double? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = Double(raw), seconds >= 0 {
            return min(seconds, 120)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return min(max(date.timeIntervalSince(now), 0), 120)
        }
        return nil
    }

    /// Exponential backoff with full jitter. `attempt` is 1-based (first retry after failure → 1).
    /// When `retryAfterSeconds` is set (from Retry-After), it is preferred (plus small jitter).
    public static func backoffSeconds(
        attempt: Int,
        retryAfterSeconds: Double? = nil,
        randomUniform: () -> Double = { Double.random(in: 0..<1) }
    ) -> Double {
        if let retryAfter = retryAfterSeconds, retryAfter > 0 {
            let jitter = randomUniform() * 0.25
            return min(120, retryAfter + jitter)
        }
        let clampedAttempt = max(1, attempt)
        let exp = min(clampedAttempt, 6)
        let ceiling = min(60.0, pow(2.0, Double(exp))) // 2…64 capped at 60
        // Full jitter: uniform in [0, ceiling]
        return max(0.25, ceiling * randomUniform())
    }

    public static func backoffNanoseconds(
        attempt: Int,
        retryAfterSeconds: Double? = nil,
        randomUniform: () -> Double = { Double.random(in: 0..<1) }
    ) -> UInt64 {
        let seconds = backoffSeconds(
            attempt: attempt,
            retryAfterSeconds: retryAfterSeconds,
            randomUniform: randomUniform
        )
        return UInt64(seconds * 1_000_000_000)
    }
}

// Copyright (C) 2025, Shyamal Suhana Chandra
// Classify retryable Ollama / cloud HTTP failures and compute backoff delays.

import Foundation

/// Pure helpers for Ollama HTTP retry decisions (unit-tested without a live server).
public enum OllamaRetryPolicy: Sendable {
    /// Default max attempts for generate / tags / keywords requests (cloud).
    public static let defaultMaxAttempts = 6

    /// Extra attempts for DNS / upstream connectivity failures on `:cloud` models.
    public static let cloudDNSMaxAttempts = 10

    /// Local (non-cloud) max attempts.
    public static let localMaxAttempts = 4

    /// HTTP statuses that should be retried with backoff (rate limits + bad gateways).
    public static let retryableStatusCodes: Set<Int> = [429, 502, 503, 504]

    /// Whether an HTTP status code is worth retrying.
    public static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        retryableStatusCodes.contains(statusCode)
    }

    /// Detect DNS / upstream connectivity failures in error or HTTP body text.
    ///
    /// Matches patterns seen when local Ollama proxies `:cloud` models to ollama.com:
    /// `dial tcp: lookup ollama.com: i/o timeout`, `no such host`, etc.
    public static func isDNSConnectivityFailure(_ text: String) -> Bool {
        let combined = text.lowercased()
        guard !combined.isEmpty else { return false }

        if combined.contains("no such host")
            || combined.contains("temporary failure in name resolution")
            || combined.contains("name or service not known")
            || combined.contains("nodename nor servname provided")
            || combined.contains("network is unreachable")
            || combined.contains("host is unreachable")
            || combined.contains("can't assign requested address")
            || combined.contains("cannot assign requested address")
        {
            return true
        }

        // DNS lookup failures often look like timeouts; treat lookup/dial DNS timeouts as connectivity.
        let looksLikeDNSLookup =
            combined.contains("lookup ")
            || combined.contains("dial tcp")
            || (combined.contains("ollama.com") && (combined.contains("dns") || combined.contains("resolve")))
        if looksLikeDNSLookup
            && (combined.contains("i/o timeout")
                || combined.contains("timeout")
                || combined.contains("timed out")
                || combined.contains("no such host"))
        {
            return true
        }

        if combined.contains("dns")
            && (combined.contains("fail") || combined.contains("error") || combined.contains("timeout"))
        {
            return true
        }

        return false
    }

    /// Gateway status whose body indicates DNS/connectivity to ollama.com (or similar).
    public static func isDNSConnectivityHTTPFailure(statusCode: Int, bodyOrMessage: String) -> Bool {
        guard statusCode == 502 || statusCode == 503 || statusCode == 504 else { return false }
        return isDNSConnectivityFailure(bodyOrMessage)
    }

    /// Max attempts for a failure class. DNS/connectivity on cloud gets more tries than ordinary 429.
    public static func maxAttempts(isCloud: Bool, isDNSConnectivity: Bool) -> Int {
        if isCloud && isDNSConnectivity { return cloudDNSMaxAttempts }
        if isCloud { return defaultMaxAttempts }
        return localMaxAttempts
    }

    /// Whether a transport / connection error is transient (including ephemeral-port exhaustion).
    public static func isTransientNetworkError(_ error: Error) -> Bool {
        let s = String(describing: error).lowercased()
        let localized = error.localizedDescription.lowercased()
        let combined = s + " " + localized

        // DNS / connectivity (including lookup i/o timeouts) — retryable before generic timeout rule.
        if isDNSConnectivityFailure(combined) {
            return true
        }

        // Request/read timeouts are not retried — cloud models may legitimately run near the limit.
        if combined.contains("timeout") || combined.contains("deadline") || combined.contains("timed out") {
            return false
        }

        // Ephemeral port / socket exhaustion under high cloud concurrency.
        if combined.contains("address already in use")
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
    /// DNS/connectivity failures use a higher floor and ceiling so cloud upstream flaps can recover.
    public static func backoffSeconds(
        attempt: Int,
        retryAfterSeconds: Double? = nil,
        isDNSConnectivity: Bool = false,
        randomUniform: () -> Double = { Double.random(in: 0..<1) }
    ) -> Double {
        if let retryAfter = retryAfterSeconds, retryAfter > 0 {
            let jitter = randomUniform() * 0.25
            let cap = isDNSConnectivity ? 180.0 : 120.0
            return min(cap, retryAfter + jitter)
        }
        let clampedAttempt = max(1, attempt)
        if isDNSConnectivity {
            // Longer waits: floor 2s, ceiling up to 90s (2^n full jitter).
            let exp = min(clampedAttempt + 1, 7)
            let ceiling = min(90.0, pow(2.0, Double(exp)))
            return max(2.0, ceiling * randomUniform())
        }
        let exp = min(clampedAttempt, 6)
        let ceiling = min(60.0, pow(2.0, Double(exp))) // 2…64 capped at 60
        // Full jitter: uniform in [0, ceiling]
        return max(0.25, ceiling * randomUniform())
    }

    public static func backoffNanoseconds(
        attempt: Int,
        retryAfterSeconds: Double? = nil,
        isDNSConnectivity: Bool = false,
        randomUniform: () -> Double = { Double.random(in: 0..<1) }
    ) -> UInt64 {
        let seconds = backoffSeconds(
            attempt: attempt,
            retryAfterSeconds: retryAfterSeconds,
            isDNSConnectivity: isDNSConnectivity,
            randomUniform: randomUniform
        )
        return UInt64(seconds * 1_000_000_000)
    }

    /// User-facing tip when DNS/connectivity to ollama.com (or similar) fails.
    public static let dnsConnectivityUserTip = """
     DNS/connectivity to ollama.com failed (upstream). \
    Check network, VPN, DNS, or firewall; retry later; or use a local model (e.g. --model llama3.2:3b).
    """
}

// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class OllamaRetryPolicyTests: XCTestCase {

    func testRetryableHTTPStatuses() {
        XCTAssertTrue(OllamaRetryPolicy.isRetryableHTTPStatus(429))
        XCTAssertTrue(OllamaRetryPolicy.isRetryableHTTPStatus(502))
        XCTAssertTrue(OllamaRetryPolicy.isRetryableHTTPStatus(503))
        XCTAssertTrue(OllamaRetryPolicy.isRetryableHTTPStatus(504))
        XCTAssertFalse(OllamaRetryPolicy.isRetryableHTTPStatus(400))
        XCTAssertFalse(OllamaRetryPolicy.isRetryableHTTPStatus(404))
        XCTAssertFalse(OllamaRetryPolicy.isRetryableHTTPStatus(200))
        XCTAssertFalse(OllamaRetryPolicy.isRetryableHTTPStatus(500))
    }

    func testTransientNetworkIncludesPortExhaustion() {
        struct FakeError: Error, CustomStringConvertible {
            let description: String
        }
        XCTAssertTrue(
            OllamaRetryPolicy.isTransientNetworkError(
                FakeError(description: #"read tcp 192.168.1.1:54321->ollama.com:443: can't assign requested address"#)
            )
        )
        XCTAssertTrue(
            OllamaRetryPolicy.isTransientNetworkError(
                FakeError(description: "connection reset by peer")
            )
        )
        XCTAssertTrue(
            OllamaRetryPolicy.isTransientNetworkError(
                FakeError(description: "too many open files")
            )
        )
        XCTAssertFalse(
            OllamaRetryPolicy.isTransientNetworkError(
                FakeError(description: "request timeout after 600s")
            )
        )
    }

    func testParseRetryAfterSeconds() {
        XCTAssertEqual(OllamaRetryPolicy.parseRetryAfterSeconds("3"), 3)
        XCTAssertEqual(OllamaRetryPolicy.parseRetryAfterSeconds("1.5"), 1.5)
        XCTAssertNil(OllamaRetryPolicy.parseRetryAfterSeconds(nil))
        XCTAssertNil(OllamaRetryPolicy.parseRetryAfterSeconds(""))
        XCTAssertEqual(OllamaRetryPolicy.parseRetryAfterSeconds("999"), 120) // capped
    }

    func testParseRetryAfterHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(8)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: future)
        let seconds = OllamaRetryPolicy.parseRetryAfterSeconds(header, now: now)
        XCTAssertNotNil(seconds)
        XCTAssertEqual(seconds!, 8, accuracy: 0.01)
    }

    func testBackoffPrefersRetryAfter() {
        let seconds = OllamaRetryPolicy.backoffSeconds(
            attempt: 1,
            retryAfterSeconds: 5,
            randomUniform: { 0.0 }
        )
        XCTAssertEqual(seconds, 5, accuracy: 0.01)
    }

    func testBackoffExponentialWithJitter() {
        let low = OllamaRetryPolicy.backoffSeconds(attempt: 1, randomUniform: { 0.0 })
        let high = OllamaRetryPolicy.backoffSeconds(attempt: 1, randomUniform: { 0.999 })
        XCTAssertGreaterThanOrEqual(low, 0.25)
        XCTAssertLessThanOrEqual(high, 2.0 + 0.01)

        let later = OllamaRetryPolicy.backoffSeconds(attempt: 4, randomUniform: { 1.0 })
        XCTAssertLessThanOrEqual(later, 60.0)
        XCTAssertGreaterThan(later, high)
    }

    func testBackoffNanosecondsPositive() {
        let ns = OllamaRetryPolicy.backoffNanoseconds(attempt: 2, randomUniform: { 0.5 })
        XCTAssertGreaterThan(ns, 0)
    }
}

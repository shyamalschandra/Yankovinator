import XCTest
@testable import Yankovinator

final class OllamaGenerateResponseTests: XCTestCase {
    func testCleanLineResponseStripsWrappingDoubleQuotes() {
        XCTAssertEqual(OllamaClient.cleanLineResponse("\"hello world\""), "hello world")
    }

    func testCleanLineResponseKeepsContractionsInSingleQuotes() {
        XCTAssertEqual(OllamaClient.cleanLineResponse("'don't stop'"), "'don't stop'")
    }

    func testParseParodyLineRejectsEmptyResponse() {
        let json: [String: Any] = [
            "response": "",
            "thinking": "internal reasoning",
            "done": true
        ]
        XCTAssertThrowsError(try OllamaClient.parseParodyLineFromGenerateJSON(json)) { error in
            guard case OllamaError.emptyGenerateResponse = error else {
                return XCTFail("expected emptyGenerateResponse, got \(error)")
            }
        }
    }

    func testParseParodyLineReturnsCleanedText() {
        let json: [String: Any] = ["response": "  I wanna transcend  \n"]
        XCTAssertEqual(try OllamaClient.parseParodyLineFromGenerateJSON(json), "I wanna transcend")
    }

    func testGenerateRequestBodyDisablesThinking() {
        let body = OllamaClient.ollamaGenerateRequestBody(
            model: "deepseek-v4-pro:cloud",
            prompt: "line",
            options: ["num_predict": 100]
        )
        XCTAssertEqual(body["think"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, false)
    }
}

import XCTest
@testable import ClipMind

final class AIActionServiceTests: XCTestCase {
    func testFormatJSONProducesParseableJSON() async throws {
        struct FakeProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                """
                {
                  "name": "ClipMind",
                  "enabled": true
                }
                """
            }
        }

        let result = try await AIActionService.run(
            action: .formatJSON,
            text: #"{"name":"ClipMind","enabled":true}"#,
            provider: FakeProvider()
        )

        XCTAssertTrue(AIActionService.isValidJSON(result))
    }

    func testFormatJSONRejectsInvalidOutput() async {
        struct FakeProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                "not json"
            }
        }

        do {
            _ = try await AIActionService.run(
                action: .formatJSON,
                text: "{bad",
                provider: FakeProvider()
            )
            XCTFail("Expected invalid JSON error")
        } catch {
            XCTAssertEqual(error as? AIActionError, .invalidJSONOutput)
        }
    }

    func testSummarizeReturnsProviderText() async throws {
        struct FakeProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                "A concise summary."
            }
        }

        let result = try await AIActionService.run(
            action: .summarize,
            text: "Long text about a project roadmap and milestones.",
            provider: FakeProvider()
        )

        XCTAssertEqual(result, "A concise summary.")
    }

    func testBulletPointsActionShape() async throws {
        struct FakeProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                """
                - First point
                - Second point
                """
            }
        }

        let result = try await AIActionService.run(
            action: .bulletPoints,
            text: "First point and second point in prose.",
            provider: FakeProvider()
        )

        XCTAssertTrue(result.contains("- First point"))
        XCTAssertTrue(result.contains("- Second point"))
    }
}

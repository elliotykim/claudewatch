import XCTest
@testable import ClaudeWatch

final class StatusClientTests: XCTestCase {

    private func respond(componentStatus: String) {
        let body = #"""
        {
          "page": {"id":"x","name":"Claude","url":"https://status.claude.com"},
          "components": [
            {"id":"other","name":"claude.ai","status":"operational"},
            {"id":"yyzkbfz2thpt","name":"Claude Code","status":"\#(componentStatus)"}
          ]
        }
        """#.data(using: .utf8)!
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
    }

    func testMapsAllComponentStatuses() async {
        let cases: [(String, Severity)] = [
            ("operational", .operational),
            ("degraded_performance", .minor),
            ("under_maintenance", .minor),
            ("partial_outage", .major),
            ("major_outage", .critical),
        ]
        for (status, expected) in cases {
            respond(componentStatus: status)
            let client = StatusClient(session: MockURLProtocol.sessionWithMock())
            let result = await client.fetch()
            guard case .success(let state) = result else {
                return XCTFail("expected success for \(status)")
            }
            XCTAssertEqual(state.severity, expected, "status=\(status)")
        }
    }

    func testSeverityInitFallback() {
        XCTAssertEqual(Severity(componentStatus: "weird-unknown"), .operational)
    }
}

import XCTest
@testable import ClaudeWatch

final class QuotaSyncClientTests: XCTestCase {

    private var tmpFile: String!

    override func setUp() {
        super.setUp()
        tmpFile = NSTemporaryDirectory() + "claudewatch-test-\(UUID().uuidString).json"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpFile)
        super.tearDown()
    }

    func testReadsUsageFromFile() {
        let json = """
        {
            "five_hour": { "used_percentage": 42.5, "resets_at": 1713100000 },
            "weekly": [
                { "label": "All models", "used_percentage": 18.3, "resets_at": 1713500000 },
                { "label": "Sonnet only", "used_percentage": 5.0, "resets_at": 1713600000 }
            ],
            "updated_at": 1713099000
        }
        """
        FileManager.default.createFile(atPath: tmpFile, contents: json.data(using: .utf8))

        let client = QuotaSyncClient(filePath: tmpFile)
        let state = client.read()

        XCTAssertNotNil(state)
        XCTAssertEqual(state?.fiveHour?.usedPercentage, 42.5)
        XCTAssertNotNil(state?.fiveHour?.resetsAt)
        XCTAssertEqual(state?.weeklyLimits.count, 2)
        XCTAssertEqual(state?.weeklyLimits[0].label, "All models")
        XCTAssertEqual(state?.weeklyLimits[0].usedPercentage, 18.3)
        XCTAssertEqual(state?.weeklyLimits[1].label, "Sonnet only")
        XCTAssertEqual(state?.weeklyLimits[1].usedPercentage, 5.0)
        XCTAssertNotNil(state?.updatedAt)
    }

    func testLegacySevenDayFallback() {
        let json = """
        {
            "five_hour": { "used_percentage": 42.5, "resets_at": 1713100000 },
            "seven_day": { "used_percentage": 18.3, "resets_at": 1713500000 },
            "updated_at": 1713099000
        }
        """
        FileManager.default.createFile(atPath: tmpFile, contents: json.data(using: .utf8))

        let client = QuotaSyncClient(filePath: tmpFile)
        let state = client.read()

        XCTAssertEqual(state?.weeklyLimits.count, 1)
        XCTAssertEqual(state?.weeklyLimits.first?.label, "All models")
        XCTAssertEqual(state?.weeklyLimits.first?.usedPercentage, 18.3)
    }

    func testReturnsNilForMissingFile() {
        let client = QuotaSyncClient(filePath: "/tmp/does-not-exist.json")
        XCTAssertNil(client.read())
    }

    func testReturnsNilForInvalidJSON() {
        FileManager.default.createFile(atPath: tmpFile, contents: "not json".data(using: .utf8))
        let client = QuotaSyncClient(filePath: tmpFile)
        XCTAssertNil(client.read())
    }

    func testReadsFromArbitraryConfigDirViaAccount() {
        // Simulate an alternate CLAUDE_CONFIG_DIR by writing the usage JSON
        // into a temp dir and reading via a bookmark-less account (falls
        // through to direct file access; no sandbox in the test host).
        let tmpDir = NSTemporaryDirectory() + "claudewatch-dir-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let usageFile = (tmpDir as NSString).appendingPathComponent("claudewatch-usage.json")
        let json = #"{"five_hour":{"used_percentage":12},"updated_at":1713099000}"#
        FileManager.default.createFile(atPath: usageFile, contents: json.data(using: .utf8))

        let account = TrackedAccount(label: "Alt", configDir: tmpDir)
        let state = QuotaSyncClient.read(account: account)
        XCTAssertEqual(state?.fiveHour?.usedPercentage, 12)
    }

    func testMissingUsageFileForAccountReturnsNil() {
        let account = TrackedAccount(label: "Ghost", configDir: "/tmp/definitely-not-here-\(UUID())")
        XCTAssertNil(QuotaSyncClient.read(account: account))
    }

    func testPartialDataOmitsNilWindows() {
        let json = """
        {
            "five_hour": { "used_percentage": 10 },
            "updated_at": 1713099000
        }
        """
        FileManager.default.createFile(atPath: tmpFile, contents: json.data(using: .utf8))

        let client = QuotaSyncClient(filePath: tmpFile)
        let state = client.read()

        XCTAssertNotNil(state?.fiveHour)
        XCTAssertTrue(state?.weeklyLimits.isEmpty ?? false)
    }
}

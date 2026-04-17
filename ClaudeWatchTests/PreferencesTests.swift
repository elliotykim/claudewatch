import XCTest
@testable import ClaudeWatch

@MainActor
final class PreferencesTests: XCTestCase {

    private let key = "trackedAccounts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testSeedsDefaultAccountWhenEmpty() {
        let accounts = Preferences.shared.accounts
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.label, "Default")
        XCTAssertTrue(accounts.first!.configDir.hasSuffix(".claude"))
    }

    func testRoundTripsMultipleAccounts() {
        let prefs = Preferences.shared
        let a = TrackedAccount(label: "Work", configDir: "/tmp/claude-work")
        let b = TrackedAccount(label: "Personal", configDir: "/tmp/claude-personal")
        prefs.accounts = [a, b]

        let decoded = prefs.accounts
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].label, "Work")
        XCTAssertEqual(decoded[1].configDir, "/tmp/claude-personal")
    }

    func testAddAccountAppends() {
        let prefs = Preferences.shared
        prefs.accounts = [TrackedAccount(label: "A", configDir: "/tmp/a")]
        prefs.addAccount(TrackedAccount(label: "B", configDir: "/tmp/b"))
        XCTAssertEqual(prefs.accounts.map(\.label), ["A", "B"])
    }

    func testRemoveAccountById() {
        let prefs = Preferences.shared
        let a = TrackedAccount(label: "A", configDir: "/tmp/a")
        let b = TrackedAccount(label: "B", configDir: "/tmp/b")
        prefs.accounts = [a, b]

        prefs.removeAccount(id: a.id)
        XCTAssertEqual(prefs.accounts.map(\.label), ["B"])
    }

    func testUpdateAccountPreservesOthers() {
        let prefs = Preferences.shared
        let a = TrackedAccount(label: "A", configDir: "/tmp/a")
        let b = TrackedAccount(label: "B", configDir: "/tmp/b")
        prefs.accounts = [a, b]

        var updated = a
        updated.label = "A-renamed"
        prefs.updateAccount(updated)

        XCTAssertEqual(prefs.accounts.map(\.label), ["A-renamed", "B"])
    }

    func testBookmarkDataRoundTrips() {
        let prefs = Preferences.shared
        let bookmark = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let a = TrackedAccount(label: "Work", configDir: "/tmp/a", bookmarkData: bookmark)
        prefs.accounts = [a]

        XCTAssertEqual(prefs.accounts.first?.bookmarkData, bookmark)
    }
}

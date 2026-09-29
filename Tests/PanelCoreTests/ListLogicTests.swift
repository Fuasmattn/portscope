import Foundation
import XCTest
@testable import PanelCore

final class ListLogicTests: XCTestCase {
    func testFilterMatchesPortProjectProcessBranch() {
        XCTAssertTrue(ListLogic.matches(needle: "30", port: 3000, projectName: "app", processName: "node", branch: nil))
        XCTAssertTrue(ListLogic.matches(needle: "APP", port: 1, projectName: "my-app", processName: "node", branch: nil))
        XCTAssertTrue(ListLogic.matches(needle: "vite", port: 1, projectName: "x", processName: "vite", branch: nil))
        XCTAssertTrue(ListLogic.matches(needle: "feat", port: 1, projectName: "x", processName: "y", branch: "feature/z"))
        XCTAssertFalse(ListLogic.matches(needle: "zzz", port: 1, projectName: "x", processName: "y", branch: nil))
        XCTAssertTrue(ListLogic.matches(needle: "   ", port: 1, projectName: "x", processName: "y", branch: nil))
    }

    func testStuckAfterThreshold() {
        let start = Date()
        XCTAssertFalse(ListLogic.isStuck(signalledAt: start, now: start.addingTimeInterval(3)))
        XCTAssertTrue(ListLogic.isStuck(signalledAt: start, now: start.addingTimeInterval(5)))
    }

    func testGroupsSharedProjectsAndKeepsSingles() {
        struct E { let port: Int; let cwd: String?; let name: String; let pinned: Bool }
        let entries = [
            E(port: 8080, cwd: "/b", name: "b", pinned: false),
            E(port: 3000, cwd: "/a", name: "a", pinned: false),
            E(port: 3001, cwd: "/a", name: "a", pinned: false),
            E(port: 9000, cwd: nil, name: "c", pinned: true),
        ]
        let groups = ListLogic.grouped(entries, key: \.cwd, title: \.name, port: \.port, pinned: \.pinned)
        XCTAssertEqual(groups.map(\.title), [nil, "a", nil])
        XCTAssertEqual(groups[0].entries.map(\.port), [9000])
        XCTAssertEqual(groups[1].entries.map(\.port), [3000, 3001])
        XCTAssertEqual(groups[2].entries.map(\.port), [8080])
    }
}

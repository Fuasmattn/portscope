import Foundation
import XCTest
@testable import PortscopeCore

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

    private struct P { let id: String; let port: Int; let cwd: String?; let pid: Int32 }

    private func merge(_ entries: [P]) -> ListLogic.PortMerge<P> {
        ListLogic.mergeByPort(entries, id: \.id, port: \.port, folder: \.cwd, pid: \.pid)
    }

    func testMergesSamePortSameFolderOntoLowestPID() {
        let entries = [
            P(id: "20:3000", port: 3000, cwd: "/a", pid: 20),
            P(id: "10:3000", port: 3000, cwd: "/a", pid: 10),
            P(id: "30:8080", port: 8080, cwd: "/b", pid: 30),
        ]
        let result = merge(entries)
        XCTAssertEqual(result.collapsed.map(\.id), ["10:3000", "30:8080"])
        XCTAssertEqual(result.siblings["10:3000"]?.map(\.id), ["20:3000"])
        XCTAssertNil(result.siblings["30:8080"])
    }

    func testDoesNotMergeAcrossFoldersOrWithoutFolder() {
        let entries = [
            P(id: "1:4000", port: 4000, cwd: "/a", pid: 1),
            P(id: "2:4000", port: 4000, cwd: "/b", pid: 2),
            P(id: "3:5000", port: 5000, cwd: nil, pid: 3),
            P(id: "4:5000", port: 5000, cwd: nil, pid: 4),
        ]
        let result = merge(entries)
        XCTAssertEqual(result.collapsed.count, 4)
        XCTAssertTrue(result.siblings.isEmpty)
    }

    func testConflictOnlyBetweenVisibleRowsOnSamePort() {
        let rows = [
            P(id: "1:4000", port: 4000, cwd: "/a", pid: 1),
            P(id: "2:4000", port: 4000, cwd: "/b", pid: 2),
            P(id: "3:4000", port: 4000, cwd: "/c", pid: 3),
            P(id: "4:9000", port: 9000, cwd: "/d", pid: 4),
        ]
        func conflict(_ row: P, hidden: Set<String> = []) -> Bool {
            ListLogic.hasPortConflict(row, in: rows, id: \.id, port: \.port, shown: { !hidden.contains($0.id) })
        }
        XCTAssertTrue(conflict(rows[0]))
        XCTAssertFalse(conflict(rows[3]))
        XCTAssertFalse(conflict(rows[0], hidden: ["2:4000", "3:4000"]))
    }
}

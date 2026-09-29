import Foundation
import XCTest
@testable import PanelCore

final class LsofParserTests: XCTestCase {
    func testParsesIPv4IPv6AndWildcard() {
        let output = """
        p101
        cnode
        u501
        f23
        n127.0.0.1:3000
        p102
        cControlCenter
        u501
        f9
        n*:5000
        f10
        n[::1]:5000
        p103
        cGoogle\\x20Chrome
        u501
        f4
        n[::1]:9222
        """
        let sockets = LsofParser.parseListeners(output)
        XCTAssertEqual(sockets.count, 4)
        XCTAssertEqual(sockets[0], ListeningSocket(pid: 101, command: "node", uid: 501, host: "127.0.0.1", port: 3000))
        XCTAssertEqual(sockets[1].host, "*")
        XCTAssertEqual(sockets[2].host, "::1")
        XCTAssertEqual(sockets[3].command, "Google Chrome")
        XCTAssertTrue(sockets[0].isLoopbackOnly)
        XCTAssertFalse(sockets[1].isLoopbackOnly)
    }

    func testParsesWorkingDirectories() {
        let output = "p101\nfcwd\nn/Users/me/app\np102\nfcwd\nn/\n"
        XCTAssertEqual(LsofParser.parseWorkingDirectories(output), [101: "/Users/me/app", 102: "/"])
    }
}

final class ProcessTableTests: XCTestCase {
    private func record(_ pid: Int32, _ ppid: Int32, _ command: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, uid: 501, startTime: "t\(pid)", startDate: nil, command: command)
    }

    func testParsesLineWithPaddedDay() {
        let line = "  4242   1234   501 Tue Sep  9 13:22:38 2026 /usr/local/bin/node server.js --port 3000"
        let parsed = ProcessTable.parseLine(Substring(line))
        XCTAssertEqual(parsed?.pid, 4242)
        XCTAssertEqual(parsed?.ppid, 1234)
        XCTAssertEqual(parsed?.uid, 501)
        XCTAssertEqual(parsed?.startTime, "Tue Sep 9 13:22:38 2026")
        XCTAssertEqual(parsed?.command, "/usr/local/bin/node server.js --port 3000")
        XCTAssertEqual(parsed?.executableName, "node")
        XCTAssertNotNil(parsed?.startDate)
    }

    func testExecutableNameUsesAppBundle() {
        let parsed = ProcessRecord(
            pid: 1, ppid: 0, uid: 501, startTime: "", startDate: nil,
            command: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron --foo")
        XCTAssertEqual(parsed.executableName, "Visual Studio Code")
    }

    func testAncestorsDescendantsAndAttribution() {
        let table = ProcessTable(records: [
            record(10, 1, "/Applications/Terminal.app/Contents/MacOS/Terminal"),
            record(11, 10, "-zsh"),
            record(12, 11, "/Users/me/.local/bin/claude"),
            record(13, 12, "/bin/zsh -c npm run dev"),
            record(14, 13, "node server.js"),
        ])
        XCTAssertEqual(table.ancestors(of: 14).map(\.pid), [13, 12, 11, 10])
        XCTAssertEqual(Set(table.descendants(of: 12).map(\.pid)), [13, 14])
        XCTAssertEqual(AttributionResolver.resolve(pid: 14, in: table).launcher, "Claude Code")
    }

    func testDetachedWhenParentIsLaunchd() {
        let table = ProcessTable(records: [record(20, 1, "node server.js")])
        let attribution = AttributionResolver.resolve(pid: 20, in: table)
        XCTAssertTrue(attribution.isDetached)
        XCTAssertNil(attribution.launcher)
    }
}

final class ProjectDetectorTests: XCTestCase {
    func testReadsPackageNameAndBranch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("panel-test-\(UUID().uuidString)")
        let app = root.appendingPathComponent("apps/web")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/x\n".write(
            to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try #"{"name": "my-web-app"}"#.write(
            to: app.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let info = ProjectDetector.detect(cwd: app.path, home: "/nonexistent-home")
        XCTAssertEqual(info.name, "my-web-app")
        XCTAssertEqual(info.branch, "feature/x")
    }
}

final class FormattingTests: XCTestCase {
    func testFormatsUptime() {
        XCTAssertEqual(Formatting.uptime(45), "45s")
        XCTAssertEqual(Formatting.uptime(190), "3m")
        XCTAssertEqual(Formatting.uptime(5520), "1h 32m")
        XCTAssertEqual(Formatting.uptime(200_000), "2d 7h")
    }
}

final class NoiseFilterTests: XCTestCase {
    private let home = "/Users/me"

    func testHidesDesktopAppsAndDaemons() {
        XCTAssertTrue(NoiseFilter.isSystemNoise(
            processName: "Discord",
            commandLine: "/Applications/Discord.app/Contents/MacOS/Discord",
            cwd: "/", home: home))
        XCTAssertTrue(NoiseFilter.isSystemNoise(
            processName: "Spotify",
            commandLine: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            cwd: "/Users/me/Library/Application Support/Spotify", home: home))
        XCTAssertTrue(NoiseFilter.isSystemNoise(
            processName: "ControlCenter", commandLine: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            cwd: "/", home: home))
    }

    func testKeepsDevServers() {
        XCTAssertFalse(NoiseFilter.isSystemNoise(
            processName: "node", commandLine: "node server.js",
            cwd: "/Users/me/Projects/app", home: home))
        // An Electron app run from a project folder still counts as dev work.
        XCTAssertFalse(NoiseFilter.isSystemNoise(
            processName: "Electron",
            commandLine: "/Users/me/Projects/app/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron .",
            cwd: "/Users/me/Projects/app", home: home))
    }
}

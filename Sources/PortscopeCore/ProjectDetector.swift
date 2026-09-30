import Foundation

public struct ProjectInfo: Equatable, Sendable {
    public let name: String
    public let branch: String?
    public let root: String?
}

public enum ProjectDetector {
    private static let manifests = ["package.json", "Package.swift", "pyproject.toml", "Cargo.toml", "go.mod"]

    /// Walks up from a working directory to find the project name and git branch.
    /// Name preference: package.json "name", then git root folder, then the cwd's own folder name.
    public static func detect(cwd: String, home: String = NSHomeDirectory()) -> ProjectInfo {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: cwd).standardizedFileURL
        var manifestName: String?
        var gitRoot: URL?

        for _ in 0..<12 {
            let path = directory.path
            if path == "/" || path == home { break }

            if manifestName == nil, let name = packageJSONName(in: directory) {
                manifestName = name
            }
            if gitRoot == nil, fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                gitRoot = directory
            }
            if gitRoot != nil { break }
            directory = directory.deletingLastPathComponent()
        }

        let fallback = URL(fileURLWithPath: cwd).lastPathComponent
        let name = manifestName ?? gitRoot?.lastPathComponent ?? (fallback.isEmpty ? cwd : fallback)
        return ProjectInfo(
            name: name,
            branch: gitRoot.flatMap { currentBranch(gitRoot: $0) },
            root: gitRoot?.path)
    }

    static func packageJSONName(in directory: URL) -> String? {
        let file = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty
        else { return nil }
        return name
    }

    /// Reads HEAD directly (no `git` subprocess). Handles worktrees where `.git` is a file.
    static func currentBranch(gitRoot: URL) -> String? {
        let dotGit = gitRoot.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }

        var gitDirectory = dotGit
        if !isDirectory.boolValue {
            guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                  let line = text.split(whereSeparator: \.isNewline).first,
                  line.hasPrefix("gitdir:")
            else { return nil }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDirectory = URL(fileURLWithPath: target, relativeTo: gitRoot).standardizedFileURL
        }

        guard let head = try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8) else {
            return nil
        }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        return trimmed.count >= 7 ? String(trimmed.prefix(7)) : nil
    }
}

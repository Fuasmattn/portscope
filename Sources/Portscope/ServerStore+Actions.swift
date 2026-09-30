import AppKit
import PortscopeCore

// Things the user does to a server: open, copy, reveal, stop, start again.
extension ServerStore {
    /// http://localhost:PORT plus the path remembered for that port.
    func url(for entry: ServerEntry) -> URL? {
        URL(string: "http://localhost:\(entry.port)\(settings.openPath(for: entry.port))")
    }

    func open(_ entry: ServerEntry) {
        guard let url = url(for: entry) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyAsCurl(_ entry: ServerEntry) {
        guard let url = url(for: entry) else { return }
        copy("curl -i \(url.absoluteString)", label: "curl command")
    }

    func copyURL(_ entry: ServerEntry) {
        copy("http://localhost:\(entry.port)", label: "http://localhost:\(entry.port)")
    }

    func copyPort(_ entry: ServerEntry) {
        copy(String(entry.port), label: "\(entry.port)")
    }

    func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied \(label)")
    }

    func revealWorkingDirectory(_ entry: ServerEntry) {
        guard let cwd = entry.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    func openWorkingDirectory(_ entry: ServerEntry, in editor: Launchers.EditorApp) {
        guard let cwd = entry.cwd else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: editor.url, configuration: configuration) { _, error in
            if let error = error {
                Task { @MainActor in self.show("Could not open in \(editor.name): \(error.localizedDescription)") }
            }
        }
    }

    /// Clicking the radar sends out a ping ring.
    func poke() {
        pingDate = Date()
    }

    func terminate(_ entry: ServerEntry, force: Bool) {
        react(.lost, for: 1.2)
        // Processes merged into this row go too, or the port would stay taken.
        let others = siblings(of: entry)
        Task {
            let pid = entry.pid
            let startTime = entry.startTime
            let result = await Task.detached {
                KillService.terminate(pid: pid, expectedStartTime: startTime, force: force)
            }.value
            for other in others {
                let otherPID = other.pid
                let otherStart = other.startTime
                _ = await Task.detached {
                    KillService.terminate(pid: otherPID, expectedStartTime: otherStart, force: force)
                }.value
            }

            switch result {
            case .signalled(let count):
                let total = count + others.count
                let extra = total > 1 ? " (+\(total - 1) more processes)" : ""
                show((force ? "Killed" : "Stopping") + " :\(entry.port)" + extra)
                if stopping[entry.id] == nil { stopping[entry.id] = Date() }
                history.remember(entry)
            case .notFound:
                show("Already stopped")
            case .pidReused:
                show("That process changed. Nothing was killed.")
            case .refused(let reason):
                show(reason)
            case .failed(let code):
                show("Could not signal process (errno \(code))")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    /// Runs the saved command line again in its working directory, detached from this app.
    func startAgain(_ stopped: StoppedServer) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A login shell so PATH matches the user's terminal; nohup + & so it outlives us.
        process.arguments = ["-lc", "nohup \(stopped.commandLine) >/dev/null 2>&1 &"]
        if let cwd = stopped.cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        do {
            try process.run()
            show("Starting \(stopped.projectName) on :\(stopped.port)…")
            history.forget(stopped)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refresh()
            }
        } catch {
            show("Could not start: \(error.localizedDescription)")
        }
    }

    func resetHidden() {
        rules.resetHidden()
        show("Hidden list cleared")
    }
}

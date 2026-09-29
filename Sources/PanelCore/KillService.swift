import Foundation

public enum KillResult: Equatable, Sendable {
    /// Signal delivered to this many processes (target plus descendants).
    case signalled(count: Int)
    /// Process is already gone.
    case notFound
    /// The PID now belongs to a different process than the one shown. Nothing was signalled.
    case pidReused
    case refused(reason: String)
    case failed(errno: Int32)
}

public enum KillService {
    /// Sends SIGTERM (or SIGKILL when `force`) to a server and its descendants.
    /// Re-reads the process table first and aborts if the PID's start time no longer matches
    /// what the UI showed, so a recycled PID is never killed by mistake.
    public static func terminate(
        pid: Int32,
        expectedStartTime: String,
        force: Bool,
        currentUID: uid_t = getuid()
    ) -> KillResult {
        if pid <= 1 || pid == getpid() {
            return .refused(reason: "Refusing to signal PID \(pid)")
        }
        let table = ProcessTable.snapshot()
        guard let target = table.records[pid] else { return .notFound }
        guard target.startTime == expectedStartTime else { return .pidReused }
        guard target.uid == currentUID else {
            return .refused(reason: "Process is owned by another user")
        }

        let victims = [target] + table.descendants(of: pid).filter { $0.uid == currentUID }
        let signalNumber = force ? SIGKILL : SIGTERM
        var delivered = 0
        var lastError: Int32 = 0
        // Children first, so a parent that respawns workers cannot outrun the signal.
        for victim in victims.reversed() {
            if kill(victim.pid, signalNumber) == 0 {
                delivered += 1
            } else if errno != ESRCH {
                lastError = errno
            }
        }
        if delivered == 0 {
            return lastError == 0 ? .notFound : .failed(errno: lastError)
        }
        return .signalled(count: delivered)
    }
}

# Localhost Panel — Phase 1 spec

Working title. A native macOS menu bar app that shows which dev servers are listening on localhost, so you never have to run `lsof` and guess ports.

## Decisions
- Native SwiftUI, menu bar app (`MenuBarExtra`), macOS 26 (Tahoe) on Apple Silicon.
- Built from scratch. Manfath is a feature reference only.
- Distributed outside the App Store (needs `lsof`, `ps`, and `kill`, which the sandbox blocks).

## Phase 1 features
1. **Port list, open, kill.** List listening TCP ports for the current user. Click opens `http://localhost:PORT` in the default browser. Kill sends SIGTERM (Option-click: SIGKILL).
2. **Project, branch, uptime.** Resolve each server's working directory, walk up to the repo/package root, show project name, git branch, and uptime instead of just "node".
3. **Hotkey and pin/hide.** Global hotkey toggles a small floating panel. Pin ports you care about, hide ones you never do (persisted).
4. **Session attribution and detached processes.** Walk the parent chain to show who started each server (Claude Code, Cursor/VS Code, Terminal, ...). Flag processes whose parent is launchd (PID 1) as "detached" candidates.

## Kill safety
- Every row carries the process start time (`ps lstart`) captured at scan time.
- Before signalling, re-read the start time for that PID. If it differs, abort: the PID was reused.
- SIGTERM goes to the process and its descendants; SIGKILL only on explicit request or after a timeout the user confirms.
- Only processes owned by the current user are listed, so no privilege escalation is ever attempted.

## Noise filtering
- Only current-user processes.
- Known system listeners hidden by default (e.g. ControlCenter on 5000/7000, rapportd).
- HTTP probe per port decides whether "open in browser" is offered.

## Refresh
- 2 s while the popover or panel is visible, 10 s otherwise (badge count).

## Out of scope for phase 1
Tunnels, QR codes, log tailing, notifications, agent-session status (only the parent-chain attribution above).

## Architecture
- `PanelCore` (Foundation only): parsers, process table, project detection, attribution, kill service. Unit-testable.
- `LocalhostPanel` (SwiftUI/AppKit): menu bar UI, floating panel, hotkey, settings.

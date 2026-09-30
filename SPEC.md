# Portscope — Phase 1 spec

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
- `PortscopeCore` (Foundation only): parsers, process table, project detection, attribution, kill service. Unit-testable.
- `Portscope` (SwiftUI/AppKit): menu bar UI, floating panel, hotkey, settings.

## Phase 2 (shipped)

What grew on top of phase 1, after using it for a while.

### UI
- The floating panel is the only UI. The menu bar item toggles it under the icon; the hotkey opens it near the cursor or where it was last dragged (Settings). Borderless window, dragged by the header card, pinned open with the footer pin, Esc closes.
- Header card is a corner sonar scope: one blip per server placed by port, a ping ring every 4 s (8 s when empty) that lights blips as it passes, orange for detached, arrival and departure animations, hover ring with port label linked to the row. Clicking a blip opens it, clicking empty scope pings. Commentary line under the title, rotating.
- Rows: status dot (HTTP 2xx/3xx green, 4xx yellow, 5xx red, grey when the port is open but silent), port, project, branch, process, live uptime, launcher app icon. Badges: `detached`, `network` (non-loopback), `×N` (merged processes), `port conflict`. Actions on hover: details, open, stop. Stop shows "stopping…" and offers Force kill when SIGTERM goes unanswered for 4 s.
- Details popover: command, folder, PID with copy buttons, listening scope, and a per-port path used by Open.
- Servers sharing a folder are grouped under a project header. Same port and same folder collapse to one row (IPv4 + IPv6, parent + worker); Stop signals all of them. Same port from different folders is flagged as a conflict.
- Filter field above 8 rows or on ⌘F. Keyboard: ↑↓ select, ↩ open, Space details, ⌘⌫ stop (⌥ SIGKILL), ⎋ closes details, clears filter, clears selection, closes the panel.
- Recently stopped: last 5, with Start again (same command, same folder, via a login shell, detached).
- Context menu: open, details, copy URL / port / curl, open project in installed editors and terminals, reveal folder, pin, hide by port / process / project, stop, force kill.
- Settings window: hotkey recorder, reopen where left, menu bar badge (count / dot / icon), stale server mark, show system noise, row click behaviour, refresh interval, radar toggle, reset hidden rules.

### Distribution
- Still no app bundle or signing. `make install` copies the release binary to `~/.local/bin` and loads a LaunchAgent so it starts at login. `make restart`, `make uninstall`.
- Consequences: no launch-at-login toggle in Settings (needs `SMAppService` in a bundle), no notifications, no Sparkle.

### Architecture
- `PortscopeCore` gained `ListLogic` (filter match, stuck detection, project grouping, port merge, conflict) as pure functions with tests, and `HTTPProbe` now returns the status code.
- `ServerStore` is the live state (scan, arrivals, stop attempts, selection). Preferences live in `PanelSettings`, visibility rules in `VisibilityRules`, stop history in `StopHistory`, editor and icon lookup in `Launchers`. Child objects forward `objectWillChange` to the store.
- Views: `ServerListView` (list, search, footer), `ServerRow` (row, popover, menu), `WatcherHeader` (radar card), `RadarView`, `RecentlyStoppedSection`, `ButtonStyles`, `SettingsView`, `FloatingPanel`.

### Decisions
- Inline row expansion was tried and dropped: the window has to resize, and AppKit window frames never animate on SwiftUI's clock. A popover has no such problem.
- A radar glow bleeding into the list was tried and dropped as too much.
- Menu bar dropdown (`MenuBarExtra`) dropped in favour of one panel: the dropdown resized in one step and duplicated every panel bug.

### Not done
- Notifications, Sparkle, tunnels, QR, log tailing (still out of scope).
- Probe cost: every listening port gets a HEAD every 2 s while the panel is open. Fine on a laptop so far, could cache per pid:port.

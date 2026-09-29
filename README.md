# Localhost Panel

Menu bar app that shows which dev servers are listening on localhost. Working title.

See [SPEC.md](SPEC.md) for scope and decisions.

## Build and run

Requires Xcode 26 (or its command line tools) on macOS.

```sh
swift build -c release
.build/release/LocalhostPanel
```

Run the tests:

```sh
swift test
```

- Click the menu bar item for the list. Control-Option-L opens a floating panel near the cursor.
- Click the arrow to open a server in your browser. Click the x, then Stop, to send SIGTERM. Option-click Stop for SIGKILL.
- Right-click a row to pin, hide, copy the URL or port, open the project in an installed editor or terminal, or reveal its working directory.
- After Stop, the row shows "stopping…". If the process ignores SIGTERM for a few seconds, a Force kill button appears.
- With more than 8 rows a filter field appears. Type a port, project, process, or branch.
- An orange network icon marks servers bound to all interfaces (reachable from your network).
- Click a blip on the radar to open that server. Click empty scope for a ping.
- Click a row to open it in the browser (non-HTTP rows show details instead). The chevron shows command line, folder, PID, with copy buttons.
- Servers from the same folder are grouped under a project header. A dot before the port shows the HTTP status: green answered, yellow 4xx, red 5xx, grey open but silent.
- Keyboard: ↑ ↓ select, ↩ open, Space details, ⌘⌫ stop (⌥ for SIGKILL), ⌘F filter, ⎋ clear.
- Recently stopped servers stay listed at the bottom with a "Start again" button that reruns the same command in the same folder.
- Settings (gear in the footer): hotkey, reopen panel where you left it, menu bar badge style, refresh rate, radar on/off.

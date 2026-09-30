# Building, installing, releasing

How Portscope gets from source to a running menu bar item, and how a new version goes out. Everything here assumes Apple Silicon and macOS 26. There is no app bundle and no Apple Developer account involved.

## Building

```sh
swift build              # debug, .build/debug/Portscope
swift build -c release   # release, .build/release/Portscope
swift test               # needs Xcode; the Command Line Tools ship without XCTest
```

Two targets: `PortscopeCore` (Foundation only, unit-tested) and `Portscope` (SwiftUI/AppKit app). CI runs build and tests on every push to `main` via [`.github/workflows/swift.yml`](../.github/workflows/swift.yml).

`Portscope --version` prints the version and exits. The constant lives in `Sources/Portscope/PortscopeApp.swift` and is the single source of truth; the publish script bumps it.

## Running it as a login item

The binary is a plain executable, so "start at login" is a LaunchAgent, not `SMAppService`. Three ways to get there:

| | Command | Where it goes | Started by |
|---|---|---|---|
| From source | `make install` | `~/.local/bin/Portscope` | LaunchAgent `dev.martinprinz.portscope` |
| Release tarball | `make install-binary` (inside the unpacked tarball) | same | same |
| Homebrew | `brew install fuasmattn/tap/portscope`, then `brew services start portscope` | `/opt/homebrew/opt/portscope/bin/Portscope` | LaunchAgent `homebrew.mxcl.portscope` |

`make restart` rebuilds and reloads the agent, `make uninstall` removes agent and binary, `make status` shows launchctl's view. For Homebrew the equivalents are `brew upgrade portscope`, `brew services stop portscope`, `brew uninstall portscope`.

Do not run two of these at once. Two agents means two menu bar items scanning the same ports.

The agent plist sets `ProcessType Interactive` and `LimitLoadToSessionType Aqua`, so it only runs in a GUI session, and restarts the app if it crashes but not after a clean quit.

## Signing and Gatekeeper

The release binary is ad-hoc signed (`codesign -s -`). That satisfies the kernel on Apple Silicon, which refuses to run unsigned code at all, but it does not satisfy Gatekeeper for files that carry the quarantine attribute, which every browser download does.

- `make install-binary` runs `xattr -d com.apple.quarantine` on the copied binary.
- Homebrew downloads with curl, which does not set the attribute, so the brew path never hits Gatekeeper.
- Someone who unpacks the tarball and double-clicks the binary will see "cannot be opened". That is expected.

Proper notarization needs a Developer ID certificate and an app bundle. Not planned until there is a reason.

## Cutting a release

```sh
make publish VERSION=0.2.0
```

That runs [`scripts/publish.sh`](../scripts/publish.sh), which:

1. Refuses to run unless the tree is clean, you are on `main`, the tag does not exist, and `gh` is logged in.
2. Sets the version constant, commits `Release 0.2.0`, tags `v0.2.0`.
3. Builds release, ad-hoc signs, checks that `--version` agrees, packages `Portscope-0.2.0-macos-arm64.tar.gz` with the binary, `Makefile`, and `LICENSE`, and computes the SHA-256.
4. Pushes `main` and the tag, creates the GitHub release with auto-generated notes plus install instructions and the checksum, uploads the tarball.
5. Clones the tap, rewrites `url`, `version`, `sha256`, and the test assertion in `Formula/portscope.rb`, commits, pushes.

After that, `brew upgrade portscope` picks it up. If a step fails midway, the earlier steps have already happened: check `git tag`, the releases page, and the tap before re-running.

Write the changelog into the release on GitHub afterwards if the generated notes are not enough. `gh release edit v0.2.0 --notes-file ...` works.

## The Homebrew tap

Lives at [Fuasmattn/homebrew-tap](https://github.com/Fuasmattn/homebrew-tap). One formula, `Formula/portscope.rb`, which:

- downloads the release tarball (no compile, so users do not need a toolchain),
- requires `arm64` and macOS 26 (`:tahoe`),
- installs the binary into `bin`,
- declares a `service` block so `brew services` writes and loads the LaunchAgent, with `keep_alive crashed: true` and `process_type :interactive`,
- tests `Portscope --version`.

`brew style fuasmattn/tap` and `brew audit --formula fuasmattn/tap/portscope` should stay clean. One gotcha: Homebrew treats any formula without a bottle as a source build and checks that the Command Line Tools are current, even though this one only copies a file. If `brew install` complains about outdated CLT, that is the user's toolchain, not the formula.

Homebrew core is not an option yet; it wants a notable project and a proper build from source. The tap is fine for now.

## Versioning

Semver, tags `vX.Y.Z`. Patch for fixes, minor for features, major when the panel or its settings change in a way that breaks an existing install. Version `0.x` until the settings and keyboard map settle.

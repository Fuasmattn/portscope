#!/usr/bin/env bash
# Cut a release: bump the version constant, tag, build, sign, package, publish to GitHub,
# and update the Homebrew tap formula. Run from the repo root via `make publish VERSION=x.y.z`.
#
# Needs: a clean tree on main, the Swift toolchain, `gh` logged in with push access to
# Fuasmattn/portscope and Fuasmattn/homebrew-tap.
set -euo pipefail

VERSION="${1:?usage: publish.sh x.y.z}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 1; }
TAG="v$VERSION"
REPO="Fuasmattn/portscope"
TAP_REPO="Fuasmattn/homebrew-tap"
ASSET="Portscope-$VERSION-macos-arm64.tar.gz"
VERSION_FILE="Sources/Portscope/PortscopeApp.swift"

cd "$(git rev-parse --show-toplevel)"

# Preconditions
[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "not on main"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "tag $TAG exists"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not logged in"; exit 1; }
grep -q 'static let version = "' "$VERSION_FILE" || { echo "version constant not found in $VERSION_FILE"; exit 1; }

# 1. Version bump, commit, tag
sed -i '' "s/static let version = \"[^\"]*\"/static let version = \"$VERSION\"/" "$VERSION_FILE"
git add "$VERSION_FILE"
git commit -q -m "Release $VERSION"
git tag -a "$TAG" -m "Portscope $VERSION"
echo "Tagged $TAG"

# 2. Build, sign, package
swift build -c release 2>&1 | tail -1
codesign -s - --force .build/release/Portscope
[[ "$(.build/release/Portscope --version)" == "Portscope $VERSION" ]] || { echo "binary reports the wrong version"; exit 1; }
WORK="$(mktemp -d)"
STAGE="$WORK/portscope-$VERSION"
mkdir -p "$STAGE"
cp .build/release/Portscope Makefile LICENSE "$STAGE/"
tar -C "$WORK" -czf "$WORK/$ASSET" "portscope-$VERSION"
SHA="$(shasum -a 256 "$WORK/$ASSET" | cut -d' ' -f1)"
echo "Packaged $ASSET ($SHA)"

# 3. Push and publish the GitHub release
git push -q origin main "$TAG"
NOTES="$WORK/notes.md"
cat > "$NOTES" <<NOTES
## Install

\`\`\`sh
brew install fuasmattn/tap/portscope && brew services start portscope
\`\`\`

Or from source: \`git clone https://github.com/$REPO.git && cd portscope && make install\`

Or the tarball below (ad-hoc signed, not notarized): unpack it and run \`make install-binary\` inside.

SHA-256: \`$SHA\`
NOTES
gh release create "$TAG" "$WORK/$ASSET" --repo "$REPO" --title "Portscope $VERSION" --generate-notes --notes-file "$NOTES"
echo "Released https://github.com/$REPO/releases/tag/$TAG"

# 4. Point the Homebrew formula at the new asset
TAP="$WORK/tap"
gh repo clone "$TAP_REPO" "$TAP" -- -q
FORMULA="$TAP/Formula/portscope.rb"
sed -i '' \
  -e "s#releases/download/v[^/]*/Portscope-[^\"]*\.tar\.gz#releases/download/$TAG/$ASSET#" \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  -e "s/assert_match \"Portscope [0-9.]*\"/assert_match \"Portscope $VERSION\"/" \
  "$FORMULA"
git -C "$TAP" -c user.name=Fuasmattn -c user.email=5929583+Fuasmattn@users.noreply.github.com \
  commit -qam "portscope $VERSION"
git -C "$TAP" push -q origin main
echo "Formula updated in $TAP_REPO"

rm -rf "$WORK"
echo "Done. Users get it with: brew upgrade portscope"

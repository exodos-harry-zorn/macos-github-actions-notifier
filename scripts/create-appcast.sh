#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Packaging/Info.plist")}"
TAG="${TAG:-v$VERSION}"
DIST_DIR="$ROOT_DIR/dist"
UPDATES_DIR="$DIST_DIR/sparkle-updates"
DMG_NAME="GitHub-Actions-Notifier-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "SPARKLE_PRIVATE_KEY is required to sign the Sparkle appcast." >&2
  echo "Generate it with Sparkle's generate_keys tool and store the private key as a GitHub Actions secret." >&2
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast tool not found. Run swift package resolve first." >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  echo "Run ./scripts/create-dmg.sh first." >&2
  exit 1
fi

rm -rf "$UPDATES_DIR"
mkdir -p "$UPDATES_DIR"
cp "$DMG_PATH" "$UPDATES_DIR/$DMG_NAME"

if [[ -f "$DIST_DIR/release-notes.md" ]]; then
  cp "$DIST_DIR/release-notes.md" "$UPDATES_DIR/GitHub-Actions-Notifier-${VERSION}.md"
fi

echo "$PRIVATE_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/exodos-harry-zorn/macos-github-actions-notifier/releases/download/$TAG/" \
  --full-release-notes-url "https://github.com/exodos-harry-zorn/macos-github-actions-notifier/releases" \
  --embed-release-notes \
  --maximum-versions 1 \
  -o "$UPDATES_DIR/appcast.xml" \
  "$UPDATES_DIR"

cp "$UPDATES_DIR/appcast.xml" "$APPCAST_PATH"
echo "Built $APPCAST_PATH"

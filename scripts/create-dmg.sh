#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GitHub Actions Notifier"
APP_PATH="${APP_PATH:-$ROOT_DIR/dist/$APP_NAME.app}"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')}"
DMG_NAME="GitHub-Actions-Notifier-${VERSION}.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run ./scripts/build-app.sh first." >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
echo "Built $DMG_PATH"

#!/bin/bash
# make-app.sh — assemble dist/Tempo.app from a release build of the `tempo`
# SwiftPM executable.
#
# Idempotent: safe to re-run in any state. Always builds fresh, always
# rebuilds the .app bundle from scratch (rm -rf before assembling), and the
# Info.plist is generated from the heredoc below — there is no separate
# checked-in plist to drift out of sync.
#
# Usage: scripts/make-app.sh   (from anywhere; resolves the repo root itself)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Tempo"
EXECUTABLE_NAME="tempo"
BUNDLE_ID="com.gameslayer999.tempo"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
RELEASE_BIN="$REPO_ROOT/.build/release/${EXECUTABLE_NAME}"

# ---------------------------------------------------------------------------
# 1. Build (release). SwiftPM serializes concurrent builds on a lock file in
#    .build/; another agent building this repo at the same time can cause a
#    transient failure. Retry a couple of times before giving up.
# ---------------------------------------------------------------------------
echo "==> Building ${EXECUTABLE_NAME} (release)…"

MAX_ATTEMPTS=3
ATTEMPT=1
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT

while true; do
  if swift build -c release 2>&1 | tee "$BUILD_LOG"; then
    break
  fi
  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "error: swift build failed after ${ATTEMPT} attempts" >&2
    exit 1
  fi
  if grep -qiE "resource temporarily unavailable|another instance|lock|database is locked" "$BUILD_LOG"; then
    ATTEMPT=$((ATTEMPT + 1))
    echo "==> Build lock contention detected; retrying in 15s (attempt ${ATTEMPT}/${MAX_ATTEMPTS})…" >&2
    sleep 15
  else
    echo "error: swift build failed (not a lock contention issue)" >&2
    exit 1
  fi
done

if [ ! -x "$RELEASE_BIN" ]; then
  echo "error: expected release binary not found at $RELEASE_BIN" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Assemble the .app bundle fresh (never layer on top of a stale one).
# ---------------------------------------------------------------------------
echo "==> Assembling ${APP_NAME}.app…"

rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" || {
  echo "error: failed to create bundle directory structure" >&2
  exit 1
}

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/${EXECUTABLE_NAME}" || {
  echo "error: failed to copy release binary into bundle" >&2
  exit 1
}
chmod +x "$APP_BUNDLE/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>${EXECUTABLE_NAME}</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Tempo controls Spotify via AppleScript to read now-playing track info and drive playback (play, pause, previous, next).</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Tempo captures Spotify's audio output solely to animate the notch visualizer; audio is never recorded or stored.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# 3. Codesign. Prefer a real "Apple Development" identity if one is
#    installed in the keychain; otherwise fall back to ad-hoc signing.
# ---------------------------------------------------------------------------
echo "==> Codesigning…"

IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development")"

if [ -n "$IDENTITY_LINE" ]; then
  IDENTITY_HASH="$(echo "$IDENTITY_LINE" | awk '{print $2}')"
  echo "==> Signing path: Apple Development identity (${IDENTITY_HASH})"
  codesign --force --deep --sign "$IDENTITY_HASH" --identifier "$BUNDLE_ID" "$APP_BUNDLE" || {
    echo "error: codesign with Apple Development identity failed" >&2
    exit 1
  }
else
  echo "==> Signing path: ad-hoc (no Apple Development identity found in keychain)"
  echo "==> WARNING: ad-hoc signing means TCC permission grants (Automation/Audio) are tied to this exact binary and are NOT guaranteed to survive a rebuild — get a real Apple Development identity for stable TCC identity across rebuilds."
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" || {
    echo "error: ad-hoc codesign failed" >&2
    exit 1
  }
fi

# ---------------------------------------------------------------------------
# 4. Verify.
# ---------------------------------------------------------------------------
echo "==> Verifying codesign…"
if ! codesign --verify --deep --strict -v "$APP_BUNDLE"; then
  echo "error: codesign --verify failed" >&2
  exit 1
fi

echo "==> Linting Info.plist…"
if ! plutil -lint "$APP_BUNDLE/Contents/Info.plist"; then
  echo "error: plutil -lint failed on Info.plist" >&2
  exit 1
fi

echo "==> Done: $APP_BUNDLE"

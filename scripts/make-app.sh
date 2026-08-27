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
# The MediaRemote adapter must exist before the bundle is assembled — it is
# copied into Contents/Resources below, and Tempo has no now-playing signal
# without it. Its own script verifies the entitlement still holds.
echo "==> Building the MediaRemote adapter…"
if ! "$SCRIPT_DIR/build-media-adapter.sh"; then
  echo "error: scripts/build-media-adapter.sh failed" >&2
  exit 1
fi

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

# The adapter: the perl loader plus the framework it dlopen()s. Both live in
# Resources, which is where MediaRemoteService looks first.
cp "$REPO_ROOT/Vendor/build/mediaremote-adapter.pl" "$APP_BUNDLE/Contents/Resources/" || {
  echo "error: failed to copy mediaremote-adapter.pl into bundle" >&2
  exit 1
}
cp -R "$REPO_ROOT/Vendor/build/MediaRemoteAdapter.framework" "$APP_BUNDLE/Contents/Resources/" || {
  echo "error: failed to copy MediaRemoteAdapter.framework into bundle" >&2
  exit 1
}

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
	<string>0.2.0</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Tempo controls Spotify via AppleScript to read now-playing track info and drive playback (play, pause, previous, next).</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Tempo shows a brief notice in the notch when a Bluetooth device connects or disconnects. It never pairs, configures or transfers data.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Tempo captures Spotify's audio output solely to animate the notch visualizer; audio is never recorded or stored.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Tempo uses your approximate location to show current weather on the lock-screen card. The coordinate is rounded, used only for that weather lookup, and never stored or shared. You can type a city in Settings instead.</string>
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

# ---------------------------------------------------------------------------
# 5. Restart any instance that was running the bundle we just replaced.
#    `open dist/Tempo.app` on an already-running app activates the existing
#    process instead of launching the new binary, so without this a rebuild
#    silently keeps testing the old build. Cost real debugging time once
#    (2026-08-20): a process from before three rebuilds was still the one on
#    screen, which read as "the new feature isn't there".
#
#    Quit *and relaunch*, never just quit: a rebuild has to hand back a running
#    app in the state it found, otherwise it silently takes the notch off screen
#    — which cost another round trip the first time this step only killed.
#    An app that was not running stays not running.
# ---------------------------------------------------------------------------
# Match the bundle-relative suffix, not $APP_BUNDLE: the repo resolves under
# both /Users/…/Documents/code/Tempo and /Users/…/documents/code/tempo (the
# filesystem is case-insensitive, `pgrep -f` is not), so an absolute-path
# pattern misses a process launched via the other spelling.
RUNNING_PIDS="$(pgrep -f "${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" || true)"
if [ -n "$RUNNING_PIDS" ]; then
  echo "==> Quitting the running ${APP_NAME} (PID $(echo "$RUNNING_PIDS" | tr '\n' ' ' | sed 's/ $//')) so the next launch uses this build…"
  # SIGTERM only: the app has no unsaved state, and a stuck process is the
  # user's to deal with rather than something this script should SIGKILL.
  #
  # This is a real quit, not a kill: Tempo routes SIGTERM through
  # `NSApplication.terminate` (decision 067), so `applicationWillTerminate`
  # runs and reaps its `/usr/bin/perl` mediaremote-adapter child. It did not
  # always — the kernel's default disposition killed the process outright, and
  # every rebuild orphaned an adapter to PPID 1. Deliberately *not* switched to
  # `osascript … to quit`, which would have worked equally well and cost this
  # script an Automation (Apple Events) TCC prompt it has never needed.
  echo "$RUNNING_PIDS" | xargs kill 2>/dev/null || true

  # Wait for the old process to actually go before relaunching, so `open`
  # can't find a live instance and just activate it again.
  for _ in $(seq 1 20); do
    pgrep -f "${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" >/dev/null || break
    sleep 0.25
  done

  if pgrep -f "${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" >/dev/null; then
    echo "==> WARNING: the old ${APP_NAME} did not exit; not relaunching. Quit it and run: open $APP_BUNDLE" >&2
  else
    echo "==> Relaunching ${APP_NAME}…"
    open "$APP_BUNDLE" || echo "==> WARNING: relaunch failed; run: open $APP_BUNDLE" >&2
  fi
fi

echo "==> Done: $APP_BUNDLE"
echo "==> Launch it with: open $APP_BUNDLE  (already relaunched if it was running)"

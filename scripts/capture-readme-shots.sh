#!/usr/bin/env bash
#
# capture-readme-shots.sh — regenerate the screenshots embedded in README.md.
#
# Drives the *running* Tempo app the way a user would (pointer onto the notch to
# expand, click the gear to open Settings) and captures each state with
# `screencapture`. Idempotent: re-running overwrites docs/images/*.png and
# leaves Spotify and the pointer where it found them.
#
# Requirements, all one-time and reported by name if missing:
#   - dist/Tempo.app running (./scripts/make-app.sh && open dist/Tempo.app)
#   - the invoking terminal has Screen Recording   (System Settings ▸ Privacy &
#     Security ▸ Screen & System Audio Recording) — for `screencapture`
#   - the invoking terminal has Accessibility      (…▸ Accessibility) — to post
#     the pointer moves and the gear click
#   - Spotify running with a track loaded, so the shots show real artwork and
#     live visualizer bars rather than the media-off pill
#
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="docs/images"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# ---------------------------------------------------------------- helper -----
# Pointer control + screen/notch geometry. Compiled here rather than shipped as
# a binary so the script stays the only thing to run.
cat > "$WORK/shotkit.swift" <<'SWIFT'
import AppKit

/// The notched screen if there is one, else the main screen.
let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main!

/// Move the pointer to a top-left-origin point and let apps see it move.
/// The warp alone repositions the cursor without generating an event some
/// windows act on; the posted `mouseMoved` is what triggers Tempo's hover.
func move(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    CGWarpMouseCursorPosition(p)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func click(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "geom":
    let f = screen.frame
    // Notch width is the gap between the two auxiliary areas flanking it;
    // zero on a notchless display, where Tempo draws its fallback strip.
    var nw = 0.0, nh = 0.0
    if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
        nw = r.minX - l.maxX
        nh = f.maxY - l.minY
    }
    // Emitted as shell assignments so the caller can `eval` them.
    print("SCREEN_W=\(f.width) SCREEN_H=\(f.height) NOTCH_W=\(nw) NOTCH_H=\(nh)")
case "pointer":
    let p = NSEvent.mouseLocation                       // bottom-left origin
    print("\(p.x) \(screen.frame.maxY - p.y)")          // → top-left origin
case "move":
    move(Double(args[1])!, Double(args[2])!)
case "click":
    move(Double(args[1])!, Double(args[2])!)
    usleep(120_000)
    click(Double(args[1])!, Double(args[2])!)
case "window":
    // Frame of the frontmost window of the named app, top-left origin, via the
    // window-server list (Tempo's panel and Settings window are both
    // non-activating, so AppleScript's `window` of System Events misses them).
    let name = args[1]
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerName as String] as? String) == name {
        guard let b = w[kCGWindowBounds as String] as? [String: Double],
              (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 200 else { continue }
        print("\(b["X"]!) \(b["Y"]!) \(b["Width"]!) \(b["Height"]!)")
        exit(0)
    }
    exit(1)
default:
    FileHandle.standardError.write(Data("usage: shotkit geom|pointer|move|click|window\n".utf8))
    exit(2)
}
SWIFT
swiftc -O "$WORK/shotkit.swift" -o "$WORK/shotkit"
kit="$WORK/shotkit"

# ------------------------------------------------------------ preflight -----
pgrep -qf 'Tempo.app/Contents/MacOS/tempo' \
  || { echo "Tempo is not running — ./scripts/make-app.sh && open dist/Tempo.app" >&2; exit 1; }

screencapture -x -R 0,0,10,10 "$WORK/probe.png" 2>/dev/null \
  || { echo "No Screen Recording permission for this terminal — grant it in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then relaunch the terminal." >&2; exit 1; }

eval "$($kit geom)"
echo "screen ${SCREEN_W}x${SCREEN_H}, notch ${NOTCH_W}x${NOTCH_H}"

# Panel geometry, mirroring NotchGeometry in Sources/tempo/NotchWindow.swift.
SIDE_PADDING=110
PANEL_H=280
PANEL_W=$(echo "$NOTCH_W + $SIDE_PADDING * 2" | bc)
PANEL_X=$(echo "$SCREEN_W / 2 - $PANEL_W / 2" | bc -l)
NOTCH_CX=$(echo "$SCREEN_W / 2" | bc -l)

shot() {  # shot <name> <x> <y> <w> <h>
  screencapture -x -R"$2,$3,$4,$5" "$OUT/$1.png"
  echo "  → $OUT/$1.png"
}

# Remember what to put back.
read -r HOME_X HOME_Y <<<"$($kit pointer)"
WAS_PLAYING=$(osascript -e 'tell application "Spotify" to return player state' 2>/dev/null || echo unknown)

restore() {
  [ "$WAS_PLAYING" = "playing" ] || osascript -e 'tell application "Spotify" to pause' 2>/dev/null || true
  $kit move "$HOME_X" "$HOME_Y"
}
trap 'restore; rm -rf "$WORK"' EXIT

# --------------------------------------------------------------- capture ----
# Playing, not paused: the collapsed pill drops its artwork, visualizer and
# transport controls after a minute with no playback, and the shots would show
# a bare notch.
osascript -e 'tell application "Spotify" to play' 2>/dev/null || true
sleep 3

echo "collapsed pill…"
$kit move "$NOTCH_CX" $(echo "$SCREEN_H - 120" | bc -l)   # pointer off the notch
sleep 1.5
shot collapsed \
  $(echo "$PANEL_X - 40" | bc -l) 0 $(echo "$PANEL_W + 80" | bc -l) 72

echo "expanded panel…"
$kit move "$NOTCH_CX" 12
sleep 1.5
shot expanded \
  $(echo "$PANEL_X - 40" | bc -l) 0 $(echo "$PANEL_W + 80" | bc -l) \
  $(echo "$PANEL_H + 20" | bc -l)

echo "settings window…"
# The gear sits in the expanded content's top-right corner: inset
# `expandedTopRadius (19) + 7` from the panel edge, less the button style's own
# 8pt padding, ~34pt below the panel top (strip height + the content's 16pt
# vertical padding).
$kit click $(echo "$PANEL_X + $PANEL_W - 21" | bc -l) $(echo "$NOTCH_H + 20" | bc -l)
sleep 2
if read -r SX SY SW SH <<<"$($kit window Tempo)"; then
  shot settings "$SX" "$SY" "$SW" "$SH"
  osascript -e 'tell application "System Events" to tell process "Tempo" to click button 1 of window 1' 2>/dev/null || true
else
  echo "  ! Settings window not found — the gear click missed; capture it by hand." >&2
fi

echo "done."

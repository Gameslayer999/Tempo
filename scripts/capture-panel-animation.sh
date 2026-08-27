#!/usr/bin/env bash
#
# capture-panel-animation.sh — record the panel opening and closing, and slice
# the result into numbered frames you can read one at a time.
#
# Animation quality is the thing this category lives or dies on (UI Design
# Principle #5), and it is not something a description can be checked against:
# decision 065 is a black slab and a half-second ghost that both existed for
# weeks on a notchless display and were invisible to every other kind of test.
# This is how that was found, kept so the next animation change is looked at
# rather than reasoned about (Agent Guideline #8).
#
# Drives the *running* Tempo app the way a user would — pointer up into the
# hover region, hold, pointer away — while `screencapture -v` records the top
# of the screen. Leaves the pointer where it found it. Writes nothing outside
# the output directory.
#
# Requirements, all one-time and reported by name if missing:
#   - dist/Tempo.app running (./scripts/make-app.sh && open dist/Tempo.app)
#   - the invoking terminal has Screen Recording   (System Settings ▸ Privacy &
#     Security ▸ Screen & System Audio Recording) — for `screencapture`
#   - the invoking terminal has Accessibility      (…▸ Accessibility) — to post
#     the pointer moves
#   - ffmpeg on PATH (brew install ffmpeg) — to slice frames
#
# Usage:  ./scripts/capture-panel-animation.sh [OUT_DIR]
#         OUT_DIR defaults to a fresh temp directory, printed at the end.
#
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-$(mktemp -d /tmp/tempo-anim.XXXXXX)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

HOLD=2.5          # seconds the panel is held open
FPS=25            # slice rate; 25 is fine for a 0.45s spring
REC=7             # total recording length, must cover approach + HOLD + close

# ---------------------------------------------------------------- helper -----
cat > "$WORK/kit.swift" <<'SWIFT'
import AppKit

/// The notched screen if there is one, else the main screen — the same screen
/// Tempo picks, so the geometry below is the geometry it drew to.
let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main!

/// Move the pointer to a top-left-origin point and let apps see it move. The
/// warp alone repositions the cursor without generating an event; the posted
/// `mouseMoved` is what `NotchHoverDetector`'s global monitor acts on.
func move(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    CGWarpMouseCursorPosition(p)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "geom":
    let f = screen.frame
    print("SCREEN_X=\(f.minX) SCREEN_W=\(f.width) SCREEN_H=\(f.height)")
case "pointer":
    let p = NSEvent.mouseLocation                       // bottom-left origin
    print("\(p.x) \(screen.frame.maxY - p.y)")          // → top-left origin
case "move":
    move(Double(args[1])!, Double(args[2])!)
case "run":
    // approach → hover → hold → leave. Stepped rather than teleported: a
    // single warp onto the notch is one event, and the hover dwell wants to
    // see the pointer arrive the way a hand delivers it.
    let cx = Double(args[1])!, hold = Double(args[2])!
    for i in 0...10 { move(cx, 300 - Double(i) * 29); usleep(20_000) }
    move(cx, 4); usleep(30_000); move(cx, 6); usleep(30_000); move(cx, 4)
    usleep(UInt32(hold * 1_000_000))
    for i in 1...15 { move(cx, Double(i) * 40); usleep(8_000) }
    move(cx, 700)
    usleep(UInt32(hold * 1_000_000))
default:
    FileHandle.standardError.write(Data("usage: kit geom|pointer|move|run\n".utf8))
    exit(2)
}
SWIFT
swiftc -O "$WORK/kit.swift" -o "$WORK/kit"
kit="$WORK/kit"

# ------------------------------------------------------------ preflight -----
pgrep -qf 'Tempo.app/Contents/MacOS/tempo' \
  || { echo "Tempo is not running — ./scripts/make-app.sh && open dist/Tempo.app" >&2; exit 1; }
command -v ffmpeg >/dev/null \
  || { echo "ffmpeg not found — brew install ffmpeg" >&2; exit 1; }

eval "$($kit geom)"
CX=$(printf '%.0f' "$(echo "$SCREEN_X + $SCREEN_W / 2" | bc -l)")
# Region around the panel: it is 640pt at its widest and never taller than
# 680pt, so 1200x420 centred on the notch holds it with room to see anything
# that spills outside it — which is the whole point of watching the frames.
RX=$((CX - 600))
read -r HOME_X HOME_Y <<<"$($kit pointer)"
restore() { $kit move "$HOME_X" "$HOME_Y"; }
trap 'restore; rm -rf "$WORK"' EXIT   # restore first: `restore` runs $kit, which lives in $WORK

# -------------------------------------------------------------- capture -----
echo "==> Recording ${REC}s at ${RX},0 1200x420…"
rm -f "$OUT/panel.mov"
screencapture -v -V "$REC" -R "$RX,0,1200,420" "$OUT/panel.mov" &
sleep 1.5
$kit run "$CX" "$HOLD"
wait

# ---------------------------------------------------------------- slice -----
# Two products, because they answer different questions. The contact sheet
# says *when* things happen — find the open and the close on it. The numbered
# frames are what you then read one at a time to see *what* happens.
echo "==> Slicing…"
rm -rf "$OUT/frames"; mkdir -p "$OUT/frames"
ffmpeg -loglevel error -y -i "$OUT/panel.mov" \
  -vf "fps=$FPS,drawtext=text='%{pts}':fontcolor=yellow:x=6:y=6:fontsize=22" \
  "$OUT/frames/%03d.png"
ffmpeg -loglevel error -y -i "$OUT/panel.mov" \
  -vf "fps=8,scale=420:-1,drawtext=text='%{pts}':fontcolor=yellow:x=4:y=4:fontsize=18,tile=8x7" \
  -frames:v 1 "$OUT/contact-sheet.png"

echo "==> Done."
echo "    timeline : $OUT/contact-sheet.png   (8fps, seconds stamped on each cell)"
echo "    frames   : $OUT/frames/*.png        (${FPS}fps, $(ls "$OUT/frames" | wc -l | tr -d ' ') of them)"
echo "    video    : $OUT/panel.mov"

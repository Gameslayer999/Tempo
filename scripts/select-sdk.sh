#!/bin/bash
# select-sdk.sh — print the path of a macOS SDK this machine can actually
# build Tempo against, and keep a copy of it out of the installer's reach.
#
# Why this exists (decision 098): the macOS 27 SDK turned SwiftUI's `@State`
# into a macro implemented by a `SwiftUIMacros` compiler plugin that ships
# only inside Xcode. On a Command-Line-Tools-only machine every SwiftUI file
# then fails with "plugin for module 'SwiftUIMacros' not found", so the
# Command Line Tools 27.0 update broke `swift build` outright.
#
# Nothing here is pinned to a version number. Each candidate SDK is *probed*
# — a five-line SwiftUI file with a `@State` in it is typechecked against it —
# and the newest one that compiles wins. The day a toolchain ships the plugin,
# the newest SDK starts passing and gets picked with no edit to this script.
#
# Idempotent and safe to re-run in any state (Agent Guideline #8): it prints a
# path and touches nothing but its own cache and SDK copy.
#
# Usage:  scripts/select-sdk.sh [--refresh]
#         SDKROOT="$(scripts/select-sdk.sh)" swift build
# Output: the SDK path on stdout, everything else on stderr.

set -uo pipefail

TEMPO_DIR="$HOME/Library/Developer/Tempo"
VENDOR_DIR="$TEMPO_DIR/SDKs"
CACHE_FILE="$TEMPO_DIR/sdk-pin"
DEPLOYMENT_TARGET="14.0"   # matches Package.swift's .macOS(.v14)

REFRESH=0
[ "${1:-}" = "--refresh" ] && REFRESH=1

note() { echo "$@" >&2; }

# ---------------------------------------------------------------------------
# Candidates: every macOS SDK on the machine, newest first.
#
# The vendored copy is in the list like any other, so if a future installer
# drops the SDK this picked, the copy is simply the next candidate found —
# there is no separate fallback path to go stale.
# ---------------------------------------------------------------------------
sdk_version() { plutil -extract Version raw "$1/SDKSettings.plist" 2>/dev/null; }

candidates() {
  local roots root sdk real version
  roots="/Library/Developer/CommandLineTools/SDKs
$(xcode-select -p 2>/dev/null)/Platforms/MacOSX.platform/Developer/SDKs
$VENDOR_DIR"

  # "<version> <path>" per line; symlinks resolved so MacOSX26.sdk and the
  # MacOSX26.5.sdk it points at are not probed twice.
  while IFS= read -r root; do
    [ -d "$root" ] || continue
    for sdk in "$root"/MacOSX*.sdk; do
      [ -d "$sdk" ] || continue
      real="$(cd "$sdk" && pwd -P)" || continue
      version="$(sdk_version "$real")"
      [ -n "$version" ] && echo "$version $real"
    done
  done <<< "$roots" | sort -u -k2 | sort -t. -k1,1nr -k2,2nr -k3,3nr
}

# ---------------------------------------------------------------------------
# The probe. `@State` is the construct that broke; typechecking is enough to
# hit the missing plugin, and needs no link step.
# ---------------------------------------------------------------------------
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_DIR"' EXIT
cat > "$PROBE_DIR/probe.swift" <<'SWIFT'
import SwiftUI

struct SDKProbe: View {
    @State private var value = 0
    var body: some View { Text("\(value)") }
}
SWIFT

probe() {
  swiftc -typecheck \
    -sdk "$1" \
    -target "$(uname -m)-apple-macos$DEPLOYMENT_TARGET" \
    "$PROBE_DIR/probe.swift" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Cache. Probing costs a few seconds per candidate, and every build would pay
# it. The key is the compiler plus the full candidate list, so installing or
# removing an SDK — or updating the toolchain — re-probes on its own.
# ---------------------------------------------------------------------------
CANDIDATES="$(candidates)"
if [ -z "$CANDIDATES" ]; then
  note "error: no macOS SDK found under CommandLineTools, Xcode or $VENDOR_DIR"
  exit 1
fi

KEY="$(printf '%s\n%s\n' "$(swiftc --version 2>/dev/null | head -1)" "$CANDIDATES" | shasum | awk '{print $1}')"

if [ "$REFRESH" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  CACHED_KEY="$(sed -n 1p "$CACHE_FILE")"
  CACHED_SDK="$(sed -n 2p "$CACHE_FILE")"
  if [ "$CACHED_KEY" = "$KEY" ] && [ -d "$CACHED_SDK" ]; then
    echo "$CACHED_SDK"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Probe newest first.
# ---------------------------------------------------------------------------
CHOSEN=""
while IFS=' ' read -r version path; do
  [ -n "$path" ] || continue
  if probe "$path"; then
    CHOSEN="$path"
    note "==> SDK ${version}: builds SwiftUI — using $path"
    break
  fi
  note "==> SDK ${version}: cannot build SwiftUI here (compiler plugin missing) — skipping"
done <<< "$CANDIDATES"

if [ -z "$CHOSEN" ]; then
  note "error: no installed SDK can compile SwiftUI on this machine."
  note "       Every candidate failed the @State probe:"
  note "$CANDIDATES"
  note "       Installing Xcode supplies the SwiftUIMacros plugin the newest SDK needs."
  exit 1
fi

# ---------------------------------------------------------------------------
# Keep a copy where the installer cannot reach it. Command Line Tools updates
# have left older SDKs in place so far (13.1 from 2022 and 15.2 from 2024 both
# survived the 27.0 update), but a reinstall that ships only the newest SDK
# would leave this machine with nothing that builds. ~333MB, copied once.
# ---------------------------------------------------------------------------
case "$CHOSEN" in
  "$VENDOR_DIR"/*) ;;   # already the copy
  *)
    COPY="$VENDOR_DIR/$(basename "$CHOSEN")"
    if [ ! -d "$COPY" ]; then
      note "==> Copying $(basename "$CHOSEN") to $VENDOR_DIR (once, ~$(du -sh "$CHOSEN" 2>/dev/null | awk '{print $1}')) so an installer cannot remove the only SDK that builds…"
      mkdir -p "$VENDOR_DIR"
      # Copy to a `.partial` name, prove the copy itself compiles SwiftUI, and
      # only then give it the real name — a half-copied SDK that still looked
      # like a candidate would be a trap for the day it is needed. `.partial`
      # is outside the `MacOSX*.sdk` glob above, so a leftover is inert.
      # Copied twice before giving up: the first attempt failed once against
      # this directory and an identical retry succeeded.
      for attempt in 1 2; do
        rm -rf "$COPY.partial" 2>/dev/null
        if ditto "$CHOSEN" "$COPY.partial" && probe "$COPY.partial"; then
          mv "$COPY.partial" "$COPY" && note "==> Copy kept at $COPY"
          break
        fi
        [ "$attempt" = 2 ] && note "==> WARNING: could not copy the SDK; the build still works, but only while $CHOSEN exists"
      done
      rm -rf "$COPY.partial" 2>/dev/null
    fi
    ;;
esac

mkdir -p "$TEMPO_DIR"
printf '%s\n%s\n' "$KEY" "$CHOSEN" > "$CACHE_FILE"

echo "$CHOSEN"

#!/bin/bash
# build-media-adapter.sh — compile the vendored MediaRemote adapter framework.
#
# Tempo reads now-playing state for *any* media app through the MediaRemote
# private framework. Since macOS 15.4 that framework only answers processes
# entitled to use it, so the adapter is loaded inside /usr/bin/perl (which is
# Apple-signed and entitled) via bin/mediaremote-adapter.pl. This script builds
# the dylib that perl dlopen()s.
#
# The upstream project builds with CMake. This script uses clang directly so
# the repo needs no build tooling beyond the Xcode command line tools — the
# perl loader only requires that <Name>.framework/<Name> be a Mach-O dylib
# exporting the adapter_* symbols, not a full versioned framework bundle.
#
# Source: Vendor/mediaremote-adapter (BSD 3-Clause, see its LICENSE), pinned at
# the commit in Vendor/mediaremote-adapter/COMMIT.
#
# Idempotent: safe to re-run in any state; always rebuilds from scratch.
#
# Usage: scripts/build-media-adapter.sh   (from anywhere)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SRC_DIR="$REPO_ROOT/Vendor/mediaremote-adapter"
OUT_DIR="$REPO_ROOT/Vendor/build"
FRAMEWORK="$OUT_DIR/MediaRemoteAdapter.framework"
DYLIB="$FRAMEWORK/MediaRemoteAdapter"

if [ ! -d "$SRC_DIR/src" ]; then
  echo "error: vendored adapter source missing at $SRC_DIR/src" >&2
  exit 1
fi

echo "==> Building MediaRemoteAdapter.framework…"

rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK" || {
  echo "error: failed to create $FRAMEWORK" >&2
  exit 1
}

# Universal binary: Tempo's own release build is whatever `swift build` emits on
# this machine, but the adapter is loaded by Apple's /usr/bin/perl, which is a
# universal binary and may run either slice. Build both so the dlopen cannot
# fail on an architecture mismatch.
#
# -fvisibility=default is load-bearing: the perl script resolves adapter_*
# symbols by name, and they are invisible to DynaLoader without it.
clang -dynamiclib -fobjc-arc -fvisibility=default \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=14.0 \
  -I"$SRC_DIR/include" -I"$SRC_DIR/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
  -o "$DYLIB" \
  "$SRC_DIR"/src/adapter/*.m \
  "$SRC_DIR"/src/private/MediaRemote.m \
  "$SRC_DIR"/src/utility/*.m || {
  echo "error: clang failed to build the adapter dylib" >&2
  exit 1
}

# The perl script loads the dylib by path; copy the loader next to it so the
# whole adapter is one directory to bundle (and one to point at in dev runs).
cp "$SRC_DIR/bin/mediaremote-adapter.pl" "$OUT_DIR/mediaremote-adapter.pl" || {
  echo "error: failed to stage mediaremote-adapter.pl" >&2
  exit 1
}
chmod +x "$OUT_DIR/mediaremote-adapter.pl"

echo "==> Codesigning the adapter framework (ad-hoc)…"
codesign --force --sign - "$FRAMEWORK" || {
  echo "error: ad-hoc codesign of the adapter framework failed" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Verify: the symbols perl resolves must be exported, and the framework must
# actually answer MediaRemote on this macOS version. A dylib that builds but
# is not entitled is exactly the failure this whole approach exists to avoid,
# so check it here rather than discovering it at runtime as an empty notch.
# ---------------------------------------------------------------------------
echo "==> Verifying exported symbols…"
for sym in adapter_stream adapter_get adapter_send adapter_seek; do
  if ! nm -gU "$DYLIB" 2>/dev/null | grep -q "_${sym}$"; then
    echo "error: expected symbol ${sym} not exported by $DYLIB" >&2
    exit 1
  fi
done

echo "==> Verifying MediaRemote access via /usr/bin/perl…"
GET_OUTPUT="$(/usr/bin/perl "$OUT_DIR/mediaremote-adapter.pl" "$FRAMEWORK" get --no-artwork 2>&1)"
GET_STATUS=$?
if [ "$GET_STATUS" -ne 0 ]; then
  echo "error: adapter could not read MediaRemote (exit ${GET_STATUS}):" >&2
  echo "$GET_OUTPUT" >&2
  echo "This usually means macOS tightened the entitlement on /usr/bin/perl." >&2
  exit 1
fi

echo "==> MediaRemote responded. Now playing: ${GET_OUTPUT:-<nothing playing>}"
echo "==> Done: $FRAMEWORK"

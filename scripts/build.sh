#!/bin/bash
# build.sh — `swift build` with an SDK this machine can actually build against.
#
# Plain `swift build` targets the newest installed SDK, which since the macOS
# 27 SDK needs a compiler plugin only Xcode ships (decision 098). This wrapper
# asks scripts/select-sdk.sh for one that works and builds against that.
#
# Usage: scripts/build.sh [any swift build arguments]
#        scripts/build.sh -c release

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(cd "$SCRIPT_DIR/.." && pwd)"

SDK="$("$SCRIPT_DIR/select-sdk.sh")" || exit 1

SDKROOT="$SDK" exec swift build "$@"

#!/bin/bash
# Verify the token and timing figures of decision 048 — what
# `SessionStatsService` reads out of a Claude Code transcript, and how it reads
# it incrementally — against fixture transcripts.
#
# The figures come from a file Tempo does not own and that grows to megabytes
# while it is being read, so the things that can go wrong are: counting a
# subagent's messages into the main context, re-reading the whole file every
# poll, losing an entry to a poll that lands mid-append, and carrying stale
# totals across a rewritten file. Each has a case here.
#
# The shipped service is copied with **only** its projects-directory constant
# redirected at a temp fixture, so nothing here reads anything under ~/.claude
# (Agent Guideline #3) and nothing is stubbed.
#
# Idempotent, self-cleaning, no arguments. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FIX="$(mktemp -d "${TMPDIR:-/tmp}/tempo-stats.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/projects/-fix-proj"

# The shipped service, pointed at the fixture's projects directory.
python3 - "$FIX" <<'PY'
import sys
fix = sys.argv[1]
src = open("Sources/tempo/Services/SessionStatsService.swift").read()
old = ('FileManager.default.homeDirectoryForCurrentUser\n'
       '            .appendingPathComponent(".claude/projects", isDirectory: true)')
new = f'URL(fileURLWithPath: "{fix}/projects", isDirectory: true)'
if old not in src:
    sys.exit("test is out of date with the source — could not redirect:\n" + old)
open(f"{fix}/SessionStatsService.swift", "w").write(src.replace(old, new))
PY

# Transcript fixtures. `phase` picks what the file looks like this poll; the
# service is driven twice per run so the second poll sees only what phase 2
# appended, which is the whole point of the byte cursor.
cat > "$FIX/fixture.py" <<'PY'
import json, os, sys, time
root, phase = sys.argv[1], sys.argv[2]
path = f"{root}/projects/-fix-proj/S1.jsonl"
T = time.time()

def usage(inp, cache_w, cache_r, out):
    return {"input_tokens": inp, "cache_creation_input_tokens": cache_w,
            "cache_read_input_tokens": cache_r, "output_tokens": out}

def assistant(u, sidechain=False):
    return {"type": "assistant", "isSidechain": sidechain,
            "message": {"model": "claude-opus-5", "role": "assistant",
                        "content": [{"type": "text", "text": "x" * 200}], "usage": u}}

def prompt(offset):
    return {"type": "user", "promptSource": "typed", "message": {"role": "user", "content": "hi"},
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(T - offset)) + ".000Z"}

def toolresult():
    return {"type": "user", "message": {"role": "user",
            "content": [{"type": "tool_result", "content": "y" * 500}]}}

def turn_end(ms):
    return {"type": "system", "subtype": "turn_duration", "durationMs": ms, "messageCount": 4}

def write(entries, mode="w", trailing_partial=False):
    with open(path, mode) as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
        if trailing_partial:
            # A poll landing mid-append: a complete JSON object with no newline
            # after it yet.
            f.write(json.dumps(assistant(usage(1, 2, 3, 4)))[:-20])

if phase == "1":
    write([
        prompt(90),
        assistant(usage(10, 1000, 0, 500)),
        toolresult(),
        # A subagent's message: real spend, but not this session's context.
        assistant(usage(5, 200, 40000, 300), sidechain=True),
        assistant(usage(2, 500, 20000, 400)),
    ], trailing_partial=True)
elif phase == "2":
    # Appends only — the fragment phase 1 left is completed first, exactly as
    # Claude Code would finish writing it.
    with open(path, "a") as f:
        f.write(json.dumps(assistant(usage(1, 2, 3, 4)))[-20:] + "\n")
        for e in [assistant(usage(3, 700, 30000, 600)), turn_end(45500)]:
            f.write(json.dumps(e) + "\n")
elif phase == "3":
    # The file was rewritten shorter (a /clear, a resume): totals must reset
    # rather than continue from a file that no longer exists.
    write([prompt(7), assistant(usage(4, 100, 900, 50))])
PY

cat > "$FIX/main.swift" <<SWIFT
import AppKit

var failures = 0

@MainActor
func check(_ name: String, _ got: String, _ want: String) {
    print((got == want ? "PASS  " : "FAIL  ") + name + "   got=\\(got) want=\\(want)")
    if got != want { failures += 1 }
}

@MainActor
func session() -> AgentSession {
    AgentSession(id: "S1", state: "running", label: "fix", updatedAt: Date(),
                 cwd: "/fix/proj", ide: "cli", pid: 1, task: "t")
}

/// One service instance for the whole run: the byte cursor it keeps between
/// polls is the thing under test, so it must survive from phase to phase the
/// way it does in the app.
@MainActor final class Harness {
    let state = AppState()
    lazy var service = SessionStatsService(state: state)
    init() { state.sessions = [session()] }
    func poll() { service.poll() }
    var stats: SessionStats? { state.sessionStats["S1"] }
}

MainActor.assumeIsolated {
    let h = Harness()
    let phase = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"

    if phase == "1" {
        h.poll()
        // Context is the last **main-chain** message only: 2 + 500 + 20000.
        // The subagent's 40k cache read must not appear.
        check("context excludes the subagent", "\\(h.stats?.contextTokens ?? -1)", "20502")
        // Spend includes it: 1510 + 505 + 902.
        check("spend includes the subagent", "\\(h.stats?.sessionTokens ?? -1)", "2917")
        check("a turn is running", "\\(h.stats?.isTiming ?? false)", "true")
        // A range, not an equality: the fixture stamps the prompt 90s ago and
        // the process starts some fraction of a second later.
        let elapsed = h.stats?.elapsed(at: Date()) ?? 0
        check("elapsed counts up from the prompt", "\\(elapsed >= 90 && elapsed < 93)", "true")
        check("and formats as a turn length", SessionStats.compactDuration(90), "1m30s")
    } else {
        h.poll()   // phase-1 contents
        let afterFirst = h.stats?.sessionTokens ?? -1

        Fixture.run("2")
        h.poll()
        // The fragment phase 1 refused to parse is picked up whole once its
        // newline arrives, so its 7 tokens land exactly once, alongside the
        // 1303 of the message appended after it.
        check("the mid-append fragment is not lost",
              "\\((h.stats?.sessionTokens ?? -1) - afterFirst)", "1310")
        check("context follows the newest main-chain message",
              "\\(h.stats?.contextTokens ?? -1)", "30703")
        check("a finished turn stops counting up", "\\(h.stats?.isTiming ?? true)", "false")
        check("and shows what the turn took, rounded to the second",
              SessionStats.compactDuration(h.stats?.lastTurnDuration ?? 0), "46s")

        Fixture.run("3")
        h.poll()
        // 4 + 100 + 50 — the rewritten file's own total, not added to the old.
        check("a shortened file resets the totals", "\\(h.stats?.sessionTokens ?? -1)", "154")
        check("and re-reads its context", "\\(h.stats?.contextTokens ?? -1)", "1004")
    }
}
exit(failures == 0 ? 0 : 1)

enum Fixture {
    static func run(_ phase: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["$FIX/fixture.py", "$FIX", phase]
        try? p.run()
        p.waitUntilExit()
    }
}
SWIFT

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
    find Sources/tempo -name '*.swift' ! -name 'main.swift' ! -name 'SessionStatsService.swift'
)
swiftc -o "$FIX/fixtest" "${SOURCES[@]}" "$FIX/SessionStatsService.swift" "$FIX/main.swift"

status=0
echo "— one poll: context vs spend, subagents, live turn —"
python3 "$FIX/fixture.py" "$FIX" 1 && "$FIX/fixtest" 1 || status=1
echo "— across polls: incremental append, mid-append fragment, rewritten file —"
python3 "$FIX/fixture.py" "$FIX" 1 && "$FIX/fixtest" 2 || status=1

if [ "$status" -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit "$status"

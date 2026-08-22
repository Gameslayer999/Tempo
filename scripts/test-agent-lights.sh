#!/bin/bash
# Verify what the agent lights actually show — the reconciliation of decision
# 043, the unread light of 044 and the shared finish signal of 045 — against
# fixture directories.
#
# The status file records hook *events*, so a turn the user interrupts leaves a
# green light on disk forever, and a background job's `idle` says nothing about
# whether it finished or stopped to ask. The service reconciles both against
# Claude Code's own records, and derives from the same files which finished
# turns the user has not looked at yet. This exercises that logic in the
# shipped source:
# the service file is copied with **only** its two directory constants and its
# `claude` lookup redirected at a temp fixture, so nothing here reads or writes
# anything under ~/.claude (Agent Guideline #3) and nothing is stubbed.
#
# Idempotent, self-cleaning, no arguments. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FIX="$(mktemp -d "${TMPDIR:-/tmp}/tempo-reconcile.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/status/sessions" "$FIX/sessions" "$FIX/jobs/jobF" "$FIX/jobs/jobG"

# A fake `claude` that answers the listing and records every spawn, so the test
# can also assert the query is *not* run when nothing could need it.
cat > "$FIX/claude" <<SH
#!/bin/sh
echo spawn >> "$FIX/spawns.log"
cat "$FIX/agents.json"
SH
chmod +x "$FIX/claude"

# The shipped service, pointed at the fixture.
python3 - "$FIX" <<'PY'
import sys
fix = sys.argv[1]
src = open("Sources/tempo/Services/AgentStatusService.swift").read()
subs = [
    ('FileManager.default.homeDirectoryForCurrentUser\n            .appendingPathComponent(".claude/status/sessions", isDirectory: true)',
     f'URL(fileURLWithPath: "{fix}/status/sessions", isDirectory: true)'),
    ('FileManager.default.homeDirectoryForCurrentUser\n            .appendingPathComponent(".claude/sessions", isDirectory: true)',
     f'URL(fileURLWithPath: "{fix}/sessions", isDirectory: true)'),
    ('FileManager.default.homeDirectoryForCurrentUser\n            .appendingPathComponent(".claude/jobs/\\(jobID)/state.json")',
     f'URL(fileURLWithPath: "{fix}/jobs/\\(jobID)/state.json")'),
    ('run("/usr/bin/which", ["claude"])', f'run("/bin/echo", ["{fix}/claude"])'),
]
for old, new in subs:
    if old not in src:
        sys.exit("test is out of date with the source — could not redirect:\n" + old)
    src = src.replace(old, new)
open(f"{fix}/AgentStatusService.swift", "w").write(src)
PY

# The two fixture states, written fresh before each phase so a rerun cannot
# inherit the previous one.
cat > "$FIX/fixture.py" <<'PY'
import json, os, sys, time
root, phase = sys.argv[1], sys.argv[2]
T = int(time.time())
for f in os.listdir(f"{root}/status/sessions"): os.remove(f"{root}/status/sessions/{f}")
for f in os.listdir(f"{root}/sessions"): os.remove(f"{root}/sessions/{f}")
open(f"{root}/spawns.log", "w").close()

def status(sid, state, ide="cli", detail="", updated_at=None):
    # `detail` is the wrap-up message a Stop event writes: non-empty means the
    # turn ended with output to review, empty means it did not.
    json.dump({"state": state, "cwd": root, "ide": ide, "pid": 1, "label": sid,
               "updated_at": updated_at or T, "task": "t", "detail": detail},
              open(f"{root}/status/sessions/{sid}.json", "w"))

def record(sid, status_, ms, kind="background"):
    json.dump({"sessionId": sid, "kind": kind, "status": status_, "statusUpdatedAt": ms},
              open(f"{root}/sessions/{sid}.json", "w"))

if phase == "1":
    # `detail` on a running session is the last tool event, not a wrap-up.
    status("A", "running", detail="$ sleep 90"); record("A", "busy", (T - 5) * 1000, "interactive")
    status("B", "running", detail="$ ls");       record("B", "idle",  T * 1000 + 900, "interactive")
    status("C", "running", detail="$ ls");       record("C", "busy",  (T + 5) * 1000, "interactive")
    status("D", "running")                                    # no record: finishes cleanly
    status("E", "idle");    record("E", "idle",  (T + 5) * 1000)
    status("F", "idle");    record("F", "idle",  (T + 5) * 1000)
    status("G", "idle");    record("G", "idle",  (T + 5) * 1000)
    status("H", "running", ide="claude-desktop")              # reports no status at all
    status("I", "idle", ide="vscode")                         # a fresh idle: no wrap-up
    status("J", "idle", ide="vscode", detail="here is what I did")
    json.dump({"needs": "may I delete build/?"}, open(f"{root}/jobs/jobF/state.json", "w"))
    json.dump({"needs": "send a prompt to start"}, open(f"{root}/jobs/jobG/state.json", "w"))
    json.dump([
        {"sessionId": "E", "kind": "background",  "status": "busy", "state": "working", "id": "jobE"},
        {"sessionId": "F", "kind": "background",  "status": "idle", "state": "blocked", "id": "jobF"},
        {"sessionId": "G", "kind": "background",  "status": "idle", "state": "blocked", "id": "jobG"},
        {"sessionId": "A", "kind": "interactive", "status": "busy"},
    ], open(f"{root}/agents.json", "w"))
else:
    # Nothing but interactive sessions: no background job can be here, so the
    # listing must not be spawned at all.
    status("A", "running"); record("A", "busy", (T - 5) * 1000, "interactive")
    status("B", "idle");    record("B", "idle", (T + 5) * 1000, "interactive")
    json.dump([], open(f"{root}/agents.json", "w"))
PY

# The harness: drives the real service and checks what the lights end up showing.
cat > "$FIX/main.swift" <<SWIFT
import AppKit

let fixture = "$FIX"
var failures = 0

@MainActor
func check(_ name: String, _ got: String, _ want: String) {
    print((got == want ? "PASS  " : "FAIL  ") + name + "   got=\\(got) want=\\(want)")
    if got != want { failures += 1 }
}

@MainActor
func phase1() {
    let state = AppState()
    let service = AgentStatusService(state: state)
    service.start()
    // Poll 1 kicks off the listing query; the poll after it reconciles with it.
    RunLoop.main.run(until: Date().addingTimeInterval(3.0))
    func light(_ id: String) -> AgentSession? { state.sessions.first { \$0.id == id } }
    // What the collapsed pill would draw for that one session.
    func summary(_ id: String) -> String {
        light(id).map { String(describing: AgentSummary([\$0])) } ?? "-"
    }

    check("bg working -> green", light("E")?.state ?? "-", "running")
    check("bg stopped to ask -> orange", light("F")?.state ?? "-", "blocked")
    check("bg idle at an empty prompt -> stays grey", light("G")?.state ?? "-", "idle")
    check("answer from the light's own second -> stays green", light("B")?.state ?? "-", "running")
    check("Claude Code says busy -> stays green", light("C")?.state ?? "-", "running")
    check("host reports no status -> stays green", light("H")?.state ?? "-", "running")
    check("before the interrupt -> green", light("A")?.state ?? "-", "running")
    check("before finishing -> green", light("D")?.state ?? "-", "running")

    check("finished turn -> unread", String(light("J")?.unread ?? false), "true")
    check("a fresh idle with no wrap-up -> not unread", String(light("I")?.unread ?? true), "false")
    check("a running session is never unread", String(light("C")?.unread ?? true), "false")
    check("bg job reconciled off idle is not unread", String(light("F")?.unread ?? true), "false")

    // Clicking the row is what acknowledges the finish; the light must go out
    // at once, and stay out across the polls that follow.
    if let j = light("J") { state.acknowledgeFinish(j) }
    check("acknowledged -> light out immediately", String(light("J")?.unread ?? true), "false")
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    check("acknowledged -> stays out across polls", String(light("J")?.unread ?? true), "false")

    // The next turn to finish lights it again: the acknowledgement is keyed to
    // the finish it acknowledged, not to the session.
    let next = Int(Date().timeIntervalSince1970) + 1
    try? #"{"state":"idle","cwd":"\#(fixture)","ide":"vscode","pid":1,"label":"J","updated_at":\#(next),"task":"t","detail":"and here is the next thing"}"#
        .write(toFile: fixture + "/status/sessions/J.json", atomically: true, encoding: .utf8)
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    check("the next finish lights it again", String(light("J")?.unread ?? false), "true")

    // 045: the pill dot reads the same finish the row does, so an unread
    // session lights it white even after the 20s "just finished" window.
    check("unread alone -> the pill dot is white", summary("J"), "finished")

    // A's turn is interrupted: Claude Code goes idle, and no Stop event ever
    // fires, so the status file still says running.
    let now = Int(Date().timeIntervalSince1970)
    try? #"{"sessionId":"A","kind":"interactive","status":"idle","statusUpdatedAt":\#((now + 5) * 1000)}"#
        .write(toFile: fixture + "/sessions/A.json", atomically: true, encoding: .utf8)
    // D's turn ends cleanly: its own hook writes idle.
    try? #"{"state":"idle","cwd":"\#(fixture)","ide":"cli","pid":1,"label":"D","updated_at":\#(now),"task":"t","detail":"d"}"#
        .write(toFile: fixture + "/status/sessions/D.json", atomically: true, encoding: .utf8)
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))

    check("interrupted turn -> grey", light("A")?.state ?? "-", "idle")
    check("interrupted turn is not 'just finished'", String(light("A")?.justFinished ?? true), "false")
    check("interrupted turn is not unread either", String(light("A")?.unread ?? true), "false")
    check("clean finish -> grey", light("D")?.state ?? "-", "idle")
    check("clean finish is 'just finished'", String(light("D")?.justFinished ?? false), "true")
    check("clean finish is unread", String(light("D")?.unread ?? false), "true")
    check("clean finish -> the pill dot is white", summary("D"), "finished")

    // 045: clicking the row clears *both* finished flags, so the pill above the
    // panel can never stay white over a row the click has already greyed.
    if let d = light("D") { state.acknowledgeFinish(d) }
    check("acknowledged -> 'just finished' out too", String(light("D")?.justFinished ?? true), "false")
    check("acknowledged -> the pill dot goes out with the row", summary("D"), "idle")
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    check("acknowledged -> 'just finished' stays out inside the window",
          String(light("D")?.justFinished ?? true), "false")
    check("acknowledged -> the pill dot stays out", summary("D"), "idle")

    let spawns = (try? String(contentsOfFile: fixture + "/spawns.log", encoding: .utf8)) ?? ""
    check("a background job is possible -> the listing is queried",
          spawns.isEmpty ? "0" : "1+", "1+")
}

@MainActor
func phase2() {
    let state = AppState()
    let service = AgentStatusService(state: state)
    service.start()
    RunLoop.main.run(until: Date().addingTimeInterval(3.0))
    let spawns = (try? String(contentsOfFile: fixture + "/spawns.log", encoding: .utf8)) ?? ""
    check("only interactive sessions -> no subprocess at all",
          spawns.isEmpty ? "0" : "1+", "0")
    check("and the lights still read as written",
          state.sessions.map { "\\(\$0.id)=\\(\$0.state)" }.sorted().joined(separator: ","),
          "A=running,B=idle")
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("2") { phase2() } else { phase1() }
}
exit(failures == 0 ? 0 : 1)
SWIFT

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
    find Sources/tempo -name '*.swift' ! -name 'main.swift' ! -name 'AgentStatusService.swift'
)
swiftc -o "$FIX/fixtest" "${SOURCES[@]}" "$FIX/AgentStatusService.swift" "$FIX/main.swift"

status=0
echo "— reconciliation (043), the unread light (044), one finish one light (045) —"
python3 "$FIX/fixture.py" "$FIX" 1 && "$FIX/fixtest" 1 || status=1
echo "— the listing subprocess is not spawned when it cannot matter —"
python3 "$FIX/fixture.py" "$FIX" 2 && "$FIX/fixtest" 2 || status=1

if [ "$status" -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit "$status"

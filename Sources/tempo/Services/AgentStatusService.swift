import Foundation

/// Read-only consumer of AgentStatus's session status files (decision 005).
///
/// Tempo never writes to, deletes, or locks anything under `~/.claude/**` —
/// this service only opens files for reading. If the status directory is
/// absent or unreadable, the lights feature hides itself silently (Agent
/// Guideline #3): `state.sessions` is simply set to `[]`.
///
/// Per Agent Guideline #5, this service reads only the fields the lights
/// need: `state`, `label` and `updated_at` to draw one, plus `cwd`, `ide` and
/// `pid` to route a click on it (decision 035), plus `task` for the one-line
/// description beside the label (decision 040). `task` is a prompt excerpt, so
/// it is rendered in the panel and nowhere else — never logged, never written
/// to disk, never sent anywhere. Of `detail` only its emptiness is read — the
/// wrap-up message itself is never decoded (decision 044).
///
/// The status file records hook *events*, and two of the things a light must
/// show never produce one — a turn the user interrupted, and what a background
/// job is doing between turns. So the poll also reads Claude Code's own view of
/// its sessions (`~/.claude/sessions/<pid>.json` and `claude agents --json`) and
/// reconciles the two before drawing (decision 043). Both are read-only, and
/// neither is under `~/.claude/status/**` (Agent Guideline #3).
@MainActor
final class AgentStatusService: ObservableObject {
    let state: AppState

    /// AgentStatus's own staleness backstop: a session whose `updated_at` is
    /// older than this is presumed dead and dropped so Tempo never shows a
    /// lying light (UI Principle #4).
    private static let staleAfter: TimeInterval = 2 * 60 * 60

    private static var sessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/status/sessions", isDirectory: true)
    }

    /// Claude Code's own per-process session records — the second source
    /// decision 043 reconciles against.
    private static var claudeRecordsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// How long a `claude agents --json` answer is reused (seconds). It is a
    /// subprocess, so it runs at a fraction of the poll rate; between refreshes
    /// the poll reconciles from the last answer. The records directory needs no
    /// such cache — those are three small files, and `status` changes on every
    /// turn boundary, which is exactly what 043 must see at once.
    private static let cliFactsTTL: TimeInterval = 10

    /// How long a session that was just observed going running -> idle keeps
    /// its distinct "just finished" light (decision 042). Long enough to catch
    /// on the next glance at the notch, short enough that the pill is not
    /// permanently claiming something finished.
    static let finishedWindow: TimeInterval = 20

    private var timer: Timer?

    /// Last observed state per session id, and when a session most recently
    /// went running -> idle. Both are in-memory only and hold no status-file
    /// content beyond the state word (Agent Guideline #5); they are dropped as
    /// soon as a session's file disappears.
    private var lastStates: [String: String] = [:]
    private var finishedAt: [String: Date] = [:]

    /// The last `claude agents --json` answer, when it was taken, and whether a
    /// refresh is already running. nil is "no answer" — never "nothing is
    /// running" — so it reconciles nothing (decision 043).
    private var cliFacts: [String: CliFact]?
    private var cliFactsAt = Date.distantPast
    private var cliQueryRunning = false

    init(state: AppState) {
        self.state = state
    }

    /// Begins a ~2s repeating poll of `~/.claude/status/sessions/`. A poll is
    /// simpler than an FSEvents watcher and sufficient for a glanceable
    /// display (Agent Guideline #0 — this is a display layer, not a
    /// low-latency signal pipeline).
    func start() {
        timer?.invalidate()
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        // Allow the timer to fire while the run loop is tracking UI events
        // (scrolling/dragging the panel), same as other pollers in Tempo.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let fm = FileManager.default
        let dir = Self.sessionsDirectory

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            setSessions([])
            return
        }

        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            setSessions([])
            return
        }

        let now = Date()
        var parsed: [AgentSession] = []

        for url in entries {
            // Only plain "<id>.json" session files — skip "<id>.subagents"
            // marker directories and anything else (e.g. .DS_Store).
            guard url.pathExtension == "json" else { continue }

            let id = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let session = Self.parseSession(id: id, data: data) else { continue }
            guard now.timeIntervalSince(session.updatedAt) < Self.staleAfter else { continue }

            parsed.append(session)
        }

        // The CLI listing is consulted for exactly two things — what a background
        // job is doing (063), and keeping a background light out of 067's grey —
        // so it is only worth a subprocess when a background job might be here.
        // An interactive session says so in its own record, which is a free file
        // read, so a machine running only interactive sessions never pays for the
        // query at all. Anything else — a record that says otherwise, an
        // unrecognised kind, a session with no record yet — asks (fail toward
        // being right about the light, not toward saving the spawn).
        let records = Self.claudeRecords()
        let mightBeBackground = parsed.contains {
            $0.ide == "cli" && records[$0.id]?.kind != "interactive"
        }
        refreshCLIFacts(now: now, needed: mightBeBackground)
        let (reconciled, reconciledIdle) = reconcile(parsed, records: records)
        setSessions(Self.sort(markUnread(markFinished(reconciled, now: now, reconciledIdle: reconciledIdle))))
    }

    /// Overlay Claude Code's own view on the states the hook wrote, and report
    /// which lights were greyed by it rather than by a `Stop` event
    /// (decision 043). Returns the sessions unchanged when neither source has
    /// anything to say about them.
    private func reconcile(
        _ sessions: [AgentSession],
        records: [String: ClaudeRecord]
    ) -> ([AgentSession], Set<String>) {
        var reconciledIdle: Set<String> = []
        let out = sessions.map { session -> AgentSession in
            var session = session
            let fact = cliFacts?[session.id]
            // A background job's light says what Claude Code says. Only an
            // `idle` light is touched, so anything the hook actually observed —
            // `running`, `blocked`, `error` — always wins.
            if session.ide == "cli", session.state == "idle", let next = Self.bgLightState(fact) {
                session.state = next
            }
            // Background jobs are excluded from the grey: Claude Code reports
            // them `idle` between turns while the job is alive and working, so
            // `idle` does not mean there what it means for an interactive
            // session. Claude Desktop is excluded by its data rather than by a
            // rule — it writes no `status`, so `turnEnded` reads no evidence.
            if session.ide != "cursor",
               session.state == "running",
               fact?.kind != "background",
               Self.turnEnded(records[session.id], lightUpdatedAt: session.updatedAt) {
                session.state = "idle"
                reconciledIdle.insert(session.id)
                // And specifically not a white light. `hasOutput` means one
                // thing — the wrap-up message a `Stop` event writes — and an
                // interrupted turn has none: `detail` still holds whatever the
                // last tool event wrote, so leaving it set would raise "there
                // is output to review" on a cancelled tool call, in a session
                // the user is by definition already looking at (decision 044).
                session.hasOutput = false
            }
            return session
        }
        return (out, reconciledIdle)
    }

    /// Refresh the `claude agents --json` answer off the main actor, at most one
    /// query at a time and at most one per `cliFactsTTL`, and only when the poll
    /// says the answer could matter. The poll never waits on it — it reads
    /// whatever the last query left behind.
    private func refreshCLIFacts(now: Date, needed: Bool) {
        guard needed, !cliQueryRunning,
              now.timeIntervalSince(cliFactsAt) >= Self.cliFactsTTL else { return }
        cliQueryRunning = true
        Task.detached(priority: .utility) {
            let facts = ClaudeCLI.facts()
            await MainActor.run { [weak self] in
                guard let self else { return }
                // A failed query is cached as nil too: retrying it every poll
                // would be the spawn storm the cache exists to avoid.
                self.cliFacts = facts
                self.cliFactsAt = Date()
                self.cliQueryRunning = false
            }
        }
    }

    /// Claude Code's live session records, keyed by session id. A missing or
    /// unreadable directory reads as empty, which reconciles nothing.
    private static func claudeRecords() -> [String: ClaudeRecord] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: claudeRecordsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var out: [String: ClaudeRecord] = [:]
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["sessionId"] as? String, !id.isEmpty else { continue }
            out[id] = ClaudeRecord(
                kind: object["kind"] as? String ?? "",
                status: object["status"] as? String ?? "",
                statusUpdatedMs: (object["statusUpdatedAt"] as? NSNumber)?.intValue ?? 0
            )
        }
        return out
    }

    /// Whether a green light must be forced grey because Claude Code itself says
    /// the turn is over (decision 043). AgentStatus's hook can only write `idle`
    /// from a `Stop` event, so a turn that ends any other way — the user
    /// interrupting it with Ctrl-C or Esc being the everyday case — leaves
    /// `"state":"running"` on disk indefinitely.
    ///
    /// Two guards keep this from ever inventing a grey light (UI Principle #4):
    ///   * **positive evidence only** — the record must actually say `idle`. An
    ///     absent status, an unreadable record, or a session Claude Code does
    ///     not list changes nothing.
    ///   * **the answer must be newer than the light** — `statusUpdatedAt` (ms)
    ///     has to fall in a strictly later second than the hook event the light
    ///     was drawn from, so anything the hook observed wins over a stale
    ///     answer. Strictly later, not merely greater, because the hook stamps
    ///     whole seconds: within one shared second the two clocks cannot be
    ///     ordered, and the tie has to go to the hook.
    ///
    /// `shell` is deliberately not treated as idle — it plainly is not a running
    /// turn, but what produces it is unconfirmed, and a guess is not worth a
    /// lying light.
    private static func turnEnded(_ record: ClaudeRecord?, lightUpdatedAt: Date) -> Bool {
        guard let record, record.status == "idle" else { return false }
        return record.statusUpdatedMs >= (Int(lightUpdatedAt.timeIntervalSince1970) + 1) * 1000
    }

    /// The `needs` a background job reports when it is idle at an empty prompt:
    /// it is not asking anything, it is waiting to be given work. Every other
    /// `needs` on a blocked job is the question it stopped to ask.
    private static let bgNeedsPrompt = "send a prompt to start"

    /// The state a background agent's light should show when its own hook last
    /// wrote `idle` (decision 043), or nil to leave the light as written. Hooks
    /// describe *turns*, so a turn that ended because the job finished and one
    /// that ended because it stopped to ask the user both land on `idle`; Claude
    /// Code separates the two, so the light asks instead of inferring.
    private static func bgLightState(_ fact: CliFact?) -> String? {
        guard let fact, fact.kind == "background" else { return nil }
        // Working right now, whatever the last hook said — a job between tool
        // calls is still running, and its light is green.
        if fact.status == "busy" { return "running" }
        // Stopped and waiting on the user: that is what orange means everywhere
        // else on the bar, and it is what this is — provided the job is actually
        // asking. A job that finished and sits at an empty prompt reports the
        // same `blocked` and asks nothing, so it keeps its hook's `idle`. An
        // unrecognised `needs` keeps the orange: a missed attention light is the
        // costlier mistake (UI Principle #2).
        if fact.jobState == "blocked", fact.needs != bgNeedsPrompt { return "blocked" }
        return nil
    }

    /// Flags each session that has gone running -> idle within the last
    /// `finishedWindow` seconds, and records this poll's states for the next
    /// comparison. The very first poll after launch records without flagging,
    /// so a session that was already idle at launch never reads as one that
    /// just finished.
    ///
    /// `reconciledIdle` holds the lights decision 043 greyed. Those went idle
    /// because the turn was **interrupted**, not because it finished, so they
    /// must not raise the "just finished" light — that light says there is
    /// output worth reading, and a cancelled turn produced none.
    private func markFinished(
        _ sessions: [AgentSession],
        now: Date,
        reconciledIdle: Set<String>
    ) -> [AgentSession] {
        let liveIDs = Set(sessions.map(\.id))
        lastStates = lastStates.filter { liveIDs.contains($0.key) }
        finishedAt = finishedAt.filter { liveIDs.contains($0.key) }

        return sessions.map { session in
            if lastStates[session.id] == "running", session.state == "idle",
               !reconciledIdle.contains(session.id) {
                finishedAt[session.id] = now
            }
            lastStates[session.id] = session.state

            guard let at = finishedAt[session.id] else { return session }
            guard now.timeIntervalSince(at) < Self.finishedWindow else {
                finishedAt[session.id] = nil
                return session
            }
            var marked = session
            marked.justFinished = true
            return marked
        }
    }

    /// Flags each finished turn the user has not acknowledged (decision 044).
    /// Unlike `justFinished`, this is not a window: an unread light stays lit
    /// until the row is clicked, which is what makes it the panel's record of
    /// "this one is done and you haven't looked at it". It survives a relaunch
    /// too, because the signal it reads is the status file's own wrap-up
    /// message rather than a transition Tempo happened to be running for.
    private func markUnread(_ sessions: [AgentSession]) -> [AgentSession] {
        state.pruneAcknowledgements(liveIDs: Set(sessions.map(\.id)))
        return sessions.map { session in
            var session = session
            session.unread = session.hasOutput
                && session.state == "idle"
                && state.acknowledgedFinish[session.id] != session.updatedAt
            return session
        }
    }

    /// Parses one session JSON file into an `AgentSession`, reading only
    /// `state`, `label`, `updated_at`, `cwd`, `ide`, `pid`, `task` and whether
    /// `detail` is empty (decision 044). Returns nil
    /// (fail silent, per Agent Guideline #3) if the file isn't valid JSON or is
    /// missing a required field.
    private static func parseSession(id: String, data: Data) -> AgentSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let state = object["state"] as? String,
              let label = object["label"] as? String else {
            return nil
        }
        // updated_at is documented as an integer Unix-seconds field, but
        // accept any JSON number to tolerate a trailing ".0" without
        // rejecting the whole file.
        let updatedAtSeconds: TimeInterval
        if let intValue = object["updated_at"] as? Int {
            updatedAtSeconds = TimeInterval(intValue)
        } else if let numberValue = object["updated_at"] as? NSNumber {
            updatedAtSeconds = numberValue.doubleValue
        } else {
            return nil
        }

        // The routing fields are optional: a session file missing one still
        // draws a light, its click just has less to go on (an empty `ide`
        // routes as an editor session, which needs only `cwd`).
        let pid: Int
        if let intValue = object["pid"] as? Int {
            pid = intValue
        } else if let numberValue = object["pid"] as? NSNumber {
            pid = numberValue.intValue
        } else {
            pid = 0
        }

        return AgentSession(
            id: id,
            state: state,
            label: label,
            updatedAt: Date(timeIntervalSince1970: updatedAtSeconds),
            cwd: object["cwd"] as? String ?? "",
            ide: object["ide"] as? String ?? "",
            pid: pid,
            task: Self.summarize(object["task"] as? String),
            // Only whether a wrap-up message exists, never the message
            // (decision 044, Agent Guideline #5).
            hasOutput: !(object["detail"] as? String ?? "").isEmpty
        )
    }

    /// Flattens a `task` excerpt into one display line: newlines and runs of
    /// whitespace collapse to single spaces, and the result is capped at 120
    /// characters so one long prompt can't dictate the panel's width. The
    /// writer's own truncation marker is dropped — the row truncates visually
    /// on its own, and a trailing ellipsis on top of that reads as noise.
    private static func summarize(_ raw: String?) -> String {
        guard let raw else { return "" }
        let flattened = raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > 120 else { return flattened }
        return String(flattened.prefix(120))
    }

    /// Attention states first (blocked, error), then running, then idle;
    /// alphabetical by label within a group. Unrecognized states sort last.
    private static func sort(_ sessions: [AgentSession]) -> [AgentSession] {
        func rank(_ state: String) -> Int {
            switch state {
            case "blocked", "error": return 0
            case "running": return 1
            case "idle": return 2
            default: return 3
            }
        }
        return sessions.sorted { a, b in
            let (ra, rb) = (rank(a.state), rank(b.state))
            if ra != rb { return ra < rb }
            if a.label != b.label { return a.label.localizedStandardCompare(b.label) == .orderedAscending }
            return a.id < b.id
        }
    }

    private func setSessions(_ next: [AgentSession]) {
        if state.sessions != next {
            state.sessions = next
        }
    }
}

/// What Claude Code records about one of its own live sessions, in the
/// per-process file it keeps at `~/.claude/sessions/<pid>.json` (decision 043).
/// `status` is what the session is doing *right now* as Claude Code sees it —
/// observed values on 2.1.240: `busy`, `idle`, `waiting`, `shell` — and
/// `statusUpdatedMs` is when it said so, in **milliseconds**, which is what
/// makes that answer safely orderable against the hook event a light was drawn
/// from. Both are absent for a Claude Desktop session, which reports neither.
/// `kind` is the session's own word for what it is — `interactive` on every
/// session observed on this machine — and is what keeps the `claude agents`
/// subprocess off a machine that is running no background jobs.
private struct ClaudeRecord {
    var kind: String
    var status: String
    var statusUpdatedMs: Int
}

/// What `claude agents --json` says about one live session (decision 043).
/// `status` is live (is it burning a turn right now); `jobState` is the job's
/// own lifecycle word and only background jobs report one; `needs` is what a
/// blocked job is waiting for, read from the job's own record because the
/// listing carries the state but not the reason behind it.
private struct CliFact: Sendable {
    var kind: String
    var status: String
    var jobState: String
    var needs: String
}

/// The off-main half of decision 043: asking the `claude` binary to enumerate
/// its own live sessions. Kept out of `AgentStatusService` because it must run
/// off the main actor — the query costs ~0.3s of subprocess, measured on this
/// machine, and the poll it feeds runs on the main actor beside the notch's
/// animations.
private enum ClaudeCLI {
    /// The `claude` binary, resolved once. A GUI app inherits almost no PATH,
    /// so `which` is tried first and then the install locations AgentStatus
    /// checks; nil means no query, and therefore no reconciliation.
    static let binary: String? = {
        if let path = run("/usr/bin/which", ["claude"]),
           let resolved = String(decoding: path, as: UTF8.self)
               .trimmingCharacters(in: .whitespacesAndNewlines)
               .nilIfEmpty,
           FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }()

    /// Claude Code's live sessions, keyed by session id, or nil when the query
    /// could not run or failed — which reconciles nothing, so the failure mode
    /// is the pre-043 behaviour.
    ///
    /// `AGENTSTATUS_IGNORE=1` is passed for AgentStatus's benefit, not Tempo's:
    /// without it, AgentStatus's hooks would write a status file for Tempo's
    /// own query process and Tempo would put a light on the bar it is only
    /// supposed to be reading (Agent Guideline #3).
    static func facts() -> [String: CliFact]? {
        guard let binary else { return nil }
        guard let data = run(binary, ["agents", "--json"], environment: ["AGENTSTATUS_IGNORE": "1"]),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var out: [String: CliFact] = [:]
        for entry in array {
            guard let id = entry["sessionId"] as? String, !id.isEmpty else { continue }
            let kind = entry["kind"] as? String ?? ""
            out[id] = CliFact(
                kind: kind,
                status: entry["status"] as? String ?? "",
                jobState: entry["state"] as? String ?? "",
                // Only a background job has a job record to read.
                needs: kind == "background" ? jobNeeds(entry["id"] as? String) : ""
            )
        }
        return out
    }

    /// What a background job says it is waiting for, from its own record at
    /// `~/.claude/jobs/<id>/state.json`. A missing or unreadable file reads as
    /// empty, which keeps decision 043's orange — a missed attention light is
    /// the costlier mistake.
    private static func jobNeeds(_ jobID: String?) -> String {
        guard let jobID, !jobID.isEmpty else { return "" }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/jobs/\(jobID)/state.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        return object["needs"] as? String ?? ""
    }

    /// Run a process to completion and return its stdout, or nil if it could
    /// not be started or exited non-zero. stderr is discarded — a failed query
    /// reconciles nothing, and Tempo logs nothing about sessions (Guideline #5).
    private static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:]
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drained before waiting, so a listing that outdid the pipe buffer
        // cannot block on write while we block on exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

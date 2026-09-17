import Foundation

/// Read-only reader of Claude Code's own session transcripts, for the token
/// and timing figures on each agent row (decision 048).
///
/// AgentStatus's status files carry no stats — verified against the installed
/// writer: `state`, `cwd`, `ide`, `pid`, `label`, `updated_at`, `task`,
/// `detail` and nothing else (Agent Guideline #4). The numbers live in Claude
/// Code's transcript for the same session id, at
/// `~/.claude/projects/<slug>/<session_id>.jsonl`, which is a different tree
/// from `~/.claude/status/**` and is likewise only ever opened for reading
/// (Agent Guideline #3).
///
/// Per Agent Guideline #5 this reads **numbers and timestamps only**: an
/// assistant entry's `usage` counts, a user entry's `timestamp`, and a
/// `turn_duration` entry's `durationMs`. No message content, no prompt text and
/// no tool output is ever read out of the parsed line, stored, or logged — the
/// decoded object is dropped at the end of each iteration.
///
/// Transcripts are append-only and reach megabytes, so a poll never re-reads
/// one: each session keeps a byte offset and reads only what was appended
/// since the last poll (typically a few KB). A file that has shrunk since the
/// last read has been rotated or rewritten, so its accumulators reset and it is
/// read from the top again.
@MainActor
final class SessionStatsService: ObservableObject {
    let state: AppState

    private var timer: Timer?
    /// Per-session read cursor and running totals. Dropped as soon as a session
    /// leaves `state.sessions`, so this never outlives the light it feeds.
    private var readers: [String: Reader] = [:]
    /// Session id -> transcript URL, resolved once per session. `nil` records a
    /// resolution that failed, so a session whose transcript cannot be found
    /// is not searched for again on every poll.
    private var transcripts: [String: URL?] = [:]

    init(state: AppState) {
        self.state = state
    }

    /// Polls at the same 2s cadence as the lights themselves: the figures sit
    /// on those rows, and a slower clock would leave a row's token count
    /// disagreeing with the state its own dot is showing.
    ///
    /// It keeps polling while the panel is collapsed, which is what makes the
    /// reads cheap rather than wasteful: the cost of a poll is the bytes
    /// appended since the last one, so a warm cursor is a few KB. Polling only
    /// while expanded would make every first expansion pay a full scan of a
    /// file that reaches megabytes.
    func start() {
        guard timer == nil else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops polling and drops every cursor, so a disabled module costs no
    /// file reads at all — the same contract `SystemStatsService.stop()` has
    /// for the usage graph.
    func stop() {
        timer?.invalidate()
        timer = nil
        readers.removeAll()
        transcripts.removeAll()
        if !state.sessionStats.isEmpty { state.sessionStats = [:] }
    }

    /// One pass over every live session's transcript. `start()` schedules it;
    /// `scripts/test-session-stats.sh` drives it directly so it can control
    /// what the file looks like between polls.
    func poll() {
        let live = state.sessions
        let liveIDs = Set(live.map(\.id))
        readers = readers.filter { liveIDs.contains($0.key) }
        transcripts = transcripts.filter { liveIDs.contains($0.key) }

        var out: [String: SessionStats] = [:]
        for session in live {
            guard let url = transcript(for: session) else { continue }
            var reader = readers[session.id] ?? Reader()
            reader.consumeAppended(at: url)
            readers[session.id] = reader
            guard let stats = reader.stats else { continue }
            out[session.id] = stats
        }
        if state.sessionStats != out { state.sessionStats = out }
    }

    /// The transcript file for a session, resolved once and cached (including
    /// the failure). Claude Code names a project directory after the working
    /// directory with every non-alphanumeric character replaced by `-`
    /// (verified against all 12 project directories on this machine), so the
    /// path is derived from the `cwd` the status file already carries. If that
    /// derivation misses — an older naming rule, or a session whose `cwd` moved
    /// — the projects directory is scanned once for a directory holding a file
    /// with this session's id, rather than guessing again.
    private func transcript(for session: AgentSession) -> URL? {
        guard !session.ide.hasPrefix("codex") else { return nil }
        if let cached = transcripts[session.id] { return cached }

        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        let file = "\(session.id).jsonl"

        var found: URL?
        if !session.cwd.isEmpty {
            let slug = String(session.cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let candidate = root.appendingPathComponent(slug, isDirectory: true)
                .appendingPathComponent(file)
            if FileManager.default.isReadableFile(atPath: candidate.path) { found = candidate }
        }
        if found == nil,
           let dirs = try? FileManager.default.contentsOfDirectory(
               at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in dirs {
                let candidate = dir.appendingPathComponent(file)
                if FileManager.default.isReadableFile(atPath: candidate.path) {
                    found = candidate
                    break
                }
            }
        }
        transcripts[session.id] = found
        return found
    }
}

/// One session's transcript cursor and running totals.
///
/// `offset` only ever advances past **complete** lines. A poll can land in the
/// middle of Claude Code appending an entry, so the trailing fragment is left
/// unconsumed for the next poll to read whole rather than being parsed as a
/// truncated line and dropped.
private struct Reader {
    var offset: UInt64 = 0
    var contextTokens = 0
    var sessionTokens = 0
    var turnStart: Date?
    var lastTurnDuration: TimeInterval?
    var sawAny = false

    var stats: SessionStats? {
        guard sawAny else { return nil }
        return SessionStats(
            contextTokens: contextTokens,
            sessionTokens: sessionTokens,
            turnStart: turnStart,
            lastTurnDuration: lastTurnDuration
        )
    }

    mutating func consumeAppended(at url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        // A file shorter than the cursor was rotated or rewritten; the totals
        // accumulated from the old contents describe a file that no longer
        // exists, so they go with it (UI Principle #4).
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            self = Reader()
        }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        var consumed = 0
        var lineStart = data.startIndex
        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            let line = data[lineStart..<newline]
            if !line.isEmpty { apply(line) }
            consumed = data.distance(from: data.startIndex, to: newline) + 1
            lineStart = data.index(after: newline)
        }
        offset += UInt64(consumed)
    }

    /// Reads one transcript line for its numbers. The substring test in front
    /// of the JSON parse is what keeps this cheap: most lines in a transcript
    /// are tool results with nothing to contribute, and skipping them avoids
    /// decoding a payload this service has no business looking at anyway
    /// (Agent Guideline #5).
    private mutating func apply(_ line: Data) {
        guard line.contains(subsequence: Self.usageKey)
                || line.contains(subsequence: Self.turnDurationKey)
                || line.contains(subsequence: Self.promptSourceKey) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

        switch object["type"] as? String {
        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            let input = Self.int(usage["input_tokens"])
            let cacheCreation = Self.int(usage["cache_creation_input_tokens"])
            let cacheRead = Self.int(usage["cache_read_input_tokens"])
            let output = Self.int(usage["output_tokens"])
            // Everything the session spent, subagents included — their work is
            // this session's spend even though it never enters its context.
            sessionTokens += input + cacheCreation + output
            // What is live in the context window right now, which is the main
            // chain only: a subagent runs its own window, and counting its
            // messages here would make the figure jump on every fan-out.
            if !(object["isSidechain"] as? Bool ?? false) {
                contextTokens = input + cacheCreation + cacheRead
            }
            sawAny = true

        case "user":
            // A user entry with a `promptSource` is a real prompt — the start
            // of a turn. The unmarked ones are tool results being fed back.
            guard object["promptSource"] != nil,
                  let date = Self.date(object["timestamp"]) else { return }
            turnStart = date
            sawAny = true

        case "system":
            guard object["subtype"] as? String == "turn_duration" else { return }
            lastTurnDuration = TimeInterval(Self.int(object["durationMs"])) / 1000
            // Claude Code writes this at the turn boundary, so the turn that
            // was running is over: the row stops counting up and shows what
            // that turn took.
            turnStart = nil
            sawAny = true

        default:
            return
        }
    }

    private static let usageKey = Array("\"usage\"".utf8)
    private static let turnDurationKey = Array("\"turn_duration\"".utf8)
    private static let promptSourceKey = Array("\"promptSource\"".utf8)

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return formatter.date(from: string)
    }
}

private extension Data {
    /// Whether this line contains the given byte sequence. Used only to decide
    /// whether a line is worth decoding at all.
    func contains(subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        let first = needle[0]
        var index = startIndex
        let limit = index + (count - needle.count)
        while index <= limit {
            guard let hit = self[index...limit].firstIndex(of: first) else { return false }
            if self[hit..<(hit + needle.count)].elementsEqual(needle) { return true }
            index = hit + 1
        }
        return false
    }
}

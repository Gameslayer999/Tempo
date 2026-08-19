import Foundation

/// Read-only consumer of AgentStatus's session status files (decision 005).
///
/// Tempo never writes to, deletes, or locks anything under `~/.claude/**` —
/// this service only opens files for reading. If the status directory is
/// absent or unreadable, the lights feature hides itself silently (Agent
/// Guideline #3): `state.sessions` is simply set to `[]`.
///
/// Per Agent Guideline #5, this service reads only the fields the lights
/// need (`state`, `label`, `updated_at`) — it never decodes or surfaces the
/// `task`/`detail` prompt-excerpt fields, and never logs file contents.
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

    private var timer: Timer?

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

        setSessions(Self.sort(parsed))
    }

    /// Parses one session JSON file into an `AgentSession`, reading only
    /// `state`, `label`, and `updated_at`. Returns nil (fail silent, per
    /// Agent Guideline #3) if the file isn't valid JSON or is missing a
    /// required field.
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

        return AgentSession(
            id: id,
            state: state,
            label: label,
            updatedAt: Date(timeIntervalSince1970: updatedAtSeconds)
        )
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

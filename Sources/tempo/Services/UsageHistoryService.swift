import Foundation

/// Seven-day token history and the rolling five-hour total, read from Claude
/// Code's own transcripts (decision 079).
///
/// It is the wide-scan sibling of `SessionStatsService`: that one follows the
/// handful of transcripts belonging to *live* sessions and reports per-session
/// figures; this one rolls up **every** project's transcripts to answer "how
/// much have I spent this week, and how hard am I leaning on the window right
/// now". Same tree — `~/.claude/projects/<slug>/<session_id>.jsonl` — and the
/// same read-only posture: nothing under `~/.claude/**` is ever written,
/// moved, created or locked (Agent Guideline #3).
///
/// **Not** `~/.claude/stats-cache.json`: verified on this machine, it is days
/// stale and every `costUSD` in it is zero, so it would show a lying figure
/// (UI Principle #4).
///
/// Per Agent Guideline #5 this extracts **numbers only** — a timestamp, a
/// model name and four token counts per assistant entry. `cwd`, `task`,
/// `detail`, prompt text, tool output and the file paths themselves are never
/// decoded out of a line, retained, surfaced or logged; the parsed object is
/// dropped at the end of each iteration and only the integers survive.
///
/// Token counting matches `SessionStatsService.Reader.apply`:
/// `input + cache_creation + output`, **excluding `cache_read`**. Cache reads
/// dominate the raw totals — 175M of 180M on one real day here — so counting
/// them would make every figure on the surface meaningless.
///
/// Cost control (this is history, not live state):
/// - Files are prefiltered by modification date before being opened. A
///   transcript last written before the seven-day window began cannot contain
///   an entry inside it. Measured here: 1291 files on disk, 699 opened.
/// - An unchanged file is not re-read. Its extracted numbers are kept keyed by
///   size and modification date, so a steady-state refresh parses only the
///   transcripts that actually grew.
/// - The scan runs off the main actor and publishes back on it, the way
///   `AgentStatusService` runs its `claude agents --json` query.
/// - The timer is 60s, and only one scan is ever in flight.
@MainActor
final class UsageHistoryService: ObservableObject {
    static let shared = UsageHistoryService()

    /// One local calendar day's spend.
    struct DayTotal: Identifiable, Equatable {
        /// Start of that day, local time.
        let date: Date
        let tokens: Int
        /// Tokens by model, keyed by the short display name
        /// (`shortModelName(_:)`) rather than the raw id, so a caller can put
        /// the key straight on screen.
        let byModel: [String: Int]
        var id: Date { date }
    }

    /// The last seven local days, **oldest first**, with days that saw no
    /// activity present and zeroed. Empty only when there is nothing to read
    /// at all — no `~/.claude/projects` directory, or it is unreadable — which
    /// is the signal for a view to hide itself entirely (Agent Guideline #3).
    @Published private(set) var days: [DayTotal] = []

    /// Tokens in the rolling five-hour window ending now.
    @Published private(set) var windowTokens = 0

    /// The model that spent the most tokens over the seven days, as a short
    /// display name. `nil` when nothing was spent.
    @Published private(set) var topModel: String?

    /// The largest five-hour total anywhere in the seven-day scan. Shown in
    /// Settings beside the window-budget slider: the real per-account limit is
    /// not readable locally, so the heaviest window actually observed is the
    /// only honest calibration hint Tempo can offer.
    @Published private(set) var busiestWindowTokens = 0

    /// When the last scan finished. `nil` before the first one completes, so a
    /// view can tell "nothing spent" from "nothing read yet".
    @Published private(set) var lastScan: Date?

    /// How much history the rollup covers, and the window the pace figure
    /// measures. Both are fixed: the seven days are what the bars draw, and
    /// five hours is Claude Code's own rate-limit window.
    nonisolated static let historyDays = 7
    nonisolated static let windowDuration: TimeInterval = 5 * 60 * 60

    /// History, not live state — a minute of staleness is invisible on a
    /// seven-day bar and on a five-hour total, and anything faster would be
    /// paying for a filesystem sweep nobody can see the result of.
    private static let refreshInterval: TimeInterval = 60

    private var timer: Timer?
    private var scanning = false
    /// Touched only from inside the detached scan task, one at a time
    /// (`scanning` is the gate).
    private let scanner = TranscriptScanner()

    private init() {}

    /// Starts the 60s refresh, scanning once immediately. Idempotent, so both
    /// views that show this data can call it from `onAppear` without
    /// double-scheduling.
    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        // Keep refreshing while the run loop tracks UI events (dragging or
        // scrolling the panel), same as the other pollers in Tempo.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refreshNow()
    }

    /// Stops scanning entirely (the module was switched off in Settings). The
    /// last figures are kept, so switching it back on redraws what was already
    /// collected instead of blanking — the same contract `SystemStatsService`
    /// has for the usage graph.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Scans now, unless one is already running. Safe to call from anywhere on
    /// the main actor — Settings uses it after the budget slider moves.
    func refreshNow() {
        guard !scanning else { return }
        scanning = true
        let scanner = self.scanner
        let now = Date()
        Task.detached(priority: .utility) {
            let result = scanner.scan(now: now)
            await MainActor.run { [weak self] in
                self?.apply(result, at: now)
            }
        }
    }

    private func apply(_ result: TranscriptScanner.Result, at time: Date) {
        scanning = false
        if days != result.days { days = result.days }
        if windowTokens != result.windowTokens { windowTokens = result.windowTokens }
        if topModel != result.topModel { topModel = result.topModel }
        if busiestWindowTokens != result.busiestWindowTokens {
            busiestWindowTokens = result.busiestWindowTokens
        }
        lastScan = time
    }

    // MARK: - Formatting

    /// A token count at glance width: `0`, `478K`, `1.4M`. Three characters of
    /// mantissa at most, because these sit in a 10pt monospaced-digit figure
    /// beside a bar and must not reflow as they tick (UI Principle #1).
    static func shortTokens(_ tokens: Int) -> String {
        let value = Double(tokens)
        if tokens >= 9_950_000 { return "\(Int((value / 1_000_000).rounded()))M" }
        if tokens >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if tokens >= 1_000 { return "\(Int((value / 1_000).rounded()))K" }
        return "\(tokens)"
    }

    /// `claude-opus-5` -> `Opus 5`, `claude-haiku-4-5-20251001` -> `Haiku 4.5`.
    /// Purely cosmetic and lossy on purpose: two dated builds of one model fold
    /// into a single bucket, which is what a one-line "what am I mostly
    /// running" label wants. An id that doesn't match the shape is returned
    /// unchanged rather than mangled into something it isn't.
    nonisolated static func shortModelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        // Trailing build date, e.g. 20251001.
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        guard let family = parts.first, !family.isEmpty else { return id }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? name : "\(name) \(version)"
    }
}

// MARK: - Scanning

/// The off-main-actor half: walks `~/.claude/projects`, extracts numbers, and
/// hands back an aggregate. Holds a parse cache across scans, and is only ever
/// entered by one task at a time (`UsageHistoryService.scanning`), which is why
/// it can be `@unchecked Sendable`.
private final class TranscriptScanner: @unchecked Sendable {
    struct Result {
        var days: [UsageHistoryService.DayTotal] = []
        var windowTokens = 0
        var topModel: String?
        var busiestWindowTokens = 0
    }

    /// The only thing kept out of a transcript line.
    private struct Event {
        let time: Date
        let tokens: Int
        let model: String
    }

    /// One file's extracted numbers, valid while the file's size and
    /// modification date are unchanged.
    private struct Parsed {
        let size: Int
        let modified: Date
        let events: [Event]
    }

    private var cache: [String: Parsed] = [:]

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let usageKey = Data("\"usage\"".utf8)

    private var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func scan(now: Date) -> Result {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(UsageHistoryService.historyDays - 1), to: today
        ) else { return Result() }

        guard let files = candidates(modifiedSince: windowStart) else {
            // No projects directory, or it cannot be listed: no data, no noise.
            cache.removeAll()
            return Result()
        }

        var events: [Event] = []
        var fresh: [String: Parsed] = [:]
        for file in files {
            let path = file.url.path
            let parsed: Parsed
            if let hit = cache[path], hit.size == file.size, hit.modified == file.modified {
                parsed = hit
            } else {
                parsed = Parsed(size: file.size, modified: file.modified,
                                events: parse(file.url, notBefore: windowStart))
            }
            fresh[path] = parsed
            events.append(contentsOf: parsed.events)
        }
        // Anything no longer a candidate is dropped, so the cache tracks the
        // window rather than growing for the life of the process.
        cache = fresh

        return aggregate(events, now: now, windowStart: windowStart, calendar: calendar)
    }

    // MARK: File selection

    private struct Candidate {
        let url: URL
        let size: Int
        let modified: Date
    }

    /// Every `<session>.jsonl` under a project directory whose last write is
    /// inside the window. This prefilter is what keeps the scan honest about
    /// cost: a transcript is append-only, so one last written before the window
    /// opened cannot hold an entry inside it, and opening it would be pure
    /// waste. Returns nil only when the projects root itself is unreadable.
    private func candidates(modifiedSince cutoff: Date) -> [Candidate]? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let projects = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        var out: [Candidate] = []
        for project in projects {
            guard let entries = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      let size = values.fileSize,
                      modified >= cutoff else { continue }
                out.append(Candidate(url: url, size: size, modified: modified))
            }
        }
        return out
    }

    // MARK: Parsing

    /// One transcript's assistant entries, as numbers. Unreadable file, torn
    /// line, malformed JSON, missing field: each is skipped in place — never a
    /// crash, never a dialog, never a log line (Agent Guideline #3).
    private func parse(_ url: URL, notBefore cutoff: Date) -> [Event] {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return [] }

        var events: [Event] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            // Most lines in a transcript are user turns and tool results with
            // no numbers to contribute. Skipping them before the JSON parse is
            // both the speed-up and the smallest possible read of content this
            // service has no business decoding (Agent Guideline #5).
            guard Self.hasUsageKey(line) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  // API-error placeholder; its usage is all zeros anyway.
                  model != "<synthetic>",
                  let usage = message["usage"] as? [String: Any],
                  let stamp = object["timestamp"] as? String,
                  let time = iso.date(from: stamp),
                  time >= cutoff else { continue }

            // cache_read is deliberately absent: see the type comment.
            let tokens = Self.int(usage["input_tokens"])
                + Self.int(usage["cache_creation_input_tokens"])
                + Self.int(usage["output_tokens"])
            guard tokens > 0 else { continue }
            events.append(Event(time: time, tokens: tokens,
                                model: UsageHistoryService.shortModelName(model)))
        }
        return events
    }

    /// `memmem` rather than `Data.range(of:)`: the search runs over every byte
    /// of every transcript line, and Foundation's own search is slow enough
    /// there to dominate the whole scan (measured on this corpus: 4.8s -> 2.0s
    /// for a cold seven-day rollup, unoptimised build).
    private static func hasUsageKey(_ line: Data) -> Bool {
        line.withUnsafeBytes { haystack -> Bool in
            guard let base = haystack.baseAddress, haystack.count >= usageKey.count else { return false }
            return usageKey.withUnsafeBytes { needle -> Bool in
                guard let key = needle.baseAddress else { return false }
                return memmem(base, haystack.count, key, needle.count) != nil
            }
        }
    }

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    // MARK: Aggregation

    private func aggregate(_ events: [Event], now: Date, windowStart: Date,
                           calendar: Calendar) -> Result {
        var totals: [Date: Int] = [:]
        var models: [Date: [String: Int]] = [:]
        var overall: [String: Int] = [:]
        var window = 0
        let windowOpens = now.addingTimeInterval(-UsageHistoryService.windowDuration)

        for event in events where event.time >= windowStart {
            let day = calendar.startOfDay(for: event.time)
            totals[day, default: 0] += event.tokens
            models[day, default: [:]][event.model, default: 0] += event.tokens
            overall[event.model, default: 0] += event.tokens
            if event.time >= windowOpens { window += event.tokens }
        }

        var result = Result()
        result.days = (0..<UsageHistoryService.historyDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart) else { return nil }
            return UsageHistoryService.DayTotal(date: day, tokens: totals[day] ?? 0,
                                                byModel: models[day] ?? [:])
        }
        result.windowTokens = window
        result.topModel = overall.max { a, b in a.value < b.value }?.key
        result.busiestWindowTokens = Self.busiestWindow(events)
        return result
    }

    /// The heaviest five hours in the scan, by a sliding sum over the events in
    /// time order. Every window that matters ends on an event, so checking the
    /// sum at each event is exact rather than an approximation over buckets.
    private static func busiestWindow(_ events: [Event]) -> Int {
        guard !events.isEmpty else { return 0 }
        let sorted = events.sorted { $0.time < $1.time }
        var best = 0
        var running = 0
        var tail = sorted.startIndex
        for index in sorted.indices {
            running += sorted[index].tokens
            let opens = sorted[index].time.addingTimeInterval(-UsageHistoryService.windowDuration)
            while sorted[tail].time < opens {
                running -= sorted[tail].tokens
                tail += 1
            }
            best = max(best, running)
        }
        return best
    }
}

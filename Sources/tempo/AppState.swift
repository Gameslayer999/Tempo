import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    /// Pinned by a click on the expanded panel; stays expanded on mouse-out
    /// while true.
    @Published var isExpanded = false
    /// Mouse currently within the active (strip or full-panel) region.
    @Published var isHovered = false
    @Published var nowPlaying: NowPlaying? = nil
    /// `spotify:track:…` URI for the current track, and only when Spotify is
    /// the source. MediaRemote reports a per-playback `contentItemIdentifier`
    /// that is not a Spotify URI, so add-to-playlist still needs this one
    /// AppleScript round-trip (decision 049). Owned by `MusicService`.
    @Published var spotifyTrackURI: String? = nil
    @Published var artwork: NSImage? = nil {
        didSet {
            artworkTint = artwork?.dominantColor()
            // A nil tint makes the `.tinted` panel style indistinguishable
            // from plain glass, which is indistinguishable from the style
            // being broken. Say which it is under TEMPO_DEBUG_VIZ=1.
            tempoDebug(artworkTint.map {
                let c = $0.usingColorSpace(.sRGB) ?? $0
                return String(format: "artwork tint h=%.2f s=%.2f b=%.2f",
                              c.hueComponent, c.saturationComponent, c.brightnessComponent)
            } ?? "artwork tint: none (cover is \(artwork == nil ? "missing" : "unsamplable")) — .tinted will look like plain glass")
        }
    }
    /// Dominant colour of the current cover, recomputed only when the cover
    /// itself changes. Drives the `.tinted` panel style (decision 030); nil
    /// when there is no artwork, which that style reads as plain glass.
    @Published private(set) var artworkTint: NSColor? = nil
    /// Whether the media UI (album cover, visualizer, transport controls,
    /// playlist row) is shown at all. False when nothing has actually played
    /// for `MediaRemoteService.mediaIdleTimeout` — a paused-and-forgotten
    /// player, or no player at all — so the collapsed pill shrinks back to the
    /// bare notch instead of parking a grey placeholder and a frozen
    /// visualizer over the desktop (decision 038). Owned by
    /// `MediaRemoteService`.
    @Published var isMediaActive = false
    /// Live playback position for the progress bar (decision 041). Stored as
    /// an *anchor* — a position and the instant it was true — rather than a
    /// ticking value, so advancing the bar costs no publishes: the view
    /// extrapolates from this on its own clock and only a real correction
    /// (a notification, a poll, a seek) touches state.
    @Published var progress: PlaybackProgress? = nil
    @Published var sessions: [AgentSession] = []
    /// Token and timing figures per session id, read from Claude Code's own
    /// transcripts by `SessionStatsService` (decision 048). Keyed separately
    /// from `sessions` rather than folded into `AgentSession` because the two
    /// come from different files on different cadences, and because the module
    /// can be switched off — an empty map is simply a row with no figures.
    @Published var sessionStats: [String: SessionStats] = [:]
    /// Finished turns the user has already looked at (decision 044), keyed by
    /// session id and the finish that was acknowledged — so the *next* turn a
    /// session finishes lights its row again. App-local and in-memory: it holds
    /// an id and a timestamp, is never written anywhere, and never touches
    /// AgentStatus's files (Agent Guideline #3).
    private(set) var acknowledgedFinish: [String: Date] = [:]
    /// Mark a session's finished turn as seen. Clears the light immediately
    /// rather than at the next poll: the same click collapses the panel, and a
    /// light still white on the way out reads as a click that didn't take.
    ///
    /// Both finished flags are cleared, not just `unread`. They are two views
    /// of one event — the row reads `unread`, the collapsed pill reads
    /// `justFinished` — and clearing only one left the panel's row grey while
    /// the pill above it still lit white for the rest of the finished window
    /// (decision 045).
    func acknowledgeFinish(_ session: AgentSession) {
        guard session.unread || session.justFinished else { return }
        acknowledgedFinish[session.id] = session.updatedAt
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].unread = false
            sessions[index].justFinished = false
        }
    }

    /// Forget acknowledgements for sessions that no longer exist, so the map
    /// tracks the live set the way the poll's other per-session memory does.
    func pruneAcknowledgements(liveIDs: Set<String>) {
        guard acknowledgedFinish.contains(where: { !liveIDs.contains($0.key) }) else { return }
        acknowledgedFinish = acknowledgedFinish.filter { liveIDs.contains($0.key) }
    }

    /// The collapsed pill's summary light (decision 042). Derived, not stored:
    /// `sessions` is the single source and republishing it is what redraws the
    /// dot — including when a just-finished session's window expires, since
    /// `AgentStatusService`'s 2s poll clears that flag.
    var agentSummary: AgentSummary { AgentSummary(sessions) }
    /// Bumped by `NotchPanel` whenever the display layout changes and the
    /// notch geometry is re-read (decision 037). Nothing reads the value —
    /// publishing it is what makes ContentView evaluate its body again and
    /// pick up the new `NotchGeometry` widths.
    /// True while a file drag is inside the notch's activation region
    /// (decision 051). Expands the panel like a hover does, so the user can
    /// drop without first parking the drag to open it.
    @Published var isDragTargeting = false

    /// True while the pointer is inside the region that opens the *undrawn*
    /// notch — the hover target that survives when the collapsed strip is
    /// hidden on a notchless display (decision 055). Written by
    /// `NotchHoverDetector`, which only runs in that mode; ContentView feeds
    /// it into the same dwell-and-haptic path as a real `onHover`.
    @Published var isPointerNearNotch = false

    @Published var screenGeneration: UInt = 0

    /// True while the first-run hello / setup sequence is playing in the panel
    /// (decision 057). Written by `OnboardingController`.
    ///
    /// It is folded into `displayedExpanded` rather than being handled
    /// separately, and that is the whole trick: the panel is already held open
    /// by that one property, so hover-out, the outside-click monitor, the hit
    /// region and the pin-on-click path all keep the onboarding panel open
    /// without any of them learning what onboarding is.
    @Published var isOnboarding = false

    /// What the UI actually shows: expanded if pinned by a click, currently
    /// hovered, being dragged onto, or running the first-run sequence.
    var displayedExpanded: Bool { isExpanded || isHovered || isDragTargeting || isOnboarding }
}

struct NowPlaying: Equatable {
    var track: String
    var artist: String
    var album: String
    /// Bundle id of the app MediaRemote reports as the now-playing source
    /// (`com.spotify.client`, `com.apple.Music`, `com.google.Chrome`, …).
    /// Empty when the player did not report one.
    var sourceBundleID: String
    var isPlaying: Bool

    var isSpotify: Bool { sourceBundleID == "com.spotify.client" }
}

/// Where playback is in the current track, as of `anchorDate`.
///
/// Units: everything here is **seconds**. MediaRemote reports microseconds
/// (`durationMicros`, `elapsedTimeMicros`) and an absolute epoch timestamp for
/// the measurement; the conversion happens once, in `MediaRemoteService`, so
/// nothing downstream carries that trap.
struct PlaybackProgress: Equatable {
    var duration: TimeInterval
    var anchorPosition: TimeInterval
    var anchorDate: Date
    var isPlaying: Bool

    /// Position extrapolated to `date`. Paused playback ignores elapsed time,
    /// and the result is clamped to the track so a tick arriving after the
    /// track ended cannot draw the knob past the end of the bar.
    func position(at date: Date) -> TimeInterval {
        let raw = isPlaying ? anchorPosition + date.timeIntervalSince(anchorDate) : anchorPosition
        return min(max(raw, 0), duration)
    }

    /// 0...1 along the bar. Zero-length (no track loaded, or an ad Spotify
    /// reports as 0) reads as 0 rather than dividing by zero.
    func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return position(at: date) / duration
    }
}

struct AgentSession: Identifiable, Equatable {
    var id: String           // session id (filename stem)
    var state: String        // "running" | "blocked" | "idle" | "error"
    var label: String
    var updatedAt: Date
    /// The three fields click-to-focus routes on (decision 035): which kind of
    /// host the session lives in, the folder its window is titled after, and
    /// the process to walk up to its terminal. Nothing displays them.
    var cwd: String
    var ide: String
    var pid: Int
    /// One-line summary of what the session is working on, shown beside the
    /// label so two sessions in the same folder are told apart (decision 040).
    /// Empty when the status file carries no `task`.
    var task: String
    /// True for the first `AgentStatusService.finishedWindow` seconds after
    /// this session was observed going running -> idle (decision 042). It is a
    /// *transition*, not a state AgentStatus writes: the status file only ever
    /// says "idle", and "just finished" is the thing a glance at the notch is
    /// actually looking for.
    var justFinished: Bool = false
    /// Whether the status file carried a wrap-up message — AgentStatus's `Stop`
    /// hook writes the turn's closing text into `detail`, and `SessionStart`
    /// forces it empty, so a non-empty `detail` is the durable "this turn ended
    /// and there is output to review" signal (decision 044). Only its emptiness
    /// is read: the message itself is never decoded, stored or rendered
    /// (Agent Guideline #5).
    var hasOutput: Bool = false
    /// A finished turn the user has not acknowledged yet — what the expanded
    /// panel draws as a white light (decision 044). Derived each poll from
    /// `hasOutput`, the session being idle, and `AppState.acknowledgedFinish`.
    var unread: Bool = false
}

/// What one session's transcript says about its spend and pace (decision 048).
/// Every field is a number or a timestamp — no message content reaches here
/// (Agent Guideline #5).
struct SessionStats: Equatable {
    /// Tokens live in the context window as of the last main-chain assistant
    /// message: fresh input + cache writes + cache reads. Shown absolutely
    /// rather than as a percentage, because the transcript records the model as
    /// `claude-opus-5` with no marker for which context window it was opened
    /// with — a session on this machine peaked at 460k, so a bar scaled to 200k
    /// would read "230% full" (UI Principle #4).
    var contextTokens: Int
    /// Everything the session has spent: fresh input + cache writes + output,
    /// summed over every assistant message including subagents'.
    var sessionTokens: Int
    /// When the turn now running started, or nil between turns.
    var turnStart: Date?
    /// What the last completed turn took, as Claude Code measured it.
    var lastTurnDuration: TimeInterval?

    /// How long to show on the row at `date`: the running turn's live elapsed
    /// time, else the last completed turn's duration, else nothing.
    func elapsed(at date: Date) -> TimeInterval? {
        if let turnStart { return max(0, date.timeIntervalSince(turnStart)) }
        return lastTurnDuration
    }

    /// Whether `elapsed` is currently counting up, which is what tells the row
    /// to keep a 1Hz clock running instead of drawing a static figure.
    var isTiming: Bool { turnStart != nil }

    /// "812" / "77k" / "1.2M" — three characters of magnitude, because the row
    /// has room for a magnitude and not for a digit-exact count.
    static func compactTokens(_ tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        if tokens < 1_000_000 { return "\(tokens / 1_000)k" }
        return String(format: "%.1fM", Double(tokens) / 1_000_000)
    }

    /// "8s" / "2m14s" / "1h04m". Seconds are dropped past an hour — at that
    /// scale they are noise, and the field would otherwise widen the cluster.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3_600 { return "\(total / 60)m\(String(format: "%02d", total % 60))s" }
        return "\(total / 3_600)h\(String(format: "%02d", (total % 3_600) / 60))m"
    }
}

/// One-glance rollup of every live session, for the collapsed pill's summary
/// dot (decision 042). Most urgent wins, and `none` means there is nothing to
/// draw at all — the pill keeps its bare width.
///
/// `.finished` reads *both* finished flags, so the pill and the expanded row
/// it summarises are never lit differently: the transient one covers a turn
/// that ended with no wrap-up message, the durable one keeps the light on
/// until the row is clicked (decision 045).
enum AgentSummary: Equatable {
    case none, idle, running, finished, blocked, error

    init(_ sessions: [AgentSession]) {
        if sessions.isEmpty { self = .none }
        else if sessions.contains(where: { $0.state == "error" }) { self = .error }
        else if sessions.contains(where: { $0.state == "blocked" }) { self = .blocked }
        else if sessions.contains(where: { $0.justFinished || $0.unread }) { self = .finished }
        else if sessions.contains(where: { $0.state == "running" }) { self = .running }
        else { self = .idle }
    }
}


extension NSImage {
    /// The cover's representative colour, for tinting glass.
    ///
    /// A plain average washes out to grey-brown on most covers, because the
    /// dark background and letterboxing outnumber the coloured subject. So
    /// each pixel of a 16x16 downscale is weighted by its own saturation
    /// (plus a small floor, so an entirely grey cover still yields grey), and
    /// the result is floored to a saturation and brightness a glass tint can
    /// actually be seen at.
    func dominantColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var sum = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let weight = 0.15 + (high == 0 ? 0 : (high - low) / high)
            sum.r += r * weight
            sum.g += g * weight
            sum.b += b * weight
            sum.weight += weight
        }
        guard sum.weight > 0 else { return nil }

        let average = NSColor(
            srgbRed: sum.r / sum.weight,
            green: sum.g / sum.weight,
            blue: sum.b / sum.weight,
            alpha: 1
        )
        return NSColor(
            hue: average.hueComponent,
            saturation: min(1, max(0.5, average.saturationComponent)),
            brightness: min(1, max(0.6, average.brightnessComponent)),
            alpha: 1
        )
    }
}

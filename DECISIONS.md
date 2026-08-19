# DECISIONS.md — Architecture & Tooling Decisions

> Every significant choice — architecture, tooling, the notch-window mechanics, the
> music-control approach, the OAuth flow, or a reversal of a prior decision — is logged
> here with its context, the options considered, the choice, and the reasoning
> (Agent Guideline #9). Code captures *what* the system does; this file captures *why*.

---

## Decision Index

| # | Date | Decision | Status |
|---|------|----------|--------|
| 001 | 2026-08-19 | Stack: native SwiftUI/AppKit built with SwiftPM (`swift build`), no Xcode project, no Tauri | Accepted |
| 002 | 2026-08-19 | Music signal & transport: AppleScript to the Spotify desktop app (not the private MediaRemote framework) | Accepted |
| 003 | 2026-08-19 | Add-to-playlist: Spotify Web API with OAuth 2.0 PKCE, user-supplied Client ID, loopback redirect | Accepted |
| 004 | 2026-08-19 | Visualizer v1: playback-synced animated bars (no system-audio capture) | Accepted |
| 005 | 2026-08-19 | AgentStatus integration: read-only consumer of AgentStatus's existing status files; Tempo installs no hooks | Accepted |
| 006 | 2026-08-19 | Window: non-activating borderless NSPanel hugging the physical notch; click toggles collapsed/expanded | Accepted |
| 007 | 2026-08-19 | Repository: private GitHub repo `Gameslayer999/Tempo`; v1 scope is Spotify-only | Accepted |
| 008 | 2026-08-19 | Panel sizing: one static NSPanel at expanded size; SwiftUI animates content; custom `hitTest` passthrough outside the drawn shape | Accepted |
| 009 | 2026-08-19 | Hover-grow: strip expands ~10×4pt on hover (boringNotch-style spring); passthrough rect is always the hover-grown size so flicker is structurally impossible | Revised by 011 |
| 010 | 2026-08-19 | Liquid Glass: expanded panel uses macOS 26 `glassEffect` (`.ultraThinMaterial` fallback) with a black-to-glass top gradient; collapsed strip stays pure black | Accepted |
| 011 | 2026-08-19 | Interaction model: hover fully expands (transient) with a haptic tick; click pins; click outside unpins — revises 009 | Accepted |

---

## 001 — Stack: native SwiftUI/AppKit via SwiftPM

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** Tempo is a notch-hugging overlay in the category of boringNotch and
NotchNook. AgentStatus (this user's prior project, whose display concept Tempo
absorbs) used Tauri.

**Options considered.**
- **Tauri (Rust + web UI)** — familiar from AgentStatus, but every notch behavior
  (notch geometry, non-activating panel above the menu bar, fluid expand animation)
  requires reaching through plugins into AppKit anyway; the webview adds weight for
  an animation-heavy always-on surface.
- **Electron** — heaviest option; rejected outright for an always-running overlay.
- **Native SwiftUI/AppKit** — direct access to `NSScreen` notch geometry
  (`safeAreaInsets` / `auxiliaryTopLeftArea`), `NSPanel` styles, and SwiftUI
  animation. This is what the whole category (boringNotch et al.) uses.

**Choice.** Native SwiftUI/AppKit. Built as a **SwiftPM executable** (`swift build`)
rather than an Xcode project: this machine has only the Command Line Tools (no
`xcodebuild`), SwiftPM keeps the build fully scriptable (Agent Guideline #8), and a
`.app` bundle can be assembled from the SPM binary by a small script when needed
(Info.plist for Accessory activation + AppleScript usage description).

---

## 002 — Music signal & transport: AppleScript to Spotify

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** Tempo needs now-playing metadata (track, artist, artwork), play state,
and transport control (play/pause/prev/next) for Spotify.

**Options considered.**
- **MediaRemote (private framework)** — what older notch apps used; Apple locked it
  down in recent macOS (entitlement-gated), it's unstable across versions, and it's
  unverifiable per Agent Guideline #4.
- **Spotify Web API for playback state** — requires network + OAuth just to see what's
  playing, has rate limits and latency, and fails for free-tier control.
- **AppleScript to the Spotify desktop app** — Spotify ships a stable scripting
  dictionary: `player state`, `current track` (name, artist, album, `artwork url`,
  `id`/`spotify url`), `playpause`, `next track`, `previous track`. Local, instant,
  no credentials, works offline.

**Choice.** AppleScript (`NSAppleScript`/`osascript`) polled on a short interval,
guarded by "is Spotify running" so Tempo never launches Spotify as a side effect.
Artwork fetched from the track's `artwork url` (a plain HTTPS CDN image, no auth).
Requires the one-time macOS Automation permission prompt (Tempo → Spotify), which is
documented in the README. The Web API is reserved for the one thing AppleScript
cannot do: modifying playlists (decision 003).

**Addendum (2026-08-19, verified gotcha).** Inside a `tell application "Spotify"`
block, a variable named `st` fails to compile (`Expected expression but found "st".
(-2741)`) — it collides with an undocumented term in Spotify's scripting dictionary.
Use descriptive variable names (e.g. `playerState`) in any AppleScript sent to
Spotify. The fetch script and `playpause` were verified live against the running
Spotify app on this machine; `next track`/`previous track` share the verified
command shape but were not exercised (would have skipped the user's actual song).

---

## 003 — Add-to-playlist: Spotify Web API, OAuth 2.0 PKCE

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** Adding the current song to a playlist is a differentiating v1 feature
and has no AppleScript equivalent.

**Options considered.**
- **Authorization Code + client secret** — requires shipping a secret in a desktop
  app; wrong for open/distributable code.
- **PKCE (Authorization Code with code challenge)** — Spotify's recommended flow for
  apps that can't hold a secret; needs only a Client ID.

**Choice.** OAuth 2.0 PKCE with a **user-supplied Client ID** (the user creates a
free Spotify Developer app once; documented in the README) and a loopback redirect
(`http://127.0.0.1:<port>/callback`) served by a tiny in-process listener during the
auth handshake. Scopes: `playlist-read-private playlist-modify-private
playlist-modify-public`. Tokens (access + refresh) are stored in
`~/Library/Application Support/Tempo/` with `0600` permissions and are never logged
or committed (Agent Guidelines #5, #12). Track identity comes from AppleScript's
track `id` (a `spotify:track:…` URI), so the add call needs no search round-trip.

---

## 004 — Visualizer v1: playback-synced animation

**Date:** 2026-08-19 · **Status:** Accepted (user-approved)

**Context.** The user wants an audio visualizer like the iPhone Dynamic Island's.
The real thing is audio-reactive; on macOS that requires a Core Audio process tap
and an audio-capture permission.

**Options considered.**
- **Real audio-reactive (Core Audio process tap)** — faithful, but a large lift, a
  scary permission prompt, and version-sensitive APIs.
- **Playback-synced animation** — bars animate with organic pseudo-random motion
  while `player state == playing`, settle to a low idle when paused. No permissions,
  no audio pipeline. This is what comparable notch apps ship.

**Choice.** Playback-synced animation for v1 (user chose this explicitly).
Real audio reactivity is queued in `NEXT_STEPS.md` under **Later**.

---

## 005 — AgentStatus integration: read-only consumer, no hooks

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** Tempo's differentiator is showing live Claude Code session lights in
the notch. AgentStatus already solved the signal layer on this machine: its hooks
write one JSON file per session to `~/.claude/status/sessions/<session_id>.json`
(schema verified live on 2026-08-19: `state`, `cwd`, `ide`, `pid`, `label`,
`updated_at`, `task`, `detail`; sibling `<id>.subagents/` marker dirs).

**Options considered.**
- **Tempo installs its own hooks** — duplicates AgentStatus's installer, risks
  double-registration in the user's `settings.json`, and violates the spirit of
  "never break the user's Claude Code".
- **Read AgentStatus's files** — zero installation, zero risk to Claude Code
  sessions, and the schema is stable and locally verifiable.

**Choice.** Tempo is a **read-only** second display layer over AgentStatus's signal
layer. It never writes into `~/.claude/status/**`. If the directory is absent
(AgentStatus not installed), the lights feature hides itself silently (Agent
Guideline #3). Staleness: a session silent past a timeout is dimmed/dropped, mirroring
AgentStatus's own rules. Making Tempo self-sufficient (bundling a hook installer) is
queued under **Later** in `NEXT_STEPS.md`.

---

## 006 — Window: non-activating NSPanel hugging the notch

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** The whole product is a panel that lives at the physical notch,
expands on click, and never interferes with other apps.

**Choice.**
- A borderless, non-activating `NSPanel` (`.nonactivatingPanel`), window level above
  the menu bar (`.statusBar`+), `collectionBehavior` = can-join-all-spaces +
  full-screen-auxiliary, so it rides over full-screen apps like the category leaders.
- Notch geometry from `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (their
  gap is the physical notch); fallback to a fixed 200×32pt centered strip on
  notchless displays.
- **Collapsed (default):** the strip spans artwork + notch + visualizer, visually
  merging with the notch's black. **Click → expanded:** the panel animates open below
  the notch (music controls, playlist picker, agent lights). Click outside or
  re-click → collapse.
- SwiftUI hosted inside the panel (`NSHostingView`) for the animation work.

---

## 008 — Panel sizing: static expanded-size NSPanel + `hitTest` passthrough

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** The panel must animate between the collapsed strip and the expanded
view. Animating the NSWindow frame itself is janky and makes the frame math fragile.

**Choice.** The `NotchPanel` window is always sized to the expanded maximum
(`notchWidth+220 × 190`), positioned once flush with the notch, and never resized —
SwiftUI animates the collapsed/expanded content inside it. To keep the invisible
region from swallowing clicks meant for other apps (Agent Guideline #3),
`PassthroughHostingView` (an `NSHostingView` subclass in `NotchWindow.swift`)
overrides `hitTest(_:)` to return `nil` outside the strip rect (collapsed) or the
full panel rect (expanded), so AppKit routes those clicks through to whatever is
beneath. Collapse-on-outside-click is a global `NSEvent` left-mouse-down monitor.
Cost: one small self-contained override; benefit: zero window-frame animation and
trivial positioning math.

---

## 007 — Repository & v1 scope

**Date:** 2026-08-19 · **Status:** Accepted (user-chosen)

- **Private** GitHub repository `Gameslayer999/Tempo` (the account AgentStatus lives
  under, matching this machine's SSH identity), pushed before any code exists. An
  initial mis-creation under the `gchan453` account was abandoned; the user re-cloned
  from Gameslayer999.
- **Spotify only** in v1 — Apple Music support queued in `NEXT_STEPS.md`.
- Docs structure (CLAUDE.md / DECISIONS.md / NEXT_STEPS.md / README.md) carried over
  from AgentStatus, adapted to Tempo.

---

## 009 — Hover-grow with an always-grown passthrough rect

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** The collapsed strip should subtly expand on mouse hover, like
boringNotch. boringNotch (checked at source: `boringNotch/ContentView.swift`) tracks
hover via `.onHover` and uses `interactiveSpring(response: ~0.38, dampingFraction:
0.8)` for its transitions; it has no distinct "grow while collapsed" state (hover
either adds a shadow or fully opens after a delay), so Tempo's subtle-grow is our own
blend of that feel.

**Choice.**
- `AppState.isHovered`; strip grows 10pt in width and 4pt in height (top-pinned, so
  the notch seam never moves) with `spring(response: 0.32, dampingFraction: 0.68)`.
  Grow is inert while expanded. Because decision 008 fixed the window at expanded
  size, width growth headroom comes from resting the strip 10pt narrower than the
  panel, at the undrawn outer edges.
- **Hit-test strategy:** the passthrough strip rect always uses the hover-grown
  dimensions. A rect that tracked hover state could flicker (grow → pointer outside
  original rect → hover lost → shrink → repeat); a permanently grown rect makes that
  loop structurally impossible at the cost of ~4pt of inert zone below the strip.
- Trackpad haptic feedback on hover (boringNotch has it) was deliberately left out
  as unrequested; queued in `NEXT_STEPS.md` under Later.

---

## 010 — Liquid Glass expanded panel, black collapsed strip

**Date:** 2026-08-19 · **Status:** Accepted

**Context.** The user wants Tempo to match macOS 26's Liquid Glass design language,
citing Notchy — whose look is "a premium, Apple-like Liquid Glass aesthetic built
purely in SwiftUI" applied to the expanded island while the collapsed shape stays
solid.

**Choice.**
- The **collapsed strip stays pure black unconditionally** — it must merge with the
  physical notch (UI Principle #6); glass there would break the illusion.
- The **expanded panel** background is `Color.clear.glassEffect(.regular, in: shape)`
  — the real SwiftUI Liquid Glass API, verified against this machine's macOS 26.5
  SDK (`macOS 26.0+`, `SwiftUICore`) rather than search results — gated behind
  `#available(macOS 26.0, *)` with `shape.fill(.ultraThinMaterial)` as the fallback,
  so `Package.swift` stays at `.macOS(.v14)`.
- A black→transparent `LinearGradient` covers the top `stripHeight + 20`pt of the
  expanded panel so the seam against the notch stays black and fades into glass.
- Track/artist text and transport buttons gained a subtle black shadow for contrast
  against light desktops showing through the glass. `PlaylistSection` /
  `AgentLightsView` contrast on glass is unverified (their files weren't in scope) —
  flagged in `NEXT_STEPS.md`.
- No theme toggle — glass is simply the look (Notchy documents no toggle either).

---

## 011 — Hover fully expands; click pins; click outside unpins (revises 009)

**Date:** 2026-08-19 · **Status:** Accepted (user-specified)

**Context.** The user upgraded the interaction model: instead of 009's subtle
10×4pt hover-grow, hovering should open the FULL expanded panel, mouse-off should
collapse it, a click should hold ("pin") it open, and a click outside should unpin
and collapse. The user also asked for the haptic tick 009 had deliberately omitted.

**Choice.**
- **State model:** `isExpanded` is now the click-owned *pinned* flag; `isHovered`
  tracks the pointer; a computed `displayedExpanded = isExpanded || isHovered` on
  `AppState` drives both the SwiftUI layout and the passthrough hit-test rect.
- **Hover:** `.onHover` sits on a wrapper spanning the strip when collapsed and the
  whole panel when displayed-expanded. Hover-in fires
  `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)` only on the true
  collapsed→hover transition (not repeats, not into an already-pinned panel).
- **Pin:** an `onTapGesture` on the glass background layer (behind the content via
  `.background(…)`) sets the pin — buttons and menus in the foreground consume their
  own taps first, so pinning never steals control clicks. The strip's old
  click-to-toggle is superseded. The global outside-click monitor clears both flags.
- **Hit-test/flicker:** the passthrough rect flips instantly (boolean) between strip
  rect and full rect while the visual grows on the spring, and the full rect strictly
  contains the strip rect, so the flip can never eject the pointer — 009's dead-zone
  headroom (`hoverGrowWidth/Height`) became unnecessary and was removed. One real
  jitter case remains: a pointer outrunning the ~0.35s spring into not-yet-rendered
  panel area can fire a spurious hover-out, absorbed by a 0.15s cancellable hover-out
  debounce (hover-in is never delayed).

**Addendum (2026-08-19, bug fix).** The pin `.onTapGesture` as shipped never fired:
it lived on the `.background()` glass layer, and SwiftUI does not route taps to a
background-layer gesture when a foreground view with its own `contentShape` sits in
front — verified at runtime with temporary logging and synthesized CGEvents (the
AppKit `mouseDown` reached the window with `displayedExpanded=true`; the background
tap closure never ran). Moved the gesture to the foreground content container
(guarded on `displayedExpanded`), whose hit-reachability the hover logs had already
proven; buttons/menus still claim their own taps first per SwiftUI's
descendant-priority rule. Also noted for future UI debugging: this dev shell has
Accessibility (synthetic clicks work) but not Screen Recording (no screenshots), and
raw CGEventPost against this non-activating overlay window class is unreliable —
post-fix behavior was verified structurally.

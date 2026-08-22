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
| 002 | 2026-08-19 | Music signal & transport: AppleScript to the Spotify desktop app (not the private MediaRemote framework) | Amended by 015 |
| 003 | 2026-08-19 | Add-to-playlist: Spotify Web API with OAuth 2.0 PKCE, user-supplied Client ID, loopback redirect | Accepted |
| 004 | 2026-08-19 | Visualizer v1: playback-synced animated bars (no system-audio capture) | Superseded by 016 (kept as fallback) |
| 005 | 2026-08-19 | AgentStatus integration: read-only consumer of AgentStatus's existing status files; Tempo installs no hooks | Accepted |
| 006 | 2026-08-19 | Window: non-activating borderless NSPanel hugging the physical notch; click toggles collapsed/expanded | Amended by 013 |
| 007 | 2026-08-19 | Repository: private GitHub repo `Gameslayer999/Tempo`; v1 scope is Spotify-only | Accepted |
| 008 | 2026-08-19 | Panel sizing: one static NSPanel at expanded size; SwiftUI animates content; custom `hitTest` passthrough outside the drawn shape | Amended by 012 |
| 009 | 2026-08-19 | Hover-grow: strip expands ~10×4pt on hover (boringNotch-style spring); passthrough rect is always the hover-grown size so flicker is structurally impossible | Revised by 011 |
| 010 | 2026-08-19 | Liquid Glass: expanded panel uses macOS 26 `glassEffect` (`.ultraThinMaterial` fallback) with a black-to-glass top gradient; collapsed strip stays pure black | Accepted |
| 011 | 2026-08-19 | Interaction model: hover fully expands (transient) with a haptic tick; click pins; click outside unpins — revises 009 | Amended by 014 |
| 012 | 2026-08-20 | Click-fallthrough fix: hit region tracks the live animating shape geometry, not the expanded/collapsed flag — amends 008 | Accepted |
| 013 | 2026-08-20 | Geometry: Dynamic-Island collapsed pill (notch + content-fit wings, concave-top NotchShape); expanded panel is content-sized — amends 006 | Amended by 019 |
| 014 | 2026-08-20 | Motion & control polish: boringNotch spring constants, 0.25s hover dwell, Reduce Motion fades, HIG 28pt targets + press states, semantic colors — amends 011 | Accepted |
| 015 | 2026-08-20 | Spotify signal delivery: event-driven via `PlaybackStateChanged` distributed notification; 1s AppleScript poll removed — amends 002 | Accepted |
| 016 | 2026-08-20 | Real audio-reactive visualizer: Core Audio per-process tap on Spotify + 5-band vDSP FFT; 004's animation kept as silent fallback — supersedes 004 | Accepted |
| 017 | 2026-08-20 | System usage graph: CPU + memory sparklines (Notchy/iStat style) in the expanded panel; Path-based, never Canvas | Accepted |
| 018 | 2026-08-20 | Packaging: `scripts/make-app.sh` assembles a signed `dist/Tempo.app`; required for the audio-capture permission | Accepted |
| 019 | 2026-08-20 | Pill content insets clear the silhouette's corner curves; album art travels from the pill into the expanded header, left of the transport controls — amends 013 | Accepted |
| 020 | 2026-08-20 | Settings: a separate ordinary NSWindow (System-Settings sidebar+form), opened by a gear in the expanded panel; preferences in UserDefaults, Client ID written to config.json from the Music pane | Accepted |
| 021 | 2026-08-20 | Visualizer reads the tap's buffer in the aggregate input list, not buffer 0 — buffer 0 is the output device's microphone whenever it has one — fixes 016 | Accepted |
| 022 | 2026-08-20 | Fullscreen: drop the panel below the top edge to dodge macOS's chrome reveal | **Reverted** same day — pill sits at the notch |
| 023 | 2026-08-20 | Settings Music pane is a guided 3-step setup (dashboard link, redirect-URI copy, Client ID); the developer app itself cannot be removed — Spotify's AppleScript dictionary has no playlist support | Accepted |
| 024 | 2026-08-20 | Visualizer claims the play state on appear without starting a transition — `.task(id:)` fires on appear, which froze the bars at full playing height on a paused launch — fixes 004/016 | Accepted |
| 025 | 2026-08-20 | A minimal `NSApp.mainMenu` (app + Edit) so the Settings text field accepts ⌘V/⌘C/⌘X/⌘A — an accessory app has no main menu, and AppKit routes editing key equivalents through it | Accepted |
| 026 | 2026-08-20 | Playlist picker lists only playlists the user can add to (owned or collaborative), and add-failures report Spotify's actual reason — amends 003 | Accepted |
| 027 | 2026-08-20 | Playlist search lives in Settings (searchable list + chosen favorites), not in the notch panel — the panel stays non-key | Accepted |
| 028 | 2026-08-20 | Expanded header: 72pt cover, title centred over the play button, transport spread full width, gear as a corner overlay — amends 019 | Accepted |
| 029 | 2026-08-20 | Expanded panel gets a visible glass rim: gradient 1.2pt stroke + blurred 3pt under-stroke, overlaid outside the clip, masked off across the black notch-merge band — amends 010 | Accepted |
| 030 | 2026-08-20 | Panel material is a preference: regular / clear / album-tinted glass / solid, from the only three real `Glass` variants plus an opt-out — amends 010 | Accepted |
| 031 | 2026-08-20 | Paint a 5% substrate under the expanded panel's glass: macOS routes clicks on a non-opaque window by backing-store alpha, and Liquid Glass paints none — amends 010 | Accepted |
| 032 | 2026-08-20 | Pin-on-click moves to `NotchPanel.sendEvent` so clicks on controls also pin the panel; only an outside click closes it — amends 011 | Accepted |
| 033 | 2026-08-20 | The outside-click monitor must ignore clicks that land on the panel: a non-activating app's own clicks reach its global monitor — completes 032 | Accepted |
| 034 | 2026-08-20 | Hover-expand dwell becomes a setting (0–400ms, default 60ms) so the haptic tick lands while the finger is still on the trackpad; pattern/threading/background-actuation ruled out by measurement — amends 011 | Accepted |
| 035 | 2026-08-20 | Agent lights become buttons: a click goes to that session's host window (AgentStatus's `focus_session`, macOS paths, ported to Swift), minus the `~/.claude/status` focus relay and the background-agent launch — amends 005 | Accepted |
| 036 | 2026-08-21 | Notch on the lock screen: **not possible** from an app — macOS composites the lock screen in a context that excludes user-session windows at every level | **Rejected** (built, measured, reverted) |
| 037 | 2026-08-22 | Notch geometry is re-read on every display change and the panel re-framed; the target stays the built-in notched screen, falling back to the menu-bar display when the lid is shut | Accepted |
| 038 | 2026-08-22 | The media UI (cover, visualizer, transport, playlist) hides after 60s with nothing playing, and the collapsed pill shrinks to the bare notch — amends 013 | Accepted |
| 039 | 2026-08-22 | The visualizer settles when the output device is muted or at zero volume: a process tap is taken before device volume, so muting was invisible to it — amends 016 | Accepted |
| 040 | 2026-08-22 | Agent rows show the session's `task` excerpt beside the label and stack vertically: the folder label alone can't tell two sessions in one repo apart — amends 005, narrows Guideline #5 | Accepted |
| 041 | 2026-08-22 | Scrubbable progress bar in the expanded panel: position is an extrapolated *anchor*, reconciled at 1Hz only while the panel is open, and seeks are optimistic with a 0.5s settle window — amends 015 | Accepted |
| 042 | 2026-08-22 | The collapsed pill carries an agent light outboard of the visualizer — a summary dot by default, switchable in Settings — with a derived "just finished" state, mirrored slot geometry, and no dependence on media being active — amends 005/038 | Accepted |
| 043 | 2026-08-22 | Lights reconcile against Claude Code's own view: an interrupted turn greys, a background job's light says what Claude Code says — reads `~/.claude/sessions` and `claude agents --json`, both read-only — amends 005 | Accepted |
| 044 | 2026-08-22 | The expanded panel's rows show a white **unread** light for a finished turn nobody has looked at, cleared by the click that goes to the session; derived from `detail`'s emptiness, kept out of the collapsed pill — amends 005/042 | Accepted |

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

**Addendum (2026-08-20).** Hover timing and dwell amended by 014.

---

## 012 — Click-fallthrough fix: hit region tracks live geometry (amends 008)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** The user's top bug: hover the notch, panel expands, click pause — the
click sometimes lands on the window *behind* the panel. Root cause found in 008's
`hitTest`: it keyed off the discrete `displayedExpanded` boolean. On hover-out the
boolean flips instantly while the panel is still visually expanded mid-spring
(0.35–0.45s), so the hit region snapped to the collapsed strip and a click on a
still-visible control fell through the transparent window to the app behind.

**Options considered.**
- **Delete the custom `hitTest`, rely on stock `NSHostingView`** (what boringNotch
  does — verified at source: they have zero hitTest overrides). *Rejected by
  measurement:* on this machine (macOS 26.6, Swift 6.3), `NSHostingView.hitTest`
  returns `self` for **every** point in its bounds — even with
  `.allowsHitTesting(false)` on the root view — so a stock view would swallow every
  click in the transparent 405×280 window (worse Guideline #3 violation).
- **Track the live animated geometry.** `NotchShape.path(in:)` is called by SwiftUI
  once per animation frame with the interpolated rect (measured ~298 calls per
  0.45s spring, both directions). The always-present silhouette layer reports that
  rect to a lock-guarded `NotchHitRegion`; `hitTest` reads it.

**Choice.** Live geometry. Regions: *displayed-expanded* → the expanded panel's
target rect (jumps to full size instantly so a pointer travelling pill→controls
can't outrun the spring and cancel the expansion); *collapsing* → the live shrinking
shape (the fix: a click on a still-visible control is caught at every animation
step); *settled collapsed* → exactly the pill. Verified by driving the compiled real
sources through `hitTest` directly: mid-collapse control clicks captured at every
sampled height (182→107pt), passthrough beside/below the pill intact. Also from the
boringNotch dive: `canBecomeKey`/`canBecomeMain` overridden to false,
`isFloatingPanel`, `.ignoresCycle`, `darkAqua` appearance; `acceptsFirstMouse` is
NOT needed (boringNotch ships without it; clicks on SwiftUI buttons in a
non-activating panel work as first clicks).

**Constraint discovered (load-bearing).** A view inserted by an `if` branch does
not join an in-flight animation — it is evaluated once, at final size. The
reporting silhouette must therefore live *outside* every branch, or the hit region
would report nothing exactly when it matters (during collapse).

---

## 013 — Dynamic-Island pill + content-sized panel (amends 006)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** The collapsed strip spanned `notchWidth + 220pt` — far wider than its
content; the user wants an iOS-Dynamic-Island-style pill "wide enough to hold the
song cover and the audio visualizer, but no wider than needed". Separately, the
expanded panel's fixed 190pt height overflowed once agent lights (and the new usage
graph) were present, and would show dead glass when sections hide.

**Choice.**
- **Pill:** width = `notchWidth + 2×wingWidth`; each wing holds one
  `(stripHeight−10)pt` square (artwork left, visualizer right) plus 6pt padding —
  on this machine 185+2×35 = **255pt** (was 405). Height = physical notch height.
- **Shape:** a custom `NotchShape` — top corners *concave* (flare out and tuck
  under the menu-bar edge), bottom corners convex; radii animate. Constants adopted
  from boringNotch's tuned values: collapsed top 6 / bottom 14, expanded top 19 /
  bottom 24. Written from the geometric spec, not copied source (GPL).
- **Content-sized expanded panel:** the window is a fixed 280pt-tall ceiling
  (008's never-resize principle stands); the drawn panel measures its actual
  content (sections hide/show: playlist unconfigured, no agent sessions) via a
  GeometryReader report into an explicit — therefore spring-animatable — container
  height, which also feeds the hit region's expanded target (012). No dead glass,
  no overflow, and the window band below a short panel stays click-through.

---

## 014 — Motion & control polish: boringNotch constants + HIG (amends 011)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** The user asked for category-leader polish ("look at Notchy and
boringNotch") and macOS-native feel (Apple HIG). Sourced from the boringNotch
code dive and a fetch of the actual HIG pages (Materials, Motion, Accessibility,
Buttons, Typography, Windows, Popovers, Charts).

**Choice.**
- **Hover dwell 0.25s** before expanding (boringNotch defaults 0.3s): a pointer
  merely crossing the notch never flickers the panel open. Haptic tick moved to
  when the expansion actually fires. Hover-out debounce 0.1s (boringNotch's value).
- **Springs:** open `.spring(response 0.42, damping 0.8)` (slight overshoot);
  close `.spring(response 0.45, damping 1.0)` — critically damped, no bounce into
  the notch. Both are boringNotch's shipped constants; HIG publishes no numeric
  spring guidance (verified — don't cite one as Apple's).
- **Reduce Motion** (`accessibilityReduceMotion`): both springs replaced by a
  0.15s ease + opacity transition — HIG explicitly says replace movement and
  blur transitions with fades.
- **Controls:** ≥28×28pt hit targets (HIG's macOS control size; the 44pt figure is
  iOS), `NotchButtonStyle` with hover capsule highlight AND a pressed state (HIG:
  "without a press state, a button can feel unresponsive") — replaces the
  hover-scale-only modifier. Semantic `.primary`/`.secondary` instead of hardcoded
  grays/white-opacities (vibrancy-aware on glass).

---

## 015 — Event-driven Spotify signal (amends 002)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** 002's 1s AppleScript poll = ~3600 Apple-event round trips/hour
forever, a large share of Tempo's steady-state CPU. boringNotch has no music
polling at all: Spotify posts a `com.spotify.client.PlaybackStateChanged`
distributed notification on every play/pause/track change.

**Verified live on this machine (Guideline #4).** The notification fires
instantly; userInfo carries `Player State` (**title-case** "Playing"/"Paused" —
unlike AppleScript's lowercase), `Track ID` (full `spotify:track:` URI), `Name`,
`Artist`, `Album`, `Duration`, `Playback Position`, etc. **No artwork URL** —
confirmed absent, so AppleScript remains the only artwork path.

**Choice.** Subscribe to the notification; same-track events update state with
zero AppleScript; a track-identity change triggers ONE AppleScript fetch (artwork).
One fetch at startup and on Spotify launch (NSWorkspace observers); state cleared
immediately on Spotify termination. A 30s reconciliation poll runs only while
Spotify is running, as insurance against a dropped notification. Steady-state:
1s-interval polling → 2 cheap calls/min, and instant (not up-to-1s-late) UI
updates. AppleScript remains the transport-command and artwork mechanism (002's
core choice stands).

---

## 016 — Real audio-reactive visualizer: Core Audio process tap (supersedes 004)

**Date:** 2026-08-20 · **Status:** Accepted (user-requested)

**Context.** The user asked to "make the audio visualizer for real this time."
004's playback-synced animation becomes the fallback.

**Verified live on this machine (Guideline #4), full probe first.**
- Per-process tap on Spotify works: PID → process object → `CATapDescription`
  (stereo mixdown, private, **`muteBehavior = .unmuted`** — `.mutedWhenTapped`
  would silence Spotify for the user) → process tap → private aggregate device
  (drift-compensated tap list) → IOProc. Delivered format: 48kHz float32
  interleaved stereo, 512 frames/callback at 93.75Hz, pre-device-volume.
- **TCC trap:** every call returns `noErr` even when unauthorized — denial is
  *silent all-zero buffers*. Authorization is only ever granted to a signed
  `.app` bundle (grant lives under Privacy & Security → Screen & System Audio
  Recording); a bare `.build/release/tempo` always gets silence. Embedded-plist
  CLI workarounds do not work for `kTCCServiceAudioCapture`.
- Cost: 512-pt vDSP FFT + 5 band means ≈ 1µs/callback (~0.01% core); probe
  process 0.0–0.1% CPU.

**Choice.** `AudioTapService`: tap exists only while Spotify runs (NSWorkspace +
HAL process-object-list observers; Spotify's audio object appears only after it
first touches the HAL); full rebuild on default-output-device change (the
aggregate pins the output UID); teardown order Stop → DestroyIOProc →
DestroyAggregate → DestroyTap. IO thread computes 5 log-scaled band levels
(Hz edges 93.75/187.5/468.75/1218.75/4031.25/Nyquist, per-band gain calibrated
against live Spotify); a 30Hz main-thread pump applies asymmetric smoothing
(attack 0.5 / release 0.10) and publishes. Bass renders in the center capsule,
frequency rising outward. **Silent-denial detection:** ~2s of exact zeros while
Spotify's process object reports output running → `isCapturing=false` →
`VisualizerView` uses 004's animation (which now also caps at 30Hz and fully
pauses its TimelineView when settled — the old always-on display-refresh redraw
was the main CPU leak). Zero redraws and zero timers at rest in both modes.
Levels are derived and discarded; no samples are ever stored (Guideline #5).
Verified end-to-end: the production service, compiled into a signed harness app,
captured real music (bands separating naturally); the unbundled binary correctly
detected denial and fell back. macOS <14.2 lacks the tap API → fallback via
`#available`.

---

## 017 — System usage graph: CPU + memory sparklines

**Date:** 2026-08-20 · **Status:** Accepted (user-requested)

**Context.** The user likes Notchy's usage view. Research: Notchy self-describes
it as an "iStat-style flyout" (CPU/memory/network); no screenshot of Notchy's own
rendering was findable, so the visual language was taken from iStat Menus itself —
scrolling history graphs, bold numerals, no axis chrome.

**Choice.** `SystemStatsService` (1Hz): CPU from `HOST_CPU_LOAD_INFO` tick deltas
(aggregate, unprivileged, sub-ms); memory from `HOST_VM_INFO64` — used =
`(active + wired + compressor) × host_page_size()` (16KB pages on Apple Silicon —
never hardcode 4096) over physical memory, matching Activity Monitor's
convention (verified against `vm_stat` to the exact page count; `top`'s higher
figure additionally counts inactive pages — explained, not a bug). 60-sample ring
buffers; sampling starts at launch so history exists on first expand.
`UsageGraphView`: headerless 24pt row, two cells (CPU | MEM) — SF Symbol +
monospaced-digit percentage + 80×22pt area sparkline on a **fixed 0–100 scale**
(HIG: fixed range when bounds are meaningful), newest at right, `.secondary`
color, value tinted red only >80%, "--" until a real sample exists (never a fake
0), accessibility labels per cell. **Path/Shape rendering only — never SwiftUI
`Canvas`**: the first Canvas in a process pays a one-time ~93MB Metal allocation;
nothing in Tempo uses Canvas and nothing may start to. Swift Charts likewise
rejected (built on Canvas, heavy for a fixed sparkline).

---

## 018 — Packaging: signed `dist/Tempo.app` via `scripts/make-app.sh`

> **Amended 2026-08-20:** the script now SIGTERMs any process still running the
> bundle it just replaced, waits for it to exit, and **relaunches it**. `open dist/Tempo.app`
> on an already-running app *activates the existing process* rather than
> launching the new binary, so three consecutive rebuilds were tested against a
> build from before all of them — which read as "the new feature isn't there".
> The pattern matches the bundle-relative suffix (`Tempo.app/Contents/MacOS/
> tempo`), not the absolute path: this repo resolves under both
> `…/Documents/code/Tempo` and `…/documents/code/tempo`, and while the
> filesystem is case-insensitive, `pgrep -f` is not — an absolute-path pattern
> silently matched nothing. SIGTERM only; a stuck process is the user's to deal
> with, not something a build script should SIGKILL. Quitting *without*
> relaunching was the first version and was wrong in its own way — a rebuild
> silently took the notch off screen, which cost another round trip. An app
> that was not running before the rebuild stays not running.

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** Queued since 008 for login-item/TCC identity; became mandatory when
016 proved audio capture is only ever authorized for a signed bundle.

**Choice.** One idempotent script: `swift build -c release` (with build-lock
retry), fresh `dist/Tempo.app` assembly, Info.plist from an in-script heredoc
(single source of truth): `com.gameslayer999.tempo`, `LSUIElement`,
`NSAppleEventsUsageDescription`, `NSAudioCaptureUsageDescription`; codesign with
an Apple Development identity if present, else ad-hoc with a stable identifier;
`codesign --verify` + `plutil -lint` gates. `dist/` gitignored. **Caveat:** with
ad-hoc signing, TCC grants may not survive rebuilds (in practice the audio grant
survived one ad-hoc re-sign during verification, but it is not guaranteed);
a self-signed "Tempo" certificate — the pattern AgentStatus already uses on this
machine — is queued in NEXT_STEPS as the durable fix. Bundled launch is now the
*primary* run path (the bare binary cannot capture audio, 016).

---

## 019 — Pill content insets + album art moves into the expanded header (amends 013)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** Two defects the user reported against 013's layout.

1. *Content overflowed the black pill.* 013 sized each wing as
   `contentSquare + 12` and centred the square in it, so the square's outer edge
   landed exactly on the pill's **rect** edge. But `NotchShape`'s straight side
   starts `collapsedTopRadius` (6pt) *inside* that rect, and the bottom corner
   rounds away over `collapsedBottomRadius` (14pt). Measured on this machine:
   at the artwork's bottom edge (5pt above the pill's bottom) the shape's
   boundary sits **8.3pt** in from the rect edge while the artwork started at
   **6pt** — a 2.3pt overhang at both bottom corners, and the top corners were
   flush to within 0.05pt. Invisible over a dark full-screen window, obvious
   over a light desktop, which is exactly how it was reported. The visualizer
   compounded it: its bar row is 25pt wide but 013 gave it a
   `contentSquare`-wide (23pt) frame, so it overflowed its own slot too.
2. *Expanded controls sat alone against the panel's left edge*, with the album
   cover stranded up in the pill.

**Choice.**
- **Explicit, curve-derived insets.** `wingOuterInset =
  NotchShape.collapsedTopRadius + contentInset` (12pt) and `wingInnerInset =
  contentInset` (6pt), with `contentInset` (6pt) also setting the vertical
  inset — so `contentSquare = stripHeight − 12`. The wing's content slot is
  `max(contentSquare, VisualizerView.naturalWidth)`, keeping both wings
  identical and neither one's content past its slot. On this machine: square
  23→21pt, wing 35→43pt, pill 255→**271pt**; worst-case clearance between
  content and the shape boundary is now 4.3pt (was −2.3pt).
- **Album art travels into the panel.** The expanded view opens with a
  `nowPlayingHeader`: 56pt cover on the left, track/artist and the transport row
  stacked to its right. The cover is the *same* view as the pill's, paired by
  `matchedGeometryEffect`, so it flies down-left and grows rather than
  cross-fading; the pill's slot keeps its width, so the visualizer and the notch
  gap never shift. The pill is unchanged while collapsed.

**Rejected.** Clipping the strip content to `NotchShape` — it would hide the
overhang instead of fixing the spacing, and would shave the artwork's corners.
Also rejected: shrinking only the vertical inset to keep a 23pt square; the
report was that the border felt *tight*, so the extra breathing room is the
point.

---

## 020 — Settings: a separate activating NSWindow, opened by a gear in the panel

**Date:** 2026-08-20 · **Status:** Accepted

### Context

Tempo had no settings surface at all: the Spotify Client ID could only be
configured by hand-writing `~/Library/Application Support/Tempo/config.json`
(the one manual step the README documented — exactly what Agent Guideline #8
exists to eliminate), and the display modules could not be turned off. The
user asked for the pop-out settings NotchNook and boringNotch have, matching
macOS System Settings, opened from a gear in the expanded view's top-right.

### The constraint that decides the shape

The notch panel is a non-activating `NSPanel` whose `canBecomeKey` is
hard-`false` (decision 006, Agent Guideline #3). A window that can never
become key can never receive a keystroke — so the Client ID field cannot live
in the panel. Settings has to be a second, ordinary window.

### Options considered

| Option | Pros | Cons |
|---|---|---|
| Settings inside the notch panel | No new window; stays in the notch metaphor | **Can't type into it** — the panel is non-activating by design. Would also make the panel a menu, against UI Principle #3 |
| SwiftUI `Settings` scene | Free ⌘, handling and window plumbing | Requires an `App`-lifecycle app; Tempo is `main.swift` + `NSApplicationDelegate` (decision 001). Would mean restructuring the app entry point for one window |
| **Separate `NSWindow` built by an owner object** (chosen) | Ordinary focusable system-appearance window; no change to the panel or the app entry point; window is built once and reused so pane selection and an in-progress edit survive close/reopen | We do the activation ourselves |

### Decisions

1. **`SettingsWindowController` owns one lazily-built `NSWindow`**
   (`.titled/.closable/.miniaturizable/.resizable/.fullSizeContentView`,
   transparent titlebar so the sidebar material runs up under it).
2. **Activation policy stays `.accessory`** — no Dock icon appears. Opening
   calls `NSApp.activate(ignoringOtherApps: true)` then
   `makeKeyAndOrderFront`. `ignoringOtherApps` is load-bearing, not legacy
   habit: measured on macOS 26.6 that plain `NSApp.activate()` leaves the
   window `isVisible == true` but `isKeyWindow == false`, because the panel
   that was clicked is non-activating and the system therefore does not treat
   Tempo as the app the user is interacting with. A non-key window cannot take
   the Client ID field's keystrokes. This is the one moment Tempo takes focus,
   and only because the user explicitly clicked the gear.
3. **Layout: `NavigationSplitView` sidebar + `.formStyle(.grouped)` detail**,
   panes General / Music / Modules / About — the System Settings shape the user
   asked for, and the one that scales as panes are added.
4. **The gear collapses the panel on the way out.** Necessary, not cosmetic:
   `NotchPanel`'s outside-click monitor is a *global* monitor, and a click in
   Tempo's own Settings window is not global, so a pinned panel would otherwise
   stay open behind/above Settings forever.
5. **Preferences live in `UserDefaults`** (`Preferences.shared`), defaulting to
   on so a fresh install behaves exactly as before. The Client ID is *not*
   among them — it stays in Application Support beside the tokens, the one
   place with owner-only permissions (Agent Guideline #5). The Music pane
   writes `config.json` at 0600 via `SpotifyWebAPI.saveClientID`, and changing
   the id to a different app drops the tokens issued to the old one.
6. **Launch at login via `SMAppService.mainApp`**, with the system as the source
   of truth (re-read every time the window opens, since the user can also
   remove the login item in System Settings). From the bare `swift build`
   binary there is no bundle to register: the toggle is disabled and says so
   rather than failing silently.
7. **Hiding the visualizer keeps its wing slot.** The collapsed pill's width is
   a `static let` that `NotchPanel`'s hit-region clamp floors against; making
   it depend on a preference would make the panel over-claim clicks in
   transparent area when the visualizer is off (Agent Guideline #3). The slot
   stays, its content is simply not drawn. Revisit if the empty wing reads as
   broken.
8. **Switching the usage module off stops `SystemStatsService`** (new `stop()`),
   driven by a Combine sink on the preference in `AppDelegate` — a hidden
   module should cost nothing, not just be invisible.

### Consequences

- The README's manual `config.json` step becomes optional; hand-editing still
  works.
- Tempo now briefly takes focus when Settings opens. The notch panel itself is
  unchanged: still non-activating, still never key.

---

## 021 — Visualizer must read the tap's buffer, not buffer 0 (fixes 016)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

Reported: the visualizer sometimes looks like audio is playing when music is
stopped — noticed while in a meeting.

### Root cause

Decision 016's tap is correctly scoped to Spotify
(`CATapDescription(stereoMixdownOfProcesses:)`), but the IO proc runs on the
**aggregate device**, whose input buffer list is *the sub-device's input
streams first, the tap's streams after them*. `TapProcessor.process` read
`abl[0]` unconditionally.

Verified on macOS 26.6 by building the exact aggregate this codebase builds and
reading `kAudioDevicePropertyStreamConfiguration` (input scope) — no IO proc, so
no microphone was opened:

| Aggregate's sub-device | Input buffer layout | What `abl[0]` is |
|---|---|---|
| Output-only device (built-in speakers, AirPods in A2DP) | `[2]` | the tap ✅ |
| Device that also carries an input stream | `[1, 2]` | that device's **microphone** ❌ |

So buffer 0 was the tap only by luck of the user's current output device.
Whenever the default output device also has an input stream — a headset in call
mode, or the input+output virtual device meeting apps install — Tempo was
running its FFT over **microphone audio**: bars that dance to the room with
Spotify stopped, and a direct contradiction of the README's privacy claim that
the tap is scoped to Spotify.

Notably this machine's AirPods currently enumerate as *two* devices
(`…:input` / `…:output`), so the plain-desktop case never showed the bug — which
is why it survived 016's live verification.

### Fix

`AudioTapService.tapBufferIndex(aggregate:subDevice:)` computes the tap's
position as the sub-device's input-buffer count, checked against the
aggregate's own input layout, and hands it to the processor before the IO proc
starts. `process()` reads `abl[tapBuffer]` with an `abl.count > tapBuffer`
guard, and the non-interleaved second-channel lookup moves to
`abl[tapBuffer + 1]`.

Verified against real aggregates of Tempo's exact shape: output-only sub-device
→ index 0 (a no-op, so the behaviour 016 verified live is unchanged);
sub-device with an input stream → index 1, and the buffer at that index is the
2-channel stereo mixdown the tap produces.

### Considered and rejected

- **Gate `isCapturing` on `isRunningOutput(spotifyProcessObject)` at 30 Hz** —
  treats the symptom, adds a HAL property read per frame, and would still have
  left mic audio going through the FFT.
- **Build a tap-only aggregate (no sub-device)** — would make index 0 correct by
  construction, but changes the device topology that 016 verified live capturing
  real music, for no benefit over reading the right index.

---

## 022 — Fullscreen drop instead of suppressing the chrome reveal

**Date:** 2026-08-20 · **Status:** Reverted the same day — see the reversal below

### Context

In a fullscreen app, pulling the pointer straight up to the notch slides down
the menu bar and the fullscreen window's title bar (its close/expand buttons).
Requested: don't reveal it when going to the notch, but keep revealing it
everywhere else along the top edge.

### What was ruled out first

- **Public API.** There is none. The reveal is the WindowServer's, keyed on
  cursor position; `NSApplication.presentationOptions` and
  `NSMenu.setMenuBarVisible` only affect the calling app, and Tempo is never
  the active app. The close/expand buttons are the *other* app's AppKit
  title bar, in that app's process.
- **The category hasn't solved it.** boringNotch carries the same complaint as
  open bugs (#1359, #764) — theirs additionally gets stuck revealed.
- **Private SkyLight symbols.** Probed on this machine (macOS 26.6):
  `SLSSetMenuBarVisibilityOverrideOnDisplay`, `SLSSetMenuBarInsetAndAlpha` and
  `SLSSetMenuBarDrawingStyle` all resolve. Rejected: they are *system-wide*,
  not region-scoped, so Tempo would have to run a continuous global cursor
  monitor and toggle a global override as the pointer crosses the notch —
  reaching into a system surface every other app depends on (Agent Guideline
  #3) — on unversioned private API, and they address the menu bar, not the
  title bar the user actually named.

### Decision

Tempo can't veto the reveal, but it can change **where it invites the pointer
to stop**. While a fullscreen window owns the notched display, the panel drops
`fullscreenDrop` (10pt) below the top edge: a pointer pulled straight up lands
on the pill without entering the trigger band, and the bare top edge either
side of the pill still reveals the chrome exactly as before.

Implementation notes:

- **The window moves, not the content.** `activeRect` is in window
  coordinates, so it travels with the frame and decision 012's live-geometry
  passthrough keeps working untouched.
- **Detection is event-driven, not polled** (`activeSpaceDidChange` +
  `didActivateApplication` — entering, leaving, or switching into a fullscreen
  app always changes the Space), evaluated immediately and again at +0.8s
  because the new window geometry isn't in place when the Space notification
  fires. A resting panel still costs nothing.
- **`CGWindowListCopyWindowInfo`** with `.optionOnScreenOnly` (current Space
  only), reading layer and bounds but never `kCGWindowName`, so it needs no
  Screen Recording grant and raises no prompt — verified with a bare unsigned
  binary. Measured baseline: ordinary maximized windows sit at y=34 under the
  34pt menu-bar inset and never match; a fullscreen window starts at y=0 and
  spans the full display height.

### Reversal (same day)

Removed at the user's request; the panel sits at the notch again and the whole
detection path (`observeFullscreen`, `CGWindowListCopyWindowInfo`, the drop) is
gone rather than left dormant behind a zero constant.

Worth recording precisely, because the reversal rests on a **failed test, not a
measurement**: the drop was reported as ineffective, but the Tempo process on
screen had started at 11:26:19, before any of that day's three builds — `open
dist/Tempo.app` activates an already-running instance instead of launching the
replaced binary, so the running app contained no drop at all. By the time this
came to light the user had chosen to keep the pill at the notch, which settles
it; but the 10pt drop remains **untested**, not disproved. If this is revisited,
start by actually observing it, then escalate toward the menu-bar height (34pt)
— which puts the pill fully below the notch and is a real change in look.

The stale-instance trap itself is now fixed in `scripts/make-app.sh` (see 018).

---

## 023 — The Spotify developer app can't be removed, only made one click per step

**Date:** 2026-08-20 · **Status:** Accepted

### The question

Can the one-time Spotify Developer app setup be dropped?

### Answer: no, and the reason is checkable

Verified against the installed Spotify **1.2.95.453** by reading its scripting
definition directly (`/Applications/Spotify.app/Contents/Resources/Spotify.sdef`,
Agent Guideline #4): the dictionary declares two classes (`application`,
`track`), five commands (`play`, `pause`, `playpause`, `next track`,
`previous track`, `play track`) and track properties. The string "playlist"
does not appear in the file at all.

So add-to-playlist has to go through the Web API, and Spotify requires every
Web API app to be registered under a developer account. Shipping a Client ID
inside Tempo doesn't help either: apps in Development Mode serve only up to 25
users, each added by hand in the dashboard, and Extended Quota Mode needs an
app review — so an embedded id would still mean per-user dashboard work, plus
it would tie every user to one person's developer app.

### What was done instead

The Music pane is now a guided three-step flow rather than a bare field:

1. **Open Dashboard** button (`NSWorkspace.open`) — no URL to retype.
2. The Redirect URI shown in monospace, selectable, with a **Copy** button that
   confirms for two seconds. It has to be character-exact, which is the step
   most likely to be got wrong by hand.
3. The Client ID field and **Save**.

The footer states plainly why the step can't be skipped, and that the Client ID
is not a secret (PKCE publishes it) but is still stored owner-only alongside the
tokens.

### Also fixed here

`SettingsWindowController`'s window gets
`collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`. A plain
window stays in the Space it was first opened on, so clicking the gear from
another desktop either switched Spaces or appeared to do nothing instead of
showing Settings where the user was.

---

## 024 — Visualizer must not start a transition on appear (fixes 004/016)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

Launching Tempo with nothing playing showed bars at playing height, frozen
there — a launch with no audio looked exactly like music playing.

### Root cause

`VisualizerView.transitionStart` is deliberately initialised to `.distantPast`
so the first render reads as a *completed* transition; the existing comment even
warns that starting it at `.now` "would leave a paused visualizer frozen at full
playing height on appear". But the `.task(id: isPlaying)` that drives the
play/pause fade stamped `transitionStart = .now` unconditionally — and
`.task(id:)` fires once when the view *appears*, not only when the id changes.
So every launch re-created the documented hazard.

With `transitionStart == .now`, `playEnergy` reads progress ≈ 0 and returns
`1 - eased` ≈ **1.0** — full playing height — and the `TimelineView` is paused
whenever `!isPlaying && settled`, both of which are true on a paused launch, so
that frame is the one that stays. Reproduced numerically against the view's own
maths: bar fractions `[0.57, 0.80, 0.33, 0.65, 0.69]` instead of a flat
`[0.15 × 5]`.

### Fix

A `didAppear` flag: the first run of the task claims the current play state
without starting a transition, and only genuine `isPlaying` changes stamp
`transitionStart`. Verified: energy 0.00 and a flat `[0.15 × 5]` on a paused
launch, unchanged behaviour on a play/pause flip.

### Note on 021

This is a *separate* cause from decision 021's microphone-buffer bug, and it is
the one that matches "looks like it's playing at launch". 021 remains a real
defect — it was verified structurally — but the two should not be conflated.

---

## 025 — A main menu, purely to make ⌘V work in Settings

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

The Client ID could not be pasted into the Settings field. Typing worked;
⌘V did nothing.

### Root cause

AppKit resolves editing key equivalents through
`NSApp.mainMenu.performKeyEquivalent(with:)` *before* the keystroke reaches the
responder chain — ⌘V is delivered by the Edit menu's Paste item, not by the text
field itself. An accessory app (`LSUIElement`) launched from `main.swift` with
no nib has **no main menu at all**, so there was nothing to carry the shortcut.

Verified both directions against the real app, with a temporary hook that put a
known string on the pasteboard, made the Client ID field first responder, and
sent a synthesized ⌘V through the main menu:

| | `performKeyEquivalent` | field contents |
|---|---|---|
| No main menu (the reported state) | `false` | `""` |
| With the Edit menu | `true` | `"PASTED_CLIENT_ID_42"` |

### Decision

Install a minimal `NSMenu` at launch: an app menu (AppKit always treats the
first item as such) carrying Quit, and an Edit menu with Undo/Redo/Cut/Copy/
Paste/Select All. `LSUIElement` still means no menu bar is ever *displayed* —
the titles are never seen, and the menu exists only to carry key equivalents.
This also gives Tempo a ⌘Q for the first time, which it had no way to offer
before.

Right-click → Paste in the field worked all along (the field editor supplies
its own contextual menu), which is why this looked like a field problem rather
than a menu problem.

---

## 026 — Only offer playlists that can actually be added to (amends 003)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

Adding the current song showed a warning triangle and nothing else.

### Root cause

`GET /me/playlists` returns **followed** playlists alongside owned ones, and
decision 003's picker listed all of them and defaulted to the first row. Spotify
answers **403 Forbidden** to a POST against someone else's non-collaborative
playlist, and `add()` discarded the status entirely — `return http.statusCode ==
200 || http.statusCode == 201` — so every distinct failure collapsed into one
mute glyph.

Diagnosed against the live account with read-only calls (no POST, so nothing was
added, and the token was passed to `curl` through a 0600 config file rather than
argv, and never printed): `/me` and `/me/playlists` both returned 200 — auth was
never the problem — and of **48 playlists, the first was owned by another
user**. The default selection could not have worked.

### Decisions

1. **Filter to writable playlists**: keep an item only when
   `owner.id == currentUserID || collaborative == true`. Offering a playlist
   that can never accept a track is a lying signal (UI Principle #4), and it
   poisoned the *default* selection specifically. Verified against the real
   response: 48 → 17 offered, default becomes the user's own first playlist.
   `currentUserID` comes from one cached `GET /me`, cleared on disconnect.
2. **Report the actual reason.** `lastAddError` carries a sentence the user can
   act on — 403 → "it isn't yours and isn't collaborative", 401 → reconnect,
   404 → playlist gone, 429 → rate-limited, otherwise Spotify's own
   `error.message` plus the status. Shown under the row and as the triangle's
   tooltip, and the failure state now lingers 6s rather than 2s so it can be
   read. Agent Guideline #11: state what failed, not that something failed.
3. **Reject local files early**: AppleScript reports them as `spotify:local:…`,
   which the Web API cannot add at all, so that gets its own message instead of
   a confusing 400.
4. **Re-point a stale selection** when the filtered list changes, so a removed
   playlist can't sit there failing on every press.

### Note

Nothing here was an auth problem, which is why "reconnect Spotify" would have
been the wrong instinct — the session was valid the whole time with ~55 minutes
of headroom left.

---

## 027 — Playlist search belongs in Settings, not the notch panel

**Date:** 2026-08-20 · **Status:** Accepted

### The constraint

Searching means typing, and the notch panel's `canBecomeKey` is hard-`false`
(decision 006) — it can never receive a keystroke.

### Was that relaxable?

Tested rather than assumed. A `.nonactivatingPanel` with `canBecomeKey`
flipped to true, made key while Finder was frontmost:

```
frontmost before makeKey = Finder
panel.isKeyWindow        = true
field can take typing    = true
frontmost after makeKey  = Finder
=> stole the foreground? = false
```

So an in-panel search field *was* technically viable — the panel can take
keystrokes without stealing the foreground app, exactly as Spotlight does. It
would still mean that while the field is open the user's typing goes to Tempo
rather than the app they're looking at, and it would turn decision 006's
invariant into a conditional. Presented with that trade, the user chose to keep
the panel non-key.

### Decision

Search lives in **Settings ▸ Music**, which is an ordinary focusable window:

- a search field filtering the writable playlists by **substring**, not prefix
  (so "worship" finds "Sunday Worship Set" — the thing menu type-select can't
  do), plus a Refresh button;
- tick the playlists to offer in the notch; the notch picker then shows only
  those, in the order they were picked, starting on the first;
- **ticking nothing means everything is offered**, so add-to-playlist still
  works for someone who never opens Settings.

Stored as `Preferences.favoritePlaylistIDs` in UserDefaults — display
preference, not credential.

### Note

`offered` builds its lookup with `Dictionary(_:uniquingKeysWith:)` rather than
`uniqueKeysWithValues:`, which traps on a duplicate key: Spotify's paginated
`/me/playlists` can repeat an entry if the underlying list shifts between page
fetches, and a trap there would crash the notch panel.

---

## 028 — Expanded header: centred title over the transport row (amends 019)

**Date:** 2026-08-20 · **Status:** Accepted

Requested layout change. The cover grows 56 → **72pt**, chosen so cover +
controls fill the content width and the cover's height matches the column
beside it (title + artist + a 28pt control row ≈ 72pt).

Title and artist are centred above the transport row, which spreads across the
full remaining width with equal spacers — so the middle button (play/pause)
lands on the column's centre line, directly under the title.

**Addendum 4 (same day) — the picker's hover decoration has to live on the
`Menu`, not in its `label:`.** With `.background`/`.overlay` written inside the
label closure the hover state produced no visible change. Moving them onto the
`Menu` itself fixes it; verified by having the app render its own view to a
bitmap and sample the picker's rect, which then tracked the hover state exactly
(0.9326 → 0.9680 using deliberately opaque test colours).

Method note: that measurement was wrong three times before it was right — the
sample region was mis-placed, then `bitmapImageRepForCachingDisplay` was found
to return a **pixel**-sized rep so point coordinates sampled at half scale on a
Retina display (landing on the album art, which is why an opaque red background
read the same as an 8% white one), then a whole-area average was used where only
a 1.5pt border changes. Each correction reversed the conclusion. A probe that
cannot distinguish red from white is not measuring what it claims to.

**Addendum 3 (same day) — picker hover matches the transport buttons.** The
picker's highlight now uses `NotchButtonStyle`'s own values (`hoverFill`,
`hoverStroke`, `hoverAnimation`, promoted to shared statics) plus an outline on
hover, so the two controls speak the same language. A `ButtonStyle` cannot reach
a `Menu`, so the picker has to mirror the constants rather than adopt the style;
sharing them keeps the two from drifting. It keeps a faint resting plate (0.08)
that the buttons don't have, because unlike them it has no glyph to mark it —
that was the fix in addendum 1.

**Addendum 2 (same day) — playlist row moved into the header column, cover
auto-sized.** The add-to-playlist row now sits inside the right-hand column,
under the transport controls, rather than as its own row across the panel. That
makes the column taller, so the cover is no longer a fixed 72pt: it tracks the
column's *measured* height (`headerColumnHeight`, the same GeometryReader
pattern the panel already uses for its own height), clamped to 72–116pt. The
column's height depends on font metrics and on which rows are showing, which is
not something to hard-code — measured live at 106pt, so the cover is 106.
The clamp's upper bound exists because the add-failure message is a transient
extra line inside that column and shouldn't balloon the cover; the resize rides
the same spring as the rest of the panel. Picker padding also went to 13×10pt
with a 34pt minimum height.

**Addendum (same day) — the playlist picker was nearly unclickable.** Its
`Menu` used a bare `Text` label, so its hit region was the width of the rendered
characters and no taller, with no background or indicator to show it was a
control at all. It now draws a full-width plate: 10×7pt padding, a 30pt minimum
height (HIG target, decision 014), a rounded fill that brightens on hover, an
explicit up/down chevron, and `.contentShape` so the whole plate takes the
click rather than the glyphs. This also closes the open question logged in
`NEXT_STEPS.md` about the `Menu` having no hover affordance — a `ButtonStyle`
can't reach a `Menu`, but the label can carry the affordance itself.

The gear moved out of the header row into an `.overlay(alignment: .topTrailing)`
on the panel content. As a member of the row it consumed width on one side
only, which pulled the "centred" title off the play button; as an overlay it
costs no layout width. The title keeps *symmetric* horizontal padding so it
stays centred while still clearing the gear.

---

## 029 — A visible rim on the expanded panel (amends 010)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** Decision 010's Liquid Glass panel had no edge at all. Against a
bright or busy window behind it the `glassEffect` body has low contrast with its
surroundings, so the panel's outline was hard to read and it stopped looking
like a discrete surface. Request was a more noticeable border that still reads
as glass, not as a drawn box.

**Implementation.** `borderLayer` in `ContentView.swift`, two strokes of
`NotchShape`:

- a 1.2pt stroke filled with a vertical white gradient (0.55 → 0.16 → 0.38), so
  the shoulders and base catch light while the waist stays dim — how a real
  glass edge lights, rather than a uniform hairline;
- under it a 3pt stroke at 0.14 white, blurred 2.5pt, which reads as the
  thickness of the material and keeps the rim visible over light backdrops
  without raising the crisp stroke's opacity.

**Two constraints that shaped it:**

1. **Overlay after `clipShape`, not inside it.** A stroke drawn inside the
   clipped glass group is centred on the path, so the clip eats its outer half
   and halves the effective width. `.overlay(borderLayer)` sits outside the
   clip and draws at full width.
2. **Masked off across the top band.** The panel's first `stripHeight` points
   are deliberately blended to black so the panel merges with the notch pill
   (010, UI Principle #6). An outline through that band would draw a lit edge
   across the seam and make the panel read as a box hanging off the notch. The
   mask is a point-exact `VStack` — clear for `stripHeight`, a 24pt ramp, then
   opaque — matching the black gradient's own extent rather than a percentage.

The layer is `allowsHitTesting(false)`; it exists only while
`displayedExpanded`, so the collapsed pill is untouched (still pure black, no
rim).

---

## 030 — The panel's material is a preference (amends 010)

**Date:** 2026-08-20 · **Status:** Accepted

**Context.** Requested after seeing the same control in Notchy/boringNotch:
let the user pick the Liquid Glass style rather than hardcoding one.

**What the API actually offers (verified, Agent Guideline #4).** Read from the
installed SDK's interface
(`MacOSX.sdk/…/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`, SDK
26.5 on macOS 26.6.1): `Glass` exposes exactly three variants — `.regular`,
`.clear`, `.identity` — plus `.tint(Color?)` and `.interactive(Bool)`. So
"pick a glass style" is a two-item menu unless the picker also covers
non-Apple materials. `.identity` is not offered: for a panel it means no
material at all, which reads as a rendering bug rather than a style.

**The four styles** (`PanelStyle` in `Preferences.swift`):

| Style | Draws | Note |
|---|---|---|
| Regular (default) | `glassEffect(.regular)` | unchanged from 010 |
| Clear | `glassEffect(.clear)` | + a 0.22 black scrim |
| Album tint | `glassEffect(.regular.tint(cover colour))` | falls back to plain regular with no artwork |
| Solid | `Color.black.opacity(0.93)` | opts out of glass; one slab with the notch |

**Clear glass needs the scrim.** `.clear` passes the backdrop through almost
intact, so white track titles over a bright window behind the notch are
unreadable — this matches Apple's own guidance that clear glass belongs over
media with a dimming layer. The scrim is applied only for that style; the
others already carry enough density.

**Album tint: weighted, not averaged.** A plain average of a cover comes out
grey-brown on most albums, because dark background and letterboxing outnumber
the coloured subject. `NSImage.dominantColor()` (AppState.swift) draws a 16×16
downscale, weights each pixel by its own saturation (with a 0.15 floor so an
entirely grey cover still yields grey), then floors the result to 0.5
saturation / 0.6 brightness — below that a glass tint is invisible. It is
recomputed in `AppState.artwork`'s `didSet`, i.e. once per cover change, not
per frame. The tint is applied at 0.55 alpha; `.tint(nil)` is defined as "no
tint", so the no-artwork case needs no separate branch.

**Below macOS 26** there is no `glassEffect`, so the three glass styles degrade
to the nearest `Material` (`.ultraThinMaterial` for clear, `.regularMaterial`
otherwise). The picker still works and still visibly changes the panel; it just
isn't Liquid Glass. `.solid` is identical on every version.

**Persistence** is the raw string in `UserDefaults`, decoded with a
`?? .regular` fallback, so an unrecognised value from another build degrades
instead of failing.

**Unchanged:** the collapsed pill. Every style leaves it pure black — it has to
merge with the physical notch (UI Principle #6), which is not a stylistic
choice. The rim from 029 is drawn for all four styles.

---

## 031 — Liquid Glass paints no alpha, so clicks fell through it (amends 010)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

Clicks on the expanded panel's **body** reached the app behind. Clicks on the
album art, the usage graphs, the agent lights and the gear did not — reported
precisely that way by the user, which is what made this findable.

### Root cause

macOS routes a click on a **non-opaque** window by the alpha in that window's
backing store: fully transparent pixels pass the click to the window beneath.
Decision 010's expanded background is `Color.clear.glassEffect(…)` — Liquid
Glass is a *compositor* effect that samples what is behind the window and paints
essentially no alpha of its own. So the panel's glass body was, to the window
server, a hole.

Everything that worked was a real pixel: the artwork bitmap, the sparkline
paths, text, and the black top gradient. Everything that leaked was bare glass.

The decisive evidence was an absence — with hit-testing instrumented, the
leaking clicks produced **no `hitTest` call at all**:

```
outside-click monitor: onPanel=true -> ignored     <- monitor saw the click
                                                   <- but no hitTest, no sendEvent
```

`NotchHostingView.hitTest` was never consulted, and when called directly at
those same points it answered "hit" every time. The panel was willing to take
the click; it was never offered it. That is a window-server routing decision,
which is what pointed at alpha rather than at any code in this project.

### Fix

Paint a `shape.fill(Color.black.opacity(0.05))` substrate beneath the glass in
the expanded branch of `backgroundShape`. Measured threshold:

| substrate alpha | bare-glass click |
|---|---|
| 0.0 | passes through |
| 0.02 | captured |
| 0.10 | captured |

0.05 is margin against 8-bit rounding and is imperceptible over the glass.
Verified afterwards at four bare-glass points spread across the panel — all
delivered.

### Notes

- The collapsed pill was never affected: it is `Color.black`, fully opaque.
- This is why decision 032 and 033 each fixed something real without fixing the
  reported symptom — the click never reached the code either of them changed.
- Method note: two rounds of these measurements were wasted because the harness
  grepped stderr while the instrumentation wrote to a file, so *every* trial
  reported failure — including the 0.02 substrate that in fact worked. A test
  that can only produce one answer is worse than no test; check that a harness
  can report success before trusting a failure.


---

## 032 — Clicking anything in the panel pins it (amends 011)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

Clicking inside the expanded panel could still collapse it. Only an outside
click was supposed to.

### Root cause

Decision 011's pin was a SwiftUI `.onTapGesture` on the content container. A
`Button` or a `Menu` consumes the tap before any gesture on the container sees
it, so clicking a *control* never set `isExpanded`. The panel therefore stayed
merely hover-expanded, and the next hover-out collapsed it. The playlist picker
made this sharp: opening its menu moves the pointer onto the menu's own window,
hover-out fires, and the panel collapsed out from under the menu the user had
just opened.

### Decision

Pin in `NotchPanel.sendEvent(_:)` — the window's own entry point for every
event routed to it, reached before any view can swallow the mouse-down.

Gated on `contentView?.hitTest(event.locationInWindow) != nil`, which is the
same live-geometry region decision 012 uses for passthrough, so a click on the
transparent part of the window is still meant for the app behind and pins
nothing.

The gear still closes the panel: it pins on mouse-down here, then its action
runs on mouse-up and wins. The `.onTapGesture` stays as a backstop for plain
clicks, the path already known to work.

### Verification

`sendEvent` was driven directly with synthesized mouse-downs at both kinds of
location:

```
start: displayedExpanded=true isExpanded=false
after click on transparent region: isExpanded=false  (want false)
after click on the panel body:     isExpanded=true   (want true)
```

Note on method: an earlier attempt used `NSEvent.addLocalMonitorForEvents` with
an `event.window === self` check, tested by posting clicks with
`CGEvent.postToPid`. The monitor fired, but the injected event carried
`window=nil` — window association happens during real event routing, not for
directly posted events — so that check could not be verified and, worse, its
correctness depended on a field the test could not exercise. `sendEvent` needs
no window check at all, which is why it replaced the monitor.

---

## 033 — A non-activating app's own clicks reach its global monitor (completes 032)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

After 032, clicking inside the expanded panel *still* closed it.

### Root cause

`NSEvent.addGlobalMonitorForEvents` skips events delivered to the **active**
app. This panel is deliberately non-activating (decision 006), so Tempo is never
the active app — and its own panel's clicks therefore arrive at its own global
monitor. Every click on the panel counted as a click *outside* it.

Caught by instrumenting all three state-changing paths and driving a real
session-level click at the panel:

```
HOVER true (isExpanded=false)
SENDEVENT mouseDown loc=(68.0, 180.0) hit=true displayedExpanded=true
SENDEVENT -> pinned isExpanded=true          <- 032's pin worked
HOVER false (isExpanded=true)                <- correctly stayed open
GLOBAL monitor fired -> collapsing           <- then this undid it
```

This predates 032. Decision 011's pin was a tap gesture, which fires on
mouse-**up**, *after* this monitor's mouse-**down** — so it silently re-pinned
what the monitor had just cleared, and the defect stayed hidden. Moving the pin
to `sendEvent` (mouse-down) removed the accidental cover and exposed it.

### Fix

The monitor converts the cursor position into window coordinates and ignores
the click when it lands on the drawn panel:

```swift
let point = self.convertPoint(fromScreen: NSEvent.mouseLocation)
guard self.contentView?.hitTest(point) == nil else { return }
```

Same live-geometry hit region already used for passthrough (012) and the pin
(032) — one definition of "on the panel", three uses.

### Verification

Real clicks posted at the panel and then well outside it:

```
SENDEVENT -> pinned isExpanded=true
HOVER false (isExpanded=true)                        <- inside click: stays open
GLOBAL monitor fired: onPanel=false -> COLLAPSING    <- outside click
FINAL isExpanded=false isHovered=false               <- closed
```

### Lesson

Two rounds of plausible reasoning about this (a local monitor's `event.window`,
then `sendEvent`) each fixed something real and neither fixed the reported
symptom, because the actual culprit was a third path nobody had instrumented.
Logging every path that can mutate the state found it in one run.

---

## 034 — The hover-expand dwell is a setting, not a constant (amends 011)

**Date:** 2026-08-20 · **Status:** Accepted

### Symptom

The haptic tick on expansion was felt only occasionally — "sometimes I feel it
but most times I cannot."

### What was ruled out first

Three plausible causes, each eliminated against this machine rather than
assumed (Agent Guideline #4):

- **Hardware/settings.** Mac14,15 (M2 Air) has a Force Touch trackpad;
  `ActuateDetents = 1` and `ForceSuppressed = 0`, so haptics are enabled.
- **Pattern too weak.** `.alignment` is the subtlest of the three feedback
  patterns, so a harness fired `.generic`, `.alignment` and `.levelChange`
  three times each for comparison. The user reported all three feel the same —
  so the pattern is not the variable, and swapping it would have been a
  no-op fix.
- **Actuation from a non-frontmost app.** The notch panel is deliberately
  non-activating (decision 006), so Tempo is never the active app. The same
  harness runs as a non-frontmost process and its ticks *were* felt, so
  background actuation works.
- **Wrong thread.** A `Task` in `handleHover` performs the tick, and AppKit
  haptics off the main thread would be unreliable. A forced recompile under
  `-strict-concurrency=complete` produced zero warnings, so the closure is
  MainActor-isolated and the tick is already on the main thread.

### Root cause

Timing, as the user diagnosed. The tick fires when the expansion actually
triggers, which is `hoverExpandDelay` after the pointer arrives. At 250ms it
was firing into a trackpad the finger had usually already left.

### The geometry that sizes the trade-off

The dwell exists to stop a pointer merely crossing the notch from flickering
the panel open. Measured against the real pill on this machine — 271 x 33pt
(185pt notch + 43pt wings), top-centre of a 1710pt screen:

| Crossing | Time inside the pill | Filtered by |
|---|---|---|
| Vertical (up to the menu bar and past) — the common accident | 13–40ms at any normal speed | any dwell >= ~50ms |
| Fast horizontal flick along the top band | ~108ms at 2500pt/s | 120ms, not 60ms |
| Slow horizontal travel along the menu bar | 180–340ms at 800–1500pt/s | **none of these values, 250ms included** |

The last row is the important one: the dwell never protected against the case
it looks like it protects against. So the range between 0 and ~120ms costs far
less than the original 250ms implied.

### Options considered

| Option | Pros | Cons |
|---|---|---|
| Stronger haptic pattern | One-line change | Ruled out by measurement — all three patterns feel identical here |
| Fire the tick at hover-in instead of at expansion | Always lands while the finger is down | The tick would no longer mean "it opened" — a lying signal (UI Principle #4) |
| Pick a shorter constant | Simplest | The right value is a matter of feel, and one number cannot be argued to be right |
| **A setting (chosen)** | The user lands on their own number; the trade-off is stated in the UI | One more preference to maintain |

### Decision

`hoverExpandDelayMS` in `Preferences` (UserDefaults), 0–400ms in 10ms steps,
default **60ms**, exposed as a slider in Settings ▸ General ▸ Interaction.
`ContentView.hoverExpandDelay` became a computed property reading it, so a
change applies on the next hover with no restart. Clamped on read as well as
write: a hand-edited defaults value outside the range would otherwise make the
notch unopenable.

The collapse grace (100ms) stays a constant — it is not on the haptic path and
nothing was reported about it.

### Consequences

- The stated default drops from 250ms to 60ms, so the panel opens noticeably
  sooner out of the box. Per the table, the only protection given up is against
  a fast horizontal flick along the top 33pt band.
- 0 is a legitimate setting (open on arrival), which makes the tick land
  inside the trackpad contact the user's own pointer move just made.

---

## 035 — Agent lights are buttons: click a light, land in that session

**Date:** 2026-08-20 · **Status:** Accepted · **Amends:** 005

**Context.** Decision 005 made Tempo a read-only display layer over
AgentStatus's status files: the lights showed *which* sessions needed
attention, but a light was inert. Reaching the session it named meant leaving
the notch and hunting for the right terminal tab or IDE window — the one thing
a light is supposed to save you. AgentStatus's bar has solved this already
(`focus_session`), so the question was how much of that to bring across, not
whether to.

### What was ported

AgentStatus's macOS routing, in `Sources/tempo/Services/SessionFocusService.swift`,
keyed on the status file's `ide` field:

| `ide` | Route |
|---|---|
| `cli` | tty → the terminal that owns the session. Terminal.app is matched tab-precisely by tty; Ghostty by the session's Claude title (its dictionary publishes no tty or pid); any other emulator gets its **exact process instance** fronted, not `open -a <name>` |
| `cli`, no tty | a detached background agent: focus the Ghostty surface it is already attached in, if one exists |
| `vscode`, unknown | AX raise of the window titled after the workspace root (~0.2s, current Space only) **and** the `code` CLI, which covers the cross-Space / full-screen case the raise cannot see |
| `cursor` | AX raise + `open -a Cursor` — never the Cursor CLI, which opens a *new* agent instead of focusing (AgentStatus #047) |
| `claude-desktop` | `open -a Claude`; it scripts no conversation selection |

The workspace root comes from Claude Code's own IDE lock files
(`~/.claude/ide/*.lock`), so a session that `cd`'d into a subfolder still
resolves to the window that has its root open.

### What was deliberately not ported

| AgentStatus does | Tempo does | Why |
|---|---|---|
| Writes `~/.claude/status/focus-request.json` so its VS Code extension focuses the exact session **tab** | Focuses the VS Code **window** only | Agent Guideline #3 — Tempo may not write anywhere under `~/.claude/status/**`. That relay belongs to AgentStatus, which owns the signal layer and ships the extension that reads it |
| Runs `claude attach` in a new Ghostty/Terminal window for a detached background agent | Focuses an already-attached surface, otherwise does nothing | Tempo is a display layer (005). Launching terminals and Claude sessions is not something a notch panel should do behind a light |
| Asks Claude Code (`cli_facts`) whether a session is interactive or background | Infers it from the controlling terminal (`ps -o tty=`) | The fallback AgentStatus itself uses when that query fails. Tempo has no path that spawns anything, so the failure mode the query exists to prevent (a redundant attach) cannot occur here |
| Presses the session's row in Cursor's tray menu via the Accessibility API | Raises Cursor's window | ~200 lines of AX code for per-conversation precision, and it needs its own Accessibility grant. The window is the honest 80% |

### Fields read

`parseSession` now also reads `cwd`, `ide` and `pid` — the three fields the
routing needs. They are held in `AgentSession` and never displayed, logged, or
written anywhere (Agent Guideline #5). The `task`/`detail` prompt excerpts are
still never decoded.

One further exception to #5 is taken knowingly: matching a Ghostty surface
requires Claude Code's own session title, which lives only in the session
transcript (`~/.claude/projects/*/<id>.jsonl`, `ai-title` records). The
transcript is opened only on a click, only that one string is taken out of it,
nothing is stored, and the string is already on screen in the tab it names.
Files over 16MB are skipped rather than read on the click path.

### Verification (Agent Guideline #4)

Run against this machine, not assumed:

- **Status schema** — a live session file carries `cwd`, `ide:"cli"` and `pid`
  exactly as documented.
- **Ancestry walk** — `claude`(3999) → `-/bin/zsh` → `/usr/bin/login` →
  `/Applications/Ghostty.app/Contents/MacOS/ghostty`, so the emulator is found
  4 generations up.
- **Ghostty title match** — 3 surfaces open, exactly 1 whose title *ends with*
  this session's `ai-title`: the strong match is unambiguous, no weak matches.
- **End to end** — with Finder frontmost, `SessionFocusService.focus(session)`
  compiled into a probe brought Ghostty forward. Repeated with a session id
  that has no transcript (so no title): still landed in Ghostty, via the
  exact-process fallback — the untitled case degrades instead of dying.
- **Window raise** — the AX raise script (whose process name is now an argv
  variable rather than an interpolated string, so a quote in a folder name
  cannot break it) returned `ok` and raised a titled Finder window.
- **Not verified:** the VS Code and Cursor routes. Both apps are installed but
  neither was running a Claude session, and `~/.claude/ide` held no lock files,
  so `workspaceRoot` fell back to `cwd` untested.

### Consequences

- Every AppleScript/`ps` call runs on a detached task; the click returns to the
  main actor immediately, so the panel's collapse animation never waits on a
  ~1s VS Code CLI boot.
- The AX raise needs the Accessibility grant. Without it the raise silently
  no-ops and the click still works through the CLI / `open` fallbacks — slower
  for editors, and for a terminal session it degrades to app-level focus.
- Clicking a light collapses the panel (`ContentView.focusSession`). Any click
  on the panel pins it open (032), which would otherwise leave the pinned panel
  hanging over the window the click just fronted.
- A click on a VS Code session lands in the workspace window, not the Claude
  tab inside it. If tab precision is wanted later, the only clean route is
  AgentStatus writing the relay on Tempo's behalf — Tempo asking AgentStatus,
  not Tempo writing into AgentStatus's directory.

---

## 036 — The notch cannot be shown on the lock screen (rejected)

**Date:** 2026-08-21 · **Status:** **Rejected** — implemented, measured, reverted the same day

### Context

Asked for: the notch bar visible "even when I am logged out." Three readings,
far apart in cost:

1. **After a logout** — the pill returns when you log back in or switch users
   back. (Already true: the panel is at `.statusBar` and reappears by itself.)
2. **On the lock screen** — drawn while the screen is locked, in your session.
3. **At the login window** — drawn before anyone logs in.

(3) was ruled out first: it needs a root `LoginWindow` `LaunchAgent` in
`/Library/LaunchAgents`, and in that session there is no user home — no Spotify
to AppleScript, no `~/.claude/status/sessions`, no `UserDefaults` — so the pill
would draw empty. It is also nearly moot on this machine: **FileVault is on**
(`fdesetup isactive` → true), so the screen at boot is the pre-boot unlock,
which runs before macOS and cannot host a third-party process, and unlocking it
logs straight in.

That left (2), which is what this decision tried and what does not work.

### What was built

- `ScreenLockService` — lock state from `loginwindow`'s
  `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications,
  reconciled against `CGSessionCopyCurrentDictionary()` on start / wake /
  session-activation so a missed edge self-corrects.
- `NotchPanel` swapping its level between `.statusBar` (25) unlocked and
  `CGShieldingWindowLevel() + 1` locked, with `orderFrontRegardless()`.
- An empty hit region and a disabled hover handler while locked, so the locked
  pill could not be clicked or expanded.
- A `showOnLockScreen` preference, on by default.

All of it worked. None of it was visible.

### Measurement (Agent Guideline #4)

macOS 26.6.1 (25G76), Apple silicon, FileVault on.

- **The level swap fires correctly, both edges.** Polled twice a second across
  a real lock/unlock: `CGWindowListCopyWindowInfo` reported Tempo's panel at
  `layer = 2147483629` the moment the screen locked and back at `layer = 25`
  on unlock, frame intact at 405 x 280.
- **The panel is ordered above the lock screen and is "on screen".** While
  locked, the on-screen window list contained
  `loginwindow@2004`, `loginwindow@2001`, `Tempo@2147483629` — so
  `loginwindow`'s actual lock-screen windows live at **2001 and 2004**, not at
  the 2147483628 shield constant, and Tempo was above both with
  `kCGWindowIsOnscreen = true` throughout.
- **And it still could not be seen.** A separate probe put four opaque,
  labelled, full-colour 600x60 strips on screen at levels **1000, 2002, 2005
  and 2147483629** simultaneously — bracketing `loginwindow`'s windows from
  below, between, just above, and far above. Locked, **none of the four was
  visible.**

The last point is the decisive one, and it is why "above the shield" was the
wrong mental model. macOS does not draw the lock screen as a very high window
in the user's session that other windows can be ordered above; it composites
the lock screen in a separate secure context that simply does not include
user-session windows. Window level is not the variable. There is no value of
it that works.

Note what this means for evidence: `kCGWindowIsOnscreen`, window levels and
on-screen list membership all describe the *window server's* bookkeeping, and
every one of them said the pill was there. None of them describes what the
locked display actually composites. Only a human looking at a locked screen
settled it — this is exactly the case Agent Guideline #4 is about, and the
first round of "verification" here proved ordering and mistook it for pixels.

### Decision

Rejected. Every change listed above was reverted; `NotchWindow.swift`,
`AppDelegate.swift` and `Preferences.swift` are byte-identical to their
pre-036 state and `ScreenLockService.swift` is deleted. Nothing about the lock
screen remains in the code, because a lock-awareness layer whose only purpose
was a presentation that cannot happen is dead weight that reads as a working
feature.

### What is actually available

- **macOS's own Now Playing on the lock screen** is system-owned and already
  fed by Spotify directly. Tempo cannot add to it or restyle it; there is no
  third-party lock-screen widget API on macOS the way there is on iOS.
- If a locked-Mac glance at agent state is ever wanted, the only sanctioned
  surfaces are system-mediated ones — a notification, or the Now Playing /
  Control Center furniture — not a window Tempo draws.

### Consequences

- The pill behaves as it always did: visible unlocked, hidden by the lock
  screen, back by itself on unlock. No user-visible change from this decision.
- Anyone who reaches for `CGShieldingWindowLevel()` for a "show it over the
  lock screen" feature should read this entry first. The constant exists, the
  API accepts it, the window server reports success, and the pixels never
  appear.


---

## 037 — Notch geometry follows the displays, instead of being frozen at launch

**Date:** 2026-08-22 · **Status:** Accepted

**Context.** With an external monitor attached, the panel drew in the wrong
place. `NotchGeometry` resolved the target screen, the notch size, and the
screen frame into `static let`s — evaluated once, on first access, and never
again. `NotchPanel` then computed its window frame from that snapshot inside
`init` and nothing ever observed
`NSApplication.didChangeScreenParametersNotification`.

Every one of those inputs changes when the display layout changes:

- `NSScreen.screens` gains and loses the built-in screen when the lid opens or
  shuts, and gains and loses the external when it is plugged in.
- A screen's `frame` is expressed in a global space whose origin is the
  bottom-left of the *primary* display, so attaching a monitor or moving a
  display in System Settings ▸ Displays re-origins the screen Tempo targets —
  usually to a negative `y`.
- `safeAreaInsets` / `auxiliaryTopLeftArea` are what the real notch size is
  read from, and they only exist while the notched screen is actually present.

So after any of those events the window sat at coordinates describing a layout
that no longer existed, and — because `panelWidth` and `pillWidth` derive from
the notch width — potentially at the wrong size for the screen it was on.
`ContentView` had the same defect one layer up: it copied all ten geometry
values into stored `let`s, freezing its interior layout at the launch-time
notch.

### Which screen the panel targets

| Option | Verdict |
|---|---|
| **Always the built-in notched screen** | **Chosen.** Tempo's whole premise is hugging the physical notch; a pill floating at the top of a monitor that has no notch is a different product. The panel stays on the MacBook display no matter which screen is main |
| Follow the main (menu-bar) display | Rejected — it would move the pill onto a notchless external whenever the user made that display primary, which is the common docked arrangement |
| Follow the display under the pointer | Rejected — the panel would hop between screens mid-work, against UI Principle #1 (glanceable, one fixed place to look) |

Resolution order is now: the first screen with `safeAreaInsets.top > 0`, else
`NSScreen.screens.first`, else `NSScreen.main`. The middle term is new and
matters in clamshell: `screens[0]` is documented to be the menu-bar display,
whereas `NSScreen.main` is the screen holding the *key window* — and Tempo is
non-activating, so it deliberately never has one, which makes `main` the wrong
question to ask. When no notched screen exists the previous behaviour is kept
unchanged: the synthetic 200×32 strip, centred on that screen and flush with
its top edge.

### Implementation

- `NotchGeometry`: the derived values became computed `static var`s over a
  `refresh()`-updated `targetScreen` / `raw` pair, plus a `windowFrame` that is
  the single definition of where the window belongs. `refresh()` returns
  whether anything moved, compared **by value** — macOS vends fresh `NSScreen`
  instances per reconfiguration, so an identity check reports a change for each
  of the several notifications one reconfiguration emits.
- `NotchPanel` observes `didChangeScreenParametersNotification`, calls
  `applyGeometry()` (refresh → `setFrame` → bump `state.screenGeneration`),
  and re-checks once 750ms later: macOS posts the notification while the
  reconfiguration is still settling, and on lid-open the built-in screen can
  already be back in `screens` with `safeAreaInsets` still reading zero, which
  would otherwise leave the notchless fallback on a notched display.
- The hit-region closure reads `NotchGeometry` at call time instead of
  capturing widths at `init`; captured bounds would have clamped the click
  region to the old screen's notch (decision 012's passthrough contract fails
  open, not closed, so this would have silently swallowed clicks meant for
  other apps).
- `ContentView`'s ten geometry `let`s became computed `var`s. `AppState`
  gained `screenGeneration`, whose only job is to publish a change so SwiftUI
  re-evaluates the body and re-reads them.

### Consequences

- Plugging in a monitor, unplugging it, shutting or opening the lid, or
  rearranging displays now moves and re-sizes the panel onto the current notch
  within one notification (plus the 750ms settle re-check).
- No polling: the whole mechanism is one notification observer, and
  `applyGeometry()` returns immediately when nothing actually changed.
- Not covered: display *mirroring* is treated as whatever `NSScreen` reports
  for the resulting configuration, and a notched external display (none exist)
  would be targeted over the built-in if one ever shipped.


## 038 — The media UI hides when nothing has played for a minute (amends 013)

**Date:** 2026-08-22
**Status:** Accepted

### Context

The collapsed pill always carried media: album artwork in the left wing, the
visualizer in the right one, and — expanded — the cover, transport row and
playlist picker. "Always" included the cases where there is nothing to show.
Pause Spotify and walk away, or quit it entirely, and the pill still parked a
grey placeholder square and five frozen bars beside the notch indefinitely,
43pt of black wing on each side of the hardware notch — clearly visible over a
light desktop, and carrying no signal at all. That is the opposite of UI
Principle #1: the collapsed strip is supposed to carry exactly the signals that
are live.

### Decision

Media is shown while something is playing, and for **60 seconds** after
playback stops. After that the whole media UI leaves: both pill wings (cover
and visualizer) and the expanded panel's now-playing header (cover, title,
transport buttons, playlist row). The collapsed pill becomes exactly
`notchWidth` — the hardware notch, nothing beside it. Anything playing brings
it all back immediately.

| Trigger | Considered | Verdict |
| --- | --- | --- |
| Hide the instant playback pauses | Simplest rule | Rejected — a pause to take a call or an app switch is a gap in listening, not the end of it; the pill would flicker its wings away and back several times an hour |
| Hide only when Spotify quits | No timer at all | Rejected — the common case is Spotify left running and paused for hours, which is exactly the state complained about |
| Hide after a timeout (chosen) | One one-shot timer | Accepted — covers paused-and-forgotten, Spotify quit, and Spotify never launched with the same rule |

The timeout is a constant (`MusicService.mediaIdleTimeout`), not a setting: no
one asked for it to be adjustable, and unlike the hover dwell (decision 034)
its exact value has no effect on whether an interaction lands.

### Implementation

- `AppState.isMediaActive`, owned by `MusicService`. It starts **false**, so a
  Tempo launched while Spotify is paused or not running never shows the media
  UI at all — nothing has played.
- `MusicService.updateMediaActivity(playing:)` is called from `setNowPlaying`
  *after* its equality guard, which is load-bearing: the 30s reconciliation
  poll re-reports the same paused track, and re-arming the countdown on each
  of those would mean it never fires.
- Every non-playing case arms the same timer, including `nowPlaying == nil`.
  A momentary AppleScript failure also produces nil, so hiding immediately on
  nil would flicker the pill; the 60s delay absorbs that.
- `ContentView`: `collapsedWidth` is `pillWidth` or `notchWidth`, both wings
  and the now-playing header sit behind `showsMedia`, and the flip animates on
  the same spring as expand/collapse so the wings retract rather than vanish.
- `NotchHitRegion`'s collapsed floor drops from `pillWidth` to `notchWidth`
  (NotchWindow.swift). Left at the pill, the panel would have gone on claiming
  the two wings' 43pt after they had visibly retracted — right beside the menu
  bar's own items, and decision 012's passthrough contract fails *open*, so it
  would have silently swallowed clicks meant for other apps.

### Consequences

- At rest with no music, Tempo is invisible: the pill is exactly the notch.
- Hover still works there and still opens the panel (the notch itself has
  always been part of the hover surface), so the usage graphs, the agent
  lights and the Settings gear stay reachable with no media on screen.
- The expanded panel is shorter in this state; it is already content-sized, so
  the height simply re-measures.
- A paused track's cover survives short pauses — the state is "nothing has
  played for a minute", not "not playing right now".


## 039 — The visualizer must follow the output device's mute and volume (amends 016)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Reported: with the Mac muted, the bars danced as if music were playing while
nothing could be heard. Reproduced on this machine with the tap instrumented
(`TEMPO_DEBUG_VIZ=1`, below), Spotify playing into a muted BuiltInSpeakerDevice:

```
tap live=1 silentFor=0.01 tapBuffer=0 rawPeak=0.633 spotifyRunningOutput=1
```

`rawPeak` is the level the FFT is seeing: full-amplitude audio, on a silent
Mac. The cause is inherent to the mechanism chosen in decision 016 — a
`CATapDescription(stereoMixdownOfProcesses:)` tap captures the *process's*
rendered stream, which is upstream of the device's volume and mute. The
system's mute state is simply not in that signal path, so the visualizer had
no way to know the user could hear nothing. Decision 016 was verified against
"is this Spotify's audio?" and never against "can it be heard?".

The same run confirms what is **not** broken: pausing drops the tap to
`live=0, rawPeak=0.000` within 1.5s, and with an output-only default device
(`subDeviceInputBuffers=0`) the tap sits at buffer 0, so decision 021's
microphone hazard is not involved.

### Decision

Motion means audible sound (UI Principle #5). The bars settle whenever the
current default output device is **muted or at zero volume**, exactly as they
do for a pause, and pick the music back up the moment it becomes audible
again. Playing-but-inaudible is treated as not playing *for the visualizer
only* — the cover, transport controls and the decision-038 idle timer still
follow Spotify's real play state, because the music genuinely is playing.

| Considered | Verdict |
| --- | --- |
| Scale the bar heights by the output volume | Rejected — the levels are already normalised in dB, and the useful reading of the bars is "what the music is doing", not "how loud your speakers are". Only the audible/inaudible edge is a lie worth fixing |
| Gate on `isCapturing` alone | Rejected — that only silences *reactive* mode; the fallback sine animation keys off `isPlaying` and would have gone on dancing, the same lie in a different mode |
| Leave it: the music really is playing | Rejected — the strip's whole job is to be readable at a glance, and motion that contradicts silence is exactly the stale/lying signal UI Principle #4 forbids |

### Implementation

- `AudioTapService.outputAudible` (published): not muted
  (`kAudioDevicePropertyMute`) and not at zero volume
  (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`), read on the
  default output device. **Fails open** — a device exposing neither property
  reads as audible, so an unusual device degrades to the old behaviour rather
  than to a permanently dead visualizer.
- `tick()` splits the old `live` in two: `hasSignal` (audio is arriving) still
  drives the TCC silent-denial heuristic — a muted Mac is not a denied tap —
  while `live = hasSignal && outputAudible` drives the bars.
- `VisualizerView.animating` = `isPlaying && tap.outputAudible`, replacing
  `isPlaying` in the timeline's paused condition, the transition `task(id:)`
  and `playEnergy`, so the fallback settles on mute too.
- Listener-driven, not polled: the pump stops once the bars are flat, so a
  poll inside `tick()` would never see the un-mute. Mute and volume listeners
  are attached to the current default output device (re-attached when that
  device changes, alongside the existing aggregate rebuild), and becoming
  audible explicitly restarts the pump — the audio thread only signals on a
  silence→sound edge, and muting creates no such edge: the tap goes on
  delivering the same nonzero audio throughout.
- `DebugLog.swift` / `tempoDebug(_:)`: stderr diagnostics, silent unless
  `TEMPO_DEBUG_VIZ=1` is set (`open --env TEMPO_DEBUG_VIZ=1 --stderr <file>
  dist/Tempo.app`). Kept, not scaffolding-deleted: the tap only runs inside
  the signed bundle, so there is no other way to see what it is receiving, and
  the remaining unverified audio case (a dual-scope meeting device, decision
  021) will need exactly this. It logs booleans and one peak magnitude — never
  a sample, never session content.

### Verified

Live on this machine, Spotify playing throughout, tap instrumented: muted →
`live=0` (`rawPeak=0.501`); unmuted with volume still 0 → `live=0`
(`rawPeak=0.525`); volume 4 → `live=1` (`rawPeak=0.583`), i.e. the pump
restarted from the volume listener with no silence→sound edge; muted again →
`live=0`.

### Consequences

- Mute the Mac and the notch goes still, cover and controls unchanged.
- Zero volume counts as muted, since it is equally inaudible.
- Volume/mute on a *device other than* the default output (e.g. per-app
  volume in another app) is not modelled; nothing in the signal path exposes
  it.

---

## 040 — Agent rows carry the session's task, and stack vertically (amends 005)

**Date:** 2026-08-22
**Status:** Accepted

### Context

The agent lights were a horizontal strip of pills, each a dot plus the
session's `label` — which AgentStatus sets to the session's folder name. That
is enough to *count* sessions but not to *pick* one: two Claude Code sessions
open on the same repo produce two pills reading `Tempo`, `Tempo`, and clicking
one is a coin flip. Decision 035 made these pills clickable, which made the
ambiguity actually cost something.

The status files already carry the disambiguating text. Read from a live file
on this machine:

```json
{"state":"running","cwd":"…/Tempo","ide":"cli","pid":36309,"label":"Tempo",
 "updated_at":1787411901,
 "task":"lets give the agent status part of the tempo a bit more detail: a short desc…",
 "detail":"$ ls ~/.claude/status/sessions/ 2>/dev/null | head -20; …"}
```

### Options

**Which text.**

| Field | What it is | Verdict |
|---|---|---|
| `task` | The user's prompt for the current turn, truncated by the writer to ~150 chars. Stable for the length of a turn. | **Chosen** — it answers "which session is this?", which is the actual question. |
| `detail` | The current tool call (`$ ls …`). | Rejected — rewrites every few seconds; at a glance it says the session is busy, not which session it is, and a description that flickers competes with the lights (UI Principle #1). |
| Both (`task` shown, `detail` on hover) | — | Rejected — surfaces a second prompt-excerpt field for a hover almost nobody performs. |

**Layout.**

| Option | Verdict |
|---|---|
| Vertical list, one full-width row per session | **Chosen** — the description gets the panel's full width, so it is actually readable, and rows scan top-to-bottom like a list of sessions. |
| Two-line pills, horizontal scroll | Rejected — a pill wide enough for a description is ~170pt, so ~2 fit; the rest are off-screen behind a scroll. |
| Single-line pills, horizontal scroll | Rejected — the description is the first thing truncated, which defeats the change. |

### Decision

Each session renders as a full-width row — dot, folder label, task description
— stacked vertically, three visible before the list scrolls.

### Guideline #5 is narrowed, deliberately

Agent Guideline #5 says to render only what the lights need, and this service
previously refused to decode `task`/`detail` at all. Showing `task` reverses
that specific refusal at the user's explicit request. The rest of the
guideline stands and is now the load-bearing part:

- `task` is **rendered and nowhere else** — never logged (including under
  `TEMPO_DEBUG_VIZ`), never written to disk, never sent over the network.
- `detail` stays undecoded.
- `AgentStatusService.summarize` flattens the excerpt to one line (whitespace
  runs collapse), drops the writer's trailing `…`, and caps it at 120
  characters, so one long prompt cannot dictate the panel's width.

### Implementation

- `AgentSession.task: String` — empty when the file has no `task`, in which
  case the row is dot + label, as before.
- `AgentLightsView` becomes a vertical `ScrollView` of rows, height pinned to
  `min(sessions.count, 3)` rows at 28pt + 2pt spacing, so a busy machine
  cannot grow the expanded panel without bound.
- The label column is floored at 56pt and capped at 108pt: the floor keeps
  descriptions from jagging left and right down the list, the cap stops one
  long folder name from eating the row.
- Rows keep `NotchButtonStyle`, so they hover, press and hit-target exactly
  like the transport buttons (decision 035's reasoning, unchanged) — except
  for its scale. `NotchButtonStyle` gains `scales: Bool = true`; the rows pass
  `false`. The style's 1.06 hover growth was built for a 28pt icon button; on
  a full-width row it pushed the capsule ~10pt past the panel's 26pt content
  inset at each end and the notch shape clipped the ends off. Fill and hover
  outline carry the state instead, which is the normal treatment for a list
  row. Every other control keeps the scale by default.
- The tooltip becomes `Go to <label> — <task>`, giving the untruncated text to
  anyone who wants it.

### Consequences

- Two sessions in one repo are now distinguishable at a glance.
- The expanded panel is taller when sessions exist: one row (~28pt) where the
  old strip was one row, but up to three rows plus scrolling.
- A prompt excerpt is visible on screen whenever the panel is expanded. On a
  shared or screen-shared machine that is new exposure; the agent-lights
  toggle in Settings remains the way to turn the whole surface off.

---

## 041 — A scrubbable progress bar, driven by an extrapolated anchor (amends 015)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Asked for: a progress bar for the current track, with the ability to jump to
any point in the song. Everything needed was verified live against the
installed Spotify (1.2.95.453) before any code was written (Agent Guideline
#4):

| Probe | Result |
| --- | --- |
| `player position` | Seconds, as a real — `57.064998626709` |
| `duration of current track` | **Milliseconds** — `206440` for a 3:26 track, despite the `.sdef` documenting "The length of the track in seconds" |
| `set player position to 90` | Works, exact, and restores |
| Notification `Playback Position` / `Duration` | Present in every `PlaybackStateChanged` payload — seconds and milliseconds respectively, matching AppleScript to the millisecond |
| Does a seek post a notification? | **No.** Driving `set player position` with a listener attached produced nothing at all |
| Cost of one position round-trip | 16.6ms median on the main thread; 33ms median / 54ms p90 off it, nearly all of it blocked on Spotify's reply |

Two of those shape the whole design. The duration unit is a trap the `.sdef`
actively misleads about. And because a seek is silent, a purely event-driven
service — which is what decision 015 made this — cannot learn that the user
scrubbed inside Spotify's own window.

### Decision

**The position is an anchor, not a ticking value.** `AppState.progress` holds
a position plus the instant it was true; the view extrapolates from it on a
4Hz `TimelineView` clock. A playing track therefore costs redraws of one small
subtree and *zero* state publishes, and a paused one installs no timer at all
(the anchor reads the same at every date). This keeps decision 016's measured
zero-timer rest state intact.

**Reconciliation runs at 1Hz, only while the panel is open.** The progress bar
is the only thing that needs a fresh position and it exists only while the
panel is expanded, so that is exactly when the poll runs — plus one immediate
fetch on open. Collapsed or paused, nothing polls.

**Seeks are optimistic, then settle.** The anchor jumps to the target before
the AppleScript runs, so the bar stays where the user let go instead of
snapping back for the round-trip. Seek fires on release (and on a plain
click), never continuously.

| Considered | Verdict |
| --- | --- |
| Poll `player position` at 1Hz whenever music plays | Rejected — reinstates the steady-state AppleScript poll decision 015 deliberately removed, to feed a bar nobody is looking at |
| Only reconcile on open + the existing 30s safety poll | Rejected — a scrub in Spotify with the panel pinned open would leave the bar lying for up to 30s (UI Principle #4) |
| Publish a ticking position from the service | Rejected — a publish per frame re-evaluates the whole panel; the anchor gives the same motion for one small subtree's redraws |
| Seek live while dragging | Rejected — an AppleScript round-trip per movement, and Spotify audibly re-buffers on each one |
| Put the bar in the column beside the cover | Rejected — full width below the header gives ~1.7pt per second to aim at instead of ~1.1 |
| Show the bar in the collapsed pill | Rejected — the pill carries exactly three signals (UI Principle #1) |

### The bug this uncovered: `set player position` returns before it takes effect

The first implementation reconciled immediately after the seek command
returned. Intermittently — roughly one run in five — the bar jumped back to
the *pre-seek* position and stayed there. Traced through the real code path:

```
4236ms setProgress -> 58.40      <- seek issued, optimistic anchor
4266ms fetch STARTED             <- after `set player position` returned
4292ms fetch RETURNED 100.0      <- Spotify STILL reports the old position
4292ms setProgress -> 100.00     <- the seek is undone on screen
```

Spotify's player had not moved when the command returned, and kept reporting
the old position for up to ~56ms afterwards. An earlier attempt to measure
this latency in isolation reported a reassuring 13–23ms and missed the bug
entirely — each probe read itself costs 15–25ms, so the measurement could not
resolve what it was measuring. Instrumenting the service made the race vanish
(the logging perturbed the timing), which is why it was chased by tracing
rather than by adding print statements.

Fixed with a 0.5s settle window: reconciliation results that land inside it
are discarded, and the seek's own reconcile is scheduled after it. A long
window costs no accuracy — the optimistic anchor is exactly where the user
asked to go — it only delays discovering a *refused* seek. Verified by 8
consecutive seeks with the poll armed: max anchor deviation 0.00s, 0 failures.

### Implementation

- `PlaybackProgress` (AppState.swift): `duration` / `anchorPosition` /
  `anchorDate` / `isPlaying`, with `position(at:)` and `fraction(at:)`.
  Milliseconds are converted to seconds at each parse site so nothing
  downstream carries the `.sdef`'s trap.
- `MusicService`: the existing combined fetch now returns
  `{textFields, player position, duration}` as an AppleEvent **list** — the
  text parse is unchanged, and the two numbers arrive as typed numbers rather
  than `as string`, so parsing cannot depend on the system's decimal
  separator. Same one round-trip as before.
- `MusicService.seek(to:)`: optimistic anchor, `seekSettleUntil`, and a
  position literal formatted against `en_US_POSIX` (a comma-decimal locale
  would emit `set player position to 58,4` — two arguments, not one).
- `MusicService.setPanelOpen(_:)`: called from `ContentView.onChange(of:
  displayedExpanded)`; arms the 1Hz timer only when the panel is open *and*
  something is playing.
- `runPositionFetch()` builds a fresh `NSAppleScript` per call — it runs on
  the concurrent executor, which is not a fixed thread, and `NSAppleScript`
  is not thread-safe. Measured to cost the same as a cached instance.
- `PlaybackProgressView`: elapsed / bar / remaining, 4pt track with a 20pt
  hit band, 9pt knob that grows on hover, `DragGesture(minimumDistance: 0)`
  so a plain click also seeks. Time labels are monospaced-digit at a width
  derived from the *duration* (36pt, or 52pt past an hour) so the bar's ends
  never shift as the clock runs — at a flat 36pt an hour-long track rendered
  as `1:02:…`, caught by rendering the view and reading the pixels.

### Verification

Driven against live Spotify through the real compiled sources, and the user's
playback restored to its exact original position and state afterwards:

- Duration converted ms → s (206440 → 206.44); anchor populated on `start()`
- Seek: optimistic anchor exact, Spotify's real position matches, and the
  post-settle reconcile agrees — 8/8 seeks with 0.00s deviation
- Poll arms only when it should: 5 re-anchors in 4s with the panel open and
  playing; **1** (i.e. none) with the panel closed; **1** paused with the
  panel open
- Extrapolation: paused is time-invariant; playing advances 1:1; clamped at
  the track end; zero duration yields 0 rather than dividing by zero
- Seek while playing with the poll armed: no jitter, drawn position
  self-consistent to 0.000
- View rendered offscreen at 353pt: knob travel exactly `(265 − 9) × 2` px
  with uniform steps, and it stays inside the track at both 0:00 and the end

---

## 042 — An agent light in the collapsed pill (amends 005, 038)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Until now the agent signal existed only in the expanded panel: hover the notch,
and a list of sessions appears. That inverts the point of the feature. UI
Principle #1 names three collapsed-strip signals — what's playing, that it's
playing, and *which sessions need attention* — and the third one was the only
one you had to ask for. A blocked session sitting behind an un-hovered notch is
a signal the user never receives.

The constraint is width. The collapsed pill is exactly `notch + two wings`, and
both wings are already full (artwork left, visualizer right) at
`max(contentSquare, VisualizerView.naturalWidth)`. There is no spare room; any
agent light has to add geometry.

### Decision

**A light slot outboard of the visualizer, mirrored by an empty slot on the
leading side.** The strip is centred in the window, so a slot added on the
trailing side alone walks the notch gap half a slot off the physical notch —
which UI Principle #6 does not allow. The mirror costs a few points of black
either side of the pill and keeps the gap registered to the hardware.

**Three modes, chosen in Settings ▸ Modules ▸ Agent light.** The right amount
of detail here is a matter of taste, not of correctness:

| Mode | What it draws |
| --- | --- |
| Off | Nothing; agent state stays in the expanded panel |
| Summary dot *(default)* | One dot, the most urgent state across every session |
| One dot per session | Up to three dots in the panel's own priority order |

**The summary is a priority rollup, not an average:** red (any error) > orange
(any blocked) > pulsing white (any just finished) > green (any running) > dim
grey (all idle). Blocked and just-finished pulse; nothing else moves, so motion
in the pill only ever means "this wants you" or "this is done" (UI Principle
#5). Idle draws at 0.4 opacity — it is the state nobody acts on, and at full
strength a grey dot competes with the visualizer beside it.

**"Just finished" is derived, not read.** AgentStatus writes no such state; a
finished session is simply `idle`, indistinguishable from one that has been
idle for an hour. But "it's done" is exactly what a glance at the notch is
looking for, so `AgentStatusService` remembers each session's previous state
across polls and flags a `running -> idle` transition for 20 seconds. The first
poll after launch records without flagging, so sessions that were already idle
at launch never read as just-finished.

**The light is not tied to `showsMedia`.** Decision 038 retracts the pill to the
bare notch when nothing has played recently. Agent state is the one signal worth
widening an otherwise bare notch for — the alternative is that the feature
disappears exactly when the user is heads-down in a terminal and not playing
music, which is when it matters most.

| Considered | Verdict |
| --- | --- |
| Put the dot inside the existing right wing, left of the bars | Rejected — no pill growth, but the bars shift inward and the wing is already sized to its content |
| Grow only the trailing side | Rejected — moves the notch gap off the hardware notch (UI Principle #6) |
| Show the light only for blocked/error | Rejected as the default — the pill would change width whenever a session blocks; "everything is fine" is also worth a glance. Reachable by choosing Off plus the expanded list |
| Reuse `showAgentLights` for both views | Rejected — one switch cannot express "dot in the pill, no list in the panel" or the reverse; they are separate surfaces |
| Pulse red for errors too | Rejected — parity with the expanded rows, which pulse blocked only; static red is already the loudest thing in the pill |
| Show the label/task in the pill | Rejected — that is the expanded panel's job (decision 040); the pill carries signals, not text |

### Implementation

- `AgentSession.justFinished` and `AgentSummary` (AppState.swift). The summary
  is a computed rollup over `sessions`, so republishing sessions is what
  redraws the dot — including when a just-finished window expires.
- `AgentStatusService.markFinished(_:now:)`: `lastStates` and `finishedAt`
  dictionaries, both in-memory, both pruned to live session ids each poll.
  They hold the state word and a timestamp — nothing from a status file's
  `task`/`detail`/`cwd` (Agent Guideline #5).
- `CollapsedAgentLight` (Views/CollapsedAgentLight.swift), with a static
  `width(sessions:mode:)` so the pill can lay out around it without measuring.
  The dot re-arms its pulse on `onChange(of: summary)` as well as `onAppear` —
  unlike the expanded rows, it is long-lived and changes state in place.
- `ContentView`: `lightWidth` / `lightSlotWidth` / `lightLeadingGap`, the
  mirrored `Color.clear` slot, and `.animation(expandAnimation, value:
  lightSlotWidth)` so a session starting or ending springs the pill instead of
  snapping it.
- `Preferences.collapsedAgentLight` (`CollapsedAgentLightMode`), defaulting to
  `.summary`, persisted by raw value with a fallback to the default.

Verified against the live `~/.claude/status/sessions/` on this machine: two
session files (one `idle`, one `running`) plus six `.subagents` directories,
which the existing `pathExtension == "json"` filter already skips.

---

## 043 — The lights reconcile against Claude Code's own view (amends 005)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Reported live: a session was interrupted mid-turn; AgentStatus's lightbar went
grey and Tempo's light stayed green.

Decision 005 made Tempo a read-only consumer of AgentStatus's status files, on
the understanding that those files *are* the signal. They are not. They are a
record of **hook events**, and the hook's only route to `idle` is a `Stop`
event — so a turn that ends any other way never produces one, and the file goes
on saying `"state":"running"` indefinitely. Interrupting a turn with Ctrl-C or
Esc is the everyday case.

AgentStatus solved this in its own backend (its decisions 067, 063, 084): every
poll, it reconciles each light against what Claude Code says about the same
session. That work happens **in memory and is never written back** — its
`list_sessions` returns a corrected state to its own frontend and leaves the
file alone. So none of it was ever visible to Tempo, which read the raw file and
drew exactly what the hook last wrote. The lights were not "missing a feature"
from AgentStatus; they were reading a source that structurally cannot answer
these two questions.

### Decision

**Tempo asks the same two questions AgentStatus asks, from the same two
sources, and reconciles before drawing.** Both are read-only, and neither is
under `~/.claude/status/**`, so Agent Guideline #3 is untouched — this is the
005 contract extended to two more files, not a write path.

| Source | What it answers |
| --- | --- |
| `~/.claude/sessions/<pid>.json` | `status` — what Claude Code says the session is doing right now — plus `statusUpdatedAt` (ms) and `kind` |
| `claude agents --json` | For a background job: `kind`, live `status`, the job's own `state`, and (via `~/.claude/jobs/<id>/state.json`) the `needs` behind a `blocked` |

Two rules follow, ported from AgentStatus:

1. **An interrupted turn greys its own light.** A `running` light whose session
   Claude Code reports as `idle` becomes `idle`.
2. **A background job's light says what Claude Code says.** An `idle` light on a
   `--bg` job reads `running` while the job is busy and `blocked` while it is
   waiting on an answer. Only an `idle` light is touched, so anything the hook
   actually observed — `running`, `blocked`, `error` — always wins.

**Three guards keep this from ever inventing a light** (UI Principle #4: a wrong
signal is worse than no signal):

- **Positive evidence only.** The record must actually say `idle`. An absent
  status (every Claude Desktop session reports none), an unreadable record, a
  session Claude Code does not list, or a failed query all change nothing — the
  failure mode is the pre-043 behaviour, not a wrong light.
- **The answer must be newer than the light.** `statusUpdatedAt` has to fall in a
  **strictly later second** than the hook event the light was drawn from, so
  anything the hook observed wins over a stale answer. Strictly later, not merely
  greater: the hook stamps whole seconds, so within one shared second the two
  clocks cannot be ordered and the tie goes to the hook. It costs up to a second
  of latency to be certain a light is never grey at the start of a turn.
- **Background jobs are excluded from rule 1.** Claude Code reports a `--bg` job
  `idle` between turns while it is alive and working, so `idle` does not mean
  there what it means for an interactive session. What a background light shows
  is decided entirely by rule 2. `shell` is likewise not treated as idle: it is
  plainly not a running turn, but what produces it is unconfirmed, and a guess is
  not worth a lying light.

**An interrupted turn is not a finished one.** Decision 042 derives a "just
finished" light from a `running -> idle` transition. A light greyed by rule 1
makes exactly that transition, so without care every cancelled turn would raise
the pulsing white dot that means *there is output worth reading* — on a turn that
produced none, in a session the user is by definition already looking at. Lights
greyed by reconciliation are therefore excluded from `justFinished`; lights that
went idle because their own hook said so are not.

**The subprocess only runs when it could matter.** `claude agents --json` costs
~0.3s of CPU per call (measured on this machine), and at AgentStatus's 10-second
cadence that is roughly 3% of a core, forever — against a measured idle cost of
0.3% for the whole app. But it is only ever consulted about background jobs, and
every interactive session says `"kind":"interactive"` in its own record, which is
a free file read. So the query is skipped entirely unless some CLI light's record
says otherwise, is unrecognised, or is missing. On a machine running only
interactive sessions — the common case, and this machine — the subprocess is
never spawned at all and the poll measures 0.02s of CPU per 12 seconds.

| Considered | Verdict |
| --- | --- |
| Leave it: Tempo shows what the file says | Rejected — the file cannot say the turn ended, so the light lies for as long as the session lives. UI Principle #4 |
| Have AgentStatus persist its reconciled state into the status file | Rejected by the user in favour of this. It would fix every consumer at once, but makes Tempo's lights depend on AgentStatus *running*, not merely on its hooks being installed — and the reconciliation is cheap to do first-hand |
| Infer the interrupt ourselves (silence timer on a green light) | Rejected — a long build or a big file write is silent too, and greying that is exactly the lying light the guards exist to prevent. Ask; don't infer |
| Port AgentStatus's prune rules (dead pid, closed window, gone cwd, quit Cursor) too | Not needed for this fix: those rules *delete* the status file, so Tempo already inherits them while AgentStatus is running. Tempo's own backstop stays the 2-hour staleness drop. Left as a known gap for a machine where AgentStatus is installed but not running |
| Port AgentStatus's Cursor reconciliation (#048/#052) | Deferred — a separate source (Cursor's SQLite store), a separate failure mode, and no reported symptom. Tempo still draws a Cursor subagent as its own light, which AgentStatus folds into its parent |

### Implementation

All in `Sources/tempo/Services/AgentStatusService.swift`:

- `ClaudeRecord` / `claudeRecords()` — the `~/.claude/sessions` read, keyed by
  session id. No cache: `status` changes on every turn boundary, and three small
  files per poll is the same shape of read the service already does.
- `ClaudeCLI` (file-scope) — `binary` resolved once (`which`, then AgentStatus's
  install candidates; a GUI app inherits almost no PATH), `facts()`, and
  `jobNeeds(_:)`. Runs off the main actor via `Task.detached`, behind
  `cliFactsTTL` (10s) and a single-flight flag, so the poll never waits on a
  subprocess beside the notch's animations. The query passes
  `AGENTSTATUS_IGNORE=1` for AgentStatus's benefit, not Tempo's: without it,
  AgentStatus's hooks write a status file for Tempo's own query process and
  Tempo puts a light on the bar it is only supposed to be reading.
- `turnEnded(_:lightUpdatedAt:)` and `bgLightState(_:)` — the two rules and their
  guards, each a pure function of what was read.
- `reconcile(_:records:)` — applies rule 2 then rule 1, and returns the ids it
  greyed; `markFinished(_:now:reconciledIdle:)` skips those when flagging
  "just finished".
- Nothing new is stored: `CliFact` and `ClaudeRecord` hold state words, a
  timestamp and a job's `needs`, and none of it is logged or written anywhere
  (Agent Guideline #5). The rendered `AgentSession` is unchanged, so no view moves.

### Verification

`scripts/test-agent-lights.sh` (re-runnable, self-cleaning, Agent Guideline
#8) compiles the **shipped** service file with only its two directory constants
and its `claude` lookup redirected at a temp fixture — nothing stubbed, nothing
under `~/.claude` touched — and drives the real poll through 15 checks: an
interrupted turn greys and does not read as just-finished; a clean finish greys
and does; a same-second answer, a `busy` answer, and a host that reports no
status all leave the light green; a background job reads green while busy, orange
while asking, and grey while idle at an empty prompt; the listing is queried when
a background job could be present and **not spawned at all** when only
interactive sessions exist.

Live on this machine, against the real files: schema confirmed on Claude Code
2.1.239/2.1.240 (`status`, `statusUpdatedAt`, `kind` present on every session
record; `claude agents --json` listing all three live sessions), a running light
whose session reports `busy` correctly stays green, and 12 seconds of polling
costs 0.02s of CPU with no subprocess spawned. The background-job fields
(`kind: background`, the job `state`, and `needs`) could not be re-measured today
— no `--bg` job was running — and are carried over from AgentStatus's decisions
063 and 084, which measured them live.

---

## 044 — A white unread light in the expanded panel (amends 005, 042)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Decision 042 gave the *collapsed pill* a white "just finished" dot. The expanded
panel never got one: a session that had just finished a turn drew the same grey
dot as one that had been idle since breakfast. The panel is the surface with the
room to say which is which, and it was the one saying less.

AgentStatus has had this since its decisions 014/050, and calls it the **unread**
light: a finished turn shows a steady white light until you click it. The signal
it reads is not a transition — it is the status file's own `detail` field. The
`Stop` hook writes the turn's wrap-up message there, and `SessionStart` forces it
empty, so *idle with a non-empty `detail`* means "this turn ended and there is
output to review", durably and across restarts. Decision 042 claimed AgentStatus
"writes no such state" and derived one from a transition instead; that was true
of the *state* word and wrong about the file, which carries the finish plainly.

### Decision

**The expanded row draws a steady white light for a finished turn the user has
not acknowledged, and the click that goes to the session clears it.** Going to a
session *is* reviewing it, so no second affordance is invented — the row already
had exactly one click, and it now means both things. The acknowledgement is keyed
to the finish it acknowledged (session id + that `updated_at`), so the next turn
to finish lights the row again on its own.

**Steady, not pulsing.** Motion in Tempo means "this wants you" (UI Principle
#5): blocked pulses because it is stopped waiting on the user. A finished turn is
not waiting on anything — white against grey is enough separation to see, and a
row that pulsed until clicked would be nagging for something that has already
gone right. This matches AgentStatus's own "steady white attention light".

**Only `detail`'s emptiness is read** — never the message. `AgentSession` gains a
`hasOutput: Bool`, and the string is dropped at the parse. `detail` is a wrap-up
of the session's work and is exactly the kind of content Agent Guideline #5 keeps
out of Tempo; a Bool answers this question completely.

**An interrupted turn is never unread.** Decision 043 greys a light whose turn
Claude Code says is over, and the file's `detail` in that case is whatever the
last tool event wrote (`$ sleep 90`) — not a wrap-up. Left alone, every
interrupted turn would raise "there is output to review" over a cancelled tool
call, in a session the user is by definition already looking at. So the
reconciliation clears `hasOutput` along with the state, which is the same
correction AgentStatus makes when it greys one.

**The collapsed pill is left alone.** It now carries the more transient of the
two signals (042's 20-second "just finished") and the panel the more durable one,
and that is the right way round: an unread light that persists until clicked is
useful in a list you are reading, and would mean a pill that is almost never grey
— which is precisely what 042 rejected ("short enough that the pill is not
permanently claiming something finished"). Unifying them is a one-line change if
the split turns out to read badly.

| Considered | Verdict |
| --- | --- |
| Show 042's `justFinished` in the rows instead | Rejected — a 20-second window is the opposite of an unread light; expand the panel a minute later and the finish you missed is gone |
| A separate "mark as read" control on the row | Rejected — UI Principle #3, the panel is a surface, not a menu. The click that takes you to the session is the acknowledgement |
| Clear the light on a timer instead of a click | Rejected — same failure as above: the user is not always looking |
| Acknowledge by session id alone | Rejected — the row would then stay dark for every later finish too. Keying on `updated_at` makes the next finish re-light it |
| Pulse the white light | Rejected — motion means "act on this" (UI Principle #5); a finished turn is not blocked on anyone |
| Read `detail` for the row's text as well | Rejected — Agent Guideline #5. The row already carries `task` (decision 040), which is what tells sessions apart; the wrap-up message stays undecoded |
| Make the pill's summary unread-based too | Deferred — see above; not asked for, and it changes 042's observable behaviour (Agent Guideline #7) |

### Implementation

- `AgentSession.hasOutput` (whether `detail` was non-empty) and
  `AgentSession.unread` (that, and idle, and unacknowledged), both in
  `AppState.swift`.
- `AppState.acknowledgedFinish` — session id → the finish acknowledged — plus
  `acknowledgeFinish(_:)`, which also clears the light in `sessions` on the spot,
  and `pruneAcknowledgements(liveIDs:)`. In-memory, app-local, never written.
- `AgentStatusService.markUnread(_:)` derives `unread` each poll, next to
  `markFinished`; `parseSession` reads `detail`'s emptiness only; `reconcile`
  clears `hasOutput` on a 043 grey.
- `AgentLight.color` returns white when `session.unread` (before the state
  switch — a session cannot be both idle and blocked, so this only ever wins over
  grey), and the tooltip says the click marks it as seen.
- `ContentView.focusSession` calls `state.acknowledgeFinish(session)`.

### Verification

`scripts/test-agent-lights.sh` (renamed from `test-agent-reconcile.sh`, which
covered 043 alone) — 24 checks, all passing. For this decision: a finished turn
reads unread; a fresh idle with no wrap-up does not; a running session never
does; a background job reconciled off idle does not; an interrupted turn does not
even though its `detail` is non-empty; acknowledging clears the light immediately
*and* keeps it clear across the polls that follow; and the next finish lights it
again. Live against this machine's real files: the session that had finished a
turn reads unread, the one mid-turn does not.

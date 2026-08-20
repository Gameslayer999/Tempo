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

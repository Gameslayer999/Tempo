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

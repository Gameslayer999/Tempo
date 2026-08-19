# NEXT_STEPS.md — Living Build Queue

> Read this at the start of every session to pick up where the last one left off.
> Update it at the end of every session where anything changed (Agent Guideline #10).

---

## Current state

- **v1 feature set implemented and building clean (2026-08-19).** `swift build` (debug
  and release) exits 0 with zero warnings; the app runs as an accessory-policy process
  drawing a notch-hugging non-activating NSPanel (decisions 006/008). Implemented:
  - **Spotify now-playing + transport** (`Services/MusicService.swift`) — 1s AppleScript
    poll (compiled once, reused), guarded by `NSRunningApplication` so Spotify is never
    launched as a side effect; artwork downloaded off-main when the URL changes;
    play/pause/prev/next with an immediate re-poll after each command. Fetch script and
    `playpause` verified live against the real Spotify app (see decision 002 addendum,
    including the `st` variable-name gotcha).
  - **Visualizer** (`Views/VisualizerView.swift`) — 5 capsule bars, per-bar layered
    sine functions driven by `TimelineView(.animation)` (no timers); eases to
    motionless stubs over 0.35s when paused (decision 004).
  - **Add-to-playlist** (`Services/SpotifyWebAPI.swift`, `Views/PlaylistSection.swift`)
    — PKCE per decision 003: config + tokens in `~/Library/Application Support/Tempo/`
    (0600/0700), one-shot NWListener on 127.0.0.1:8888, rotating refresh tokens,
    playlist pagination capped at 200, compact picker + add-button row with transient
    success/failure feedback. Hides entirely when unconfigured. **The live OAuth
    round-trip is unverified** — no Client ID is configured on this machine yet.
  - **AgentStatus lights** (`Services/AgentStatusService.swift`,
    `Views/AgentLightsView.swift`) — read-only 2s poll of
    `~/.claude/status/sessions/*.json` (parsing verified against a live file), 2h
    staleness cutoff, attention-first sort, blocked lights pulse, unknown states render
    as hollow rings, feature hides when the directory is absent (decision 005).
- **Not yet verified by a human:** the panel's visual alignment with the physical
  notch, expand/collapse feel, click-through behavior, transport buttons end-to-end
  from the UI, and the full OAuth flow. Automated checks stop at "builds clean, runs,
  stays alive, AppleScript/status parsing verified at the shell level".

## Now

- [ ] **User verification pass** — run `.build/release/tempo`, approve the one-time
      Automation prompt (Tempo → Spotify), and check: strip hugs the notch; artwork +
      visualizer render; hover expands the Liquid Glass panel with a haptic tick,
      mouse-off collapses it, click pins it, click outside unpins (decision 011);
      the 0.15s hover-out debounce feels natural; controls work; agent lights match
      open sessions; clicks outside the strip pass through to other apps.
- [ ] **Check PlaylistSection / AgentLightsView contrast on glass** — the glass
      change added text shadows to ContentView's own controls only; the other two
      views' legibility over a light desktop is unverified.
- [ ] **Verify the OAuth flow live** — create the Spotify Developer app (README
      steps), add the Client ID to config.json, run Connect Spotify, add a song to a
      playlist. Fix whatever the first real round-trip surfaces.

## Next

- [ ] `.app` bundle script (Info.plist: `LSUIElement`, `NSAppleEventsUsageDescription`)
      so Tempo can be a login item and get stable TCC identity.
- [ ] Agent lights in the *collapsed* strip (tiny dots) — currently expanded-only.
- [ ] Settings surface (poll interval, show/hide lights, visualizer style).

## Later

- [ ] Apple Music support (AppleScript dictionary exists; artwork via `artworks` raw
      data instead of a URL).
- [ ] Real audio-reactive visualizer (Core Audio process tap) — deferred per
      decision 004.
- [ ] Self-sufficient agent-status signal layer (bundle a hook installer for machines
      without AgentStatus) — deferred per decision 005.
- [ ] Click a light → focus that session (port AgentStatus's focus logic).
- [ ] Calendar / battery / file-shelf modules (category table stakes, explicitly out
      of v1 scope).

## Decisions needed

- None currently open.

## Recently completed

- **2026-08-19** — Interaction model reworked (decision 011, revising 009): hover
  fully expands with a trackpad haptic tick, mouse-off collapses (0.15s debounce),
  click pins, click outside unpins; the 10×4pt hover-grow and its dead-zone
  constants removed.
- **2026-08-19** — Hover-grow on the collapsed strip (decision 009) and Liquid Glass
  on the expanded panel (decision 010), after checking boringNotch's hover source and
  Notchy's glass styling; `glassEffect` verified against the macOS 26.5 SDK with an
  `.ultraThinMaterial` fallback.
- **2026-08-19** — v1 features implemented in parallel (music service, visualizer,
  add-to-playlist, agent lights) against the scaffold's stub interfaces; one
  integration fix (actor isolation in `SpotifyWebAPI`'s NWListener callbacks); debug
  and release builds clean.
- **2026-08-19** — Scaffold: SwiftPM app shell, notch NSPanel with `hitTest`
  passthrough (decision 008), stubbed services, smoke-tested.
- **2026-08-19** — Project bootstrapped: docs carried over from AgentStatus and
  adapted, architecture decisions 001–007 logged, pushed to the private repo
  `Gameslayer999/Tempo`.

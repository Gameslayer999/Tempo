# NEXT_STEPS.md — Living Build Queue

> Read this at the start of every session to pick up where the last one left off.
> Update it at the end of every session where anything changed (Agent Guideline #10).

---

## Current state

- **Core-functionality rework landed (2026-08-20), decisions 012–018.** Debug and
  release builds exit 0; the app now runs primarily as a signed bundle
  (`scripts/make-app.sh` → `dist/Tempo.app` — required for audio capture). What
  changed this session:
  - **Click-fallthrough bug fixed** (decision 012): the hit region now tracks the
    live animating shape geometry instead of the expanded/collapsed flag, so a
    click on a still-visible control mid-collapse can no longer fall through to
    the window behind. Verified by driving the compiled sources through
    `hitTest` at every animation step. Root-cause note: stock
    `NSHostingView.hitTest` claims its whole bounds on macOS 26.6 — the custom
    override is load-bearing.
  - **Dynamic-Island pill** (013): collapsed width is now content-fit
    (notch + artwork wing + visualizer wing = 255pt on this machine, was 405),
    concave-top `NotchShape`, content-sized expanded panel (no more fixed-height
    overflow/dead glass).
  - **Motion/controls per boringNotch + HIG** (014): 0.25s hover dwell, 0.1s
    hover-out debounce, open spring (0.42/0.8), critically-damped close
    (0.45/1.0), Reduce Motion fades, 28pt hit targets, press states
    (`NotchButtonStyle`), semantic colors.
  - **Event-driven Spotify** (015): `PlaybackStateChanged` distributed
    notification (verified live; title-case `Player State`, no artwork key)
    replaces the 1s AppleScript poll; one AppleScript fetch per track change +
    30s reconciliation while Spotify runs.
  - **Real audio visualizer** (016): Core Audio per-process tap on Spotify,
    5-band vDSP FFT, 30Hz asymmetric-smoothed bars (bass center). Verified
    capturing real music via a signed harness. Falls back silently to the old
    playback-synced animation when unauthorized (bare binary always is — TCC
    denial is silent zeros) or on macOS <14.2. Zero redraws/timers at rest.
  - **Usage graph** (017): CPU + memory 1Hz sampling, 60-sample Path-based
    sparklines (never Canvas — ~93MB one-time Metal cost), fixed 0–100 scale.
  - **Packaging** (018): idempotent `scripts/make-app.sh`, ad-hoc signed (no
    Apple Development identity on this machine).
- **Measured performance:** idle/paused ≈ **0.3% CPU** (was 3–7% constantly —
  the old visualizer redrew at display refresh forever). While playing ≈ 4–8%
  (30Hz SwiftUI update churn; see "Now").
- **Not yet verified by a human:** pill/panel look and feel, hover dwell feel,
  click-to-pause reliability in real use, the reactive visualizer visually, the
  usage graph rendering, agent-light legibility on glass, OAuth flow (still no
  Client ID configured).

## Now

- [ ] **User verification pass** — run `scripts/make-app.sh`, `open dist/Tempo.app`,
      approve the two permission prompts (Automation → Spotify, System Audio
      Recording), then check: pill hugs the notch and is content-width; hover
      dwell feels right (0.25s); pause always takes the click (the original bug);
      bars genuinely follow the music; usage sparklines render; panel height fits
      its sections with none hidden/shown oddly; clicks beside/below the pill
      still reach other apps.
- [ ] **Visualizer render cost** — while playing, the 30Hz SwiftUI update path
      costs ~4–8% CPU (profiled: AttributeGraph/view churn, not DSP). If that
      reads high in real use: try `drawingGroup()` on the bar row, a 20Hz pump,
      or publishing only quantized level changes.
- [ ] **Self-signed "Tempo" certificate** for stable TCC identity across rebuilds
      (AgentStatus already uses this pattern on this machine — port it, script
      it). Until then rebuilds may re-prompt for Automation/audio.
- [ ] **Verify the OAuth flow live** — create the Spotify Developer app (README),
      add the Client ID, Connect Spotify, add a song to a playlist.

## Next

- [ ] Agent lights in the *collapsed* pill (tiny dots) — currently expanded-only.
- [ ] Playlist `Menu` has no hover affordance since `HoverScale` was replaced
      (`NotchButtonStyle` can't style a `Menu`) — decide whether it needs one.
- [ ] Settings surface (hover dwell, show/hide lights/usage, visualizer style).
- [ ] Login item via the bundled app.

## Later

- [ ] Apple Music support (AppleScript dictionary exists; artwork via `artworks`
      raw data instead of a URL).
- [ ] Network throughput in the usage row (Notchy shows it; `getifaddrs` deltas,
      filter `utun*`/`awdl*`/`bridge*`).
- [ ] Self-sufficient agent-status signal layer (bundle a hook installer for
      machines without AgentStatus) — deferred per decision 005.
- [ ] Click a light → focus that session (port AgentStatus's focus logic).
- [ ] Calendar / battery / file-shelf modules (category table stakes, out of v1).

## Decisions needed

- None currently open.

## Recently completed

- **2026-08-20** — Core-functionality rework (decisions 012–018): click-fallthrough
  fix via live-geometry hit region; Dynamic-Island pill + content-sized panel;
  boringNotch/HIG motion and control polish; event-driven Spotify (1s poll
  removed); real audio-reactive visualizer (Core Audio process tap, verified
  live, silent fallback); CPU+memory usage sparklines; `scripts/make-app.sh`
  bundle packaging. Idle CPU 3–7% → ~0.3%. Research inputs: boringNotch source
  dive, Apple HIG fetch, live tap probe, Notchy/iStat + Mach-API research.
- **2026-08-19** — Pin bug fixed (011 addendum); hover-scale on all interactive
  controls.
- **2026-08-19** — Interaction model reworked (decision 011, revising 009).
- **2026-08-19** — Hover-grow strip (009) + Liquid Glass expanded panel (010).
- **2026-08-19** — v1 features implemented (music service, visualizer,
  add-to-playlist, agent lights); debug and release builds clean.
- **2026-08-19** — Scaffold: SwiftPM app shell, notch NSPanel with `hitTest`
  passthrough (decision 008), stubbed services, smoke-tested.
- **2026-08-19** — Project bootstrapped: docs carried over from AgentStatus and
  adapted, architecture decisions 001–007 logged, pushed to the private repo
  `Gameslayer999/Tempo`.

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
- **Settings window landed (2026-08-20), decision 020.** A gear in the expanded
  panel's top-right corner opens a separate, ordinary `NSWindow` shaped like
  System Settings (sidebar + grouped forms): General (open at login), Music
  (Spotify Client ID field, Connect/Disconnect), Modules (visualizer, usage
  graphs, agent lights), About. Preferences in `UserDefaults`; the Client ID is
  written to `config.json` at 0600, so the README's hand-edit step is now
  optional. Verified at runtime that the window builds, centres, and becomes
  key (`activate(ignoringOtherApps: true)` is required for that — plain
  `activate()` leaves it visible but not key, and the Client ID field would
  take no keystrokes).
- **Not yet verified by a human:** pill/panel look and feel, hover dwell feel,
  click-to-pause reliability in real use, the reactive visualizer visually, the
  usage graph rendering, agent-light legibility on glass, OAuth flow (still no
  Client ID configured).

## Now

- [ ] **User verification pass** — run `scripts/make-app.sh`, `open dist/Tempo.app`,
      approve the two permission prompts (Automation → Spotify, System Audio
      Recording), then check: pill hugs the notch and is content-width; artwork
      and visualizer stay fully inside the black pill over a *light* desktop
      (decision 019); the cover flies into the expanded header rather than
      jumping or double-drawing; hover dwell feels right (0.25s); pause always
      takes the click (the original bug); bars genuinely follow the music; usage
      sparklines render; panel height fits its sections with none hidden/shown
      oddly; clicks beside/below the pill still reach other apps.
- [ ] **Confirm the visualizer fix in a meeting-style setup** (decision 021) —
      with a headset/virtual audio device as the default output, pause Spotify
      and talk: the bars must stay flat. Structurally verified, but not yet
      observed against a live dual-scope output device (this machine has none —
      its AirPods enumerate as separate input and output devices).
- [ ] **Verify the Settings window in use** — hover the notch, click the gear:
      the panel should collapse and Settings come forward *with keyboard focus*
      (click into the Client ID field and type). Check each Modules toggle takes
      effect immediately in the notch, and that switching the visualizer off
      leaves an empty right wing that doesn't look broken (decision 020 keeps
      the slot deliberately — see below).
- [ ] **Open-at-login round trip** — toggle it on from `dist/Tempo.app`, confirm
      the login item appears in System Settings ▸ General ▸ Login Items, and
      that it survives a reboot. Ad-hoc signing may make macOS re-ask for
      approval after each rebuild.
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
- [ ] The notch picker has no search (deliberate, decision 027). If choosing
      favourites in Settings turns out to be too indirect, the tested
      in-panel-search route is written up there.
- [ ] Collapsed pill with the visualizer switched off leaves an empty wing
      (decision 020 §7 keeps the slot so the hit region can't over-claim). If
      it looks wrong, make the pill content-fit — which means teaching
      `NotchPanel`'s hit-region clamp a narrower floor.
- [ ] Settings not yet covered: hover dwell, visualizer style, agent-light
      options. Panes exist; adding a control is now a one-file change.

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

<!-- resolved 2026-08-20, decision 022:
- **Fullscreen chrome reveal when hovering the notch.** The user wants the
  fullscreen title bar (close/expand buttons) to stay hidden when the pointer
  goes straight up into the notch, while still revealing everywhere else along
  the top edge. macOS exposes no way for an app to suppress that reveal for a
  region — it is cursor-position-driven by the WindowServer, and boringNotch has
  the same unsolved complaint (issue #1359). Options: (a) test whether raising
  the panel's window level so it covers the trigger strip suppresses it —
  cheap to try, unverified; (b) a `CGEventTap` clamping the cursor in the notch
  column — rejected on sight, it fights the user for input (Agent Guideline #3);
  (c) accept it and document. Awaiting the user's call. -->

## Recently completed

- **2026-08-20** — Hover-expand dwell is now a setting (decision 034): Settings
  ▸ General ▸ Interaction has a *Hover delay* slider, 0–400ms in 10ms steps,
  default 60ms (was a fixed 250ms), applied on the next hover with no restart.
  Fixes an intermittently-felt haptic tick — the tick fires when the expansion
  triggers, so at 250ms it usually fired into a trackpad the finger had already
  left. Pattern strength, background actuation and main-thread isolation were
  each measured and ruled out first. **Awaiting the user's final number** — the
  shipped default should be set to whatever they land on.

- **2026-08-20** — CPU and memory sparklines now fill the expanded panel's full
  content width (each roughly 2.5x the old fixed 80pt), with the row height
  unchanged at 22/24pt so the panel does not grow.

- **2026-08-20** — `DECISIONS.md` numbering repaired: two same-day sessions had
  each written a 029 and a 030. The click-handling pair became 032/033, section
  031 moved ahead of them so the body reads in order, the index was sorted, and
  the missing 024 index row was added. Index and sections now match one-to-one.

- **2026-08-20** — Playlist picker hover highlight (decision 028 addenda 3–4):
  shared highlight constants on `NotchButtonStyle` plus an outline on hover, and
  the decoration moved out of the `Menu`'s `label:` onto the `Menu` itself,
  which is why it had no visible effect before. Exact contrast still wants a
  human eye.

- **2026-08-20** — Clicks no longer fall through the expanded panel's glass
  (decision 031): macOS routes clicks on a non-opaque window by backing-store
  alpha, and Liquid Glass paints none, so the panel body was a hole while the
  artwork/graphs/text caught clicks normally. A 5% black substrate under the
  glass fixes it (measured: 0.0 leaks, 0.02 already captures).

- **2026-08-20** — Clicking inside the expanded panel no longer closes it
  (decision 033): the outside-click global monitor was firing for Tempo's *own*
  clicks, because a global monitor only skips events delivered to the **active**
  app and this panel is deliberately non-activating. It now ignores clicks that
  land on the drawn panel. Verified end-to-end with real posted clicks.

- **2026-08-20** — Clicking a control in the expanded panel now pins it
  (decision 032): the pin moved from a SwiftUI tap gesture — which `Button` and
  `Menu` swallow — to `NotchPanel.sendEvent`, gated on the same hit region used
  for passthrough. Fixes the panel collapsing out from under the playlist menu.

- **2026-08-20** — The expanded panel's material is now a preference (decision
  030): Settings ▸ General ▸ *Expanded panel* picks regular glass, clear glass
  (with a legibility scrim), album-tinted glass, or solid. Album tint samples
  the cover's dominant colour once per track change. The collapsed pill stays
  pure black in every style.

- **2026-08-20** — Add-to-playlist row moved beside the cover, under the
  transport controls; cover now auto-sizes to the measured column height
  (72–116pt clamp, 106pt as measured) instead of a fixed 72; picker padding
  increased to 13×10pt / 34pt tall (decision 028 addendum 2).

- **2026-08-20** — The expanded panel now has a visible glass rim (decision
  029): a gradient 1.2pt stroke plus a blurred 3pt under-stroke, overlaid
  outside the clip so it isn't halved, and masked off across the top band that
  blends to black for the notch seam. Collapsed pill unchanged.

- **2026-08-20** — Playlist picker is now a full-width plate with padding, a
  30pt minimum height, a chevron and a hover fill (decision 028 addendum). Its
  `Menu` previously had a bare `Text` label, so the clickable area was just the
  characters — hard to hit and with nothing marking it as a control. Also
  closes the logged open question about the `Menu` lacking a hover affordance.

- **2026-08-20** — Playlist search in Settings (decision 027): searchable,
  substring-matching list of writable playlists with tick-to-offer-in-the-notch;
  ticking none offers all. In-panel search was tested and shown viable (a
  non-activating panel takes keys without stealing the foreground) but declined
  to keep the panel non-key.
- **2026-08-20** — Expanded header relayout (decision 028): 72pt cover, title
  centred over the play/pause button, transport spread full width, gear moved
  to a corner overlay so it can't pull the title off-centre.

- **2026-08-20** — Add-to-playlist fixed (decision 026): the picker listed
  *followed* playlists too and defaulted to the first one, which on this
  account was someone else's — Spotify 403s that, and `add()` threw the status
  away, leaving a bare triangle. Now only owned/collaborative playlists are
  offered (48 → 17 on this account) and failures state Spotify's actual reason.

- **2026-08-20** — ⌘V (and ⌘C/⌘X/⌘A/⌘Z, plus ⌘Q) now work in the Settings
  window (decision 025): an accessory app has no main menu, and AppKit routes
  editing key equivalents through it, so the Client ID field silently refused
  paste. Verified both directions against the running app.

- **2026-08-20** — Visualizer no longer starts up looking like it's playing
  (decision 024): `.task(id:)` fires on *appear* as well as on change, and it
  stamped the transition start each time, freezing a paused launch at full bar
  height. Verified numerically against the view's own maths.
- **2026-08-20** — Guided Spotify setup + Settings Space fix (decision 023):
  the Music pane is now three steps with an Open Dashboard button and a
  copy-to-clipboard Redirect URI; the Settings window carries
  `.moveToActiveSpace` so it opens on whichever Space the user is on. Confirmed
  the developer app can't be designed away — Spotify's `.sdef` has no playlist
  support at all.

- **2026-08-20** — Fullscreen pill drop (decision 022) built, then **reverted
  the same day** at the user's request: the pill sits at the notch again and
  the detection path is gone. The drop was reported ineffective, but the app on
  screen was a process from before that day's builds, so it was never actually
  running — untested rather than disproved. Private SkyLight menu-bar overrides
  were probed (`SLSSetMenuBarVisibilityOverrideOnDisplay` and friends do exist)
  and rejected as system-wide unversioned API.
- **2026-08-20** — `scripts/make-app.sh` now quits *and relaunches* a running
  instance of the bundle it replaced (amends decision 018), so a rebuild can
  neither leave a stale build on screen nor take the notch off it. The stale
  instance cost three rebuilds' worth of misleading test results.

- **2026-08-20** — Visualizer mic-leak fix (decision 021): the DSP read
  `abl[0]` of the *aggregate's* input list, which is the output device's
  microphone whenever that device has one (verified: layout `[1, 2]` — mic
  first, tap second). It now resolves and reads the tap's own buffer. Explains
  bars moving with music stopped, and stops mic audio ever reaching the FFT.

- **2026-08-20** — Settings window (decision 020): gear in the expanded panel's
  top-right opens a separate focusable `NSWindow` with a System-Settings
  sidebar + grouped forms; `Preferences` (UserDefaults) for the module
  toggles, `SpotifyWebAPI.saveClientID`/`clearConfiguration`/`disconnect` for
  the Client ID and account, `SMAppService` open-at-login, and
  `SystemStatsService.stop()` so a hidden usage graph costs nothing.

- **2026-08-20** — Collapsed-pill spacing fix + expanded now-playing header
  (decision 019): wing content is now inset past `NotchShape`'s corner curves
  (artwork and visualizer no longer overhang the black fill on a light desktop;
  pill 255→271pt), and the album cover moves from the pill into the expanded
  panel via `matchedGeometryEffect`, sitting left of the transport controls.

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

# NEXT_STEPS.md — Living Build Queue

> Read this at the start of every session to pick up where the last one left off.
> Update it at the end of every session where anything changed (Agent Guideline #10).

---

## Current state

- **The close artifact on a notched Mac is fixed (2026-08-27),
  decision 082.** Decision 065 fixed the same-sounding "black fade out" on a
  notchless display and closed with "notched-Mac behaviour unchanged by
  construction" — which is exactly what left the built-in screen with a fade of
  its own. Recorded and read frame by frame: the black silhouette retracted
  correctly, but the expanded column (output chips, gear, CPU/memory readouts)
  and the glass both stayed at **full panel size** and faded over the desktop
  on the collapse spring, legible at t+0.16s through t+0.24s with no panel
  behind them. A removed SwiftUI subtree keeps the size it held and does not
  follow the frame inward. Content is now clipped to the retracting shape, and
  the rim light moved outside that clip so the stroke is not halved by it.
  Verified on screen before and after: the ghost ran t+0.04s to t+0.32s before,
  and after it every frame of the close is content inside the outline with the
  pill settling pure black. The open improved as a side effect — the column now
  unrolls out of the notch instead of appearing at full width inside a growing
  shape. Two curve changes were tried and reverted; `.animation(_:value:)` on
  the silhouette also scopes the geometry arriving from the frame above, which
  retracted the pill faster than the panel it backs.

- **Twelve features from a boringNotch / Notchy teardown (2026-08-27),
  decisions 069–080.** Both competitors were read off their installed bundles
  — Info.plists, preference domains, and string catalogues (boringNotch ~250
  strings, Notchy 2,213) — and the useful half was built. From boringNotch:
  album glow and blur behind the cover, sneak peek on track change,
  a three-way full-screen behaviour, the media idle timeout as a setting,
  an accent colour, a five-slot transport editor, a pinned-display picker, and
  a coloured spectrogram. From Notchy: token history, an **estimated**
  five-hour pace bar, and capture exclusion. Settings went from five panes to
  eight to house it. **None of it has been seen on screen yet** — see **Now**.

- **Two of the asks could not be built as asked, and both are logged.**
  *Show the pill while locked or in screen saver* (decision 078) is rejected,
  confirming 036: `sysadminctl -screenLock status` reports the lock delay on
  this machine is immediate, so the screen saver here *is* the lock screen and
  inherits the secure context 036 measured windows out of at every level. The
  preference was written and then removed rather than shipped as a control
  that cannot work. *Add-to-playlist as a transport slot* (decision 074) is
  excluded because it needs a target playlist owned by `PlaylistSection`; a
  slot with none chosen would be a lying control.

- **The rate-limit pace bar is an estimate, and says so.** Verified: Claude
  Code persists **no** real rate-limit signal locally — no `rate_limit`,
  `resetsAt`, `retryAfter` or `unified_rate_limit` anywhere in transcripts or
  telemetry — and `~/.claude/stats-cache.json` is unusable (measured 10 days
  stale, every `costUSD` zero). It is computed from transcript tokens in a
  rolling window, counting input + cache-creation + output and **excluding
  cache reads**, which matters: cache reads were 175M of 180M on one real day
  and counting them would make every figure meaningless.

- **SIGKILL's orphan is reaped for real (2026-08-27), decision 068.** SIGKILL
  cannot be caught — kernel guarantee, not an API gap — so the adapter it
  strands has always been caught on the *next* Tempo launch instead, by
  `MediaRemoteService.reapOrphanedStreams()`, which has existed since
  2026-08-22. It was missing most of them: it compared the adapter path with
  an exact `contains`, and `Bundle.main.resourcePath` keeps the spelling the
  bundle was *reached* through — canonical case via `open`, the shell's case
  when exec'd directly. On this case-insensitive filesystem that meant every
  orphan left by a dev-route Tempo was invisible to every `open`-launched one.
  Now compared case-insensitively, with a negative control proving it. The
  duplicate backstop added to `make-app.sh` in 067 is removed — one rule, in
  the app, running on every launch rather than only on a build.

- **A signal is a quit now (2026-08-27), decision 067.** AppKit turns neither
  SIGTERM nor SIGINT into `NSApplication.terminate`, so the default disposition
  killed Tempo outright and `applicationWillTerminate` never ran — every
  `scripts/make-app.sh` rebuild orphaned a `/usr/bin/perl` mediaremote-adapter
  to PPID 1, and ⌃C on a foreground `swift run` did the same. Both now route
  through a `DispatchSourceSignal` in `AppDelegate.installSignalHandlers()`.
  **The source must be on a global queue** — on `.main` it never fires in this
  app and Tempo just becomes immune to SIGTERM, which is worse; that is
  measured and commented at the call site. The script keeps its bare `kill`
  (no Automation TCC prompt).

- **Tempo can be quit (2026-08-27), decision 066.** Settings ▸ About now has a
  **Quit Tempo** button. It had none: `LSUIElement` means no Dock icon and no
  menu-bar item, and the main menu's ⌘Q is only live while the Settings window
  is key — so the honest answer was Activity Monitor. Uses
  `NSApplication.shared.terminate(nil)` so `applicationWillTerminate` runs and
  the lock-screen cards are withdrawn; verified by clicking it (0 tempo, 0
  adapter afterward).

- **Close animation fixed on notchless displays (2026-08-27), decision 065.**
  Reported as *"the weird black fade out … doesn't really feel that good."*
  Recorded and read frame by frame, it was two defects, both scoped to a
  notchless display with **Show the strip on external displays** off. The
  always-present black silhouette faded `0 → 1` on collapse — right on a
  notched Mac, where it becomes the pill hugging the notch, but here it drew an
  opaque black slab at near-full panel width over someone else's menu bar for
  ~0.2s. And `panelOpacity` sat inside the collapse spring's scope, so the
  whole-panel alpha inherited a critically damped curve whose tail left a dim
  ghost for ~0.5s after the retract had finished. The silhouette is now not
  drawn where there is no notch to merge with, and the alpha moved outside
  every `expandAnimation` onto its own `.easeOut(0.18)`. Verified on screen,
  before and after: no black in any frame, close down from ~0.6s to ~0.15s,
  notched-Mac behaviour unchanged by construction.

- **Screen Recording is granted (2026-08-27).** For the first time — decisions
  062, 063 and 064 each had to be verified through `ImageRenderer` or the
  accessibility tree because `screencapture` had no grant. The three **Now**
  items below were all blocked on exactly that and are now checkable on screen.
  `scripts/capture-panel-animation.sh` records the panel opening and closing
  and slices it into numbered frames.

- **Album tint fixed (2026-08-26), decision 064.** It had never worked. The
  tint *was* being computed correctly — the running app reports
  `artwork tint h=0.54 s=0.87 b=0.75` for the current cover — but it was
  handed to `Glass.tint`, and `glassEffect` contributes no pixels to the view's
  render tree at all (measured: `.regular`, `.clear` and `.tint()` in red and
  blue all render to an identical 0.502 grey). It is a compositor parameter,
  and the compositor showed nothing over a small dark panel. The colour is now
  painted as a hue-preserving, brightness-capped wash over the glass, shared
  with the Settings preview — which had been faithfully reproducing the bug.
  Two further defects fixed on the way: the tint alpha was being halved for no
  recorded reason, and below macOS 26 "Album tint" was byte-identical to
  "Regular glass". **Not yet seen on screen** — see **Now**.

- **Panel regrouped (2026-08-26), decision 063.** The expanded panel is now two
  groups — media (header, scrubber, playlist) and system (output, shelf, usage,
  agents) — separated by a wider gap and a hairline, instead of six sections at
  a uniform 12pt. The playlist row moved out of the header column to full
  width, which let the album cover drop from ~104pt to its 72pt floor. Panel
  ceiling raised 600 → 680, and `TEMPO_DEBUG_VIZ=1` now logs the measured
  height against it. Verified live through the accessibility tree: 28pt mute
  button, 24pt output chips, 353x28 agent rows reading out
  "ApplicationBot, running", no overlaps, 248pt of a 680pt ceiling.
  **The media half was not on screen when checked** (both players paused) —
  see **Now**.

- **HIG pass across every surface landed (2026-08-26), decision 062.** The
  panel, the collapsed pill, the onboarding cards and Settings now share one
  typography / metrics / state-appearance vocabulary (`Views/NotchStyle.swift`).
  Six HIG violations were fixed: **Reduce Transparency** and **Increase
  Contrast** were both entirely unread and now drive the panel's material,
  scrim, rim light and control affordances; **agent state was carried by hue
  alone** and now differs in fill, diameter and glyph (measured on a greyscale
  render — the running-vs-blocked pair went from 37/2500 to 827); five
  **sub-28pt hit targets** were raised; **31 hard-coded `.system(size:)`
  literals** (including a 9pt shelf label, below anything macOS ships) became
  named text styles that track the user's text-size setting; four per-glyph
  **text shadows** became one scrim; and the **visualizer** got the Reduce
  Motion path it was the last animation in Tempo to lack. Debug and release
  builds are clean with no warnings; `dist/Tempo.app` runs at 0.0% CPU at rest.
  **The shadow-to-scrim swap has not been seen by a human** — see **Now**.

- **First-run bug fixes landed (2026-08-25), decision 060.** The lock-screen
  cards could never post: Tempo's notification authorization is `denied` on this
  machine and `requestAuthorization` fails immediately with `UNErrorDomain#1`,
  which the code swallowed with `try?`. Permission is now requested when the
  feature is switched on, a refusal is recorded and surfaced, the grant is
  re-read on every activation, and the cards post at `.active` instead of
  `.passive` (which files a notification without presenting it). The cursive
  `hello` now uses **Apple's own lettering** (decision 061 — the hand-drawn
  curves were 1.5:1 where Apple's word is 3.36:1) and fades out before the setup
  cards arrive instead of being cut to them. **The cards still cannot
  appear until notifications are re-allowed by hand in System Settings** — see
  **Now**.

- **First-run hello and lock-screen cards landed (2026-08-24), decisions
  057–059.** Tempo now has a first run: a cursive `hello` writes itself out of
  the notch and resolves into setup rows for the permissions it needs. Weather
  and now-playing reach the *lock screen* as two system notifications — the
  only surface decision 036 left available, since a window there is impossible.
  Weather comes from Open-Meteo (no key, no account), located by
  reduced-accuracy CoreLocation with a typed city as the fallback. A new
  Settings ▸ Weather pane carries all of it, plus a live conditions readout so
  the feature can be checked without locking the Mac. Debug and release builds
  are clean with no warnings; `dist/Tempo.app` runs at 0.0% CPU with the
  onboarding panel open. **Almost none of this has been seen by a human yet** —
  see **Now**.

- **Sapphire feature review landed (2026-08-22), decisions 049–052.** Tempo now
  shows now-playing for *any* player, carries an output-device/volume row and a
  drag-aware file shelf in the expanded panel, and has a Bluetooth service that
  the platform currently refuses to let run. Debug and release builds are clean
  with no warnings; `dist/Tempo.app` runs healthy with the adapter stream as a
  child process. See **Now** for what still needs a human to look at it — the
  file-shelf drag interaction in particular has never been exercised by a real
  drag.

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
- **Click-to-focus landed (2026-08-20), decision 035.** The agent lights are now
  buttons: a click routes on the status file's `ide` field and goes to that
  session's host — the Ghostty/Terminal tab running it, the VS Code/Cursor window
  holding its workspace, or Claude Desktop — then collapses the panel. Ported
  from AgentStatus's `focus_session` (macOS paths only), **without** its two
  side-effecting parts: Tempo never writes the `~/.claude/status/focus-request.json`
  relay (Agent Guideline #3, so VS Code is window-precise, not tab-precise) and
  never runs `claude attach` to open a background agent. Every step runs off the
  main actor. Verified live on this machine: the ancestry walk finds Ghostty 4
  generations above `claude`, the session's `ai-title` matches exactly 1 of 3
  open surfaces, and a compiled probe brought Ghostty forward from a
  Finder-frontmost desktop — including for a session with no title, which falls
  back to fronting the owning terminal process. `NotchButtonStyle` gained the
  hover outline it previously only lent to the playlist picker, so transport,
  gear and lights now highlight identically.
- **Agent rows show what each session is working on (2026-08-22, decision
  040).** The lights are no longer a horizontal pill strip: each session is a
  full-width row — dot, folder label, and a one-line excerpt of the session's
  current prompt (`task`) — stacked vertically, three visible before the list
  scrolls. Two sessions in one repo are now distinguishable, which decision
  035's click-to-focus needed. `task` is rendered and nowhere else: flattened
  to one line, capped at 120 chars, never logged or stored.
- **Scrubbable progress bar landed (2026-08-22, decision 041).** The expanded
  panel has a full-width progress row under the cover and controls: elapsed
  time, a draggable bar, time remaining. Dragging the knob or clicking the bar
  seeks Spotify (on release). Position is an extrapolated *anchor* rather than
  a published ticking value, so a playing track costs 4 redraws/sec of one
  subtree and no state publishes, and a paused one installs no timer — the
  collapsed pill's zero-timer rest state is unchanged. Reconciled against
  Spotify at 1Hz **only while the panel is open** (a seek inside Spotify posts
  no notification, so nothing else would notice it). Verified live end to end;
  see the decision for the `set player position` race it uncovered.
- **Not yet verified by a human:** pill/panel look and feel, hover dwell feel,
  click-to-pause reliability in real use, the reactive visualizer visually, the
  usage graph rendering, agent-row legibility on glass **and the new row layout
  with more than one session open** (only one session existed on this machine
  while it was built), OAuth flow (still no Client ID configured).

## Now

- **The lock-screen cards need a playing track and a weather reading, and
  neither was present.** Not a defect (decision 081). `postMusicIfLocked`
  requires a *playing* track by design and Spotify has been paused;
  `postWeatherIfLocked` posts nothing without a reading, and no city is set
  (`weatherCity` unwritten, no cached place) so it depends on CoreLocation. To
  confirm both work: start playback, set a city in Settings ▸ Weather (or
  grant location), then lock. If a card still does not appear, run
  `TEMPO_DEBUG_VIZ=1 dist/Tempo.app/Contents/MacOS/tempo` and lock — there is
  now a log line per card naming which guard rejected it, and the `add()`
  completion error is no longer discarded.

- **`Show previews` is `.whenAuthenticated`, not `Always`.** Measured from the
  API: `status=2` authorized, `lockScreenSetting=2` enabled, `alertSetting=2`
  enabled, `showPreviewsSetting=1`. Tempo has **no per-app record in
  `ncprefs`** (searched all 110 entries, zero matches anywhere in the plist),
  so it is inheriting the system default and does not appear in System
  Settings ▸ Notifications ▸ Tempo for the user to change. Whether a card
  delivered under that setting renders with content on the lock screen is the
  open question — the README already warns it renders as a contentless
  "Tempo · Notification", and that claim is now worth re-checking against a
  real lock rather than trusted.

- **Look at all twelve features on screen.** Everything below decisions
  069–080 builds clean with zero warnings, and **not one of them has been
  seen running.** `scripts/capture-panel-animation.sh` and a granted Screen
  Recording permission are the tools. Specifically unwatched and most likely
  to be wrong:
  - **The album glow's strength curve** (070). Radius and alpha are folded
    into one slider; whether the chosen curve spans "barely there" to
    "unmistakable" is a matter of looking at it.
  - **The sneak peek's position and whether it collides with hover-expand**
    (072). It draws below the pill in the transparent part of the window and
    sets `allowsHitTesting(false)`; that it stays clear of the hover region is
    reasoned from decision 012's hit model, not watched.
  - **Full-screen hiding against a real full-screen app** (076). The
    `visibleFrame` vs `frame` heuristic is cheap and needs no Accessibility
    grant, but whether it fires on every full-screen style — native full
    screen, a game, a player that hides the menu bar without taking a Space —
    is exactly the class of claim Agent Guideline #4 exists for.
  - **The pinned-display picker with a second monitor actually attached**
    (075). The UUID matching and `applyGeometry(force:)` path have never run
    against real hardware.
  - **Capture exclusion** (077). Note it also hides the panel from
    `scripts/capture-panel-animation.sh`, so verify it with the setting on,
    then turn it off before capturing anything else.

- [ ] **Look at Album tint (decision 064)** — verified as pixels out of the
      real derivation code, not as a photograph. Settings ▸ General ▸ Expanded
      panel ▸ **Album tint**, with something playing. Expect a clear cast in
      the cover's hue across the panel body, and the top ~53pt still black
      where it meets the notch. The Settings card should now show the tint too
      — it previously showed plain glass. If it lands too strong or too weak,
      `PanelTint.washOpacity` (0.22) and `PanelTint.maxBrightness` (0.62) in
      `Views/NotchStyle.swift` are the only two knobs. `TEMPO_DEBUG_VIZ=1`
      prints the derived tint, or says the cover is missing/unsamplable.

- [ ] **Play something, then hover (decision 063)** — the media half of the
      regrouped panel has never been drawn. Both Spotify and Music were paused
      when it was verified, so `showsMedia` was false and the restructured
      now-playing header, the scrubber, the full-width playlist row and the
      group separator were all absent from the render. Check: the cover is
      ~72pt (not ~104); title and artist stay centred over the play button;
      the scrubber and the playlist picker each span the full 353pt content
      width; and the hairline sits between the playlist row and the audio
      output row with even air on both sides. `TEMPO_DEBUG_VIZ=1` prints the
      measured height against the 680pt ceiling on every re-measure.

- [ ] **Look at the panel over a bright window (decision 062)** — the one part
      of the HIG pass that was built by reasoning rather than by sight. Four
      places used to draw text with a `.black.opacity(0.5)` drop shadow to
      survive clear glass; those are gone, replaced by a single scrim under the
      whole content (0.30 for **Clear glass**, 0 for the denser styles, +0.22
      on top of either under Increase Contrast). `screencapture` had no Screen
      Recording grant in the session that made the change, so this was never
      rendered over a real backdrop. Check the track title, the artist, the
      transport glyphs, the scrubber's two clocks and the gear against a
      **white** window in each of the four panel styles — Clear is the one at
      risk. If Clear still washes out, `ContentView.contentScrim` is the single
      knob. Regenerating the README shots is the same exercise:
      `./scripts/capture-readme-shots.sh` (needs Screen Recording +
      Accessibility on the invoking terminal), and **the current shots are now
      stale** — they show the old 9pt shelf labels, the old flat-grey artwork
      placeholder and the old colour-only agent dots.

- [ ] **Sanity-check the four accessibility settings (decision 062)** — each
      was implemented against the HIG and compiles, but only the greyscale
      separation of the agent dots was actually measured. In *System Settings ▸
      Accessibility ▸ Display*: **Reduce Transparency** should make the panel
      opaque in every style; **Increase Contrast** should give every control a
      resting plate and border and visibly deepen the panel; **Reduce Motion**
      should leave the visualizer completely still (raised bars while audio
      plays, flat when it stops) and swap the open/close spring for a fade.

- [ ] **Watch the hello (decisions 057, 060, 061)** — Settings ▸ About ▸
      *Show the welcome again* replays it without touching `hasSeenHello`.
      The geometry is now Apple's published centreline artwork, so the shape
      itself is not in question; what still needs eyes is the **motion**.
      Check: it writes `h` → `he` → `hell` → `hello` left to right (Apple's
      artwork is two subpaths and they are sequenced by arc length — if both
      halves advance at once, `shares` is wrong); the panel springs open before
      the pen touches down; the word **fades out** before the setup cards arrive
      rather than being swapped for them; clicking the word skips; and the cards
      fit inside the panel. The write-on timing curve was set by reasoning, not
      by watching it — if it still reads wrong, that curve is the knob.

- [ ] **Turn Tempo's notifications back on, then walk the setup rows
      (decisions 057–060)** — **blocking for the lock-screen cards.** Probing
      the real bundle this session found Tempo's notification authorization is
      `denied` on this machine, and `requestAuthorization` returns
      `UNErrorDomain#1 "Notifications are not allowed for this application"`
      immediately: once macOS has a refusal on file it never prompts again. So
      the app cannot fix this itself. Go to **System Settings ▸ Notifications ▸
      Tempo** and turn **Allow Notifications** on (the sub-settings *Show on
      Lock Screen* and *alerts* already read as enabled; **Show previews** is
      `whenAuthenticated` and needs to be **Always**, or a locked card renders
      as a contentless "Tempo · Notification"). Tempo re-reads the grant on
      every activation now, so coming back from System Settings should flip the
      row to a green check with no relaunch. Then the *Weather location* row
      should appear and macOS should ask for **approximate** location (not
      precise — if it asks for precise, `kCLLocationAccuracyReduced` is not
      taking effect).
      **Answered this session:** an ad-hoc-signed bundle *can* reach the
      notification system — Tempo is registered in the notification database and
      `add()` delivers. What blocks it is the recorded denial, not the
      signature. (A probe bundle under `/private/tmp` is refused outright, so
      don't diagnose this from a scratchpad copy — test the real
      `dist/Tempo.app` in place.)

- [ ] **See the lock-screen cards on a real lock screen (decision 058)** —
      with the cards on and something playing, lock the screen (⌃⌘Q) and look.
      Expect two cards: weather, and the track. Then, still locked, skip to the
      next track — the music card must **replace itself in place**, not stack a
      second one. Unlock: both cards should be gone from Notification Center.
      **Before any of this**, set System Settings ▸ Notifications ▸ Tempo ▸
      *Show on Lock Screen* on and *Show previews* to **Always** — the default
      renders a locked card as a contentless "Tempo · Notification", which is
      the failure mode most likely to read as "the feature is broken".

- [ ] **Check the weather reading is real (decision 059)** — Settings ▸ Weather
      ▸ *Current conditions* should show a temperature, a condition and a place
      within a few seconds of switching the cards on. Verified already: the
      Open-Meteo forecast and geocoding endpoints both answer from this machine
      with well-formed payloads and no key. Not verified: that CoreLocation
      produces a fix in an ad-hoc-signed app, that the reverse geocode names
      the place, or that a typed city resolves through the app (only through
      `curl`). Try both — type a city with location off, then turn location on.

- [ ] **Re-grant System Audio Recording and watch the bars follow YouTube
      (decision 056)** — `scripts/make-app.sh` re-signs ad-hoc, which silently
      invalidates the audio grant: TCC still lists Tempo as allowed while Core
      Audio hands the tap all-zero buffers. Run `tccutil reset AudioCapture
      com.gameslayer999.tempo`, relaunch `dist/Tempo.app`, click **Allow** on the
      prompt, then play a YouTube video. The bars must move with the audio, and
      keep moving with Spotify quit. Until that click lands, the global tap is
      unverified against real audio: the tap builds and `anyRunningOutput` tracks
      playback correctly, but every sample read so far has been a denied zero.

- [ ] **The artwork can still lie while the bars tell the truth (decision 056)** —
      MediaRemote keeps reporting a paused Spotify card for up to a minute
      (`mediaIdleTimeout`) while another app plays, so the collapsed strip can
      show the wrong album beside a correctly-reacting visualizer. Decide whether
      a card whose app is *not* the one making sound should be dropped early.

- [ ] **Look at the hidden strip with your own eyes (decision 055)** — switch
      Settings ▸ General ▸ *Show the strip on external displays* **off**. Nothing
      should be drawn at the top of the external display, and the menu bar there
      should behave exactly as if Tempo weren't running. Point at the top middle:
      the panel should open, and everything in it should work normally. This was
      verified by accessibility element count and by an instrumented `hitTest`
      A/B, but not by looking — this shell has no Screen Recording permission, so
      no screenshot could be taken.

- [ ] **Check the display switch across a lid open (decisions 054, 055)** — with
      the strip switched **off**, open the MacBook's lid: the strip should appear
      on the real notch within about a second (there is a 750ms settle re-check,
      because macOS reports the built-in screen back before its `safeAreaInsets`
      are correct), and the pointer monitor should stop. Close the lid and the
      strip should go away again while the hover target stays. Everything else
      about the switch was verified live; this transition needs the hardware.

- [ ] **Confirm the expanded panel no longer clips (decision 053)** — the
      height ceiling was 280pt and the sections added since the scaffold ran
      past it, so the bottom of the panel was simply not drawn. It is now
      600pt. Open the panel with music playing, the playlist connected, files
      on the shelf and a few agent sessions live: every section — now-playing
      header, progress bar, output row, shelf, usage graphs, agent rows —
      should be fully visible with the panel's rounded bottom edge below them.
      The fullest case measured out at ~525pt on paper but has never been seen
      on screen in one frame; if anything is still cut off, raise
      `NotchGeometry.panelHeight` further (it costs nothing — the window is
      transparent and click-through outside the drawn shape).

- [ ] **Verify the file shelf by actually dragging a file (decision 051)** —
      this is the one part that could not be verified without a human. Synthetic
      mouse events do not populate the drag pasteboard, so the detection
      heuristic itself is untested end to end. Pick up a file in Finder and
      drag it toward the notch: the panel should open as a dashed drop well
      *before* you reach it (about 80pt out), and let go to keep it. Then hover
      the notch later — the shelf row should show the item; drag it back out to
      a Finder window, and right-click it for Reveal/Remove. Expect the panel
      to open a few pixels into the drag rather than instantly, since AppKit
      fills the drag pasteboard when the session begins. Also check: a drag
      that passes *near* the notch and moves away collapses it again, and a
      drag that ends elsewhere does not leave the panel stuck open (there is a
      0.2s watchdog for exactly that).

- [ ] **Try the audio output row (decision 050)** — open the panel: the mute
      button, volume slider and a chip per output device. Click a chip and the
      system output should switch (check System Settings ▸ Sound agrees).
      Connect AirPods and confirm a new chip appears without a relaunch. Select
      an HDMI/display output and confirm it says the device owns its volume
      rather than showing a dead slider. Untested on this machine:
      Bluetooth/AirPlay/USB device symbols, since none was connected.

- [ ] **Check now-playing across players (decision 049)** — play something in
      Apple Music, then a YouTube video in a browser, then a podcast: the cover,
      title, artist, progress bar and the transport buttons should all follow
      whatever is playing. Confirm the add-to-playlist row is *disabled* while
      a non-Spotify source is playing and enabled again for Spotify. Verified
      already: Spotify and Chrome are both picked up, play/pause tracks live,
      and an external seek reaches the bar in about half a second.

- [ ] **Check the panel-style previews (decision 046)** — Settings ▸ General ▸
      Expanded panel now shows four mini panels instead of a menu. Confirm the
      three glass ones actually look different from each other (each is a real
      `glassEffect` sampling the card's own gradient backdrop — if they render
      flat/identical, the effect isn't sampling in-window content and the
      backdrop needs to move behind the whole row instead), that **Album tint**
      picks up the colour of whatever is playing and updates on a track change,
      and that clicking a card changes the live notch.

- [ ] **Look at the collapsed agent light (decision 042)** — with a session
      running, the pill should carry a green dot to the right of the bars and
      stay centred on the physical notch. Check: the dot survives the media
      retraction (pause Spotify, wait 60s — the wings go, the dot stays); a
      session going blocked turns it orange and pulses; ending a session flashes
      pulsing white for 20s then settles; the pill springs rather than snaps
      when the dot appears or disappears; and switching Settings ▸ Modules ▸
      Agent light to "One dot per session" and "Off" both re-lay-out cleanly.

- [ ] **Watch the media-idle transition once (decision 038)** — with music
      playing, pause Spotify and leave it: after 60s the wings must retract on
      the spring and leave exactly the notch, and hovering that bare notch must
      still open the panel (usage graphs + agent lights, no now-playing header).
      Press play: cover, bars and controls must come straight back. Also check a
      click just beside the notch reaches the app behind once the wings are gone.

- [ ] **Try the progress bar (decision 041)** — with music playing, open the
      panel: the bar must advance smoothly and the times must count up/down.
      Drag the knob and let go — playback should land there and the bar must
      *stay* there, not snap back. Click somewhere on the bar (no drag) — it
      should jump there too. Then scrub inside Spotify's own window with
      Tempo's panel pinned open: the bar must catch up within a second. Check
      a track over an hour long (podcast/DJ set) shows `h:mm:ss` uncropped.

- [ ] **Verify the multi-display fix** (decision 037) — with Tempo running:
      open the lid while docked (pill must jump to the built-in notch at its
      real notch width), shut it again (pill must re-centre on the external as
      the 200×32 fallback strip), unplug and replug the monitor, and drag the
      displays around in System Settings ▸ Displays. In each case the pill must
      land on the current notch within a second, and hover/click must still work
      there — the hit region moves with it.

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
- [ ] **Verify click-to-focus for the editor hosts** (decision 035) — the VS Code
      and Cursor routes are the only ones untested: both apps are installed but
      neither was running a Claude session, and `~/.claude/ide` held no lock
      files, so `workspaceRoot` fell back to `cwd` unexercised. Open a session in
      each, click its light, and confirm it lands in the right window (and that
      Cursor is not handed a new agent).
- [ ] **Grant Tempo Accessibility** (System Settings ▸ Privacy & Security ▸
      Accessibility) and re-check a click on a light for a window on another
      Space or full-screen — that raise is the one step the permission gates.
- [ ] **Verify the OAuth flow live** — create the Spotify Developer app (README),
      add the Client ID, Connect Spotify, add a song to a playlist.

- [ ] **Decide what to do about Bluetooth notices (decision 052)** — the service
      is written and safe but dormant: CoreBluetooth never powers on for this
      process, so `IOBluetooth` blocks forever and no event can ever fire. It is
      confined to its own thread so it cannot freeze Tempo, and nothing is wired
      to the UI. First thing to check: whether Tempo appears in System Settings
      ▸ Privacy & Security ▸ Bluetooth at all now that the bundle carries
      `NSBluetoothAlwaysUsageDescription`. If it does, only the UI is left.

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

- [ ] **`AudioTapService.shared` blocks the main thread while it starts the tap.**
      Found while debugging decision 049: the singleton is initialised lazily
      from inside `ContentView.strip`'s body, so `AudioDeviceStart` runs on the
      main thread during a SwiftUI body evaluation. When the audio permission
      is not in force (observed by launching the bare binary rather than the
      bundle) it never returns and the whole app freezes — `sample` showed the
      main thread parked in `mach_msg2_trap` under
      `AudioTapService.buildTap(pid:)` indefinitely. The bundled, permitted
      launch path is fine, so this is not a user-facing bug today, but a slow
      or waking audio device would hit the same path. Pre-existing; not
      touched as part of the four features above.

- [ ] Apple Music support (AppleScript dictionary exists; artwork via `artworks`
      raw data instead of a URL).
- [ ] Network throughput in the usage row (Notchy shows it; `getifaddrs` deltas,
      filter `utun*`/`awdl*`/`bridge*`).
- [ ] Self-sufficient agent-status signal layer (bundle a hook installer for
      machines without AgentStatus) — deferred per decision 005.
- [ ] Click a light → focus that session (port AgentStatus's focus logic).
- [ ] Calendar / battery / file-shelf modules (category table stakes, out of v1).
- [ ] Context as a **percentage** on the agent rows, if Claude Code ever records
      which context window a session was opened with. Today the transcript says
      only `claude-opus-5`, and a session here peaked at 460k, so the figure is
      absolute (decision 048). The check is a `grep` for a window-size field in a
      fresh transcript — nothing else needs to change.

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

- **2026-09-07 — The very top row of the display is inside the target now
  (decision 096).** Reported as "a dead zone on the very top when touching the
  edge of the monitor" on the external display. Every pointer-tested region is
  a top-anchored `NSRect` whose `maxY` equals `screen.maxY`, and
  `NSRect.contains` excludes `maxY` — which is exactly what
  `NSEvent.mouseLocation.y` reports when the pointer is parked on the topmost
  row. Verified by warping the cursor: Quartz y=0 gives 1440.00 (`contains` =
  no), y=1 gives 1439.00 (yes). `hoverActivationRegion`,
  `expandedPanelRegion` and `dragActivationRegion` now all build through
  `NotchGeometry.topAnchoredRegion`, one point taller so the rect overshoots
  above the screen edge into space the pointer cannot reach. Decision 095's
  30pt row, the menu-bar gate and the dwell are unchanged.

- **2026-09-04 — The target is the menu bar's row, not a 3pt band (decision
  095).** Reported after 092 fixed the misfire: "sometimes when menu bar is down
  it doesnt expand, or it flickers and then goes away." One cause — a 3pt band
  has to *hold* the pointer for the whole dwell, and the hand relaxes a pixel or
  two down into the bar it just revealed, cancelling the dwell or collapsing the
  panel right after it opened. `hoverActivationRegion` now takes a height and
  the detector passes `MenuBarSensor.barHeight`, measured from the sensor's own
  status window (30pt) rather than `NSStatusBar.system.thickness` (22pt — the
  8pt gap *is* the relax). The gate poll runs anywhere in the row now, not only
  at the extreme edge. Safe because decision 091's gate does the filtering, not
  the height.

- **2026-09-04 — Slider values can be typed; Edge hold capped at 150ms
  (decision 094).** Asked for directly: "I should be able to fine tune sliders
  by entering the values manually... i doubt anyone would use anything over 150
  ms." `SliderRow`'s value `Text` is now a `TextField` with a per-row `parse`
  closure, so all seven sliders accept typed input — units optional, plus `2.5M`
  for the token budget and `Never` for the paused-media timeout. Typed values
  are clamped to the range but not snapped to the step (dragging steps; typing
  reaches between). Clicking away commits like Return. `maxEdgeHoldDelayMS`
  1500 → 150, step 50 → 10.

- **2026-09-04 — The edge push gets its own hold setting (decision 093).**
  Requested directly: "make sure that we are able to tweak things like how long
  we need to hold the cursor on the menu bar in settings." `edgeHoldDelayMS`
  (0–1500ms, step 50, default 60 — today's value, so no feel changes) is a
  separate preference from the pill's `hoverExpandDelayMS` (0–400ms), because
  the two gestures have opposite ideals. `handleHover` now takes the delay as a
  parameter and the pointer-monitor path passes the new one. The slider lives
  in Settings ▸ Displays ▸ Placement under "Show the strip on external
  displays", disabled while that toggle is on. The hold runs *after* the menu
  bar finishes dropping (decision 091); the footer says so.

- **2026-09-04 — `.onHover` fires where `hitTest` says nothing is there
  (decision 092).** The actual cause of the misfire decisions 090 and 091 both
  failed to fix. Instrumenting the running app and reproducing showed
  `atEdge=true` **zero** times across 3798 samples: the band was never entered
  and the menu-bar gate never consulted, while every misfire started with
  SwiftUI's `.onHover` on the collapsed pill (~308x32pt at the top of the
  screen) and the pointer monitor only reported *afterwards*, on the panel that
  had already opened. Decision 055 assumed `.onHover` could not fire where
  `hitTest` returns nil; tracking areas ignore hit-testing, so both paths were
  live and the unrestricted one won. `.onHover` is now ignored while
  `stripHidden`, leaving `NotchHoverDetector` in sole charge of that mode.
  Confirmed working on the monitor; the `TEMPO_DEBUG_HOVER=1` scaffolding it
  was diagnosed with has been removed again.

- **2026-09-04 — The notch opens only once the menu bar is down (decision
  091).** Reported as "when I try to select a tab in a browser like google
  chrome near the middle of the screen, I keep accidentally triggering tempo" —
  a full-screen tab strip runs to the top edge, so it shares the 3pt band
  decision 090 left. There is no API for "the menu bar is down":
  `NSMenu.menuBarVisible()` answers a different question and
  `NSScreen.visibleFrame` reserved the same 30pt in both states (both measured).
  A status item's window does track it exactly — hidden `y = 1440`, fully down
  `y = 1410` on a 1440pt screen — so `MenuBarSensor` owns a zero-length status
  item, created only while `NotchHoverDetector` runs, and the hover gate now
  requires the bar fully down. Opening only: the expanded panel's region stays
  ungated, since moving into the controls retracts the bar. A 0.1s timer
  re-checks the gate while the pointer is in the band, because a pointer held
  against the edge sends no further events. Builds; needs a check on the
  external monitor.

- **2026-09-04 — The invisible notch opens at the screen edge, not near it
  (decision 090).** With the strip hidden on an external display, the
  pointer-watched hover target was the full invisible pill — `pillWidth` wide
  and 32pt tall — so the panel dropped open whenever the pointer crossed the top
  of the screen on its way to a title bar or a tab.
  `NotchGeometry.hoverActivationRegion` is now a 200 x 3pt band flush with
  `screen.maxY` (`hiddenStripActivationHeight`), so Tempo appears on the same
  gesture that reveals a hidden menu bar. Only `NotchHoverDetector` reads that
  region, and only in that one mode, so the drawn strip's `.onHover` and the
  expanded panel's region are untouched. Builds; needs a check on the external
  monitor.

- **2026-08-27 — The pointer becomes a hand over a control (decision 089).**
  The panel's controls draw no chrome at rest, so the hover highlight was the
  only "this is clickable" cue and it only arrives once you are already on the
  control. A `pointingHandCursor()` modifier in `NotchStyle.swift` uses macOS
  15's `pointerStyle(.link)` where it exists — the system owns the cursor's
  lifetime, so a control that disappears under the pointer (the shelf's x, the
  whole panel on collapse) cannot strand a hand on the desktop — and falls back
  to `NSCursor` push/pop with an unwind on `onDisappear` for macOS 14. Applied
  inside `NotchButtonStyle` (transport, gear, Connect Spotify, add-to-playlist,
  agent rows) and individually to the controls no style can reach: the shelf's
  remove button, mute, the device chips, the playlist `Menu`, and onboarding's
  two custom button styles. Excluded on purpose: Settings' standard AppKit
  controls (on macOS the arrow over a real button is the convention; the hand
  means link) and onboarding's "hello" skip target (deliberately has no visible
  affordance). Shipped in the running bundle; needs a hover check on screen.

- **2026-08-27 — The shelf's remove button no longer flickers (decision 088).**
  Reported as "really difficult to delete something from the file shelf: the x
  flickers a lot when hovering over." The 24pt button was pushed outside its
  52pt chip with `.offset(x: 8, y: -8)` while `.onHover` was tracked on the chip
  alone, and the button was mounted only while hovered — so reaching for it left
  the hover region, unmounted the button, restored hover, and remounted it, over
  and over; a click landing mid-cycle hit the chip's `.onDrag` and dragged the
  file out instead of removing it. The button now sits inside the chip's bounds,
  stays mounted, and fades with `.opacity`/`.allowsHitTesting` on a 0.12s
  ease-out, so the hover region and the hit target are the same rect. The exit
  handler also clears only its own id, so moving between adjacent chips can't
  leave the row unhovered. Row spacing, chip size and the 24pt target unchanged.
  **Not yet seen on screen** — builds clean; needs a hover-and-click check.

- **2026-08-27 — The session title is read from the end of the transcript (decision 087).**
  Clicking the light for the session in `~` fronted the Ghostty app instead of
  its window. Cause: `claudeSessionTitle` skipped any transcript over 16MB, and
  that session's is 22,788,432 bytes — so the title match never ran even though
  Claude's title (`LHR 400 class alternatives`) matched its surface exactly, and
  decision 085's directory fallback missed too because the session's status file
  records `cwd` as the transcript's project directory rather than
  `~` (AgentStatus's data, read-only to Tempo). The cap is
  replaced by a backward line scan over the memory-mapped file that stops at the
  last `ai-title` record: verified with the shipped code against the real file,
  the title comes back in under 1ms from 19KB in. Also measured while chasing
  this, and left alone: Ghostty's `focus` does cross Spaces (active space 3 →
  263 with no Ghostty window on the starting Space), and it is a no-op only when
  Ghostty is already the frontmost app with all its windows elsewhere.

- **2026-08-27 — The sneak peek gets a rim light (decision 086).**
  Liquid Glass draws its own rim from what is behind the window, so the peek's
  edge thinned to nothing over bright wallpapers. A 1.5pt white 0.28
  `strokeBorder` is now the topmost layer over the glass, and replaces the
  old 0.10/1pt hairline on the Reduce-Transparency / Solid / macOS 14-15
  fallback plate. Nothing else about the peek changed.

- **2026-08-27 — A Ghostty session with no title yet is found by its folder (decision 085).**
  Clicking a light for a session Claude had not titled yet fell straight
  through to fronting the Ghostty app, landing on whichever window was last
  used — a different session on a different Space. `SessionFocusService` now
  runs a second match after the title match fails: Ghostty's per-surface
  `working directory` against the session's `cwd`, with surfaces claimed by
  another live session's `ai-title` struck out, acted on only when a single
  surface survives. `focus(_:among:)` takes the session list for that
  elimination. Verified live against three sessions in three Spaces: the
  untitled case resolved to exactly the right surface and focused it, and the
  two-untitled-sessions-in-one-folder case declined and left the old fallback
  in place. Also measured and left alone: Ghostty's `focus` does cross Spaces
  and activate the app, its app-level `terminals` list is complete regardless
  of Space, and tab order never enters the match.

- **2026-08-27 — The sneak peek wears Liquid Glass (decision 084).**
  `ContentView.peekBackground`: `glassEffect(.regular)` in a 20pt continuous
  rounded rect, replacing the black 0.82 plate and its white hairline, so the
  track-change peek reads as one of the system HUDs it appears beside. Neutral
  and independent of `panelStyle`. Plate fallback kept for macOS 14/15, Reduce
  Transparency and the Solid style; Increase Contrast adds a 0.25 scrim.
  Verified on screen over a dark terminal and a light-chrome window by driving
  a real Spotify track change at zero volume and restoring the player after.

- **2026-08-27 — Coloured Settings sidebar icons (decision 083).**
  `SettingsView.Pane.tint` plus a `PaneIcon` tile: each pane's glyph in white on
  a rounded rect of its own colour, the System Settings shape. Sidebar only.

- **2026-08-27 — The orphan reaper actually matches (decision 068).**
  `MediaRemoteService.reapOrphanedStreams()` compares the adapter path
  case-insensitively; the duplicate PPID-1 backstop is removed from
  `scripts/make-app.sh`. SIGKILL itself is unfixable and stays that way.

- **2026-08-27 — SIGTERM/SIGINT are clean quits (decision 067).**
  `AppDelegate.installSignalHandlers()`; `scripts/make-app.sh` gains a comment
  on why it still uses `kill` rather than `osascript … to quit` (its PPID-1
  reap was removed again by 068 as a duplicate). Verified: SIGTERM exits in 0.04s with the adapter
  reaped, SIGINT the same, a rebuild leaves exactly one tempo and one adapter,
  and a deliberate SIGKILL orphan is reaped on the next run.

- **2026-08-27 — Quit Tempo in Settings ▸ About (decision 066).** New section
  in `SettingsView.AboutPane` below the version;
  `NSApplication.shared.terminate(nil)`. README ▸ Settings ▸ About updated.

- **2026-08-27 — The close no longer flashes black (decision 065).**
  `ContentView.backgroundShape`'s silhouette is `.opacity(displayedExpanded ||
  stripHidden ? 0 : 1)`; `.opacity(panelOpacity)` moved outside every
  `expandAnimation` modifier and took a new `fadeAnimation`
  (`.easeOut(0.18)`, `0.15` under Reduce Motion). New
  `scripts/capture-panel-animation.sh` — the harness that found it.

- **2026-08-26 — Album tint actually tints (decision 064).** `PanelTint` in
  `Views/NotchStyle.swift` derives the wash; `ContentView.glassLayer` and
  `PanelStylePreview` both paint it. `Glass.tint` still passed, now at full
  alpha instead of 0.55. Works below macOS 26 for the first time.
  `AppState.artwork.didSet` logs the derived tint under `TEMPO_DEBUG_VIZ=1`.

- **2026-08-26 — Expanded panel regrouped (decision 063).** Media and system
  blocks with a hairline between them; `PlaylistSection` moved out of the
  header column to full width; `NotchMetrics.groupSpacing`; `hasSystemContent`
  so the rule never draws over an empty group; panel ceiling 600 → 680 with a
  debug-gated overflow log.

- **2026-08-26 — HIG pass over every surface (decision 062).** New
  `Views/NotchStyle.swift`: `NotchType` (7 named roles → macOS text styles),
  `NotchMetrics` (2 hit targets, 3 spacing steps, the content inset) and
  `AgentAppearance` / `AgentDot` (one state's colour, shape, glyph, motion and
  spoken name, shared by the pill and the rows). Adopted across
  ContentView, AgentLightsView, CollapsedAgentLight, NotchButtonStyle,
  PlaybackProgressView, AudioOutputView, ShelfView, UsageGraphView,
  PlaylistSection, VisualizerView, OnboardingView and SettingsView.
  Reduce Transparency, Increase Contrast and Reduce Motion honoured;
  VoiceOver labels and help tags added throughout (the scrubber is now an
  adjustable element that VoiceOver can seek); the artwork placeholder became a
  real empty state instead of a flat grey square.

### 2026-08-25 — the cards could never post, and the hello was a cut (decision 060)

Two reported bugs, both in the first-run surface shipped the day before.

- **Lock-screen cards never appeared.** Root cause, measured against the real
  bundle: notification authorization is `denied` and
  `requestAuthorization` fails with `UNErrorDomain#1` with no prompt. Four
  faults kept that invisible, all fixed — the request error was swallowed by
  `_ = try? await` (a refusal is now recorded as `.denied`); nothing asked for
  permission when the feature was switched **on** (`start()` now asks when the
  state is `notDetermined`); the grant was read once inside `start()` and so
  never noticed a fix made in System Settings (now re-read at launch, on every
  `didBecomeActive`, and on the lock edge); and the cards posted at
  `interruptionLevel = .passive`, which files a notification without presenting
  it — now `.active`, still soundless.
- **Artwork race fixed** — `withdraw(_:)` swept the attachment temp files, so
  withdrawing the weather card could delete the music card's artwork before
  `UNNotificationAttachment` had copied it. Files are now swept when writing the
  next one.
- **The hello is now Apple's actual lettering (decision 061).** Two hand-drawn
  passes were both wrong in three independent ways — aspect 1.5:1 against
  Apple's **3.36:1**, straight-diagonal ascenders against continuously curving
  ones, and a 3pt hairline against Apple's **8% of the word's height**. Apple
  publishes the word as *centreline* paths (`fill="none"`, `stroke-width="60"`),
  which is the one form that works here: a filled glyph outline run through
  `trimmedPath` would draw its contour, not a pen stroke. It is two subpaths, so
  they are drawn in sequence weighted by arc length, and the stroke width is
  derived from the rendered size rather than fixed. The `Text("Tempo")` label is
  gone, timing is near-steady instead of `easeInOut`, and the word now **fades
  out** before the cards arrive.
  **Licensing note:** the artwork is "Copyright © 2020 Apple Inc. All rights
  reserved." Swapping in an original word is a data-only change — the two
  subpath arrays in `HelloScript` are the whole dependency.
- Debug and release builds are clean with no warnings; `dist/Tempo.app` rebuilt
  and relaunched.
- **Also:** the System Settings link now deep-links to *Tempo's own*
  notification page via `?id=<bundle-id>` (verified by reading back the window
  title), rather than dumping the user in the app list.
- **Not yet seen by a human:** the hello animating in the running app, and any
  lock-screen card — the latter is blocked until notifications are re-allowed in
  System Settings (see **Now**).

### 2026-08-24 — a first run, and the lock screen revisited (decisions 057–059)

- **Asked for:** "a hello screen when first starting the app, just like the
  Apple hello", and "revisit those lock screen notifications: weather and music
  would be pretty nice".
- **The hello writes itself out of the notch** (057). Presentation was the
  user's call from four options; unrolling from the notch means no new window
  and no activation — Tempo is `LSUIElement` and never takes focus. `HelloScript`
  is **one continuous cubic path**, which is what lets `trimmedPath(from:to:)`
  draw it letter by letter; five subpaths would draw all five at once. The
  curve was tuned by rendering it to a PNG and looking at it across three
  passes — the first had a pinched `e` and a long trailing swash where Apple's
  ends on a short tick.
- **One flag did the whole job.** `AppState.isOnboarding` folded into
  `displayedExpanded` means hover-out, the outside-click monitor, the
  pin-on-click path and the live hit region all hold the onboarding panel open
  without learning what onboarding is. `NotchWindow.swift` did not change.
- **Two bugs, both found and fixed during the session.** The setup cards bled
  past the panel edges — `.padding` after `.frame(width:)` adds *outside* the
  frame, so content laid out 52pt wider than the window
  (`ContentView.expandedContent` had the correct order all along). And
  `LocationService` matched only `.authorizedAlways`, while
  `requestWhenInUseAuthorization()` — the call Tempo makes — returns
  **`.authorizedWhenInUse`**; a granted Mac would have silently never started
  the location manager. Folded into `CLAuthorizationStatus.grantsLocation` so
  it cannot recur at one call site and not another.
- **The lock screen, honestly** (058). Decision 036 proved a window there is
  impossible — four opaque strips bracketing `loginwindow`'s own windows were
  all invisible while locked — and named notifications as the only remaining
  surface. Two cards, posted on the lock edge, **replaced in place** by
  re-adding the same identifier while locked, withdrawn on unlock and on quit.
  Passive and silent: they never wake a sleeping display. `ScreenLockService`
  is 036's code restored — its lock *detection* was measured correct on both
  edges and was deleted along with the drawing that wasn't.
- **Weather from Open-Meteo** (059), verified live from this machine before it
  was chosen: current temperature, apparent temperature, a WMO code and a
  day/night flag, with no key and no account. WeatherKit was ruled out on a
  hard fact — it needs a Team ID, and `codesign -dv` reports
  `TeamIdentifier=not set`. Location is reduced-accuracy CoreLocation with a
  typed city as the fallback; the device coordinate is never written to disk.
- **Also:** a Settings ▸ Weather pane (cards, location, units, live conditions,
  and the two System Settings switches Tempo cannot set for itself),
  Settings ▸ About ▸ *Show the welcome again*, and
  `NSLocationWhenInUseUsageDescription` added to the Info.plist generated by
  `scripts/make-app.sh` — not hand-edited into the bundle (Guideline #8).

### 2026-08-24 — the visualizer went deaf to everything but Spotify (decision 056)

- **Reported:** "the audio visualizer bugs out when watching media other than
  spotify … its stuck." It was frozen, not glitching: `AudioTapService` tapped
  only `com.spotify.client`'s process, so a YouTube tab produced no levels, and
  the sine fallback's gate (`isPlaying`) came from MediaRemote, which at that
  moment reported Spotify's *paused* card while Chrome played. Both signals said
  "nothing is playing", so `VisualizerView` paused its `TimelineView` outright.
- **Fixed with one global tap** —
  `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`. The tap is built
  once and lives for Tempo's lifetime (no more Spotify launch/terminate
  observer), and the TCC-denial heuristic now asks "is *any* process running
  output" via `kAudioHardwarePropertyProcessObjectList`.
- **The strip grows a visualizer-only wing** when audio plays with no
  now-playing card behind it (`ContentView.showsAudioOnly`): no artwork, empty
  mirror wing so the notch gap stays centred. It keys off a new
  `AudioTapService.audioActive` — 2s to open (a Discord ping must not pop the
  pill) and 15s to close (the gap between two clips must not retract it).
- **Still open:** MediaRemote can report a *stale paused* card from one app while
  another plays, so the artwork beside the honest bars can be the wrong track.
  See **Now**.
- **Watch out when rebuilding:** ad-hoc signing means every `scripts/make-app.sh`
  run invalidates the audio-capture grant while TCC still lists it as allowed —
  the tap then returns all zeros with no prompt and no error. `tccutil reset
  AudioCapture com.gameslayer999.tempo`, relaunch, click Allow.

### 2026-08-24 — "Show the strip on external displays" (decisions 054, 055)

- **New setting, Settings ▸ General ▸ Displays.** Off means the collapsed strip
  is not drawn when the display Tempo hugs has no hardware notch — lid closed, or
  a Mac with no built-in notch. On (the default) is exactly the old behaviour. No
  effect while the built-in display is present, since `resolveScreen()` already
  prefers the real notch over every external monitor.
- **Hidden means undrawn, not gone.** The panel still opens when the pointer
  reaches the top middle of that display, with the same dwell and haptic. It is
  `ContentView.panelOpacity` (0 while hidden and shut) rather than a branch in the
  hierarchy, because the silhouette has to stay in the tree to report animated
  geometry to `NotchHitRegion`.
- **Nothing is claimed while undrawn** — `activeRect` is `.zero` there, so clicks
  in the middle of that menu bar go to the app behind. Measured: with the strip
  hidden the window server does not even consult our `hitTest`, because the window
  is fully transparent at that point.
- **`NotchHoverDetector`** (new, `Sources/tempo/Services/`) is one `.mouseMoved`
  global monitor, installed only in that mode, that writes
  `state.isPointerNearNotch` into the existing hover path. Costs 0.2ms per event
  while the pointer moves and nothing while it is still.
- **Re-opening Tempo from Finder now opens Settings** (`applicationShouldHandleReopen`) —
  added as 054's escape hatch, kept because it is the right behaviour anyway.
- Caught in review-by-running (054, since removed): `@Published` fires from
  `willSet`, so a sink that re-reads the property sees the *old* value and the
  panel lagged one toggle behind the checkbox. Use the emitted value.

### 2026-08-24 — expanded panel was being clipped (decision 053)

- **`NotchGeometry.panelHeight` 280 → 600.** The window is never resized, so
  that constant is a hard clip on the drawn panel, not a scroll: everything the
  expanded content laid out below 280pt was outside the window and was not
  drawn. 280 dates from the scaffold, when the panel held only the now-playing
  header; the progress bar, output row, file shelf, usage graphs and agent rows
  added since then run past it. Measured live from the running bundle (a
  temporary `tempoDebug` in `reportExpandedHeight` plus a scripted hover): the
  output row + usage graphs + agent rows alone are 233pt including the strip;
  the sections that were off screen at that moment add ~290pt more. The panel is
  still content-sized — only the ceiling moved — so every state that already
  fitted looks identical.

### 2026-08-22 — four features from the Sapphire feature review (decisions 049–052)

- **Now-playing for every player, not just Spotify (049).** The private
  MediaRemote framework, reached through an entitled `/usr/bin/perl` loading a
  vendored BSD-licensed adapter (`Vendor/mediaremote-adapter`, built by
  `scripts/build-media-adapter.sh`, bundled by `make-app.sh`). Verified live on
  macOS 26.6.1 before any code was written: real metadata from Chrome *and*
  Spotify, play/pause tracked within half a second, and external seeks pushed
  with a fresh anchor. `MusicService` shrank 557 → ~130 lines and now supplies
  only the Spotify track URI that add-to-playlist needs. **Decision 041's 1Hz
  reconciliation poll was deleted** — the stream reports external seeks, so an
  open panel now costs zero timers.
- **Audio output row (050).** Output-device chips, volume and mute through the
  Core Audio HAL. Tempo deliberately never joins the render path. Uncovered
  and worked around a real bug: `AudioObjectAddPropertyListenerBlock` cannot be
  removed from Swift (measured: listeners still fired after removal), so all
  listeners use the C-proc API.
- **File shelf (051).** Global drag detection via the drag pasteboard's change
  count — verified to need **no** permission — opens the panel as a drop target
  ~80pt out from the pill, with the activation region re-read per event so it
  follows the notch across displays. Dropped files are copied into Application
  Support with a JSON index; items drag back out.
- **Bluetooth notices (052) — built but dormant.** `IOBluetooth` blocks forever
  in this process because CoreBluetooth never powers on for it (reproduced
  across five signing/launch configurations, no TCC prompt ever shown). The
  service is confined to a dedicated thread so it cannot freeze Tempo, and is
  not wired to any UI.

- **2026-08-22** — **Token and timing figures on the agent rows (decision 048).**
  The rows said which sessions were alive and what each was doing, but nothing
  about cost or pace. AgentStatus's status files carry no such fields (verified
  against the installed writer), so the figures come from Claude Code's own
  transcripts at `~/.claude/projects/<slug>/<session_id>.jsonl` — same session
  id, read-only, numbers and timestamps only. New `SessionStatsService` publishes
  `AppState.sessionStats`; each row gained a right-aligned
  **context · spend · turn length** cluster (`125k · 581k · 2m14s`), the turn
  length counting up live on a 1Hz `TimelineView` while a turn runs.
  Transcripts reach 2.4MB here, so a poll reads only the bytes appended since
  the last one, leaves a mid-append fragment for the next poll, and resets its
  totals if the file was rewritten shorter. Context is absolute, never a
  percentage: the transcript does not record which context window a session was
  opened with, and one session here peaked at 460,201 tokens. No dollar figure —
  Claude Code records no cost, so any number would be invented. Gated on a new
  Settings ▸ Modules toggle (`showAgentStats`) together with the lights: off
  stops the service and drops every cursor, so no transcript is opened at all.
  New `scripts/test-session-stats.sh` (11 checks, all passing) covers subagent
  exclusion, incremental append, a mid-append fragment and a rewritten file;
  cross-checked against a live transcript, where the service and an independent
  computation agreed exactly.

- **2026-08-22** — **Agent rows sort attention-first (decision 047).** The row
  sort ranked on the `state` string alone, and a finished turn is `idle` — so the
  white "finished, not yet seen" row sat below every running session, out of the
  three rows the panel shows without scrolling. `AgentStatusService.sort` now
  ranks the session rather than its state: blocked/error, then an unacknowledged
  finish (`justFinished || unread`, the same pair the pill reads), then running,
  then idle. The collapsed pill and the first row now always point at the same
  session. `scripts/test-agent-lights.sh` is up to 31 checks, all passing.

- **2026-08-22** — **The panel-style picker previews itself (decision 046).**
  Settings ▸ General's *Expanded panel* row was four names in a menu; three of
  the four styles differ only in translucency, so choosing meant closing
  Settings and hovering the notch, once per style. It is now four selectable
  miniatures (`Views/PanelStylePreview.swift`) drawn with the panel's own layer
  stack — `NotchShape`, substrate, the same `Glass` switch, clear-glass scrim,
  black top blend, rim — over a synthetic desktop gradient, which is what makes
  a translucent material legible in an opaque Settings window. The **Album
  tint** card uses the live `AppState.artworkTint`, so `SettingsView` now takes
  `AppState` (a plain `let`, tracked through `objectWillChange` — Settings must
  not redraw on every playback publish).

- **2026-08-22** — **One finish, one light (decision 045).** Reported live: after
  clicking a row, the panel's dot went grey while the pill above it kept pulsing
  white. The two surfaces were reading different flags for the same event — the
  row `unread` (durable, cleared by the click), the pill `justFinished` (a 20s
  window off the running → idle transition) — so a click cleared one and not the
  other, and a finish older than 20s had the mirror-image problem. Now: the pill's
  white dot is **steady** (only blocked pulses; finished keeps its halo without
  moving), `AgentSummary.finished` reads `justFinished || unread`, and
  acknowledging a row clears both flags with the poll no longer re-raising the
  transient one for a finish already seen. `scripts/test-agent-lights.sh` is up to
  30 checks, all passing.

- **2026-08-22** — **White unread light in the expanded panel (decision 044).**
  The panel's rows drew the same grey dot for a session that had just finished a
  turn and one idle since breakfast; only the collapsed pill said anything, and
  only for 20 seconds. Rows now show a **steady white** light for a finished turn
  nobody has looked at, cleared by the click that already goes to the session
  (keyed to that finish, so the next one re-lights it). The signal is the status
  file's own `detail` — `Stop` writes the wrap-up message, `SessionStart` forces
  it empty, so *idle + non-empty detail* is a durable, restart-proof "there is
  output to review". Only its **emptiness** is read; the message is never decoded
  (Agent Guideline #5). An interrupted turn (decision 043) is explicitly not
  unread — its `detail` is the cancelled tool call, not a wrap-up. The collapsed
  pill kept 042's transient dot at the time — superseded by decision 045, which
  made the pill read this light too. Covered by
  `scripts/test-agent-lights.sh` (24 checks then, 30 now) and confirmed live.

- **2026-08-22** — **Lights reconcile against Claude Code's own view
  (decision 043).** Reported live: a session interrupted mid-turn went grey on
  AgentStatus's lightbar and stayed green in Tempo. Root cause: AgentStatus's
  status files record hook *events*, and the hook's only route to `idle` is a
  `Stop` event — so an interrupted turn leaves `"state":"running"` on disk
  forever. AgentStatus corrects this in its own backend (its decisions 067 /
  063 / 084) **in memory**, never writing it back, so Tempo — reading the raw
  file — never saw it. `AgentStatusService` now reads two more sources,
  read-only: `~/.claude/sessions/<pid>.json` (an interrupted turn greys its
  light) and `claude agents --json` (a background job's light reads green while
  it works, orange while it waits on an answer). Guards ported intact: positive
  evidence only, the answer must be from a strictly later second than the hook
  event, background jobs excluded from the grey. A reconciled grey does not
  raise decision 042's "just finished" dot — an interrupted turn produced no
  output to review. The `claude agents --json` subprocess (~0.3s CPU/call) is
  gated on a CLI session whose own record does not say `"kind":"interactive"`,
  so a machine running only interactive sessions never spawns it: 12s of
  polling measured 0.02s CPU with no spawn. Verified by
  `scripts/test-agent-lights.sh` — 15 checks against the shipped service
  file with only its directories redirected — plus live schema confirmation on
  Claude Code 2.1.239/2.1.240.

  **Known gaps left open** (not required by the reported symptom, both logged
  in decision 043): Tempo does not port AgentStatus's *prune* rules (dead pid,
  closed IDE window, gone `cwd`, quit Cursor) — those delete the status file,
  so Tempo inherits them while AgentStatus is running, and falls back to its own
  2-hour staleness drop when it is not. Tempo also does not port AgentStatus's
  Cursor reconciliation (#048/#052), so a Cursor subagent still draws a light of
  its own instead of folding into its parent's row.

- **2026-08-22** — **Agent light in the collapsed pill (decision 042).** The
  agent signal no longer requires expanding the notch. A slot outboard of the
  visualizer holds either a summary dot (default) or up to three per-session
  dots, chosen in Settings ▸ Modules ▸ Agent light; the slot is mirrored by an
  empty one on the leading side so the notch gap stays registered to the
  hardware notch. Adds a derived **just finished** state — `AgentStatusService`
  now remembers each session's previous state across polls and flags a
  `running -> idle` transition for 20s as a pulsing white dot, since AgentStatus
  itself writes nothing that distinguishes "done" from "idle for an hour". The
  light deliberately survives the decision-038 media retraction. Builds clean;
  verified against the two live session files on this machine (one idle, one
  running). **Unverified visually** — see "Now".

- **2026-08-22** — **Progress bar with seek (decision 041).** Full-width
  scrubber in the expanded panel. Verified live against Spotify 1.2.95.453
  before writing code: `player position` is seconds, `duration` is
  **milliseconds** (the `.sdef` says seconds and is wrong), `set player
  position` works, the `PlaybackStateChanged` payload already carries both —
  and a seek posts **no** notification, which is why reconciliation exists at
  all. Position is an anchor the view extrapolates from (no per-frame
  publishes); the 1Hz reconcile runs only while the panel is open. Uncovered
  and fixed an intermittent bug where `set player position` returns before
  Spotify's player actually moves, so the immediate read-back undid the seek
  on screen — now a 0.5s settle window, 8/8 seeks with 0.00s deviation.

- **2026-08-22** — **Agent rows carry a task description (decision 040).**
  `AgentSession.task` is parsed from the status file's `task` field and
  rendered beside the folder label; `AgentLightsView` became a vertical
  scrolling list capped at three visible 28pt rows instead of a horizontal pill
  strip. Narrows Agent Guideline #5 at the user's explicit request — `task` is
  displayed only, `detail` stays undecoded, nothing is logged or written.
  Builds clean; the multi-session layout is unverified visually (one session
  existed on this machine).

- **2026-08-22** — **Visualizer no longer dances on a muted Mac (decision
  039).** A `CATapDescription` process tap captures Spotify's stream upstream
  of the output device's volume and mute, so muting was invisible to it —
  reproduced with the tap instrumented: `live=1 rawPeak=0.633` on a silent
  machine. `AudioTapService.outputAudible` (mute + virtual main volume on the
  default output device, listener-driven, fails open) now gates both reactive
  mode and the fallback animation, and becoming audible restarts the pump
  since un-muting creates no silence→sound edge for the audio thread to signal
  on. Verified live across muted / volume-0 / volume-4 / muted again. Also
  added `DebugLog.swift`: stderr diagnostics, silent unless `TEMPO_DEBUG_VIZ=1`
  (`open --env TEMPO_DEBUG_VIZ=1 --stderr <file> dist/Tempo.app`).

- **2026-08-22** — **Media UI hides when nothing has played for a minute
  (decision 038).** The pill used to carry a grey artwork placeholder and five
  frozen visualizer bars forever whenever Spotify was paused, quit, or never
  launched. Now `AppState.isMediaActive` (owned by `MusicService`, one one-shot
  60s timer armed whenever playback is not playing) gates the cover, the
  visualizer, the expanded panel's transport row and playlist picker; the
  collapsed pill shrinks from `pillWidth` to `notchWidth`, so at rest Tempo is
  exactly the hardware notch. `NotchHitRegion`'s collapsed floor dropped to
  `notchWidth` to match — left at `pillWidth` the panel would have kept
  claiming the retracted wings' clicks beside the menu bar. Builds clean;
  **not yet observed at runtime** (see Now).

- **2026-08-22** — **Panel now follows the displays (decision 037).** Fixes the
  panel drawing in the wrong place with an external monitor attached.
  `NotchGeometry` resolved the target screen, notch size, and screen frame into
  `static let`s evaluated once at first access, and `NotchPanel` computed its
  window frame from that snapshot inside `init` — nothing observed
  `NSApplication.didChangeScreenParametersNotification`, so after any display
  change the window sat at coordinates for a layout that no longer existed (and,
  since `panelWidth`/`pillWidth` derive from the notch width, potentially at the
  wrong size). Geometry is now re-read on every screen-parameters notification,
  the window re-framed, and the SwiftUI content re-laid out via a new
  `AppState.screenGeneration`; a 750ms settle re-check covers macOS posting the
  notification before `safeAreaInsets` have caught up on lid-open. Target screen
  stays the built-in notched display, falling back to the menu-bar display
  (`screens[0]`, not `NSScreen.main` — Tempo has no key window) with the
  unchanged 200×32 top-centre strip in clamshell.

- **2026-08-21** — **Lock-screen pill attempted and rejected (decision 036).**
  Asked for as "show the bar when I'm logged out". Built it — a lock-tracking
  service plus an above-the-shield window level — and it worked exactly as
  designed at the window-server level and still could not be seen. Measured:
  `loginwindow`'s lock-screen windows are at levels 2001/2004, Tempo sat at
  2147483629 above them and stayed in the on-screen window list the whole time
  locked, yet a four-level probe (1000 / 2002 / 2005 / 2147483629, opaque
  full-colour strips) was **invisible at every level**. macOS composites the
  lock screen in a context that excludes user-session windows, so no window
  level reaches it. All code reverted; `DECISIONS.md` 036 keeps the measurement
  so nobody tries it twice.

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

# NEXT_STEPS.md — Living Build Queue

> Read this at the start of every session to pick up where the last one left off.
> Update it at the end of every session where anything changed (Agent Guideline #10).

---

## Current state

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

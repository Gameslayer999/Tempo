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
| 002 | 2026-08-19 | Music signal & transport: AppleScript to the Spotify desktop app (not the private MediaRemote framework) | Amended by 015, reversed by 049 |
| 003 | 2026-08-19 | Add-to-playlist: Spotify Web API with OAuth 2.0 PKCE, user-supplied Client ID, loopback redirect | Accepted |
| 004 | 2026-08-19 | Visualizer v1: playback-synced animated bars (no system-audio capture) | Superseded by 016 (kept as fallback) |
| 005 | 2026-08-19 | AgentStatus integration: read-only consumer of AgentStatus's existing status files; Tempo installs no hooks | Accepted |
| 006 | 2026-08-19 | Window: non-activating borderless NSPanel hugging the physical notch; click toggles collapsed/expanded | Amended by 013 |
| 007 | 2026-08-19 | Repository: private GitHub repo `Gameslayer999/Tempo`; v1 scope is Spotify-only | Privacy reversed by 102; Spotify-only reversed by 049 |
| 008 | 2026-08-19 | Panel sizing: one static NSPanel at expanded size; SwiftUI animates content; custom `hitTest` passthrough outside the drawn shape | Amended by 012 |
| 009 | 2026-08-19 | Hover-grow: strip expands ~10×4pt on hover (boringNotch-style spring); passthrough rect is always the hover-grown size so flicker is structurally impossible | Revised by 011 |
| 010 | 2026-08-19 | Liquid Glass: expanded panel uses macOS 26 `glassEffect` (`.ultraThinMaterial` fallback) with a black-to-glass top gradient; collapsed strip stays pure black | Accepted |
| 011 | 2026-08-19 | Interaction model: hover fully expands (transient) with a haptic tick; click pins; click outside unpins — revises 009 | Amended by 014 |
| 012 | 2026-08-20 | Click-fallthrough fix: hit region tracks the live animating shape geometry, not the expanded/collapsed flag — amends 008 | Accepted |
| 013 | 2026-08-20 | Geometry: Dynamic-Island collapsed pill (notch + content-fit wings, concave-top NotchShape); expanded panel is content-sized — amends 006 | Amended by 019 |
| 014 | 2026-08-20 | Motion & control polish: boringNotch spring constants, 0.25s hover dwell, Reduce Motion fades, HIG 28pt targets + press states, semantic colors — amends 011 | Accepted |
| 015 | 2026-08-20 | Spotify signal delivery: event-driven via `PlaybackStateChanged` distributed notification; 1s AppleScript poll removed — amends 002 | Accepted |
| 016 | 2026-08-20 | Real audio-reactive visualizer: Core Audio per-process tap on Spotify + 5-band vDSP FFT; 004's animation kept as silent fallback — supersedes 004 | Amended by 056 |
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
| 036 | 2026-08-21 | Notch on the lock screen: **not possible** from an app — macOS composites the lock screen in a context that excludes user-session windows at every level | **Rejected** (built, measured, reverted); its surviving conclusion is taken up by 058 |
| 037 | 2026-08-22 | Notch geometry is re-read on every display change and the panel re-framed; the target stays the built-in notched screen, falling back to the menu-bar display when the lid is shut | Accepted |
| 038 | 2026-08-22 | The media UI (cover, visualizer, transport, playlist) hides after 60s with nothing playing, and the collapsed pill shrinks to the bare notch — amends 013 | Accepted |
| 039 | 2026-08-22 | The visualizer settles when the output device is muted or at zero volume: a process tap is taken before device volume, so muting was invisible to it — amends 016 | Accepted |
| 040 | 2026-08-22 | Agent rows show the session's `task` excerpt beside the label and stack vertically: the folder label alone can't tell two sessions in one repo apart — amends 005, narrows Guideline #5 | Accepted |
| 041 | 2026-08-22 | Scrubbable progress bar in the expanded panel: position is an extrapolated *anchor*, reconciled at 1Hz only while the panel is open, and seeks are optimistic with a 0.5s settle window — amends 015 | Accepted |
| 042 | 2026-08-22 | The collapsed pill carries an agent light outboard of the visualizer — a summary dot by default, switchable in Settings — with a derived "just finished" state, mirrored slot geometry, and no dependence on media being active — amends 005/038 | Accepted |
| 043 | 2026-08-22 | Lights reconcile against Claude Code's own view: an interrupted turn greys, a background job's light says what Claude Code says — reads `~/.claude/sessions` and `claude agents --json`, both read-only — amends 005 | Accepted |
| 044 | 2026-08-22 | The expanded panel's rows show a white **unread** light for a finished turn nobody has looked at, cleared by the click that goes to the session; derived from `detail`'s emptiness, kept out of the collapsed pill — amends 005/042 | Accepted |
| 045 | 2026-08-22 | One finish, one light: the collapsed pill's white dot stops pulsing and reads `unread` as well as `justFinished`, and acknowledging a row clears both flags — fixes a white pill over a grey row — amends 042/044 | Accepted |
| 046 | 2026-08-22 | The panel-style picker previews itself: four mini panels drawn in the real style over a synthetic desktop, replacing the text menu — amends 030 | Accepted |
| 047 | 2026-08-22 | The agent rows sort attention-first — blocked/error, then an unacknowledged finish, then running, then idle — so the three rows the panel shows without scrolling are the ones that want the user; matches the collapsed pill's precedence — amends 005/044 | Accepted |
| 048 | 2026-08-22 | Token and timing figures on the agent rows — context, spend and turn length read incrementally from Claude Code's own transcripts (read-only, numbers only, byte-cursored); context shown absolutely because the window size is not recorded; no dollar figure, because no cost is — amends 005 | Accepted |
| 049 | 2026-08-22 | Now-playing & transport move to the private MediaRemote framework via an entitled `/usr/bin/perl` trampoline, covering every player; Spotify AppleScript is kept only for the track URI add-to-playlist needs — amends 002/015/041 | Accepted |
| 050 | 2026-08-22 | Audio output: switch the default device and set its volume through the Core Audio HAL; Tempo never joins the render path (no aggregate devices, no per-app routing) — and listeners use the C-proc API, not the block API | Accepted |
| 051 | 2026-08-22 | File shelf: a global drag monitor opens the notch as a drop target when a dragged file comes near, and the shelf keeps a copy that can be dragged back out | Accepted |
| 052 | 2026-08-22 | Bluetooth connect/disconnect notices are built but dormant: IOBluetooth blocks forever on this machine because CoreBluetooth never powers on for the process, so the service is confined to a dedicated thread and left unwired | Deferred |
| 053 | 2026-08-24 | Expanded-panel height ceiling raised 280 -> 600: the window is never resized, so the ceiling is a hard clip, and the sections added since the scaffold ran past it | Accepted |
| 054 | 2026-08-24 | "Show on external displays" hides Tempo entirely when the display it would hug has no hardware notch; the panel is ordered out, and re-opening Tempo from Finder opens Settings so the switch is never a trap | Amended by 055 |
| 055 | 2026-08-24 | The switch hides the *strip*, not Tempo: on a notchless display the collapsed pill is undrawn and claims no clicks, and a global pointer monitor opens the panel when the cursor reaches the top middle | Accepted |
| 056 | 2026-08-24 | The visualizer taps **all** system audio with a global Core Audio tap instead of only Spotify's process, and the collapsed strip grows a visualizer-only wing when audio plays with no now-playing card behind it | Accepted |
| 057 | 2026-08-24 | First run plays a cursive **hello** that writes itself out of the notch, then setup rows for the permissions Tempo needs; one `isOnboarding` flag folded into `displayedExpanded` reuses the whole panel-open machinery | Accepted |
| 058 | 2026-08-24 | Weather and now-playing reach the lock screen as **two system notifications**, posted on lock, replaced in place while locked, withdrawn on unlock — the only surface decision 036 left available | Accepted |
| 059 | 2026-08-24 | Weather data comes from **Open-Meteo** (no key, no account — WeatherKit needs a Team ID this ad-hoc-signed app does not have), located by reduced-accuracy CoreLocation with a typed city as the fallback | Accepted |
| 060 | 2026-08-25 | The lock-screen cards ask for notification permission when the feature is switched on, record a refusal instead of swallowing it, re-read the grant on every activation, and post at `.active` rather than `.passive`; the cursive `hello` is re-drawn on Palmer-method letterforms and hands off to the setup cards through a fade rather than a cut | Accepted |
| 061 | 2026-08-25 | The `hello` uses **Apple's own lettering** — its published centreline SVG, drawn as two arc-length-weighted subpaths in sequence — instead of hand-authored curves, which were 1.5:1 where Apple's is 3.36:1 | Accepted |
| 062 | 2026-08-26 | HIG pass across every surface: one typography/metrics/state-appearance vocabulary (`NotchStyle.swift`), Reduce Transparency and Increase Contrast honoured, agent states told apart by shape as well as colour, sub-28pt hit targets raised, per-glyph text shadows replaced by one scrim, Reduce Motion path for the visualizer | Accepted |
| 063 | 2026-08-26 | The expanded panel is regrouped into a media block and a system block, separated by a wider gap and a hairline; the playlist row moves out of the header column to full width, which lets the cover sit at its 72pt floor; panel ceiling raised 600 → 680 | Accepted |
| 064 | 2026-08-26 | Album tint is **painted**, not delegated to `Glass.tint`: `glassEffect` contributes no pixels to the view's render tree, so the tint is drawn as a hue-preserving, brightness-capped wash over the glass — shared by the panel and its Settings preview, and working below macOS 26 where `.tinted` was previously identical to plain glass | Accepted |
| 065 | 2026-08-27 | The black silhouette is not drawn where there is no notch to merge with (it was fading a black slab over someone else's menu bar on a notchless display), and the panel's own alpha moves out of the collapse spring's scope onto a short `easeOut` — the critically damped spring's tail was leaving a dim ghost for about half a second after the retract finished | Accepted |
| 066 | 2026-08-27 | **Quit Tempo** is a button in Settings ▸ About, not a menu-bar extra and not a control in the panel: `LSUIElement` left ⌘Q reachable only while the Settings window was key, so the app had no findable way out | Accepted |
| 067 | 2026-08-27 | SIGTERM and SIGINT are routed through `NSApplication.terminate` by a dispatch signal source, so `applicationWillTerminate` runs and the MediaRemote child is reaped — AppKit turns neither signal into a quit, and every rebuild was orphaning an adapter. The source must be on a global queue: on `.main` it never fires in this app, leaving Tempo immune to SIGTERM instead | Accepted |
| 068 | 2026-08-27 | SIGKILL cannot be caught, so the orphan is caught on the *next* launch instead: `reapOrphanedStreams` compares the adapter path **case-insensitively**, because `Bundle.main.resourcePath` keeps the spelling the bundle was reached through and an exact compare had been skipping every orphan left by a directly-exec'd Tempo. The duplicate backstop added to `make-app.sh` in 067 is removed | Accepted |
| 069 | 2026-08-27 | Accent colour: system accent or a custom pick, floored on WCAG **relative luminance** (not HSB brightness — `#0000FF` is already brightness 1.0 and still invisible) by mixing toward white; all eight macOS system accents already clear the floor, so the default passes through unchanged. Never reaches the agent lights, whose hues carry state | Accepted |
| 070 | 2026-08-27 | Album glow and blur are two independent switches behind the cover, **painted** as real fills and blurs rather than expressed as a material hint — decision 064 measured that `glassEffect` contributes no pixels. Expanded header only: in the collapsed pill the bloom would spill past the black silhouette | Accepted |
| 071 | 2026-08-27 | Coloured spectrogram: four palettes over the five band magnitudes the tap already publishes. Hue follows the **band**, not the bar position, so warm sits in the centre with the bass and cools outward, matching `barToBand`. `.monochrome` is the default and is pixel-identical to the flat white it replaced | Accepted |
| 072 | 2026-08-27 | Sneak peek: a track change flashes title and artist under the notch without expanding. Draws in the transparent part of the window below the pill and claims no clicks — the window's hit region is the drawn silhouette only. Suppressed while the panel is open, where it would repeat what is already on screen | Accepted |
| 073 | 2026-08-27 | The media inactivity timeout becomes a setting instead of a hard-coded 60s constant — the right value was always a matter of taste. Default is still 60s so an install that never touches the slider is unchanged; 0 means never drop the media UI | Accepted |
| 074 | 2026-08-27 | Transport row is data-driven over five slots, drag-and-drop **and** menu-editable. Palette is limited to actions Tempo can actually perform (previous / play-pause / next / mute); add-to-playlist is excluded because it needs a target playlist owned by `PlaylistSection`. Empty slots are dropped from layout, not rendered zero-width, so the default row is byte-identical to the hard-coded one | Accepted |
| 075 | 2026-08-27 | The strip can be pinned to a display, identified by `CGDisplayCreateUUIDFromDisplayID` rather than by `CGDirectDisplayID` (reassigned across reconnects). A pin to a detached display falls through to the automatic order. `applyGeometry(force:)` bypasses the value-equality check, which two identical monitors would otherwise defeat | Accepted |
| 076 | 2026-08-27 | Full-screen behaviour is a three-way choice. `.fullScreenAuxiliary` is dropped from the collection behaviour for "hide for all apps"; the per-app case additionally orders the window out, because a Space that is already full screen does not re-evaluate collection behaviour on its own. Detected from `visibleFrame` vs `frame`, needing no private API and no Accessibility grant | Accepted |
| 077 | 2026-08-27 | `sharingType = .none` excludes the panel from screen capture and sharing. A window-server flag, so unlike the glass tint of 064 it cannot be defeated by a compositing path — agent lights and `cwd` labels are exactly what should not land in a screen share | Accepted |
| 078 | 2026-08-27 | Showing the pill on the lock screen or screen saver: **rejected again**, confirming 036. `sysadminctl -screenLock status` reports the lock delay on this machine is immediate, so the screen saver *is* the lock screen here and inherits the secure context 036 measured windows out of at every level. The setting was written and then removed rather than shipped as a control that could not work | **Rejected** |
| 079 | 2026-08-27 | Token history and an **estimated** five-hour pace bar, read from Claude Code's transcripts — not from `~/.claude/stats-cache.json`, which measured 10 days stale with every `costUSD` zero. Counts input + cache-creation + output and excludes cache reads, matching `SessionStatsService`; counting cache reads would have made every figure meaningless (175M of 180M on one real day). Claude Code persists no real rate-limit signal locally, so the budget is user-set and the word "estimate" is on the surface | Accepted |
| 080 | 2026-08-27 | Settings restructured from five panes to eight — Appearance, Displays and Agents split out — so every new knob has an obvious home rather than extending Modules into a catch-all | Accepted |
| 081 | 2026-08-27 | The sneak peek was inside `panelOpacity`'s scope, so it rendered at alpha 0 in clamshell with the strip hidden — the one configuration it was reported missing from. Moved outside it. Separately, the notification calls gain a 4s timeout: `notificationSettings()` was measured never returning under an ad-hoc signature, leaking a task per Settings-open and leaving the UI reporting a state that was not true | Accepted |
| 082 | 2026-08-27 | The collapse on a **notched** Mac left the expanded content and the glass at full panel size, fading over the desktop after the pill was already back in the notch — a removed SwiftUI subtree keeps the size it had and does not follow the frame inward. Fixed by clipping the panel to its own retracting shape, with the rim light moved outside that clip. Curve changes were tried and reverted: `.animation(_:value:)` on the silhouette scopes the incoming geometry too, and retracted the pill faster than the panel it backs | Accepted |
| 083 | 2026-08-27 | Settings sidebar icons become System-Settings-style tiles: the glyph in white on a rounded rect filled with a per-pane colour, rather than eight monochrome symbols. Colour is the fastest way to find a row in a fixed list, and the colours echo what each pane controls (green for Agents, sky blue for Weather) | Accepted |
| 084 | 2026-08-27 | The track-change sneak peek is drawn in Liquid Glass (`glassEffect(.regular)`) instead of a flat black plate with a hairline stroke, so it reads as one of the system's own transient HUDs — the AirPods and volume indicators it appears beside. Untinted and independent of `panelStyle`, because those HUDs are neutral and an album tint would recolour the peek on every track. The plate survives as the fallback for macOS 14/15, Reduce Transparency and the Solid panel style | Accepted |
| 085 | 2026-08-27 | Clicking an agent light landed on the wrong session: a Ghostty surface is matched by Claude's `ai-title`, which a session does not have until its first turn ends, and an unmatched session fell through to fronting the Ghostty *app* — whichever window was last used, on whatever Space that is. Added a second grade of match on Ghostty's per-surface `working directory`, with surfaces claimed by another live session's title struck out, acted on only when a single surface survives | Accepted |
| 086 | 2026-08-27 | The sneak peek gets a rim light of its own — 1.5pt white at 0.28, stroked over the glass as well as over the fallback plate. Partly reverses 084's "glass draws its own rim, so the hairline goes": it does, but a rim built from what is behind the window vanishes against a bright wallpaper, which is exactly where a floating capsule most needs an edge | Accepted |
| 087 | 2026-08-27 | A session's Ghostty surface was unreachable by title once its transcript passed 16MB: `claudeSessionTitle` skipped any file over that cap outright, so the longest-running session on the machine (22MB) fell through to fronting the Ghostty app. The cap is replaced by a backward line scan over the memory-mapped file that stops at the last `ai-title` record — 19KB from the end on that transcript, under 1ms | Accepted |
| 088 | 2026-08-27 | The shelf's remove button flickered under the pointer: it was offset outside the chip that tracked hover and mounted only while hovered, so reaching for it ended hover, unmounted it, and restored hover — a loop that also sent stray clicks to the chip's drag. It now sits inside the chip, stays mounted, and fades on hover | Accepted |
| 089 | 2026-08-27 | The pointer becomes a hand over Tempo's own controls, which draw no chrome at rest — the cursor is the only "this is clickable" cue that arrives before the hover highlight. `pointerStyle(.link)` on macOS 15+, a push/pop fallback that unwinds on disappear below it. Settings' standard AppKit controls and onboarding's intentionally-invisible skip target are excluded | Accepted |
| 090 | 2026-09-04 | The undrawn strip's hover target on an external display shrank from the full invisible pill (pillWidth x 32pt) to a 200x3pt band pressed against the top edge of the screen, so Tempo opens on the same gesture that drops a hidden menu bar rather than whenever the pointer passes near the top of the display | Accepted |
| 091 | 2026-09-04 | The undrawn strip will not open unless the menu bar is fully down. There is no API for that state — `visibleFrame` does not move when the bar auto-reveals — so Tempo reads the window of a zero-length status item, which rides the bar and slides with it, created only in that one mode. A full-screen tab strip at the top edge no longer trips the notch | Accepted |
| 092 | 2026-09-04 | The real cause of the panel opening at a full-screen browser's tab strip: `.onHover` fires even where `hitTest` returns nil, because tracking areas ignore hit-testing. Decision 055 assumed otherwise, so the hidden strip had two live hover paths and the unrestricted one — the pill's whole 308x32pt rect — was doing the opening. `.onHover` is now ignored in that mode; the pointer monitor owns it | Accepted |
| 093 | 2026-09-04 | The undrawn strip's edge push gets its own **Edge hold** setting (Settings ▸ Displays ▸ Placement, 0–150ms after 094 trimmed the ceiling, default 60) rather than sharing the pill's 0–400ms hover delay: pushing into a screen edge is a deliberate gesture with a different right answer than brushing a drawn pill, and it is the one the user needs to tune | Accepted |
| 094 | 2026-09-04 | Every Settings slider's value is now a text field you can type into — units optional, `Never` and `2.5M` understood, clamped to the range but never snapped to the step, since typing exists to reach what lies between steps. Edge hold's ceiling cut from 1500ms to 150ms: nothing past it is a hold anyone would choose | Accepted |
| 095 | 2026-09-04 | The undrawn strip's target grows from decision 090's 3pt edge band to the menu bar's own row (measured at 30pt, not the 22pt `NSStatusBar` reports): 3pt was too tight to hold, so relaxing the pointer after the bar dropped cancelled the dwell or collapsed the panel a frame after it opened. Safe because the menu-bar gate, not the height, is what keeps it from firing | Accepted |
| 096 | 2026-09-07 | The topmost row of the display was outside every pointer-tested region: they are top-anchored rects whose `maxY` is `screen.maxY`, and `NSRect.contains` excludes `maxY` — the exact coordinate a pointer shoved into the edge reports. All three now go through `topAnchoredRegion`, one point taller, overshooting above the screen | Accepted |
| 097 | 2026-09-16 | Add-to-playlist moves from the retired `POST /playlists/{id}/tracks` to `POST /playlists/{id}/items`: Spotify's Feb/Mar 2026 Web API migration retired the `/tracks` path, which now answers a bare 403 `Forbidden` for every caller, including the user's own playlists. Separately, a 403 detail that only restates the status is no longer echoed to the user — it was rendering as the single word "Forbidden" | Accepted |
| 098 | 2026-09-16 | `swift build` is routed through `scripts/select-sdk.sh`, which probes each installed SDK with a five-line `@State` file and builds against the newest one that actually compiles — the macOS 27 SDK's `@State` is a macro needing a `SwiftUIMacros` plugin that ships only inside Xcode, so the Command Line Tools 27.0 update broke the build outright. The chosen SDK is also copied once to `~/Library/Developer/Tempo/SDKs`, out of the installer's reach | Accepted |
| 099 | 2026-09-16 | Pausing one player out of several: the audible set comes from the Core Audio HAL's process list, and a pause is routed per app — AppleScript by name for music apps, MediaRemote for whoever holds now-playing. The panel lists them whenever two are playing; an opt-in switch pauses the previous player automatically when a new one takes over | Accepted |
| 100 | 2026-09-16 | A session finishing a turn raises the same card a track change does — folder, task line and a white check, five seconds, under the collapsed notch. The event is published from the one place the running -> idle *transition* exists (`markFinished`), not derived from the `justFinished` flag that follows it, which is a 20-second state and would re-announce on every poll. The two peeks share one slot, because two cards drawn in the same place would overlap. Toggle in Settings ▸ Agents, on by default | Accepted |
| 101 | 2026-09-16 | The agent list no longer scrolls inside three rows: it grows a row per session and the panel grows with it. The window height ceiling (`NotchGeometry.panelHeight`) stops being the constant 680 of decision 063 and becomes the target screen's height less a 24pt margin, so the growth has somewhere to go; the list keeps a cap derived from that ceiling purely so rows can never be laid out below the window, where they would not be drawn at all | Accepted |
| 102 | 2026-09-16 | Tempo goes public at **v0.4**, source-only, on a new tag — `v0.1`/`v0.2`/`v0.3` already existed as pushed milestone tags and `gh release list` was empty, so the missing thing was the Release, not the tag; moving `v0.1` would rewrite published history. No binary is attached because `make-app.sh` signs ad-hoc or Apple-Development and **never notarizes**, so a downloaded zip would be Gatekeeper-refused. Reverses the privacy half of 007 | Accepted |

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
  **Decision 058 took this route**: weather and now-playing are posted as two
  notifications on the lock edge. `ScreenLockService`, deleted here, was
  restored there — the lock *detection* measured correct on both edges and was
  thrown away with the drawing that did not work.

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

---

## 045 — One finish, one light: the pill's white dot goes steady and follows the row (amends 042, 044)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Two things about the white "finished" light were wrong in use.

**It pulsed.** Decision 042 gave the collapsed pill's just-finished dot the same
pulse as blocked. Sitting beside a moving visualizer, a second animated element
made the pill read as busy, and it blurred the one distinction motion is supposed
to carry: blocked is the state you have to act on, finished is only a state to
notice. Decision 044 had already settled this for the expanded row — steady white
there, explicitly "steady, not pulsing" — leaving the two surfaces disagreeing
about the same event.

**The two surfaces went out at different times.** They read different flags for
one event: the row reads `unread` (durable, cleared by the click), the pill reads
`justFinished` (a 20s window off the running → idle transition). So clicking a row
greyed the row and left the pill white above it for the rest of the window — the
observed bug — and, in the other direction, a finish older than 20s kept a white
row under a grey pill. 044 listed "make the pill's summary unread-based too" as a
deferred option, on the grounds that it changed 042's observable behaviour
(Guideline #7) and had not been asked for. It has now been asked for.

### Options considered

| Option | Verdict |
| --- | --- |
| **Pill reads `unread \|\| justFinished`; acknowledging clears both** | **Chosen** — one event, one light on both surfaces, and neither existing case is lost |
| Pill reads `unread` alone | Rejected — drops the white flash for a turn that ends with no wrap-up message, which 042's dot does cover today |
| Leave the flags apart, just suppress the pill for the window after a click | Rejected — patches the symptom and keeps two sources of truth for one event |
| Keep the pulse, fix only the desync | Rejected — the pulse is half of what was reported, and it contradicts 044's own reasoning |

### Decision

**The pill's white dot is steady, and the pill and the row read the same
finish.**

- **Only blocked pulses.** Motion in Tempo now means exactly one thing: this one
  wants you (UI Principle #5). Finished keeps its halo — a solid white dot with a
  steady glow — so it is still the second-most prominent thing in the pill without
  moving.
- **`AgentSummary.finished` reads `justFinished || unread`.** The transient flag
  covers a turn that ended with no wrap-up message; the durable one keeps the
  light on until the row is clicked. Both are the same event, so both light the
  same dot.
- **Acknowledging clears both flags.** The click that goes to a session clears
  `unread` *and* `justFinished`, and the poll no longer re-raises `justFinished`
  for a finish already acknowledged at that `updated_at`. Nothing about the
  acknowledgement record changes: still app-local, in-memory, never written, and
  still nothing is read from or written to `~/.claude/status/**` (Guideline #3).

### Implementation

- `SummaryDot` (`CollapsedAgentLight.swift`): `pulses` is `blocked` only; a new
  `glows` (`blocked || finished`) keeps the halo on the steady white dot.
- `AgentSummary.init` (`AppState.swift`): `.finished` when any session is
  `justFinished || unread`.
- `AppState.acknowledgeFinish(_:)`: takes a `justFinished` session too, and
  clears both flags on the spot.
- `AgentStatusService.markFinished(_:)`: skips (and drops) a `finishedAt` whose
  finish is already acknowledged at that `updated_at`.

### Verification

`scripts/test-agent-lights.sh` — 30 checks, all passing. New for this decision:
a clean finish lights the pill dot white; an `unread` session alone lights it too
(the case that used to go dark after 20s); acknowledging clears `justFinished`
with `unread`, takes the pill dot out with the row, and keeps it out across the
polls still inside the finished window.
---

## 046 — The panel-style picker shows the panel (amends 030)

**Date:** 2026-08-22 · **Status:** Accepted

**Context.** Decision 030 shipped the four panel materials behind a plain
`Picker` of four names plus a sentence of prose. The names are the problem:
"Regular glass" versus "Clear glass" versus "Album tint" is a distinction you
can only settle by choosing one, closing Settings, hovering the notch, and
going back — three of the four differ *only* in how translucent they are.
Requested: show what each one looks like at the point of choosing.

### Options

| Option | Verdict |
| --- | --- |
| **Four selectable mini panels, drawn in the real style over a synthetic desktop** | **Chosen** — the picker answers its own question, and the swatch is the same layer stack as the panel |
| Keep the menu, add a single large live preview of the current selection | Rejected — still one style at a time, so comparing two is the same round trip |
| Keep the menu, add screenshots of each style | Rejected — a bitmap can't carry the album tint or the current appearance, and it drifts from the panel the first time the panel changes |
| Live-apply on hover over the menu row | Rejected — flickers the real notch while the pointer crosses a menu, and it is invisible if the panel isn't on screen |

### Decision

**Each style is picked by clicking a miniature of the panel drawn in that
style** (`PanelStylePreview`, in the "Expanded panel" section of General).

- **Same layer stack as the panel.** The mini panel repeats
  `ContentView.backgroundShape` exactly — `NotchShape` silhouette, 0.05 black
  substrate, the same `glassLayer`/`Glass` switch, the clear-glass 0.22 scrim,
  the black top blend, the rim stroke masked off the top. Not an approximation
  of the panel's look: the same code path, so it cannot drift into showing a
  material the panel doesn't draw (UI Principle #4).
- **A synthetic desktop behind it, and it is load-bearing.** SwiftUI materials
  and `glassEffect` sample what is drawn behind them in the same window. Over
  the Settings window's flat background all three glass styles would look like
  the same grey fill, so each card draws a gradient (dark top-left, bright
  bottom-right) with an opaque white "window" over it. That is what makes
  regular and clear visibly different in the picker.
- **The real album tint, live.** The `.tinted` card uses `AppState.artworkTint`
  — the actual dominant colour of what is playing right now — and falls back to
  plain glass with no artwork, exactly as the panel does. `SettingsView` takes
  `AppState` as a plain `let`, not an `@ObservedObject`: Settings has no reason
  to redraw on every playback or session publish, so it tracks the one value it
  needs through `objectWillChange`.
- **Shorthand contents, never text.** Cover square, two title bars, three
  transport dots and a green/orange pair for the agent lights. At 104×74 real
  strings would be unreadable noise; the shapes are enough to read it as the
  panel.

### Implementation

- `Sources/tempo/Views/PanelStylePreview.swift` — new; the mini panel.
- `SettingsView.swift` — `GeneralPane` replaces the `Picker` with a row of four
  preview buttons; new `state: AppState` on `SettingsView`.
- `SettingsWindow.swift`, `AppDelegate.swift` — pass `AppState` through to
  Settings.

### Verification

Rendered all four styles at both tint states in a throwaway harness to check the
geometry and content, then in the running app: `swift build`, then
`scripts/make-app.sh`, and the picker checked against the panel it opens.

---

## 047 — The agent rows sort attention-first (amends 005, 044)

**Date:** 2026-08-22
**Status:** Accepted

### Context

The expanded panel shows three agent rows at once and scrolls the rest
(decision 040's cap, kept so a busy machine cannot grow the panel without
bound). Which three you get is decided by the row sort, and that sort ranked
sessions on the `state` string alone: blocked and error first, then running,
then idle.

A finished turn is idle. So the one row that most often wants the user — the
white "finished, and you haven't looked at it" light of decisions 044/045 — sat
in the idle bucket at the *bottom* of the list, below every running session.
On a machine with four or five sessions running, the finish that just landed
was off-screen until the user scrolled to it, which is exactly the signal the
white light exists to make un-missable (UI Principle #2). The collapsed pill
already got this right: `AgentSummary` ranks `finished` above `running`, so the
pill would go white and then send the user to a list where the row it was
telling them about was not visible.

### Options considered

| Option | Verdict |
| --- | --- |
| **Rank an unacknowledged finish above running, matching `AgentSummary`'s precedence** | **Chosen** — the pill and the list agree about what is most worth looking at, and the fix is in the one comparator that already owns row order |
| Raise the visible-row cap so everything fits | Rejected — trades a bounded panel for an unbounded one, and still buries the important row *within* the list on a busy machine |
| Pin attention rows outside the scroll view, scroll the rest under them | Rejected — two lists and a second layout for the same rows, to solve what an ordering change solves |
| Leave the order, mark scrolled-away attention rows on the scroll bar | Rejected — adds chrome to point at a row instead of just showing the row (UI Principle #1) |

### Decision

**Row order follows attention, in the same precedence the collapsed pill uses.**
`AgentStatusService.sort` now ranks the session, not just its state string:

| Rank | Rows |
| --- | --- |
| 0 | `blocked`, `error` — the user has to act |
| 1 | `idle` **and** (`justFinished` \|\| `unread`) — a finish nobody has acknowledged |
| 2 | `running` |
| 3 | plain `idle` |
| 4 | unrecognized states |

Alphabetical by label within a rank, then by id — unchanged. Both finish flags
are read, the same pair `AgentSummary.finished` reads (045), so the pill and the
first row can never be telling the user about different sessions.

Rows move when their rank changes: a finish jumps to the top, and the click that
acknowledges it drops it back into the idle group as the light goes out. That
movement is the feature — the list is ordered by what wants the user *now*.

### Implementation

- `AgentStatusService.sort(_:)`: `rank` takes an `AgentSession` instead of a
  `String`, so it can see the finish flags; ranks renumbered to open a slot
  between `blocked`/`error` and `running`.

Nothing else changed: `AgentLightsView` still draws whatever order it is handed,
the three-row cap stands, and no new state is read from `~/.claude/status/**`
(Guideline #3).

### Verification

`scripts/test-agent-lights.sh` — 31 checks, all passing. New for this decision:
a fixture of ten sessions (one blocked, two unacknowledged finishes, four
running, three idle) comes out of the service ordered blocked → finished →
running → idle, so the two finishes sit above the running sessions instead of
below them.

---

## 048 — Token and timing figures on the agent rows, read from Claude Code's transcripts (amends 005)

**Date:** 2026-08-22
**Status:** Accepted

### Context

The agent rows say *which* sessions are alive and *what* each is doing, but
nothing about their cost or pace. The two questions a glance at a row cannot
currently answer are "is this one about to run out of context?" and "has this
been stuck for two minutes or twenty?".

AgentStatus's status files cannot answer either. Verified against the installed
writer (Agent Guideline #4): a session file carries `state`, `cwd`, `ide`,
`pid`, `label`, `updated_at`, `task`, `detail` — no counts, no durations.

Claude Code keeps the numbers itself, in the transcript it writes for every
session at `~/.claude/projects/<slug>/<session_id>.jsonl`, keyed by the same
session id the status file is named after. Read on this machine (CC 2.1.240,
18 transcripts):

| Figure | Where it is |
| --- | --- |
| Context occupancy | an assistant entry's `usage`: `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` |
| Spend | the same entries' `input_tokens + cache_creation_input_tokens + output_tokens`, summed |
| Turn start | a `user` entry carrying `promptSource` — the unmarked ones are tool results |
| Turn length | a `system` entry with `"subtype":"turn_duration"` and `durationMs`, written at the turn boundary |

**Cost in dollars is not recorded anywhere** — no `costUSD`, no total. It could
only be produced by multiplying tokens against a price table that depends on the
user's plan and on how cache reads are billed, so Tempo would be publishing a
guess as a number. It is not shown.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Leave the rows as they are | no new data source | the two questions above stay unanswered |
| Ask `claude` for the figures | one source, already used for 043 | no such command exists; the listing carries no usage |
| Read the transcripts | the real numbers, same session id, no new permission | a second tree to read, and files that reach megabytes |

### Decision

**Read the transcripts**, in a `SessionStatsService` separate from
`AgentStatusService`, publishing `AppState.sessionStats` keyed by session id.
Each row gains a right-aligned cluster: **context · spend · turn length**.

Four things make that safe to do on a 2s poll:

1. **Incremental reads.** Transcripts are append-only and reach 2.4MB here, so
   a poll never re-reads one: each session keeps a byte offset and reads only
   what was appended (typically a few KB). A file shorter than its cursor was
   rewritten, so its totals reset with it rather than continuing from a file
   that no longer exists.
2. **Only complete lines are consumed.** A poll can land mid-append; the
   trailing fragment is left for the next poll to read whole rather than parsed
   truncated and dropped.
3. **Numbers only.** Usage counts, timestamps and `durationMs` are the only
   fields read out of a decoded line — never message content, prompt text or
   tool output, and nothing is stored or logged (Agent Guideline #5). A
   substring test in front of the JSON parse skips the tool-result lines
   entirely, which is most of a transcript.
4. **Off means off.** The figures are a Modules toggle
   (`Preferences.showAgentStats`), gated together with the lights themselves:
   switched off, the service stops and drops every cursor, so no transcript is
   opened at all — the same contract `SystemStatsService.stop()` has for the
   usage graph.

**Context is absolute (`125k`), never a percentage.** The transcript records the
model as `claude-opus-5` with no marker for which context window the session was
opened with, and a session on this machine peaked at **460,201 tokens** — a bar
scaled to 200k would have read "230% full". A number that cannot lie beats a
percentage that can (UI Principle #4).

**Context excludes subagents; spend includes them.** A subagent runs its own
window, so counting its messages into the context figure would make the number
jump on every fan-out — but its tokens are still this session's spend.

The cluster is unlabelled. Three labels cost more width than the panel's 368pt
of content has, and would out-shout the task text beside them (UI Principle #1);
the two token counts are told apart by weight — the live one is brighter — and
the row's tooltip names all three.

### Reasoning

Everything needed is already on disk, written by the tool whose sessions the
lights are about, under a session id Tempo already has. The alternative is no
answer at all. The read is bounded by a byte cursor rather than by file size, it
is read-only on a tree Tempo does not own (Agent Guideline #3), and it decodes
strictly less about a session than the `task` excerpt the row already renders.

Verified by `scripts/test-session-stats.sh` — subagent exclusion, incremental
append, a mid-append fragment, and a rewritten file — and cross-checked against
a live transcript, where the service and an independent computation agreed
exactly (`ctx=125059`, `spend=581791`).

---

## 049 — Now-playing and transport move to MediaRemote, for every player (amends 002/015/041, reverses 002)

**Date:** 2026-08-22
**Status:** Accepted

### Context

Decision 002 chose AppleScript to the Spotify desktop app and explicitly
rejected the private MediaRemote framework. That was the right call then: on
macOS 15.4 Apple restricted `MRMediaRemoteGetNowPlayingInfo` and friends to
processes carrying an entitlement no third-party app can obtain, so MediaRemote
simply returned nothing.

The consequence is that Tempo is blind to everything except Spotify. Music
playing in Apple Music, a YouTube video in a browser, a podcast in Overcast —
the notch shows nothing and the panel says "Nothing playing".

The restriction has a documented, widely-used way around it. `/usr/bin/perl` is
Apple-signed and *is* entitled to use MediaRemote, and it can `dlopen` an
arbitrary dylib. `ungive/mediaremote-adapter` (BSD 3-Clause) is a small
Objective-C framework plus a perl loader built exactly for this: perl loads the
framework, the framework talks to MediaRemote, and results come back as
newline-delimited JSON on stdout.

**Verified live on this machine before any code was written** (Agent Guideline
#4), macOS 26.6.1:

- The entitlement holds. `get` returned real metadata for **Google Chrome**
  (a YouTube video) and for **Spotify** — two sources, one of which the old
  path could never see.
- `stream --debounce=100 --micros` pushes a diff frame within ~0.5s of every
  play/pause.
- **A seek made inside the player is pushed too.** Seeking Spotify externally
  to 30s and then 90s produced two frames carrying the new `elapsedTimeMicros`
  and a fresh `timestampEpochMicros`.
- Every field Tempo renders is present: `title`, `artist`, `album`,
  `artworkData` (base64 JPEG), `durationMicros`, `elapsedTimeMicros`,
  `timestampEpochMicros`, `playing`, `bundleIdentifier`, `processIdentifier`.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Keep Spotify-only AppleScript | no dependency, no workaround | blind to every other player; the notch is empty most of the day |
| Add an AppleScript path per app | no private API | only scriptable apps qualify — browsers and most players are not; N dictionaries to verify and maintain |
| MediaRemote via the perl trampoline | every player, event-driven, richer data than AppleScript gives | a vendored dependency, a child process, and a workaround Apple could close |

### Decision

Adopt the MediaRemote adapter as the single source of now-playing state and
transport, for every player.

- The adapter source is **vendored** at `Vendor/mediaremote-adapter` (BSD
  3-Clause, `LICENSE` and pinned `COMMIT` retained, local modifications
  recorded in `VENDORED.md`) so builds need no network and cannot drift.
- `scripts/build-media-adapter.sh` compiles it with `clang` rather than the
  upstream CMake, because the perl loader only needs
  `<Name>.framework/<Name>` to be a Mach-O dylib exporting the `adapter_*`
  symbols — not a full versioned bundle. That keeps the repo's tooling
  requirement at the Xcode command line tools. The script **verifies the
  entitlement by running the real `get` command** and fails loudly if macOS has
  closed the door, so this breaks at build time rather than as a silently empty
  notch.
- `scripts/make-app.sh` builds the adapter first and copies both files into
  `Contents/Resources`.

**Spotify AppleScript is kept for exactly one value.** MediaRemote identifies a
track only by `contentItemIdentifier`, which is a per-playback UUID — observed
live changing three times for the same song across three seeks. Add-to-playlist
needs the stable `spotify:track:…` URI, so `MusicService` shrinks from 557
lines to ~130 whose only job is to publish `state.spotifyTrackURI`, taken free
from Spotify's `PlaybackStateChanged` notification. The playlist row is
therefore enabled only while Spotify is the source, and disabled (not hidden,
not silently inert) otherwise.

### Consequences

- **Decision 041's 1Hz panel-open reconciliation poll is removed.** It existed
  because a seek inside Spotify posted no notification. MediaRemote pushes it,
  verified above, so the open panel now costs **zero timers** rather than one.
- Artwork arrives as base64 in the stream instead of a URL fetch. It is decoded
  off the main actor and only when a fingerprint of the blob changes, so a diff
  frame that happens to repeat the artwork costs nothing.
- The stream is diff-based, so frames **must** be applied in order. Separate
  `Task { @MainActor }` instances carry no ordering guarantee between them, so
  finished lines are handed over on `DispatchQueue.main`, which is FIFO.
- The adapter runs as a `/usr/bin/perl` child process. `applicationWillTerminate`
  stops it; a crash is normally covered by SIGPIPE on the next write. But a
  stream with nothing playing never writes — three orphans accumulated during
  development on 2026-08-22 — so `start()` also reaps adapter processes that
  are running *this* adapter path and have already been reparented to launchd.

### Risk accepted

This is a workaround of a restriction Apple imposed deliberately and could
tighten again. The mitigation is that the failure is loud and localised: the
build script tests the real entitlement, and at runtime a missing or unentitled
adapter fails silent into "no media", exactly as Spotify-not-running already
did. The Spotify AppleScript path remains in the tree.

---

## 050 — Audio output switching through the HAL; Tempo never joins the render path

**Date:** 2026-08-22
**Status:** Accepted

### Context

Sapphire's "advanced audio" offers per-app volume and per-app EQ from the
notch. Its implementation creates a Core Audio process tap per app per output
device plus an aggregate device, and applies gain and a 10-band biquad EQ in
the render callback.

Tempo already owns half of that machinery: `AudioTapService` creates a
per-process tap on the playing app for the visualizer. But that tap is
**passive** — it reads a copy of the audio. Changing what the user hears means
becoming the output path: mute the app on the real device, re-render through an
aggregate device Tempo owns. Tempo would then be load-bearing for the user's
audio, and a crash or a force-quit mid-route means silence or a stuck aggregate
device. That is a direct collision with Agent Guideline #3.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Per-app volume + EQ (Sapphire's design) | the full feature | Tempo owns the audio path; a crash costs the user their sound; shipped as Beta upstream for good reason |
| Nothing | no risk | the panel cannot answer "send this to my headphones" |
| Default-device switching + system volume | ~80% of the everyday use at a fraction of the risk; Tempo stays a reader | does not solve "quieten one app" |

### Decision

Ship device switching and system volume only. `AudioOutputService` enumerates
output devices, reads and sets the default output device, and reads and sets
that device's volume and mute — all through the public Core Audio HAL. **Tempo
never creates an aggregate device, never taps for playback, and never sits in
anyone's render path.**

Devices are filtered by output channel count rather than by name, so the split
input/output enumeration of AirPods is handled structurally: verified on this
machine, 5 HAL devices reduced to the 2 real outputs, correctly excluding three
input-only ones.

### Reversal within this decision: listener API

The obvious API, `AudioObjectAddPropertyListenerBlock`, is **broken from
Swift** and was measured to be so on this machine. A Swift closure re-bridges
to a fresh Objective-C block at each C call boundary, so
`AudioObjectRemovePropertyListenerBlock` returns `noErr` while leaving the
original listener registered — after `stop()`, external volume changes still
mutated published state (`fired-while-registered=2, fired-after-remove=2`).
Storing the closure as an explicit `@convention(block)` value does not help.

The C-proc API (`AudioObjectAddPropertyListener`) removes by
`(proc, clientData)` identity and works: `fired-after-remove=0`. `clientData`
is a retained context holding a **weak** service reference, released on
removal, so a callback racing teardown finds nil rather than a dangling
pointer. **Any future listener code in this repo should use the C-proc API.**

### Notes

Some digital outputs own their own level: the LG ULTRAWIDE here answers
`kAudioHardwareUnknownPropertyError` for both volume and mute. `volume` is
`Float?` for that reason and the UI says so rather than rendering a dead slider
at zero (UI Principle #4). Raising the slider on a muted device also unmutes,
because the HAL does not treat a volume change as an unmute and the alternative
is a control that visibly moves and changes nothing.

---

## 051 — File shelf: the notch opens as a drop target when a dragged file comes near

**Date:** 2026-08-22
**Status:** Accepted

### Context

The requested behaviour: while the user is holding a file, the notch should
notice, expand into a place to drop it as the pointer gets close, then later
show that it is holding something and let the file be dragged back out.

macOS gives no notification that a drag session is in progress. The technique
boringNotch uses, and the one adopted here, is to watch the **drag
pasteboard's change count**: snapshot `NSPasteboard(name: .drag).changeCount`
on global `.leftMouseDown`, and when it differs during `.leftMouseDragged`, a
real drag with content has begun.

**Verified: this needs no permission.** A dedicated ad-hoc-signed probe app
with its own bundle id observed the full synthetic sequence — 1 down, 8 drags,
1 up, with correct `NSEvent.mouseLocation` — while `AXIsProcessTrusted()`,
`CGPreflightListenEventAccess()` and `CGPreflightPostEventAccess()` were all
false and no TCC prompt was ever shown. Global monitors for *mouse* events are
not gated the way keyboard events are. Handlers were also confirmed to arrive
on the main thread.

### Decision

- `DragDetector` installs global monitors only while the shelf is switched on,
  so a disabled shelf watches nothing at all.
- The activation region comes from a **closure re-read on every event**, not a
  rect captured at init: Tempo relocates the notch across displays (decision
  037), and boringNotch's fixed rect would leave the shelf attached to a
  display the notch has left.
- The region is `pillWidth + 80pt` on each side and `notchHeight + 80pt` tall.
  The notch should *attract* a drag; the user aims at the top of the screen,
  not at a 32pt strip.
- A drag inside the region sets `state.isDragTargeting`, which feeds
  `displayedExpanded` exactly as hover does — so the panel opens on the same
  animation path, with no second expansion mechanism.
- The drop is accepted by the **whole panel**, not just the drawn well, so a
  drop landing slightly off the affordance still lands in the shelf.
- Files are **copied** into `~/Library/Application Support/Tempo/Shelf/` (dir
  `0700`) with a JSON index beside them, so the shelf survives the original
  being moved or deleted, and survives relaunch. The index stores the stored
  copy's *file name, not an absolute path* — no user path is written down.
  Duplicate names are disambiguated rather than overwritten. Files over 256 MB
  are skipped, not truncated, and excluded from the returned count.

### Deviation from the reference implementation

boringNotch's detector relies on the global `.leftMouseUp` to end a drag. In a
cross-app drag that mouse-up is consumed by the *source* application's dragging
session and is not guaranteed to arrive, which can leave the notch stuck open
as a drop target for a drag that already finished. A 0.2s watchdog polling
`NSEvent.pressedMouseButtons`, running only while a content drag is live,
closes that hole.

Text drags are deliberately **not** accepted: the shelf stores files, and
opening a drop target for a text selection would mean refusing the drop.

---

## 052 — Bluetooth connect/disconnect notices: built, dormant, off the main thread

**Date:** 2026-08-22
**Status:** Deferred — the platform refuses the API on this machine

### Context

The intent was a transient "AirPods connected" notice in the notch, using the
public `IOBluetooth` API.

**IOBluetooth does not work in this process, and the failure mode is a
permanent hang.** Every entry point — `IOBluetoothDevice.pairedDevices()`,
`register(forConnectNotifications:)` — funnels through
`+[IOBluetoothCoreBluetoothCoordinator sharedInstance]`, whose `init` blocks the
calling thread on an untimed `dispatch_semaphore_wait` that is never signalled.
Captured twice with `sample`.

The root cause, isolated with a direct `CBCentralManager` probe:
**CoreBluetooth never powers on for this process.**
`centralManagerDidUpdateState:` is never called, state stays `.unknown` after
10s, and `CBManager.authorization` stays `notDetermined` — **with no TCC prompt
ever shown**. Reproduced identically across five configurations: a bare CLI
binary; an ad-hoc-signed `.app` carrying `NSBluetoothAlwaysUsageDescription`;
an `.app` signed with a real keychain identity; launched directly and via
`open`; and from both the main thread and a background thread — so it is *not*
a main-queue self-deadlock.

Bluetooth is on, with ~10 paired devices, confirmed via
`system_profiler SPBluetoothDataType`.

### Decision

Keep the service, do not wire it up.

- All IOBluetooth work is confined to one dedicated `Thread` with its own run
  loop, created once per process, which is allowed to park in that semaphore
  forever. **Calling any IOBluetooth API on the main actor would freeze Tempo
  permanently** — this is the single most important constraint for anyone
  touching this file. `start()` measured at 2ms with the main run loop
  continuing to tick.
- `NSBluetoothAlwaysUsageDescription` is added to the bundle's Info.plist so
  the permission can be asked for at all if the platform ever allows it.
- `batteryPercent` is always `nil`. `responds(to:)` was false for every
  battery selector; `ioreg` showed no battery keys for any HID device. A
  fabricated percentage would be a lying signal (UI Principle #4).
- No UI is wired, and this is **not** described in `README.md` as a feature,
  because it cannot produce an event today.

### To revisit

If a future macOS or a notarized Developer ID identity lets CoreBluetooth power
on for Tempo, events flow with no code change and only the UI remains to be
built. The first thing to check is whether Tempo appears in System Settings ▸
Privacy & Security ▸ Bluetooth at all.

---

## 053 — Raise the expanded panel's height ceiling from 280pt to 600pt

**Date:** 2026-08-24

### Context

`NotchGeometry.panelHeight` is both the window height and the ceiling the drawn
panel is clamped to (`ContentView.currentHeight`,
`NotchHitRegion.expandedTarget`). The window is deliberately never resized —
only the SwiftUI content animates (decision 013) — so anything the expanded
content lays out below that line is outside the window and is not drawn at all.
The ceiling is a hard clip, not a scroll.

280pt was the scaffold's figure (decision 008), set when the expanded panel held
only the now-playing header. Since then the panel gained the playback progress
bar (039), the audio-output row (050), the file shelf (051), the usage graphs
(017) and the per-session agent rows (040/048). With those on, the content runs
past 280 and the bottom sections are silently cut off.

Measured live on this machine (temporary `tempoDebug` in
`reportExpandedHeight`, notchless external-display fallback, media idle): the
output row + usage graphs + agent rows alone lay out at **233pt including the
strip**. The sections not on screen at that moment add roughly 290pt more — the
now-playing header ~113 (its column is title 33 + transport 28 + playlist ~35
plus spacing, and the cover matches the column), the progress bar ~20 (its
`hitHeight`), the shelf row 68 (`itemSide` 52 + 16), two more agent rows 60
(28 + 2 spacing each), plus 12pt of stack spacing before each — for **~525pt in
the fullest case**.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Raise the constant ceiling** | One-line change; keeps the never-resize window invariant that decision 013 and the hit-region design rest on; margin costs nothing because the window is transparent and click-through outside the drawn shape | The figure is derived, not measured end-to-end in the fullest state; a future section could run past it again |
| B. Resize the window to the measured content | No ceiling to maintain | Changes the notch-window mechanics — the hit region, the shape reporting and the open/close springs all assume a fixed window; a window resize during the spring is exactly the jank decision 013 removed |
| C. Scroll the whole expanded content | Never clips at any size | The panel becomes a scroll view, not a surface (UI Principle #3); a scrollbar in the notch competes with the signals |

### Decision

**Option A — `panelHeight: 280 -> 600`.**

- Every growable section is already individually bounded: the agent list caps at
  three rows and scrolls (`AgentLightsView.visibleRows`), the shelf row and the
  output-device row scroll horizontally. So the fullest panel is a fixed height,
  and the ceiling only has to clear it — it never has to grow with the machine's
  state.
- 600 clears the ~525pt fullest case with margin, and the margin is free: the
  window is transparent outside the drawn silhouette and
  `NotchHostingView.hitTest` passes every click outside the live shape through
  to the app behind (Agent Guideline #3). A taller window claims nothing extra.
- The drawn panel is unchanged in every state that already fitted: it is still
  content-sized (`min(expandedContentHeight + stripHeight, panelHeight)`), so
  the only visible difference is that the sections that used to be clipped are
  now drawn.

### Verification

Debug and release builds clean; `dist/Tempo.app` rebuilt via
`scripts/make-app.sh` and running. The measurement above was taken from the
running signed bundle with a scripted hover over the notch, then the
instrumentation was removed. The fullest state (music playing + playlist
connected + shelf holding files + three live agent sessions) has not been
observed on screen in one frame — that is the one part of this figure that is
arithmetic rather than measurement.

---

## 054 — "Show on external displays": hide Tempo when there is no hardware notch

**Date:** 2026-08-24

### Context

`NotchGeometry.resolveScreen()` prefers the built-in notched display whenever it
is in `NSScreen.screens`, so on a MacBook with monitors attached Tempo already
stays on the real notch. The case this decision is about is the *other* one:
lid closed (the built-in leaves the screen list entirely), or a Mac with no
built-in notch. There `resolveRaw` falls back to a centred 200x32 strip on the
menu-bar display — a black bar hanging off the top of an external monitor that
has no notch to merge with. Requested: a way to have nothing there at all.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| **A. One switch, hide the whole panel by ordering the window out** | A window that is not on screen draws nothing, takes no hover, accepts no drop and runs no SwiftUI body — there is no second "hidden" code path to keep correct; the panel returns in the state it left | The gear is inside the panel, so a hidden Tempo has no way back into Settings unless one is added |
| B. Per-display opt-in list | Fine-grained | Nothing to be fine-grained about: Tempo only ever draws on one display at a time, and which one is already decided by the hardware notch |
| C. Keep drawing but make the strip invisible until hovered | Panel stays reachable | An invisible hover target at the top of the screen is exactly the "swallows clicks meant for other apps" failure Agent Guideline #3 forbids |

### Decision

**Option A**, `Preferences.showOnExternalDisplays`, default **on** — which is
byte-for-byte the behaviour that existed before the switch.

- The condition is `showOnExternalDisplays || NotchGeometry.isHardwareNotch`.
  `isHardwareNotch` reads `targetScreen.safeAreaInsets.top > 0` rather than
  comparing `raw` against the fallback dimensions, because 200x32 is a plausible
  real notch size and would not distinguish the two cases.
- `NotchPanel` owns the visibility, not `AppDelegate`: it subscribes to the
  preference itself, and because `@Published` replays on subscribe, that
  subscription is also what first puts the panel on screen. `AppDelegate` no
  longer calls `orderFrontRegardless()`, so a Tempo told not to draw never
  flashes on screen at launch.
- `applyGeometry()` calls `updateVisibility()` on every display change,
  unconditionally — before this it early-returned when no dimension had changed,
  and the display that just appeared or vanished is exactly the one that decides
  whether Tempo shows at all.
- **The escape hatch is `applicationShouldHandleReopen`**: opening Tempo again
  from Finder or the Dock while it is running opens Settings. Without it, a user
  who switches this off on a Mac with no notch has no route back to the gear,
  since the gear lives inside the panel that is now hidden. (Re-opening a running
  accessory app previously did nothing at all, so this costs no existing
  behaviour.)

### The `@Published` trap this uncovered

The first implementation had the sink ignore the emitted value and re-read
`prefs.showOnExternalDisplays`. A `@Published` publisher fires from `willSet`,
so the stored property still holds the **old** value inside the closure, and the
panel lagged one toggle behind the checkbox — measured: switching the box off
left the panel on screen, switching it back on made the panel disappear. The
sink now uses the value it is handed. `updateVisibility()` (for callers outside
the publisher, where the property *is* current) reads the property.

### Verification

Driven live against the signed bundle on this machine, which is currently in
exactly the case the switch governs — lid closed, one 3440x1440 external display,
no screen with `safeAreaInsets.top > 0` — with window state read out of
`CGWindowListCopyWindowInfo` and the checkbox clicked through the accessibility
API:

- Setting on (default): notch panel present, layer 25, 420x600 at the top of the
  external display.
- Setting off, relaunched: **no on-screen windows owned by Tempo at all.**
- Re-opening Tempo from Finder while hidden: the Settings window appears
  (682x420, layer 0) — the escape hatch works.
- Clicking the checkbox on: the panel appears immediately, no relaunch.
- Clicking it off again: the panel goes, the Settings window stays.

Not verified, because it needs the lid: opening the built-in display while the
setting is off should bring the panel back on the real notch. That path runs
through `applyGeometry()` -> `updateVisibility()`, which is the same code the
clicks above exercised, but the transition itself has not been observed.

---

## 055 — Hide the *strip*, not Tempo: an undrawn notch you can still hover

**Date:** 2026-08-24 · **Amends 054**

### Context

Decision 054 made the switch mean "draw nothing on a notchless display", and
implemented that by ordering the panel's window out. That is more than was
wanted: it takes the music controls, the shelf and the agent lights away on that
display too, and it made the switch a trap severe enough to need
`applicationShouldHandleReopen` as an escape hatch. What is actually unwanted is
the *black bar* — a pill with no notch under it to merge with, hanging off the
top of a monitor (UI Principle #6). The panel itself is still wanted; it just
should not be visible until asked for.

### Decision

The switch (now `showStripOnExternalDisplays`) hides the **collapsed strip**.
The panel still opens when the pointer reaches the top middle of that display,
and everything from there on is unchanged.

Three parts:

1. **Undrawn, not unbuilt.** `ContentView.panelOpacity` is 0 while the strip is
   hidden and the panel is shut. Not an `if` in the hierarchy: the black
   silhouette is what reports live animated geometry to `NotchHitRegion`, and a
   view introduced by a branch flip does not join an animation already in flight
   (the same constraint `backgroundShape` documents). As alpha, the panel fades
   in as it grows and out as it retracts, on the existing springs.

2. **Claims nothing while undrawn.** `NotchHostingView.activeRect` returns
   `.zero` in that state, so no click in the middle of that display's menu bar
   is swallowed (Agent Guideline #3). This is keyed off the expansion flag and
   not the live shape — the deliberate opposite of the collapsing rule that
   fixed the click-fallthrough bug (decision 012). The flag flips while the
   panel is still visibly fading, so passthrough is handed back a few hundred
   milliseconds early; here that is the right way to err, because what is fading
   sits over someone else's menu bar and swallowing a click there is worse than
   dropping one.

3. **A global pointer monitor supplies the hover.** With nothing hit-testable
   there, the window receives no mouse events over the invisible pill and
   SwiftUI's `.onHover` can never fire, so the pointer's position is the only
   signal left. `NotchHoverDetector` adds one `.mouseMoved` global monitor —
   needing no Accessibility or Input Monitoring grant, the same finding
   `DragDetector` rests on — and writes `state.isPointerNearNotch`. ContentView
   feeds that into `handleHover`, the *same* dwell and haptic as a real hover,
   so the two entry paths cannot drift apart. The monitor is installed only in
   this one mode, gated on the setting and on `screenGeneration` so a display
   change re-evaluates it.

The activation region is `NotchGeometry.hoverActivationRegion`: exactly where
the pill would be drawn if it were drawn — same width, same height, same place.
The target is "the notch is still there, you just can't see it", not a second
differently-shaped hot zone. It uses `pillWidth` rather than the live
`collapsedWidth`, so it does not shrink to the bare notch when the media UI goes
idle (decision 038) — an invisible target that silently changes size is
unusable. Once open, the region becomes the panel's own rect, so travelling from
the invisible strip down into the controls does not read as leaving.

### What this reverses from 054

The window is never ordered out any more, so `updateVisibility`/`setVisible` and
the visibility subscription are gone, and `AppDelegate` orders the panel front at
launch again. `applicationShouldHandleReopen` — added as 054's escape hatch —
**stays**: Settings is reachable by hovering now, so it is no longer
load-bearing, but re-opening a running accessory app previously did nothing at
all, and opening Settings is the obviously right thing for it to do.

### Verification

Driven live against the signed bundle, on this machine in the mode the switch
governs (lid closed, one 3440x1440 external, no screen with
`safeAreaInsets.top > 0`). Expansion state read as the accessibility element
count of the panel window — 1 collapsed, 15 expanded — with the pointer moved by
posted `CGEvent`s:

- Strip hidden, pointer away: window present (420x600 at the top of the
  external), AX count **1**.
- Pointer moved to the top middle: AX count **15** — the panel opened with
  nothing drawn to hover.
- Pointer moved away: back to **1**.
- **Click-through, A/B with `hitTest` temporarily instrumented**, clicking the
  top middle 40ms after arriving (inside a hover dwell raised to 400ms, so the
  panel is still shut): strip *shown* logs one `hitTest` → **CLAIMED**, active
  rect `(84, 568, 252, 32)`, the pill exactly. Strip *hidden* logs **no
  `hitTest` at all** — the window is fully transparent there, so the window
  server routed the click past Tempo without ever consulting the view. The
  `.zero` guard is the belt to that braces, and covers the paths that do reach
  the view.
- **Cost of the monitor**, process CPU time across 4.0s of posted mouse-moves at
  100/sec, pointer nowhere near the notch: 10ms with the monitor off, 90ms with
  it on. 0.2ms per event, ~2% of one core while the pointer is moving
  continuously, and nothing at all while it is still.

## 056 — The visualizer taps all system audio, not Spotify's process (amends 016, 039)

**Date:** 2026-08-24 · **Amends 016, 039**

### Context

Reported: "the audio visualizer bugs out when watching media other than
Spotify: i am watching youtube right now and its stuck."

It was not stuck — it was two Spotify-shaped signals agreeing that nothing was
playing while sound came out of the machine:

- **The tap was Spotify-only.** `AudioTapService` translated
  `com.spotify.client`'s pid to a Core Audio process object and built
  `CATapDescription(stereoMixdownOfProcesses:)` around it (decision 016). A
  YouTube tab is not in that tap, so `isCapturing` stayed false and the reactive
  path never engaged.
- **The fallback keys off now-playing, and now-playing was Spotify.** With no
  tap levels, `VisualizerView` falls back to the playback-synced sine animation
  (decision 004), whose `animating` gate is `isPlaying && outputAudible`.
  Measured at the time of the report, `mediaremote-adapter … get` returned
  `bundleIdentifier = com.spotify.client`, `playing = false` — Spotify's paused
  card, while Chrome played. So `animating` was false, the `TimelineView` was
  explicitly `paused`, and the bars sat frozen at their resting height under
  Spotify's stale artwork.

Neither half was wrong on its own terms. The architecture only ever had one
source of truth about audio, and it was named "Spotify".

### Options

| Option | Reactive for YouTube? | Cost |
| --- | --- | --- |
| **Global system tap** | Yes, for every app | One-line description change; the tap no longer has an owning app to ask about running output |
| Tap the now-playing app's process | **No** — MediaRemote reported Spotify (paused) while Chrome played, so the tap would have followed the wrong pid | Same code, wrong answer |
| Global tap used only as an is-anything-playing flag, driving the sine | Motion, but still fake | Same permission and nearly the same code as the real thing |

### Decision

**One global tap.** `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` —
verified present in the macOS 26.6 SDK (`CATapDescription.h`) — replaces the
per-process description. Consequences:

1. **The tap outlives Spotify.** It is built once and kept for Tempo's lifetime;
   the only thing that tears it down is an output-device change. The
   `NSWorkspace` launch/terminate observer for `com.spotify.client` and the
   `spotifyPID` lookup are gone. `observeProcessObjects()` stays, now as the
   generic retry hook for a build that failed before Core Audio was ready.
2. **The TCC-denial heuristic has no owning app any more.** It asked
   `isRunningOutput(spotifyProcessObject)`; it now asks
   `anyProcessRunningOutput()`, which walks
   `kAudioHardwarePropertyProcessObjectList`. Same meaning: callbacks arriving,
   every sample exactly zero, something is playing → the tap was never
   authorized.
3. **Nothing is excluded.** Tempo plays no audio, and naming a specific app in
   that list is precisely the mistake being fixed.

Decision 039 is untouched and now matters more: a global tap is taken before the
output device's volume and mute, so a muted Mac must still settle the bars.

### The strip grows a visualizer-only wing

A YouTube tab often publishes no now-playing card at all, so `isMediaActive` can
be false while real audio plays — a bare notch over live sound, which reads as
broken. `ContentView.showsAudioOnly` puts the visualizer wing up on real audio
alone, with **no artwork** (there is none to show) and an empty mirror wing on
the leading side so the notch gap stays centred on the hardware notch (UI
Principle #6).

It keys off `AudioTapService.audioActive`, not `isCapturing`, because
`isCapturing` is the wrong shape for geometry at both ends:

- **Late to open** (`audioOnsetSeconds = 2`). A Discord ping is sound, not
  something to listen to, and must not pop the pill's wings open. Two seconds
  sits above the 1.5 s `captureHoldSeconds` that keeps `isCapturing` up past a
  short sound.
- **Slow to close** (`audioHoldSeconds = 15`). The 1.5 s hold would retract and
  re-grow the pill in the gap between two YouTube clips. Fifteen seconds rides
  that out and still puts the notch back to bare shortly after a video ends —
  deliberately much shorter than the 60 s `mediaIdleTimeout`, which is holding a
  *card* someone may come back to rather than reacting to sound in the room.

### What this does not change

Now-playing metadata. When MediaRemote reports Spotify's paused card while
another app plays, the collapsed strip still shows that card — the visualizer
beside it is now honest, the artwork is not. That is a MediaRemote-side problem
(which app owns the now-playing session) and is left alone here.

### Verification

- `CATapDescription.h` in the macOS 26.6 SDK exposes
  `initStereoGlobalTapButExcludeProcesses:` (`NS_REFINED_FOR_SWIFT`), alongside
  the mixdown initializer already in use.
- `mediaremote-adapter … get` during the report: `bundleIdentifier =
  com.spotify.client`, `playing = false`, elapsed 23.82 s — Spotify's stale
  paused card while Chrome was playing. That is the frozen-bar state, reproduced
  from the command line.
- With the global tap built: `tap built global subDeviceInputBuffers=0
  aggregateInputBuffers=1 tapBuffer=0`, and `anyProcessRunningOutput` reads 1
  while Chrome plays and 0 when it stops — so the new denial heuristic tracks
  real playback with no app named anywhere.
- **Ad-hoc signing invalidates the audio grant on every rebuild.** After
  `scripts/make-app.sh`, `kTCCServiceAudioCapture | com.gameslayer999.tempo`
  still read `auth_value = 2` (allowed) in TCC.db, yet every tap buffer came
  back exactly zero and `silentDenialSuspected` latched — the stored code
  requirement no longer matches the re-signed binary, and Core Audio denies by
  delivering silence rather than an error. `tccutil reset AudioCapture
  com.gameslayer999.tempo` plus a relaunch re-prompts. This is the ad-hoc
  signing tax `scripts/make-app.sh` already warns about, not new behaviour.


---

## 057 — First run writes a cursive `hello` out of the notch, then asks for what it needs

**Date:** 2026-08-24 · **Status:** Accepted

### Context

Tempo had no first run at all. A fresh install put a pill on the notch and
nothing else: the visualizer's bars sat still because System Audio Recording
had never been granted, the Spotify features were invisible because no Client
ID was configured, and nothing anywhere said either of those things. The user
asked for "a hello screen when first starting the app, just like the Apple
hello" — the word that writes itself during macOS setup.

Two questions had real answers, and both were put to the user before any code
was written (Agent Guideline #1, Decision Framework step 2).

### Options considered — what the hello leads to

| Option | For | Against |
|---|---|---|
| Animation only | Smallest change; pure atmosphere | A fresh install still starts with a dead visualizer and no explanation |
| **Animation → setup rows** | The one moment the user is definitely looking is also the moment the permissions are asked for | More to build; the rows have to report live grant state or they lie |
| Animation → open Settings | Reuses the built Settings window | Drops the user into a form instead of an introduction |

**Chosen: animation → setup rows.**

### Options considered — where it is presented

| Option | For | Against |
|---|---|---|
| Full-screen black takeover | Most faithful to Apple's setup | Tempo is `LSUIElement` and never activates; a full-screen takeover is the most intrusive thing it could possibly do |
| Centred floating card | Safe, dismissible | A second window to build and manage, and it says nothing about what Tempo *is* |
| **Unrolls out of the notch** | The introduction happens in the surface being introduced; no new window at all | The panel is non-activating, so nothing in it can take keyboard input |

**Chosen: it drops out of the notch** — the user's call, and the right one:
the first thing Tempo does is demonstrate the thing it is.

### How it is built

- `HelloScript` — the word as **one continuous cubic path**, pen down at the
  foot of the `h`, pen up at the end of the `o`. That is load-bearing:
  `trimmedPath(from:to:)` walks a single subpath by arc length, so one stroke
  writes itself letter by letter. Split into five per-letter subpaths it would
  draw all five simultaneously, each a fifth of the way along. The control
  points were tuned by **rendering the curve to a PNG and looking at it**,
  three passes — the first read as `hello` but had a pinched `e` and a long
  trailing swash; Apple's ends on a short tick, and the stroke is thin (3.2pt)
  because weight is what separates handwriting from a logo.
- `OnboardingController` — a three-state phase (`inactive` / `hello` /
  `setup`), a 2.4s write-on, a 0.7s hold, and a tap anywhere on the word to
  skip. Reduce Motion gets the finished word immediately, no write-on (HIG,
  matching what the panel's springs already do).
- **`AppState.isOnboarding`, folded into `displayedExpanded`.** This is the
  whole trick and the reason the feature is small. The panel is already held
  open by that one computed property, so hover-out, the outside-click monitor,
  `NotchPanel.sendEvent`'s pin, and the live hit region all keep the onboarding
  panel open *without any of them learning what onboarding is*. Nothing in
  `NotchWindow.swift` changed.
- `hasSeenHello` is written when the user finishes the cards, **never** when
  the animation merely plays, so a crash mid-hello does not silently consume
  the only first run. Settings ▸ About has "Show the welcome again", so
  replaying is a button and not a hand-edited default (Agent Guideline #8).

### The bug this shipped with, and the fix

The setup cards bled past the panel's edges on first sight. Cause:
`.padding(.horizontal, …)` applied **after** `.frame(width: panelWidth)`, which
adds outside the frame — the content laid out at `panelWidth + 52pt` inside a
window exactly `panelWidth` wide. `ContentView.expandedContent` had the right
order all along (pad, then frame); the new view did not copy it. Height needed
no change: `reportExpandedHeight` already measures the content and drives both
the panel's height and the hit region's target, and onboarding reports through
the same path, so the panel sizes itself to the hello and again to the cards.

### Consequences

- One new flag on `AppState`, no change to the window or hit-region code.
- The rows report **live** grant state (`UNAuthorizationStatus`,
  `CLAuthorizationStatus`, `SpotifyWebAPI.isAuthed`) rather than a checklist
  the user ticks off, so a permission revoked in System Settings is reflected
  the next time the panel is opened (UI Principle #4).
- The audio row is deliberately **informational**: there is no TCC-status API
  for audio capture, and `AudioTapService.silentDenialSuspected` is a
  heuristic, not an authorization. Claiming a status Tempo cannot actually read
  would be exactly the lying signal UI Principle #4 forbids, so the row says
  what will happen and offers the System Settings pane instead.


---

## 058 — Weather and now-playing reach the lock screen as two notifications (completes 036)

**Date:** 2026-08-24 · **Status:** Accepted

### Context

Asked for: revisit the lock screen, with weather and music on it.

Decision 036 is the reason this is not simply "draw the notch there". That
decision built a lock-aware panel, measured it, and reverted every line: macOS
composites the lock screen in a **separate secure context that does not include
user-session windows at any level**. Four opaque labelled strips at levels
1000, 2002, 2005 and 2147483629 — bracketing `loginwindow`'s real lock-screen
windows from below, between, just above and far above — were *all* invisible
while locked. Window level is not the variable; there is no value that works.

036's own closing section named the one surface that remains: "the only
sanctioned surfaces are system-mediated ones — a notification". This decision
takes it up.

### Options considered

| Option | For | Against |
|---|---|---|
| One combined card | Never more than one Tempo card | Weather and music are different rhythms crammed into one line |
| **Two cards** | Each legible alone; weather survives when the music stops | Two Tempo notifications stacked on the lock screen |
| Music card only, weather as a subtitle | Quietest | A locked Mac playing nothing shows nothing at all |
| Always posted, not just when locked | More reach | Permanently occupies a Notification Center slot — clutter |

**Chosen: two separate cards** (the user's call).

### How it works

- `ScreenLockService` — **this is 036's code, resurrected.** That decision
  deleted it along with everything else, but the deletion threw away a verified
  component: the lock *detection* was measured correct on both edges at the
  time; only the drawing was impossible. It is `loginwindow`'s
  `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications,
  reconciled against `CGSessionCopyCurrentDictionary()` at start, on wake, and
  on session activation, so a missed edge self-corrects (UI Principle #4).
- `LockScreenNotifier` — posts on the lock edge, withdraws on the unlock edge.
  A change while locked (a track, a refreshed reading) re-adds the **same
  identifier**, which replaces the delivered card in place instead of stacking
  a second one, so a whole evening of music is one card that keeps changing.
- `interruptionLevel = .passive`, `sound = nil`: delivered without a sound and
  without lighting a sleeping display. The card is meant to be *found* on the
  lock screen, not to interrupt.
- Only a **playing** track earns a music card, and only a real reading earns a
  weather card; otherwise that card is withdrawn rather than posted empty.
- Album art rides along as a `UNNotificationAttachment`, written as a PNG into
  the temp directory and swept up on withdrawal (the attachment API takes a
  file URL and moves the file into its own store).
- Off by default. The feature needs Notification authorization, and a fresh
  install must never open with a permission prompt nobody asked for — the
  hello screen (decision 057) is what turns it on, at the moment the user
  grants.

### The part Tempo does not control, and says so

Authorization is necessary and **not sufficient**. Two switches decide whether
a delivered card is legible when locked, and neither is ours: System Settings ▸
Notifications ▸ Tempo needs **Show on Lock Screen** on, and **Show previews**
set to *Always* — the default, "when unlocked", renders a locked card as a
contentless "Tempo · Notification". Settings ▸ Weather states this explicitly
and links to the pane, because a granted-but-blank card is precisely the
failure mode that reads as a broken feature.

### Consequences

- Off means genuinely off: no notification-centre calls, no lock observers, no
  network, no location manager.
- Withdrawn on quit as well as on unlock — a card left in Notification Center
  after the app that posted it is gone is a signal with nothing behind it.
- `UNUserNotificationCenter.current()` traps in a process with no bundle, so
  every entry point is gated on `Bundle.main.bundleIdentifier != nil`: the bare
  `swift build` binary simply has no lock cards.


---

## 059 — Weather comes from Open-Meteo, located by reduced-accuracy CoreLocation with a typed city as fallback

**Date:** 2026-08-24 · **Status:** Accepted

### Context

Decision 058's weather card needs a weather source and a location. Both were
verified against the real services before any code was written (Agent
Guideline #4).

### The data source

**WeatherKit is unavailable to this app.** It requires a real Team ID and a
`com.apple.developer.weatherkit` entitlement; `codesign -dv` on
`dist/Tempo.app` reports `Signature=adhoc`, `TeamIdentifier=not set`
(decision 018 — there is no Apple Development identity on this machine). That
is not a preference, it is a hard block.

**Open-Meteo** was queried live from this machine before being chosen. It
returns current temperature, apparent temperature, a WMO condition code and a
day/night flag with **no API key and no account**, and advertises
`interval: 900` on the current block — so Tempo polls every 15 minutes and no
faster, because faster would spend requests re-reading identical numbers. Its
geocoding endpoint (same host family, also key-free) resolves a typed city
name; both were confirmed returning well-formed payloads.

### The location

| Option | For | Against |
|---|---|---|
| **CoreLocation, typed city as fallback** | Correct when you travel; still works when denied | Two code paths, one TCC prompt |
| Manual city only | No permission ever, most private | Wrong the moment you travel |
| CoreLocation only | Fewest moving parts | A denied prompt kills the feature permanently |

**Chosen: CoreLocation with the city fallback** (the user's call), which is
also the only one that satisfies Guideline #3's fail-silent rule.

Accuracy is deliberately `kCLLocationAccuracyReduced` — a coarse, city-scale
fix is all a weather lookup needs, it is the least the user has to hand over
(Guideline #5), and it makes macOS show the *approximate* location prompt
rather than the precise one. The distance filter is 3km, so a walk around the
block spends neither a geocode nor a weather request. The device coordinate is
**never written to disk**; only a *typed* city's resolved coordinates are
cached, because the user typed them.

### One bug worth recording

The first pass matched only `.authorizedAlways` and the deprecated
`.authorized` when deciding whether to start the location manager. Tempo calls
`requestWhenInUseAuthorization()`, which is exactly the request that returns
**`.authorizedWhenInUse`** — so a user who granted location would have had the
manager silently never start, and the weather would have fallen back to the
typed city with nothing to explain why. Folded into a
`CLAuthorizationStatus.grantsLocation` helper used by every call site, so the
same omission cannot recur in one place and not another.

### Consequences

- The city fallback uses **Open-Meteo's** geocoder rather than `CLGeocoder`,
  deliberately: `CLGeocoder` is rate-limited per process and refuses outright
  while Location Services is off, which is precisely the case the fallback
  exists for. `CLGeocoder` is still used to *name* a device fix, where Location
  Services is by definition on.
- What leaves the machine is a rounded coordinate and nothing else — no
  identifier, no device name, no session data. Settings ▸ Weather says so.
- Switching the weather card off stops the network requests **and** the
  location manager. An off switch that leaves a location manager running is not
  off.

---

## 060 — The lock-screen cards were never allowed to post, and the hello was a cut, not a hand (amends 057, 058)

**Date:** 2026-08-25
**Status:** Accepted

### Context

Two first-run defects, reported together.

**The lock-screen cards never appeared.** Decision 058 shipped the feature
without a human ever having seen a card. Probing the real bundle
(`dist/Tempo.app`, launched through LaunchServices, so the reading is the app's
own and not a harness artefact) reported:

```
status=1 (denied)  alert=2 (enabled)  lockScreen=2 (enabled)  previews=1 (whenAuthenticated)
requestAuthorization -> UNErrorDomain#1 "Notifications are not allowed for this application"
```

So Tempo's notification authorization was **denied**, and the request to fix it
returned an error *immediately, with no prompt* — which is what macOS does once
a refusal has been recorded: it never prompts a second time. Three separate
faults kept that invisible:

1. `requestAuthorization()` swallowed the error with `_ = try? await`. The
   published `authorization` therefore stayed `.notDetermined`, so both the
   hello's setup row and Settings ▸ Weather kept offering an "Allow" / "Ask now"
   button that could not possibly work, and neither ever said the feature was
   blocked.
2. Nothing asked for permission when the feature was *switched on*. The
   Settings toggle set `showLockScreenCards` and started the notifier; the
   notifier only ever *read* the authorization state. A user who enabled the
   cards from Settings — which is what happened here, `showLockScreenCards = 1`
   with authorization never granted — got a switch that claimed a live feature
   over a permission macOS had never been asked for.
3. `authorization` was refreshed once, inside `start()`, which itself only runs
   while the master switch is on. The one route back from a denial is System
   Settings, and returning from it changes nothing the notification centre
   reports — so a user who *did* fix it would have seen Tempo keep insisting it
   was denied until the next launch.

A fourth fault would have kept the cards invisible even once allowed:
`interruptionLevel = .passive`. Decision 058 chose it to avoid beeping at a
sleeping Mac, but `.passive` means *file this into the list without presenting
it* — the opposite of a card whose entire purpose is to be visible on the lock
screen. Silence was already coming from `content.sound = nil`.

Also found while reading the posting path: `withdraw(_:)` called
`cleanUpAttachments()`, deleting the artwork temp file whenever *either* card
was withdrawn. `UNNotificationAttachment` copies the file into its own store
when the request is added, asynchronously, so withdrawing the weather card
could race the music card's copy and cost it its artwork.

**The hello was clunky.** Two separate causes. The letterforms were free-handed
rather than constructed: an ascender loop was drawn with the upstroke bowing
*left*, so the two strokes crossed high and `h`, `l`, `l` read as balloons on
sticks; the `e` had no closed eye and came out as an angular kite; the `o`
trailed a long swash. And the motion cut: the word vanished on the same frame
the panel jumped from a 96pt line of writing to a full column of setup rows,
with a `Text("Tempo")` label popping in at 75% of the stroke.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Leave posting ungated, fix only the UI | Smallest change | Was the status quo — the feature is silently dead |
| Gate `post()` on `authorization` | Refuses to pretend | A stale reading would suppress cards that would have worked; macOS drops them anyway |
| Ask on switch-on + record refusals + re-read on activation | The user is asked at the moment they express intent, and a denial is both visible and recoverable | Three small changes rather than one |
| Re-draw the hello from a cursive font glyph | Real letterforms for free | A glyph is a filled outline, not a centreline — `trim` would draw its contour, not a pen stroke |
| Re-draw by construction (Palmer method) | Keeps the single-stroke trim animation that makes the write-on work | Hand-tuned control points, verified by rendering |

### Decision

**Notifications.** Ask for authorization from `start()` when the state is
`.notDetermined`, so switching the feature on is what triggers the prompt.
Catch the request error and, when it is `UNError.notificationsNotAllowed` and
the settings read still says `.notDetermined`, record `.denied` — the UI then
shows the only thing that can fix it, a link to System Settings. Refresh the
grant at launch and on every `NSApplication.didBecomeActiveNotification`
(independent of the master switch), and again on the lock edge. Post at
`.active`. Sweep artwork temp files when writing the next one rather than on
withdrawal.

Posting is deliberately **not** gated on `authorization`: a stale reading would
suppress cards that would have worked, and macOS already drops what it must.

**Hello.** Re-drawn on constructed letterforms — an ascender is a narrow
teardrop whose strokes cross *low*, the `e`'s eye is small and closes high, the
`o` ends on a tick. A single shear about the baseline supplies the slant, and
the shape now measures its own bounds (`designPath.boundingRect`) instead of
carrying a hand-maintained design box, so moving a control point cannot leave
the word off-centre. The `Text("Tempo")` label is gone (Apple's hello carries no
label), the stroke gets a two-pass bloom, and the timing curve is near-steady
rather than `easeInOut` — which ran the middle of the word at ~1.6x the average
and braked hard into the `o`. The handoff is now written → held → **faded out**
→ cards, with the panel's existing spring carrying the height change.

### Consequences

- The user must still turn Tempo back on in System Settings ▸ Notifications
  once — a recorded denial cannot be undone from inside the app. The hello row
  and the Weather pane both link straight there now.
- `showPreviewsSetting` on this machine is `whenAuthenticated`, so even once
  allowed the locked card shows without its content until previews are set to
  *Always*. Both surfaces already say so; that text is now reachable, because
  the `.denied` branch no longer masks it.
- `.active` is a behaviour change from 058: the cards now present on the lock
  screen instead of being filed silently. They remain soundless and passive in
  every other respect.
- First run is ~0.4s longer (the fade), and the hello is drawn 132pt tall
  rather than 96pt so the larger word is legible at a glance.

---

## 061 — The `hello` is Apple's actual lettering, not an impression of it (supersedes the curves in 060)

**Date:** 2026-08-25
**Status:** Accepted

### Context

Decision 060 re-drew the cursive `hello` by hand, on Palmer-method
construction. It was a large improvement on what preceded it and still wrong:
*"way too linear — not like the Apple hello at all."* Measured against the real
artwork, three separate faults, none of which more hand-tuning would have
found:

| | hand-drawn (060) | Apple |
| --- | --- | --- |
| aspect (w : h) | ~1.5 : 1 | **3.36 : 1** |
| ascenders | long straight diagonals | continuously curving, no straight run |
| stroke weight | 3pt hairline (~2.5% of height) | **8.04%** of height |

The proportion error is the one that mattered most: the letters were cramped to
under half their proper width, so the word's whole silhouette was wrong. No
amount of control-point nudging fixes a shape that is twice as tall as it should
be for its width.

Apple publishes the `hello` lettering as vector artwork, and critically it is
authored as **centreline paths** — `fill="none" stroke-width="60"
stroke-linecap="round"` — not as filled glyph outlines. That distinction decides
whether it is usable at all here: a filled outline run through `trimmedPath`
draws its own *contour*, not a pen stroke, so it could not have driven the
write-on. A centreline trimmed by arc length is exactly the primitive this
animation already uses.

The artwork is two subpaths — the `h`'s entry-and-ascender, then everything from
the `h`'s stem through the `o` — and they meet end to end (subpath 0 ends at
≈(49, 198), subpath 1 opens at ≈(50, 188)). Trimming a single `Path` containing
both would advance both at once, which is the same "all the letters at once"
failure the original single-subpath authoring existed to avoid.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Keep hand-tuning the authored curves | No third-party asset | Three independent metrics were wrong; iterating on renders had already missed all three |
| Trace a cursive system font (Snell Roundhand) | Ships with macOS | A font glyph is a filled outline — no centreline, so no pen-stroke write-on |
| Use Apple's published centreline artwork | Exactly the intended look; already the right primitive | It is Apple's copyrighted artwork (see Consequences) |

### Decision

Use Apple's centreline geometry, normalised to a 200-unit-tall design box and
embedded as two subpaths. Drive them **in sequence, weighted by arc length**, so
`progress` is spent on each in proportion to how much of the ink it actually is
— the pen then reads as one continuous hand across the pen-lift. Arc lengths are
computed once at first use by flattening (32 samples per cubic); they only need
to be accurate enough to apportion progress between two subpaths.

Stroke weight follows Apple's ratio rather than a fixed point value:
`HelloScript.lineWidth(fitting:)` derives it from the same fit the shape itself
performs, and the view supplies the size through a `GeometryReader`, so the two
cannot drift apart. The design bounds are grown by half a stroke on every side
so round caps are not clipped by the frame.

The write-on timing, the hold, and the fade-out handoff from decision 060 are
unchanged. The frame is 112pt tall (was 132), because at 3.36 : 1 the word is
now width-limited at the panel's content width and wants ~105pt of height.

### Consequences

- **Licensing.** The artwork carries "Copyright © 2020 Apple Inc. All rights
  reserved." Tempo now ships Apple's lettering. This is the same thing the other
  notch apps in this category do, and it was an explicit product instruction —
  but it is Apple's asset, not ours, and that is a distribution question rather
  than a technical one. Swapping in an original word later is a data-only change:
  the two subpath arrays are the entire dependency.
- `HelloScript` no longer carries a slant constant, an `ascender` helper, or a
  design origin — the geometry is data now, not construction. Roughly 60 lines of
  hand-authored curve-building went away.
- The shape gained an arc-length flattener. It runs once, lazily, for two
  subpaths totalling 34 cubics.
- Other languages are a drop-in: the same source publishes `hello` for ~37
  locales in the identical format.

---

## 062 — A Human Interface Guidelines pass over every Tempo surface

**Date:** 2026-08-26
**Status:** Accepted

### Context

The panel had been built one feature at a time, and it showed in the places
where a rule should have been shared instead of re-decided. An audit against
Apple's Human Interface Guidelines and the *UI Design Dos and Don'ts* found
six classes of problem, none of them cosmetic:

1. **Reduce Transparency did nothing.** The expanded panel is Liquid Glass —
   the exact effect the setting exists to switch off — and no code read it.
   Increase Contrast was likewise unread: white text on clear glass over a
   bright desktop had no way to get more legible.
2. **Agent state was carried by hue alone.** Running / blocked / error / idle /
   finished were five discs identical but for colour. Rendered greyscale and
   scored over a 7x7 luminance grid, *running* and *blocked* differed by **37
   points out of a possible 2500** — which is to say a colourblind user, or
   anyone glancing at a dimmed display, could not tell a working session from
   one that had been waiting on them. That is the HIG's single clearest colour
   rule, and it was broken on the app's headline feature.
3. **Hit targets below the platform floor.** The mute button was 16x16pt, the
   shelf's remove button 12x12, the output chips ~19pt tall, the onboarding
   action pills ~18pt, and "Open Settings" in the first run was an unpadded
   11pt text run.
4. **31 hard-coded `.system(size:)` literals**, including a 9pt file-shelf
   label — below every macOS text style and under Apple's own stated
   legibility floor. None of them tracked the user's text-size setting.
5. **Per-glyph drop shadows standing in for a scrim.** Four places drew text
   with `.shadow(.black.opacity(0.5))` to survive clear glass — the track title and
   artist, the transport row, the gear, and the scrubber's clocks. The HIG calls
   this out directly: a shadow behind every letter thickens the type and still
   fails over a mid-grey backdrop.
6. **The visualizer looped forever under Reduce Motion.** Every other
   animation in Tempo already honoured the setting; this one did not.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Fix each violation where it sits | Smallest diff; no new file | Leaves the *cause* — every view deciding its own type sizes and state colours — so the next feature reintroduces the same drift |
| One shared vocabulary, adopted everywhere | Makes the rules enforceable rather than aspirational; a new section inherits them for free | A new file, and a mechanical edit across ten views |
| Adopt a full design-system package | Comprehensive | Wildly disproportionate for a notch app; contradicts the project's simplicity rule |

### Decision

Add `Views/NotchStyle.swift`, holding three things and nothing more:
`NotchType` (seven named roles mapped to macOS text styles), `NotchMetrics`
(two hit targets, three spacing steps, the content inset), and
`AgentAppearance` / `AgentDot` (one state's colour, shape, glyph, motion and
spoken name, shared by the collapsed pill and the expanded rows). Then adopt it
everywhere and fix the six classes above against it.

The typography change is **mechanism, not measurement**: `.caption2` is 10pt on
macOS, `.subheadline` 11, `.callout` 12, `.headline` 13, `.title3` 15,
`.title2` 17 — the sizes the panel already drew. The one deliberate size change
is the file shelf's 9pt name moving to 10, because macOS ships nothing smaller.

Agent states are now separated on **four** axes rather than one: fill vs. ring
(idle is hollow), diameter (the quiet states draw at 0.72x the slot, so the
slot geometry is unchanged), a black glyph at or above 10pt drawn diameter
(`?` blocked, `!` error, checkmark finished), and motion (only blocked pulses).

### Verification

The colour-alone fix was measured, not eyeballed: `AgentDot` was rendered
offscreen through `ImageRenderer` at both the sizes it is used at, converted to
Rec. 709 luma, and every pair of states scored on a 7x7 grid.

| Pair | Before | After (8pt) | After (12pt) |
| --- | --- | --- | --- |
| running vs blocked | **37** | 887 | 827 |
| worst pair overall | 37 (running/blocked) | 520 (running/idle) | 387 (blocked/error) |

The first attempt punched the glyph with `.blendMode(.destinationOut)`, which
let the state's own glow shine up through the hole and left the glyph at about
half contrast; drawing it solid black instead is what took the figures above.

Debug and release builds are clean with no warnings. `dist/Tempo.app` runs at
0.0% CPU at rest, unchanged.

### Consequences

- **Not visually verified against a live desktop.** `screencapture` has no
  Screen Recording grant in this session, so the shadow-to-scrim swap
  (item 5) has been reasoned about and built but not *seen* over a bright
  window. `scripts/capture-readme-shots.sh` is the way to check it, and the
  README screenshots it produces are now stale.
- The scrim replaces the shadows only for **text**. The album cover's drop
  shadow and the scrubber knob's stay: those convey depth, not legibility.
- `contentScrim` adds 0.22 to every panel style under Increase Contrast, so a
  high-contrast user sees a denser panel than the style preview in Settings
  shows. The preview is not contrast-aware; noted, not fixed.
- Under Reduce Motion the visualizer no longer moves at all. It re-encodes the
  signal as height — a fixed raised profile while audio plays, flat when it
  does not — so "something is playing" survives, but per-band detail does not.
- `NotchButtonStyle` now shows a resting fill and border under Increase
  Contrast. At standard contrast the controls are still bare glyphs until
  hovered, which is the deliberate glanceable look (UI Principle #1).
- Settings was already the most conformant surface (grouped `Form`,
  `LabeledContent`, semantic colours) and needed only two undersized targets
  raised and their labels added.

---

## 063 — The expanded panel is two groups, not six equal siblings

**Date:** 2026-08-26
**Status:** Accepted

### Context

Decision 062 fixed the panel's conformance — materials, contrast, colour,
targets, type — but deliberately left its *layout* alone, and the result was a
panel that was more correct and looked identical. The layout problem it did not
address is a real one, and it is the HIG's plainest layout rule: **alignment
and proximity are what show which things are related.**

Every section sat in one `VStack` at a uniform 12pt. That put the artist's name
exactly as far from the track title as the CPU sparkline was from the agent
list. Six things, all equally related to each other, which is to say none of
them related to anything — the panel read as a column of unrelated widgets
rather than "what's playing" followed by "what this Mac is doing".

A second, compounding problem: `PlaylistSection` lived *inside* the column
beside the album cover. The cover's side tracks that column's measured height,
and the picker was the tallest thing in it, so the picker was what inflated the
cover to ~104pt — a header half again as tall as its content needed, and a
picker squeezed into ~230pt of width to show a playlist name in.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Uniform spacing, small headers on every section | Explicit; scannable | Four new labels cost ~56pt in a panel near its ceiling, and out-shout the content they name (UI Principle #1) |
| Control-Center-style plates behind each section | Strongest grouping; the platform idiom for a panel like this | ~64pt of padding added; plates on glass read muddy, and four of them is exactly the chrome UI Principle #1 forbids |
| Proximity + one hairline | Costs ~33pt total; no labels, no plates; groups are unmistakable | Less explicit than headers — relies on the reader noticing the gap |

### Decision

Two groups. The media block (header, scrubber, playlist) sits at 8pt internal
spacing; the system block (output, shelf, usage, agents) at 12pt; between them
`NotchMetrics.groupSpacing` (16pt) on each side of a 1px hairline.

The hairline is drawn **only when both groups have content**. Three of the four
system sections hide themselves when empty — an empty shelf, no live sessions —
so `hasSystemContent` is asked before the rule is drawn; a rule with nothing
under it is worse than no rule.

`PlaylistSection` moves out of the header column to full content width. The
column becomes title + artist + transport, the cover settles to its 72pt floor,
and the picker gets 353pt instead of ~230.

`panelHeight` goes 600 → 680. Net height change is about +31pt (playlist out of
the column +42, cover shrink −32, separator and its air +21), for ~556pt in the
fullest case — but the ceiling is a **hard clip, not a scroll**, and
overflowing it deletes the bottom section with no other symptom. The margin is
free: the window is transparent outside the drawn shape and passes clicks
through.

`reportExpandedHeight` now emits the measured height against the ceiling under
`TEMPO_DEBUG_VIZ=1`, so that failure mode is observable instead of having to be
noticed by eye.

### Verification

Driven live on the running bundle. The pointer was moved onto the notch to
expand the panel (Accessibility is granted to this terminal; Screen Recording
is not), and the laid-out geometry read back out of the accessibility tree:

```
WINDOW 405x680
  AXButton  x= 678 y= 49 w= 28 h= 28  Unmute                  <- was 16x16
  AXSlider  x= 714 y= 57 w=317 h= 12  Volume                  <- was unlabelled
  AXButton  x= 678 y= 85 w=152 h= 24  MacBook Air Speakers    <- was ~19pt tall
  AXButton  x= 836 y= 85 w=139 h= 24  Tempo Visualizer Tap
  AXButton  x= 678 y=174 w=353 h= 28  ApplicationBot, running <- state now spoken
  AXButton  x= 678 y=204 w=353 h= 28  Tempo, running
```

No overlapping frames; content starts at y=49 (33pt strip + 16pt padding) as
intended. The logged measurement was `panel content 215pt + strip 33pt = 248pt
of 680pt ceiling`.

### Consequences

- **The media half of this change is unverified.** Both players were paused
  when it was checked, so `showsMedia` was false and neither the restructured
  header, the scrubber, the playlist row nor the separator was on screen. What
  was verified is the system group and the 062 target/label fixes. Play
  something and hover to exercise the rest.
- Still not seen over a real desktop — Screen Recording is ungranted, so the
  scrim question from 062 remains open and the README screenshots remain stale.
- The cover is now ~72pt in the common case instead of ~104. `expandedArtMax`
  (116) is effectively unreachable unless a future row goes back into that
  column.
- A user with every module off and nothing playing gets an empty panel with no
  separator, which is correct but was not previously possible to reach.

---

## 064 — Album tint is painted, not delegated to `Glass.tint`

**Date:** 2026-08-26
**Status:** Accepted

### Context

Reported plainly: *"album tint doesn't actually change any of the colors."*

Three candidate causes, and it was worth separating them before touching
anything, because the fix differs for each: (a) no tint is being computed;
(b) a tint is computed but `Glass.tint` does nothing visible with it; (c) a
tint is applied but is too weak to see.

**(a) was ruled out by measurement.** With `TEMPO_DEBUG_VIZ=1` the running
bundle reported `artwork tint h=0.54 s=0.87 b=0.75` — an 87%-saturated cyan.
The colour existed and was vivid; it simply never reached the screen.

**(b) was confirmed by measurement.** Four glass variants were rendered through
`ImageRenderer` over an identical neutral-grey backdrop and their mean RGB read
back:

```
regular        R=0.502 G=0.502 B=0.502
tint red 1.0   R=0.502 G=0.502 B=0.502
tint red 0.55  R=0.502 G=0.502 B=0.502
tint blue 1.0  R=0.502 G=0.502 B=0.502
clear          R=0.502 G=0.502 B=0.502
```

Every variant is identical to the bare backdrop — including `.clear`, which
looks nothing like `.regular` on screen. `glassEffect` contributes **no pixels
to the view's own render tree**; it is a compositor parameter, applied out of
process. How much of a tint the compositor elects to show over a small dark
panel is therefore not something Tempo can set, only something it can hope for.

Two further defects were found by reading the code around it:

- `.regular.tint(color.opacity(0.55))` halved an already-subtle effect, with no
  recorded reason for the 0.55.
- The pre-macOS-26 branch was `shape.fill(style == .clear ? .ultraThinMaterial
  : .regularMaterial)` — so on macOS 14 and 15, **"Album tint" was byte-for-byte
  identical to "Regular glass."** The style has never worked at all there.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Raise the tint alpha and hope | One-line change | The measurement says the parameter contributes nothing observable; there is no alpha at which nothing becomes something |
| Tint the album colour into the *content* (text, glyphs) instead | No material work | Recolours the very things that must stay legible; fights the HIG's contrast rule |
| Paint an explicit wash over the glass | Real pixels, under our control, works on every macOS version and in the Settings preview | We are now drawing the tint rather than the platform; a future OS whose `Glass.tint` works well would double-tint |

### Decision

Draw the tint. `PanelTint.wash(for:)` derives a colour from the cover and it is
filled over the glass inside `glassLayer`, under the black top blend so the
notch seam stays black. `Glass.tint` is still passed (now at full alpha) so the
compositor contributes whatever it will on top.

The wash keeps the cover's **hue and saturation** and **caps its brightness** at
0.62. `NSImage.dominantColor()` floors brightness at 0.6 because it was feeding
`Glass.tint`, which wants a vivid colour; painting that unmodified costs
white-text contrast. Modelling the glass as flat grey, worst case across the hue
circle (saturated yellow):

| backdrop | no wash | capped 0.62 | uncapped |
| --- | --- | --- | --- |
| dark glass 0.15 | 15.08 | 10.99 | 8.17 |
| mid glass 0.45 | 4.76 | **4.44** | 3.44 |
| bright glass 0.75 | 1.83 | 2.09 | 1.71 |

The cap is what keeps the mid case near 4.5:1 rather than well under it. Note
the wash is *not* what makes the bright-backdrop case bad — the glass is already
at 1.83 there with no tint at all, and the wash slightly improves it.

The derivation lives in `PanelTint` (NotchStyle.swift) rather than in
`ContentView`, because `PanelStylePreview` must paint exactly the same thing:
that card's entire job is to show what choosing the style will do, and it was
previously showing "Album tint" as plain glass — faithfully reproducing the bug.

`AppState.artwork`'s `didSet` now logs the derived tint (or says the cover is
missing or unsamplable) under `TEMPO_DEBUG_VIZ=1`, so cause (a) is never again
something to guess at.

### Verification

The live tint value was read out of the running bundle, then fed through the
real `PanelTint.wash(for:)` and rendered:

```
over dark glass 0.15    R=0.174 G=0.287 B=0.319   colour spread 0.145  VISIBLE
over mid glass 0.45     R=0.442 G=0.533 B=0.563   colour spread 0.122  VISIBLE
over bright glass 0.75  R=0.666 G=0.747 B=0.771   colour spread 0.106  VISIBLE
no cover (control)      R=0.198 G=0.198 B=0.198   colour spread 0.000  neutral
```

Colour spread was 0.000 on every backdrop before. The no-cover control
correctly stays neutral, preserving the documented fallback.

### Consequences

- **Still not seen on screen.** Screen Recording is ungranted in this session,
  so the wash is verified as *pixels produced by the real derivation code*, not
  as a photograph of the panel. `PanelTint.washOpacity` (0.22) and
  `maxBrightness` (0.62) are the two knobs if it lands too strong or too weak.
- Album tint now works below macOS 26 for the first time.
- If a future macOS makes `Glass.tint` visibly effective, the panel will carry
  both it and the wash and may read too strong; `washOpacity` is where to
  correct that.
- The tint is drawn under the black top blend, so the top ~53pt of the panel is
  unaffected by design — the seam with the notch must stay black.

---

## 065 — No black silhouette where there is no notch, and the panel's alpha off the collapse spring

**Date:** 2026-08-27
**Status:** Accepted

### Context

Reported plainly: *"the weird black fade out animation that occurs when tempo
fades back into the top: it doesn't really feel that good."*

This was recorded rather than reasoned about. `screencapture -v -V 7 -R` over
the top of the display, with the pointer warped into and out of the hover
region by a small `CGWarpMouseCursorPosition` driver, then sliced at 25fps.
The frames named two separate defects in the close, on a notchless display
with **Settings ▸ General ▸ Show the strip on external displays** off — which
is this machine's configuration (LG ULTRAWIDE, `showStripOnExternalDisplays =
0`), and the only configuration in which either defect exists:

1. **A black slab.** `backgroundShape`'s always-present silhouette faded
   `0 → 1` on collapse. On a notched Mac that is right: the layer it is fading
   into is the black pill that hugs the notch. Here there is no notch, so what
   the frames showed was an opaque black rounded rectangle materialising at
   near-full panel width *on top of* the retracting glass, across someone
   else's menu bar, for a few hundred milliseconds.

2. **A ghost.** `panelOpacity` (the whole-panel alpha, which is what makes the
   panel appear and disappear at all when there is no strip to fall back to —
   decision 055) sat inside the scope of `.animation(expandAnimation, value:
   displayedExpanded)`, so it inherited the collapse spring. That spring is
   deliberately critically damped (`response: 0.45, dampingFraction: 1.0`) so
   the *geometry* never bounces on its way back into the notch — but a
   critically damped curve has a long tail, and an alpha on it stayed faintly
   visible for roughly half a second after the panel had finished retracting.

Both are invisible on a notched MacBook, which is why neither was caught when
the collapse animation was tuned.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Shorten the collapse spring | One number | Changes the retract on notched Macs too, where it is correct; and the black slab is not a timing problem |
| Drop the whole-panel fade, let it retract to the pill and stop | No alpha to tune | The pill is not drawn in this mode — the panel would vanish on a frame boundary |
| Cross-fade the silhouette in *late* via a keyframed curve | Keeps the retract-to-black feel | Black is only ever right because it merges with the notch; there is no notch here, so there is nothing for a late fade to merge into |
| Don't draw the black at all here, and give the alpha its own short ease | Removes the cause of each defect independently; both are scoped to the one configuration that has them | Two changes rather than one |

### Decision

Both, because they are two independent defects:

- `backgroundShape`'s silhouette is `.opacity(displayedExpanded || stripHidden
  ? 0 : 1)`. Black is only ever right because it merges with the notch, so
  where there is no notch it is not drawn. The layer stays in the hierarchy at
  zero alpha for the reasons already recorded there (it must not be introduced
  by a branch flip), and its geometry report goes unread in exactly this case
  anyway: `NotchHostingView.activeRect` short-circuits to `.zero` for strip-off
  + notchless + shut (decision 055).

- `.opacity(panelOpacity)` moves **outside** every `expandAnimation` modifier
  and takes its own `fadeAnimation` — `.easeOut(duration: 0.18)`, or `0.15`
  under Reduce Motion. Placed there, the `expandAnimation` modifiers are still
  the closer animation for the frame and the shape, so the retract spring is
  untouched; only the alpha changes curve.

The alpha now reaches zero while the geometry is still settling, so the visible
close on a notchless display is a clean ~0.15s dissolve rather than a retract
the user watches fade. That is the honest animation for this mode: there is no
notch on that display for the panel to retract *into*.

### Verification

Recorded before and after with the same driver, sliced at 25fps and read frame
by frame:

| | before | after |
| --- | --- | --- |
| black slab over the menu bar | present, ~full panel width, ~5 frames (0.2s) | **absent in every frame** |
| dim ghost after the retract | ~12 frames (0.48s) | **absent** |
| close, first fade to fully gone | ~15 frames (0.6s) | ~3–4 frames (0.15s) |
| open | no black flash | no black flash, unchanged |

Notched-Mac behaviour is unchanged by construction: `stripHidden` is false when
there is a hardware notch, so the silhouette still fades in exactly as before,
and `panelOpacity` is a constant `1` there, so `fadeAnimation` never fires.

`scripts/capture-panel-animation.sh` is that harness, kept (Agent Guideline #8)
so the next animation change is checked against frames rather than described.

### Consequences

- **Screen Recording is granted in this session** — the first time it has been
  (see decision 064's consequences, which had to verify pixels through
  `ImageRenderer` instead). Panel animations can now be checked on screen.
- The close on a notchless display no longer visibly retracts; it dissolves.
  If that reads as too abrupt, `fadeAnimation`'s duration is the one knob, and
  raising it lets more of the retract show before the alpha reaches zero.
- Rebuilding the ad-hoc-signed bundle reset its audio-capture TCC grant
  mid-session and put a system dialog on screen, which swallowed one recording.
  That is the failure `scripts/make-app.sh` already warns about, unchanged by
  this work.

---

## 066 — Quit lives in Settings ▸ About

**Date:** 2026-08-27
**Status:** Accepted

### Context

Requested plainly: *"lets include the option to quit tempo on the settings
page."*

The gap is real and was not deliberate. Tempo is `LSUIElement` (decision 002):
no Dock icon, no menu-bar item. `AppDelegate.makeMainMenu()` does build an app
menu carrying **Quit Tempo** at ⌘Q, but its titles are never displayed — that
menu exists so the key equivalents work — and an `LSUIElement` app's main menu
is only active while one of its windows is key. In practice that means ⌘Q works
*only* while the Settings window is in front, which is not a way out anyone can
be expected to find. Quitting from Activity Monitor was the honest answer, and
that is not an answer.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| A menu-bar extra with Quit in it | The conventional home for it | Tempo's whole premise is that the notch replaces the menu-bar item; adding one back contradicts the product |
| A Quit control in the notch panel | Fewest clicks | The panel is a glanceable surface, not a menu (UI Design Principle #3), and a quit button one hover away from the pointer is the wrong thing to be able to hit by accident |
| Settings ▸ General, at the bottom | Discoverable; the pane most people open first | General is a pane of *preferences*; quitting is not one, and it would sit under a heading it doesn't belong to |
| Settings ▸ About | Sits with **Show the welcome again**, the pane's other app-level *action*; already the pane about Tempo-the-app rather than Tempo's behaviour | One pane further in |

### Decision

Settings ▸ About, in its own section below the version. `AboutPane` is no
longer only "about" — it is what Tempo is, plus the two things you can do *to*
Tempo rather than configure about it, and its doc comment now says so.

`NSApplication.shared.terminate(nil)` rather than `exit()`, so
`applicationWillTerminate` runs: it stops the services and, in particular,
withdraws the lock-screen cards. Leaving those in Notification Center after the
app that posted them is gone is a signal with nothing behind it, which is the
same rule as UI Design Principle #4.

**No confirmation sheet.** Quitting Tempo destroys nothing and is undone by
opening it again; a confirmation would be a detour for its own sake. The footer
carries what the user actually needs to know instead — that Tempo has no Dock
icon or menu-bar item, so this pane is the way back out, and how to get it
back.

### Verification

Clicked in the running bundle, with the pane captured on screen first: the
section renders as **Quit** / *Quit Tempo* below the version, in the same
`LabeledContent` shape as **Show the welcome again** above it.

```
before: 1 tempo, 1 adapter
after:  0 tempo, 0 adapter
```

Both processes are gone, so `applicationWillTerminate` did run — the
MediaRemote `perl` child not outliving the app is the reason that method
exists at all.

**Found while verifying, not caused by this change:** `scripts/make-app.sh`
quits the running Tempo with a bare `kill` (SIGTERM). AppKit does not turn
SIGTERM into `NSApplication.terminate`, so the default disposition kills the
process outright and `applicationWillTerminate` never runs — orphaning the
adapter on every rebuild. One such orphan (PID 27457, PPID 1) had been
streaming to a dead pipe for six hours. It usually goes unnoticed because
SIGPIPE collects it on the next write; it survives exactly when nothing is
playing, which is the same case the method's own comment already calls out.
Left alone here rather than folded into an unrelated change (Agent Guideline
#7) — see **Now** in `NEXT_STEPS.md`.

### Consequences

- The main menu's ⌘Q is unchanged and still works; this adds a second, findable
  path rather than replacing it.
- Nothing else in Tempo can terminate the app, so this is the only new way to
  lose the panel — and it is behind two clicks (gear, About), which is about
  right for an action you take once.

---

## 067 — SIGTERM and SIGINT are routed through `NSApplication.terminate`

**Date:** 2026-08-27
**Status:** Accepted

### Context

Found while verifying decision 066, not reported: an orphaned
`/usr/bin/perl mediaremote-adapter.pl` with PPID 1 that had been streaming to
a pipe no one reads for six hours.

`scripts/make-app.sh` SIGTERMs the running Tempo before it relaunches the new
build. **AppKit does not turn SIGTERM into a quit.** The kernel's default
disposition kills the process outright, so `applicationWillTerminate` — the
only thing that reaps the MediaRemote child and withdraws the lock-screen
cards — never runs. Every rebuild leaked an adapter. It usually goes unnoticed
because SIGPIPE collects the child on its next write; it survives exactly when
nothing is playing, which is the case `applicationWillTerminate`'s own comment
already called out. ⌃C on a foreground `swift run` (SIGINT) leaks identically.

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| `osascript … to quit` in the script | Script-only change; no app code | Sending an Apple Event needs **Automation** TCC approval for the invoking terminal — a new permission prompt in a script that has never needed one. Fixes one caller, not the signal |
| Reap the orphan in the script after killing | Simple, no app code | Treats the symptom; every other SIGTERM sender (`killall`, a shell's ⌃C, a future script) still leaks |
| Handle the signal in Tempo | Fixes the cause once, for every sender, with no new permission | ~10 lines of app code, and the naive spelling silently does nothing (below) |

### Decision

Handle it in Tempo. `AppDelegate.installSignalHandlers()`, first thing in
`applicationDidFinishLaunching`: `signal(sig, SIG_IGN)` to take the default
disposition out of the way, then a `DispatchSourceSignal` whose handler calls
`NSApp.terminate(nil)` — never in signal context, where `terminate` is nowhere
near async-signal-safe. SIGINT as well as SIGTERM, because ⌃C is the same
defect through a different door.

**The source runs on a global queue, not `.main`, and that is load-bearing.**
The obvious spelling — `makeSignalSource(signal:queue: .main)`, handler calls
`terminate` directly — compiles, installs, and never fires in this app. It was
measured, not guessed: with the source on `.main` the handler produced no log
line at all, while `SIG_IGN` *had* taken effect, so Tempo simply became immune
to SIGTERM — strictly worse than the bug being fixed. Moving only the queue to
`.global()` made the identical handler fire immediately. A main-queue source
can deliver only when the main run loop drains the main queue, and this app was
not doing so when the signal landed. Signal delivery must not depend on that,
so the quit is hopped back to main explicitly instead.

The script keeps its bare `kill` — deliberately, and its comment now says why —
so it needs no Automation grant, and it keeps its existing wait-for-exit loop
and its no-SIGKILL rule.

`make-app.sh` also gained a backstop for adapters orphaned *before* this
landed, or by any SIGKILL, which no in-app handler can catch. Candidates were
selected by **PPID 1**, which is exactly what "orphaned" means here: the
adapter is spawned as a child of the app, so its parent is only `launchd` once
that app is gone.

> **Superseded by decision 068.** That backstop was written without noticing
> that `MediaRemoteService.reapOrphanedStreams()` had done the same job, by the
> same PPID-1 rule, since 2026-08-22 — and does it on *every* Tempo launch
> rather than only on a build. The script copy is removed; 068 fixes the real
> reason the existing reaper was missing orphans.

### Verification

Every path measured on the real bundle:

```
SIGTERM   before: tempo=49106 adapter=49109
          tempo exited after 0.04s
          adapter left: []
SIGINT    before: tempo=49158 adapter=49161
          after:  tempo=[]    adapter=[]
make-app  before: tempo=49603 adapter=49606
          ==> Quitting the running Tempo (PID 49603)…
          ==> Relaunching Tempo…
          after:  tempo=[49737] adapter=[49744]      (one each, no orphan)
```

The backstop was tested against a real orphan, made the only way one can still
occur:

```
kill -9 49315   →  tempo=[] adapter=[49319], ps -o ppid = 1
==> Reaping 1 orphaned mediaremote-adapter process(es)…
orphan left: []
```

Two bugs in this change were themselves caught by running it rather than
reading it: the first `pgrep` pattern was absolute, which misses a process
launched through the other spelling of this case-insensitive repo path (the
trap the `RUNNING_PIDS` comment two lines up already documents), and the reap
was inside the was-running branch — skipping the one case it exists for, an
orphan left by a previous session with nothing running now.

### Consequences

- `kill`, `killall tempo` and ⌃C are all clean quits now: cards withdrawn,
  adapter reaped. Only SIGKILL still leaks, and nothing in-process can change
  that — which is why the script keeps the backstop.
- Tempo ignores SIGTERM's default disposition permanently. If the dispatch
  source ever fails to install, the app becomes unkillable by SIGTERM rather
  than merely leaky; the `.main`-queue measurement above is that failure mode
  observed, and is why the queue choice carries the comment it does.
- The handler logs one line under `TEMPO_DEBUG_VIZ=1`, which is how the
  `.main` failure was distinguished from a `terminate` that ran and hung.

---

## 068 — SIGKILL is unfixable; the orphan it leaves is not

**Date:** 2026-08-27
**Status:** Accepted

### Context

Follow-on from decision 067, which closed SIGTERM and SIGINT and left one hole
open: *"lets see if we can fix the sigkill."*

**SIGKILL cannot be caught, blocked or ignored.** That is a kernel guarantee,
not an API gap, and no amount of app code changes it. So the goal was restated
as the thing actually wanted — *no orphaned adapter survives* — and that turns
out to be a question about the child, not the signal.

Reading the code for it turned up something that should have been read first:
`MediaRemoteService.reapOrphanedStreams()` has done exactly this job since
2026-08-22 — same PPID-1 rule, run on every `start()`. **The backstop added to
`make-app.sh` in 067 was a second implementation of an existing one**, written
because the existing one was never looked for.

Which raised the real question: if Tempo already reaps orphans on every
launch, how did the orphan in 067 survive six hours and every relaunch in
between?

Measured, and the answer is a one-word bug:

```
launched with `open`  → /Users/…/Documents/code/Tempo/dist/Tempo.app/…
exec'd off a shell    → /Users/…/documents/code/tempo/dist/Tempo.app/…
```

`Bundle.main.resourcePath` reports the bundle **the way it was reached**.
Through LaunchServices it is the canonical on-disk case; exec'd straight off
whatever path a shell was sitting in — the dev route — it keeps that shell's
spelling. The filesystem is case-insensitive so both name the same file, both
appear in `ps`, and `reapOrphanedStreams` compared them with
`line.contains(script)` — exact, case-sensitive. Every orphan left by a
directly-exec'd Tempo was invisible to every Tempo started with `open`. That
is precisely PID 27457's six hours.

### Options considered

Making the child die *immediately* on SIGKILL, rather than at the next launch,
needs the child to notice the parent is gone. It cannot be told:

| Option | Pros | Cons |
| --- | --- | --- |
| `PR_SET_PDEATHSIG` | Exactly this feature | Linux only; Darwin has no equivalent |
| Adapter exits on stdin EOF — Tempo holds the write end, so any death closes it | No polling, no wakeups, immediate | `mediaremote-adapter.pl` never reads stdin (checked), and it is vendored third-party code — teaching it to would mean forking it |
| `sh` wrapper: run perl, block on `cat` reading the inherited pipe, kill perl at EOF | No polling; immediate; no forking of vendored code | Turns one child into three, and `streamProcess` becomes the `sh` — so `terminate()`, `terminationHandler` and the restart path all change meaning. Real risk to working behaviour for an idle process |
| Poll the parent PID from a shell wrapper | Simple | A timer that never sleeps, forever, in a background app, to catch an event that needs a `kill -9` |
| Fix the existing reaper and accept "dies at next launch" | One line; no new processes; uses machinery that already exists and is already trusted | The orphan lives until Tempo next starts |

### Decision

Fix the existing reaper: compare with
`line.range(of: script, options: .caseInsensitive) != nil`. Remove the
duplicate backstop from `make-app.sh` — one rule, in the app, where it can run
on every launch instead of only on a build.

**Do not chase immediate death.** The orphan is a perl process blocked in a
run loop at ~0% CPU; it costs a process-table entry and a MediaRemote
subscription until Tempo next starts, and Tempo is a login item. Trading that
for three processes and a rewritten child-lifetime contract is a bad deal, and
`terminate()` / `terminationHandler` / the restart path are exactly the code
that must not quietly change meaning (Agent Guideline #7).

### Verification

The six-hour scenario reproduced end to end — a SIGKILL of a directly-exec'd
Tempo, then a relaunch through `open`, which is the mismatched pair:

```
fixed    orphan 52594 (ppid 1, lowercase path)  →  after relaunch: 52619 only
control  orphan 52878 (ppid 1, lowercase path)  →  after relaunch: 52878, 52899
```

The control is the same test with `line.contains(script)` restored: the orphan
survives alongside the new adapter, so the case-insensitive compare is what
fixes it rather than luck. Restoring the fix reaped the control's leftover on
the next launch.

### Consequences

- SIGKILL still orphans an adapter. It always will. The window is now "until
  Tempo next starts" for real, rather than "until a Tempo started the same way
  next starts", which is what it silently was.
- Two places no longer implement one rule. `reapOrphanedStreams` is the only
  reaper.
- The lesson is cheaper than the bug: `Bundle.main.resourcePath` is not
  canonical, and any code comparing it against a path from `ps` — or from
  `pgrep -f` in a script, which bit this same session twice — has to be
  case-insensitive or suffix-matched.

---

## 069 — Accent colour, floored on luminance rather than brightness

**Date:** 2026-08-27 · **Status:** Accepted

### Context

boringNotch exposes an accent colour — system or custom, with presets — and it
is the cheapest customization in either competitor: it tunes something that
already exists rather than adding a subsystem. Tempo had no accent concept at
all; a repo-wide grep for "accent" returned four incidental
`Color.accentColor` uses and nothing else.

The problem is contrast. The panel is forced to dark appearance
(`NSAppearance(named: .darkAqua)`), and a user can pick any colour, including
one that is invisible on it.

### Options considered

| Option | Verdict |
|---|---|
| Take the pick as typed | Rejected — `#001F5B` measures 0.97:1 on the panel. A control drawn in it is a control nobody can see. |
| Cap HSB brightness, as `PanelTint.wash` does | Rejected — wrong knob for an accent. `#0000FF` is *already* at brightness 1.0 and still measures 1.76:1, so a brightness floor leaves it exactly as invisible. |
| Floor WCAG relative luminance by mixing toward white | **Chosen.** Preserves hue exactly, spends only saturation, and targets the thing that actually governs legibility. |

### Decision

`NotchAccent.legible(_:)` bisects toward white in 16 steps until relative
luminance clears a floor: `0.16` normally and `0.27` under Increase Contrast —
the values giving 3:1 (WCAG's non-text/UI minimum) and 4.5:1 against the same
flat-grey backdrop model `PanelTint` used.

The accent **never reaches `AgentAppearance`**. Those hues carry state, and
decision 062 measured the state encoding at 827/2500 on a greyscale render
precisely because it is multi-channel; letting a user recolour it would undo
that. UI Principle #2.

### Verification

Measured across the eight macOS system accents and three deliberately dark
picks:

| accent | as typed | floored 0.16 | floored 0.27 |
|---|---|---|---|
| Blue / Purple / Graphite / Yellow | 3.76 / 3.65 / 4.63 / 9.98 | unchanged | 4.60 / 4.60 / 4.63 / 9.98 |
| `#0000FF` | 1.76:1 | 3.02:1 | 4.60:1 |
| `#001F5B` | 0.97:1 | 3.02:1 | 4.60:1 |
| `#000000` | 0.72:1 | 3.02:1 | 4.60:1 |

The load-bearing result: **all eight system accents already clear the normal
floor**, so the shipped default passes through byte-identical and the clamp
fires only on a pick that would otherwise be invisible.

### Consequences

Increase Contrast is read via
`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` rather than the
SwiftUI environment, because these are static tokens with no view to read an
environment from. Toggling the setting therefore takes effect at the next
redraw, not instantly. Noted rather than fixed: the alternative is threading an
environment value through every token call site for a setting people change
approximately never.

---

## 070 — Album glow and blur are painted, and live only in the expanded header

**Date:** 2026-08-27 · **Status:** Accepted

### Context

Asked for, from boringNotch: "a bit of a light behind albums." Reading its
string catalogue shows it is not one feature but two independent switches —
**Enable glowing effect** and **Enable blur effect behind album art** — plus a
separate window shadow. They read as different looks and people want them
separately.

### Options considered

| Option | Verdict |
|---|---|
| Extend `panelStyle: .tinted` | Rejected — that is a wash *over* the glass across the whole panel. This is a bloom *behind one element*, spilling past its edges. Different layer, different geometry. |
| Express the glow as a `Glass` tint / material hint | Rejected outright — decision 064 measured that `glassEffect` contributes **no pixels** to this view's render tree. A glow written that way would have been invisible for exactly the reason the album tint was for six weeks. |
| Paint real fills and real blurs behind the clipped artwork | **Chosen.** |
| Draw it in the collapsed pill too | Rejected — see below. |

### Decision

`albumAmbience(side:cornerRadius:)` draws, behind the clipped cover: the bloom
(cover's dominant colour, blurred and over-scaled, radius and alpha both
scaling off one `albumGlowStrength` control) and beneath it, optionally, a
blurred over-scaled copy of the cover itself. Neither takes clicks.

**Expanded header only.** In the collapsed pill the bloom would spill past the
black silhouette and hang in the air beside the notch — precisely the artefact
the silhouette exists to prevent, and the same class of defect decision 065
fixed on notchless displays.

Suppressed entirely under Reduce Transparency: a bloom is decoration spilling
past the thing it decorates, which is what that setting asks apps to stop
doing.

### Verification

Builds clean. **Not yet seen on screen** — see Consequences.

### Consequences

The strength control folds radius and alpha together so one slider spans
"barely there" to "unmistakable" rather than shipping two knobs for one
sensation. Whether the chosen curve actually feels right is a matter of
looking at it, and that has not happened yet.

---

## 071 — Coloured spectrogram: hue follows the band, not the bar

**Date:** 2026-08-27 · **Status:** Accepted

### Context

Every visualizer bar was `Color.white.opacity(0.92)`, flat, with zero hue
variation. boringNotch ships a colored-spectrogram option. Tempo is already
ahead of it on data — decision 016's tap publishes five real FFT band
magnitudes, where boringNotch's visualizer is playback-synced animation — so
this is a colour mapping over numbers that are already being computed, not a
new capture path.

### Decision

Four palettes: `.monochrome` (default), `.accent`, `.album`, `.spectrum`.

The load-bearing detail is `.spectrum`. Bars are laid out through
`barToBand = [3, 1, 0, 2, 4]` — bass deliberately in the **centre** bar. Hue is
therefore indexed by *band*, not by bar position, so warm sits in the middle
with the bass and cools outward and the colour ramp is symmetric the way the
layout is. Indexing by bar would have produced a ramp that visibly disagreed
with the shape it was colouring.

`.album` runs the artwork tint through the same luminance floor as 069:
`dominantColor()` floors HSB brightness at 0.6, and a saturated blue cover at
0.6 measures **1.05:1** on the dark panel — bars that are drawn and invisible.

### Verification

`.monochrome` is the same `Color` value at the same call site — pixel-identical
to the flat white it replaced, so an install that never opens Settings is
unchanged (Agent Guideline #7). `.spectrum`'s five fixed values measure
6.10 / 10.59 / 11.92 / 9.97 / 4.77:1, clearing 4.5:1 under either contrast
setting with no runtime clamp. The colour path reads no motion state, so
Reduce Motion and the settle-when-paused behaviour are untouched.

**Not yet seen on screen.**

---

## 072 — Sneak peek

**Date:** 2026-08-27 · **Status:** Accepted

### Context

The expanded panel already answers "what's playing" — but only after moving the
pointer to the notch and waiting out the hover dwell. A track change is the one
moment that answer is wanted *without* being asked for. This is boringNotch's
Sneak Peek, and it is the most on-mission thing it does: pure glanceability,
no expansion.

### Decision

A track change raises title and artist below the pill for
`sneakPeekSeconds`, then retracts. It draws in the transparent part of the
window under the notch and sets `allowsHitTesting(false)`; the window's hit
region is the drawn silhouette only (decision 012), so it is pixels over
whatever app is behind and nothing more.

Only a real change to a *named* track counts. Startup, a stop, and the artwork
arriving a beat after the title all pass through the same `onChange` and none
of them is a track change worth interrupting for. Suppressed while the panel is
open, where it would repeat what is already on screen an inch above it.

### Verification

Builds clean. **Not yet seen on screen** — in particular, that it does not
collide with the hover-expand region has been reasoned from decision 012's hit
model but not watched.

---

## 073 — The media inactivity timeout becomes a setting

**Date:** 2026-08-27 · **Status:** Accepted · **Amends 038**

### Context

`MediaRemoteService.mediaIdleTimeout` was a hard-coded 60 seconds with a
documented rationale: "a pause to take a call, a scrub, or an app switch is a
gap in playback, not the end of listening." The rationale is right; the
*number* was always taste. boringNotch exposes the same knob.

### Decision

It reads `Preferences.mediaIdleSeconds`. Default stays 60, so an install that
never touches the slider behaves exactly as before (Agent Guideline #7). `0`
means never drop the media UI, and is handled by not scheduling a timer at all
rather than by scheduling one that fires immediately.

---

## 074 — Transport slots, and the control that is deliberately missing

**Date:** 2026-08-27 · **Status:** Accepted

### Context

boringNotch's control-slot editor is the best customization idea in either
competitor: five slots, drag-and-drop, a live preview. It personalizes without
adding features. Tempo's transport row was three hard-coded `Button` literals
in one `HStack` — no model, no identity, no `ForEach`.

### Options considered

| Option | Verdict |
|---|---|
| Mirror boringNotch's palette (shuffle, repeat, volume, …) | Rejected — `MediaRemoteService` exposes previous / play-pause / next and nothing else. A shuffle button that cannot shuffle is a lying control (UI Principle #4). |
| Include add-to-playlist | Rejected — it needs a *target* playlist, and that selection is state owned by `PlaylistSection`, which already carries its own add button. A slot with no playlist chosen would be the same lying control. |
| Render empty slots as zero-width boxes | Rejected — with equal spacers, two extra participants redistribute the spacing and shift the three default buttons inward. |

### Decision

Five slots over `MusicControl` — `none / previous / playPause / next / mute` —
drag-and-drop **and** menu-editable. The menu is not a fallback: drag-and-drop
alone is unreachable by keyboard and VoiceOver, and decision 062 made
accessibility a standing requirement here.

Empty slots are **filtered out of the layout**, not rendered zero-width. With
the default `[none, previous, playPause, next, none]` that leaves exactly three
buttons and four spacers — byte-identical to the hard-coded row it replaced,
including the play button landing on the column's centre line under the title.

---

## 075 — The strip can be pinned to a display, by UUID

**Date:** 2026-08-27 · **Status:** Accepted · **Amends 037**

### Context

`resolveScreen()` always preferred the built-in notched display, falling back
to the menu-bar display. Correct default, no override. boringNotch has both a
preferred-display picker and an auto-switch toggle, and its own preferences
store a `preferred_screen_uuid`.

### Options considered

| Option | Verdict |
|---|---|
| Store `CGDirectDisplayID` | Rejected — macOS reassigns them across reconnects, so a monitor unplugged and plugged back in becomes a different display. |
| Store `localizedName` | Rejected — two identical monitors share it. |
| Store `CGDisplayCreateUUIDFromDisplayID` | **Chosen.** Stable across reconnects; what boringNotch settled on too. |

### Decision

`preferredDisplayUUID`, empty meaning automatic. A pin to a display that is not
currently attached falls through to the existing automatic order rather than
leaving the panel nowhere.

Two mechanics were load-bearing:

- **`applyGeometry(force:)`.** `refresh()` returns "did anything change?" by
  comparing notch dimensions and screen *frame* by value. Two identical
  external monitors report identical frames, so the pin would have moved the
  target screen without the panel following. The pin path forces.
- **A nonisolated mirror of the preference.** `resolveScreen()` is reached from
  `targetScreen`'s lazy static initialiser, which carries no actor, while
  `Preferences` is `@MainActor`. Marking `NotchGeometry` `@MainActor` was tried
  first and rejected: `NotchHitRegion` seeds its geometry from a nonisolated
  context and stops compiling. The mirror is written only from `Preferences`,
  which is main-actor isolated.

---

## 076 — Full-screen behaviour

**Date:** 2026-08-27 · **Status:** Accepted

### Context

The panel overlaid full-screen apps unconditionally. Agent Guideline #3 says
never fight the user for the screen, and a full-screen video or a presentation
is exactly when a strip pinned to the notch is in the way. boringNotch offers
three choices; Tempo had none.

Note the history: decision **022** tried to solve full-screen by dropping the
panel below the top edge, and was reverted the same day. This is the other
approach.

### Options considered

| Option | Verdict |
|---|---|
| Walk the window list for a full-screen window | Rejected — needs Accessibility, which Tempo does not otherwise require. |
| Private CoreGraphics Space APIs | Rejected — undocumented, version-fragile. |
| Compare `visibleFrame` to `frame` | **Chosen.** A Space showing a full-screen app hides the menu bar, so `visibleFrame` reaches `frame`'s top edge; in an ordinary Space the menu bar keeps them apart. Costs nothing, needs no grant. |

### Decision

Three-way: never hide (the default, and the behaviour every prior build had),
hide for the app that's playing, hide for all apps.

`.fullScreenAuxiliary` — the collection-behaviour flag that lets a
non-activating panel draw over a full-screen app at all — is dropped for "hide
for all apps". The per-app case additionally orders the window out, because a
Space that is *already* full screen does not re-evaluate collection behaviour
on its own.

"Hide for the app that's playing" matches `NowPlaying.sourceBundleID` against
`NSWorkspace.frontmostApplication`, which is the app owning the full-screen
Space. This was caught in review: a first cut hid whenever the menu bar was
hidden regardless of *which* app was full screen, which made the option
behave identically to "hide for all apps" — a control whose label promised
something it did not do (UI Principle #4).

Both `activeSpaceDidChangeNotification` and
`didActivateApplicationNotification` are watched. One edge alone is not enough:
activating a different app can land on a Space that is already full screen, and
without the second edge the panel stays hidden after the user has left.

### Verification

Builds clean. **Not verified against a real full-screen app** — the
`visibleFrame` heuristic is reasoned and cheap, but whether it fires correctly
on every full-screen style (native full screen, a game, a video player that
hides the menu bar without taking a Space) has not been watched. This is
exactly the class of claim Agent Guideline #4 exists for.

---

## 077 — Hide from screen capture

**Date:** 2026-08-27 · **Status:** Accepted

### Context

Tempo draws agent lights, session labels derived from `cwd`, and token figures.
That is precisely the content that should not land in a screen share. Both
competitors offer this; Notchy scopes its version to Zoom/Meet/Teams/OBS.

### Decision

`sharingType = .none` on the panel, behind `hideFromScreenCapture`, off by
default.

This is a window-server flag rather than a drawing trick, which matters after
decision 064: the album tint failed because it was expressed as a compositor
hint the compositor declined to honour. `sharingType` is enforced by the window
server itself and applies to every capture path — screen sharing,
`screencapture`, and recording alike.

### Consequences

It also hides the panel from Tempo's *own* development capture path.
`scripts/capture-panel-animation.sh` records the panel opening and closing;
with this setting on, those frames come back empty. Off by default, so the
default development workflow is unaffected.

---

## 078 — The pill still cannot be shown while locked, and the screen saver is the same thing here (rejected)

**Date:** 2026-08-27 · **Status:** **Rejected** — preference written, then removed before shipping

### Context

Notchy's settings carry the string *"Keep the pill visible while locked or in
screen saver."* Taken at face value that contradicts decision **036**, which
implemented lock-screen drawing, measured it, and reverted it.

### What 036 established

macOS does not draw the lock screen as a very high window that other windows
can be ordered above; it composites it in a separate secure context that does
not include user-session windows. 036 proved this by putting four opaque
labelled strips on screen simultaneously at levels 1000, 2002, 2005 and
2147483629 — bracketing `loginwindow`'s own windows from below, between, just
above, and far above. **Locked, none of the four was visible.** Window level is
not the variable; there is no value of it that works.

### What was checked this time

The escape hatch would have been that a screen saver is *not* a lock — an
unlocked screen saver is an ordinary user session where windows composite
normally, so a level above `kCGScreenSaverWindowLevel` could plausibly work.

`sysadminctl -screenLock status` reports **"screenLock delay is immediate"** on
this machine. The screen saver here therefore *is* the lock screen, and
inherits the secure context 036 measured windows out of.

### Decision

Rejected. A `showDuringScreenSaver` preference was written, then removed before
it shipped — a setting whose promise cannot be kept on this configuration is a
lying control, and UI Principle #4 makes a wrong signal worse than no signal.

The sanctioned surface for a locked glance remains the notification cards of
decisions 053–059, which already exist and already work.

### Consequences

This was not verified by locking the screen. With the lock delay immediate,
triggering the screen saver would have locked the user out of a live session
mid-task; the configuration read is sufficient to settle it without that. If
someone later sets a non-zero lock delay, the unlocked-screen-saver case
becomes worth re-testing — and *only* then.

---

## 079 — Token history and an estimated pace bar, from transcripts

**Date:** 2026-08-27 · **Status:** Accepted

### Context

Notchy's AI Usage tab is the most complete thing either competitor does, and
its most valuable number is rate-limit pace — the thing that actually bites a
Claude Code user. Tempo already read Claude Code transcripts for per-session
figures (decision 048) but had no aggregation over time and nothing about
budget.

### The source question

| Source | Verdict |
|---|---|
| `~/.claude/stats-cache.json` | **Rejected.** It has exactly the right shape — `dailyActivity`, `dailyModelTokens`, `modelUsage` — and is unusable: measured `lastComputedDate` 10 days stale, its own last populated day 13 days behind, and every `costUSD` / `contextWindow` field zero. |
| A real rate-limit signal on disk | **Does not exist.** Searched transcripts and telemetry for `rate_limit`, `resetsAt`, `retryAfter`, `unified_rate_limit`: no matches. Notchy's own strings concede the same — "Usage is estimated, not exact", "Estimated: %@ session quotas left". |
| Transcripts | **Chosen.** Verified every assistant message carries `model`, `usage` and `timestamp` — zero gaps across 601 sampled messages spanning the full corpus. |

### Decision

`UsageHistoryService` scans transcripts on a 60s timer, off the main actor.

**Counting: input + cache-creation + output, excluding cache reads.** This
matches `SessionStatsService`'s existing convention and is not cosmetic —
cache reads dominate raw totals (measured: 175M of 180M on one real day), so
counting them would have made every figure on both surfaces meaningless.

The pace bar is **an estimate and says so on its face** (header reads
`5H PACE · ESTIMATE`). The budget it measures against is user-set, because the
real limit is account-dependent and Anthropic does not publish it anywhere
Tempo can read. Settings shows the measured busiest window beside the slider so
the number can be calibrated rather than guessed.

Off by default, both switches. It is a wider read than the per-session figures
— every project's transcripts rather than one session's — so it is opt-in
(Agent Guideline #5). Only timestamps, model ids and token integers are ever
retained; no `cwd`, no `task`, no `detail`, no paths.

### Verification

Measured on this machine, cross-checked against an independent rollup — every
closed day matches to the token:

| day | tokens |
|---|---|
| 2026-08-21 | 478,114 |
| 2026-08-22 | 4,379,222 |
| 2026-08-23 | 0 (real gap day, present and zeroed) |
| 2026-08-24 | 5,268,175 |
| 2026-08-25 | 8,181,418 |
| 2026-08-26 | 4,944,457 |

Busiest five-hour window: **5,295,766**. Top model: Opus 5.

Cost: mtime prefilter takes 1291 files to 699 for a 7-day window; cold scan
2.2s debug / 1.4s release, cached rescan **0.052s**. Swapping `Data.range(of:)`
for `memmem` on the pre-filter cut the cold scan 4.8s → 2.0s.

That measured 5.30M peak is why the default budget is **10M**, not the 5M first
written: a 5M default would have shown a bar reading 106% on the first day it
was switched on, which is a false alarm rather than a signal.

### Consequences

The figures are honest about being estimates and cannot become exact without a
signal Claude Code does not currently write. If one ever appears, this service
is the place it would replace the estimate — the views already carry the
"estimate" label that would then come off.

---

## 080 — Settings goes from five panes to eight

**Date:** 2026-08-27 · **Status:** Accepted · **Amends 020**

### Context

Decisions 069–079 add roughly seventeen preferences. Settings had five panes —
General, Music, Weather, Modules, About — and Modules was already the catch-all
that everything without an obvious home had drifted into.

### Decision

Eight panes: General, **Appearance**, **Displays**, Music, **Agents**, Weather,
Modules, About.

Appearance takes the panel style and its preview out of Modules and gains the
accent, album glow and blur, and the spectrogram palette. Displays takes the
display section out of General and gains the display pin, full-screen
behaviour, and capture exclusion. Agents takes the agent toggles and the
collapsed-light picker out of Modules and gains the usage and pace controls.
Modules keeps only what it was named for: which modules appear in the notch.

The rule applied throughout: a pane is a place a *kind* of question gets
answered, not a bucket. Every footer states the mechanism and the caveat, which
is the voice the existing footers already had.

---

## 081 — The sneak peek inherited the hidden strip's alpha, and the notification calls could hang

**Date:** 2026-08-27 · **Status:** Accepted · **Fixes 072**

### Context

Two things reported missing on a clamshell Mac driving one external display:
the sneak peek (decision 072, shipped hours earlier) and the lock-screen
cards (decisions 053–059, months old). They turned out to be unrelated, and
only the first was a defect.

### The sneak peek — a real bug, and mine

`panelOpacity` is `(stripHidden && !displayedExpanded) ? 0 : 1`, and
`stripHidden` is `!showStripOnExternalDisplays && !isHardwareNotch`. On this
machine both hold: `AppleClamshellState = Yes` (lid shut, so no built-in notch
in `NSScreen.screens`) and the user had **Show the strip on external displays**
switched off.

The peek's `.overlay` sat at line 347 and `.opacity(panelOpacity)` at line 380
— so the alpha applied to a *parent* of the overlay. Every time the peek fired
it was drawn at zero alpha. It was never going to be visible in that
configuration, which is the configuration most in need of it: with no strip
drawn, a track change has no other surface to appear on.

Moved outside `panelOpacity`. The judgement embedded in that: hiding the
persistent strip is a statement about chrome sitting over the menu bar, not a
request to be told nothing — the peek is transient, claims no clicks, and is
the whole point of the feature.

### The lock cards — not a defect, and the investigation took a wrong turn first

Recorded because the wrong turn is instructive.

`ncprefs` had no entry for Tempo among 110 apps, and an instrumented run showed
`lockCards.start()` logging with `canNotify=true` while **neither** following
notification log line ever appeared — `notificationSettings()` never returned.
Re-signing with the one certificate in the keychain (a self-signed one) made
the calls answer, and `requestAuthorization` then failed with `UNErrorDomain`
code 1, *"Notifications are not allowed for this application."* That looked
conclusive: ad-hoc signing blocks notification registration.

**It was not the cause.** After a clean rebuild the ad-hoc build answered
normally: `status=2` (`.authorized`), `lockScreenSetting=2` (enabled),
`alertSetting=2` (enabled). The hang was real and reproduced twice, but it was
a first-registration condition, not a standing property of ad-hoc signing — and
a conclusion had been drawn from two observations that a third overturned.

The actual reasons no card appeared, both by design and both documented in the
code that produces them:

- **Music.** `postMusicIfLocked` requires a *playing* track — "a paused player
  behind a locked screen is not news, and a card claiming to be now-playing
  while nothing plays is precisely the lying signal UI Principle #4 forbids."
  Spotify was `paused` throughout (every `mediaremote-adapter` probe in this
  session reported `"playing":false`).
- **Weather.** `postWeatherIfLocked` posts nothing without a reading. No city
  is set (`weatherCity` unwritten) and no place is cached, so the card depends
  entirely on CoreLocation having produced a fix.

### Decision

1. The peek moves outside `panelOpacity`, with the reason written at the call
   site so it is not "tidied" back inside.
2. `notificationSettings()` and `requestAuthorization` get a 4s timeout. The
   hang was real, and an `await` that never resumes leaks a task on every
   Settings open and every app activation while the pane reports a state that
   is not true. A timeout sets `registrationBlocked`, which the Weather pane
   reports as its own thing rather than as a permission the user withheld.
3. The post path logs its outcome. `add(request) { _ in }` was discarding the
   completion error outright, so a card that failed to deliver said nothing
   anywhere. Now behind `TEMPO_DEBUG_VIZ`, along with a line per card naming
   which guard rejected it.

### Consequences

The `registrationBlocked` copy deliberately does **not** assert a cause. The
honest statement is "macOS did not answer, this was seen once under an ad-hoc
signature, try a rebuild" — asserting the signing theory in the UI would have
shipped the same wrong conclusion this investigation reached and discarded.

Diagnosing this needed the app's own logging, and it took three instrumentation
rounds because none of the paths involved reported anything. The lines added
here are the ones that would have answered it in one.

---

## 082 — The close on a notched Mac: the panel retracted, its contents did not

**Date:** 2026-08-27 · **Status:** Accepted · **Fixes 065**

### Context

Decision 065 fixed "the weird black fade out" on a *notchless* display and
closed with "notched-Mac behaviour unchanged by construction." That was true,
and it was the problem: the built-in MacBook screen still had a fade-out of its
own, reported the same way. It is a different defect with the same symptom, and
it needed the same method to find — `scripts/capture-panel-animation.sh`, read
frame by frame, because nothing about it is visible in a description.

### What the frames showed

Recorded on the built-in Liquid Retina display at 25fps, cropped to the notch.
Over the 0.45s collapse, three layers came apart:

- **The black silhouette** retracted correctly, reaching pill size in ~0.28s.
- **The expanded column** — output chips, gear, mute, the CPU/memory readouts —
  stayed at **full panel size** and faded out on the collapse spring. At
  t+0.16s through t+0.24s "MacBook Air Speakers" and "Tempo Visualizer Tap" are
  plainly legible floating over the desktop with no panel behind them.
- **The glass** did the same: its slab was still on screen after the pill was
  back in the notch.

The cause is one SwiftUI rule applied twice. A subtree removed inside an
animated transaction keeps the size it held at removal and fades in place — it
does not follow the frame inward. The panel's `.frame(width:height:)` shrinks;
neither the removed content nor the removed glass branch is clipped by it, so
both were left hanging at 640-ish points wide while the shape they belonged to
was already gone.

### Options

| | Approach | Verdict |
|---|---|---|
| A | Shorten the collapse spring | Rejected — makes the ghost briefer, not absent, and 065 already tuned this curve |
| B | Fade the content faster | Half a fix — still a full-size panel over the desktop, just for less time |
| C | Clip the panel to its own retracting shape | **Chosen** — the content is wiped by the closing outline instead of hanging in the air |
| D | Keep the glass in the hierarchy at zero alpha so it shrinks with the frame | Rejected — runs the Liquid Glass compositor at all times for a case a clip already solves |

### Decision

1. `.clipShape(shape)` on the panel, placed **after** `.background(...)` so it
   takes the glass as well as the content. Both branches still freeze at full
   size when removed; the clip is what makes that invisible.
2. The rim light moves out of `backgroundShape` to an overlay applied *after*
   that clip — a stroke on the boundary would be halved by it — and is
   alpha-gated rather than branched, so it retracts with the frame instead of
   becoming the very outline the clip exists to remove.
3. Everything else stays on the collapse spring. Two curve changes were tried
   first and both reverted: pinning the glass's removal to `fadeAnimation`, and
   pinning the silhouette's alpha to it. The second was actively wrong and the
   frames show why — `.animation(_:value:)` scopes the *geometry* arriving from
   the frame above as well as the alpha, so the black pill retracted in 0.18s
   while the panel it backs took the 0.45s spring, and the content spilled out
   around a pill that had already reached the notch. One artifact traded for
   another.

### Consequences

Nothing is drawn outside the silhouette at any point in the animation, opening
or closing. Measured on the built-in display, before and after: the ghost ran
from t+0.04s to t+0.32s before ("MacBook Air Speakers" and "Tempo Visualizer
Tap" legible over the desktop with no panel behind them, the readouts with
them); after, every frame of the close is content inside the outline, and the
pill settles pure black. The open reads better too, as a side effect — the
column now unrolls out of the notch instead of appearing at full width inside a
growing shape.

The expanded panel is unchanged. Checked at matched frames before and after,
including a zoom on the left edge: the rim light is the same weight in its new
position outside the clip.

`.clipShape` also clips hit testing, which is harmless here: `.contentShape`
is applied after it and defines the hit region explicitly, and the expanded
content is inside the shape by construction.

Verified on screen with `scripts/capture-panel-animation.sh`. Three earlier
runs of it caught no panel at all while a full-screen app owned the notch; that
is a property of those runs and not a Tempo defect — the panel opens there.

---

## 083 — The Settings sidebar gets coloured icons

**Date:** 2026-08-27

### Context

The eight-pane sidebar of decision 080 drew every row with a plain SF Symbol in
the label colour. Eight monochrome glyphs in one column are found by reading
the text next to them, not by looking — the icons carried no signal the title
did not already carry.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Leave the symbols monochrome | No work; matches a plain SwiftUI `List` | The icon is decoration only; the row is found by reading |
| Tint the symbol itself per pane | One line per case | Coloured glyphs on the sidebar's material read as thin and washed out, and go muddy on a selected row |
| Coloured rounded tile behind a white glyph | The shape System Settings, Mail and Shortcuts all use; reads at a glance and holds up on a selected row | Slightly more view code; needs a colour per pane |

### Decision

The tile. `Pane.tint` gives each pane a colour and `PaneIcon` draws a 20×20
`RoundedRectangle(cornerRadius: 5, style: .continuous)` filled with
`tint.gradient`, the symbol over it in white at 11pt semibold. Colours echo
what the pane controls rather than being arbitrary: green for Agents (a running
light), sky blue for Weather, red for Music, purple for Appearance, orange for
Modules, grey for General as in System Settings.

Four symbols moved to their filled variants (`gearshape.fill`,
`paintbrush.fill`, `cloud.sun.fill`, `square.grid.2x2.fill`) and About to bare
`info` — an outline glyph on a filled tile reads as a hole in it.

### Consequences

Sidebar only; nothing else in the window changed, and the row heights are the
ones AppKit already gave (the tile is 20pt, under the row's own height). Seen
on screen: all eight tiles draw in their colour with the selected row's tile
unchanged, which is the point of the white-on-colour shape.

---

## 084 — The sneak peek wears Liquid Glass

**Date:** 2026-08-27

### Context

The track-change peek of decision 072 was drawn on a flat plate:
`RoundedRectangle(cornerRadius: 12)` filled black at 0.82 with a 1pt white
hairline over it. That was written before the panel itself moved to Liquid
Glass (decisions 030 and 064), and it was the last surface in the app still
faking a material by painting one.

It is also the surface with the clearest system precedent. The peek is exactly
the shape of a macOS HUD — a capsule that appears unbidden, says one thing and
retracts — and on macOS 26 the AirPods connection and volume indicators it
appears a few points below are all Liquid Glass. A black plate next to them
reads as a third-party overlay, which is what it was.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Keep the painted plate | Works on every supported OS with one code path | Visibly not the system's material; the one surface still painting a material by hand |
| `.regular` glass, neutral | The material the system HUDs beside it use; refracts what is behind rather than covering it; glass draws its own rim, so the hairline goes | Needs an `#available(macOS 26.0)` fallback and a Reduce Transparency branch |
| Glass tinted with the album colour, or following `panelStyle` | Consistent with the panel's own style setting | The HUDs it sits beside are neutral, and a peek that changes colour every track is decoration competing with the two lines it exists to show |

### Decision

`.regular` glass in a 20pt continuous rounded rect, untinted, with the padding
opened from 14/8 to 16/10 so the capsule keeps the system HUDs' proportions.
The hairline stroke and the black fill are gone with it — Liquid Glass draws
its own rim and shading.

Three cases still get the old plate, and all three are the same statement:
there is no glass to have. Reduce Transparency (nothing behind may show
through), `panelStyle == .solid` (the user asked this app's chrome to be
opaque), and macOS 14/15, which has no `glassEffect`. Increase Contrast adds a
0.25 black scrim between the glass and the text, mirroring `contentScrim`'s
top-up for the panel.

The peek deliberately does **not** follow `panelStyle` beyond honouring
`.solid`. `panelStyle` is a statement about the panel — the surface the user
opens and reads — and the peek is a system-HUD-shaped thing that shows up
without being asked for.

### Consequences

Verified on screen on macOS 26.6.2: a real Spotify track change was driven at
zero volume with the pointer away from the notch, and captured over both a
dark terminal and an Outlook window. The capsule refracts and lenses what is
behind it and carries the glass rim, and the title and artist hold at white and
secondary-white over both. The window is pinned to `.darkAqua`
(`NotchWindow.swift`), so the glass resolves to its dark variant no matter how
bright the desktop behind it is — the same reason the panel's own glass is
legible.

No change to when the peek fires, how long it stays, what it says, or what it
claims: the window's hit region is geometry-driven
(`NotchHitRegion`/`NotchHostingView.hitTest`), so glass pixels below the pill
take no clicks, exactly as the painted plate took none.

## 085 — A Ghostty session is found by its folder when it has no title yet

**Date:** 2026-08-27

### Context

Reported: Tempo takes you to the wrong agent session when the sessions live in
different Spaces and their windows have been reordered since they were started.

Measured on this machine with three live `cli` sessions (two in
`~/Documents/code/Tempo`, one in `~`), each in a Ghostty window on its own
Space. The parts that work were verified first, so the fix would not be aimed
at the wrong thing:

- Ghostty's app-level `terminals` element lists **every** surface regardless of
  Space — three surfaces returned while zero Ghostty windows were on the
  current Space. (Its `windows` element does *not*: it returned two of the
  three windows, then one, then two again as focus moved. Nothing here reads
  it.)
- `focus` crosses Spaces and activates the app. From Finder frontmost and no
  Ghostty window on the current Space, focusing the `LHR 400` surface left
  Ghostty frontmost with exactly that window on screen.
- Tab order is irrelevant to the match: the title match resolved all three
  sessions to the correct surface id, in one dry run, with no ordering input.

What does *not* work is the case the title cannot express. Claude Code writes
its `ai-title` only after a turn has ended, so a session is untitled for
exactly as long as it is new — "after first starting them". With no title,
`focusGhosttySurface` returns false immediately and `focusCLISession` falls
through to `activateProcess(terminal.pid)`, which fronts the Ghostty
*application*. That lands on whichever Ghostty window was last used — and when
each window sits on its own Space, that is a Space switch to a different
session. The fallback exists for "another emulator, or a tab we could not
match", and it is the wrong answer for Ghostty specifically, because Ghostty
does expose enough to identify the surface.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Leave it; the title arrives eventually | No code | The wrong-session jump is exactly what the user reported, and every session passes through the untitled state |
| Decline the click when no title matches, as AgentStatus's Windows `pick_window` does | Never lands wrong | A click that does nothing reads as broken, and Ghostty has an identifier the Windows path does not |
| Match on Ghostty's per-surface `working directory` | Present from the first millisecond of a session, no `ai-title` needed; already published per surface (OSC 7, the shell's real cwd), the same path the status file carries | Not unique on its own — two sessions in one repo share a folder |
| `working directory`, minus the surfaces another live session's title already claims | Unique in the reported case (two Tempo sessions, one of them titled); degrades to the old fallback only when *two* sessions in one folder are both untitled | Costs one extra `osascript` and reads the sibling sessions' titles, but only on the path where the click was going to be wrong anyway |

### Decision

The last one. `focusGhosttySurfaceByDirectory(cwd:siblings:)` runs only after
the title match has already failed, and focuses a surface only when exactly one
survives:

1. A Ghostty running exactly one surface *is* the session's surface — the
   caller has already walked the session's process tree to this Ghostty
   instance.
2. Otherwise, strike out every surface whose title ends with another live
   session's `ai-title` (a surface showing a different session is not this
   one), then keep the ones whose `working directory` is this session's `cwd`.
   One survivor is focused; zero or several fall through to the old app-level
   fallback unchanged.

Paths are compared with AppleScript's default text comparison, which ignores
case: OSC 7 reports the cwd as the shell spells it, and the surfaces here
report `~/documents/code/tempo` against the status file's
`~/Documents/code/Tempo`.

The detached-background-agent branch deliberately does **not** get this. That
branch runs when the session has no controlling terminal, so it has no surface
of its own; a folder match there would front some other session's tab and call
it the agent.

`SessionFocusService.focus` therefore takes the session list as well as the
session — the elimination step needs to know who the other sessions are.

### Consequences

Verified against the three live sessions:

- Simulating the untitled case for the Tempo session (its own title withheld,
  the other two passed as claimed) picked exactly one surface, the right one:
  `hits=1 :: ◐ Tempo agent session navigation across spaces`. Run for real, the
  front Ghostty window changed to the intended session.
- The genuinely ambiguous case — both Tempo surfaces in the folder, neither
  claimed — returned `no`, so the old fallback still carries it rather than a
  coin flip.

No change to the titled path, to Terminal.app, to the editors, or to the
background-agent branch. Nothing is written, and the sibling transcripts are
opened only for their `ai-title` string, on a click, exactly as the session's
own already was (Agent Guideline #5).


---

## 086 — The sneak peek gets a rim light

**Date:** 2026-08-27 · **Status:** Accepted

### Context

Decision 084 dropped the peek's 1pt white hairline on the reasoning that
Liquid Glass draws its own rim. It does — but that rim is derived from what is
behind the window, so its contrast against the desktop varies with the
desktop. Over a dark terminal the capsule's edge is obvious; over a bright
window or a light wallpaper it thins to nearly nothing and the two lines of
text read as floating loose under the notch rather than sitting on a surface.

The fallback plate had the opposite problem for the same reason: its stroke
was fixed at white 0.10, faint enough to be decorative rather than an edge.

### Decision

One rim light, the same on both paths: `strokeBorder(.white.opacity(0.28),
lineWidth: 1.5)` on the peek's 20pt rounded rect. On macOS 26 it is stroked
over the glass as the topmost layer of the `ZStack`; on the plate it replaces
the old 0.10/1pt overlay.

`strokeBorder` rather than `stroke` so the line is inset into the shape and
does not straddle the glass's own boundary, which would fringe against the
refracted edge.

The rest of 084 stands: still `.regular` glass, still untinted, still
independent of `panelStyle` beyond honouring `.solid`, same corner radius,
same padding, same three fallback cases.

### Consequences

Nothing else changes — the peek fires on the same trigger, for the same
duration, and takes no clicks. `swift build` clean.

---

## 087 — The session title is read from the end of the transcript, not the whole file

**Date:** 2026-08-27

### Context

Reported: clicking the light for the session running in `~` does not go to its
Ghostty window, which sits in a separate Ghostty window on its own Space.

Measured on this machine, against that live session
(`3a9a3e92…`, pid 75616, `ide: cli`):

- The Ghostty surface is there and is titled: `terminals` lists
  `✳ LHR 400 class alternatives`, working directory `~`.
- Claude's current title for the session is exactly `LHR 400 class
  alternatives`, so `focusGhosttySurface`'s strong match — surface title *ends
  with* session title — would have resolved it in one step.
- It never ran. `claudeSessionTitle` returns nil before reading anything,
  because the transcript is **22,788,432 bytes** and the function skipped any
  file over 16MB (decision 035's guard against reading a large file on the
  click path).
- With no title, the click fell to decision 085's directory match, which also
  missed: the status file for this session records
  `cwd: ~/.claude/projects/-Users-<user>` — the
  transcript's *project directory*, not the session's working directory, which
  `lsof` confirms is `~`. That value comes from the hook
  payload AgentStatus writes verbatim; Tempo is read-only on it (Agent
  Guideline #3) and cannot correct it.
- Both matches failing, the click ended at `activateProcess(terminal.pid)`,
  which fronts the Ghostty application — from a Space with no Ghostty window on
  it, that is a jump to whichever Ghostty window was last used. Exactly the
  symptom reported.

Two things that were suspected and ruled out by measurement, so the fix would
not be aimed at the wrong thing:

- **Ghostty's `focus` does cross Spaces.** Sampling `CGSGetActiveSpace` around
  the call, with Outlook frontmost and no Ghostty window on the current Space,
  the active space moved from 3 to 263 within 500ms and stayed there. (It is a
  no-op when Ghostty is *already* the frontmost application while its windows
  are on another Space — a state a previous failed click leaves behind, and the
  reason an early probe here showed no switch.)
- **Nothing in the AppleScript needed changing.** Adding `activate` after
  `focus` was tried and made no difference to the space switch.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Raise the cap to 32/64MB | One-line change | Buys months, not a fix; the next long session hits the new number and fails the same silent way |
| Shell out to `tail -c` and parse that | Small | Another process on the click path, and a title that stopped updating early would still be missed |
| Read the file backwards, mapped, stop at the first `ai-title` from the end | The current title *is* the last such record, so the scan ends where the answer is — 19KB in on the file that broke this; no cap left to age out; `Data(contentsOf:options:.mappedIfSafe)` never materialises 22MB | Worst case (a session titled once, long ago) still walks the file, though only through mapped pages |

### Decision

The third. `claudeSessionTitle` maps the transcript and walks it backwards a
line at a time, parsing only lines that contain `"ai-title"` and returning the
first one that yields a non-empty `aiTitle`. The 16MB guard is gone — the
guard is now the scan's own direction, which is a property of the file format
rather than a number to be outgrown.

Verified with the shipped code compiled standalone against the real files:
`LHR 400 class alternatives` from the 22MB transcript in under 1ms (nil
before), the correct title from a 1MB transcript, and nil for a file with no
records.

### Consequences

The reported click now resolves through the strong title match, the same path
every other titled session already used; decision 085's directory match stays
as the fallback for sessions Claude has not titled yet.

The bad `cwd` in that session's status file is untouched and still makes the
directory fallback miss for it — it only matters if the session is ever
untitled again, and correcting another tool's data is not Tempo's to do.

---

## 088 — The shelf's remove button stops fighting the pointer

**Date:** 2026-08-27

### Context

Removing a file from the shelf was reported as "really difficult: the x
flickers a lot when hovering over it."

The cause is a hover loop, visible in the code as written. The 52pt chip owned
the `.onHover`; the remove button was a 24pt hit target pushed out of the chip
by `.offset(x: 8, y: -8)`, so roughly two-thirds of it sat **outside** the
region hover was tracked on. The button was also mounted conditionally —
`if hoveredID == item.id { Button … }`.

That is a cycle: the pointer reaches for the button → it leaves the chip →
`hoveredID` clears → the button unmounts → the pointer is now over bare chip
again → hover returns → the button remounts under the pointer. Each frame the
pointer sits in the overhanging area, the button appears and disappears, and a
click that lands mid-cycle hits the chip's `.onDrag` instead of the button —
which is why the file gets dragged out rather than removed.

A second, smaller defect sat next to it: `hoveredID = $0 ? item.id : nil`
clears the shared state unconditionally on exit, so moving from one chip
straight onto its neighbour can arrive as (enter B, exit A) and leave nothing
hovered.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Pad the chip so the hover region reaches the offset button | Keeps the button's outside-the-corner look | Padding is layout: it adds 8pt of gap to every chip in the row and changes the row's spacing and height |
| Track hover with an `NSTrackingArea` over the union of both frames | Exact control of the region | AppKit plumbing for one 24pt button, and the union still has to be kept in sync with the layout |
| Keep the button inside the chip, mounted always, and fade it | The hover region and the button occupy the same rect by construction — no geometry to keep in sync, no layout change | The x no longer overhangs the corner |

### Decision

The third. The button loses its `.offset` and sits at the chip's top-trailing
corner, inside the bounds `.onHover` already tracks, so reaching for it cannot
end hover. It stays mounted at all times and is faded with
`.opacity(isHovered ? 1 : 0)` plus `.allowsHitTesting(isHovered)` — hit-testing
never churns, and there is no insertion/removal for the pointer to chase. The
fade runs on a 0.12s ease-out.

The exit handler now clears only its own id (`else if hoveredID == item.id`),
so a chip-to-chip move cannot have the departing chip erase the arriving one's
hover.

The glyph is drawn in palette rendering — 0.85 primary on a 0.25 primary
circle — because at the corner of a filled chip a `.secondary` `xmark.circle.fill`
has too little separation from the chip behind it.

### Consequences

The 24pt hit target is unchanged, and it is now entirely on the chip, so every
part of it is clickable on the first try. The row's spacing, chip size and
height are untouched. The context menu's **Remove** remains as the second path.

---

## 089 — The pointer becomes a hand over a control

**Date:** 2026-08-27

### Context

Following 088: the shelf's remove button was hard to use partly because
nothing tells you where a control's edge is until you are already on it.

That is true of the whole panel, not just the shelf. Decision 062's controls
draw **no chrome at rest** — the transport glyphs, the gear, the device chips
and the shelf's x are bare until hover fills a capsule behind them. The hover
highlight is the only "this is clickable" cue, and it arrives *after* you have
already found the thing. The cursor is the one cue that can arrive first,
while the pointer is still travelling.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| `NSCursor.pointingHand.set()` on hover-in, `.arrow.set()` on hover-out | One line, works on every macOS Tempo targets | `set()` is a bare assignment with no owner: a control that vanishes under the pointer sends no exit event, and in a borderless panel with no cursor rects nothing restores the arrow — the hand strands on the desktop |
| `push()`/`pop()` on hover | Has a defined unwind | The stack corrupts if a push is not paired, which is exactly what the vanishing-control case does |
| `pointerStyle(.link)` (macOS 15+), push/pop with an unwind on disappear below it | The system owns the cursor's lifetime on 15+, so a disappearing control cannot strand it; the fallback's `onDisappear` closes the one hole push/pop has | Two code paths until the deployment target moves off macOS 14 |

### Decision

The third, as one `pointingHandCursor()` modifier in `NotchStyle.swift`.

Applied at the shared layer wherever there is one: inside
`NotchButtonStyle.ControlBody`, which covers the transport buttons, the gear,
Connect Spotify, add-to-playlist and the agent rows in a single place. The
controls no style can reach get it individually — the shelf's remove button,
the mute button and the device chips (`.plain`), the playlist picker (a `Menu`,
which no ButtonStyle can see), and onboarding's two custom styles.

**Two deliberate exclusions.** The Settings window keeps the system's
behaviour: those are standard AppKit controls, and on macOS the arrow over a
real button is the convention — the hand means *link*. This is for Tempo's own
chrome-less surfaces, where that convention has nothing to work with. And
onboarding's "hello" skip target keeps the arrow, because it is deliberately a
target with no visible affordance (a Skip button would out-shout the animation
it interrupts) and a hand cursor across the whole word would announce exactly
what that design hides.

### Consequences

Every control in the expanded panel now declares itself before the pointer
lands on it, which is the cue 088's button was missing. The hit targets, the
hover highlights and the layout are unchanged — this adds a cursor and nothing
else.

---

## 090 — The invisible notch opens at the screen edge, not near it

**Date:** 2026-09-04

### Context

Decision 055 gave the undrawn collapsed strip a pointer-watched hover target,
because a pill that claims no clicks gets no `.onHover` of its own. That target
was deliberately "exactly where the pill would be": `pillWidth` wide and
`stripHeight` (32pt) tall, hung off the top of the screen.

In use on an external display that is the wrong shape. 32pt is deep enough that
the pointer crossing the top of the screen on its way somewhere else — to a
window's title bar, to a tab, to the menu bar itself — lands in it, and the
panel drops open over the app the user was actually reaching for. The pill is
invisible there, so there is nothing on screen that explains why.

The gesture the user described is the one macOS already trains: push the
pointer into the very top edge, the way you reveal an auto-hidden menu bar, and
*then* Tempo appears alongside it.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Keep the pill-shaped region, raise the dwell delay | No geometry change | The panel still opens on a pass-through, just later; and the dwell is a user setting that governs the drawn strip too |
| Thin band at the top edge (chosen) | Matches the menu-bar-reveal gesture exactly; the cursor cannot travel past `maxY`, so resting on the edge is a stable, easy target rather than a pixel-accurate one | Deliberate: a pointer 4pt below the edge no longer opens it |
| Require a dedicated gesture (edge push with a velocity or dwell test of its own) | Even harder to trigger by accident | New mechanism, new tuning, and nothing else in Tempo works that way |

### Decision

The second. `NotchGeometry.hoverActivationRegion`, which only
`NotchHoverDetector` reads, is now `notchWidth` (200pt) wide by
`hiddenStripActivationHeight` (3pt) tall, flush with `screen.maxY`.

3pt rather than 1pt because `NSEvent.mouseLocation` is in points on a display
whose backing scale need not be 1, and the top row of a screen is not
guaranteed to report exactly `maxY`. Width drops from `pillWidth` to
`notchWidth` for the same reason the height dropped: the region is an invisible
target, and it should be no larger than the thing it opens.

Everything else is untouched. This region is read in exactly one mode — the
strip switched off *and* no hardware notch (decision 055) — so a real notched
display, and an external display with the strip drawn, both still hover through
`.onHover` on the pill itself. Once the panel is open the detector switches to
`expandedPanelRegion`, so moving down off the edge into the controls keeps it
open as before.

### Consequences

On an external display with the strip hidden, Tempo now stays out of the way
until the pointer is against the top edge of the monitor. The cost is that the
target is unforgiving by design: brushing past the top of the screen no longer
opens the panel, which is the point.

---

## 091 — The notch opens only once the menu bar is down

**Date:** 2026-09-04

### Context

Decision 090 shrank the undrawn strip's hover target to a 200 x 3pt band at the
very top edge, which stopped the panel opening on a pass-through. It did not
stop the case that actually costs the user something: in a full-screen browser
the tab strip runs to the top edge of the screen, so reaching for a tab puts
the pointer in exactly the same 3pt row the notch listens to. Position alone
cannot tell "aiming at a tab" from "aiming at Tempo" — both are `y = maxY`.

The user's own framing is the discriminator: *"make it so I can't open tempo
unless the apple menu bar is down as well."* macOS only drops an auto-hidden
menu bar when the pointer pushes into the edge and stays; hovering a tab strip
never drops it. Gate on that, and the two gestures separate cleanly.

### Options

Measured on this machine before choosing (Agent Guideline #4), with a probe
logging each candidate at 10Hz while the menu bar was hidden, revealed, and
hidden again:

| Option | Result |
| --- | --- |
| `NSMenu.menuBarVisible()` | Answers a different question (app-level hiding). Constant `true` in both states |
| `NSScreen.visibleFrame` | Reserved the same 30pt in both states — does not move when the bar auto-reveals. Dead |
| The menu bar's own window via `CGWindowListCopyWindowInfo` | The bar is not enumerable: nothing at layer 24 in either state. The transient `Window Server` entries that do appear blink with the pointer parked, so they are not it. Dead |
| Accessibility API (`kAXMenuBarAttribute`) | Would work, and sees the real bar rather than a proxy — but costs an Accessibility TCC grant Tempo has never needed |
| A status item's window | Tracks it exactly. On a 1440pt screen with a 30pt bar: hidden `y = 1440` (entirely above the top edge), sliding `1434 … 1416`, fully down `y = 1410` |

### Decision

The last, as `MenuBarSensor` (`Services/MenuBarSensor.swift`): a **zero-length**
status item whose button draws nothing, created only while
`NotchHoverDetector` is running — the one mode that asks this question
(decision 055). Everywhere else Tempo still puts nothing in the menu bar. The
sensor reports *fully* down only: the slide's intermediate frames hang off the
top of the screen and read false, so the gate opens when the bar has arrived
rather than while it is on its way.

Presented to the user with its one real cost — Tempo owning a menu-bar slot in
that mode — and chosen over the two cheaper alternatives (a longer edge dwell,
which cannot separate the gestures, and the Accessibility grant).

**Two deliberate scope limits.**

The gate applies to *opening* only. Once the panel is open the region is the
panel itself, ungated: moving down into the controls retracts the menu bar, and
gating there would slam the panel shut the instant it was used.

The pointer held against the edge sends no further `mouseMoved` events, and the
bar drops a beat after it arrives — so the gate would otherwise be evaluated
once, before the bar had moved, and never again. A 0.1s timer re-evaluates it,
running only while the pointer is inside the band.

### Consequences

On a display where the menu bar auto-hides, Tempo now opens on the same push
that drops the bar, and a full-screen tab strip at the top edge no longer trips
it. Where the menu bar is permanently visible the sensor reads down at all
times, so behaviour there is exactly decision 090's. The cost is a menu-bar
slot in the hidden-strip mode, and a 10Hz poll for as long as the pointer sits
in a 200 x 3pt band.

---

## 092 — `.onHover` fires where `hitTest` says nothing is there

**Date:** 2026-09-04

### Context

Decisions 090 and 091 both aimed at the same report — the panel opening when
the user reaches for a tab in a full-screen browser on the external display —
and neither changed the symptom. 090 shrank the hover band to 200 x 3pt at the
screen's edge; 091 gated it on the menu bar being fully down. The user, after
both: *"this is not helping: im still running into tempo when trying to hit
chrome tabs."*

Instrumenting the running app (`TEMPO_DEBUG_HOVER=1`) and having the user
reproduce it settled it in one pass. Across 3798 logged samples covering
several misfires:

- `atEdge=true` occurred **zero** times. The band was correct
  (`x1620…1820 y1437…1440` on a 3440x1440 screen) and the pointer never
  entered it.
- The menu-bar gate was never even consulted — it sits behind `atEdge` in an
  `&&`.
- Every misfire began with `### SwiftUI .onHover on the panel view: true`,
  followed by the panel opening, followed only *then* by
  `isPointerNearNotch = true` — the pointer monitor reporting the pointer
  inside the panel that had already opened. Cause and effect were the reverse
  of what was assumed.

Decision 055 states that with the strip undrawn "the collapsed pill is
invisible *and* claims no clicks — `NotchHostingView.hitTest` returns nil over
it, so the window receives no mouse events there at all and SwiftUI's
`.onHover` can never fire." The first half is true and still is. The second
half does not follow: **`.onHover` is implemented with an `NSTrackingArea`,
and tracking areas deliver `mouseEntered` / `mouseExited` regardless of what
`hitTest` returns.** Hit-testing governs which view a *click* is routed to; it
does not gate tracking. So the mode has had two live hover paths all along —
the pointer monitor, band-limited and now gated, and `.onHover` over the
collapsed pill's whole ~308 x 32pt rect at the top of the screen, restricted by
nothing. The second is what a full-screen tab strip runs into.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Ignore `.onHover` while the strip is hidden (chosen) | One guard, in the mode that already has a dedicated pointer path; leaves every other mode's hover exactly as it is | Nothing observable — that path was never supposed to be live here |
| Shrink the `.onHover` view to the band | Keeps a single hover path | The view is the drawn pill; resizing it to sense hover would change what is drawn, and the pill is drawn at the pill's size in every other mode |
| Drop the pointer monitor and gate `.onHover` instead | One path rather than two | `.onHover` reports enter/exit of a view rect, not a screen band; the menu-bar gate needs polling while the pointer is stationary, which enter/exit cannot provide |

### Decision

The first. `ContentView`'s `.onHover` returns immediately when `stripHidden`,
so in that mode `NotchHoverDetector` owns hover entirely — opening *and*
closing — which is what decision 055 intended and described. Every other mode
is untouched: the drawn pill still hovers through `.onHover` exactly as before.

### Consequences

The edge band (090) and the menu-bar gate (091) finally govern this mode,
because they are now the only way in. Both were correct when built and neither
was reachable. The lesson for anything similar: `hitTest` and tracking areas
are independent mechanisms, and "no clicks" does not imply "no hover" —
verify a suppression rather than reasoning it (Agent Guideline #4).

---

## 093 — The edge push gets its own hold setting

**Date:** 2026-09-04

### Context

After decision 092 made the edge band the only way into the undrawn strip, the
user asked to be able to tune it: *"lets also make sure that we are able to
tweak things like how long we need to hold the cursor on the menu bar in
settings."*

The dwell was already a setting — `hoverExpandDelayMS`, Settings ▸ General ▸
Interaction ▸ *Hover delay* — and `handleHover` applied it to both entry paths.
But it is scaled for the drawn pill: 0–400ms, default 60, and its whole
justification (decision 034) is about a pointer *brushing across* the notch on
its way somewhere else. Pushing into a screen edge and holding is a different
gesture, and one the user has now been burned by three times, so the value they
want is unlikely to be the value that makes the pill feel right.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Raise the existing *Hover delay* ceiling and keep one setting | No new configuration surface (AI Guideline: avoid over-configurability) | One slider governing two gestures with opposite ideals — a hold long enough to make the edge deliberate makes the drawn pill feel broken |
| A separate **Edge hold** (chosen) | Each gesture tunes independently; the range can run to 1500ms where a deliberate hold actually lives | One more setting, shown in one more place |
| Hard-code a longer edge hold | Nothing to tune | Exactly what was asked for, refused |

### Decision

The second. `Preferences.edgeHoldDelayMS`, 0–1500ms in 50ms steps, default 60 —
the same value the shared setting had, so nobody's current feel changes.
`handleHover` takes the delay as a parameter; the pointer-monitor path passes
`edgeHoldDelay`, and everything else keeps `hoverExpandDelay`.

It sits in Settings ▸ Displays ▸ Placement, directly under *Show the strip on
external displays*, and is disabled while that toggle is on — the mode it
governs cannot occur then. Not in General ▸ Interaction beside the pill's hover
delay: two sliders with near-identical labels, one of which silently does
nothing in most configurations, is worse than putting each next to the thing it
affects.

The hold is measured *after* the menu bar has finished dropping (decision 091),
so the two add up in use — the footer says so, because a user setting 0 and
still waiting half a second deserves to know why.

### Consequences

The edge gesture is tunable from 0 (opens the moment the menu bar lands) to
a deliberate hold, without touching how the drawn pill feels. (The ceiling
shipped at 1500ms and was cut to 150ms by decision 094 the same day.) The
band's *height* stays fixed at 3pt — it is not exposed as a setting, since
nothing so far suggests the geometry is what needs tuning, and a second knob
for the same gesture would make finding the right feel harder, not easier.

---

## 094 — Slider values can be typed, and Edge hold stops at 150ms

**Date:** 2026-09-04

### Context

Two pieces of feedback on decision 093's slider: *"I should be able to fine
tune sliders by entering the values manually. Also, the sliders for edge hold
seem a bit much: i doubt anyone would use anything over 150 ms."*

Both are about the same thing — a slider is a coarse instrument. Tempo has
seven of them, and their steps are chosen for dragging: 10ms, 0.05, 0.5s, 10s,
250,000 tokens, 1%. Any value between two steps was unreachable, and the range
had to be wide enough for the extreme nobody wants in order to reach it at all.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| A `TextField` on every slider row (chosen) | One change covers all seven; the value was already displayed there, so nothing new appears in the window | Each row's units differ, so each needs to say how its own text parses |
| Finer steps instead | No new control | Makes dragging worse to make typing unnecessary, and still cannot express 75 on a 50-step slider |
| A stepper beside each slider | Precise | Slower than typing, and a third control in a row that already has two |

### Decision

The first. `SliderRow`'s read-only `Text` becomes a `TextField`, and the row
gains a `parse` closure — handed the field's text verbatim, unit and all,
because only the row knows what `%` is a percentage *of*, what `M` multiplies,
or that "Never" is its own word for zero. Returning nil rejects the edit and
the field reverts to the real value.

Three details that make it feel right rather than merely work:

- **Clamped, never snapped.** A typed value is held to the row's range and then
  kept exactly as entered. Snapping it to `step` would defeat the entire
  purpose — dragging is what steps; typing is how you reach 75 on a slider that
  moves in 50s.
- **Units are optional on input.** `150`, `150 ms` and `150ms` all read as 150,
  so the displayed text can be edited in place without first deleting its unit.
  `2.5M` and `500K` work on the token budget, and `Never` on the paused-media
  timeout.
- **Clicking away commits**, exactly as Return does. A typed value that
  silently evaporates because the field lost focus is worse than no field.

And Edge hold's ceiling drops from 1500ms to 150ms, with the step from 50ms to
10ms. The wide range existed to make a deliberate hold *reachable*; typing
reaches any value now, so the slider can be scaled to the useful span instead.

### Consequences

Every slider in Settings is now precise to whatever its units allow, and the
edge-hold slider spends its whole width on the 0–150ms range that matters.
Dragging behaviour is unchanged everywhere. The one asymmetry worth knowing:
after typing a between-steps value, the next drag snaps back to the step grid —
correct, but worth not being surprised by.

---

## 095 — The target is the menu bar's row, not a 3pt band

**Date:** 2026-09-04

### Context

With decision 092 in place the misfire was gone — the panel no longer opens at
a full-screen browser's tab strip. What surfaced underneath it: *"sometimes
when menu bar is down it doesnt expand, or it flickers and then goes away."*

Both symptoms are one cause. Decision 090's band is 3pt tall, and it has to
hold the pointer for the whole dwell, not merely be touched. Pushing into a
screen edge is a shove: the pointer lands at `maxY`, the menu bar drops, and
the hand relaxes a pixel or two down into the bar it just revealed. That exits
the band — cancelling the dwell before it fires (no expand), or, if the dwell
had already fired, collapsing the panel a frame after it opened (the flicker).

The band was sized that way when it was the *only* protection against opening
by accident. It is not any more: decision 091's menu-bar gate is, and a menu
bar that is down covers whatever was underneath it — including the tab strip
this whole thread is about.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Keep 3pt, add hysteresis (a larger rect to stay in than to enter) | Keeps the strict entry | Two rects to reason about, and the entry still has to be hit precisely at the moment the bar drops |
| Grow the target to the menu bar's row (chosen) | The pointer cannot relax out of it while the bar is down, because the bar *is* that row; nothing is given up, since the gate is what does the filtering | Where the menu bar never hides, the target is a 200 x 30pt strip in the middle of the bar — which is decision 055's original behaviour |
| Lengthen the dwell instead | No geometry change | Wrong axis entirely: the problem is leaving the region, not leaving too soon |

### Decision

The second. `hoverActivationRegion` takes the height as a parameter and the
detector passes `MenuBarSensor.barHeight` — **measured from the sensor's own
status window** rather than asked for. `NSStatusBar.system.thickness` returns
22 on this machine while the bar actually occupies 30pt on screen, and 30 is
where the pointer is; the 8pt difference is exactly the relax that was
cancelling the dwell. The sensor already owns a window in the bar, so the true
height is free.

The poll that keeps the gate live now runs while the pointer is anywhere in
that row, not just at the extreme edge — otherwise a pointer that entered the
row a few points low would sit there with the bar down and never be looked at
again.

### Consequences

Pushing into the top edge and holding now opens the panel reliably, and it
stays open while the pointer rests anywhere in the notch-width span of the menu
bar. The 3pt band from decision 090 is gone; what stops the accidental opens is
decision 091's gate plus decision 092's fix, which is where that job belonged.

---

## 096 — The topmost row of the screen is inside the target, not outside it

**Date:** 2026-09-07

### Context

*"tempo on external monitor has a dead zone on the very top when touching the
edge of the monitor."* Decision 095 grew the undrawn strip's target to the
menu bar's full 30pt row precisely so a shoved pointer could not relax out of
it — and yet the one place the shove actually lands, the topmost row itself,
still did nothing.

Measured on this machine with a cursor-warp probe (LG ULTRAWIDE 3440x1440, the
only attached display, lid closed, `showStripOnExternalDisplays` off, menu bar
30pt):

    warp to Quartz y=0  ->  NSEvent.mouseLocation.y = 1440.00 = frame.maxY   contains = no
    warp to Quartz y=1  ->  NSEvent.mouseLocation.y = 1439.00               contains = YES
    warp to Quartz y=2  ->  NSEvent.mouseLocation.y = 1438.00               contains = YES

`NSRect.contains` excludes its own `maxY`, and every one of Tempo's
pointer-tested regions is built as `NSRect(y: screen.maxY - height, height:
height)` — so its `maxY` *is* `screen.maxY`, the exact coordinate the pointer
reports when it is parked against the top edge. The region covered the whole
bar except the one row the gesture ends on. Backing off a single point worked,
which is what made it read as a "dead zone" rather than as broken hover.

Three regions shared the bug: `hoverActivationRegion` (the panel would not
open), `expandedPanelRegion` (a panel already open would not stay open with
the pointer at the edge), and `dragActivationRegion` (a file dragged to the
very top would not open the shelf).

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| `NSMouseInRect(p, rect, false)` at each call site | Cocoa's own edge-inclusive test | Inclusive on the *bottom* edge instead, which is a real boundary here — the panel's lower edge would over-claim by a point; and three call sites to remember |
| Clamp the pointer's y to `maxY - 0.5` before testing | One place, no geometry change | Lies about where the pointer is, in a value other logic may later read |
| Build the regions one point taller, overshooting above the screen (chosen) | The regions stay plain rects tested with plain `contains`; the extra point is off-screen space no pointer can reach, so no other edge moves | The rect no longer equals the visual region it describes, which needs saying in a comment |

### Decision

The third, via a single `NotchGeometry.topAnchoredRegion(width:height:)` that
all three regions now go through: horizontally centred on the target screen,
top-anchored, `height + 1` tall. The overshoot lives entirely above
`screen.maxY`, so the only coordinate it adds is the topmost row itself.

### Consequences

Slamming the pointer into the top edge of the display now opens the notch, and
holding it there keeps the panel open. Nothing else about the target changed —
same width, same menu-bar gate from decision 091, same dwell. The drawn
strip's own hit region (`NotchHostingView.hitTest`, in window coordinates) has
the same top-row exclusion, left alone here: over a hardware notch that row is
unlit hardware, and with the strip drawn on an external display hover comes
from a tracking area rather than from that rect. Worth revisiting only if a
click on the pill's topmost row is ever reported as missing.

---

## 097 — Add-to-playlist uses `/playlists/{id}/items`; a content-free 403 is not echoed

**Date:** 2026-09-16 · **Status:** Accepted

### Context

The add-to-playlist button failed on every attempt, showing the single word
`Forbidden` — the whole of Spotify's own error message, surfaced verbatim by
`addFailureMessage`'s 403 branch (decision 003's error reporting prefers
Spotify's `error.message` over Tempo's own sentence when one is present).

Verified live against this machine's account and the app's stored token
(Agent Guideline #4), current track `spotify:track:1MottqWa40K0rVmWZRge39`:

```
POST /v1/playlists/{owned}/tracks          -> 403 {"error":{"status":403,"message":"Forbidden"}}
POST /v1/playlists/{not owned}/tracks      -> 403 (same bare body)
DELETE /v1/playlists/{owned}/tracks        -> 403 (same)
POST /v1/users/{me}/playlists              -> 403 (same)
PUT  /v1/playlists/{owned}          (name) -> 200, name observed changed and restored
PUT  /v1/playlists/{owned}/followers       -> 200
GET  /v1/me, /v1/me/playlists              -> 200
POST /v1/playlists/{owned}/items           -> 201 {"snapshot_id":...}
DELETE /v1/playlists/{owned}/items         -> 200 with body {"items":[{"uri":...}]}
```

Two facts fall out of that. The grant is intact — `playlist-modify-public`
writes succeed through `PUT`, so this was never a missing scope or an expired
session, and never the "playlist isn't yours" case decision 049's owner filter
already removed. And the failure is the path: Spotify's February/March 2026
Web API migration retired `/playlists/{id}/tracks` in favour of
`/playlists/{id}/items`, and the retired path now answers 403 `Forbidden`
rather than 404 or 410 — the one status whose Tempo message blamed ownership.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Point `add()` at `/items` (chosen) | One-word path change; verified 201 on this account; the endpoint Spotify documents today | Drops support for any Spotify deployment still serving only `/tracks` — none observed |
| Try `/items`, fall back to `/tracks` on 404 | Survives either server | Two round-trips on the failure path, and `/tracks` does not 404 — it 403s, so the fallback could never be reached by its own trigger |
| Leave the path, improve only the message | Smallest diff | The button still never works — a correctly-worded failure is still a failure |

### Decision

`add()` POSTs to `\(apiBase)/playlists/\(playlistID)/items`. The 403 branch of
`addFailureMessage` now discards a `detail` that is only the word "Forbidden"
and falls through to Tempo's own sentence, so a future content-free 403 reads
as something the user can act on instead of as Spotify's status restated.

### Consequences

Add-to-playlist works again. The ownership sentence is now reachable only for
a 403 that really is an ownership refusal, which the owner filter in
`loadPlaylists` already makes rare. Nothing else in `SpotifyWebAPI` touched a
migrated path: `GET /me` and `GET /me/playlists` are unchanged by the
migration and were observed returning 200 in the same session.

Not fixed here, and unrelated to this change: `swift build` fails on this
machine for every SwiftUI file — `error: external macro implementation type
'SwiftUIMacros.StateMacro' could not be found; plugin for module
'SwiftUIMacros' not found`. The active toolchain is Command Line Tools only
(`xcode-select -p` → `/Library/Developer/CommandLineTools`, Swift 6.4, macOS
27.0 SDK), whose `usr/lib/swift/host/plugins` ships `libObservationMacros` and
`libSwiftMacros` but no `libSwiftUIMacros`; no Xcode is installed. The edited
file typechecks standalone (`swiftc -typecheck` on `SpotifyWebAPI.swift`, no
SwiftUI import), but the app cannot be rebuilt until a toolchain with the
SwiftUI macro plugin is present.
---

## 098 — The build picks its SDK by probe, and keeps a copy of the one that works

**Date:** 2026-09-16 · **Status:** Accepted

### Context

`swift build` stopped building this project entirely. Every SwiftUI file failed
with:

```
VisualizerView.swift:67:24: error: external macro implementation type
'SwiftUIMacros.StateMacro' could not be found for macro 'State()';
plugin for module 'SwiftUIMacros' not found
```

Measured on this machine rather than inferred. In the macOS 27.0 SDK,
`SwiftUICore.swiftinterface:20038` declares

```swift
@attached(accessor, ...) @attached(peer, ...) public macro State() = #externalMacro(
    module: "SwiftUIMacros", type: "StateMacro")
```

— `@State` is a macro now. The macOS 26.5 SDK's interface has no such
declaration; there it is still a property wrapper. The macro needs a compiler
plugin, and `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins`
holds only `libObservationMacros` and `libSwiftMacros`: `libSwiftUIMacros`
exists nowhere on this machine, because it ships inside Xcode, which is not
installed. `xcode-select -p` is the Command Line Tools.

The trigger was an update, not a change to Tempo: CLT 27.0.0 installed
2026-09-10 (`pkgutil --pkg-info`), three days after `dist/Tempo.app` was last
built on 09-07, and it made `MacOSX.sdk` point at `MacOSX27.0.sdk`.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| Install Xcode | Supplies the plugin; the newest SDK builds; macOS 27 APIs become available | ~20GB, manual download, and Xcode's own updates are more of exactly the version churn that caused this |
| Hardcode `SDKROOT=…/MacOSX26.5.sdk` in the build scripts | One line | A pinned version number is a second thing to remember to change, and it goes stale silently — the build would stay on 26.5 forever, including after a toolchain that can do better arrives |
| Probe each installed SDK and use the newest that compiles (chosen) | No version number anywhere; self-correcting in both directions — the day a toolchain ships the plugin, the newest SDK starts passing and is picked with no edit | A few seconds on a cold run, so it needs a cache |
| Probe, plus keep a copy of the working SDK outside the installer's reach (chosen) | Survives a Command Line Tools reinstall that ships only the newest SDK — the last failure mode the probe alone cannot cover | ~303MB of disk |

### Decision

The last two, as `scripts/select-sdk.sh`: it collects every macOS SDK under
Command Line Tools, Xcode (if present) and its own copy directory, sorts them
newest-first, and typechecks a five-line SwiftUI view with a `@State` in it
against each until one compiles. That path is printed for `SDKROOT`;
`scripts/build.sh` and `scripts/make-app.sh` both build through it. The result
is cached in `~/Library/Developer/Tempo/sdk-pin`, keyed on the compiler version
plus the full candidate list, so adding or removing an SDK — or updating the
toolchain — re-probes by itself. The chosen SDK is copied once to
`~/Library/Developer/Tempo/SDKs`; the copy is a candidate like any other, so
there is no separate fallback path to rot.

No version number appears anywhere in the script.

### Consequences

Verified end to end on this machine:

- Cold run: `SDK 27.0: cannot build SwiftUI here … skipping`, then
  `SDK 26.5: builds SwiftUI`, then the copy — 54s including the copy.
- Cached run: 0.16s, silent.
- `swift build` and `swift build -c release` both complete against the chosen
  SDK (34.6s and 40.3s).
- Simulating a Command Line Tools with its SDKs gone (the roots list pointed at
  a nonexistent directory) selects `~/Library/Developer/Tempo/SDKs/
  MacOSX26.5.sdk`, and a **release build against that copy completes** — so the
  copy is a real fallback, not a reassuring gesture.

The copy is verified by the same probe before it is given its final name; a
half-finished copy would otherwise sit there looking like a candidate for the
day it is actually needed. It is written to `<name>.partial` first, which is
outside the `MacOSX*.sdk` glob, and retried once — the first attempt against
that directory failed and an identical retry succeeded, cause unidentified.

The cost of this choice: while pinned to the 26.5 SDK, Tempo cannot adopt
macOS 27-only APIs. Nothing in the app needs one — it targets macOS 14 and its
newest dependency is Liquid Glass from 26 — and the probe lifts the limit on
its own if Xcode ever appears.

Nothing here writes inside `/Library/Developer`: the script only reads SDKs,
and writes to its own directory under `~/Library/Developer/Tempo`.

---

## 099 — Pausing one player out of several: the HAL says who is audible, the route says who can be stopped

**Date:** 2026-09-16 · **Status:** Accepted

### Context

Asked for directly: *"i want tempo to have the ability to pause a specific
track when multiple thigns are playing: like when spotify is playing but i am
starting a youtube video."*

macOS lets every app hold the output device at once, so Spotify and a YouTube
tab simply play over each other, and Tempo's existing transport row is no help
— every control in it goes through `MediaRemoteService`, which models the
machine as having exactly **one** now-playing client. That is not a limitation
of the adapter's CLI but of the framework underneath it: `MRMediaRemoteSendCommand`
takes a command and a `userInfo` dictionary and nothing else (read off the
vendored `src/adapter/send.m` and `src/private/MediaRemote.h`), so `pause`
always lands on whichever app took over last. In the reported scenario that is
Chrome — precisely the app the user does *not* want paused.

Two things therefore had to be established before any code (Agent Guideline #4),
both measured live on this machine, macOS 26.6, 2026-09-16:

**Who is actually making sound.** The Core Audio HAL knows. Enumerating
`kAudioHardwarePropertyProcessObjectList` and reading
`kAudioProcessPropertyIsRunningOutput` on each object reported Spotify at `1`
and Chrome at `0` while Spotify played alone, with `kAudioProcessPropertyPID`
and `kAudioProcessPropertyBundleID` answering on every object. `AudioTapService`
has used these same selectors since decision 059, but only folded to a single
"is anything playing" bool.

**Which process to blame for the sound.** Browsers and Electron apps render
audio in helper processes. Measured mapping for the helpers present: Chrome's
5648 and 5649 → 1294, Spotify's 22399 → 1383, Discord's 1519 and 1532 → 1299.
Both `responsibility_get_pid_responsible_for_pid` and a plain `ppid` walk
produced that identical set, so the public one is enough.

The obvious walk — take the first ancestor that has an `NSRunningApplication` —
is wrong, and measuring caught it before it ever ran. A helper *does* resolve:
Chrome's helper pid answers with a live object whose bundle id is
`com.google.Chrome.helper` and whose activation policy is `.accessory`, so that
walk stops one process short and yields a bundle id that matches nothing and
can be paused by nothing. The test is the policy: `com.google.Chrome.helper`
and `com.hnc.Discord.helper[.Renderer]` are `.accessory`, Chrome, Discord and
Spotify are `.regular`. Safari is worse still — its audio comes from
`com.apple.WebKit.GPU`, whose parent resolves to nothing at all.

One thing is **not** yet verified and is recorded as such: no YouTube video was
playing during the measurement window, so Chrome's audio has been attributed
through its process tree but never observed with `isRunningOutput` actually set.

### Options

| Option | Pros | Cons |
| --- | --- | --- |
| A list of what is playing, each row with its own pause (chosen, both halves) | Direct — the user picks the one to silence; never acts on its own | Needs the panel open |
| Auto-pause the previous player when a new one starts (chosen, opt-in, default off) | Zero interaction, which is the actual complaint | Acts on another app unprompted; only reaches AppleScript-controllable apps |
| Mute the other app instead of pausing it | Reaches any app, including a background browser tab | The HAL exposes no per-process volume; a YouTube video muted rather than paused keeps running, which is not what "pause" means |
| Inject JavaScript into the browser tab over Apple Events | Would reach a background tab | Requires the user to enable "Allow JavaScript from Apple Events" by hand — a manual step Guideline #8 forbids — and full Automation control of the browser for one button |

### Decision

`AudioSourcesService` publishes the apps that are audible **and** pausable,
from two sources, because neither is sufficient alone. The **now-playing client
comes from MediaRemote**, which already names the app properly and already
knows whether it is playing — that is what makes a browser row correct despite
the helper problem above. **Everything else comes from the HAL**, filtered to
the AppleScript set, which is exactly the set of apps that go on playing
underneath a new now-playing client, and which produce audio from their own
`.regular` process under their own bundle id (measured: Spotify's audio object
is pid 1383 `com.spotify.client` itself, Music's is pid 1306 `com.apple.Music`).

The pause route is part of each row's identity rather than something worked out
at click time:

- `.appleScript(application:)` — Spotify, Music, TV, Podcasts, VLC, IINA,
  QuickTime Player. Names the app, so it works no matter who holds now-playing.
  This is the route that reaches the *older* player.
- `.mediaRemote` — whoever currently holds now-playing, via
  `MediaRemoteService.pauseNowPlaying()`. The only route that reaches a browser
  tab, and it reaches it precisely because the tab is what started last.

An app that is neither — a background browser tab that has lost now-playing —
**is not listed at all**. There is no third route to it, and a row whose pause
button did nothing would be a lying control (UI Principle #4).

The panel draws the rows only when two or more apps are playing: one player is
what the transport row above already controls, and repeating it would be a
second control for the same thing. The scan is a 1s poll that runs only while
the panel is open.

The automatic rule is `Settings ▸ Music ▸ "Pause the previous player when a new
one starts"`, **off by default** — the only switch in `Preferences` that
defaults to off against the house rule at the top of that file, and
deliberately: every other one decides whether Tempo draws something, this one
decides whether Tempo reaches into another app and stops it unasked. When a
different app takes over now-playing *and* is playing, the app that lost it is
paused — but only after re-reading the HAL to confirm it is still making sound
(so pausing Spotify yourself first means nothing is sent), only if it can be
named over AppleScript, and only if the handover still stands 0.4s later. The
comparison is against the last app seen **playing**, not the last app seen:
players emit empty frames between handovers, and comparing against one of those
would blank out the previous player exactly when the rule needs it.

`pause` is sent rather than `playpause` everywhere, including the row buttons:
this feature only ever silences something, and a toggle sent to an app that
stopped on its own between the scan and the click would start it playing.

### Consequences

Spotify-under-YouTube is covered from both ends: Chrome is pausable because it
holds now-playing, Spotify because it answers to its name. The reverse case —
a background browser tab that is not now-playing — is not covered by anything
here and is documented as such in the README rather than papered over.

First use of a row's pause will raise the system's Automation prompt for that
app, once, the same grant `MusicService` already asks for.

Also fixed here, because it made the change untestable: `scripts/make-app.sh`
ran `swift build -c release` directly and so could not build on this machine at
all, failing with the `SwiftUIMacros` plugin error that `scripts/select-sdk.sh`
exists to route around. `scripts/build.sh` had the fix; `make-app.sh` never got
it. It now exports the same selected `SDKROOT`.

Written concurrently with decisions 098, 100 and 101 by another session on the
same day; the SDK workaround this entry leans on is that 098.

---

## 100 — A finished session raises the same card a track change does

**Date:** 2026-09-16 · **Status:** Accepted · **Extends 072**

*Numbered 100, not 098 or 099: a second Claude Code session was editing this
repo while this was written and has already claimed both — 097 and (in its
`AgentLightsView` row-count comment) 098 in one, 099 in its `audioSources`
work in `ContentView`. Those two entries are theirs to write; the gap is
deliberate, not a lost decision.*

### Context

Decision 072 built the sneak peek for the one moment the panel's answer is
wanted without being asked for — a track change. The agent lights have exactly
the same moment and nothing built for it: a turn ending is *the* thing the user
is waiting on, and until now finding out meant either catching the pill's white
dot out of the corner of an eye or hovering the notch to read the row. The user
asked for the finish to raise the same card the next track does.

The transition itself was already being computed. `AgentStatusService`'s
`markFinished` has detected running -> idle since decision 042, with decision
043's interrupted-turn exclusion and decision 045's acknowledgement check
already applied to it — so this is a display for a signal that exists, not a
new read of anything. Tempo still writes nothing under `~/.claude/**`
(Agent Guideline #3).

### Options

| | Option | Against |
|---|---|---|
| A | A **second** overlay beside the track peek | Both draw in the same place under the notch. A track change and a finish land together often enough — you start a turn and change the music — and two cards at that point overlap into unreadable mush |
| B | Derive the card from the `justFinished` flag in the view | The flag is a 20-second *state*, not a moment. The view would have to remember which ids it had already shown a card for, which is the transition memory `markFinished` already keeps, kept twice |
| C | A macOS notification through `UNUserNotificationCenter` | Wrong surface, and this app is about not having to look away from the notch. It also lands in a queue the user has to dismiss, where the point of the peek is that it goes away by itself |
| **D** | **One peek slot, raised from an event the poller publishes** | Chosen |

### Decision

`AppState.lastAgentFinish` is an `AgentFinish` event — session id, label, task
excerpt, and the instant it was observed — published by `markFinished` at the
moment it records the transition, before the flag that follows it. The
timestamp is what makes two consecutive turns of one session two events rather
than one. Two sessions finishing inside a single 2s poll raise the first: there
is a single card, so the second would only replace it in the same frame.

`ContentView` now holds **one** peek slot (`NotchPeek`) instead of a track:
title, optional subtitle, optional glyph and tint, spoken label, and its own
duration. A track change and a finish both go through `raisePeek`, so they
cannot drift apart on placement, material, transition, hit-testing or the
suppression while the panel is open — and a card arriving while another is up
replaces it, which is the right answer for a transient HUD.

The finish card reads *"<folder> finished"* over the session's task line, with
a white `checkmark.circle.fill` and the halo `AgentAppearance(.finished)`
already gives that state in the panel, so the notch says "finished" in the same
colour and shape everywhere. It stays up for a fixed **5 seconds** —
deliberately not a second slider: the two cards are read at different moments
(a track change while you are already looking at the screen, a finish after
something moves in the corner of your eye), so the finish simply wants the
longer of the two.

`Preferences.agentFinishPeek` (Settings ▸ Agents ▸ Finish peek, **on**) gates
it, and is independent of `showAgentLights` — the same relationship
`collapsedAgentLight` has: switching the expanded panel's list off is a
statement about the panel, not a request to stop being told a turn ended.

The task excerpt is rendered in the card and nowhere else — not logged, not
written, not copied (Agent Guideline #5) — the same terms the panel row already
displays it under.

### Consequences

The track peek's observable behaviour is unchanged (Agent Guideline #7): same
material, same position, same 3s default, same suppression rules, same
retraction on a stop or a nameless track. Only the state it lives in was
renamed and generalised.

**Not yet seen on screen, and not built.** `swift build` still fails on this
machine for every SwiftUI file — `SwiftUIMacros.StateMacro` is missing from the
Command Line Tools toolchain and no Xcode is installed (see decision 097's
closing note and NEXT_STEPS ▸ Now). All five edited files parse clean
(`swiftc -parse`), which is as far as verification can go here: type checking
`ContentView` requires the same macro plugin the build needs. The card's
appearance, the 5s duration and the collision behaviour between a track change
and a finish all need a real look once the toolchain is resolved.

---

## 101 — The agent list grows the panel instead of scrolling

**Date:** 2026-09-16 · **Status:** Accepted

**Context.** `AgentLightsView` showed three rows and scrolled the rest
(`visibleRows = 3`). With four or more live sessions — routine on this machine,
which had five during this work — the panel showed three and hid the others
behind a scroll gesture nobody thinks to make on a notch panel. That is exactly
the stale/partial signal UI Principle #4 rules out: the light that wants you may
be the one below the fold, and the attention-first ordering of decision 047 only
mitigates it.

The cap existed for a real reason. The window is never resized while the panel
animates — the window is sized once to the maximum and only the SwiftUI content
moves — so anything the content lays out past `NotchGeometry.panelHeight` is
outside the window and simply never drawn. Decision 063 raised that ceiling to
a constant 680pt, computed from the fullest content mix *including* a
three-row agent list. Growing the list without raising the ceiling would have
traded a scroll for a silent clip, which is worse.

**Options.**

| | Approach | Pros | Cons |
|---|---|---|---|
| A | Raise the 680 constant to a bigger constant | One-line change | Same failure mode one session later; the right number depends on the display |
| B | Resize the `NSPanel` as the content grows | Window is never bigger than it needs | Breaks the invariant the whole hit-testing design rests on: `NotchHitRegion` and `NotchHostingView.hitTest` read live geometry against a fixed window rect, and a window frame animating alongside the SwiftUI spring is a second animation to keep in sync |
| C | Ceiling = target screen height − margin; list grows to fit it | Keeps the fixed-window invariant exactly; the bound becomes the physical limit rather than a guess at content | The window is mostly empty most of the time |

**Decision: C.** `panelHeight` is now
`max(screenFrame.height - 24, 320)`, re-read on every display change through
the existing `refresh()` / `applyGeometry()` path like every other figure in
`NotchGeometry`. The empty window costs nothing: it is transparent outside the
drawn shape and `NotchHostingView.hitTest` already hands every point outside the
live silhouette to the app behind (Agent Guideline #3), and the drawn panel
still sizes itself to its content in `ContentView.currentHeight`.

`AgentLightsView` keeps a row cap, but it is now derived rather than fixed:
`(panelHeight - 520) / 30`, floored at three. The 520 is the fullest non-agent
panel content (decision 063's ~556pt figure less the three agent rows it
included), rounded up. The cap is not a display choice any more — it is the
line past which a row would be laid out below the window and not drawn — so it
only bites on a machine with more live sessions than the screen can show, and
the scroll survives underneath for exactly that case.

**Verified on screen.** Five live sessions, 3440x1440 display: ceiling 1416pt,
panel content measured 542pt + 32pt strip = 574pt, all five rows drawn with the
panel's rounded bottom below them (`TEMPO_DEBUG_VIZ=1`, pointer driven into the
notch the way `scripts/capture-panel-animation.sh` does it, screenshot read
back). Before this change the same five sessions drew three rows and scrolled.

### Consequences

The panel is now as tall as its content demands, so a busy machine gets a tall
panel — that is the intent, and the ceiling is what keeps it on the display.
Nothing else in the panel changed: every other section is bounded as it was
(the shelf and output rows still scroll horizontally), and the debug line that
reports a clipped panel is unchanged and still the way an overflow shows up.

---

## 102 — Tempo goes public at v0.4, source-only, on a new tag

**Date:** 2026-09-16
**Status:** Accepted
**Reverses:** the privacy half of decision 007

### Context

The ask was "release v0.1 of Tempo on GitHub". Three facts made that literal
reading impossible, and all three were checked before anything was published:

- **`v0.1`, `v0.2` and `v0.3` already exist as tags, and are already pushed**
  (`v0.1` = `dea8c33`, 2026-08-22). They are internal build milestones, not
  releases — `gh release list` was empty, so what had never existed was the
  GitHub *Release*, not the tag.
- **The repository was private** (decision 007), so a Release on it would have
  been visible to nobody.
- The working tree carried ~1,000 uncommitted lines across 17 tracked files and
  four new sources, so no existing commit contained the current work.

### Options considered

| Option | Verdict |
|---|---|
| Release the existing `v0.1` tag | Rejected — `dea8c33` is five weeks and three milestones behind; publishing it as the current app would be a lying signal |
| Force-move `v0.1` to the current commit | Rejected — rewrites already-pushed history for a cosmetic version number |
| New three-part tag `v0.1.0` | Viable: does not collide with the two-part `v0.1`, and starts the public series at "v0.1" as asked |
| **New tag `v0.4`** | **Chosen** — continues the existing `v0.1`/`v0.2`/`v0.3` series honestly rather than restarting the numbering beside it |

### Decision

Tag the current work **`v0.4`** on `main`, flip `Gameslayer999/Tempo` to
public, and publish a **source-only** Release — no binary attached.

Source-only is the deliberate half. `scripts/make-app.sh` signs the bundle with
an Apple Development identity when one is in the keychain and ad-hoc otherwise;
**neither is notarized**, so a `.zip` downloaded from GitHub would arrive
quarantined and be refused by Gatekeeper on every machine but this one. Shipping
a download that cannot be opened is worse than shipping none, and the honest
alternative — telling every user to `xattr -d com.apple.quarantine` a binary
from a stranger — is advice this project should not give. The existing
`dist/Tempo-v0.2.zip` was also assembled by hand, which Agent Guideline #8
forbids; a zip asset would need packaging scripted first.

### What was checked before flipping visibility

Going public is effectively irreversible (forks, caches, indexing), so the
whole history was audited, not just the working tree:

- **Credentials: none, ever.** All 18 commits scanned for token, key and
  private-key shapes — zero hits. `config.json`, `tokens.json` and `*.log` were
  never committed; `.gitignore` has covered them since the first commit.
- **Personal paths: eight, all in the uncommitted README**, in the
  `~/.codex/hooks.json` example, which hardcoded
  `/Users/<user>/Documents/code/Tempo/...` eight times. Replaced with
  `/absolute/path/to/Tempo/...` plus a note that Codex expands neither `~` nor
  relative paths in a hook command. Committed history had none.
- **`scripts/__pycache__/` was untracked *and* ungitignored** — a `.pyc` was
  one `git add -A` from being published. `__pycache__/` and `*.pyc` added to
  `.gitignore` and the directory removed.
- **Licensing is clean for redistribution.** Tempo is MIT; the vendored
  `mediaremote-adapter` is BSD-3 with its LICENSE, upstream URL, pinned commit
  and local modifications all recorded in `Vendor/mediaremote-adapter/`.

### Consequences

The README's status banner no longer describes the 2026-08-20 rework as the
newest thing in the app. It now states the version, that the app has only ever
run on one Mac, that there are no tests, and it **names the seven features that
compile but have never been watched on screen** (two-player pause rows, finish
peek, lock-screen cards, album-glow curve, full-screen hiding, pinned-display
picker, capture exclusion) rather than leaving a visitor to infer that
everything listed is proven. A public pre-alpha that overstates itself is the
one failure mode worth more than the download convenience given up above.

`CLAUDE.md` also claimed Tempo "builds with `swift build`", which decision 098
had already made false; it now says `scripts/build.sh`.

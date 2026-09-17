# Tempo

A dynamic notch for macOS — in the spirit of boringNotch and NotchNook — that turns
the MacBook notch into a glanceable surface for **music** and **live AI-agent
session status**.

> **Status: pre-alpha — v0.4.** Everything described below is implemented and
> builds clean with `scripts/build.sh` on macOS 14+ (Apple silicon, developed on
> macOS 26). It has only ever run on one Mac, and there are no tests: treat it as
> something to read and build, not something to depend on. Several features are
> written and compiling but **have not yet been watched on screen** — the
> two-player pause rows, the session-finish peek, the lock-screen cards, the
> album-glow strength curve, full-screen hiding, the pinned-display picker, and
> capture exclusion. `NEXT_STEPS.md` names exactly what is unverified and how to
> check it; `DECISIONS.md` records why every choice was made.
>
> Distribution is source-only. There is no signed or notarized download, so
> build it yourself — see **Building**.

## What it does (v1)

**Collapsed (default)** — a Dynamic-Island-style black pill hugging the notch, no
wider than its content:
- **current album artwork** on the left of the notch — for whatever is playing:
  Spotify, Apple Music, a YouTube video in your browser, a podcast. Tempo reads
  macOS's own now-playing information, so it is not tied to one app
- an **audio-reactive visualizer** on the right — five bars driven by a live
  5-band frequency analysis of whatever your Mac is actually playing (bass in
  the center): Spotify, a YouTube tab, a game, a call.
  Requires running the bundled app and the one-time audio permission below;
  otherwise the bars fall back to a playback-synced animation. The bars settle
  when your Mac is muted or at zero volume — a process tap is taken before the
  output device's volume, so this is deliberate: no motion for something you
  can't hear.
- an **agent light** outboard of the visualizer — the agent signal without
  expanding anything. By default it is one dot carrying the most urgent state
  across your Claude Code sessions: 🔴 an error · 🟠 one is blocked and needs
  you · ⚪️ solid white, one *just finished* and you haven't looked at it yet ·
  🟢 any are working · a hollow grey ring, all idle. Only blocked pulses;
  nothing else moves. **Shape carries the state, not just colour** — the states
  that want you draw as a full-size haloed dot, the ones that don't draw
  smaller (running) or hollow (idle), so the light still reads on a greyscale
  display or with any form of colour blindness. The white dot goes out on the same click that clears the row's white
  light in the panel, so the two never disagree. Switch it to
  one dot per session (up to three), or off, in Settings ▸ Agents. It draws
  nothing at all when no sessions are running.
- a **sneak peek** when the track changes — the title and artist flash below
  the notch for a few seconds and retract, so you find out what just started
  without moving the pointer or opening anything. It is a Liquid Glass capsule
  on macOS 26, the same material the system's own AirPods and volume HUDs wear
  (an opaque plate on macOS 14/15, with Reduce Transparency on, or with the
  panel style set to Solid). It is drawn over whatever is behind it and takes
  no clicks. Length is adjustable, and it stays out of the way while the panel
  is already open.
- **the same flash when a Claude Code session finishes** — the moment a session
  goes from working to done, the folder it's in and what it was working on flash
  under the notch for five seconds and retract, in the same glass capsule, with
  a white check beside them. It's the answer to "is it done yet" without
  switching windows: nothing opens, nothing takes focus, and there is no sound.
  Only a turn that actually ended raises it — a turn you interrupted doesn't —
  and nothing flashes while the panel is already open, where that session's own
  row is on screen anyway. On by default; switch it off in Settings ▸ Agents.

When nothing has actually played for a minute — paused and forgotten, or no
player running at all — the media UI switches off: the cover, the visualizer and the
transport controls and the progress bar disappear, and the pill shrinks back to
exactly the hardware notch — except for the agent light, which stays put, since
that is the signal worth widening a bare notch for. It comes back the moment
something plays again.

Audio with no now-playing card behind it — a YouTube tab that publishes no track
info, a game, a call — still gets a visualizer, with no artwork beside it. It
appears about two seconds in, so a notification ping never opens the pill, and
stays up for fifteen seconds after the sound stops so the gap between two clips
doesn't retract it. The panel still opens on hover, with the usage graphs and
agent lights in it.

**Hover to expand** — resting the pointer on the pill briefly (60ms by default,
adjustable in Settings ▸ General) opens the full panel, with a trackpad haptic
tick at the moment it opens; a pointer merely crossing the notch doesn't. Moving the mouse away collapses it. **Clicking anywhere on the open
panel pins it** — including the controls, so using the transport buttons or the
playlist picker keeps it open; only a click outside unpins and collapses it. Honors the system Reduce Motion
setting (fades instead of springs).

The expanded view is a Liquid Glass panel (macOS 26's design language; frosted
material on older macOS), sized to its content, opening below the notch. It is
in **two groups** — what's playing, then what your Mac is doing — set apart by a
wider gap and a hairline, so the panel reads as two things rather than one long
column:
- **now playing**: the album cover slides down out of the pill and grows, with
  the track and artist centred above the play / pause button and the previous /
  play / next controls spread across the width beside the cover. The scrubber
  and the add-to-playlist row sit under the whole block at full width
- **progress bar** — elapsed time, a full-width scrubber and time remaining,
  under the cover and controls. **Drag the knob, or click anywhere on the bar,
  to jump to that point in the song**; the track jumps when you let go.
  Scrubbing inside the player's own window is reflected here within about half
  a second, because macOS pushes the new position to Tempo as it happens.
- **what else is playing** — start a YouTube video while Spotify is going and
  both play at once; macOS lets every app hold the audio device. When two apps
  are playing, Tempo lists them under the controls with a pause button each, so
  you can silence the one you didn't mean to leave running. Turn on
  Settings ▸ Music ▸ **Pause the previous player when a new one starts** and it
  happens by itself — the app that was already playing stops as soon as another
  takes over. It's off by default because it reaches into another app unasked.
  Tempo can pause any app that answers AppleScript (Spotify, Music, TV,
  Podcasts, VLC, IINA, QuickTime Player) plus whichever app most recently took
  over playback — which is how a YouTube tab gets paused. A browser tab that is
  already playing in the *background* can't be reached by either route, so
  Tempo leaves it out of the list rather than offering a button that does
  nothing. The first pause of a given app asks macOS for permission to control
  it, once.
- **audio output** — a mute button, a volume slider, and one chip per output
  device: click a chip to switch where sound goes. Tempo only sets the system's
  default output device and its volume; it never sits in the audio path, so it
  can't take your sound with it if it stops. Some digital outputs (HDMI) own
  their own level — Tempo says so instead of showing a slider that does nothing
- **file shelf** — drag any file toward the notch and the panel opens as a drop
  target before you get there; let go and Tempo keeps a copy. Hover the notch
  later and the shelf shows what it is holding: drag an item back out to any
  app, hover an item and click the x in its corner to remove it, or right-click
  to reveal it in Finder. The copy means the shelf still works after you move or
  delete the original
- **add the current song to a Spotify playlist** — full width, under the
  scrubber. The picker lists only
  playlists you can actually add to (your own, plus collaborative ones), or just
  the ones you ticked in Settings; if an add fails, Tempo says why rather than
  just flagging it. This one row is Spotify-only — it needs Spotify's own track
  id — so it is disabled while something else is playing
- **system usage** — compact CPU and memory sparklines (last 60 s, iStat-style)
- **token history and pace** *(opt-in, off by default)* — the last seven days
  of Claude Code token use and the model you leaned on most, plus a bar showing
  how much of a rolling five-hour budget you have spent. The pace figure is an
  **estimate** and is labelled as one: Claude Code does not record your real
  rate limit anywhere Tempo can read, so you set the budget and Tempo shows the
  busiest window it has actually measured so you can calibrate it. Counts
  input, cache-creation and output tokens; excludes cache reads, which would
  otherwise swamp every other number.
- **agent session lights** — one row per open Claude Code or Codex CLI session: a state
  light (🟢 running · 🟠 blocked, needs you · ⚪ finished and not yet seen ·
  hollow grey idle · 🔴 error), the session's folder, and a one-line description
  of what it is working on, so two sessions
  in the same repo are told apart at a glance. With the extra room a row has,
  the light also carries a glyph — `?` blocked, `!` error, a checkmark for
  finished — so the state is legible without relying on its colour. Read from
  [AgentStatus](https://github.com/Gameslayer999/AgentStatus)'s status files, plus Tempo's
  Codex hook helper under `scripts/agentstatus-codex-hook.py`. This is
  Tempo's differentiator over other notch apps. Those files record hook *events*,
  so Tempo cross-checks them against Claude Code's own view of each session
  (read-only, and only what a light needs): a turn you interrupt with Ctrl-C or
  Esc greys its light straight away instead of leaving it green, and a
  background agent's light shows green while it is working and orange while it
  is waiting on an answer from you. A row stays white until you click it —
  going to the session is what marks it as seen — and lights up again the next
  time that session finishes something. Rows that want you float to the top —
  blocked and errored first, then finished-and-unseen, then running, then idle —
  so the row that wants you is at the top. The list doesn't scroll: the panel
  grows a row taller per session, up to what the display can show. The description is that session's current prompt, shown in the
  panel only — Tempo never logs it, stores it, or sends it anywhere; switch the
  lights off in Settings ▸ Modules if you would rather it not be on screen.
  Claude Code rows also carry three figures on the right — **context · tokens spent ·
  turn length** (`125k · 581k · 2m14s`), read from Claude Code's own transcript
  for that session. The first is how full its context window is, the second is
  everything it has spent including its subagents', and the third counts up
  while a turn is running and shows what the last one took when it isn't. Hover
  the row to see the three named. Context is an absolute count, not a
  percentage, because the transcript doesn't record which context window the
  session was opened with — a percentage would be a guess. There is no dollar
  figure for the same reason: Claude Code records no cost, so Tempo would be
  inventing one. Switch the figures off in Settings ▸ Modules and Tempo stops
  reading the transcripts entirely. Codex rows skip those figures because
  Codex documents its transcript path as a convenience rather than a stable
  hook interface.
  **Click a row to go to that session**: a terminal session raises the tab it is running in (Terminal.app
  matched by tty, Ghostty by session title — or, for a session Claude has not
  titled yet, by the tab's working directory), a VS Code or Cursor session
  raises the window that has its folder open, and a Claude Desktop session
  brings Claude forward. The panel collapses on the way out. Raising a window that is
  on another Space or full-screen relies on the Accessibility permission — grant
  Tempo *System Settings ▸ Privacy & Security ▸ Accessibility* for the fastest,
  most reliable jump; without it editors are still reached through their CLI and
  terminals through app-level focus.
- a **gear in the top-right corner** opens Settings (below).

Codex CLI lights use Codex's official hook events. Point Codex at Tempo's helper
from `~/.codex/hooks.json`, substituting the absolute path to your own clone —
Codex does not expand `~` or resolve relative paths in a hook command:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "Interrupt": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/Tempo/scripts/agentstatus-codex-hook.py" }] }]
  }
}
```

The expanded panel is rimmed with a soft glass edge so it reads as a distinct
surface over whatever is behind it, and its material is yours to pick — see
Settings ▸ General.

Tempo is built to be extremely light: everything is event-driven or gated (no
music polling; the visualizer and animations fully stop redrawing at rest).
Measured ≈0.3% CPU idle on this machine.

## First run

The first time Tempo launches, a cursive **hello** writes itself out of the
notch — Apple's own lettering, drawn as one pen stroke at a steady hand's pace
over about two and a half seconds — holds for a beat, then fades out as the
panel resolves into a short setup list. Click the word to skip straight to it.

The list is the handful of things Tempo needs a human to say yes to, each
showing its **live** state rather than a checkbox you tick:

- **Audio visualizer** — macOS asks for System Audio Recording the first time
  audio plays; until you allow it, the bars stay still. The row links to the
  System Settings pane. (Tempo cannot read this permission's state, so this row
  tells you what will happen rather than claiming a status it can't verify.)
- **Lock screen cards** — asks for notification permission, and switches the
  lock-screen cards on if you allow it. If you've refused before, macOS will not
  ask again — the row says so and links to System Settings, which is the only
  place that can undo it.
- **Weather location** — appears once the cards are on; asks for *approximate*
  location so the weather card knows where you are. You can type a city instead.
- **Spotify playlists** — optional, opens Settings ▸ Music (the Client ID needs
  a keyboard, and the notch panel deliberately never takes focus).

**Get Started** closes it and the notch behaves normally from then on. Nothing
here is mandatory and everything is changeable later in Settings. To see it
again: Settings ▸ About ▸ **Show the welcome again**.

## Lock screen

With your Mac locked, Tempo can show **two notification cards** — current
weather, and what's playing:

- posted when the screen locks
- updated **in place** while it stays locked, so a track change replaces the
  card rather than stacking a new one
- withdrawn when you unlock, so Notification Center isn't left holding them

They're silent: no sound, and nothing that beeps at a sleeping Mac. A card only
appears when it has something true to say — no card for a paused player, none
for weather that hasn't loaded.

Tempo asks for notification permission when you switch the cards on. If macOS
has a refusal on file it will not prompt again, and the request fails
immediately — Settings ▸ Weather and the first-run row both report that and link
to **System Settings ▸ Notifications ▸ Tempo**, where **Allow Notifications**
has to be turned back on by hand.

**Tempo cannot draw on the lock screen.** macOS composites it in a secure
context that excludes app windows at every window level; this was built,
measured and abandoned (see decision 036 in `DECISIONS.md`). Notifications are
the only surface available, which is what these are.

Two switches decide whether the cards are actually *legible* when locked, and
neither is Tempo's to set — in **System Settings ▸ Notifications ▸ Tempo**:

- **Show on Lock Screen** must be on
- **Show previews** must be **Always** — the default, *when unlocked*, renders a
  locked card as a contentless "Tempo · Notification"

Settings ▸ Weather links straight to that pane and says which of these is
outstanding.

## Settings

The gear in the expanded panel's top-right corner opens a standard macOS
Settings window — sidebar of panes on the left, grouped form on the right, the
same shape as System Settings. Opening it collapses the notch panel. Tempo has
no Dock icon, so the gear is the usual way in; opening Tempo again from Finder
while it is already running opens Settings too. Each pane's sidebar row carries
its own coloured icon — grey General, purple Appearance, red Music, green
Agents — so a pane is found by colour before it is read.

- **General** — *Open Tempo at login* (works from `dist/Tempo.app` only; a bare
  `swift build` binary has no bundle to register, and the toggle says so), plus
  a reminder of the hover / click / click-outside interaction model and a
  *Hover delay* slider — 0–400ms, 60ms by default — setting how long the
  pointer must rest on the notch before the panel opens. The haptic tick fires
  at that same moment, so a shorter delay is also more likely to land while
  your finger is still on the trackpad; a longer one keeps a pointer that is
  only passing over the notch from opening it, and 0 opens the instant the
  pointer arrives.
- **Appearance** — *Expanded panel* picks the material the open panel is drawn
  in, by clicking a miniature of the panel drawn in that style: **Regular
  glass** (default), **Clear glass** (near-transparent, with a slight scrim so
  the text stays readable), **Album tint** (frosted glass carrying the current
  cover's dominant colour — with nothing playing, or a cover Tempo can't
  sample, it falls back to plain glass) or **Solid** (opaque, no glass). Each
  preview is the real material over a stand-in desktop, so the translucent ones
  are actually comparable side by side, and the tint preview carries the colour
  of whatever is playing right now. The notch updates as you pick. On macOS
  below 26 there is no Liquid Glass, so the three glass options fall back to the
  nearest system material.

  *Accent colour* follows your system accent or takes a custom pick. A colour
  too dark to read on the panel is lightened until it is legible — the eight
  macOS system accents already clear that bar and pass through untouched. The
  accent never recolours the agent lights: those hues carry state.

  *Album art* has two independent switches. **Glow** paints a bloom in the
  cover's own colour behind the artwork, with a strength slider; **Blur behind
  album art** puts a blurred, slightly enlarged copy of the cover behind it.
  They read as different looks, so you can have either, both, or neither. Both
  are drawn only in the expanded panel — in the collapsed pill the bloom would
  spill past the black silhouette. Both switch off under Reduce Transparency.

  *Visualizer colour* is white (the default), the accent colour, the current
  cover's colour, or a spectrum — a hue per frequency band, warm in the centre
  where the bass sits, cooling outward.
- **Every slider in Settings can also be typed into.** Click its value, enter a
  number, press Return — the units are optional (`150`, `150 ms` and `150ms` all
  work, as do `2.5M` for the token budget and `Never` for the paused-media
  timeout). A typed value is kept exactly as entered rather than snapped to the
  slider's step, which is the point: dragging steps, typing reaches what lies
  between.
- **Displays** — *Preferred display* pins the strip to one screen; left on
  automatic, Tempo hugs the built-in notch whenever that display is available.
  A pinned display that isn't currently attached falls back to automatic rather
  than leaving the panel nowhere. **Show the strip on external displays**
  governs what Tempo draws when there is no hardware notch to hug: with the lid
  closed, or on a Mac with no built-in notch, it normally falls back to a small
  strip at the top of whichever display carries the menu bar. Switch this off
  and that strip isn't drawn — but Tempo is still there: push the pointer into
  the very top edge of the display, in the middle, the same way you drop a
  hidden menu bar, and the panel opens with the same hover delay and the same
  tick. The target is the middle of the menu bar's own row, and where that bar
  auto-hides Tempo waits until it is actually down — so reaching for a tab in a
  full-screen browser, which runs to the same top edge, doesn't open it. In that mode only, Tempo keeps a zero-width item in the menu bar: it
  draws nothing and exists purely to sense whether the bar is down. **Edge
  hold** sets how long the pointer must stay at the edge after the menu bar has
  dropped — 0 opens the moment it lands, up to 150 ms for a deliberate hold. It
  applies only while the strip is hidden, so it's disabled when the toggle
  above it is on. While it is closed it is invisible *and*
  click-through, so the menu bar underneath behaves exactly as if Tempo weren't
  running.

  *Full screen* chooses what happens when an app goes full screen: **Never
  hide** (the default, and how every earlier version behaved), **Hide for the
  app that's playing**, or **Hide for all apps**.

  *Hide from screen capture* excludes the panel from screen sharing and
  recording — Zoom, Meet, Teams, OBS and `screencapture` alike. Off by default.
  Worth knowing: the agent lights and session labels are exactly the content
  you don't want on a shared screen, and this also hides the panel from Tempo's
  own capture script.
- **Music** — a searchable list of your playlists: tick the ones you add songs
  to most and only those appear in the notch picker (tick none and all are
  offered). Plus connection status, Connect / Disconnect, and a guided
  three-step setup: a button that opens the Spotify Developer Dashboard, a copy
  button for the exact Redirect URI, and the Client ID field. See below for why
  that setup exists at all.

  *Controls* is a five-slot editor for the transport row: drag a control onto a
  slot, or pick it from the slot's menu, with a live preview and a reset. The
  palette is **Previous**, **Play / Pause**, **Next**, **Mute** and **Empty** —
  every action Tempo can actually carry out. Empty slots are skipped rather
  than left as gaps, and the row stays centred on whatever sits in the middle.
  Adding a song to a playlist is not a slot, because it needs a playlist chosen
  — that button lives in the panel's playlist row, where the choice is.

  *Sneak peek* flashes the title and artist under the notch when the track
  changes, without opening the panel, for as long as its slider says. *Keep
  media showing* sets how long after playback stops the notch keeps showing the
  media wings — 60 seconds by default, because a pause to take a call is not
  the end of listening; 0 keeps them up indefinitely. *Pause the previous
  player when a new one starts* is the automatic half of the "what else is
  playing" list above — off by default, and it only acts on apps Tempo can
  address by name.
- **Agents** — the agent session lights and the token/timing figures on those
  rows, and **Agent light**, which picks what the *collapsed* pill shows: a
  summary dot (the default), one dot per session, or nothing. Switching the
  figures off stops every transcript read.

  *Finish peek* — **Flash a session when it finishes**, on by default, is the
  five-second card described above. It's independent of the lights: it's a
  signal in the collapsed notch, like the pill's own dot, so turning the panel's
  list off doesn't stop it.

  *Usage* adds two opt-in surfaces, both off by default because they read every
  project's transcripts rather than one session's. **Token history** shows the
  last seven days and the model you used most. **Rate-limit pace** shows how
  much of a rolling five-hour budget you've spent.

  That pace figure is an **estimate**, and is labelled as one everywhere it
  appears. Claude Code doesn't record your real rate limit anywhere on disk, so
  Tempo cannot read it — you set the budget yourself, and Settings shows the
  busiest five-hour window it has actually measured so you can calibrate rather
  than guess. Tempo counts input, cache-creation and output tokens and excludes
  cache reads; counting cache reads would swamp every other number.
- **Weather** — the lock-screen cards and where their weather comes from.
  *Lock screen*: a master switch plus one per card (weather, what's playing).
  *Location*: **Use my location** (approximate — CoreLocation at reduced
  accuracy), a **City** field used whenever location is off, denied or hasn't
  produced a fix yet, and °F / °C. *Current conditions* shows the live reading
  and a Refresh button, so you can tell the feature is working without locking
  your Mac. The pane reports notification permission and links to the two
  System Settings switches described above. Switching the weather card off
  stops the network requests *and* the location manager — off means off.
- **Modules** — show or hide the audio visualizer, the audio output row, the
  file shelf and the CPU/memory graphs. Switching the graphs off stops their
  sampling timer entirely. Also **Show the welcome again**, which replays the
  first-run hello.
- **About** — version and **Quit Tempo**. Tempo has no Dock icon and no
  menu-bar item, so that button is the only way out apart from ⌘Q while the
  Settings window is in front. Quitting stops everything — the panel, the
  lock-screen cards, the agent lights — and withdraws any cards already
  delivered. Open Tempo from Finder or Spotlight to bring it back; with *Open
  Tempo at login* on it also returns at your next login.

Standard editing shortcuts (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z) work in the Settings window, and
⌘Q there quits Tempo.

## Accessibility

Tempo follows the four macOS accessibility settings that apply to a surface
like this one. All of them live in *System Settings ▸ Accessibility ▸ Display*
and none of them need anything switched on inside Tempo.

- **Reduce Transparency** — the expanded panel drops Liquid Glass entirely and
  draws opaque, whichever panel style is selected. (Album tint deliberately
  does *not* survive as an opaque tint: the point of the setting is that
  nothing behind the window shows through, and a tint that changes with the
  track is its own kind of distraction.)
- **Increase Contrast** — the panel gains a deeper scrim under its content and
  a harder rim light, and every control in it keeps a visible plate and border
  at rest instead of appearing only when you hover it.
- **Reduce Motion** — the panel opens and closes with a short fade rather than
  a spring, the first-run `hello` appears already written, controls stop
  growing under the pointer, and the visualizer stops moving: it shows a fixed
  raised bar profile while audio is playing and a flat row when it isn't, so
  you still get the "something is playing" signal without the animation.
- **Colour** — no state in Tempo is carried by colour alone. The agent lights
  differ in fill, size and glyph as well as hue; the current audio output chip
  is outlined, not just tinted.

The pointer turns into a hand over anything clickable in Tempo's own surfaces
— the transport buttons, the gear, the output chips, the playlist picker, the
shelf's remove button, the agent rows — because those controls draw no button
chrome until you are already on them. The Settings window keeps the system's
arrow, since those are standard macOS controls.

Text throughout uses the system's named text styles, so it tracks your text
size setting rather than being pinned to fixed point sizes. Controls, tooltips
and VoiceOver labels are present on the transport buttons, the scrubber (which
is an adjustable element — VoiceOver can seek it), the mute button, the output
chips, the shelf items and every agent row.

## Requirements

- macOS on a notched MacBook (works on notchless displays with a fallback strip)
  - With an external monitor attached, the panel stays on the built-in notch. Close
    the lid and it moves to the menu-bar display as the fallback strip, and back to
    the notch when you open it — plugging, unplugging, and rearranging displays are
    all followed automatically, no restart. If you would rather not see the strip on
    the external display, switch off Settings ▸ General ▸ *Show the strip on
    external displays* — the panel still opens when you push the pointer into the
    very top edge of the screen, in the middle, far enough that the menu bar drops
    with it.
- Swift toolchain (Command Line Tools are enough — the project builds with SwiftPM,
  no Xcode project)
- **Spotify desktop app** — only for add-to-playlist. Now-playing and transport
  work with any player through macOS's own media system
- *(optional)* an internet connection for the weather card — Tempo uses
  [Open-Meteo](https://open-meteo.com), which needs no account and no API key
- *(optional)* [AgentStatus](https://github.com/Gameslayer999/AgentStatus) installed —
  its hooks provide the session status Tempo displays. Without it, the lights simply
  don't appear.

## Build & run

```sh
./scripts/make-app.sh   # builds release + assembles and signs dist/Tempo.app
open dist/Tempo.app
```

If Tempo was already running, `make-app.sh` quits and relaunches it for you:
`open` on an already-running app activates the existing process instead of
launching the new binary, so without that a rebuild silently keeps the old build
on screen.

Two one-time permission prompts, both required for full function:
- **Automation → Spotify** — only for add-to-playlist, which needs Spotify's own
  track id. Now-playing, the transport buttons and the progress bar all work
  without it, for any player.
- **System Audio Recording** — the audio-reactive visualizer. Tempo taps your
  Mac's audio output, computes five band levels, and discards the samples;
  nothing is recorded or stored, and no microphone is ever read. Decline it and
  the visualizer simply falls back to a playback-synced animation that can only
  follow the app macOS reports as now-playing.

### How now-playing works

macOS 15.4 locked its media API to apps Apple entitles for it, so Tempo reads it
the way every other third-party app does: a small BSD-licensed helper
([mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), vendored
under `Vendor/`) is loaded inside `/usr/bin/perl`, which *is* entitled, and
streams now-playing updates back to Tempo. `scripts/make-app.sh` builds it
automatically and checks the mechanism still works on your macOS version,
failing the build with a clear message rather than shipping a silently empty
notch. There is nothing to install.

### Building

Build with **`scripts/build.sh`** (`scripts/build.sh -c release` for a release
build); `scripts/make-app.sh` uses it too. It takes the same arguments as
`swift build` and exists because bare `swift build` targets the newest SDK
installed, which may not be one your machine can compile SwiftUI against — the
macOS 27 SDK turned `@State` into a macro whose compiler plugin ships only
inside Xcode, so on a Command-Line-Tools-only Mac every SwiftUI file fails with
`plugin for module 'SwiftUIMacros' not found`. `scripts/select-sdk.sh` probes
each installed SDK and picks the newest one that actually compiles, caching the
answer and keeping a copy of that SDK in `~/Library/Developer/Tempo/SDKs`
(~303MB, copied once) so a toolchain update can't take it away. No SDK version
is hardcoded: install Xcode and the newest SDK is picked up automatically. Run
`scripts/select-sdk.sh --refresh` to re-probe by hand.

macOS only grants the audio permission to a signed `.app` bundle, so the bundled
launch above is the primary run path. `scripts/build.sh -c release &&
.build/release/tempo` still works for development, but the bare binary always
gets the fallback visualizer (the OS silently delivers it zeroed audio). Note:
the bundle is ad-hoc signed unless an Apple Development identity is in your
keychain, so a rebuild changes its code identity. macOS then silently delivers
the tap zeroed audio — the visualizer falls back to the synced animation with no
prompt and no error. Re-arm the prompt with `tccutil reset AudioCapture
com.gameslayer999.tempo`, relaunch, and click Allow.

## One-time Spotify setup (only for add-to-playlist)

Play/pause/skip, the progress bar and artwork need **no** account setup. Adding songs to playlists
uses the Spotify Web API and needs a free Spotify Developer app. This can't be
skipped or bundled: Spotify's AppleScript interface — which drives everything
else Tempo does — has no playlist commands at all, and Spotify requires every
Web API app to be registered under its own developer account.

1. Go to <https://developer.spotify.com/dashboard> and create an app.
2. Add `http://127.0.0.1:8888/callback` as a Redirect URI.
3. Open Tempo's **Settings ▸ Music** (the gear in the expanded panel), which
   walks through these same steps with an *Open Dashboard* button and a *Copy*
   button for the Redirect URI. Paste the app's **Client ID** and click **Save
   Client ID**.
4. Click **Connect Spotify** — in Settings or in the expanded panel — and approve
   in the browser.

Saving writes `~/Library/Application Support/Tempo/config.json`
(`{"spotify_client_id": "…"}`); you can still create that file by hand instead and
restart Tempo. **Remove** deletes it, and changing the Client ID drops any tokens
issued to the old app.

Tokens are stored locally in `~/Library/Application Support/Tempo/` with owner-only
permissions and never leave your machine except to Spotify's API. Until configured,
the add-to-playlist feature simply hides itself. **Disconnect** forgets Tempo's copy
of the tokens (it does not revoke the grant on Spotify's side — do that from your
Spotify account page).

## Privacy

- Tempo is **read-only** on `~/.claude/` and `~/.codex/` — it never writes to,
  modifies, or installs anything into your Claude Code or Codex setup. The
  optional Codex hook helper is installed by you, outside Tempo.
- The token and timing figures read Claude Code's session transcripts under
  `~/.claude/projects/`, and take **numbers and timestamps only**: token counts,
  a turn's start, a turn's duration. No message, prompt or tool output is read
  out of them, and nothing is stored or logged. Switching the figures off in
  Settings ▸ Modules stops those reads entirely.
- The audio tap is scoped to Spotify's process; samples are reduced to five
  band levels on the fly and never written anywhere.
- Now-playing information comes from macOS's own media system, read through a
  small bundled helper (see below). Track metadata and artwork are rendered and
  nothing else — never logged, never written to disk, never sent anywhere.
- Files you drop on the shelf are **copied** into
  `~/Library/Application Support/Tempo/Shelf/` (owner-only) and stay on your
  Mac. Remove an item and the copy is deleted. The shelf's index records file
  names, never the paths you dragged from.
- **Location and weather.** When the weather card is on, Tempo asks for
  *approximate* location (CoreLocation at reduced accuracy — city-scale, which
  is all a weather lookup needs) and sends a **rounded coordinate** to
  Open-Meteo. Nothing else goes with it: no identifier, no device name, no
  session data. The device's coordinate is **never written to disk** — only a
  city *you type* has its resolved coordinates cached. Deny location, or switch
  the weather card off, and the location manager is never started at all.
- **Lock-screen cards** are ordinary local notifications built on your Mac.
  Their contents are the weather reading and the track metadata already on
  screen; nothing is sent anywhere to produce them, and both are withdrawn when
  you unlock or quit Tempo.
- No analytics. The only network calls are Spotify's artwork CDN, (if
  configured) the Spotify Web API, and — if the weather card is on —
  Open-Meteo's forecast and place-lookup endpoints.

## Project docs

- `CLAUDE.md` — onboarding guide + agent guidelines (read first)
- `DECISIONS.md` — every architecture decision, with rationale
- `NEXT_STEPS.md` — living build queue

## License

MIT

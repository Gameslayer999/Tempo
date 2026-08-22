# Tempo

A dynamic notch for macOS — in the spirit of boringNotch and NotchNook — that turns
the MacBook notch into a glanceable surface for **music** and **live AI-agent
session status**.

> **Status: pre-alpha.** The v1 feature set plus the 2026-08-20 core rework
> (real audio visualizer, usage graph, Dynamic-Island pill, click-reliability fix)
> and the Settings window builds clean and is awaiting live user verification.
> See `NEXT_STEPS.md`.

## What it does (v1)

**Collapsed (default)** — a Dynamic-Island-style black pill hugging the notch, no
wider than its content:
- current Spotify album artwork on the left of the notch
- an **audio-reactive visualizer** on the right — five bars driven by a live
  5-band frequency analysis of Spotify's actual audio (bass in the center).
  Requires running the bundled app and the one-time audio permission below;
  otherwise the bars fall back to a playback-synced animation. The bars settle
  when your Mac is muted or at zero volume — a process tap is taken before the
  output device's volume, so this is deliberate: no motion for something you
  can't hear.
- an **agent light** outboard of the visualizer — the agent signal without
  expanding anything. By default it is one dot carrying the most urgent state
  across your Claude Code sessions: 🔴 an error · 🟠 one is blocked and needs
  you · ⚪️ solid white, one *just finished* and you haven't looked at it yet ·
  🟢 any are working · dim grey, all idle. Only blocked pulses; nothing else
  moves. The white dot goes out on the same click that clears the row's white
  light in the panel, so the two never disagree. Switch it to
  one dot per session (up to three), or off, in Settings ▸ Modules. It draws
  nothing at all when no sessions are running.

When nothing has actually played for a minute — Spotify paused and forgotten, or
not running — the media UI switches off: the cover, the visualizer and the
transport controls and the progress bar disappear, and the pill shrinks back to
exactly the hardware notch — except for the agent light, which stays put, since
that is the signal worth widening a bare notch for. It comes back the moment
something plays again. The panel still opens on hover, with the usage graphs and
agent lights in it.

**Hover to expand** — resting the pointer on the pill briefly (60ms by default,
adjustable in Settings ▸ General) opens the full panel, with a trackpad haptic
tick at the moment it opens; a pointer merely crossing the notch doesn't. Moving the mouse away collapses it. **Clicking anywhere on the open
panel pins it** — including the controls, so using the transport buttons or the
playlist picker keeps it open; only a click outside unpins and collapses it. Honors the system Reduce Motion
setting (fades instead of springs).

The expanded view is a Liquid Glass panel (macOS 26's design language; frosted
material on older macOS), sized to its content, opening below the notch:
- **now playing**: the album cover slides down out of the pill and grows, with
  the track and artist centred above the play / pause button, the previous /
  play / next controls spread across the width beside the cover, and the
  add-to-playlist row directly under them
- **progress bar** — elapsed time, a full-width scrubber and time remaining,
  under the cover and controls. **Drag the knob, or click anywhere on the bar,
  to jump to that point in the song**; the track jumps when you let go. While
  the panel is open Tempo re-checks Spotify's real position once a second, so
  scrubbing in Spotify's own window is reflected here too.
- **add the current song to a Spotify playlist** — the picker lists only
  playlists you can actually add to (your own, plus collaborative ones), or just
  the ones you ticked in Settings; if an add fails, Tempo says why rather than
  just flagging it
- **system usage** — compact CPU and memory sparklines (last 60 s, iStat-style)
- **agent session lights** — one row per open Claude Code session: a colored
  light (🟢 running · 🟠 blocked, needs you · ⚪ finished and not yet seen ·
  dim grey idle · 🔴 error), the session's folder, and a one-line description
  of what it is working on, so two sessions
  in the same repo are told apart at a glance. Read from
  [AgentStatus](https://github.com/Gameslayer999/AgentStatus)'s status files. This is
  Tempo's differentiator over other notch apps. Those files record hook *events*,
  so Tempo cross-checks them against Claude Code's own view of each session
  (read-only, and only what a light needs): a turn you interrupt with Ctrl-C or
  Esc greys its light straight away instead of leaving it green, and a
  background agent's light shows green while it is working and orange while it
  is waiting on an answer from you. A row stays white until you click it —
  going to the session is what marks it as seen — and lights up again the next
  time that session finishes something. Three rows show at once and the
  rest scroll. The description is that session's current prompt, shown in the
  panel only — Tempo never logs it, stores it, or sends it anywhere; switch the
  lights off in Settings ▸ Modules if you would rather it not be on screen.
  **Click a row to go to that session**: a terminal session raises the tab it is running in (Terminal.app
  matched by tty, Ghostty by session title), a VS Code or Cursor session raises
  the window that has its folder open, and a Claude Desktop session brings
  Claude forward. The panel collapses on the way out. Raising a window that is
  on another Space or full-screen relies on the Accessibility permission — grant
  Tempo *System Settings ▸ Privacy & Security ▸ Accessibility* for the fastest,
  most reliable jump; without it editors are still reached through their CLI and
  terminals through app-level focus.
- a **gear in the top-right corner** opens Settings (below).

The expanded panel is rimmed with a soft glass edge so it reads as a distinct
surface over whatever is behind it, and its material is yours to pick — see
Settings ▸ General.

Tempo is built to be extremely light: everything is event-driven or gated (no
music polling; the visualizer and animations fully stop redrawing at rest).
Measured ≈0.3% CPU idle on this machine.

## Settings

The gear in the expanded panel's top-right corner opens a standard macOS
Settings window — sidebar of panes on the left, grouped form on the right, the
same shape as System Settings. Opening it collapses the notch panel. Tempo has
no Dock icon, so the gear is the only way in.

- **General** — *Expanded panel* picks the material the open panel is drawn in:
  **Regular glass** (default), **Clear glass** (near-transparent, with a slight
  scrim so the text stays readable), **Album tint** (frosted glass tinted with
  the current cover's dominant colour) or **Solid** (opaque, no glass). The
  notch updates as you pick. On macOS below 26 there is no Liquid Glass, so the
  three glass options fall back to the nearest system material. Also *Open Tempo
  at login* (works from `dist/Tempo.app` only; a bare `swift build` binary has
  no bundle to register, and the toggle says so), plus a reminder of the hover /
  click / click-outside interaction model and a *Hover delay* slider —
  0–400ms, 60ms by default — setting how long the pointer must rest on the
  notch before the panel opens. The haptic tick fires at that same moment, so a
  shorter delay is also more likely to land while your finger is still on the
  trackpad; a longer one keeps a pointer that is only passing over the notch
  from opening it, and 0 opens the instant the pointer arrives.
- **Music** — a searchable list of your playlists: tick the ones you add songs
  to most and only those appear in the notch picker (tick none and all are
  offered). Plus connection status, Connect / Disconnect, and a guided three-step
  setup: a button that opens the Spotify Developer Dashboard, a copy button for
  the exact Redirect URI, and the Client ID field. See below for why that setup
  exists at all.
- **Modules** — show or hide the audio visualizer, the CPU/memory graphs, and
  the agent session lights. Switching the graphs off stops their sampling timer
  entirely. Separately, **Agent light** picks what the *collapsed* pill shows:
  a summary dot (the default), one dot per session, or nothing.
- **About** — version.

Standard editing shortcuts (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z) work in the Settings window, and
⌘Q there quits Tempo.

## Requirements

- macOS on a notched MacBook (works on notchless displays with a fallback strip)
  - With an external monitor attached, the panel stays on the built-in notch. Close
    the lid and it moves to the menu-bar display as the fallback strip, and back to
    the notch when you open it — plugging, unplugging, and rearranging displays are
    all followed automatically, no restart.
- Swift toolchain (Command Line Tools are enough — the project builds with SwiftPM,
  no Xcode project)
- **Spotify desktop app** for now-playing and transport controls
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
- **Automation → Spotify** — now-playing info, the transport buttons, and
  reading/setting the playback position for the progress bar.
- **System Audio Recording** — the audio-reactive visualizer. Tempo taps only
  Spotify's audio, computes five band levels, and discards the samples; nothing
  is recorded or stored. Decline it and the visualizer simply falls back to a
  playback-synced animation.

macOS only grants the audio permission to a signed `.app` bundle, so the bundled
launch above is the primary run path. `swift build -c release &&
.build/release/tempo` still works for development, but the bare binary always
gets the fallback visualizer (the OS silently delivers it zeroed audio). Note:
the bundle is ad-hoc signed unless an Apple Development identity is in your
keychain, and macOS may re-ask for the permissions after a rebuild.

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

- Tempo is **read-only** on `~/.claude/status/` — it never writes to, modifies, or
  installs anything into your Claude Code setup.
- The audio tap is scoped to Spotify's process; samples are reduced to five
  band levels on the fly and never written anywhere.
- No analytics, no network calls except Spotify's artwork CDN and (if configured)
  the Spotify Web API.

## Project docs

- `CLAUDE.md` — onboarding guide + agent guidelines (read first)
- `DECISIONS.md` — every architecture decision, with rationale
- `NEXT_STEPS.md` — living build queue

## License

MIT

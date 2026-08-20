# Tempo

A dynamic notch for macOS — in the spirit of boringNotch and NotchNook — that turns
the MacBook notch into a glanceable surface for **music** and **live AI-agent
session status**.

> **Status: pre-alpha.** The v1 feature set plus the 2026-08-20 core rework
> (real audio visualizer, usage graph, Dynamic-Island pill, click-reliability fix)
> builds clean and is awaiting live user verification. See `NEXT_STEPS.md`.

## What it does (v1)

**Collapsed (default)** — a Dynamic-Island-style black pill hugging the notch, no
wider than its content:
- current Spotify album artwork on the left of the notch
- an **audio-reactive visualizer** on the right — five bars driven by a live
  5-band frequency analysis of Spotify's actual audio (bass in the center).
  Requires running the bundled app and the one-time audio permission below;
  otherwise the bars fall back to a playback-synced animation.

**Hover to expand** — resting the pointer on the pill for a quarter second opens
the full panel (with a trackpad haptic tick); a pointer merely crossing the notch
doesn't. Moving the mouse away collapses it. **Click the open panel to pin it**;
click anywhere outside to unpin and collapse. Honors the system Reduce Motion
setting (fades instead of springs).

The expanded view is a Liquid Glass panel (macOS 26's design language; frosted
material on older macOS), sized to its content, opening below the notch:
- music controls: play / pause / previous / next
- **add the current song to a Spotify playlist**
- **system usage** — compact CPU and memory sparklines (last 60 s, iStat-style)
- **agent session lights** — one colored light per open Claude Code session
  (🟢 running · 🟠 blocked, needs you · ⚪ idle · 🔴 error), read from
  [AgentStatus](https://github.com/Gameslayer999/AgentStatus)'s status files. This is
  Tempo's differentiator over other notch apps.

Tempo is built to be extremely light: everything is event-driven or gated (no
music polling; the visualizer and animations fully stop redrawing at rest).
Measured ≈0.3% CPU idle on this machine.

## Requirements

- macOS on a notched MacBook (works on notchless displays with a fallback strip)
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

Two one-time permission prompts, both required for full function:
- **Automation → Spotify** — now-playing info and the transport buttons.
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

Play/pause/skip and artwork need **no** account setup. Adding songs to playlists
uses the Spotify Web API and needs a free Spotify Developer app:

1. Go to <https://developer.spotify.com/dashboard> and create an app.
2. Add `http://127.0.0.1:8888/callback` as a Redirect URI.
3. Put the app's **Client ID** in `~/Library/Application Support/Tempo/config.json`:
   ```json
   {"spotify_client_id": "YOUR_CLIENT_ID"}
   ```
4. In Tempo's expanded view, click **Connect Spotify** and approve in the browser.

Tokens are stored locally in `~/Library/Application Support/Tempo/` with owner-only
permissions and never leave your machine except to Spotify's API. Until configured,
the add-to-playlist feature simply hides itself.

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

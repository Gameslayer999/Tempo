# Tempo

A dynamic notch for macOS — in the spirit of boringNotch and NotchNook — that turns
the MacBook notch into a glanceable surface for **music** and **live AI-agent
session status**.

> **Status: pre-alpha.** Architecture decided, scaffold in progress. See
> `NEXT_STEPS.md` for the live build queue.

## What it does (v1)

**Collapsed (default)** — a slim strip flush with the notch:
- current Spotify album artwork on the left of the notch
- a Dynamic-Island-style audio visualizer on the right (animates while music plays)

**Click to expand** — the panel opens below the notch:
- music controls: play / pause / previous / next
- **add the current song to a Spotify playlist**
- **agent session lights** — one colored light per open Claude Code session
  (🟢 running · 🟠 blocked, needs you · ⚪ idle · 🔴 error), read from
  [AgentStatus](https://github.com/Gameslayer999/AgentStatus)'s status files. This is
  Tempo's differentiator over other notch apps.

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
swift build -c release
.build/release/tempo
```

On first Spotify control, macOS will ask to allow Tempo to automate Spotify
(Automation permission) — approve it once.

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
- No analytics, no network calls except Spotify's artwork CDN and (if configured)
  the Spotify Web API.

## Project docs

- `CLAUDE.md` — onboarding guide + agent guidelines (read first)
- `DECISIONS.md` — every architecture decision, with rationale
- `NEXT_STEPS.md` — living build queue

## License

MIT

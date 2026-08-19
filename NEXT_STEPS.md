# NEXT_STEPS.md — Living Build Queue

> Read this at the start of every session to pick up where the last one left off.
> Update it at the end of every session where anything changed (Agent Guideline #10).

---

## Current state

- **Docs bootstrapped, repo created (2026-08-19).** CLAUDE.md / DECISIONS.md /
  NEXT_STEPS.md / README.md carried over from AgentStatus and adapted to Tempo.
  Architecture decided (decisions 001–007): SwiftUI/AppKit via SwiftPM, AppleScript
  to Spotify for now-playing + transport, Spotify Web API (PKCE) for add-to-playlist,
  playback-synced visualizer, read-only AgentStatus status-file consumption,
  non-activating NSPanel at the notch. No app code yet.

## Now

- [ ] **Scaffold the app** — SwiftPM executable target; Accessory-policy app;
      non-activating NSPanel positioned at the notch (real geometry from `NSScreen`
      auxiliary areas, fallback for notchless displays); SwiftUI hosting; click
      toggles collapsed ↔ expanded with animation; click-outside collapses.
- [ ] **Spotify now-playing + transport** — AppleScript service (guarded by
      "Spotify running"), poll track/artist/state/artwork-url; artwork download;
      play/pause/prev/next; collapsed strip shows artwork left of the notch.
- [ ] **Visualizer** — Dynamic-Island-style animated bars right of the notch;
      animate while playing, settle when paused.
- [ ] **Add-to-playlist** — PKCE OAuth (user-supplied Client ID, loopback redirect),
      token store in `~/Library/Application Support/Tempo/` (0600), playlist list +
      add-current-track in the expanded view; feature hides when unconfigured.
- [ ] **AgentStatus lights** — read `~/.claude/status/sessions/*.json`, render
      state-colored lights in the expanded view; stale sessions dimmed/dropped;
      feature hides when the directory is absent.
- [ ] **Verify end-to-end on this machine** — `swift build` clean; panel hugs the
      real notch; Spotify controls work against the real app; lights match live
      Claude Code sessions.

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

- None currently open. (Spotify-only scope, visualizer approach, PKCE flow, and repo
  visibility were all decided by the user on 2026-08-19 — see decisions 003/004/007.)

## Recently completed

- **2026-08-19** — Project bootstrapped: docs carried over from AgentStatus and
  adapted, architecture decisions 001–007 logged, pushed to the private repo
  `Gameslayer999/Tempo`.

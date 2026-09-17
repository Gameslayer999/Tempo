# CLAUDE.md — Tempo Onboarding Guide

> Read this file completely before taking any action on this project.
> This file is the single source of truth for any new agent continuing development.

---

## Project Overview

**Tempo** is a dynamic notch / menu-bar replacement for macOS in the spirit of
boringNotch and NotchNook: a borderless, always-on-top panel that hugs the MacBook
notch and turns it into a useful surface. What differentiates Tempo from the
competition is that it also surfaces **live AI-agent session status** (the
AgentStatus lights) in the notch.

**v1 feature set:**

1. **Music (Spotify)** — album artwork in the collapsed notch; play / pause /
   previous / next controls in the expanded view; and **add the current song to a
   Spotify playlist** via the Spotify Web API (OAuth PKCE, user-supplied Client ID).
   Now-playing state and transport control are read/driven via AppleScript to the
   Spotify desktop app.
2. **Audio visualizer** — an iPhone-Dynamic-Island-style set of animated bars beside
   the notch. v1 is **playback-synced animation** (bars animate while music plays,
   freeze when paused) — not a real audio tap.
3. **AgentStatus integration** — Tempo renders one colored light per open Claude Code
   session by **reading the status files AgentStatus's hooks already write**
   (`~/.claude/status/sessions/<session_id>.json`). Tempo installs **no hooks of its
   own** in v1; it is a second display layer over the same signal layer.

**Interaction model (matches the category conventions):**
- **Collapsed (default)** — a slim strip flush with the notch: album artwork on the
  left of the notch, the audio visualizer on the right. Nothing else.
- **Click to expand** — the panel grows below/around the notch into the full view:
  music controls, add-to-playlist, and the agent session lights.

**Status-file schema Tempo consumes** (written by AgentStatus, one file per session):

```json
{"state":"running|blocked|idle|error","cwd":"…","ide":"cli|vscode|cursor|…",
 "pid":12345,"label":"folder","updated_at":1787164074,"task":"…","detail":"…"}
```

- 🟢 **green** — running · 🟠 **orange** — blocked (needs the user) · ⚪ **gray** —
  idle · 🔴 **red** — error. Sibling `<id>.subagents/` directories hold one marker
  file per live subagent.

**Key properties:**
- **Glanceable** — album art, a moving visualizer, and agent lights readable at a
  glance without expanding.
- **Non-intrusive** — a slim always-on-top panel that stays out of the way; expanded
  view opens on click and collapses when dismissed.
- **Self-contained & scriptable** — builds with `scripts/build.sh` (SwiftPM, no Xcode
  project); no manual setup steps beyond the documented one-time Spotify Developer
  Client ID.

> **Status:** See `NEXT_STEPS.md` for the current build queue and `DECISIONS.md`
> for the rationale behind the stack.

---

## ⚠ Agent Guidelines — Read First

These rules apply to every agent working on this project:

**0. Always build toward the final product.** Keep the end goal — the glanceable
notch surface with music controls, visualizer, and live agent lights in the Project
Overview — in mind at all times. Before starting any task, be able to state how it
moves the project toward that final product. If you don't understand how the current
piece factors into the end result — why it exists, which layer it serves, what depends
on it — **stop and figure out why before writing code.** Ask the user if the
connection is still unclear. Never build something just because it was requested or
because it seems locally reasonable; a task that doesn't advance the final product, or
that you can't tie back to it, is a signal to pause and reassess, not to proceed.

1. **Get approval before large architecture changes.** If a decision affects file
   structure, the notch-window mechanics, how music state is read or controlled, the
   Spotify OAuth flow, or how Tempo consumes the AgentStatus status files — stop and
   explain the options to the user before writing any code.

2. **Flag better alternatives.** If you see a simpler, cheaper, or more robust way to
   accomplish something than what's currently planned, say so. Don't just silently
   implement what was previously decided if there's a meaningfully better path.

3. **Never break or interfere with the user's other tools.** Tempo reads state owned
   by other software and overlays every app on screen:
   - **Read-only on AgentStatus's data.** Tempo must never write to, delete, or lock
     `~/.claude/status/**` or the user's Claude Code config. That signal layer belongs
     to AgentStatus.
   - **Never fight the user for input.** The notch panel must be non-activating
     (never steal focus), must not swallow clicks outside its own bounds, and must
     never block the menu bar or other apps.
   - **Fail silent, degrade gracefully.** Spotify not running, no Spotify Client ID
     configured, no status directory — each simply hides that feature; none may
     crash, spam dialogs, or log noise.

4. **Verify external behavior against the installed version, don't assume it.**
   Spotify's AppleScript dictionary, the Spotify Web API, and the AgentStatus status
   schema are all version-dependent. Before building logic on top of a field, command,
   or endpoint, confirm it actually behaves as expected on this machine (run the real
   AppleScript, read a real status file). Treat doc-sourced behavior as unverified
   until observed.

5. **Minimize what you read and store from sessions.** Session `cwd` paths and the
   `task`/`detail` prompt excerpts in status files can be sensitive. Render only what
   the lights need; never copy status-file contents anywhere else (disk, network,
   logs). The Spotify OAuth token is the user's credential — store it only in Tempo's
   own Application Support directory with owner-only permissions, and never log it.

6. **Test incrementally.** Don't write hundreds of lines of new code and ask the user
   to test it all at once. Build in small, verifiable steps (window shell → collapsed
   strip → now-playing polling → controls → expanded view → lights).

7. **Preserve existing behaviour.** When changing code, keep its observable behaviour
   the same unless the user explicitly asks you to change it. Bug fixes, refactors,
   and performance work should fix the defect without altering inputs, outputs, side
   effects, or interfaces that callers rely on. If you believe a behaviour change is
   warranted, stop and propose it first — don't fold it silently into an unrelated
   change.

8. **Everything must be replicable — no one-off manual steps.** If a task required
   human intervention once (a build flag, a codesign step, creating a config
   directory), capture it in a single re-runnable script before considering the task
   done. Doing it a second time should mean running one script, not repeating the
   manual steps. Scripts must be idempotent and safe to re-run in any system state.
   Manual intervention is a bug to be scripted away, not a workflow. (The sole
   documented exception: creating the Spotify Developer app, which only the user can
   do — document it precisely in the README instead.)

9. **Record every decision in `DECISIONS.md`.** Any significant choice —
   architecture, tooling, the notch-window mechanics, the music-control approach, the
   OAuth flow, or a reversal of a prior decision — must be appended to `DECISIONS.md`
   with its context, the options considered, the choice, and the reasoning. Update the
   Decision Index there too. Code captures *what* the system does; `DECISIONS.md`
   captures *why*. If you make a decision and don't log it, the task isn't finished.

10. **Keep `NEXT_STEPS.md` current.** At the end of every session where you add,
    change, or remove functionality, update `NEXT_STEPS.md`:
    - Move finished work to **Recently completed** (with date).
    - Add newly discovered work to **Now**, **Next**, or **Later**.
    - Refresh **Current state** if something material changed.
    - Record unresolved choices in **Decisions needed** (then log the decision in
      `DECISIONS.md` once the user chooses).
    Read `NEXT_STEPS.md` at the start of each session to pick up where the last agent
    left off. If the task isn't finished, the next-steps update isn't finished either.

11. **Be precise, descriptive, and concise.** Say exactly what happened — no vague
    summaries, no hand-waving. This applies to everything: user-facing messages, logs,
    commit messages, code comments, and status updates. Prefer the specific fact over
    a general impression; cut filler that doesn't help someone act on the information.
    When something fails — in the app, an AppleScript call, or the OAuth flow — report
    the exact error (message, code, or observable symptom), what triggered it, and the
    root cause once you know it. Do not say "something went wrong" when you can state
    what actually failed and why.

12. **Keep local/user data out of git.** OAuth tokens, the user's Spotify Client ID,
    any logs, and session status data are local runtime state, not source.
    `.gitignore` must cover config, tokens, logs, and build artifacts, and none of it
    should ever be staged. Before any commit, verify with `git status` that no runtime
    state, credentials, session data, or user paths appear.

13. **Keep `README.md` current with the tool.** The README is the user-facing
    description of what Tempo does and how to run it — it must always reflect the
    tool's actual current state, never a past or planned one. Any change that adds,
    removes, or alters a user-visible feature, setting, install step, supported
    player, keyboard/mouse interaction, or the setup details **must update the README
    in the same change** — document a new feature, drop a removed one, fix a step that
    no longer matches. A feature the code has but the README doesn't mention is an
    incomplete task, the same as a missing `DECISIONS.md` entry (#9). Internal-only
    work (refactors, bug fixes, build-warning cleanup) with no user-visible change
    needs no README edit.

---

## UI Design Principles

These rules apply to the Tempo display — the collapsed notch strip and the expanded
panel.

1. **Glanceable in under a second.** The collapsed strip carries exactly three
   signals: what's playing (artwork), that it's playing (visualizer motion), and —
   when shown — which agent sessions need attention (lights). Don't add chrome,
   labels, or animation that competes with those signals.

2. **Attention states must be obvious.** Orange (blocked) and red (error) agent
   lights are the states a user acts on. They must stand out clearly from green/gray —
   via color and, where it helps, motion — so a session waiting on the user is never
   missed.

3. **The notch is a surface, not a menu.** One click expands; interacting with the
   expanded view is direct (a play button plays, a playlist row adds the song). No
   nested menus, no detours. Clicking outside — or the same toggle — collapses it.

4. **Never show a stale or lying signal.** Artwork and play state must reflect
   Spotify's real current state (poll or event-driven, but bounded staleness). Agent
   lights must reflect the session's real state; a dead session's light dims or
   disappears. A wrong signal is worse than no signal.

5. **Motion is meaning.** The visualizer moves only while audio is playing; it
   freezes or settles when paused. Expansion/collapse animates smoothly (this category
   lives or dies on animation quality), but animation never delays the user's action.

6. **Respect the hardware.** The strip aligns to the physical notch (real notch
   geometry from `NSScreen`, with a sane fallback on notchless displays). It never
   overlaps the menu bar's text or another app's controls.

---

## AI Coding Guidelines (Karpathy)

Follow these principles on every coding task. They complement the Agent Guidelines
above and take precedence over default model instincts toward over-building.

### 1. Think Before Coding

- **Never assume blindly.** If a requirement has multiple interpretations, ask for
  clarification instead of silently guessing.
- **Surface confusion.** State assumptions explicitly and name what is unclear before
  writing a single line of code.
- **Push back.** If a request is technically overcomplicated or redundant, suggest a
  simpler approach before implementing it.

### 2. Simplicity First

- **Write minimum code.** Do not add unrequested features, speculative
  "future-proofing," or single-use abstractions.
- **Ruthless compression.** If 50 lines solve the problem, 200 lines are unacceptable.
- **Avoid over-configurability.** Do not add configurations or flexibilities unless
  they were explicitly requested.

### 3. Surgical Changes

- **Touch only what is necessary.** Modify strictly the lines mandatory for the
  current task.
- **No drive-by refactoring.** Do not improve adjacent formatting, comments, or
  refactor existing code that is not broken.
- **Clean up only your own mess.** Remove unused variables or imports that your own
  changes introduced; leave pre-existing dead code untouched.

### 4. Goal-Driven Execution

- **Use verifiable success criteria.** Turn vague instructions like "fix the bug"
  into declarative goals: e.g. write a test that reproduces the bug, then make it
  pass.
- **Tighten the leash.** Work from a clear objective, boundaries, and metric — then
  loop until met. Weak criteria ("make it work") inevitably require human
  intervention.

---

## Agent Decision Framework

When you encounter a choice during development, follow this process:

1. **Is it a small implementation detail?** (variable name, minor refactor, spacing,
   log formatting)
   → Decide and implement. No approval needed.

2. **Does it affect the notch-window mechanics, the music-control approach, the OAuth
   flow, how status files are consumed, or the project's build/packaging?**
   → Stop. Present a table of options with pros/cons and your recommendation.
   → Wait for explicit user approval before writing code.

3. **Is there an easier way than what's planned?**
   → Say so before implementing the planned approach. Example:
   *"The plan calls for X, but Y would achieve the same result with less code and no
   additional dependencies. My recommendation is Y — want me to proceed that way?"*

4. **Would the action touch data owned by another tool or require a macOS
   permission?** (reading `~/.claude/status`, AppleScript automation of Spotify, a
   new TCC prompt)
   → Respect Agent Guideline #3: read-only on others' data, fail-silent, never steal
   focus. Test against the real thing on this machine before shipping it as default
   behavior.

---

## Quick Start Checklist for a New Agent

- [ ] Read this entire file
- [ ] Read `NEXT_STEPS.md` — current build queue and blockers
- [ ] Read `DECISIONS.md` for architecture rationale
- [ ] Confirm the current state of the project with the user
- [ ] Ask the user what specific task they want to work on today
- [ ] Never ship a change that writes to `~/.claude/status/**`, steals focus, or
      blocks other apps (Agent Guideline #3)
- [ ] Verify AppleScript/Web-API/status-schema behavior against the real installed
      versions before relying on it (Agent Guideline #4)
- [ ] Never stage or commit tokens, credentials, session data, or user paths —
      confirm `.gitignore` covers new data paths (Agent Guideline #12)
- [ ] Before ending the session: update `NEXT_STEPS.md` if anything changed
      (Agent Guideline #10)

import Foundation

/// Click a light, land in that session (decision 035).
///
/// Ported from AgentStatus's `focus_session`, macOS paths only. The routing is
/// the same shape: the `ide` field says what kind of host the session lives in,
/// and each host has exactly one way to be reached.
///
/// | `ide` | Where the click goes |
/// |---|---|
/// | `cli` | the terminal tab running it — Terminal.app matched by tty, Ghostty by session title; otherwise the emulator instance that owns the session |
/// | `vscode` (and unknown hosts) | the VS Code window that has the workspace open (AX raise, then the `code` CLI for the cross-Space case) |
/// | `cursor` | Cursor's window for the workspace, then Cursor itself |
/// | `claude-desktop` | Claude Desktop (it exposes no per-conversation scripting) |
///
/// Two things AgentStatus does here are deliberately **not** ported:
///
/// - **The VS Code focus relay.** AgentStatus focuses the exact session *tab*
///   by dropping `~/.claude/status/focus-request.json` for its VS Code
///   extension to pick up. Tempo may not write anywhere under
///   `~/.claude/status/**` (Agent Guideline #3), so a VS Code session is
///   focused to the window, not the tab.
/// - **Opening a background agent.** AgentStatus runs `claude attach` in a new
///   terminal for a detached agent. Tempo only *focuses* an already-attached
///   Ghostty surface; it never launches a terminal or a session of its own.
///
/// Everything here is best-effort and silent: a missing binary, a denied
/// Accessibility grant, or a window that no longer exists ends the click with
/// nothing happening rather than an error (Agent Guideline #3).
enum SessionFocusService {
    /// Focus the host of `session`. Returns immediately — every step below
    /// shells out (`ps`, `osascript`, the VS Code CLI) and costs 0.2–1.1s, which
    /// on the main actor would freeze the panel mid-collapse.
    ///
    /// `sessions` is every session the panel is showing. A CLI session Claude
    /// has not titled yet is found by elimination against the *other* sessions'
    /// titles (decision 085), which needs to know who they are.
    static func focus(_ session: AgentSession, among sessions: [AgentSession]) {
        let (ide, cwd, pid, id) = (session.ide, session.cwd, session.pid, session.id)
        let siblings = sessions.map(\.id).filter { $0 != id }
        Task.detached(priority: .userInitiated) {
            route(ide: ide, cwd: cwd, pid: pid, sessionID: id, siblings: siblings)
        }
    }

    private static func route(ide: String, cwd: String, pid: Int, sessionID: String, siblings: [String]) {
        switch ide {
        case "cli":
            focusCLISession(pid: pid, sessionID: sessionID, cwd: cwd, siblings: siblings)
        case "claude-desktop":
            // Claude Desktop scripts no conversation selection, so this is
            // app-level focus by necessity.
            launch("/usr/bin/open", ["-a", "Claude"])
        case "cursor":
            // Never the Cursor CLI: with the agent window active `cursor <folder>`
            // is intercepted and opens a *new* agent instead of focusing anything
            // (AgentStatus decision 047). Raise + activate only.
            if !cwd.isEmpty {
                raiseWindow(titled: folderName(workspaceRoot(cwd)), inProcess: "Cursor")
            }
            launch("/usr/bin/open", ["-a", "Cursor"])
        default:
            focusVSCodeWindow(cwd: cwd)
        }
    }

    // MARK: Terminal sessions

    /// A CLI session owns no window; it is reached through the terminal running
    /// it. A session with no controlling terminal is a detached background
    /// agent — the one case where there may be nothing on screen to go to.
    private static func focusCLISession(pid: Int, sessionID: String, cwd: String, siblings: [String]) {
        guard pid > 0 else { return }

        guard let tty = tty(of: pid) else {
            // Background agent: focus the Ghostty surface it is already attached
            // in, if one exists. Nothing is opened if it isn't — and nothing is
            // guessed either, so the directory match below is deliberately not
            // run here: a detached agent has no surface of its own to land in.
            _ = focusGhosttySurface(sessionID: sessionID, requireUnique: false)
            return
        }
        guard let terminal = terminalApp(of: pid) else { return }

        if terminal.name == "Terminal", focusTerminalTab(tty: tty) { return }
        if terminal.name == "Ghostty" {
            if focusGhosttySurface(sessionID: sessionID, requireUnique: true) { return }
            // Untitled or ambiguous: find the surface by its working directory
            // rather than fronting the app and landing on the wrong session
            // (decision 085).
            if focusGhosttySurfaceByDirectory(cwd: cwd, siblings: siblings) { return }
        }

        // Another emulator, or a tab we could not match: land in the right app —
        // and in the right *instance* of it, which `open -a <name>` cannot
        // express and which matters whenever two Ghostty/Terminal processes run.
        if activateProcess(pid: terminal.pid) { return }
        launch("/usr/bin/open", ["-a", terminal.name])
    }

    /// Terminal.app publishes a `tty` per tab, so the exact tab running the
    /// session can be selected and raised.
    private static func focusTerminalTab(tty: String) -> Bool {
        let script = """
        on run argv
          set target to item 1 of argv
          tell application "Terminal"
            repeat with w in windows
              repeat with t in tabs of w
                if (tty of t) is target then
                  set selected of t to true
                  set frontmost of w to true
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end tell
          return "no"
        end run
        """
        return osascript(script, [tty]) == "ok"
    }

    /// Ghostty publishes no tty and no pid, so its surfaces are matched by
    /// title: Claude Code writes the session title into the terminal's title
    /// bar, and Ghostty 1.3's dictionary exposes both `name` and `focus`
    /// (AgentStatus decision 055/066).
    ///
    /// Two grades of match. A surface whose title *ends with* the session title
    /// is showing that session — the leading glyph is Claude's activity spinner
    /// — and several such surfaces are several views of one session, so the
    /// first is right by construction. A surface that merely *contains* it may
    /// be showing something else, so that grade must be unambiguous to act on
    /// (`requireUnique`).
    private static func focusGhosttySurface(sessionID: String, requireUnique: Bool) -> Bool {
        guard let title = claudeSessionTitle(sessionID: sessionID) else { return false }
        let script = """
        on run argv
          set target to item 1 of argv
          set uniqueOnly to (item 2 of argv) is "1"
          tell application "Ghostty"
            set strong to {}
            set weak to {}
            repeat with t in terminals
              set n to (name of t)
              if n ends with target then
                set end of strong to t
              else if n contains target then
                set end of weak to t
              end if
            end repeat
            if (count of strong) > 0 then
              focus (item 1 of strong)
              return "ok"
            end if
            if (count of weak) is 0 then return "no"
            if uniqueOnly and (count of weak) > 1 then return "no"
            focus (item 1 of weak)
            return "ok"
          end tell
        end run
        """
        return osascript(script, [title, requireUnique ? "1" : "0"]) == "ok"
    }

    /// The second grade of Ghostty match, for the sessions a title cannot
    /// reach: one Claude Code has not titled yet — `ai-title` arrives only
    /// after the first turn, so a session is untitled for exactly as long as it
    /// is new — or one whose title matched nothing unambiguously. Both used to
    /// fall straight through to fronting the Ghostty *app*, which lands on
    /// whichever window was last used; with each window on its own Space that
    /// is a jump to a different session on a different Space, which is what the
    /// wrong-session bug looked like (decision 085).
    ///
    /// Ghostty publishes a `working directory` per surface — OSC 7, so it is
    /// the shell's real cwd — and the session's status file carries the same
    /// path, which narrows the surfaces to the ones sitting in this session's
    /// folder. Any of those already claimed by *another* live session's title
    /// is struck out: a surface showing a different session is not this one.
    /// Only a single survivor is acted on, keeping the rule the title match
    /// uses — a wrong tab is worse than no tab (UI Principle #4).
    ///
    /// A Ghostty running exactly one surface is that surface by construction:
    /// the caller has already walked this session's process tree to this
    /// Ghostty instance.
    ///
    /// Paths are compared with AppleScript's default text comparison, which
    /// ignores case — OSC 7 reports the cwd as the shell spells it, and on a
    /// case-insensitive volume that need not match the status file's casing
    /// (observed here: `…/documents/code/tempo` against `…/Documents/code/Tempo`).
    private static func focusGhosttySurfaceByDirectory(cwd: String, siblings: [String]) -> Bool {
        guard !cwd.isEmpty else { return false }
        let claimed = siblings.compactMap { claudeSessionTitle(sessionID: $0) }
        let script = """
        on run argv
          set wantDir to item 1 of argv
          set claimedTitles to {}
          if (count of argv) > 1 then set claimedTitles to items 2 thru -1 of argv
          tell application "Ghostty"
            set surfaces to terminals
            if (count of surfaces) is 1 then
              focus (item 1 of surfaces)
              return "ok"
            end if
            set hits to {}
            repeat with t in surfaces
              set n to (name of t)
              set taken to false
              repeat with c in claimedTitles
                if n ends with (contents of c) then set taken to true
              end repeat
              if not taken then
                set d to ""
                try
                  set d to (working directory of t)
                end try
                if my sameFolder(d, wantDir) then set end of hits to t
              end if
            end repeat
            if (count of hits) is 1 then
              focus (item 1 of hits)
              return "ok"
            end if
          end tell
          return "no"
        end run

        on sameFolder(a, b)
          if a is "" or b is "" then return false
          if (count of a) > 1 and a ends with "/" then set a to text 1 thru -2 of a
          if (count of b) > 1 and b ends with "/" then set b to text 1 thru -2 of b
          return a is b
        end sameFolder
        """
        return osascript(script, [cwd] + claimed) == "ok"
    }

    /// Claude Code's own title for a session, from the `ai-title` records in its
    /// transcript — the last one written is the current title. The only handle
    /// that tells two Ghostty surfaces apart.
    ///
    /// A deliberate, narrow exception to Agent Guideline #5: the transcript is
    /// opened only on a click, only the title string is taken out of it, nothing
    /// is stored or logged, and that string is already on screen in the tab it
    /// names. Absent until Claude has titled the session and version-dependent,
    /// so every caller degrades when it is missing (Agent Guideline #4).
    private static func claudeSessionTitle(sessionID: String) -> String? {
        // The id becomes a path component: accept only the uuid alphabet.
        guard !sessionID.isEmpty,
              sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }

        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let fm = FileManager.default
        // One directory per project folder; the transcript is under whichever
        // one the session belongs to, named by session id.
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return nil
        }
        let file = "\(sessionID).jsonl"
        guard let path = dirs.map({ $0.appendingPathComponent(file) }).first(where: { fm.fileExists(atPath: $0.path) }) else {
            return nil
        }
        // The current title is the *last* `ai-title` record, so the transcript is
        // read backwards a line at a time and stops at the first one. Mapped
        // rather than loaded: a long session's transcript runs to tens of MB
        // (22MB for one live session here) while the record that ends this scan
        // sat 19KB from the end. The 16MB cap this replaces skipped those files
        // whole, which left exactly the longest-running sessions unreachable by
        // title (decision 087).
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else { return nil }
        let marker = Data("\"ai-title\"".utf8)
        var end = data.count
        while end > 0 {
            let start = data[..<end].lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
            let line = data[start..<end]
            // Cheap reject first: only the handful of title records are worth parsing.
            if line.range(of: marker) != nil,
               let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               object["type"] as? String == "ai-title",
               let value = object["aiTitle"] as? String, !value.isEmpty {
                return value
            }
            end = start == 0 ? 0 : start - 1
        }
        return nil
    }

    // MARK: Editor sessions

    /// Raise the VS Code window that has the session's workspace open. The AX
    /// raise lands in ~0.2s when that window is on the current Space; the CLI
    /// below always runs too, because AX cannot see full-screen windows on
    /// inactive Spaces (AgentStatus decision 021). With no window open for the
    /// folder, the CLI opens one — a click always arrives somewhere.
    private static func focusVSCodeWindow(cwd: String) {
        guard !cwd.isEmpty else { return }
        let root = workspaceRoot(cwd)
        raiseWindow(titled: folderName(root), inProcess: "Code")

        let cli = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        if FileManager.default.isExecutableFile(atPath: cli) {
            launch(cli, [root])
        } else {
            launch("/usr/bin/open", ["-a", "Visual Studio Code", root])
        }
    }

    /// The workspace folder an IDE actually has open around `cwd`, from Claude
    /// Code's own IDE lock files (`~/.claude/ide/*.lock`). A session that `cd`'d
    /// into a subfolder still belongs to the window holding its root, and it is
    /// the root's basename that appears in the window title. Falls back to `cwd`
    /// when there are no locks, which is the old behaviour rather than a wrong
    /// answer.
    private static func workspaceRoot(_ cwd: String) -> String {
        let ideDir = home.appendingPathComponent(".claude/ide", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: ideDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return cwd }

        var best = ""
        for url in entries where url.pathExtension == "lock" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folders = object["workspaceFolders"] as? [Any]
            else { continue }
            for case let folder as String in folders
            where folder.count > best.count && pathWithin(cwd, folder) {
                best = folder
            }
        }
        return best.isEmpty ? cwd : best
    }

    /// `cwd` is `folder` itself or sits inside it. Compared segment-wise so
    /// `/a/bcd` never counts as inside `/a/bc`.
    private static func pathWithin(_ cwd: String, _ folder: String) -> Bool {
        if cwd == folder { return true }
        guard cwd.hasPrefix(folder) else { return false }
        return cwd.dropFirst(folder.count).hasPrefix("/")
    }

    private static func folderName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Bring the first window of `process` whose title contains `title` to the
    /// front, via System Events (`set frontmost` + AXRaise). Needs the
    /// Accessibility grant and nothing else — no per-app Automation prompt.
    /// Without that grant it silently does nothing, and the caller's fallback
    /// carries the click.
    private static func raiseWindow(titled title: String, inProcess process: String) {
        guard !title.isEmpty else { return }
        let script = """
        on run argv
          set target to item 1 of argv
          set procName to item 2 of argv
          tell application "System Events"
            tell process procName
              set frontmost to true
              set ws to (windows whose title contains target)
              if (count of ws) > 0 then perform action "AXRaise" of item 1 of ws
            end tell
          end tell
          return "ok"
        end run
        """
        _ = osascript(script, [title, process])
    }

    /// Front the exact process, not just the app by name — a terminal emulator
    /// can have several instances running and only one of them owns the session.
    private static func activateProcess(pid: Int) -> Bool {
        let script = """
        on run argv
          tell application "System Events"
            set frontmost of (first process whose unix id is (item 1 of argv as integer)) to true
          end tell
          return "ok"
        end run
        """
        return osascript(script, [String(pid)]) == "ok"
    }

    // MARK: Process helpers

    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// The session's controlling terminal, as the `/dev/ttys00N` key
    /// Terminal.app publishes per tab. Nil when the process has no tty (`??`),
    /// which is every non-CLI host and every detached background agent.
    private static func tty(of pid: Int) -> String? {
        guard let out = capture("/bin/ps", ["-o", "tty=", "-p", String(pid)]), !out.isEmpty, out != "??" else {
            return nil
        }
        return "/dev/\(out)"
    }

    /// Walk up from `pid` to the first ancestor that is an app bundle: the
    /// terminal emulator hosting this session, and which instance of it.
    /// Verified live on this machine: `claude` → `-/bin/zsh` → `/usr/bin/login`
    /// → `/Applications/Ghostty.app/Contents/MacOS/ghostty`.
    private static func terminalApp(of pid: Int) -> (name: String, pid: Int)? {
        var current = pid
        for _ in 0..<12 {
            guard current > 1 else { return nil }
            guard let line = capture("/bin/ps", ["-o", "ppid=,comm=", "-p", String(current)]),
                  let separator = line.firstIndex(where: { $0 == " " || $0 == "\t" })
            else { return nil }

            let command = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if let marker = command.range(of: ".app/Contents/MacOS/") {
                let bundle = String(command[..<marker.lowerBound]) + ".app"
                let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
                return name.isEmpty ? nil : (name, current)
            }
            guard let parent = Int(line[..<separator].trimmingCharacters(in: .whitespaces)) else { return nil }
            current = parent
        }
        return nil
    }

    /// Run `script` with `arguments` as its `argv` and return its trimmed
    /// stdout. Arguments are passed as argv rather than interpolated into the
    /// source, so a folder or title containing a quote cannot change the script.
    private static func osascript(_ script: String, _ arguments: [String]) -> String? {
        capture("/usr/bin/osascript", ["-e", script] + arguments)
    }

    /// Run a process to completion and return its trimmed stdout, or nil if it
    /// could not be started. stderr is discarded — every caller treats failure
    /// as "this route didn't work", and Tempo logs nothing about sessions
    /// (Agent Guideline #5).
    private static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drained before waiting: a script that outdid the pipe buffer would
        // otherwise block forever on write while we block on exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Start a process and don't wait for it — the IDE CLI takes ~1s to boot a
    /// Node runtime and its exit status tells us nothing we act on.
    private static func launch(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
    }
}

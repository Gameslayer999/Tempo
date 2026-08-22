import Foundation

/// stderr diagnostics, silent unless `TEMPO_DEBUG_VIZ=1` is in the
/// environment. Temporary scaffolding for one investigation: the visualizer
/// showing motion with Spotify paused. A normal run writes nothing (Agent
/// Guideline #3 — no log noise), and no audio sample or session content is
/// ever written here.
let tempoDebugEnabled = ProcessInfo.processInfo.environment["TEMPO_DEBUG_VIZ"] == "1"

@inline(__always)
func tempoDebug(_ message: @autoclosure () -> String) {
    guard tempoDebugEnabled else { return }
    guard let data = ("[tempo] " + message() + "\n").data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}

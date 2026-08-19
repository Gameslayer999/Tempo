import AppKit

// Top-level `main.swift` code runs synchronously on the main thread at
// process start, but the compiler can't infer that statically; assumeIsolated
// asserts it so we can call the @MainActor AppDelegate/NSApplication APIs
// without making this file async.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    NSApp.setActivationPolicy(.accessory)
    app.run()
}

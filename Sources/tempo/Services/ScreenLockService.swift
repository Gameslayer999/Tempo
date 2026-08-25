import AppKit
import Combine
import Foundation

/// Whether the screen is locked right now (decision 058).
///
/// This is the half of decision 036 that actually worked. That decision tried
/// to *draw* the notch on the lock screen and proved it impossible — macOS
/// composites the lock screen in a secure context that excludes user-session
/// windows at every level — and reverted everything, including this. But the
/// lock *detection* was verified correct on both edges at the time
/// (`loginwindow`'s distributed notifications fired reliably across real
/// lock/unlock cycles), and the sanctioned lock-screen surface — a
/// notification — needs exactly this signal and nothing else. So it comes
/// back, without the window-level machinery that did not work.
///
/// Two sources, because neither alone is sufficient:
/// - `com.apple.screenIsLocked` / `screenIsUnlocked`, posted by `loginwindow`
///   on the *distributed* notification centre. These are the live edges.
/// - `CGSessionCopyCurrentDictionary()`, polled once at start and again on
///   wake and session activation. This is the reconciliation: a notification
///   missed while the process was starting, asleep, or in a switched-away
///   session would otherwise leave the state stuck at the wrong value
///   (UI Principle #4 — never show a stale signal).
@MainActor
final class ScreenLockService: ObservableObject {
    @Published private(set) var isLocked = false

    private var observers: [NSObjectProtocol] = []
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(locked: true) }
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(locked: false) }
        })

        // Reconcile after anything that can swallow an edge. Wake is the
        // important one: the machine can be locked, slept, and woken, and the
        // lock notification for that sequence is not guaranteed to arrive in
        // an order this process sees.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            })
        }

        reconcile()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
        }
        observers.removeAll()
        isLocked = false
    }

    private func set(locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
    }

    /// Ask the window server directly what the session's lock state is.
    private func reconcile() {
        set(locked: Self.sessionIsLocked())
    }

    /// `CGSSessionScreenIsLocked` is absent from the dictionary entirely when
    /// the screen is unlocked, so a missing key reads as false rather than as
    /// an error.
    static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    deinit {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
        }
    }
}

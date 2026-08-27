import AppKit
import Combine
import Foundation
import UserNotifications

/// The two lock-screen cards: weather, and what's playing (decision 058).
///
/// Decision 036 established that Tempo cannot draw anything on the lock
/// screen — macOS composites it in a secure context that excludes
/// user-session windows, at every window level — and named the one surface
/// that is available: a system notification. This is that surface.
///
/// Shape of the feature:
/// - The screen locks → post up to two notifications, one per card.
/// - Something changes while locked (a track, a refreshed reading) → post the
///   *same identifier* again, which replaces the delivered card in place
///   rather than stacking a second one.
/// - The screen unlocks → withdraw both, so Notification Center is not left
///   holding a card about a moment that has passed (UI Principle #4).
///
/// Two settings outside Tempo's control decide whether the cards are actually
/// legible when locked, and the Settings pane says so: System Settings ▸
/// Notifications ▸ Tempo needs **Show on Lock Screen** on, and **Show
/// previews** set to *Always* — the default, "when unlocked", renders a
/// locked card as a contentless "Tempo · Notification".
@MainActor
final class LockScreenNotifier: ObservableObject {
    /// Live notification authorization, for Settings and the hello screen.
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Set when macOS will not let this build register for notifications at
    /// all — as opposed to the user having switched them off (decision 081).
    ///
    /// Two observed failure modes, both traced to the signing identity:
    ///
    /// - **Ad-hoc signed** (`codesign` reports `flags=0x2(adhoc)`,
    ///   `TeamIdentifier=not set`, which is what `scripts/make-app.sh` falls
    ///   back to when the keychain has no Apple Development certificate):
    ///   `UNUserNotificationCenter.notificationSettings()` **never returns**.
    ///   Not an error — the continuation is simply never resumed, so every
    ///   `await` on it hangs for the life of the process. Measured on this
    ///   machine: `lockCards.start()` logged, and neither the settings nor the
    ///   request log line that follows it ever appeared.
    /// - **Signed with a non-Apple identity**: the calls return, and
    ///   `requestAuthorization` fails with `UNErrorDomain` code 1,
    ///   "Notifications are not allowed for this application".
    ///
    /// Either way no card can post, and the honest thing is to say so rather
    /// than to report `notDetermined` for ever or to blame the user's
    /// Notification settings (UI Principle #4).
    @Published private(set) var registrationBlocked = false

    private enum CardID {
        static let weather = "com.gameslayer999.tempo.card.weather"
        static let music = "com.gameslayer999.tempo.card.music"
    }

    private let state: AppState
    private let weather: WeatherService
    private let lock: ScreenLockService
    private let prefs: Preferences
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false
    /// Temp artwork files handed to `UNNotificationAttachment`, so they can be
    /// cleaned up rather than accumulating in the container for the session.
    private var attachmentFiles: [URL] = []

    /// `UNUserNotificationCenter.current()` traps outright in a process with
    /// no bundle — the bare `swift build` binary — so every entry point is
    /// gated on this rather than on a `try?`.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    init(state: AppState, weather: WeatherService, lock: ScreenLockService, prefs: Preferences) {
        self.state = state
        self.weather = weather
        self.lock = lock
        self.prefs = prefs
    }

    func start() {
        tempoDebug("lockCards.start isRunning=\(isRunning) canNotify=\(canNotify) bundleID=\(Bundle.main.bundleIdentifier ?? "nil") showCards=\(prefs.showLockScreenCards)")
        guard !isRunning, canNotify else { return }
        isRunning = true
        lock.start()
        // Switching the feature on is the moment to ask. Without this the
        // Settings toggle turned the cards "on" while macOS had never been
        // asked for permission, so nothing could ever post and nothing said so
        // (decision 060).
        Task { [weak self] in
            await self?.refreshAuthorizationAsync()
            guard let self, self.authorization == .notDetermined else { return }
            await self.requestAuthorization()
        }

        // The lock edge is what posts and withdraws. `removeDuplicates` because
        // `ScreenLockService` reconciles on wake and can re-assert a value it
        // already holds.
        lock.$isLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                guard let self else { return }
                // Re-read permission on the lock edge: a grant made in System
                // Settings mid-session must take effect at the next lock, not
                // at the next launch.
                self.refreshAuthorization()
                if locked { self.postAll() } else { self.withdrawAll() }
            }
            .store(in: &cancellables)

        // Content changes only matter while locked; posting on every track
        // change unlocked is exactly the Notification Center clutter this
        // design avoids.
        state.$nowPlaying
            .removeDuplicates()
            .sink { [weak self] _ in self?.postMusicIfLocked() }
            .store(in: &cancellables)

        weather.$reading
            .removeDuplicates()
            .sink { [weak self] _ in self?.postWeatherIfLocked() }
            .store(in: &cancellables)

        // Switching a card off while the screen is locked should take it away
        // now, not at the next unlock.
        prefs.$lockCardShowsWeather
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] on in
                guard let self else { return }
                on ? self.postWeatherIfLocked() : self.withdraw(CardID.weather)
            }
            .store(in: &cancellables)

        prefs.$lockCardShowsMusic
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] on in
                guard let self else { return }
                on ? self.postMusicIfLocked() : self.withdraw(CardID.music)
            }
            .store(in: &cancellables)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancellables.removeAll()
        withdrawAll()
        cleanUpAttachments()
        lock.stop()
    }

    // MARK: Authorization

    /// Ask for notification permission. Alerts only — no badge (an accessory
    /// app has no Dock tile to badge) and no sound, because a card that beeps
    /// at a locked, sleeping Mac is the opposite of what this is for.
    /// Once macOS has recorded a refusal it never prompts again — the request
    /// returns `UNError.notificationsNotAllowed` immediately instead. Swallowing
    /// that with `try?` is what hid this feature's real failure: the row kept
    /// offering "Allow", the button kept doing nothing, and the state stayed
    /// `notDetermined` forever. A refusal is recorded as `denied` so the UI
    /// switches to the only thing that can actually fix it — System Settings.
    func requestAuthorization() async {
        guard canNotify else { return }
        do {
            let granted = try await Self.withTimeout {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            }
            guard let granted else {
                registrationBlocked = true
                tempoDebug("notif requestAuthorization TIMED OUT — notification centre never replied")
                return
            }
            await refreshAuthorizationAsync()
            tempoDebug("notif requestAuthorization granted=\(granted) status=\(authorization.rawValue)")
        } catch {
            await refreshAuthorizationAsync()
            let ns = error as NSError
            tempoDebug("notif requestAuthorization FAILED domain=\(ns.domain) code=\(ns.code) status=\(authorization.rawValue) desc=\(ns.localizedDescription)")
            if ns.domain == UNErrorDomain,
               ns.code == UNError.Code.notificationsNotAllowed.rawValue {
                // Not the user's doing: macOS refused the registration itself.
                registrationBlocked = true
            }
        }
    }

    /// Runs `work`, giving up after `seconds` and returning `nil`.
    ///
    /// Needed because the ad-hoc case does not fail — it never answers — and
    /// an `await` that never resumes leaks a task on every Settings open and
    /// every app activation, while leaving the UI reporting a state that is
    /// simply not true.
    private static func withTimeout<T: Sendable>(
        _ seconds: Double = 4,
        _ work: @escaping @Sendable () async throws -> T
    ) async rethrows -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func refreshAuthorization() {
        Task { await refreshAuthorizationAsync() }
    }

    private func refreshAuthorizationAsync() async {
        guard canNotify else { return }
        let snapshot = await Self.withTimeout { () -> [Int] in
            let s = await UNUserNotificationCenter.current().notificationSettings()
            return [s.authorizationStatus.rawValue, s.lockScreenSetting.rawValue,
                    s.alertSetting.rawValue, s.showPreviewsSetting.rawValue]
        }
        guard let snapshot else {
            registrationBlocked = true
            tempoDebug("notif settings TIMED OUT — notification centre never replied")
            return
        }
        authorization = UNAuthorizationStatus(rawValue: snapshot[0]) ?? .notDetermined
        tempoDebug("notif settings status=\(snapshot[0]) lockScreen=\(snapshot[1]) alert=\(snapshot[2]) preview=\(snapshot[3])")
    }

    // MARK: Posting

    private func postAll() {
        postWeatherIfLocked()
        postMusicIfLocked()
    }

    private func postWeatherIfLocked() {
        tempoDebug("card weather: running=\(isRunning) locked=\(lock.isLocked) cards=\(prefs.showLockScreenCards) wantsWeather=\(prefs.lockCardShowsWeather) hasReading=\(weather.reading != nil)")
        guard isRunning, lock.isLocked, prefs.showLockScreenCards, prefs.lockCardShowsWeather else { return }
        guard let reading = weather.reading else {
            // No reading is not an empty card — it is no card at all.
            withdraw(CardID.weather)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(reading.temperatureText) \(reading.condition.title)"
        var lines: [String] = []
        if !reading.placeName.isEmpty { lines.append(reading.placeName) }
        // Only worth saying when it disagrees with the actual temperature.
        if abs(reading.apparentTemperature - reading.temperature) >= 2 {
            lines.append("Feels like \(reading.apparentText)")
        }
        content.body = lines.joined(separator: " · ")
        post(content, id: CardID.weather)
    }

    private func postMusicIfLocked() {
        tempoDebug("card music: running=\(isRunning) locked=\(lock.isLocked) cards=\(prefs.showLockScreenCards) wantsMusic=\(prefs.lockCardShowsMusic) playing=\(state.nowPlaying?.isPlaying == true) track=\(state.nowPlaying != nil)")
        guard isRunning, lock.isLocked, prefs.showLockScreenCards, prefs.lockCardShowsMusic else { return }
        // Only a *playing* track earns a card. A paused player behind a locked
        // screen is not news, and a card claiming to be now-playing while
        // nothing plays is precisely the lying signal UI Principle #4 forbids.
        guard let playing = state.nowPlaying, playing.isPlaying, !playing.track.isEmpty else {
            withdraw(CardID.music)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = playing.track
        content.body = [playing.artist, playing.album]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        if let attachment = makeArtworkAttachment() {
            content.attachments = [attachment]
        }
        post(content, id: CardID.music)
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        // `.active` — the default level — is what actually *presents* a card.
        // `.passive` files a notification into the list without presenting it,
        // which is the opposite of a card whose whole purpose is to be visible
        // on the lock screen (decision 060). Silence comes from `sound = nil`,
        // not from the interruption level, so nothing beeps at a sleeping Mac.
        content.interruptionLevel = .active
        content.sound = nil
        // Both cards share a thread so macOS groups them as one Tempo stack
        // rather than two unrelated apps' worth of notifications.
        content.threadIdentifier = "com.gameslayer999.tempo.lockcards"

        // No trigger: delivered immediately. Re-adding an identifier that is
        // already delivered replaces that card in place, which is what makes a
        // track change update the existing card instead of stacking a new one.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                tempoDebug("card post FAILED id=\(id) error=\(error.localizedDescription)")
            } else {
                tempoDebug("card post ok id=\(id)")
            }
            // Fail silent (Guideline #3): the only real failure here is
            // "not authorized", which the Settings pane already reports from
            // `authorization`, and a card that didn't post is not something to
            // interrupt the user about.
        }
    }

    // MARK: Withdrawal

    private func withdrawAll() {
        withdraw(CardID.weather)
        withdraw(CardID.music)
    }

    private func withdraw(_ id: String) {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: Artwork

    /// Album art for the music card. `UNNotificationAttachment` takes a file
    /// URL and moves the file into its own store, so a fresh temp file is
    /// written per post and the previous ones are swept up afterwards.
    ///
    /// Written into Tempo's own caches directory rather than `/tmp`, and
    /// deleted on withdrawal — artwork is not sensitive, but nothing should
    /// accumulate on disk for the life of the session either.
    private func makeArtworkAttachment() -> UNNotificationAttachment? {
        // Sweep the previous post's file here rather than on withdrawal:
        // `UNNotificationAttachment` copies the file into its own store when
        // the request is *added*, asynchronously, so deleting it the moment a
        // sibling card is withdrawn could race that copy and cost the music
        // card its artwork.
        cleanUpAttachments()

        guard let artwork = state.artwork,
              let tiff = artwork.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TempoLockCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return nil }

        guard let attachment = try? UNNotificationAttachment(identifier: "", url: url, options: nil) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        attachmentFiles.append(url)
        return attachment
    }

    private func cleanUpAttachments() {
        for url in attachmentFiles {
            try? FileManager.default.removeItem(at: url)
        }
        attachmentFiles.removeAll()
    }

    /// Open the System Settings page that holds the switches Tempo cannot set
    /// for itself (Allow Notifications, Show on Lock Screen, Show previews).
    ///
    /// Every one of those is `readonly` in `UNNotificationSettings`, and the
    /// framework's only mutator — `requestAuthorization` — is precisely the
    /// call that fails once a denial is recorded. So a link is the whole of
    /// what Tempo can do here (decision 060).
    ///
    /// `?id=<bundle-id>` lands on *Tempo's own* page rather than the app list;
    /// verified on this machine by reading back the System Settings window
    /// title ("Tempo"). Falls back to the plain pane if the bundle has no
    /// identifier, which is the bare `swift build` binary.
    static func openSystemNotificationSettings() {
        let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let target = Bundle.main.bundleIdentifier.map { "\(pane)?id=\($0)" } ?? pane
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }
}

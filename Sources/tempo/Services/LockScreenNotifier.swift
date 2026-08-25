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
        guard !isRunning, canNotify else { return }
        isRunning = true
        lock.start()
        refreshAuthorization()

        // The lock edge is what posts and withdraws. `removeDuplicates` because
        // `ScreenLockService` reconciles on wake and can re-assert a value it
        // already holds.
        lock.$isLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                guard let self else { return }
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
        lock.stop()
    }

    // MARK: Authorization

    /// Ask for notification permission. Alerts only — no badge (an accessory
    /// app has no Dock tile to badge) and no sound, because a card that beeps
    /// at a locked, sleeping Mac is the opposite of what this is for.
    func requestAuthorization() async {
        guard canNotify else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        await refreshAuthorizationAsync()
    }

    func refreshAuthorization() {
        Task { await refreshAuthorizationAsync() }
    }

    private func refreshAuthorizationAsync() async {
        guard canNotify else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    // MARK: Posting

    private func postAll() {
        postWeatherIfLocked()
        postMusicIfLocked()
    }

    private func postWeatherIfLocked() {
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
        // Passive: delivered without a sound and without lighting a sleeping
        // display. The card is meant to be *found* on the lock screen, not to
        // interrupt anything.
        content.interruptionLevel = .passive
        content.sound = nil
        // Both cards share a thread so macOS groups them as one Tempo stack
        // rather than two unrelated apps' worth of notifications.
        content.threadIdentifier = "com.gameslayer999.tempo.lockcards"

        // No trigger: delivered immediately. Re-adding an identifier that is
        // already delivered replaces that card in place, which is what makes a
        // track change update the existing card instead of stacking a new one.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in
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
        cleanUpAttachments()
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

    /// Open the System Settings pane that holds the two switches Tempo cannot
    /// set for itself (Show on Lock Screen, Show previews).
    static func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

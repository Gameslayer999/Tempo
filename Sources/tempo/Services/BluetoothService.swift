import Foundation
import IOBluetooth

/// A Bluetooth device connecting or disconnecting, as a one-shot signal for the
/// notch's transient "live activity" (the AirPods-connected card on iOS).
struct BluetoothEvent: Identifiable, Equatable {
    enum Kind { case connected, disconnected }

    let id: UUID
    let deviceName: String
    let kind: Kind
    /// 0–100, nil when the device does not report one.
    let batteryPercent: Int?
    /// SF Symbol name chosen from the device's class of device (headphones,
    /// keyboard, mouse, etc.), falling back to a generic bluetooth symbol.
    let symbolName: String
}

/// Publishes transient Bluetooth connect/disconnect events for the notch.
///
/// ## Why this never runs on the main thread
///
/// Every IOBluetooth entry point funnels through
/// `+[IOBluetoothCoreBluetoothCoordinator sharedInstance]`, whose `init` blocks
/// its calling thread on an untimed `dispatch_semaphore_wait` until CoreBluetooth
/// reports a power state. Measured on this machine (macOS 26.6.1, Apple Silicon,
/// 2026-08-22): that semaphore is never signalled, because CoreBluetooth never
/// delivers `centralManagerDidUpdateState:` to a locally-signed app at all — a
/// `CBCentralManager` created directly stays in `.unknown` indefinitely and
/// `CBManager.authorization` stays `.notDetermined` with no prompt shown.
/// Reproduced identically from a bare CLI binary, from an ad-hoc-signed `.app`
/// with `NSBluetoothAlwaysUsageDescription`, from an identity-signed `.app`,
/// launched both directly and through `open`, and from both the main thread and
/// a background thread.
///
/// So `IOBluetoothDevice.register(forConnectNotifications:selector:)` called
/// from `start()` on the main actor would hang Tempo's entire UI forever. All
/// IOBluetooth work is therefore confined to one dedicated thread that is
/// allowed to park in that semaphore; the main actor is never blocked and the
/// feature simply publishes nothing (Agent Guideline #3, fail silent). If a
/// future OS or a provisioned signing identity lets CoreBluetooth power on, the
/// registration completes and events start flowing with no code change.
///
/// The thread is created once per process. `stop()`/`start()` re-drive
/// registration on that same thread rather than spawning another, so a
/// permanently-parked thread can never accumulate.
@MainActor
final class BluetoothService: ObservableObject {
    /// The event currently worth showing, or nil. Self-clears after
    /// `eventDisplayDuration`.
    @Published private(set) var event: BluetoothEvent?

    static let eventDisplayDuration: TimeInterval = 4

    private var watcher: BluetoothWatcher?
    private var thread: Thread?
    private var running = false
    private var clearTimer: Timer?

    init() {}

    /// Idempotent: a second call while already running is a no-op.
    func start() {
        guard !running else { return }
        running = true

        if let watcher, let thread {
            watcher.perform(#selector(BluetoothWatcher.register), on: thread, with: nil, waitUntilDone: false)
            return
        }

        let watcher = BluetoothWatcher { [weak self] event in
            Task { @MainActor in self?.show(event) }
        }
        self.watcher = watcher

        let thread = Thread {
            // IOBluetooth delivers its notification callbacks on the run loop of
            // the thread that registered them, so this thread needs a live one.
            // The port keeps `run()` from spinning when no source is attached —
            // including the case where `register()` parked and never returned.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            watcher.register()
            while !Thread.current.isCancelled {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "com.gameslayer999.tempo.bluetooth"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    /// Unregisters the IOBluetooth notifications and drops any showing event.
    /// The worker thread is kept parked for a later `start()`.
    func stop() {
        guard running else { return }
        running = false
        clearTimer?.invalidate()
        clearTimer = nil
        event = nil
        if let watcher, let thread {
            watcher.perform(#selector(BluetoothWatcher.unregister), on: thread, with: nil, waitUntilDone: false)
        }
    }

    private func show(_ incoming: BluetoothEvent) {
        guard running else { return } // a callback that raced `stop()`
        event = incoming
        clearTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.eventDisplayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.event = nil }
        }
        // Keep the auto-clear firing while the run loop is tracking UI events,
        // matching the other timers in Tempo — otherwise a card left up during a
        // drag would outlive its window.
        RunLoop.main.add(timer, forMode: .common)
        clearTimer = timer
    }

    deinit {
        clearTimer?.invalidate()
        if let watcher, let thread {
            watcher.perform(#selector(BluetoothWatcher.unregister), on: thread, with: nil, waitUntilDone: false)
        }
        thread?.cancel()
    }
}

/// Owns the IOBluetooth registrations. Every method runs on `BluetoothService`'s
/// dedicated thread, never on the main actor.
///
/// `@unchecked Sendable` because that thread confinement is what makes the
/// mutable state safe, and the compiler cannot see it: the instance crosses a
/// thread boundary once at construction, after which only `perform(on:)` and
/// IOBluetooth's own callbacks — all on that one thread — touch it.
private final class BluetoothWatcher: NSObject, @unchecked Sendable {
    private let emit: (BluetoothEvent) -> Void
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []

    init(emit: @escaping (BluetoothEvent) -> Void) {
        self.emit = emit
    }

    /// Blocks for as long as the CoreBluetooth coordinator takes to come up —
    /// on this machine, forever. That is why nothing here touches the main actor.
    @objc func register() {
        guard connectNote == nil else { return }
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        // A device already connected at launch never fires a connect
        // notification, so its disconnect has to be armed up front — unplugging
        // headphones you were already wearing is the common case.
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []) where device.isConnected() {
            armDisconnect(device)
        }
    }

    @objc func unregister() {
        connectNote?.unregister()
        connectNote = nil
        disconnectNotes.forEach { $0.unregister() }
        disconnectNotes.removeAll()
    }

    private func armDisconnect(_ device: IOBluetoothDevice) {
        guard let note = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        ) else { return }
        disconnectNotes.append(note)
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        armDisconnect(device)
        emit(Self.event(for: device, kind: .connected))
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        disconnectNotes.removeAll { $0 === note }
        emit(Self.event(for: device, kind: .disconnected))
    }

    private static func event(for device: IOBluetoothDevice, kind: BluetoothEvent.Kind) -> BluetoothEvent {
        BluetoothEvent(
            id: UUID(),
            deviceName: device.nameOrAddress ?? "Bluetooth Device",
            kind: kind,
            // Always nil: no public API on this machine reports it. IOBluetooth's
            // own `IOBluetoothDevice` answers `responds(to:)` false for
            // batteryPercent / batteryLevel / batteryPercentCombined /
            // batteryPercentSingle, and `ioreg -r -l -c IOHIDDevice` printed zero
            // lines containing "battery" (checked 2026-08-22). The remaining
            // routes — parsing `system_profiler SPBluetoothDataType` or the
            // private BatteryPercent IORegistry keys on
            // AppleDeviceManagementHIDEventService — are a subprocess spawn and a
            // private key respectively, and neither could be observed returning a
            // value here because no device was connected. A guessed number would
            // be a lying signal (UI Principle #4), so this reports nothing.
            batteryPercent: nil,
            symbolName: symbolName(for: device)
        )
    }

    /// Class-of-device values are from IOBluetooth's `BluetoothAssignedNumbers.h`.
    /// SF Symbols has no bluetooth glyph, so the fallback is the radiowaves pair.
    private static func symbolName(for device: IOBluetoothDevice) -> String {
        let major = Int(device.deviceClassMajor)
        let minor = Int(device.deviceClassMinor)

        switch major {
        case kBluetoothDeviceClassMajorAudio:
            switch minor {
            case kBluetoothDeviceClassMinorAudioLoudspeaker,
                 kBluetoothDeviceClassMinorAudioHiFi,
                 kBluetoothDeviceClassMinorAudioPortable:
                return "hifispeaker"
            case kBluetoothDeviceClassMinorAudioCar:
                return "car"
            case kBluetoothDeviceClassMinorAudioMicrophone:
                return "mic"
            default:
                return "headphones"
            }
        case kBluetoothDeviceClassMajorPeripheral:
            // The peripheral minor class packs the keyboard/pointing bits into
            // its high nibble and a device type into the low one, so it must be
            // masked rather than compared outright. An unclassified peripheral
            // falls through to the generic symbol rather than guessing keyboard.
            switch minor & 0x30 {
            case kBluetoothDeviceClassMinorPeripheral1Pointing: return "computermouse"
            case kBluetoothDeviceClassMinorPeripheral1Keyboard,
                 kBluetoothDeviceClassMinorPeripheral1Combo: return "keyboard"
            default: return "dot.radiowaves.left.and.right"
            }
        case kBluetoothDeviceClassMajorPhone:
            return "iphone"
        case kBluetoothDeviceClassMajorComputer:
            return "laptopcomputer"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}

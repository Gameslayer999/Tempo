import AudioToolbox
import CoreAudio
import Foundation

/// One selectable system audio output, as the notch panel's output picker
/// renders it.
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    /// SF Symbol picked from the transport type (built-in speaker, headphones,
    /// bluetooth, usb, hdmi, airplay…).
    let symbolName: String
}

/// Weak back-reference handed to the HAL as `clientData`. It is retained for
/// exactly as long as its listener registration and released when the listener
/// is removed, so a callback already in flight during teardown resolves a live
/// object and finds `service == nil` instead of a dangling pointer.
private final class ListenerContext {
    weak var service: AudioOutputService?
    init(_ service: AudioOutputService) { self.service = service }
}

/// Fires on a HAL notification thread. It copies the selectors out before
/// hopping to the main actor because `addresses` is only valid for the
/// duration of the callback.
private let audioOutputListenerProc: AudioObjectPropertyListenerProc = { _, count, addresses, clientData in
    guard let clientData else { return noErr }
    let context = Unmanaged<ListenerContext>.fromOpaque(clientData).takeUnretainedValue()
    let selectors = (0 ..< Int(count)).map { addresses[$0].mSelector }
    Task { @MainActor in context.service?.handleChange(selectors) }
    return noErr
}

/// System audio output switching: which device macOS plays through, and that
/// device's volume/mute.
///
/// Deliberately the *cheap* alternative to per-app audio routing. Tempo never
/// becomes part of the audio render path — it creates no aggregate or virtual
/// device, installs no tap, and re-renders no samples. Everything here is a
/// Core Audio HAL property read or write against devices the system already
/// owns, which is the same thing System Settings > Sound does. That keeps the
/// feature free of latency risk, of audio-glitch blame, and of the driver
/// installs its competitors need.
///
/// Every HAL call returns an `OSStatus` that is checked and, on failure,
/// silently dropped with the published state left untouched (Agent Guideline
/// #3 — fail silent, no log noise). Devices genuinely differ in what they
/// expose: this machine's HDMI output (LG ULTRAWIDE) answers
/// `kAudioHardwareUnknownPropertyError` for volume *and* mute, which is why
/// `volume` is optional rather than defaulted to 0 — a 0 there would be a lie
/// (UI Principle #4) and the UI hides the slider instead.
@MainActor
final class AudioOutputService: ObservableObject {
    /// Output-capable devices only, sorted by name. Input-only devices are
    /// excluded by output channel count, not by name: AirPods and similar
    /// enumerate as two separate HAL devices (one input, one output), so a
    /// name-based filter would leave a microphone in the output picker.
    @Published private(set) var devices: [AudioOutputDevice] = []

    /// The current default output device. `nil` only if the HAL reports none.
    @Published private(set) var currentDeviceID: AudioDeviceID?

    /// 0…1. nil when the current device exposes no software volume control
    /// (common for some HDMI/digital outputs) — the UI hides the slider then.
    @Published private(set) var volume: Float?

    @Published private(set) var isMuted: Bool = false

    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let context: Unmanaged<ListenerContext>
    }

    /// Listeners on the system object (device list, default output). Live for
    /// as long as the service is started.
    private var systemListeners: [Listener] = []

    /// Listeners on the *current* output device (volume, mute). Torn down and
    /// re-registered whenever the default output changes, because these
    /// properties belong to the device object rather than the system object.
    private var deviceListeners: [Listener] = []

    init() {}

    /// Idempotent — a second call while already observing is a no-op, so both
    /// an orchestrator and a view's `onAppear` may call it.
    func start() {
        guard systemListeners.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            if let listener = addListener(on: system, selector: selector) {
                systemListeners.append(listener)
            }
        }
        refreshDevices()
        refreshCurrentDevice()
    }

    func stop() {
        remove(&systemListeners)
        remove(&deviceListeners)
    }

    deinit {
        // Removal is by (object, address, proc, clientData) — none of which
        // touch actor-isolated state — so teardown is safe here and leaves no
        // dangling HAL registration if the service is dropped without `stop()`.
        for listener in systemListeners + deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListener(listener.object, &address,
                                              audioOutputListenerProc, listener.context.toOpaque())
            listener.context.release()
        }
    }

    func select(_ device: AudioOutputDevice) {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else { return }
        // The default-device listener fires too, but refreshing inline keeps
        // the picker's checkmark from lagging a thread hop behind the click.
        refreshCurrentDevice()
    }

    /// Applies to whichever device is currently the default output. A muted
    /// device stays muted — unmuting is `setMuted(false)`, matching how the
    /// HAL itself treats the two properties.
    func setVolume(_ value: Float) {
        guard let id = currentDeviceID, var address = Self.volumeAddress(for: id) else { return }
        var newValue = Float32(min(max(value, 0), 1))
        let status = AudioObjectSetPropertyData(id, &address, 0, nil,
                                                UInt32(MemoryLayout<Float32>.size), &newValue)
        guard status == noErr else { return }
        volume = newValue
    }

    func setMuted(_ muted: Bool) {
        guard let id = currentDeviceID else { return }
        var address = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        var newValue: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(id, &address, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &newValue)
        guard status == noErr else { return }
        isMuted = muted
    }

    // MARK: - Change handling

    fileprivate func handleChange(_ selectors: [AudioObjectPropertySelector]) {
        for selector in selectors {
            switch selector {
            case kAudioHardwarePropertyDevices:
                refreshDevices()
            case kAudioHardwarePropertyDefaultOutputDevice:
                refreshCurrentDevice()
            default:
                // The only other listeners registered are volume and mute on
                // the current device.
                refreshVolumeAndMute()
            }
        }
    }

    private func refreshDevices() {
        let list = Self.allDeviceIDs()
            .filter { Self.outputChannelCount($0) > 0 }
            .compactMap { id -> AudioOutputDevice? in
                guard let name = Self.stringProperty(id, kAudioObjectPropertyName),
                      let uid = Self.stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
                return AudioOutputDevice(id: id, uid: uid, name: name, symbolName: Self.symbolName(for: id))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if devices != list { devices = list }
    }

    private func refreshCurrentDevice() {
        let id = Self.defaultOutputDeviceID()
        if currentDeviceID != id { currentDeviceID = id }
        rebindDeviceListeners()
        refreshVolumeAndMute()
    }

    private func refreshVolumeAndMute() {
        guard let id = currentDeviceID else {
            if volume != nil { volume = nil }
            if isMuted { isMuted = false }
            return
        }
        let newVolume = Self.volumeAddress(for: id).flatMap { Self.readFloat(id, $0) }
        if volume != newVolume { volume = newVolume }
        let newMute = Self.readMute(id) ?? false
        if isMuted != newMute { isMuted = newMute }
    }

    // MARK: - Listener plumbing

    /// Uses the C-proc listener API rather than
    /// `AudioObjectAddPropertyListenerBlock`. Verified on this machine: a Swift
    /// closure passed to the *block* API re-bridges to a fresh Objective-C
    /// block at every call boundary, so the matching
    /// `AudioObjectRemovePropertyListenerBlock` returns `noErr` yet leaves the
    /// original block registered and still firing after `stop()`. The C proc
    /// removes by (proc, clientData) identity, which actually works.
    private func addListener(on object: AudioObjectID,
                             selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Listener? {
        var address = Self.address(selector, scope)
        let context = Unmanaged.passRetained(ListenerContext(self))
        guard AudioObjectAddPropertyListener(object, &address,
                                             audioOutputListenerProc, context.toOpaque()) == noErr else {
            context.release()
            return nil
        }
        return Listener(object: object, address: address, context: context)
    }

    private func rebindDeviceListeners() {
        remove(&deviceListeners)
        guard let id = currentDeviceID else { return }
        if let volumeAddress = Self.volumeAddress(for: id),
           let listener = addListener(on: id, selector: volumeAddress.mSelector, scope: volumeAddress.mScope) {
            deviceListeners.append(listener)
        }
        if let listener = addListener(on: id, selector: kAudioDevicePropertyMute,
                                      scope: kAudioObjectPropertyScopeOutput) {
            deviceListeners.append(listener)
        }
    }

    private func remove(_ listeners: inout [Listener]) {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListener(listener.object, &address,
                                              audioOutputListenerProc, listener.context.toOpaque())
            listener.context.release()
        }
        listeners.removeAll()
    }

    // MARK: - HAL reads

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var id: AudioDeviceID = 0
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// Total channels across the device's output streams. Zero means the device
    /// cannot play audio and must not appear in the picker.
    private static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func readUInt32(_ id: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readFloat(_ id: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Float? {
        var address = address
        var size = UInt32(MemoryLayout<Float32>.size)
        var value: Float32 = 0
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readMute(_ id: AudioDeviceID) -> Bool? {
        readUInt32(id, address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)).map { $0 != 0 }
    }

    /// The one address used for reading, writing *and* observing this device's
    /// volume, so those three can never disagree about which property backs the
    /// slider. `VirtualMainVolume` is preferred because the HAL synthesises it
    /// for devices that only publish per-channel scalars; `VolumeScalar` on the
    /// main element is the fallback. `nil` means the device has no software
    /// volume at all (verified: this machine's HDMI output).
    private static func volumeAddress(for id: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                         kAudioDevicePropertyVolumeScalar] {
            var address = address(selector, kAudioObjectPropertyScopeOutput)
            if AudioObjectHasProperty(id, &address) { return address }
        }
        return nil
    }

    private static func symbolName(for id: AudioDeviceID) -> String {
        switch readUInt32(id, address(kAudioDevicePropertyTransportType)) {
        case kAudioDeviceTransportTypeBuiltIn:
            // Built-in covers both the speakers and the headphone jack; only
            // the output data source tells them apart ('ispk' vs 'hdpn').
            let source = readUInt32(id, address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput))
            return source == 0x6864_706E ? "headphones" : "speaker.wave.2"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI:
            return "hifispeaker"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "speaker.wave.2"
        }
    }
}

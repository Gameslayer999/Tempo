import Accelerate
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Tuning constants

/// Bundle identifier of the only app Tempo taps.
private let spotifyBundleID = "com.spotify.client"

/// Number of visualizer bands. Fixed at 5 to match `VisualizerView`.
private let bandCount = 5

/// 512-point real FFT. Matches the 512 frames the tap delivers per callback at
/// 48 kHz (93.75 callbacks/s), so one FFT runs per callback with no buffering
/// latency. Measured cost: ~1.0 µs per callback (~0.01% of one core).
private let fftSize = 512
private let fftLog2n = vDSP_Length(9)
private let fftHalf = fftSize / 2

/// Band edges in Hz, converted to FFT bins against the tap's real sample rate
/// when the tap is built. At the observed 48 kHz (93.75 Hz per bin) these land
/// on bins 1, 2, 5, 13, 43, 256 — i.e. bass, low-mid, mid, upper-mid, treble.
private let bandEdgesHz: [Double] = [93.75, 187.5, 468.75, 1218.75, 4031.25, .infinity]

/// `vDSP_fft_zrip` returns magnitudes scaled by 2 and a Hann window has 0.5
/// coherent gain, so a full-scale tone sitting in a one-bin band reads about
/// `fftSize / 2`. Dividing by that puts a band mean back on an amplitude-like
/// scale, which `normalizedLevel` reads in dB.
private let magnitudeScale = 1.0 / Float(fftHalf)

/// dB window mapped linearly onto 0…1 bar height. The floor is the level below
/// which a band reads as "nothing here"; the ceiling is where a bar tops out.
private let magnitudeFloorDB: Float = -50
private let magnitudeCeilDB: Float = -14

/// Per-band trim, in dB, applied before the floor/ceiling mapping. Music's
/// spectrum tilts down steeply and the upper bands average over many more bins,
/// so without this the treble bars would barely move. Calibrated from a live
/// 48 kHz Spotify capture on this machine, where the five smoothed bands sat at
/// roughly −20, −35, −48, −59 and −69 dB; these gains land them on −26…−34 dB,
/// i.e. bars resting around 45–65% height with room for transients.
private let bandGainDB: [Float] = [-6, 7, 18, 27, 35]

/// How long a band level survives without fresh nonzero audio before the
/// service reports that reactive mode is unavailable.
private let captureHoldSeconds = 1.5

/// All-zero buffers for this long, while Spotify is reported as running output,
/// is the signature of a TCC-denied tap (every Core Audio call still returns
/// `noErr`; the buffers are simply silent forever).
private let silentDenialSeconds = 2.0

/// UI pump rate and its asymmetric smoothing: bars snap up to a peak, then fall
/// away slowly, which reads as responding to the music rather than flickering.
private let pumpInterval = 1.0 / 30.0
private let attackCoefficient: Float = 0.5
private let releaseCoefficient: Float = 0.10

/// Below this a band level counts as fully settled and the pump may stop.
private let settledEpsilon: Float = 0.001

/// Magnitude → 0…1 bar height. Named so the mapping stays tunable in one place.
@inline(__always)
private func normalizedLevel(_ magnitude: Float, gainDB: Float) -> Float {
    let amplitude = magnitude * magnitudeScale
    guard amplitude > 0 else { return 0 }
    let db = 20 * log10f(amplitude) + gainDB
    let t = (db - magnitudeFloorDB) / (magnitudeCeilDB - magnitudeFloorDB)
    return min(max(t, 0), 1)
}

// MARK: - Audio thread ⇄ main thread hand-off

/// Fixed-size, last-writer-wins slot. The audio thread publishes the newest
/// band levels; the 30 Hz UI pump reads them. Storage is raw pointers behind a
/// stable `os_unfair_lock` so neither side ever allocates or copy-on-writes,
/// and the audio thread never blocks on the main thread.
private final class LevelSlot: @unchecked Sendable {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let values = UnsafeMutablePointer<Float>.allocate(capacity: bandCount)
    private var lastNonzero: UInt64 = 0
    private var lastCallback: UInt64 = 0

    init() {
        lock.initialize(to: os_unfair_lock())
        values.initialize(repeating: 0, count: bandCount)
    }

    deinit {
        lock.deallocate()
        values.deallocate()
    }

    /// Audio thread.
    func publish(_ source: UnsafePointer<Float>, nonzero: Bool, at now: UInt64) {
        os_unfair_lock_lock(lock)
        values.update(from: source, count: bandCount)
        lastCallback = now
        if nonzero { lastNonzero = now }
        os_unfair_lock_unlock(lock)
    }

    /// Main thread. Copies into a caller-owned buffer so no array is shared.
    func read(into destination: inout [Float]) -> (lastNonzero: UInt64, lastCallback: UInt64) {
        os_unfair_lock_lock(lock)
        for i in 0..<bandCount { destination[i] = values[i] }
        let stamps = (lastNonzero, lastCallback)
        os_unfair_lock_unlock(lock)
        return stamps
    }

    func reset() {
        os_unfair_lock_lock(lock)
        values.update(repeating: 0, count: bandCount)
        lastNonzero = 0
        lastCallback = 0
        os_unfair_lock_unlock(lock)
    }
}

/// The per-callback DSP. Lives for the whole process (the FFT setup and every
/// scratch buffer are allocated once here) and is reused across taps, so the
/// IO block itself allocates nothing, takes no lock except the level slot's,
/// and never logs or stores a captured sample.
private final class TapProcessor: @unchecked Sendable {
    let slot = LevelSlot()

    private let wake: DispatchSourceUserDataAdd
    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let mags: UnsafeMutablePointer<Float>
    private let levels: UnsafeMutablePointer<Float>
    private let gains: UnsafeMutablePointer<Float>
    private let binLo: UnsafeMutablePointer<Int>
    private let binHi: UnsafeMutablePointer<Int>

    private var ringWrite = 0
    private var wasSilent = true

    init?(wake: DispatchSourceUserDataAdd) {
        guard let setup = vDSP_create_fftsetup(fftLog2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.wake = wake
        self.setup = setup
        window = .allocate(capacity: fftSize)
        ring = .allocate(capacity: fftSize)
        frame = .allocate(capacity: fftSize)
        realp = .allocate(capacity: fftHalf)
        imagp = .allocate(capacity: fftHalf)
        mags = .allocate(capacity: fftHalf)
        levels = .allocate(capacity: bandCount)
        gains = .allocate(capacity: bandCount)
        binLo = .allocate(capacity: bandCount)
        binHi = .allocate(capacity: bandCount)

        vDSP_hann_window(window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        ring.initialize(repeating: 0, count: fftSize)
        frame.initialize(repeating: 0, count: fftSize)
        realp.initialize(repeating: 0, count: fftHalf)
        imagp.initialize(repeating: 0, count: fftHalf)
        mags.initialize(repeating: 0, count: fftHalf)
        levels.initialize(repeating: 0, count: bandCount)
        for i in 0..<bandCount { gains[i] = bandGainDB[i] }
        configure(sampleRate: 48_000)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for p in [window, ring, frame, realp, imagp, mags, levels, gains] { p.deallocate() }
        binLo.deallocate()
        binHi.deallocate()
    }

    /// Recomputes band bin ranges for the tap's actual sample rate. Called on
    /// the main thread before the IO proc starts, never while it is running.
    func configure(sampleRate: Double) {
        let rate = sampleRate > 0 ? sampleRate : 48_000
        let binWidth = rate / Double(fftSize)
        for i in 0..<bandCount {
            let lo = max(1, Int((bandEdgesHz[i] / binWidth).rounded()))
            let hi = bandEdgesHz[i + 1].isFinite
                ? Int((bandEdgesHz[i + 1] / binWidth).rounded())
                : fftHalf
            binLo[i] = min(lo, fftHalf - 1)
            binHi[i] = min(max(hi, binLo[i] + 1), fftHalf)
        }
    }

    /// Clears every carried-over sample so a rebuilt tap starts from silence.
    func reset() {
        ring.update(repeating: 0, count: fftSize)
        levels.update(repeating: 0, count: bandCount)
        ringWrite = 0
        wasSilent = true
        slot.reset()
    }

    // MARK: Audio thread

    func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard abl.count > 0, let data = abl[0].mData else { return }

        let channels = max(1, Int(abl[0].mNumberChannels))
        let sampleCount = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
        let frames = sampleCount / channels
        guard frames > 0 else { return }

        let left = data.assumingMemoryBound(to: Float.self)
        // Non-interleaved taps split channels across buffers; the observed tap
        // is one interleaved stereo buffer. Both mix down to mono here.
        let right: UnsafeMutablePointer<Float>? = (channels == 1 && abl.count > 1)
            ? abl[1].mData?.assumingMemoryBound(to: Float.self)
            : nil

        var offset = 0
        var half: Float = 0.5
        while offset < frames {
            let take = min(fftSize - ringWrite, frames - offset)
            let destination = ring + ringWrite
            if let right {
                vDSP_vadd(left + offset, 1, right + offset, 1, destination, 1, vDSP_Length(take))
                vDSP_vsmul(destination, 1, &half, destination, 1, vDSP_Length(take))
            } else if channels >= 2 {
                let base = left + offset * channels
                vDSP_vadd(base, vDSP_Stride(channels), base + 1, vDSP_Stride(channels),
                          destination, 1, vDSP_Length(take))
                vDSP_vsmul(destination, 1, &half, destination, 1, vDSP_Length(take))
            } else {
                destination.update(from: left + offset, count: take)
            }
            ringWrite = (ringWrite + take) % fftSize
            offset += take
        }

        // Oldest sample sits at `ringWrite`; linearize into `frame`.
        let tail = fftSize - ringWrite
        frame.update(from: ring + ringWrite, count: tail)
        (frame + tail).update(from: ring, count: ringWrite)

        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(fftSize))
        let nonzero = peak > 0

        if nonzero {
            vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(fftSize))
            var split = DSPSplitComplex(realp: realp, imagp: imagp)
            frame.withMemoryRebound(to: DSPComplex.self, capacity: fftHalf) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftHalf))
            }
            vDSP_fft_zrip(setup, &split, 1, fftLog2n, FFTDirection(FFT_FORWARD))
            vDSP_zvabs(&split, 1, mags, 1, vDSP_Length(fftHalf))

            for i in 0..<bandCount {
                var mean: Float = 0
                vDSP_meanv(mags + binLo[i], 1, &mean, vDSP_Length(binHi[i] - binLo[i]))
                levels[i] = normalizedLevel(mean, gainDB: gains[i])
            }
        } else {
            levels.update(repeating: 0, count: bandCount)
        }

        slot.publish(levels, nonzero: nonzero, at: DispatchTime.now().uptimeNanoseconds)

        // Nudge the main thread only on a silence→sound edge, so a stopped pump
        // restarts without the audio thread signalling 94 times a second.
        if nonzero && wasSilent { wake.add(data: 1) }
        wasSilent = !nonzero
    }
}

// MARK: - Service

/// Real audio-reactive levels for the notch visualizer.
///
/// Taps Spotify's output with a per-process Core Audio tap
/// (`CATapDescription(stereoMixdownOfProcesses:)` at `muteBehavior = .unmuted`,
/// so the user still hears their music) fed into a private aggregate device,
/// runs a 512-point FFT per callback, and publishes five smoothed 0…1 band
/// levels at 30 Hz.
///
/// Every failure degrades to `isCapturing == false` in silence — no dialogs, no
/// logging, no retry loops — and `VisualizerView` falls back to its
/// playback-synced animation. Captured audio is reduced to five floats and
/// discarded; no sample is ever stored, copied, or logged.
///
/// Starts itself on first access (`AudioTapService.shared`) because the view is
/// its only owner; there is nothing to wire up in `AppDelegate`.
@MainActor
final class AudioTapService: ObservableObject {
    static let shared = AudioTapService()

    /// Five smoothed band levels, 0…1, bass first.
    @Published private(set) var bands: [Float] = Array(repeating: 0, count: bandCount)

    /// True only while real nonzero audio has arrived recently — the signal
    /// `VisualizerView` uses to choose reactive mode over the fallback.
    @Published private(set) var isCapturing = false

    /// Set when the tap delivers callbacks that are all exactly zero while
    /// Spotify reports running output. That is what a TCC-denied tap looks
    /// like: every Core Audio call returns `noErr` and the buffers stay silent
    /// forever. Recorded once and left alone — no teardown, no retry loop.
    private(set) var silentDenialSuspected = false

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let ioQueue = DispatchQueue(label: "com.tempo.audiotap.io", qos: .userInitiated)
    private let wake: DispatchSourceUserDataAdd
    private let processor: TapProcessor?

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var processObjectID: AudioObjectID = 0
    private var tapStarted: UInt64 = 0
    private var lastBuildAttempt: UInt64 = 0

    private var pump: Timer?
    private var rebuild: DispatchWorkItem?
    private var raw = [Float](repeating: 0, count: bandCount)
    private var level = [Float](repeating: 0, count: bandCount)

    private init() {
        let source = DispatchSource.makeUserDataAddSource(queue: .main)
        wake = source
        processor = TapProcessor(wake: source)

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.startPump() }
        }
        source.resume()

        observeSpotify()
        observeProcessObjects()
        observeOutputDevice()
        syncTap()
    }

    // MARK: Lifecycle

    private func observeSpotify() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == spotifyBundleID else { return }
                Task { @MainActor in AudioTapService.shared.syncTap() }
            }
        }
    }

    /// Spotify has no Core Audio process object until it first touches the HAL,
    /// which is usually after `didLaunchApplication` — a tap built at that
    /// moment fails and would never be retried. Re-attempt whenever the process
    /// object list changes; `syncTap()` is a no-op once a tap exists.
    private func observeProcessObjects() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main) { _, _ in
            Task { @MainActor in AudioTapService.shared.syncTap() }
        }
    }

    /// The aggregate device pins the output device UID at creation, so it goes
    /// stale the moment the user switches output (headphones in or out). Rebuild
    /// the whole tap when the default system output changes.
    private func observeOutputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main) { _, _ in
            Task { @MainActor in AudioTapService.shared.scheduleRebuild() }
        }
    }

    /// Output switches emit several notifications in a row; coalesce them.
    private func scheduleRebuild() {
        rebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.teardownTap()
                self.syncTap()
            }
        }
        rebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private var spotifyPID: pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: spotifyBundleID)
            .first?
            .processIdentifier
    }

    /// The tap exists only while Spotify does.
    private func syncTap() {
        guard let pid = spotifyPID else {
            teardownTap()
            return
        }
        guard tapID == 0 else { return }
        // Building a tap makes Tempo a HAL client, which itself perturbs the
        // process object list. Throttle so a build that keeps failing can never
        // turn that feedback into a retry storm.
        let now = DispatchTime.now().uptimeNanoseconds
        guard lastBuildAttempt == 0 || Double(now &- lastBuildAttempt) / 1e9 > 1 else { return }
        lastBuildAttempt = now
        if #available(macOS 14.2, *) {
            buildTap(pid: pid)
        }
    }

    @available(macOS 14.2, *)
    private func buildTap(pid: pid_t) {
        guard let processor else { return }
        guard let processObject = Self.processObject(for: pid) else { return }
        processObjectID = processObject

        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.uuid = UUID()
        description.name = "Tempo Visualizer"
        description.isPrivate = true
        // Anything but `.unmuted` silences Spotify for the user.
        description.muteBehavior = .unmuted

        var tap: AudioObjectID = 0
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else { return }

        var format = AudioStreamBasicDescription()
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &formatSize, &format) == noErr {
            processor.configure(sampleRate: format.mSampleRate)
        }

        guard let outputUID = Self.defaultOutputUID() else {
            _ = AudioHardwareDestroyProcessTap(tap)
            return
        }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tempo Visualizer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]

        var aggregate: AudioObjectID = 0
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate) == noErr,
              aggregate != 0 else {
            _ = AudioHardwareDestroyProcessTap(tap)
            return
        }

        processor.reset()
        var proc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, ioQueue) { _, input, _, _, _ in
            processor.process(input)
        }
        guard created == noErr, let proc else {
            _ = AudioHardwareDestroyAggregateDevice(aggregate)
            _ = AudioHardwareDestroyProcessTap(tap)
            return
        }

        guard AudioDeviceStart(aggregate, proc) == noErr else {
            _ = AudioDeviceDestroyIOProcID(aggregate, proc)
            _ = AudioHardwareDestroyAggregateDevice(aggregate)
            _ = AudioHardwareDestroyProcessTap(tap)
            return
        }

        tapID = tap
        aggregateID = aggregate
        ioProcID = proc
        tapStarted = DispatchTime.now().uptimeNanoseconds
        silentDenialSuspected = false
        startPump()
    }

    private func teardownTap() {
        rebuild?.cancel()
        rebuild = nil

        if aggregateID != 0, let proc = ioProcID {
            _ = AudioDeviceStop(aggregateID, proc)
            _ = AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        if #available(macOS 14.2, *) {
            if aggregateID != 0 { _ = AudioHardwareDestroyAggregateDevice(aggregateID) }
            if tapID != 0 { _ = AudioHardwareDestroyProcessTap(tapID) }
        }
        ioProcID = nil
        aggregateID = 0
        tapID = 0
        processObjectID = 0
        tapStarted = 0
        lastBuildAttempt = 0
        silentDenialSuspected = false
        processor?.reset()

        stopPump()
        for i in 0..<bandCount { level[i] = 0 }
        if bands.contains(where: { $0 != 0 }) { bands = level }
        if isCapturing { isCapturing = false }
    }

    // MARK: UI pump

    private func startPump() {
        guard pump == nil, tapID != 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: pumpInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
    }

    private func stopPump() {
        pump?.invalidate()
        pump = nil
    }

    /// Reads the newest levels, applies asymmetric smoothing, publishes, and
    /// stops itself once everything has settled to silence — so a resting notch
    /// costs zero redraws until the audio thread nudges it awake again.
    private func tick() {
        guard let processor else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let stamps = processor.slot.read(into: &raw)

        let silentFor = stamps.lastNonzero == 0
            ? Double.infinity
            : Double(now &- stamps.lastNonzero) / 1e9
        let live = silentFor < captureHoldSeconds

        if live {
            silentDenialSuspected = false
        } else if !silentDenialSuspected,
                  silentFor > silentDenialSeconds,
                  stamps.lastCallback != 0,
                  Double(now &- stamps.lastCallback) / 1e9 < 0.5,
                  Self.isRunningOutput(processObjectID) {
            // Callbacks are arriving, they are all exactly zero, and Spotify is
            // playing: the tap exists but was never authorized.
            silentDenialSuspected = true
        }

        if isCapturing != live { isCapturing = live }

        var settled = true
        for i in 0..<bandCount {
            let target = live ? raw[i] : 0
            let k = target > level[i] ? attackCoefficient : releaseCoefficient
            var next = level[i] + (target - level[i]) * k
            if next < settledEpsilon { next = 0 }
            level[i] = next
            if next != 0 { settled = false }
        }
        if bands != level { bands = level }

        // Keep pumping for at least the silent-denial window after a tap is
        // built, so an unauthorized tap — which delivers zero buffers and would
        // otherwise settle the pump before its first callback ever lands — is
        // still classified. After that, silence stops the pump outright.
        let sinceTapStart = tapStarted == 0 ? 0 : Double(now &- tapStarted) / 1e9
        if settled, sinceTapStart > silentDenialSeconds, !live || silentDenialSuspected {
            stopPump()
        }
    }

    // MARK: Core Audio property reads

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var qualifier = pid
        var object: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) {
            AudioObjectGetPropertyData(systemObject, &address,
                                       UInt32(MemoryLayout<pid_t>.size), $0, &size, &object)
        }
        return (status == noErr && object != 0) ? object : nil
    }

    private static func isRunningOutput(_ processObject: AudioObjectID) -> Bool {
        guard processObject != 0 else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, $0)
        }
        guard status == noErr, let uid else { return nil }
        return uid as String
    }
}

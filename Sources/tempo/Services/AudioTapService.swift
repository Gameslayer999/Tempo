import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Tuning constants

/// How long audio has to keep arriving before the strip grows a visualizer for
/// it (decision 056). A Discord ping or a UI alert is sound, not something to
/// listen to, and must not pop the notch's wings open; `captureHoldSeconds`
/// already keeps `isCapturing` up for 1.5 s past a short sound, so this sits
/// above that.
private let audioOnsetSeconds: TimeInterval = 2

/// How long the strip keeps a visualizer up after system audio goes quiet when
/// no now-playing card is holding it there (decision 056). Long enough to ride
/// out the gap between two YouTube videos, short enough that a finished video
/// puts the notch back to bare. `captureHoldSeconds` alone (1.5 s) made the
/// pill retract and grow again between clips.
private let audioHoldSeconds: TimeInterval = 15

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
    /// Index of the *tap's* buffer inside the aggregate device's input buffer
    /// list. See `AudioTapService.tapBufferIndex(...)` — it is not always 0.
    private var tapBuffer = 0

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

    /// Points the DSP at the buffer the tap actually occupies. Called on the
    /// main thread before the IO proc starts, never while it is running.
    func configure(tapBufferIndex: Int) {
        tapBuffer = max(0, tapBufferIndex)
    }

    /// Read only by the debug log line in `AudioTapService.tick`.
    var debugTapBuffer: Int { tapBuffer }

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
        // `tapBuffer`, never 0 blindly: the aggregate's input buffer list is
        // its sub-device's input streams *first*, the tap's streams after
        // (see AudioTapService.tapBufferIndex). Reading buffer 0 unconditionally
        // meant that whenever the default output device also carries an input
        // stream, Tempo analysed that device's microphone instead of Spotify.
        guard abl.count > tapBuffer, let data = abl[tapBuffer].mData else { return }

        let channels = max(1, Int(abl[tapBuffer].mNumberChannels))
        let sampleCount = Int(abl[tapBuffer].mDataByteSize) / MemoryLayout<Float>.size
        let frames = sampleCount / channels
        guard frames > 0 else { return }

        let left = data.assumingMemoryBound(to: Float.self)
        // Non-interleaved taps split channels across buffers; the observed tap
        // is one interleaved stereo buffer. Both mix down to mono here.
        let right: UnsafeMutablePointer<Float>? = (channels == 1 && abl.count > tapBuffer + 1)
            ? abl[tapBuffer + 1].mData?.assumingMemoryBound(to: Float.self)
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
/// Taps **all system audio output** with a global Core Audio tap
/// (`CATapDescription(stereoGlobalTapButExcludeProcesses:)` at
/// `muteBehavior = .unmuted`, so the user still hears everything) fed into a
/// private aggregate device,
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

    /// True only while real nonzero audio has arrived recently *and* the
    /// output device can actually be heard — the signal `VisualizerView` uses
    /// to choose reactive mode over the fallback.
    @Published private(set) var isCapturing = false

    /// Whether the current default output device is audible at all: not muted
    /// and not at zero volume (decision 039). A process tap is taken *before*
    /// the device's volume and mute are applied, so without this the bars
    /// danced at full height on a muted Mac — motion for something nobody can
    /// hear (UI Principle #5). Fails open: a device that exposes neither
    /// property is treated as audible, which is the pre-existing behaviour.
    @Published private(set) var outputAudible = true

    /// `isCapturing`, delayed by `audioOnsetSeconds` at its start and extended
    /// by `audioHoldSeconds` at its end. The collapsed strip shows a
    /// visualizer-only wing off this when there is no now-playing card to show
    /// instead (decision 056); keying that off `isCapturing` directly would pop
    /// the wings open for a notification ping and flap the pill's width across
    /// every gap between clips.
    @Published private(set) var audioActive = false

    /// Set when the tap delivers callbacks that are all exactly zero while some
    /// process reports running output. That is what a TCC-denied tap looks
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
    private var tapStarted: UInt64 = 0
    private var lastBuildAttempt: UInt64 = 0

    private var pump: Timer?
    private var audioHold: Timer?
    private var audioOnset: Timer?
    /// The device the mute/volume listeners below are attached to, and the
    /// blocks themselves — both needed to detach them when the default output
    /// device changes.
    private var audibilityDevice: AudioObjectID = 0
    private var audibilityListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var lastDebugLog: UInt64 = 0
    private var lastDebugLive = false
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

        observeProcessObjects()
        observeOutputDevice()
        observeAudibility()
        syncTap()
    }

    // MARK: Lifecycle

    /// A tap built before Core Audio is ready — at login, or while the default
    /// output device is still settling — fails and would never be retried.
    /// Re-attempt whenever the process object list changes, which is exactly
    /// when some app starts touching the HAL; `syncTap()` is a no-op once a
    /// tap exists.
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
            Task { @MainActor in
                AudioTapService.shared.observeAudibility()
                AudioTapService.shared.scheduleRebuild()
            }
        }
    }

    // MARK: Output audibility

    /// (Re)attaches mute and volume listeners to the current default output
    /// device and re-reads `outputAudible` (decision 039).
    ///
    /// Listener-driven, not polled: the pump stops while the bars are flat, so
    /// polling inside `tick()` would never see the un-mute that has to bring
    /// them back — which is also why becoming audible restarts the pump here.
    /// The audio thread only signals on a silence→sound edge, and muting does
    /// not create one: the tap goes on delivering the same nonzero audio.
    private func observeAudibility() {
        for (address, block) in audibilityListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(audibilityDevice, &address, .main, block)
        }
        audibilityListeners.removeAll()
        audibilityDevice = Self.defaultOutputDevice() ?? 0

        guard audibilityDevice != 0 else {
            setOutputAudible(true)
            return
        }

        for selector in [kAudioDevicePropertyMute, kAudioHardwareServiceDeviceProperty_VirtualMainVolume] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(audibilityDevice, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    AudioTapService.shared.setOutputAudible(AudioTapService.isOutputAudible())
                }
            }
            guard AudioObjectAddPropertyListenerBlock(audibilityDevice, &address, .main, block) == noErr else {
                continue
            }
            audibilityListeners.append((address, block))
        }

        setOutputAudible(Self.isOutputAudible())
    }

    private func setOutputAudible(_ audible: Bool) {
        guard outputAudible != audible else { return }
        outputAudible = audible
        tempoDebug("outputAudible=\(audible)")
        // Audible again: the audio thread will not signal, because it never
        // went silent. Restart the pump so the bars pick the music back up.
        if audible { startPump() }
    }

    /// Not muted, and not at zero volume. Either property missing is read as
    /// audible — never as silence — so an unusual device degrades to the old
    /// always-reactive behaviour instead of a permanently dead visualizer.
    private static func isOutputAudible() -> Bool {
        guard let device = defaultOutputDevice() else { return true }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted) == noErr,
           muted != 0 {
            return false
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var volume: Float32 = 1
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &volumeAddress),
           AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr {
            return volume > 0.0001
        }

        return true
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

    /// One global tap, built once and kept for Tempo's lifetime — the only
    /// thing that tears it down is an output-device change (decision 056).
    private func syncTap() {
        guard tapID == 0 else { return }
        // Building a tap makes Tempo a HAL client, which itself perturbs the
        // process object list. Throttle so a build that keeps failing can never
        // turn that feedback into a retry storm.
        let now = DispatchTime.now().uptimeNanoseconds
        guard lastBuildAttempt == 0 || Double(now &- lastBuildAttempt) / 1e9 > 1 else { return }
        lastBuildAttempt = now
        if #available(macOS 14.2, *) {
            buildTap()
        }
    }

    @available(macOS 14.2, *)
    private func buildTap() {
        guard let processor else { return }

        // Every process's output, excluding none: Tempo itself plays no audio,
        // and naming a specific app here is exactly what made the visualizer
        // deaf to YouTube (decision 056).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Tempo Visualizer"
        description.isPrivate = true
        // Anything but `.unmuted` silences the tapped audio for the user.
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

        guard let outputDevice = Self.defaultOutputDevice(),
              let outputUID = Self.deviceUID(outputDevice) else {
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

        processor.configure(tapBufferIndex: Self.tapBufferIndex(aggregate: aggregate, subDevice: outputDevice))
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
        tempoDebug(String(format:
            "tap built global subDeviceInputBuffers=%d aggregateInputBuffers=%d tapBuffer=%d outputUID=%@",
            Self.inputBufferCount(outputDevice),
            Self.inputBufferCount(aggregate),
            Self.tapBufferIndex(aggregate: aggregate, subDevice: outputDevice), outputUID))
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
        tapStarted = 0
        lastBuildAttempt = 0
        silentDenialSuspected = false
        processor?.reset()

        stopPump()
        for i in 0..<bandCount { level[i] = 0 }
        if bands.contains(where: { $0 != 0 }) { bands = level }
        setCapturing(false)
    }

    /// Publishes `isCapturing` and drives the `audioActive` window around it —
    /// late to open, slow to close (decision 056).
    private func setCapturing(_ live: Bool) {
        if isCapturing != live { isCapturing = live }

        if live {
            audioHold?.invalidate()
            audioHold = nil
            guard !audioActive, audioOnset == nil else { return }
            audioOnset = Self.after(audioOnsetSeconds) { [weak self] in
                self?.audioActive = true
                self?.audioOnset = nil
            }
            return
        }

        audioOnset?.invalidate()
        audioOnset = nil
        guard audioActive, audioHold == nil else { return }
        audioHold = Self.after(audioHoldSeconds) { [weak self] in
            self?.audioActive = false
            self?.audioHold = nil
        }
    }

    /// One-shot main-runloop timer, `.common` mode so the notch's own
    /// animations do not defer it.
    private static func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
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
        // Real audio is arriving from the tap — independent of whether any of
        // it can be heard. The TCC-denial heuristic below keys off this, not
        // off `live`: a muted Mac is not a denied tap.
        let hasSignal = silentFor < captureHoldSeconds
        let live = hasSignal && outputAudible

        if hasSignal {
            silentDenialSuspected = false
        } else if !silentDenialSuspected,
                  silentFor > silentDenialSeconds,
                  stamps.lastCallback != 0,
                  Double(now &- stamps.lastCallback) / 1e9 < 0.5,
                  Self.anyProcessRunningOutput() {
            // Callbacks are arriving, they are all exactly zero, and something
            // is playing: the tap exists but was never authorized.
            silentDenialSuspected = true
        }

        setCapturing(live)

        if tempoDebugEnabled {
            let sinceLog = lastDebugLog == 0 ? Double.infinity : Double(now &- lastDebugLog) / 1e9
            if live != lastDebugLive || sinceLog > 1 {
                lastDebugLive = live
                lastDebugLog = now
                let peak = raw.max() ?? 0
                tempoDebug(String(format:
                    "tap live=%d silentFor=%.2f suspected=%d tapBuffer=%d rawPeak=%.3f anyRunningOutput=%d",
                    live ? 1 : 0, silentFor, silentDenialSuspected ? 1 : 0,
                    processor.debugTapBuffer, peak,
                    Self.anyProcessRunningOutput() ? 1 : 0))
            }
        }

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

    /// Whether *any* process is currently playing audio. Reads the HAL's
    /// process object list rather than one known process, because the global
    /// tap has no single owning app to ask.
    private static func anyProcessRunningOutput() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objects) == noErr else {
            return false
        }
        return objects.contains { isRunningOutput($0) }
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

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func deviceUID(_ device: AudioObjectID) -> String? {
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

    /// Number of buffers a device contributes to an IO proc's input buffer
    /// list, read from its input stream configuration.
    private static func inputBufferCount(_ device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).count
    }

    /// Where the tap's audio sits in the aggregate's input buffer list.
    ///
    /// The aggregate is one sub-device (the default output device) plus our
    /// process tap, and the IO proc receives the **sub-device's input streams
    /// first, the tap's streams after them**. Verified on macOS 26.6 by
    /// building the exact aggregate this file builds and reading its input
    /// stream configuration: with an output-only sub-device the layout is one
    /// 2-channel buffer (the tap, at index 0); adding a sub-device that also
    /// has an input stream makes it `[1, 2]` — the device's 1-channel
    /// microphone at index 0 and the tap at index 1.
    ///
    /// So index 0 is the tap only by luck of the user's current output device.
    /// Whenever that device also carries an input stream — a headset in call
    /// mode, or the virtual input+output device meeting apps install — buffer 0
    /// is a **microphone**, and reading it made the visualizer dance to the
    /// room instead of to Spotify (and put mic audio through the FFT, which
    /// Tempo must never do).
    ///
    /// Falls back to 0 if the layout can't be read or looks unexpected; the
    /// `abl.count > tapBuffer` guard in `TapProcessor.process` covers the rest.
    private static func tapBufferIndex(aggregate: AudioObjectID, subDevice: AudioObjectID) -> Int {
        let offset = inputBufferCount(subDevice)
        guard offset > 0, inputBufferCount(aggregate) > offset else { return 0 }
        return offset
    }
}

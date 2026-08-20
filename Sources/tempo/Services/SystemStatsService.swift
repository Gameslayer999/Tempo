import Darwin
import Foundation

/// 1Hz CPU/memory sampler backing the compact usage graph (`UsageGraphView`).
/// A singleton (rather than an `AppState`-owned service like `MusicService`/
/// `AgentStatusService`) because the sampling loop and its 60-sample history
/// are process-wide state with no per-window identity — any number of view
/// instances share one `shared`.
///
/// Both Mach calls below are unprivileged, local-machine, read-only queries
/// (`host_statistics`/`host_statistics64` against `mach_host_self()`) — no
/// other app's data is touched, matching Agent Guideline #3's read-only
/// posture even though that guideline is written specifically about
/// AgentStatus's files.
@MainActor
final class SystemStatsService: ObservableObject {
    static let shared = SystemStatsService()

    /// Latest CPU/memory usage, 0...100. `nil` until a real sample exists —
    /// CPU needs two ticks to produce a delta, so the very first tick after
    /// `start()` publishes memory but not CPU. Publishing 0 in the meantime
    /// would be a lie (UI Principle #4); `nil` lets the view show nothing
    /// instead.
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var memUsage: Double?

    /// Oldest -> newest, capped at 60 samples (~1 minute at 1Hz).
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []

    // Nonisolated: `UsageGraphView`'s `Sparkline` (a `Shape`) reads this
    // from its nonisolated `path(in:)`. It's an immutable constant, so
    // opting it out of the class's @MainActor isolation is safe.
    nonisolated static let historyLimit = 60

    private var timer: Timer?
    private var lastCPUTicks: host_cpu_load_info?

    private init() {}

    /// Starts the 1Hz sampling timer. Idempotent: a second call while a
    /// timer is already running is a no-op, so both the orchestrator and a
    /// view's `onAppear` can call this without double-scheduling.
    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        // Keep sampling while the run loop is tracking UI events (dragging,
        // scrolling the panel), same as the other pollers in Tempo.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sample()
    }

    /// Stops sampling entirely (the usage module is switched off in Settings).
    /// The history is kept, so switching it back on redraws the sparklines
    /// from what was already collected instead of starting blank.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
    }

    /// Usage% = delta(user+system+nice) / delta(total) x 100 across the two
    /// most recent samples. `host_cpu_load_info.cpu_ticks` is already
    /// aggregated across every core, so this is a system-wide 0...100
    /// figure — it must never be divided by core count.
    private func sampleCPU() {
        guard let ticks = Self.hostCPULoadInfo() else { return }
        defer { lastCPUTicks = ticks }

        guard let previous = lastCPUTicks else { return } // baseline only, no delta yet

        let deltaUser = Double(ticks.cpu_ticks.0 &- previous.cpu_ticks.0)
        let deltaSystem = Double(ticks.cpu_ticks.1 &- previous.cpu_ticks.1)
        let deltaIdle = Double(ticks.cpu_ticks.2 &- previous.cpu_ticks.2)
        let deltaNice = Double(ticks.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = deltaUser + deltaSystem + deltaIdle + deltaNice
        guard total > 0 else { return }

        let usage = (deltaUser + deltaSystem + deltaNice) / total * 100
        cpuUsage = usage
        Self.append(usage, to: &cpuHistory)
    }

    /// Used% = (active + wire + compressor pages) x real page size / total
    /// physical memory. Page size always comes from `host_page_size` — it is
    /// 16 KB on Apple Silicon, not the historical 4 KB.
    private func sampleMemory() {
        guard let info = Self.hostVMInfo64(), let pageSize = Self.pageSize else { return }

        let usedPages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return }

        let usage = Double(usedBytes) / Double(total) * 100
        memUsage = usage
        Self.append(usage, to: &memHistory)
    }

    private static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private static func hostCPULoadInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    private static func hostVMInfo64() -> vm_statistics64? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    private static var pageSize: vm_size_t? {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS else { return nil }
        return size
    }
}

// SPDX-License-Identifier: MIT

import AppKit

/// One poll result. `cpu`/`gpu` are nil when unreadable; the UI shows "--°C"
/// for nil and never crashes on missing data.
struct TemperatureReading: Equatable, Sendable {
    let cpu: Double?
    let gpu: Double?
    let cpuKey: String?
    let gpuKey: String?
    let date: Date

    static let empty = TemperatureReading(
        cpu: nil, gpu: nil, cpuKey: nil, gpuKey: nil, date: Date(timeIntervalSince1970: 0)
    )
}

/// Resolves which value the menu bar shows. Pure function (unit-tested).
/// `.max` falls back to whichever side is available when only one reads.
func resolveDisplayValue(cpu: Double?, gpu: Double?, mode: DisplayMode) -> Double? {
    switch mode {
    case .cpu:
        return cpu
    case .gpu:
        return gpu
    case .max:
        switch (cpu, gpu) {
        case let (c?, g?):
            return Swift.max(c, g)
        case let (c?, nil):
            return c
        case let (nil, g?):
            return g
        case (nil, nil):
            return nil
        }
    }
}

/// Menu bar title text. Pure function (unit-tested).
func formatTitle(celsius: Double?) -> String {
    guard let celsius, celsius.isFinite else {
        return "--°C"
    }
    return "\(Int(celsius.rounded()))°C"
}

/// Periodic SMC polling.
///
/// - SMC reads run on a private serial queue; the main thread only renders.
/// - The timer is coalesced (`tolerance`) to stay power-friendly.
/// - Sleep/wake is observed: polling pauses naturally during sleep (the
///   runloop is suspended) and a fresh read fires immediately after wake.
/// - If every key fails several polls in a row, the SMC connection is
///   recycled once (close + reopen) to recover from driver-side staleness;
///   reads then continue normally. This is the self-healing path that keeps
///   a year-long run healthy without user intervention.
///
/// All public methods must be called from the main thread.
final class TemperatureMonitor: @unchecked Sendable {
    /// Fired on the main thread after every poll.
    var onUpdate: ((TemperatureReading) -> Void)?

    private let smc = SMCService()
    private let queue = DispatchQueue(label: "dev.studiorizi.everytmp.smc")
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var interval: TimeInterval
    /// Consecutive polls where NO key (CPU or GPU) produced a reading.
    /// Accessed only on `queue`.
    private var consecutiveTotalFailures = 0
    /// Re-entrancy guard so a slow read can never stack up polls.
    /// Accessed only on `queue`.
    private var polling = false

    /// After this many fully-empty polls, recycle the SMC connection once.
    private static let failuresBeforeReconnect = 3

    var isSMCOpen: Bool { smc.isOpen }

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func start() {
        queue.async { [weak self] in
            _ = self?.smc.open()
            DispatchQueue.main.async { [weak self] in
                self?.poll()
            }
        }
        installTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        onUpdate = nil
        // Close synchronously: at termination time there is no later
        // runloop turn guaranteed, and close() is lock-guarded and fast.
        smc.close()
    }

    /// Applies a new refresh interval without touching the SMC connection.
    func setInterval(_ newInterval: TimeInterval) {
        interval = newInterval
        installTimer()
    }

    /// Triggers one poll immediately (used by the diagnostics Refresh).
    func refresh() {
        poll()
    }

    // MARK: - Private (main thread unless noted)

    private func installTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Coalescing keeps a 1-second interval from costing a full wakeup
        // every second; temperature moves slowly, so this is free savings.
        newTimer.tolerance = min(0.5, interval / 4)
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.polling else { return }
            self.polling = true
            defer { self.polling = false }

            let cpu = self.smc.firstAvailable(in: SMCKeys.cpuCandidates)
            let gpu = self.smc.firstAvailable(in: SMCKeys.gpuCandidates)

            if cpu == nil, gpu == nil {
                self.consecutiveTotalFailures += 1
                if self.consecutiveTotalFailures >= Self.failuresBeforeReconnect {
                    // Self-heal: recycle the connection once, then keep going.
                    // If the driver is truly gone, reads keep failing and the
                    // UI keeps showing "--°C" — never a crash, never a spin.
                    self.smc.close()
                    _ = self.smc.open()
                    self.consecutiveTotalFailures = 0
                }
            } else {
                self.consecutiveTotalFailures = 0
            }

            let reading = TemperatureReading(
                cpu: cpu?.celsius, gpu: gpu?.celsius,
                cpuKey: cpu?.key, gpuKey: gpu?.key,
                date: Date()
            )
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(reading)
            }
        }
    }
}

// SPDX-License-Identifier: MIT
//
// Swift wrapper around the read-only C SMC shim.
//
// Design notes for long-term stability:
// - One process-wide connection, guarded by a lock; every public method is
//   safe to call from any thread.
// - Reads are synchronous and short; callers run them on a background queue.
// - Failures are NEVER fatal: a nil return simply means "unreadable right
//   now" and the UI degrades to "--°C".

import CSMCShim
import Foundation

/// Known SMC temperature keys, in priority order.
///
/// - CPU: `TCMz` (CPU die hotspot, the same reading TG Pro labels
///   "CPU Die (Hotspot)") first, then package-level fallbacks (`TCMb`,
///   `TCDX`, Intel-era `TC0P`/`TC0D`, SoC package grid `TPD0`).
///   Per-core cluster keys (`Tp..`/`Te..`/`Tc..`) are deliberately NOT
///   used: their layout is SoC-generation specific (M2 uses `Tp..`,
///   M3 Ultra uses `Tc..`) and idle clusters report parked-sensor
///   sentinel values.
/// - GPU: `TRDX` (GPU die hotspot) first, then the `TRDx` grid cell and
///   Intel-era `TG0D`/`TG0P`/`Tg0e`.
/// Keys absent on a given Mac simply fail to read and are skipped, so this
/// list covers Apple Silicon generations and degrades gracefully on Intel.
/// Verified live on Apple M3 Ultra (Mac15,14, macOS 26.4): TCMz/TRDX/TCMb/
/// TCDX/TPD0/TRDx present as `flt`; TCHP/TC0P/TPMP/TG0D/TG0P/Tg0e absent.
enum SMCKeys {
    static let cpuCandidates = ["TCMz", "TCMb", "TCDX", "TC0P", "TC0D", "TPD0"]
    static let gpuCandidates = ["TRDX", "TRDd", "TG0D", "TG0P", "Tg0e", "TRD0"]

    /// Swift-side mirror of the C plausibility gate. Kept in sync with
    /// smc.c: powered die sensors at or below 10 °C are parked/off
    /// sentinels (the lower bound is exclusive because idle sensors clamp
    /// at exactly 10.00 °C), and nothing operates above 125 °C.
    static func isPlausibleDieTemp(_ celsius: Double) -> Bool {
        celsius.isFinite && celsius > 10.0 && celsius <= 125.0
    }
}

final class SMCService: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false

    /// Opens the AppleSMC connection (idempotent). Returns false when the
    /// machine has no readable SMC (non-SMC hardware, driver unavailable).
    @discardableResult
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if opened {
            return true
        }
        if everytmp_smc_open() == 0 {
            opened = true
            return true
        }
        return false
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if opened {
            everytmp_smc_close()
            opened = false
        }
    }

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    /// Reads one 4-character SMC key. Returns nil for any failure, including
    /// "not open". Never traps: over-long keys are rejected up front and the
    /// C call receives exactly 4 bytes.
    func readCelsius(key: String) -> Double? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
            return nil
        }
        var value: Double = 0
        lock.lock()
        defer { lock.unlock() }
        guard opened else { return nil }
        let rc: Int32 = bytes.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: 4) { cPtr in
                everytmp_smc_read_temp(cPtr, &value)
            }
        }
        guard rc == 0, SMCKeys.isPlausibleDieTemp(value) else {
            return nil
        }
        return value
    }

    /// Returns the first readable key in priority order, with the key that
    /// produced it (used by diagnostics to show the provenance).
    func firstAvailable(in keys: [String]) -> (key: String, celsius: Double)? {
        for key in keys {
            if let value = readCelsius(key: key) {
                return (key, value)
            }
        }
        return nil
    }
}

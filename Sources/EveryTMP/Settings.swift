// SPDX-License-Identifier: MIT

import Foundation

/// Which temperature the menu bar shows.
enum DisplayMode: Int, CaseIterable, Sendable {
    case cpu = 0
    case gpu = 1
    /// The higher of the CPU and GPU readings.
    case max = 2

    /// Localized menu label for this mode.
    var title: String {
        switch self {
        case .cpu: return L10n.t("menu.mode.cpu")
        case .gpu: return L10n.t("menu.mode.gpu")
        case .max: return L10n.t("menu.mode.max")
        }
    }
}

/// UserDefaults-backed settings. The stored values are always validated on
/// the way in and on the way out, so a corrupt or hand-edited defaults file
/// can never put the app into an undefined state.
enum Settings {
    private static let modeKey = "displayMode"
    private static let intervalKey = "updateInterval"

    static let defaultMode = DisplayMode.max
    static let defaultInterval: TimeInterval = 2.0

    /// The only refresh intervals the UI offers. A fixed set keeps the menu
    /// simple and bounds the SMC polling rate (lightweight by construction:
    /// at most one read per second, each read taking a few milliseconds).
    static let allowedIntervals: [TimeInterval] = [1, 2, 5, 10]

    static var displayMode: DisplayMode {
        get {
            guard UserDefaults.standard.object(forKey: modeKey) != nil else {
                return defaultMode
            }
            return DisplayMode(
                rawValue: UserDefaults.standard.integer(forKey: modeKey)
            ) ?? defaultMode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    static var updateInterval: TimeInterval {
        get {
            guard UserDefaults.standard.object(forKey: intervalKey) != nil else {
                return defaultInterval
            }
            return snappedInterval(UserDefaults.standard.double(forKey: intervalKey))
        }
        set {
            UserDefaults.standard.set(snappedInterval(newValue), forKey: intervalKey)
        }
    }

    /// Snaps any value to the nearest allowed interval. Pure function so it
    /// is unit-testable without touching UserDefaults.
    static func snappedInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultInterval }
        return allowedIntervals.min(by: { abs($0 - value) < abs($1 - value) })
            ?? defaultInterval
    }
}

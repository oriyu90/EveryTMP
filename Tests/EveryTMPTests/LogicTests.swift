// SPDX-License-Identifier: MIT

import XCTest
@testable import EveryTMP

final class LogicTests: XCTestCase {
    // MARK: - Title formatting (menu bar "xx°C")

    func testFormatTitleRoundsToInteger() {
        XCTAssertEqual(formatTitle(celsius: 42.4), "42°C")
        XCTAssertEqual(formatTitle(celsius: 42.5), "43°C")
        XCTAssertEqual(formatTitle(celsius: 36.0), "36°C")
        XCTAssertEqual(formatTitle(celsius: 105.6), "106°C")
    }

    func testFormatTitleNilIsPlaceholder() {
        XCTAssertEqual(formatTitle(celsius: nil), "--°C")
    }

    func testFormatTitleNonFiniteIsPlaceholder() {
        XCTAssertEqual(formatTitle(celsius: Double.nan), "--°C")
        XCTAssertEqual(formatTitle(celsius: Double.infinity), "--°C")
    }

    // MARK: - Display mode resolution

    func testResolveCPU() {
        XCTAssertEqual(resolveDisplayValue(cpu: 50, gpu: 40, mode: .cpu), 50)
        XCTAssertNil(resolveDisplayValue(cpu: nil, gpu: 40, mode: .cpu))
    }

    func testResolveGPU() {
        XCTAssertEqual(resolveDisplayValue(cpu: 50, gpu: 40, mode: .gpu), 40)
        XCTAssertNil(resolveDisplayValue(cpu: 50, gpu: nil, mode: .gpu))
    }

    func testResolveMaxPicksHigher() {
        XCTAssertEqual(resolveDisplayValue(cpu: 50, gpu: 62.3, mode: .max), 62.3)
        XCTAssertEqual(resolveDisplayValue(cpu: 71, gpu: 62.3, mode: .max), 71)
    }

    func testResolveMaxFallsBackToAvailableSide() {
        XCTAssertEqual(resolveDisplayValue(cpu: 50, gpu: nil, mode: .max), 50)
        XCTAssertEqual(resolveDisplayValue(cpu: nil, gpu: 44, mode: .max), 44)
        XCTAssertNil(resolveDisplayValue(cpu: nil, gpu: nil, mode: .max))
    }

    func testDisplayModeRawValuesStable() {
        // Persisted in UserDefaults: never renumber.
        XCTAssertEqual(DisplayMode.cpu.rawValue, 0)
        XCTAssertEqual(DisplayMode.gpu.rawValue, 1)
        XCTAssertEqual(DisplayMode.max.rawValue, 2)
        XCTAssertNil(DisplayMode(rawValue: 99))
    }

    // MARK: - Settings validation (pure helpers, no UserDefaults touched)

    func testSnappedInterval() {
        XCTAssertEqual(Settings.snappedInterval(1), 1)
        XCTAssertEqual(Settings.snappedInterval(2), 2)
        XCTAssertEqual(Settings.snappedInterval(3), 2)
        XCTAssertEqual(Settings.snappedInterval(4), 5)
        XCTAssertEqual(Settings.snappedInterval(7), 5)
        XCTAssertEqual(Settings.snappedInterval(8), 10)
        XCTAssertEqual(Settings.snappedInterval(0), 1)
        XCTAssertEqual(Settings.snappedInterval(-5), 1)
        XCTAssertEqual(Settings.snappedInterval(3600), 10)
        XCTAssertEqual(Settings.snappedInterval(Double.nan), Settings.defaultInterval)
        XCTAssertEqual(Settings.snappedInterval(Double.infinity), Settings.defaultInterval)
    }

    func testAllowedIntervalsUnchanged() {
        XCTAssertEqual(Settings.allowedIntervals, [1, 2, 5, 10])
    }

    // MARK: - SMC key lists

    func testCPUCandidatesLeadWithHotspot() {
        XCTAssertFalse(SMCKeys.cpuCandidates.isEmpty)
        XCTAssertEqual(SMCKeys.cpuCandidates.first, "TCMz")
        XCTAssertTrue(SMCKeys.cpuCandidates.contains("TRDX") == false)
    }

    func testGPUCandidatesLeadWithHotspot() {
        XCTAssertFalse(SMCKeys.gpuCandidates.isEmpty)
        XCTAssertEqual(SMCKeys.gpuCandidates.first, "TRDX")
    }

    func testAllCandidateKeysAreFourAsciiChars() {
        for key in SMCKeys.cpuCandidates + SMCKeys.gpuCandidates {
            XCTAssertEqual(key.utf8.count, 4, "key \(key) must be 4 chars")
            XCTAssertTrue(key.utf8.allSatisfy({ $0 < 0x80 }), "key \(key) must be ASCII")
        }
    }

    // MARK: - Plausibility gate (mirrors smc.c; parked sentinels rejected)

    func testPlausibleDieTemp() {
        XCTAssertTrue(SMCKeys.isPlausibleDieTemp(42.0))
        XCTAssertTrue(SMCKeys.isPlausibleDieTemp(125.0))
        // Parked-sensor sentinels seen on idle P-core keys.
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(6.7))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(4.633))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(0.0))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(9.9))
        // Idle sensors clamp at exactly 10.00 (verified on M3 Ultra):
        // the lower bound is exclusive.
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(10.0))
        XCTAssertTrue(SMCKeys.isPlausibleDieTemp(10.01))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(-5.0))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(Double.nan))
        XCTAssertFalse(SMCKeys.isPlausibleDieTemp(Double.infinity))
    }

    // MARK: - Diagnostics text

    func testDiagnosticsTextContainsReadings() {
        let data = DiagnosticsData(
            reading: TemperatureReading(
                cpu: 51.24, gpu: 44.0, cpuKey: "TCMz", gpuKey: "TRDX", date: Date()
            ),
            smcOpen: true,
            mode: .max,
            interval: 2,
            appVersion: "1.0.0 (1)"
        )
        let text = makeDiagnosticsText(data)
        XCTAssertTrue(text.contains("51.2"))
        XCTAssertTrue(text.contains("44.0"))
        XCTAssertTrue(text.contains("TCMz"))
        XCTAssertTrue(text.contains("TRDX"))
        XCTAssertFalse(text.isEmpty)
    }

    func testDiagnosticsTextHandlesMissingReadings() {
        let data = DiagnosticsData(
            reading: .empty,
            smcOpen: false,
            mode: .cpu,
            interval: 5,
            appVersion: "1.0.0 (1)"
        )
        let text = makeDiagnosticsText(data)
        XCTAssertTrue(text.contains("--"))
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: - ja/en strings parity

    func testLocalizableStringsParity() {
        // Locate the package root from this file's path (cwd-independent).
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent() // LogicTests.swift
            .deletingLastPathComponent() // EveryTMPTests
            .deletingLastPathComponent() // Tests
        let jaURL = packageRoot
            .appendingPathComponent("Resources/ja.lproj/Localizable.strings")
        let enURL = packageRoot
            .appendingPathComponent("Resources/en.lproj/Localizable.strings")
        let ja = try! String(contentsOf: jaURL, encoding: .utf8)
        let en = try! String(contentsOf: enURL, encoding: .utf8)
        let jaKeys = stringsKeys(ja)
        let enKeys = stringsKeys(en)
        XCTAssertFalse(jaKeys.isEmpty)
        XCTAssertEqual(jaKeys, enKeys, "ja and en tables must define the same keys")
        // Every key used by the Swift code must exist in both tables.
        for key in expectedKeysUsedInCode {
            XCTAssertTrue(jaKeys.contains(key), "missing ja key: \(key)")
        }
    }

    // MARK: - Helpers
    private func stringsKeys(_ content: String) -> Set<String> {
        // Matches: "key" = "value";
        let pattern = #""((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        var keys = Set<String>()
        for match in regex.matches(in: content, range: range) {
            if let keyRange = Range(match.range(at: 1), in: content) {
                keys.insert(String(content[keyRange]))
            }
        }
        return keys
    }

    /// Every L10n.t/f key referenced by the app. Update this list when adding UI text.
    private var expectedKeysUsedInCode: [String] {
        [
            "menu.status", "menu.version", "menu.displayMode",
            "menu.mode.cpu", "menu.mode.gpu", "menu.mode.max",
            "menu.interval", "menu.interval.seconds",
            "menu.launchAtLogin", "menu.diagnostics", "menu.quit",
            "diag.title", "diag.system", "diag.os", "diag.smc",
            "diag.smc.open", "diag.smc.closed",
            "diag.cpu", "diag.gpu", "diag.noSignal",
            "diag.mode", "diag.interval",
            "diag.refresh", "diag.close", "diag.note",
        ]
    }
}

// MARK: - Menu wiring (crash-safety of actions, no UI observation needed)

/// Builds the real menu and fires every safe action. If a selector is
/// miswired (typo, missing @objc, wrong signature) or an action traps,
/// this test crashes instead of the user's menu bar click doing so.
/// Login-item registration and Quit are deliberately NOT fired.
@MainActor
final class MenuWiringTests: XCTestCase {
    func testMenuBuildsAndSafeActionsDoNotCrash() {
        let savedMode = Settings.displayMode
        let savedInterval = Settings.updateInterval
        defer {
            Settings.displayMode = savedMode
            Settings.updateInterval = savedInterval
        }

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: Notification.Name("MenuWiringTests"))
        )
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        XCTAssertGreaterThanOrEqual(menu.items.count, 10)

        var fired = 0
        func fire(_ item: NSMenuItem) {
            guard let action = item.action else { return }
            let name = NSStringFromSelector(action)
            // Only the mode/interval setters: no side effects outside
            // EveryTMP's own UserDefaults keys (restored in defer).
            guard name.hasPrefix("setModeAction")
                || name.hasPrefix("setIntervalAction") else { return }
            NSApplication.shared.sendAction(action, to: item.target, from: item)
            fired += 1
        }
        for item in menu.items {
            fire(item)
            item.submenu?.items.forEach(fire)
        }
        // 3 mode items + 4 interval items.
        XCTAssertEqual(fired, 7)

        delegate.applicationWillTerminate(
            Notification(name: Notification.Name("MenuWiringTests"))
        )
    }
}

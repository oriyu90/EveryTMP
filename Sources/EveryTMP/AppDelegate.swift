// SPDX-License-Identifier: MIT

import AppKit
import ServiceManagement

/// Owns the status bar item and the temperature monitor lifecycle.
///
/// Single-process, event-driven design: SMC polling happens on a private
/// serial queue and the main thread only renders state — the same pattern
/// as the sibling menu-bar utility Save battery. The menu is rebuilt from
/// scratch on every open (`menuNeedsUpdate` + `removeAllItems`) so no stale
/// items can accumulate over a year-long run.
///
/// Main-actor bound: the delegate callbacks, menu actions, and monitor
/// updates all run on the main thread.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let monitor: TemperatureMonitor
    private var lastReading: TemperatureReading = .empty
    private var diagnosticsController: DiagnosticsWindowController?

    override init() {
        monitor = TemperatureMonitor(interval: Settings.updateInterval)
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        monitor.onUpdate = { [weak self] reading in
            guard let self else { return }
            self.lastReading = reading
            self.updateTitle()
            // Keep an open diagnostics window live without extra polling.
            if self.diagnosticsController?.isVisible == true {
                self.refreshDiagnostics()
            }
        }
        monitor.start()
        updateTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Status item rendering

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let value = resolveDisplayValue(
            cpu: lastReading.cpu, gpu: lastReading.gpu, mode: Settings.displayMode
        )
        button.title = formatTitle(celsius: value)
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.toolTip = L10n.f(
            "menu.status",
            formatTitle(celsius: lastReading.cpu),
            formatTitle(celsius: lastReading.gpu)
        )
    }

    private static var appVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        // Header: live CPU/GPU readings.
        let header = NSMenuItem(
            title: L10n.f(
                "menu.status",
                formatTitle(celsius: lastReading.cpu),
                formatTitle(celsius: lastReading.gpu)
            ),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let versionLine = NSMenuItem(
            title: L10n.f("menu.version", Self.appVersion),
            action: nil,
            keyEquivalent: ""
        )
        versionLine.isEnabled = false
        menu.addItem(versionLine)

        menu.addItem(.separator())

        // Display mode section.
        let modeHeader = NSMenuItem(title: L10n.t("menu.displayMode"), action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(setModeAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = (Settings.displayMode == mode) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Refresh interval submenu.
        let intervalItem = NSMenuItem(title: L10n.t("menu.interval"), action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for seconds in Settings.allowedIntervals {
            let item = NSMenuItem(
                title: L10n.f("menu.interval.seconds", Int(seconds)),
                action: #selector(setIntervalAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(seconds)
            item.state = (Settings.updateInterval == seconds) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: L10n.t("menu.launchAtLogin"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

        let diagnostics = NSMenuItem(
            title: L10n.t("menu.diagnostics"),
            action: #selector(openDiagnostics),
            keyEquivalent: ""
        )
        diagnostics.target = self
        menu.addItem(diagnostics)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: L10n.t("menu.quit"),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func setModeAction(_ sender: NSMenuItem) {
        guard let mode = DisplayMode(rawValue: sender.tag) else { return }
        Settings.displayMode = mode
        updateTitle()
    }

    @objc private func setIntervalAction(_ sender: NSMenuItem) {
        let interval = TimeInterval(sender.tag)
        Settings.updateInterval = interval
        monitor.setInterval(Settings.updateInterval)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            try? service.unregister()
        case .notRegistered, .notFound, .requiresApproval:
            try? service.register()
        @unknown default:
            break
        }
    }

    @objc private func openDiagnostics() {
        let controller = diagnosticsController ?? DiagnosticsWindowController()
        diagnosticsController = controller
        controller.setRefreshHandler { [weak self] in
            self?.monitor.refresh()
            self?.refreshDiagnostics()
        }
        refreshDiagnostics()
    }

    private func refreshDiagnostics() {
        let data = DiagnosticsData(
            reading: lastReading,
            smcOpen: monitor.isSMCOpen,
            mode: Settings.displayMode,
            interval: Settings.updateInterval,
            appVersion: Self.appVersion
        )
        diagnosticsController?.display(report: makeDiagnosticsText(data))
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

// SPDX-License-Identifier: MIT

import AppKit
import Foundation

/// Snapshot of everything the diagnostics window shows. Pure data so the
/// report text is unit-testable without a window.
struct DiagnosticsData: Equatable, Sendable {
    let reading: TemperatureReading
    let smcOpen: Bool
    let mode: DisplayMode
    let interval: TimeInterval
    let appVersion: String
}

/// Builds the diagnostics report text. Pure function (unit-tested).
func makeDiagnosticsText(_ data: DiagnosticsData) -> String {
    func tempText(_ value: Double?, key: String?) -> String {
        guard let value else {
            return "-- (\(L10n.t("diag.noSignal")))"
        }
        // POSIX locale keeps the decimal point stable across user locales
        // (deterministic output for issue reports). The raw SMC key in
        // brackets is locale-independent provenance, always shown.
        let precise = String(
            format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value
        )
        if let key {
            return "\(precise)°C [\(key)]"
        }
        return "\(precise)°C"
    }
    let smcLine = data.smcOpen ? L10n.t("diag.smc.open") : L10n.t("diag.smc.closed")
    let lines = [
        "EveryTMP \(data.appVersion)",
        "\(L10n.t("diag.system")): \(SystemInfo.chipName) / \(SystemInfo.modelIdentifier)",
        "\(L10n.t("diag.os")): \(SystemInfo.osVersionString)",
        "\(L10n.t("diag.smc")): \(smcLine)",
        "\(L10n.t("diag.cpu")): \(tempText(data.reading.cpu, key: data.reading.cpuKey))",
        "\(L10n.t("diag.gpu")): \(tempText(data.reading.gpu, key: data.reading.gpuKey))",
        "\(L10n.f("diag.mode", data.mode.title))",
        "\(L10n.f("diag.interval", L10n.f("menu.interval.seconds", Int(data.interval))))",
        "",
        L10n.t("diag.note"),
    ]
    return lines.joined(separator: "\n")
}

/// Minimal programmatic diagnostics window (no xib/nib to get stale).
/// Owned by the AppDelegate for the app's lifetime; creating the NSWindow
/// lazily keeps menu-bar-only runs allocation-free.
///
/// Main-actor bound: every method is called from the main thread only
/// (AppDelegate callbacks and button actions).
@MainActor
final class DiagnosticsWindowController {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var onRefresh: (() -> Void)?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func setRefreshHandler(_ handler: @escaping () -> Void) {
        onRefresh = handler
    }

    func display(report: String) {
        if window == nil {
            buildWindow()
        }
        textView?.string = report
        guard let window else { return }
        window.title = L10n.t("diag.title")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("diag.title")
        window.center()
        window.isReleasedWhenClosed = false

        let content = window.contentView!
        content.autoresizesSubviews = true

        let scrollView = NSScrollView(frame: content.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        content.addSubview(scrollView)

        let refreshButton = NSButton(
            title: L10n.t("diag.refresh"),
            target: self,
            action: #selector(refreshAction)
        )
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: content.bounds.width - 220, y: 12, width: 100, height: 28)
        refreshButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(refreshButton)

        let closeButton = NSButton(
            title: L10n.t("diag.close"),
            target: self,
            action: #selector(closeAction)
        )
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: content.bounds.width - 110, y: 12, width: 100, height: 28)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(closeButton)

        // Keep the text clear of the button row.
        scrollView.frame = NSRect(
            x: 0, y: 48,
            width: content.bounds.width, height: content.bounds.height - 48
        )

        self.window = window
        self.textView = textView
    }

    @objc private func refreshAction() {
        onRefresh?()
    }

    @objc private func closeAction() {
        window?.close()
    }
}

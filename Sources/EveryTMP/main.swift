// SPDX-License-Identifier: MIT

import AppKit
import Foundation

// CLI mode: read every known SMC key once, print the results, and exit.
// Useful for issue reports and automated verification (mirrors the
// --print-diagnostics convention of the sibling Save battery app).
let arguments = CommandLine.arguments
if arguments.contains("--probe") {
    let smc = SMCService()
    if !smc.open() {
        print("SMC: open FAILED (no AppleSMC service)")
        exit(1)
    }
    for key in SMCKeys.cpuCandidates {
        if let value = smc.readCelsius(key: key) {
            print("CPU \(key): \(String(format: "%.2f", value)) C")
        } else {
            print("CPU \(key): unreadable")
        }
    }
    for key in SMCKeys.gpuCandidates {
        if let value = smc.readCelsius(key: key) {
            print("GPU \(key): \(String(format: "%.2f", value)) C")
        } else {
            print("GPU \(key): unreadable")
        }
    }
    print("chip: \(SystemInfo.chipName) (\(SystemInfo.modelIdentifier))")
    print("os: \(SystemInfo.osVersionString)")
    smc.close()
    exit(0)
}

// Menu bar resident app. The accessory policy keeps the app out of the Dock
// before any window is created, so the user never sees a Dock icon at all.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// SPDX-License-Identifier: MIT

import Foundation

/// Read-only machine information for diagnostics. No data leaves the Mac.
enum SystemInfo {
    /// e.g. "Apple M3 Ultra"; falls back to the model identifier.
    static var chipName: String {
        if let brand = sysctlString("machdep.cpu.brand_string"),
           !brand.trimmingCharacters(in: .whitespaces).isEmpty {
            return brand
        }
        return sysctlString("hw.model") ?? "unknown"
    }

    static var modelIdentifier: String {
        sysctlString("hw.model") ?? "unknown"
    }

    static var osVersionString: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// True when running on Apple Silicon (the only supported sensor path).
    static var isAppleSilicon: Bool {
        chipName.contains("Apple")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}

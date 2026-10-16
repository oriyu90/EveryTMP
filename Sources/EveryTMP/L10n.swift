// SPDX-License-Identifier: MIT

import Foundation

/// Localization helper. All user-facing strings go through this type so that
/// Japanese and English stay fully in sync via Localizable.strings.
///
/// The bundle is resolved on every call from the current preferred
/// languages, so a system language switch mid-run is picked up without
/// restarting — this matters for an app designed to run for a year.
/// Resolution is two path lookups (no caching, no shared mutable state),
/// which keeps this type safe to call from any thread.
enum L10n {
    private static func bundle() -> Bundle {
        let first = Locale.preferredLanguages.first?
            .split(separator: "-").first.map(String.init) ?? "en"
        let language = (first == "ja") ? "ja" : "en"
        let main = Bundle.main
        if let path = main.path(forResource: language, ofType: "lproj"),
           let lproj = Bundle(path: path) {
            return lproj
        }
        // Fall back to English, then to the main bundle (which returns keys).
        if language != "en",
           let path = main.path(forResource: "en", ofType: "lproj"),
           let lproj = Bundle(path: path) {
            return lproj
        }
        return main
    }

    /// Returns the localized string for `key`, or the key itself when the
    /// table is missing (for example in unit test bundles).
    static func t(_ key: String) -> String {
        bundle().localizedString(forKey: key, value: key, table: nil)
    }

    /// Returns a localized, formatted string. Integer format specifiers
    /// use %ld (matching the .strings tables).
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }
}

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EveryTMP",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Minimal C shim for read-only AppleSMC access (no write path by design).
        .target(
            name: "CSMCShim",
            path: "Sources/CSMCShim",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "EveryTMP",
            dependencies: ["CSMCShim"],
            path: "Sources/EveryTMP"
        ),
        .testTarget(
            name: "EveryTMPTests",
            dependencies: ["EveryTMP"],
            path: "Tests/EveryTMPTests"
        )
    ]
)

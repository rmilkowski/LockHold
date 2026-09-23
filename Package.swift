// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LockHold",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LockHold", targets: ["LockHold"]),
        .executable(name: "LockHoldSleepHelper", targets: ["LockHoldSleepHelper"]),
    ],
    targets: [
        .target(
            name: "LockHoldCore",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "LockHold",
            dependencies: ["LockHoldCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "LockHoldSleepHelper",
            dependencies: ["LockHoldCore"],
            linkerSettings: [.linkedFramework("SystemConfiguration")]
        ),
        .testTarget(
            name: "LockHoldTests",
            dependencies: ["LockHold", "LockHoldCore"]
        ),
    ]
)

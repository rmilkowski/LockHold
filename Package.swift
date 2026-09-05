// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LockHold",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LockHold", targets: ["LockHold"])
    ],
    targets: [
        .executableTarget(
            name: "LockHold",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "LockHoldTests",
            dependencies: ["LockHold"]
        ),
    ]
)

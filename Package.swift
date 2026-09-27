// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShelfDemo",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "ShelfDemo", targets: ["ShelfDemo"]),
        .executable(name: "AmorDropClosedLidHelper", targets: ["AmorDropClosedLidHelper"]),
        .library(name: "ClosedLidCore", targets: ["ClosedLidCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ClosedLidCore",
            path: "Sources/ClosedLidCore"
        ),
        .executableTarget(
            name: "AmorDropClosedLidHelper",
            dependencies: ["ClosedLidCore"],
            path: "Sources/AmorDropClosedLidHelper"
        ),
        .executableTarget(
            name: "ShelfDemo",
            dependencies: ["ClosedLidCore"],
            path: "Sources/ShelfDemo",
            // The .icns is consumed only by the packaged .app bundle (copied
            // by scripts/build-private-app.sh). Excluding it here keeps SwiftPM
            // quiet and avoids embedding it in the SPM module's bundle.
            exclude: ["Resources/AppIcon.icns"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ShelfDemoTests",
            dependencies: ["ShelfDemo", "ClosedLidCore"],
            path: "Tests/ShelfDemoTests"
        ),
    ]
)

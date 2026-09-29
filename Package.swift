// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmorDrop",
    defaultLocalization: "en",
    platforms: [.macOS("15.6")],
    products: [
        .executable(name: "AmorDrop", targets: ["AmorDrop"]),
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
            name: "AmorDrop",
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
            name: "AmorDropTests",
            dependencies: ["AmorDrop", "ClosedLidCore"],
            path: "Tests/ShelfDemoTests"
        ),
    ]
)

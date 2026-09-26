// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShelfDemo",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ShelfDemo",
            dependencies: [],
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
            dependencies: ["ShelfDemo"],
            path: "Tests/ShelfDemoTests"
        ),
    ]
)

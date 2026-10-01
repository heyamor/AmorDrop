import Foundation

/// Installed apps must never depend on SwiftPM's absolute build-directory fallback.
/// Keep command-line SwiftPM builds working by looking beside their executable.
enum AppResources {
    static let bundle = resolve(in: Bundle(for: ResourceBundleAnchor.self))
    static let bundleName = "AmorDrop_AmorDrop.bundle"

    static func resolve(in mainBundle: Bundle) -> Bundle {
        let root = mainBundle.bundleURL
        if root.pathExtension.lowercased() == "app" {
            let resource = root.appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(bundleName, isDirectory: true)
            return Bundle(url: resource) ?? mainBundle
        }
        // XCTest loads the executable target into an xctest bundle next to its resources.
        let testBuildDirectory = root.pathExtension == "xctest" ? root.deletingLastPathComponent() : nil
        let candidates = [mainBundle.resourceURL, root,
                          mainBundle.executableURL?.deletingLastPathComponent(),
                          testBuildDirectory].compactMap { $0 }
        for directory in candidates {
            if let resource = Bundle(url: directory.appendingPathComponent(bundleName, isDirectory: true)) {
                return resource
            }
        }
        return mainBundle
    }
}

private final class ResourceBundleAnchor: NSObject {}

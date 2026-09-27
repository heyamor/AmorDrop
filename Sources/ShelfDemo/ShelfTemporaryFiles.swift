import Foundation

/// Files created by AmorDrop while staging non-file drag and clipboard data.
/// Keeping them in a dedicated subdirectory makes ownership explicit: shelf
/// cleanup must never infer ownership from a URL elsewhere in the system temp
/// directory.
enum ShelfTemporaryFiles {
    static var directoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AmorDrop", isDirectory: true)
            .appendingPathComponent("ShelfItems", isDirectory: true)
            .standardizedFileURL
    }

    @discardableResult
    static func prepareDirectory() -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return directoryURL
        } catch {
            NSLog("Shelf: failed to create temporary item directory: \(error)")
            return nil
        }
    }

    static func uniqueFileURL(extension fileExtension: String) -> URL? {
        guard let directory = prepareDirectory() else { return nil }
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return directory.appendingPathComponent(UUID().uuidString + suffix)
    }

    static func uniqueDirectoryURL() -> URL? {
        guard let directory = prepareDirectory() else { return nil }
        let child = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: child,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return child
        } catch {
            NSLog("Shelf: failed to create temporary item subdirectory: \(error)")
            return nil
        }
    }

    static func namedFileURL(_ name: String) -> URL? {
        guard let directory = prepareDirectory() else { return nil }
        return directory.appendingPathComponent(name)
    }

    static func owns(_ url: URL) -> Bool {
        let root = directoryURL.path
        let candidate = url.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else { return false }

        // Resolve symlinks before considering a path owned. This prevents a
        // link placed inside our temp folder from authorizing deletion of a
        // source file elsewhere.
        let resolvedRoot = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedCandidate.hasPrefix(resolvedRoot + "/")
    }

    /// Removes a staged file/directory only when both the shelf row carries
    /// the ownership marker and its resolved location is inside our private
    /// staging directory. Empty per-promise directories are pruned afterward.
    @discardableResult
    static func removeIfOwned(_ url: URL, markedOwned: Bool) -> Bool {
        guard markedOwned, owns(url) else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        do {
            try fm.removeItem(at: url)
        } catch {
            NSLog("Shelf: failed to remove staged temporary item: \(error)")
            return false
        }

        var parent = url.deletingLastPathComponent()
        while parent.standardizedFileURL.path != directoryURL.path,
              owns(parent),
              let contents = try? fm.contentsOfDirectory(atPath: parent.path),
              contents.isEmpty {
            try? fm.removeItem(at: parent)
            parent = parent.deletingLastPathComponent()
        }
        return true
    }
}

import Foundation

enum ZipArchive {
    static func create(sources: [URL], destination: URL) throws {
        guard !sources.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("AmorDropZIP-\(UUID())", isDirectory: true)
        let temporaryArchive = destination.deletingLastPathComponent().appendingPathComponent(".AmorDrop-\(UUID()).zip")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: temporaryArchive)
        }

        var names: [String] = []
        for source in sources {
            let staged = UniqueDestination.url(preferred: staging.appendingPathComponent(source.lastPathComponent))
            do {
                try fm.linkItem(at: source, to: staged)
            } catch {
                try fm.copyItem(at: source, to: staged)
            }
            names.append(staged.lastPathComponent)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-r", temporaryArchive.path, "--"] + names
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Drain while zip runs, avoiding a full pipe blocking a large archive.
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? "ZIP failed"
            throw NSError(domain: "AmorDrop.ZIP", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail])
        }

        // Preserve the previous destination until the new archive is complete,
        // including when the selected destination is itself one of the sources.
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporaryArchive)
        } else {
            try fm.moveItem(at: temporaryArchive, to: destination)
        }
    }
}

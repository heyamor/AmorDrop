import XCTest
@testable import ShelfDemo

final class ZipArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AmorDropZIPTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func extract(_ archive: URL) throws -> URL {
        let destination = root.appendingPathComponent("extracted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archive.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return destination
    }

    func test_zip_includes_duplicate_names_and_chinese_folder_without_changing_sources() throws {
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let folder = root.appendingPathComponent("资料文件夹")
        for directory in [first, second, folder] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let a = first.appendingPathComponent("sample.txt")
        let b = second.appendingPathComponent("sample.txt")
        let c = folder.appendingPathComponent("中文.txt")
        try Data("first".utf8).write(to: a)
        try Data("second".utf8).write(to: b)
        try Data("nested".utf8).write(to: c)
        let archive = root.appendingPathComponent("archive.zip")
        try ZipArchive.create(sources: [a, b, folder], destination: archive)
        let output = try extract(archive)
        for (name, contents) in [("sample.txt", "first"), ("sample (1).txt", "second"), ("资料文件夹/中文.txt", "nested")] {
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent(name), encoding: .utf8), contents)
        }
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: c, encoding: .utf8), "nested")
    }

    func test_failure_preserves_existing_destination() throws {
        let archive = root.appendingPathComponent("existing.zip")
        let original = Data("existing archive".utf8)
        try original.write(to: archive)
        XCTAssertThrowsError(try ZipArchive.create(sources: [root.appendingPathComponent("missing")], destination: archive))
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    func test_archive_can_replace_itself_after_safely_staging_original() throws {
        let archive = root.appendingPathComponent("original.zip")
        let original = Data("original archive bytes".utf8)
        try original.write(to: archive)
        try ZipArchive.create(sources: [archive], destination: archive)
        let output = try extract(archive)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("original.zip")), original)
    }
}

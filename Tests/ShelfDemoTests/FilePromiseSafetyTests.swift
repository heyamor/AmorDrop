import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import AmorDrop

final class FilePromiseSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AmorDropPromiseTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    private func write(source: URL, destination: URL) -> Error? {
        let view = DragInitiatorView()
        let promise = FileURLPromiseProvider(fileType: UTType.data.identifier, delegate: view)
        promise.userInfo = source
        var result: Error?
        view.filePromiseProvider(promise, writePromiseTo: destination) { result = $0 }
        return result
    }

    func test_same_destination_never_deletes_source() async throws {
        let source = root.appendingPathComponent("原文件.txt")
        let contents = Data("must survive".utf8)
        try contents.write(to: source)
        let error = await write(source: source, destination: source)
        XCTAssertNotNil(error)
        XCTAssertEqual(try Data(contentsOf: source), contents)
    }

    func test_collision_preserves_both_files() async throws {
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("existing.txt")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: destination)
        let error = await write(source: source, destination: destination)
        XCTAssertNotNil(error)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
    }

    func test_copy_supports_unicode_long_names_and_folders() async throws {
        let source = root.appendingPathComponent("中文-" + String(repeating: "a", count: 180) + ".txt")
        let folder = root.appendingPathComponent("文件夹", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("file bytes".utf8).write(to: source)
        try Data("nested bytes".utf8).write(to: folder.appendingPathComponent("内容.txt"))
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for url in [source, folder] {
            let destination = output.appendingPathComponent(url.lastPathComponent)
            let error = await write(source: url, destination: destination)
            XCTAssertNil(error)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        }
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent(source.lastPathComponent)), Data("file bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("文件夹/内容.txt")), Data("nested bytes".utf8))
    }

    func test_promise_exposes_real_file_url_for_other_apps() async throws {
        let source = root.appendingPathComponent("上传测试.pdf")
        try Data("fixture".utf8).write(to: source)
        await MainActor.run {
            let view = DragInitiatorView()
            let promise = FileURLPromiseProvider(fileType: UTType.pdf.identifier, delegate: view)
            promise.userInfo = source
            XCTAssertTrue(promise.writableTypes(for: .general).contains(.fileURL))
            XCTAssertEqual(promise.pasteboardPropertyList(forType: .fileURL) as? String, source.absoluteString)
        }
    }
}

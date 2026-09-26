import XCTest
@testable import ShelfDemo

final class ShelfLifecycleTests: XCTestCase {
    func test_multiple_shelves_clear_undo_and_close_preserve_files() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AmorDropLifecycleTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("中文.txt")
        try Data("original".utf8).write(to: source)
        await MainActor.run {
            let manager = ShelfManager(store: ShelfStore(storeURL: root.appendingPathComponent("store.json")))
            let first = manager.createShelf()
            let second = manager.createShelf()
            let item = ShelfItem(type: .file, fileURL: source)
            manager.addItem(item, to: first)
            manager.addItem(item, to: second)
            XCTAssertEqual(manager.items(of: first).count, 1)
            XCTAssertEqual(manager.items(of: second).count, 1)
            manager.clear(shelfID: first)
            XCTAssertTrue(manager.items(of: first).isEmpty)
            XCTAssertEqual(manager.items(of: second).count, 1)
            manager.performUndo()
            XCTAssertEqual(manager.items(of: first).count, 1)
            manager.removeShelf(id: first)
            XCTAssertNil(manager.shelf(id: first))
            XCTAssertEqual(manager.items(of: second).count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func test_expiry_never_deletes_external_temporary_files_and_respects_pin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AmorDropExpiryTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("external.txt")
        try Data("keep".utf8).write(to: source)
        await MainActor.run {
            let manager = ShelfManager(store: ShelfStore(storeURL: root.appendingPathComponent("store.json")))
            let expired = manager.createShelf()
            let pinned = manager.createShelf()
            let item = ShelfItem(type: .file, fileURL: source, createdAt: Date(timeIntervalSinceNow: -3 * 86_400))
            manager.addItem(item, to: expired)
            manager.addItem(item, to: pinned)
            manager.setShelfPinned(id: pinned, true)
            XCTAssertEqual(manager.pruneShelves(olderThanDays: 1), [expired])
            XCTAssertNotNil(manager.shelf(id: pinned))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }
}

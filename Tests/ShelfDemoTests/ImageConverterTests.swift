import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import AmorDrop

final class ImageConverterTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConvTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes a 10x10 solid-red PNG to `tempDir/<name>.png` and returns its URL.
    private func makeSyntheticPNG(named name: String) throws -> URL {
        let url = tempDir.appendingPathComponent("\(name).png")
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "test", code: -1) }
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        guard let cg = ctx.makeImage() else { throw NSError(domain: "test", code: -2) }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw NSError(domain: "test", code: -3) }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func test_png_to_jpeg_writes_sibling_file() throws {
        let src = try makeSyntheticPNG(named: "input")
        let result = try ImageConverter.convert(source: src, target: .jpeg)
        XCTAssertEqual(result.lastPathComponent, "input.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        // Verify the output is a real JPEG.
        let outSrc = CGImageSourceCreateWithURL(result as CFURL, nil)
        XCTAssertNotNil(outSrc)
        let type = outSrc.flatMap { CGImageSourceGetType($0) } as String?
        XCTAssertEqual(type, UTType.jpeg.identifier)
    }

    func test_png_to_jpeg_collision_appends_suffix() throws {
        let src = try makeSyntheticPNG(named: "input")
        // Pre-occupy "input.jpg".
        try Data().write(to: tempDir.appendingPathComponent("input.jpg"))

        let result = try ImageConverter.convert(source: src, target: .jpeg)

        XCTAssertEqual(result.lastPathComponent, "input (1).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }

    func test_throws_sourceMissing_when_file_absent() {
        let bogus = tempDir.appendingPathComponent("nope.png")
        XCTAssertThrowsError(
            try ImageConverter.convert(source: bogus, target: .jpeg)
        ) { error in
            XCTAssertEqual(error as? ConversionError, .sourceMissing)
        }
    }

    func test_destination_falls_back_to_cache_when_dir_unwritable() throws {
        // Make the parent dir read-only so the sibling write fails with EACCES.
        let lockedDir = tempDir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(
            at: lockedDir, withIntermediateDirectories: true
        )
        let src = lockedDir.appendingPathComponent("input.png")
        let realPNG = try makeSyntheticPNG(named: "real")
        try FileManager.default.copyItem(at: realPNG, to: src)
        // Prepare the fixture before removing directory write access.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: lockedDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: lockedDir.path
            )
        }
        let result = try ImageConverter.convert(source: src, target: .jpeg)
        defer { try? FileManager.default.removeItem(at: result) }
        XCTAssertTrue(
            result.path.contains("Caches/AmorDrop/Converted"),
            "Expected fallback dir, got \(result.path)"
        )
        XCTAssertEqual(try Data(contentsOf: src), try Data(contentsOf: realPNG))
        let output = CGImageSourceCreateWithURL(result as CFURL, nil)
        XCTAssertEqual(output.flatMap { CGImageSourceGetType($0) } as String?, UTType.jpeg.identifier)
    }

    func test_jpeg_to_png_preserves_source_and_writes_real_png() throws {
        let original = try makeSyntheticPNG(named: "roundtrip")
        let jpeg = try ImageConverter.convert(source: original, target: .jpeg)
        let before = try Data(contentsOf: jpeg)
        let png = try ImageConverter.convert(source: jpeg, target: .png)
        let output = CGImageSourceCreateWithURL(png as CFURL, nil)
        XCTAssertEqual(output.flatMap { CGImageSourceGetType($0) } as String?, UTType.png.identifier)
        XCTAssertEqual(try Data(contentsOf: jpeg), before)
        XCTAssertEqual(ShelfItem.readImagePixelSize(url: png), CGSize(width: 10, height: 10))
    }
}

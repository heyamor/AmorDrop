import Foundation
import XCTest
@testable import AmorDrop

final class AppResourcesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func makeBundle(at url: URL, app: Bool = false) throws -> Bundle {
        let infoDirectory = app ? url.appendingPathComponent("Contents") : url
        try FileManager.default.createDirectory(at: infoDirectory, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.amordrop.resources",
                                   "CFBundlePackageType": app ? "APPL" : "BNDL",
                                   "CFBundleName": "ResourceFixture"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoDirectory.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: url))
    }

    func testInstalledAppLoadsResourcesFromContentsResources() throws {
        let app = try makeBundle(at: root.appendingPathComponent("AmorDrop.app"), app: true)
        let expected = app.bundleURL.appendingPathComponent("Contents/Resources/\(AppResources.bundleName)", isDirectory: true)
        _ = try makeBundle(at: expected)
        XCTAssertEqual(AppResources.resolve(in: app).bundleURL, expected)
    }

    func testInstalledAppDoesNotUseBundleAtAppRoot() throws {
        let app = try makeBundle(at: root.appendingPathComponent("AmorDrop.app"), app: true)
        _ = try makeBundle(at: app.bundleURL.appendingPathComponent(AppResources.bundleName, isDirectory: true))
        XCTAssertEqual(AppResources.resolve(in: app).bundleURL, app.bundleURL)
    }

    func testMissingInstalledResourcesFallsBackWithoutCrash() throws {
        let app = try makeBundle(at: root.appendingPathComponent("AmorDrop.app"), app: true)
        XCTAssertEqual(AppResources.resolve(in: app).bundleURL, app.bundleURL)
    }

    func testInstalledAppDoesNotUseAdjacentDevelopmentBundle() throws {
        let app = try makeBundle(at: root.appendingPathComponent("AmorDrop.app"), app: true)
        _ = try makeBundle(at: root.appendingPathComponent(AppResources.bundleName, isDirectory: true))
        XCTAssertEqual(AppResources.resolve(in: app).bundleURL, app.bundleURL)
    }

    func testSwiftPMBuildLoadsAdjacentResourceBundle() throws {
        let executableBundle = try makeBundle(at: root.appendingPathComponent("debug"))
        let expected = executableBundle.bundleURL.appendingPathComponent(AppResources.bundleName, isDirectory: true)
        _ = try makeBundle(at: expected)
        XCTAssertEqual(AppResources.resolve(in: executableBundle).bundleURL, expected)
    }

    func testXCTestBuildLoadsResourcesBesideTestBundle() throws {
        let testBundle = try makeBundle(at: root.appendingPathComponent("AmorDropTests.xctest"))
        let expected = root.appendingPathComponent(AppResources.bundleName, isDirectory: true)
        _ = try makeBundle(at: expected)
        XCTAssertEqual(AppResources.resolve(in: testBundle).bundleURL, expected)
    }

    func testBuiltResourcesContainMenuIconAndChineseLocalization() {
        XCTAssertNotNil(AppResources.bundle.url(forResource: "MenuBarIcon", withExtension: "pdf"))
        XCTAssertTrue(AppResources.bundle.localizations.contains { $0.lowercased() == "zh-hans" })
    }
}

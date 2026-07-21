import Foundation
import XCTest
@testable import WhisperKey

final class TextInserterTests: XCTestCase {
    func testElectronAppsPreferPasteboardBeforeAX() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let frameworkURL = appURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try FileManager.default.createDirectory(at: frameworkURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appURL) }

        XCTAssertEqual(TextInserter.preferredStrategy(for: appURL), .pasteboard)
    }

    func testOtherAppsKeepStandardInsertionCascade() {
        XCTAssertEqual(TextInserter.preferredStrategy(for: nil), .standard)
    }
}

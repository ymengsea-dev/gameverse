//
//  StorageScannerTests.swift
//  GVEngineTests
//

import XCTest
@testable import GVEngine

final class StorageScannerTests: XCTestCase {
    func testCountsFilesRecursively() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(path: "Content/DLC")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: root.appending(path: "game.exe"))
        try Data(repeating: 2, count: 2_048).write(to: nested.appending(path: "archive.bin"))

        XCTAssertEqual(try StorageScanner.logicalSize(of: root), 3_072)
    }

    func testCountsSingleFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 3, count: 512).write(to: file)

        XCTAssertEqual(try StorageScanner.logicalSize(of: file), 512)
    }
}

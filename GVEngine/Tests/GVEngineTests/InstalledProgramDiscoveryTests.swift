//
//  InstalledProgramDiscoveryTests.swift
//  GVEngineTests
//

import XCTest
@testable import GVEngine

final class InstalledProgramDiscoveryTests: XCTestCase {
    func testDiscoversSharedAndPerUserStartMenuShortcutsWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = Bottle(bottleUrl: root)
        let shared = root.appending(
            path: "drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Steam"
        )
        let user = root.appending(
            path: "drive_c/users/gameverse/AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
        )
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: shared.appending(path: "Steam.lnk").path, contents: Data()
        ))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: user.appending(path: "steam.LNK").path, contents: Data()
        ))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: user.appending(path: "Game Tools.lnk").path, contents: Data()
        ))

        let shortcuts = InstalledProgramDiscovery.discoverShortcuts(in: bottle)

        XCTAssertEqual(shortcuts.map(\.name), ["Game Tools", "Steam"])
    }
}

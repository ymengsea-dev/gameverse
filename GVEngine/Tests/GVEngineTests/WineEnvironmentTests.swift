//
//  WineEnvironmentTests.swift
//  GVEngine
//
//  This file is part of GameVerse, a fork of Whisky
//  (https://github.com/Whisky-App/Whisky) by Isaac Marovitz.
//
//  GameVerse is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  GameVerse is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with GameVerse.
//  If not, see https://www.gnu.org/licenses/.
//

import XCTest
@testable import GVEngine

final class WineEnvironmentTests: XCTestCase {
    func testTerminalCommandExportsPrefixExactlyOnce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bottle = Bottle(bottleUrl: dir)
        let cmd = Wine.generateTerminalEnvironmentCommand(bottle: bottle)

        let prefixExports = cmd.components(separatedBy: "export WINEPREFIX=").count - 1
        XCTAssertEqual(prefixExports, 1)
        XCTAssertTrue(cmd.contains("export WINEDEBUG=\"fixme-all,err+all,warn+module\""))
    }
}

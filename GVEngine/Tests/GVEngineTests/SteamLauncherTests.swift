//
//  SteamLauncherTests.swift
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

final class SteamLauncherTests: XCTestCase {
    func testLaunchArgsApplaunchAppendedWithLaunchArgs() {
        let args = SteamLauncher.launchArgs(appId: 440)

        XCTAssertEqual(args, SteamFixup.launchArgs + ["-silent", "-applaunch", "440"])
    }

    func testSteamExeURLIsInsideBottleDriveC() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bottle = Bottle(bottleUrl: dir)

        let url = SteamLauncher.steamExeURL(bottle: bottle)

        XCTAssertTrue(url.path(percentEncoded: false).hasSuffix(
            "drive_c/Program Files (x86)/Steam/steam.exe"
        ))
    }
}

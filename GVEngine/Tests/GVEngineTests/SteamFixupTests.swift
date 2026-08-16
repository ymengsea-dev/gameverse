//
//  SteamFixupTests.swift
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

final class SteamFixupTests: XCTestCase {
    func testLaunchArgsForceSoftwareCEFAndDoNotBlockUpdates() {
        // CEF software-compositing flags fix the black-screen UI…
        XCTAssertEqual(
            SteamFixup.launchArgsString,
            "-cef-force-32bit -cef-disable-gpu-compositing -cef-disable-gpu"
        )
        // …and NONE of the old update-blocking flags may reappear, or Steam can
        // wedge itself half-updated (32-bit steamui.dll under a 64-bit client).
        for blocked in ["-noverifyfiles", "-nobootstrapupdate", "-skipinitialbootstrap", "-norepairfiles"] {
            XCTAssertFalse(SteamFixup.launchArgs.contains(blocked), "\(blocked) must not be a launch arg")
        }
    }

    func testIsSteamMatchesCaseInsensitively() {
        XCTAssertTrue(SteamFixup.isSteam(url: URL(filePath: "/c/Program Files (x86)/Steam/steam.exe")))
        XCTAssertTrue(SteamFixup.isSteam(url: URL(filePath: "/c/Steam/Steam.exe")))
        XCTAssertFalse(SteamFixup.isSteam(url: URL(filePath: "/c/Games/game.exe")))
    }

    func testRepairRemovesSteamCfgUpdateInhibitor() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appending(path: "steam.cfg")
        try "BootStrapperInhibitAll=enable".write(to: cfg, atomically: true, encoding: .utf8)

        // repair() also touches Wine/lib via the installer; that's a no-op when
        // the runtime isn't installed. The steam.cfg removal is what we assert.
        try? SteamFixup.repair(steamRoot: dir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: cfg.path(percentEncoded: false)))
    }
}

//
//  SteamLibraryTests.swift
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

final class SteamLibraryTests: XCTestCase {
    private func makeFixtureBottle() throws -> (Bottle, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let steamRoot = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
        let steamApps = steamRoot.appending(path: "steamapps")
        let common = steamApps.appending(path: "common").appending(path: "Team Fortress 2")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: common.appending(path: "hl2.exe"))

        let libraryFolders = #"""
        "libraryfolders"
        {
            "0"
            {
                "path"		"C:\\Program Files (x86)\\Steam"
                "apps"
                {
                    "440"		"100000"
                }
            }
        }
        """#
        try libraryFolders.write(
            to: steamApps.appending(path: "libraryfolders.vdf"), atomically: true, encoding: .utf8
        )

        let appManifest = #"""
        "AppState"
        {
            "appid"		"440"
            "name"		"Team Fortress 2"
            "installdir"		"Team Fortress 2"
        }
        """#
        try appManifest.write(
            to: steamApps.appending(path: "appmanifest_440.acf"), atomically: true, encoding: .utf8
        )

        let bottle = Bottle(bottleUrl: dir)
        return (bottle, dir)
    }

    func testDiscoversGameFromAppManifest() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let games = SteamLibrary.discoverGames(in: bottle)

        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.appId, 440)
        XCTAssertEqual(games.first?.name, "Team Fortress 2")
        XCTAssertTrue(games.first?.installDir.path(percentEncoded: false).hasSuffix(
            "steamapps/common/Team Fortress 2"
        ) ?? false)
    }

    func testReturnsEmptyWhenNoSteamInstalled() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bottle = Bottle(bottleUrl: dir)
        XCTAssertEqual(SteamLibrary.discoverGames(in: bottle), [])
    }

    func testHidesGameWhenInstallDirectoryWasDeleted() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installDir = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "steamapps")
            .appending(path: "common")
            .appending(path: "Team Fortress 2")
        try FileManager.default.removeItem(at: installDir)

        XCTAssertEqual(SteamLibrary.discoverGames(in: bottle), [])
    }

    func testHidesGameWhenOnlyEmptyInstallDirectoryRemains() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }
        let executable = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "steamapps")
            .appending(path: "common")
            .appending(path: "Team Fortress 2")
            .appending(path: "hl2.exe")
        try FileManager.default.removeItem(at: executable)

        XCTAssertEqual(SteamLibrary.discoverGames(in: bottle), [])
    }

    func testResolvesCachedIconWhenPresent() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let librarycache = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "appcache")
            .appending(path: "librarycache")
        try FileManager.default.createDirectory(at: librarycache, withIntermediateDirectories: true)
        let iconFile = librarycache.appending(path: "440_icon.jpg")
        try Data().write(to: iconFile)

        let games = SteamLibrary.discoverGames(in: bottle)

        XCTAssertEqual(
            games.first?.iconURL?.resolvingSymlinksInPath(),
            iconFile.resolvingSymlinksInPath()
        )
    }

    func testResolvesModernHashedIconWhenPresent() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appCache = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "appcache")
            .appending(path: "librarycache")
            .appending(path: "440")
        try FileManager.default.createDirectory(at: appCache, withIntermediateDirectories: true)
        let iconFile = appCache.appending(path: "f568912870a4684f9ec76277a1a404dda6bab213.jpg")
        try Data().write(to: iconFile)
        try Data().write(to: appCache.appending(path: "library_600x900.jpg"))

        let games = SteamLibrary.discoverGames(in: bottle)

        XCTAssertEqual(
            games.first?.iconURL?.resolvingSymlinksInPath(),
            iconFile.resolvingSymlinksInPath()
        )
    }

    func testUsesModernCoverWhenHashedIconIsUnavailable() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appCache = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "appcache")
            .appending(path: "librarycache")
            .appending(path: "440")
        try FileManager.default.createDirectory(at: appCache, withIntermediateDirectories: true)
        let coverFile = appCache.appending(path: "library_600x900.jpg")
        try Data().write(to: coverFile)

        let games = SteamLibrary.discoverGames(in: bottle)

        XCTAssertEqual(games.first?.iconURL, coverFile)
    }

    func testHidesSteamworksCommonRedistributables() throws {
        let (bottle, dir) = try makeFixtureBottle()
        defer { try? FileManager.default.removeItem(at: dir) }
        let steamApps = dir
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "steamapps")
        let redistributablesManifest = #"""
        "AppState"
        {
            "appid"        "228980"
            "name"         "Steamworks Common Redistributables"
            "installdir"   "Steamworks Shared"
        }
        """#
        try redistributablesManifest.write(
            to: steamApps.appending(path: "appmanifest_228980.acf"),
            atomically: true,
            encoding: .utf8
        )

        let games = SteamLibrary.discoverGames(in: bottle)

        XCTAssertEqual(games.map(\.appId), [440])
    }
}

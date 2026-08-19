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
    func testLaunchArgsKeepShimInstalledAndUseSupportedCEFOptions() {
        XCTAssertEqual(
            SteamFixup.launchArgsString,
            "-no-cef-sandbox -cef-disable-gpu -cef-single-process -noverifyfiles"
        )
        for blocked in ["-nobootstrapupdate", "-skipinitialbootstrap", "-norepairfiles"] {
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

    func testRepairInstallsShimAndPreservesGenuineHelper() throws {
        let steamRoot = try makeSteamRoot()
        defer { removeTestPrefix(containing: steamRoot) }
        let helper = webHelper(in: steamRoot)
        let backup = helper.deletingLastPathComponent().appending(path: "steamwebhelper_real.exe")
        let genuine = Data("valve-helper-v1".utf8)
        try genuine.write(to: helper)

        try SteamFixup.repair(steamRoot: steamRoot)

        XCTAssertEqual(try Data(contentsOf: backup), genuine)
        XCTAssertNotEqual(try Data(contentsOf: helper), genuine)
    }

    func testRepairIsIdempotentAndRefreshesBackupAfterSteamUpdate() throws {
        let steamRoot = try makeSteamRoot()
        defer { removeTestPrefix(containing: steamRoot) }
        let helper = webHelper(in: steamRoot)
        let backup = helper.deletingLastPathComponent().appending(path: "steamwebhelper_real.exe")
        try Data("valve-helper-v1".utf8).write(to: helper)

        try SteamFixup.repair(steamRoot: steamRoot)
        let installedShim = try Data(contentsOf: helper)
        try SteamFixup.repair(steamRoot: steamRoot)
        XCTAssertEqual(try Data(contentsOf: helper), installedShim)
        XCTAssertEqual(try Data(contentsOf: backup), Data("valve-helper-v1".utf8))

        let updatedGenuine = Data("valve-helper-v2".utf8)
        try updatedGenuine.write(to: helper)
        try SteamFixup.repair(steamRoot: steamRoot)

        XCTAssertEqual(try Data(contentsOf: helper), installedShim)
        XCTAssertEqual(try Data(contentsOf: backup), updatedGenuine)
    }

    func testRepairClearsHTMLCacheForEveryWineUser() throws {
        let steamRoot = try makeSteamRoot()
        defer { removeTestPrefix(containing: steamRoot) }
        let driveC = steamRoot.deletingLastPathComponent().deletingLastPathComponent()
        for user in ["mac-user", "steamuser"] {
            let cache = driveC
                .appending(path: "users/\(user)/AppData/Local/Steam/htmlcache")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("stale".utf8).write(to: cache.appending(path: "cache.bin"))
        }

        try SteamFixup.repair(steamRoot: steamRoot)

        for user in ["mac-user", "steamuser"] {
            let cache = driveC
                .appending(path: "users/\(user)/AppData/Local/Steam/htmlcache")
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
        }
    }

    private func makeSteamRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "drive_c/Program Files (x86)/Steam")
        let cef = root.appending(path: "bin/cef/cef.win64")
        try FileManager.default.createDirectory(at: cef, withIntermediateDirectories: true)
        return root
    }

    private func webHelper(in steamRoot: URL) -> URL {
        steamRoot.appending(path: "bin/cef/cef.win64/steamwebhelper.exe")
    }

    private func removeTestPrefix(containing steamRoot: URL) {
        let temporaryRoot = steamRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}

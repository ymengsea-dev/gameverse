//
//  BottleSettingsTests.swift
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

final class BottleSettingsTests: XCTestCase {
    func testDecodeFromMissingFileCreatesAndPersistsDefaults() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let metadataURL = dir.appending(path: "Metadata").appendingPathExtension("plist")

        let settings = try BottleSettings.decode(from: metadataURL)

        XCTAssertEqual(settings, BottleSettings())
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))
    }

    func testDecodeRoundTripsExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let metadataURL = dir.appending(path: "Metadata").appendingPathExtension("plist")

        var original = BottleSettings()
        original.name = "My Bottle"
        try original.encode(to: metadataURL)

        let decoded = try BottleSettings.decode(from: metadataURL)
        XCTAssertEqual(decoded.name, "My Bottle")
    }

    func testEnvironmentDoesNotDisableSteamClientService() {
        let settings = BottleSettings()
        var environment: [String: String] = [:]

        settings.environmentVariables(wineEnv: &environment)

        let overrides = environment["WINEDLLOVERRIDES"] ?? ""
        XCTAssertFalse(overrides.lowercased().contains("steamservice"))
        XCTAssertTrue(overrides.contains("mscoree="))
    }
}

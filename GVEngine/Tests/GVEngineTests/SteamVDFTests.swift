//
//  SteamVDFTests.swift
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

final class SteamVDFTests: XCTestCase {
    func testParsesFlatObject() throws {
        let text = #"""
        "AppState"
        {
            "appid"		"440"
            "name"		"Team Fortress 2"
        }
        """#

        let root = SteamVDF.parse(text)
        guard case let .object(appState)? = root["AppState"] else {
            return XCTFail("expected AppState object")
        }
        guard case let .string(appid)? = appState["appid"] else {
            return XCTFail("expected appid string")
        }
        XCTAssertEqual(appid, "440")
        guard case let .string(name)? = appState["name"] else {
            return XCTFail("expected name string")
        }
        XCTAssertEqual(name, "Team Fortress 2")
    }

    func testUnescapesDoubledBackslashes() throws {
        let text = #"""
        "libraryfolders"
        {
            "0"
            {
                "path"		"C:\\Program Files (x86)\\Steam"
            }
        }
        """#

        let root = SteamVDF.parse(text)
        guard case let .object(libraryFolders)? = root["libraryfolders"],
              case let .object(entry0)? = libraryFolders["0"],
              case let .string(path)? = entry0["path"] else {
            return XCTFail("failed to parse nested path")
        }
        XCTAssertEqual(path, "C:\\Program Files (x86)\\Steam")
    }

    func testParsesMultipleNestedApps() throws {
        let text = #"""
        "libraryfolders"
        {
            "0"
            {
                "path"		"C:\\Program Files (x86)\\Steam"
                "apps"
                {
                    "440"		"100000"
                    "570"		"200000"
                }
            }
        }
        """#

        let root = SteamVDF.parse(text)
        guard case let .object(libraryFolders)? = root["libraryfolders"],
              case let .object(entry0)? = libraryFolders["0"],
              case let .object(apps)? = entry0["apps"] else {
            return XCTFail("failed to parse apps object")
        }
        XCTAssertEqual(apps.count, 2)
    }
}

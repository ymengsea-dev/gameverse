//
//  SteamLauncher.swift
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

import Foundation

/// Launches a Steam game directly — `steam.exe -applaunch <appId>` lets
/// Steam resolve and run the actual game executable itself, avoiding the
/// need to reverse-engineer per-game launch executables (which Steam
/// doesn't expose cleanly outside its binary appinfo cache). The user never
/// has to open Steam's own library window.
public enum SteamLauncher {
    public static func steamExeURL(bottle: Bottle) -> URL {
        SteamLibrary.steamRoot(in: bottle).appending(path: "steam.exe")
    }

    public static func launchArgs(appId: Int) -> [String] {
        SteamFixup.launchArgs + ["-silent", "-applaunch", String(appId)]
    }

    public static func launch(game: SteamGame, bottle: Bottle) async throws {
        try await Wine.runProgram(
            at: steamExeURL(bottle: bottle), args: launchArgs(appId: game.appId), bottle: bottle
        )
    }

    /// Launch the Steam client UI itself (to log in, browse the store, or install
    /// games) with the CEF flags that keep its UI rendering on Wine/Apple Silicon.
    public static func launchClient(bottle: Bottle) async throws {
        try await Wine.runProgram(
            at: steamExeURL(bottle: bottle), args: SteamFixup.launchArgs, bottle: bottle
        )
    }
}

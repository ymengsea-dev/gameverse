//
//  SteamLibrary.swift
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

/// Discovers installed Steam games by reading Steam's own library manifests
/// directly from disk — no Steam client UI interaction required to list them.
public enum SteamLibrary {
    public static func steamRoot(in bottle: Bottle) -> URL {
        bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
    }

    public static func discoverGames(in bottle: Bottle) -> [SteamGame] {
        let root = steamRoot(in: bottle)
        var discovered: [SteamGame] = []
        for steamappsDir in libraryFolders(steamRoot: root) {
            discovered.append(contentsOf: games(in: steamappsDir, steamRoot: root))
        }
        return discovered
    }

    /// Every `steamapps` directory this bottle's Steam install knows about —
    /// its own plus any additional libraries listed in `libraryfolders.vdf`.
    private static func libraryFolders(steamRoot: URL) -> [URL] {
        let vdfURL = steamRoot.appending(path: "steamapps").appending(path: "libraryfolders.vdf")
        guard let text = try? String(contentsOf: vdfURL, encoding: .utf8) else { return [] }

        let root = SteamVDF.parse(text)
        guard case let .object(entries)? = root["libraryfolders"] else { return [] }

        return entries.values.compactMap { entry -> URL? in
            guard case let .object(fields) = entry,
                  case let .string(winPath)? = fields["path"] else { return nil }
            return bottlePath(fromWindowsPath: winPath, steamRoot: steamRoot)?.appending(path: "steamapps")
        }
    }

    private static func bottlePath(fromWindowsPath winPath: String, steamRoot: URL) -> URL? {
        guard winPath.count > 2, winPath.prefix(2).uppercased() == "C:" else { return nil }
        let driveC = steamRoot
            .deletingLastPathComponent() // Program Files (x86)
            .deletingLastPathComponent() // drive_c
        let relative = winPath.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        return driveC.appending(path: String(relative.drop(while: { $0 == "/" })))
    }

    private static func games(in steamappsDir: URL, steamRoot: URL) -> [SteamGame] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: steamappsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { game(fromManifest: $0, steamappsDir: steamappsDir, steamRoot: steamRoot) }
    }

    private static func game(fromManifest manifestURL: URL, steamappsDir: URL, steamRoot: URL) -> SteamGame? {
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return nil }
        let root = SteamVDF.parse(text)
        guard case let .object(appState)? = root["AppState"],
              case let .string(appIdString)? = appState["appid"],
              let appId = Int(appIdString),
              case let .string(name)? = appState["name"],
              case let .string(installDirName)? = appState["installdir"] else { return nil }

        let installDir = steamappsDir.appending(path: "common").appending(path: installDirName)
        let iconURL = steamRoot
            .appending(path: "appcache")
            .appending(path: "librarycache")
            .appending(path: "\(appId)_icon.jpg")
        let resolvedIconURL = FileManager.default.fileExists(
            atPath: iconURL.path(percentEncoded: false)
        ) ? iconURL : nil

        return SteamGame(appId: appId, name: name, installDir: installDir, iconURL: resolvedIconURL)
    }
}

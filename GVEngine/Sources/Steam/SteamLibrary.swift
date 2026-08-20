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
    /// Steam installs these app manifests as shared dependencies, but they are
    /// not user-launchable games and must not appear in the launcher library.
    private static let nonLaunchableAppIDs: Set<Int> = [
        228980 // Steamworks Common Redistributables
    ]

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
              !nonLaunchableAppIDs.contains(appId),
              case let .string(name)? = appState["name"],
              case let .string(installDirName)? = appState["installdir"] else { return nil }

        let installDir = steamappsDir.appending(path: "common").appending(path: installDirName)
        guard isNonEmptyDirectory(installDir) else { return nil }
        let resolvedIconURL = cachedArtworkURL(appId: appId, steamRoot: steamRoot)

        return SteamGame(appId: appId, name: name, installDir: installDir, iconURL: resolvedIconURL)
    }

    /// A manifest and artwork can remain after a game is manually deleted or
    /// while Steam only has staged download data. Such entries are not
    /// launchable and must not appear in the library or Storage tab.
    private static func isNonEmptyDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else { return false }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return !contents.isEmpty
    }

    /// Steam has used two library-cache layouts. Current clients put an app's
    /// hashed icon and artwork inside `librarycache/<appid>/`, while older
    /// clients used the flat `<appid>_icon.jpg` filename.
    private static func cachedArtworkURL(appId: Int, steamRoot: URL) -> URL? {
        let cacheRoot = steamRoot
            .appending(path: "appcache")
            .appending(path: "librarycache")
        let appCache = cacheRoot.appending(path: "\(appId)")

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: appCache,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ), let hashedIcon = entries
            .filter({ $0.isSteamHashedIcon })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first {
            return hashedIcon
        }

        let fallbackCandidates = [
            appCache.appending(path: "library_600x900.jpg"),
            appCache.appending(path: "header.jpg"),
            cacheRoot.appending(path: "\(appId)_icon.jpg")
        ]
        return fallbackCandidates.first {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
    }
}

private extension URL {
    var isSteamHashedIcon: Bool {
        let supportedExtensions = ["jpg", "jpeg", "png"]
        guard supportedExtensions.contains(pathExtension.lowercased()) else { return false }

        let stem = deletingPathExtension().lastPathComponent
        return stem.count == 40 && stem.allSatisfy(\.isHexDigit)
    }
}

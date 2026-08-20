//
//  WineRuntimeInstaller.swift
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
import SemanticVersion

public class WineRuntimeInstaller {
    /// The GameVerse application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.gameVerseBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWineRuntimeInstalled() -> Bool {
        return wineRuntimeVersion() != nil
    }

    public static func install(from: URL) throws {
        if !FileManager.default.fileExists(atPath: applicationFolder.path) {
            try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
        }
        // Preserve WineRuntimeDist and other application data. Older code removed
        // the whole support directory, deleting its own local source archive.
        if FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.removeItem(at: libraryFolder)
        }

        try Tar.untar(tarBall: from, toURL: applicationFolder)
        try normalizeLegacyWineOnlyArchiveIfNeeded()
        try FileManager.default.removeItem(at: from)
        try installRuntimeLibraries()
    }

    /// x86_64 dylibs that Wine dlopen()s by leaf name at runtime but that the
    /// bundled runtime ships without: GnuTLS (schannel/TLS, needed for Steam
    /// login) and MoltenVK (Vulkan→Metal, needed by DXVK games). Wine strips
    /// DYLD_*_LIBRARY_PATH from the target process, and modern dyld's default
    /// fallback only searches /usr/lib — so the sole reliable resolution is to
    /// place these physically in Wine's own `lib` directory, which its loader
    /// searches. They MUST be x86_64 because Wine runs under Rosetta.
    private static let runtimeLibraries = ["libgnutls.30.dylib", "libgmp.10.dylib", "libMoltenVK.dylib"]

    public static func installRuntimeLibraries() throws {
        let wineLib = libraryFolder.appending(path: "Wine").appending(path: "lib")
        guard FileManager.default.fileExists(atPath: wineLib.path) else { return }

        for name in runtimeLibraries {
            guard let source = Bundle.module.url(
                forResource: (name as NSString).deletingPathExtension,
                withExtension: "dylib", subdirectory: "Runtime"
            ) else { continue }
            let dest = wineLib.appending(path: name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        }
    }

    /// Accept the old archive layout (`bin`, `lib`, `share` at its root) while
    /// all new runtime archives use `Libraries/Wine` plus renderer directories.
    private static func normalizeLegacyWineOnlyArchiveIfNeeded() throws {
        let legacyBin = applicationFolder.appending(path: "bin")
        let installedWine = libraryFolder.appending(path: "Wine")
        let hasWineLoader = ["wine64", "wine"].contains {
            FileManager.default.fileExists(atPath: legacyBin.appending(path: $0).path)
        }
        guard hasWineLoader else { return }
        guard !FileManager.default.fileExists(atPath: installedWine.path) else { return }

        try FileManager.default.createDirectory(at: installedWine, withIntermediateDirectories: true)
        for name in ["bin", "lib", "share"] {
            let source = applicationFolder.appending(path: name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.moveItem(at: source, to: installedWine.appending(path: name))
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall Wine Runtime: \(error)")
        }
    }

    /// CrossOver 26 is based on the stable Wine 11.0 release. The actual engine
    /// string shown in the UI is always queried from `wine --version`.
    public static let bundledWineVersion = SemanticVersion(11, 0, 0)

    public static func shouldUpdateWineRuntime() async -> (Bool, SemanticVersion) {
        return (false, wineRuntimeVersion() ?? bundledWineVersion)
    }

    public static func wineRuntimeVersion() -> SemanticVersion? {
        do {
            // Filename is baked into the downloaded tarball itself (from the
            // archived upstream release) — not renamable.
            let versionPlist = libraryFolder
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WineRuntimeVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }
}

struct WineRuntimeVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}

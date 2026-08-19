//
//  SteamFixup.swift
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

public enum SteamFixup {
    public static let launchArgs = [
        "-cef-disable-gpu-compositing",
        "-cef-disable-gpu",
        "-cef-disable-sandbox",
        "-cef-enable-gl=swiftshader"
    ]

    public static var launchArgsString: String {
        launchArgs.joined(separator: " ")
    }

    public static func isSteam(url: URL) -> Bool {
        return url.lastPathComponent.lowercased() == "steam.exe"
    }

    // MARK: - Repair

    public enum SteamFixupError: Error {
        case shimResourceMissing(arch: String)
    }

    public static func repair(steamRoot: URL) throws {
        try WineRuntimeInstaller.installRuntimeLibraries()
        removeUpdateInhibitors(steamRoot: steamRoot)
        try? installWebHelperShim(steamRoot: steamRoot)
    }

    private static func removeUpdateInhibitors(steamRoot: URL) {
        let fileManager = FileManager.default

        // Drop the self-update inhibitor written by older builds.
        let cfg = steamRoot.appending(path: "steam.cfg")
        try? fileManager.removeItem(at: cfg)

        let cefBase = steamRoot.appending(path: "bin").appending(path: "cef")
        for target in webHelperTargets {
            let dir = cefBase.appending(path: target.cefDir)
            let helper = dir.appending(path: "steamwebhelper.exe")
            let realBackup = dir.appending(path: "steamwebhelper_real.exe")
            setImmutable(false, at: helper)
            setImmutable(false, at: realBackup)
            if fileManager.fileExists(atPath: realBackup.path(percentEncoded: false)) {
                try? fileManager.removeItem(at: helper)
                try? fileManager.moveItem(at: realBackup, to: helper)
            }
        }

        // Remove stale 32-bit package markers and mismatched DLLs that cause
        // c000007b (STATUS_INVALID_IMAGE_FORMAT) stack overflow crashes when
        // 64-bit Steam attempts to initialize after a UI update.
        let packageDir = steamRoot.appending(path: "package")
        try? fileManager.removeItem(at: packageDir.appending(path: "steam_client_win32.installed"))
        try? fileManager.removeItem(at: packageDir.appending(path: "steam_client_win32.manifest"))
        let crashMarker = steamRoot.appending(path: ".crash")
        try? fileManager.removeItem(at: crashMarker)

        // Clear corrupt CEF htmlcache in user AppData/Local/Steam/htmlcache so Steam
        // UI renders fresh HTML components instead of loading cached broken state.
        let bottleDriveC = steamRoot.deletingLastPathComponent().deletingLastPathComponent()
        let appDataLocalSteam = bottleDriveC
            .appending(path: "users")
            .appending(path: NSUserName())
            .appending(path: "AppData")
            .appending(path: "Local")
            .appending(path: "Steam")
            .appending(path: "htmlcache")
        try? fileManager.removeItem(at: appDataLocalSteam)

        ensureSteamLoopbackHosts(bottleDriveC: bottleDriveC)
    }

    /// Map steamloopback.host to 127.0.0.1 in Wine's Windows drivers/etc/hosts file so Steam CEF UI
    /// can resolve its local WebSocket IPC bridge without failing WSALookupService DNS resolution.
    private static func ensureSteamLoopbackHosts(bottleDriveC: URL) {
        let hostsFile = bottleDriveC
            .appending(path: "windows")
            .appending(path: "system32")
            .appending(path: "drivers")
            .appending(path: "etc")
            .appending(path: "hosts")

        let entry = "\n127.0.0.1 steamloopback.host\n::1 steamloopback.host\n"
        if let existing = try? String(contentsOf: hostsFile, encoding: .utf8) {
            if !existing.contains("steamloopback.host") {
                let updated = existing + entry
                try? updated.write(to: hostsFile, atomically: true, encoding: .utf8)
            }
        } else {
            let content = "127.0.0.1 localhost\n::1 localhost\n" + entry
            try? FileManager.default.createDirectory(at: hostsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: hostsFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - CEF webhelper shim (optional black-screen fix)

    /// Each CEF helper dir Steam may run, paired with the bundled shim of the
    /// matching architecture. cef.win7 is the 32-bit helper; cef.win64 is 64-bit.
    private static let webHelperTargets: [(cefDir: String, resource: String)] = [
        ("cef.win64", "steamwebhelper_x64"),
        ("cef.win7", "steamwebhelper_x86")
    ]

    public static func installWebHelperShim(steamRoot: URL) throws {
        let cefBase = steamRoot.appending(path: "bin").appending(path: "cef")
        for target in webHelperTargets {
            let helper = cefBase.appending(path: target.cefDir).appending(path: "steamwebhelper.exe")
            guard FileManager.default.fileExists(atPath: helper.path(percentEncoded: false)) else { continue }
            try installShim(realHelper: helper, resource: target.resource)
        }
    }

    private static func installShim(realHelper: URL, resource: String) throws {
        let fileManager = FileManager.default
        let helperDir = realHelper.deletingLastPathComponent()
        let realBackup = helperDir.appending(path: "steamwebhelper_real.exe")

        guard let shimURL = Bundle.module.url(
            forResource: resource, withExtension: "exe", subdirectory: "Shims"
        ) else {
            throw SteamFixupError.shimResourceMissing(arch: resource)
        }

        setImmutable(false, at: realHelper)

        if !fileManager.fileExists(atPath: realBackup.path(percentEncoded: false)) {
            // First install: preserve the genuine helper.
            try fileManager.moveItem(at: realHelper, to: realBackup)
        } else if fileManager.fileExists(atPath: realHelper.path(percentEncoded: false)) {
            // Backup already exists — current helper is our old shim; discard it.
            try fileManager.removeItem(at: realHelper)
        }

        try fileManager.copyItem(at: shimURL, to: realHelper)
    }

    private static func setImmutable(_ immutable: Bool, at url: URL) {
        try? FileManager.default.setAttributes(
            [.immutable: immutable], ofItemAtPath: url.path(percentEncoded: false)
        )
    }
}

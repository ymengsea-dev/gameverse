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

/// Steam-on-Wine/Apple-Silicon fixes.
///
/// History: earlier versions rolled Steam back to an archived 2025-03-06 client
/// and inhibited all self-updates (`steam.cfg` + `-skipinitialbootstrap` etc.).
/// That was a workaround for a Steam startup failure whose real cause was Wine
/// having no working TLS provider — the bundled runtime shipped an arm64
/// `secur32.so`/`libgnutls` into an x86_64 (Rosetta) Wine. Once the x86_64
/// GnuTLS stack is present in `Wine/lib` (see WineRuntimeInstaller), Steam's own
/// current client runs. The rollback/inhibit approach was actively harmful: it
/// froze Steam in a half-updated state (32-bit `steamui.dll` under a 64-bit
/// client → `c000007b`), so it has been removed.
public enum SteamFixup {
    /// Launch args for normal Steam runs. The `-cef-*` flags force software
    /// compositing for Steam's CEF UI — on Wine/Apple Silicon the GPU compositor
    /// renders nothing, giving the classic black-screen login window. Crucially
    /// there are NO update-blocking flags here: Steam must stay free to keep its
    /// own client files consistent, or a partial update wedges it (see above).
    public static let launchArgs = [
        "-cef-force-32bit",
        "-cef-disable-gpu-compositing",
        "-cef-disable-gpu",
        // Run CEF in a single process. The multi-process webHelper crashes under
        // Wine/GPTK with a nested exception on the signal stack (steamwebhelper
        // renderer faults, Wine re-faults delivering the exception), killing the
        // helper and taking steam.exe down with status=100.
        "-cef-single-process"
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

    /// Bring a Steam install back to a launchable state:
    /// 1. ensure the x86_64 runtime libs Wine dlopen()s (GnuTLS for login,
    ///    MoltenVK for games) are present in `Wine/lib`, and
    /// 2. remove anything that would stop Steam updating itself to a consistent
    ///    client — the old `steam.cfg` update inhibitor, `uchg` file locks, and
    ///    any leftover webhelper shim.
    ///
    /// After this, launching Steam (with `launchArgs`) lets it self-heal.
    public static func repair(steamRoot: URL) throws {
        try WineRuntimeInstaller.installRuntimeLibraries()
        removeUpdateInhibitors(steamRoot: steamRoot)
    }

    private static func removeUpdateInhibitors(steamRoot: URL) {
        let fileManager = FileManager.default

        // Drop the self-update inhibitor written by older builds.
        let cfg = steamRoot.appending(path: "steam.cfg")
        try? fileManager.removeItem(at: cfg)

        // Clear uchg locks and restore the genuine webhelper over any shim, so
        // Steam's updater can rename/replace those files instead of failing with
        // error 5 and reverting the whole update.
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
    }

    // MARK: - CEF webhelper shim (optional black-screen fix)

    /// Each CEF helper dir Steam may run, paired with the bundled shim of the
    /// matching architecture. cef.win7 is the 32-bit helper; cef.win64 is 64-bit.
    private static let webHelperTargets: [(cefDir: String, resource: String)] = [
        ("cef.win64", "steamwebhelper_x64"),
        ("cef.win7", "steamwebhelper_x86")
    ]

    /// Replace every present `steamwebhelper.exe` under `<steamRoot>/bin/cef`
    /// with the GameVerse shim (backing up the genuine helper as
    /// `steamwebhelper_real.exe`). The shim injects `--single-process`, which
    /// Steam's own launch args can't express, for cases where `-cef-disable-gpu`
    /// alone doesn't clear the CEF UI black screen. Optional — call only if the
    /// UI is still black after `repair` + `launchArgs`. Idempotent.
    ///
    /// NOTE: does not lock the file. A locked webhelper breaks Steam's updater
    /// (see repair); letting an update overwrite the shim is acceptable and
    /// self-healing — re-run this afterwards if needed.
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

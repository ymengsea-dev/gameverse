//
//  InstalledProgramDiscovery.swift
//  GVEngine
//

import Foundation

/// A Windows Start Menu entry found inside a bottle. The shortcut itself is
/// retained as the location because resolving every `.lnk` target is not
/// required to present a reliable installed-software inventory.
public struct InstalledShortcut: Identifiable, Hashable, Sendable {
    public let name: String
    public let shortcutURL: URL

    public init(name: String, shortcutURL: URL) {
        self.name = name
        self.shortcutURL = shortcutURL
    }

    public var id: URL { shortcutURL }
}

public enum InstalledProgramDiscovery {
    /// Discover installer-created entries from the shared and per-user Start
    /// Menus. Results are de-duplicated by display name because installers can
    /// create the same shortcut for both the current user and all users.
    public static func discoverShortcuts(in bottle: Bottle) -> [InstalledShortcut] {
        var discovered: [InstalledShortcut] = []
        var names: Set<String> = []

        for root in startMenuRoots(in: bottle) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let candidate = enumerator.nextObject() as? URL {
                guard candidate.pathExtension.lowercased() == "lnk" else { continue }
                let name = candidate.deletingPathExtension().lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                guard names.insert(name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive], locale: .current
                )).inserted else { continue }
                discovered.append(InstalledShortcut(name: name, shortcutURL: candidate))
            }
        }

        return discovered.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func startMenuRoots(in bottle: Bottle) -> [URL] {
        let driveC = bottle.url.appending(path: "drive_c")
        var roots = [
            driveC.appending(path: "ProgramData/Microsoft/Windows/Start Menu/Programs")
        ]
        let users = driveC.appending(path: "users")
        if let userDirectories = try? FileManager.default.contentsOfDirectory(
            at: users, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            roots.append(contentsOf: userDirectories.map {
                $0.appending(path: "AppData/Roaming/Microsoft/Windows/Start Menu/Programs")
            })
        }
        return roots
    }
}

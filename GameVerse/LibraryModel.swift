//
//  LibraryModel.swift
//  GameVerse
//

import Foundation
import SwiftUI
import SemanticVersion
import GVEngine

struct GameItem: Identifiable {
    enum Source {
        case program(Program)   // any pinned Windows executable
        case steam(SteamGame)   // a game discovered from a Steam install
        case steamClient        // the Steam client itself (log in / install games)
    }

    let source: Source
    let displayName: String
    let bottle: Bottle

    var id: String {
        switch source {
        case .program(let program): return "prog:\(bottle.id.path)#\(program.url.path)"
        case .steam(let game): return "steam:\(bottle.id.path)#\(game.appId)"
        case .steamClient: return "steamclient:\(bottle.id.path)"
        }
    }

    var icon: NSImage? {
        switch source {
        case .program(let program): return program.peFile?.bestIcon()
        case .steam(let game): return game.iconURL.flatMap { NSImage(contentsOf: $0) }
        case .steamClient:
            return Program(url: SteamLauncher.steamExeURL(bottle: bottle), bottle: bottle).peFile?.bestIcon()
        }
    }
}

/// The app's single source of truth: Wine bottles and the launchable items
/// inside them. Wraps GVEngine's `BottleData` (persists the list of bottles).
@MainActor
final class LibraryModel: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var isCreatingBottle = false
    @Published var runtimeReady = WineRuntimeInstaller.isWineRuntimeInstalled()

    private var store = BottleData()

    init() {
        reload()
    }

    func reload() {
        bottles = store.loadBottles().sorted()
        runtimeReady = WineRuntimeInstaller.isWineRuntimeInstalled()
    }

    // MARK: Items

    /// Every launchable item in a bottle: pinned programs (any app) plus any
    /// Steam games discovered there.
    func items(in bottle: Bottle) -> [GameItem] {
        var items: [GameItem] = []

        for pin in bottle.settings.pins {
            guard let url = pin.url,
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            items.append(GameItem(source: .program(Program(url: url, bottle: bottle)),
                                   displayName: pin.name, bottle: bottle))
        }

        for game in SteamLibrary.discoverGames(in: bottle) {
            items.append(GameItem(source: .steam(game), displayName: game.name, bottle: bottle))
        }

        var sorted = items.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        // If this bottle has Steam, always offer the Steam client itself first so
        // the user can log in and install games — even before any game exists.
        if hasSteam(bottle) {
            sorted.insert(GameItem(source: .steamClient, displayName: "Steam", bottle: bottle), at: 0)
        }
        return sorted
    }

    /// Everything across every bottle — the "All Games" shelf.
    var allItems: [GameItem] {
        bottles.flatMap { items(in: $0) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func launch(_ item: GameItem) async {
        switch item.source {
        case .program(let program):
            program.run()
        case .steam(let game):
            do {
                try await SteamLauncher.launch(game: game, bottle: item.bottle)
            } catch {
                print("Failed to launch \(game.name): \(error)")
            }
        case .steamClient:
            do {
                try await SteamLauncher.launchClient(bottle: item.bottle)
            } catch {
                print("Failed to launch Steam: \(error)")
            }
        }
    }

    /// Pin any Windows executable as a game/app in a bottle.
    func addProgram(url: URL, to bottle: Bottle) {
        guard !bottle.settings.pins.contains(where: { $0.url == url }) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        bottle.settings.pins.append(PinnedProgram(name: name, url: url))
        objectWillChange.send()
    }

    func removeProgram(_ item: GameItem) {
        guard case .program(let program) = item.source else { return }
        item.bottle.settings.pins.removeAll { $0.url == program.url }
        objectWillChange.send()
    }

    /// Whether a bottle has a Steam install (so Steam-specific actions apply).
    func hasSteam(_ bottle: Bottle) -> Bool {
        let steamExe = SteamLibrary.steamRoot(in: bottle).appending(path: "steam.exe")
        return FileManager.default.fileExists(atPath: steamExe.path(percentEncoded: false))
    }

    // MARK: Bottles

    func createBottle(name: String, winVersion: WinVersion) {
        let dir = BottleData.defaultBottleDir.appending(path: UUID().uuidString)
        Task {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: dir, inFlight: true)
                bottle.settings.name = name
                bottle.settings.windowsVersion = winVersion
                bottles.append(bottle)

                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                store.paths.append(dir)
                reload()
            } catch {
                print("Failed to create bottle: \(error)")
                try? FileManager.default.removeItem(at: dir)
                reload()
            }
        }
    }

    func delete(_ bottle: Bottle) {
        store.paths.removeAll { $0 == bottle.url }
        try? FileManager.default.removeItem(at: bottle.url)
        reload()
    }

    /// Run an arbitrary Windows executable inside a bottle without pinning it.
    func run(executable url: URL, in bottle: Bottle) {
        Task {
            do {
                try await Wine.runProgram(at: url, bottle: bottle)
            } catch {
                print("Failed to run \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// Steam-only maintenance: only meaningful when the bottle contains Steam.
    func repairSteam(in bottle: Bottle) {
        Task {
            do {
                let steamExe = SteamLibrary.steamRoot(in: bottle).appending(path: "steam.exe")
                try SteamFixup.repair(steamRoot: steamExe.deletingLastPathComponent())
            } catch {
                print("Steam repair failed: \(error)")
            }
        }
    }
}

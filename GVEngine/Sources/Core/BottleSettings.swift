//
//  BottleSettings.swift
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
import os.log

public struct PinnedProgram: Codable, Hashable, Equatable {
    public var name: String
    public var url: URL?
    public var removable: Bool

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        do {
            let volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume
            self.removable = try !(volume?.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal ?? false)
        } catch {
            self.removable = false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false
    }
}

public struct BottleInfo: Codable, Equatable {
    var name: String = "Bottle"
    var pins: [PinnedProgram] = []
    var blocklist: [URL] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
    }
}

public enum WinVersion: String, CaseIterable, Codable, Sendable {
    case winXP = "winxp64"
    case win7 = "win7"
    case win8 = "win8"
    case win81 = "win81"
    case win10 = "win10"
    case win11 = "win11"

    public func pretty() -> String {
        switch self {
        case .winXP:
            return "Windows XP"
        case .win7:
            return "Windows 7"
        case .win8:
            return "Windows 8"
        case .win81:
            return "Windows 8.1"
        case .win10:
            return "Windows 10"
        case .win11:
            return "Windows 11"
        }
    }
}

public enum EnhancedSync: Codable, Equatable {
    case none, esync, msync
}

public struct BottleWineConfig: Codable, Equatable {
    static let defaultWineVersion = SemanticVersion(11, 0, 0)
    var wineVersion: SemanticVersion = Self.defaultWineVersion
    var windowsVersion: WinVersion = .win10
    var enhancedSync: EnhancedSync = .msync
    var avxEnabled: Bool = false

    public init() {}

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wineVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .wineVersion) ?? Self.defaultWineVersion
        self.windowsVersion = try container.decodeIfPresent(WinVersion.self, forKey: .windowsVersion) ?? .win10
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync) ?? .msync
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled) ?? false
    }
    // swiftlint:enable line_length
}

public struct BottleMetalConfig: Codable, Equatable {
    var metalHud: Bool = false
    var metalTrace: Bool = false
    var dxrEnabled: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        self.metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        self.dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? false
    }
}

/// Direct3D translation backend requested for a bottle. `auto` is resolved for
/// each launched game from the DirectX DLLs referenced by its executable files.
public enum GraphicsRenderer: String, Codable, CaseIterable, Sendable {
    case auto
    case d3dMetal
    case dxmt
    case dxvk
    case wineD3D

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .d3dMetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wineD3D: return "WineD3D"
        }
    }

    public var translationPath: String {
        switch self {
        case .auto: return "Selected for each game"
        case .d3dMetal: return "Direct3D → Metal"
        case .dxmt: return "Direct3D 10/11 → Metal"
        case .dxvk: return "Direct3D 10/11 → Vulkan → MoltenVK → Metal"
        case .wineD3D: return "Direct3D → OpenGL"
        }
    }
}

public enum DXVKHUD: Codable, Equatable {
    case full, partial, fps, off
}

public struct BottleDXVKConfig: Codable, Equatable {
    var renderer: GraphicsRenderer = .auto
    var dxvkAsync: Bool = true
    var dxvkHud: DXVKHUD = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let renderer = try container.decodeIfPresent(GraphicsRenderer.self, forKey: .renderer) {
            self.renderer = renderer
        } else {
            // Migrate bottles written by GameVerse/Whisky before renderer selection
            // was represented explicitly.
            let legacyDXVK = try container.decodeIfPresent(Bool.self, forKey: .dxvk) ?? true
            self.renderer = legacyDXVK ? .dxvk : .wineD3D
        }
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(renderer, forKey: .renderer)
        try container.encode(renderer == .dxvk, forKey: .dxvk)
        try container.encode(dxvkAsync, forKey: .dxvkAsync)
        try container.encode(dxvkHud, forKey: .dxvkHud)
    }

    private enum CodingKeys: String, CodingKey {
        case renderer, dxvk, dxvkAsync, dxvkHud
    }
}

public struct BottleSettings: Codable, Equatable {
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    var fileVersion: SemanticVersion = Self.defaultFileVersion
    private var info: BottleInfo
    private var wineConfig: BottleWineConfig
    private var metalConfig: BottleMetalConfig
    private var dxvkConfig: BottleDXVKConfig

    public init() {
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.dxvkConfig = BottleDXVKConfig()
    }

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self.defaultFileVersion
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.dxvkConfig = try container.decodeIfPresent(BottleDXVKConfig.self, forKey: .dxvkConfig) ?? BottleDXVKConfig()
    }
    // swiftlint:enable line_length

    /// The name of this bottle
    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    /// The version of wine used by this bottle
    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The version of windows used by this bottle
    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The pinned programs on this bottle
    public var pins: [PinnedProgram] {
        get { return info.pins }
        set { info.pins = newValue }
    }

    /// The blocked applicaitons on this bottle
    public var blocklist: [URL] {
        get { return info.blocklist }
        set { info.blocklist = newValue }
    }

    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    public var metalHud: Bool {
        get { return metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    public var metalTrace: Bool {
        get { return metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    public var dxrEnabled: Bool {
        get { return metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    public var dxvk: Bool {
        get { return dxvkConfig.renderer == .dxvk }
        set { dxvkConfig.renderer = newValue ? .dxvk : .wineD3D }
    }

    /// Requested Direct3D renderer. Auto is resolved at launch time and does
    /// not mutate the persisted preference.
    public var graphicsRenderer: GraphicsRenderer {
        get { return dxvkConfig.renderer }
        set { dxvkConfig.renderer = newValue }
    }

    public var dxvkAsync: Bool {
        get { return dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get {  return dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    @discardableResult
    public static func decode(from metadataURL: URL) throws -> BottleSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            let settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(BottleSettings.self, from: data)

        guard settings.fileVersion == BottleSettings.defaultFileVersion else {
            Logger.wineKit.warning("Invalid file version `\(settings.fileVersion)`")
            settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        if settings.wineConfig.wineVersion != BottleWineConfig().wineVersion {
            Logger.wineKit.warning("Bottle has a different wine version `\(settings.wineConfig.wineVersion)`")
            settings.wineConfig.wineVersion = BottleWineConfig().wineVersion
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func environmentVariables(
        wineEnv: inout [String: String], resolvedRenderer: GraphicsRenderer? = nil
    ) {
        // Disable only the optional .NET/Mono bridge. Steam's 64-bit client does
        // probe its 32-bit steamservice.dll and Wine reports c000007b for that
        // in-process probe, but Steam then starts the matching 32-bit
        // SteamService.exe out of process. Disabling the DLL globally also
        // affects that service process, producing error 126 and an endless
        // "Install Steam Service" loop.
        let renderer = resolvedRenderer ?? graphicsRenderer
        var dllOverrides = ["mscoree="]
        switch renderer {
        case .d3dMetal:
            dllOverrides.append("dxgi,d3d11,d3d12=n,b")
        case .dxmt:
            dllOverrides.append("dxgi,d3d10core,d3d11,winemetal=n,b")
        case .dxvk:
            dllOverrides.append("dxgi,d3d10core,d3d11=n,b")
        case .auto, .wineD3D:
            break
        }
        wineEnv.updateValue(dllOverrides.joined(separator: ";"), forKey: "WINEDLLOVERRIDES")
        if renderer == .dxvk {
            switch dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }
        }

        if renderer == .dxvk && dxvkAsync {
            wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
        }

        switch enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
            // D3DM detects ESYNC and changes behaviour accordingly
            // so we have to lie to it so that it doesn't break
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        }

        if metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
            wineEnv.updateValue(
                "device,rosetta,memory,fps,fpsgraph,frameinterval,gputime,thermal",
                forKey: "MTL_HUD_ELEMENTS"
            )
        }

        if metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }

        if avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }

        if dxrEnabled {
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }
    }
}

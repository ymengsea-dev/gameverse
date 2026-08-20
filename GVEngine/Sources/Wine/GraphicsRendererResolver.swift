//
//  GraphicsRendererResolver.swift
//  GVEngine
//
//  This file is part of GameVerse.
//

import Foundation

public enum DirectXGeneration: Int, Comparable, Sendable {
    case unknown = 0
    case direct3D9 = 9
    case direct3D10 = 10
    case direct3D11 = 11
    case direct3D12 = 12

    public static func < (lhs: DirectXGeneration, rhs: DirectXGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct GraphicsRequirements: Equatable, Sendable {
    public let directX: DirectXGeneration
    public let has64BitRendererConsumer: Bool

    public init(directX: DirectXGeneration, has64BitRendererConsumer: Bool) {
        self.directX = directX
        self.has64BitRendererConsumer = has64BitRendererConsumer
    }
}

public struct GraphicsRendererAvailability: Equatable, Sendable {
    public let d3dMetal: Bool
    public let dxmt: Bool
    public let dxvk: Bool

    public init(d3dMetal: Bool, dxmt: Bool, dxvk: Bool) {
        self.d3dMetal = d3dMetal
        self.dxmt = dxmt
        self.dxvk = dxvk
    }
}

/// Resolves the `Auto` renderer without relying on a hard-coded game list.
/// Static imports are deliberately used as a hint rather than a compatibility
/// promise; callers can always persist a manual renderer for a specific title.
public enum GraphicsRendererResolver {
    private static let candidateExtensions = Set(["exe", "dll"])
    private static let ignoredDirectoryNames = Set([
        "_commonredist", "directxredist", "redist", "redistributable", "support"
    ])
    private static let maximumCandidateCount = 400
    private static let maximumBytesPerFile = 32 * 1024 * 1024
    private static let maximumTotalBytes = 256 * 1024 * 1024

    public static func resolve(
        requested: GraphicsRenderer,
        inspecting url: URL,
        availability: GraphicsRendererAvailability
    ) -> GraphicsRenderer {
        guard requested == .auto else { return requested }
        return resolve(requirements: inspect(url), availability: availability)
    }

    public static func resolve(
        requirements: GraphicsRequirements,
        availability: GraphicsRendererAvailability
    ) -> GraphicsRenderer {
        switch requirements.directX {
        case .direct3D12:
            if requirements.has64BitRendererConsumer && availability.d3dMetal { return .d3dMetal }
            return .wineD3D
        case .direct3D11:
            if requirements.has64BitRendererConsumer && availability.d3dMetal { return .d3dMetal }
            if availability.dxmt { return .dxmt }
            if availability.dxvk { return .dxvk }
            return .wineD3D
        case .direct3D10:
            if availability.dxmt { return .dxmt }
            if availability.dxvk { return .dxvk }
            return .wineD3D
        case .direct3D9:
            // The macOS-compatible DXVK builds support D3D10/11, not D3D9.
            return .wineD3D
        case .unknown:
            // Modern 64-bit games frequently load D3D dynamically, leaving no
            // import to inspect. Prefer Metal while retaining manual overrides.
            if availability.d3dMetal { return .d3dMetal }
            if availability.dxmt { return .dxmt }
            if availability.dxvk { return .dxvk }
            return .wineD3D
        }
    }

    public static func inspect(_ url: URL) -> GraphicsRequirements {
        let candidates = candidateFiles(at: url)
        var bestAPI: DirectXGeneration = .unknown
        var bestHas64BitConsumer = false
        var totalBytesRead = 0

        for candidate in candidates.prefix(maximumCandidateCount) where totalBytesRead < maximumTotalBytes {
            let remaining = maximumTotalBytes - totalBytesRead
            let byteLimit = min(maximumBytesPerFile, remaining)
            guard let result = inspectFile(candidate, byteLimit: byteLimit) else { continue }
            totalBytesRead += result.bytesRead

            if result.api > bestAPI {
                bestAPI = result.api
                bestHas64BitConsumer = result.is64Bit
            } else if result.api == bestAPI && result.is64Bit {
                bestHas64BitConsumer = true
            }
        }

        return GraphicsRequirements(
            directX: bestAPI,
            has64BitRendererConsumer: bestHas64BitConsumer || bestAPI == .unknown
        )
    }

    private static func candidateFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else { return [url] }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [URL] = []
        while let candidate = enumerator.nextObject() as? URL {
            if candidate.pathComponents.contains(where: { ignoredDirectoryNames.contains($0.lowercased()) }) {
                enumerator.skipDescendants()
                continue
            }
            guard candidateExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
            result.append(candidate)
            if result.count >= maximumCandidateCount { break }
        }

        // Executables and files nearest the game root are the strongest signal.
        return result.sorted {
            let leftEXE = $0.pathExtension.lowercased() == "exe"
            let rightEXE = $1.pathExtension.lowercased() == "exe"
            if leftEXE != rightEXE { return leftEXE }
            return $0.pathComponents.count < $1.pathComponents.count
        }
    }

    private static func inspectFile(
        _ url: URL, byteLimit: Int
    ) -> (api: DirectXGeneration, is64Bit: Bool, bytesRead: Int)? {
        guard byteLimit > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let signature = try? handle.read(upToCount: 2), signature == Data([0x4d, 0x5a]) else {
            return nil
        }
        try? handle.seek(toOffset: 0)

        var detected: DirectXGeneration = .unknown
        var bytesRead = 0
        var overlap = Data()
        let chunkSize = 1024 * 1024

        while bytesRead < byteLimit, detected != .direct3D12 {
            let count = min(chunkSize, byteLimit - bytesRead)
            guard let chunk = try? handle.read(upToCount: count), !chunk.isEmpty else { break }
            bytesRead += chunk.count
            var searchable = overlap
            searchable.append(chunk)
            detected = max(detected, detectDirectX(in: searchable))
            overlap = Data(searchable.suffix(32))
        }

        let architecture = (try? PEFile(url: url).architecture) ?? .unknown
        return (detected, architecture != .x32, bytesRead)
    }

    private static func detectDirectX(in data: Data) -> DirectXGeneration {
        let lowered = Data(data.map { byte in
            (0x41...0x5a).contains(byte) ? byte + 0x20 : byte
        })
        if lowered.range(of: Data("d3d12.dll".utf8)) != nil { return .direct3D12 }
        if lowered.range(of: Data("d3d11.dll".utf8)) != nil { return .direct3D11 }
        if lowered.range(of: Data("d3d10.dll".utf8)) != nil ||
            lowered.range(of: Data("d3d10core.dll".utf8)) != nil { return .direct3D10 }
        if lowered.range(of: Data("d3d9.dll".utf8)) != nil { return .direct3D9 }
        return .unknown
    }
}

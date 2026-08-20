//
//  Wine.swift
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
import os.log

public class Wine {
    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WineRuntimeInstaller.libraryFolder.appending(path: "DXVK")
    /// URL to optional native-Metal translation backends.
    private static let dxmtFolder: URL = WineRuntimeInstaller.libraryFolder.appending(path: "DXMT")
    private static let d3dMetalFolder: URL = WineRuntimeInstaller.libraryFolder.appending(path: "D3DMetal")
    /// Path to the Wine loader. New-WoW64 Wine 11 installs `wine`, while older
    /// GameVerse runtimes installed `wine64`; support both during migration.
    public static var wineBinary: URL {
        let wine64 = WineRuntimeInstaller.binFolder.appending(path: "wine64")
        if FileManager.default.isExecutableFile(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return WineRuntimeInstaller.binFolder.appending(path: "wine")
    }
    /// Parth to the `wineserver` binary
    private static let wineserverBinary: URL = WineRuntimeInstaller.binFolder.appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        directory: URL? = nil, fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            directory: directory, fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:],
        directory: URL? = nil, resolvedRenderer: GraphicsRenderer? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(
                for: bottle, environment: environment, resolvedRenderer: resolvedRenderer
            ),
            directory: directory, fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    /// Execute a program directly under `wine` (no `start /unix`) so the process
    /// stays attached to our pipes and all of its output — including crash
    /// backtraces and page faults — is captured to the log file.
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:],
        graphicsSource: URL? = nil, rendererOverride: GraphicsRenderer? = nil
    ) async throws {
        let renderer = GraphicsRendererResolver.resolve(
            requested: rendererOverride ?? bottle.settings.graphicsRenderer,
            inspecting: graphicsSource ?? url,
            availability: graphicsRendererAvailability
        )
        try await prepareGraphicsRenderer(renderer, bottle: bottle)
        let rendererEnvironment = graphicsEnvironment(for: renderer).merging(environment) { _, supplied in supplied }

        for await _ in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: [url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: rendererEnvironment,
            directory: url.deletingLastPathComponent(), resolvedRenderer: renderer
        ) { }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let renderer = GraphicsRendererResolver.resolve(
            requested: bottle.settings.graphicsRenderer,
            inspecting: url,
            availability: graphicsRendererAvailability
        )
        let rendererChanged = appliedGraphicsRenderer(for: bottle) != renderer
        if rendererChanged {
            try? applyGraphicsRenderer(renderer, bottle: bottle)
            try? recordAppliedGraphicsRenderer(renderer, bottle: bottle)
        }
        var wineCmd = "\(wineBinary.esc) start /unix \(url.esc) \(args)"
        let rendererEnvironment = graphicsEnvironment(for: renderer).merging(environment) { _, supplied in supplied }
        let env = constructWineEnvironment(
            for: bottle, environment: rendererEnvironment, resolvedRenderer: renderer
        )
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }
        if rendererChanged {
            let stopCommand = "WINEPREFIX=\"\(bottle.url.path)\" \(wineserverBinary.esc) -k"
            wineCmd = "\(stopCommand); \(wineCmd)"
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let wineCommand = wineBinary.lastPathComponent
        var cmd = """
        export PATH=\"\(WineRuntimeInstaller.binFolder.path):$PATH\"
        export WINE=\"\(wineCommand)\"
        alias wine=\"\(wineCommand)\"
        alias winecfg=\"\(wineCommand) winecfg\"
        alias msiexec=\"\(wineCommand) msiexec\"
        alias regedit=\"\(wineCommand) regedit\"
        alias regsvr32=\"\(wineCommand) regsvr32\"
        alias wineboot=\"\(wineCommand) wineboot\"
        alias wineconsole=\"\(wineCommand) wineconsole\"
        alias winedbg=\"\(wineCommand) winedbg\"
        alias winefile=\"\(wineCommand) winefile\"
        alias winepath=\"\(wineCommand) winepath\"
        """

        let env = constructWineEnvironment(for: bottle)
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = environment

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(args: args, environment: environment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    /// Stop every Wine process associated with this bottle's prefix. Awaiting
    /// the wineserver command lets callers report failures instead of losing
    /// them in an unstructured detached task.
    public static func killBottle(bottle: Bottle) async throws {
        _ = try await runWineserver(["-k"], bottle: bottle)
    }

    public static var graphicsRendererAvailability: GraphicsRendererAvailability {
        let d3dMetalExternal = d3dMetalFolder.appending(path: "external")
        let wineUnix = WineRuntimeInstaller.libraryFolder.appending(path: "Wine/lib/wine/x86_64-unix")
        return GraphicsRendererAvailability(
            d3dMetal: rendererDLLsExist(in: d3dMetalFolder.appending(path: "x64"),
                                       required: ["dxgi.dll", "d3d11.dll", "d3d12.dll"])
                && FileManager.default.fileExists(
                    atPath: d3dMetalExternal.appending(path: "libd3dshared.dylib").path
                )
                && FileManager.default.fileExists(
                    atPath: d3dMetalExternal.appending(path: "D3DMetal.framework").path
                ),
            dxmt: rendererDLLsExist(in: dxmtFolder.appending(path: "x64"),
                                   required: ["dxgi.dll", "d3d11.dll", "winemetal.dll"])
                && FileManager.default.fileExists(
                    atPath: wineUnix.appending(path: "winemetal.so").path
                ),
            dxvk: rendererDLLsExist(in: dxvkFolder.appending(path: "x64"),
                                   required: ["dxgi.dll", "d3d11.dll"])
        )
    }

    public static func resolvedGraphicsRenderer(
        requested: GraphicsRenderer, inspecting url: URL
    ) -> GraphicsRenderer {
        GraphicsRendererResolver.resolve(
            requested: requested, inspecting: url, availability: graphicsRendererAvailability
        )
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try applyGraphicsRenderer(.dxvk, bottle: bottle)
        try recordAppliedGraphicsRenderer(.dxvk, bottle: bottle)
    }

    /// Stop processes in a bottle before changing its renderer. Steam forwards
    /// `-applaunch` to an existing client process, so without this restart the
    /// game can inherit the previous renderer's environment and loaded DLLs.
    private static func prepareGraphicsRenderer(
        _ renderer: GraphicsRenderer, bottle: Bottle
    ) async throws {
        guard renderer != .auto, appliedGraphicsRenderer(for: bottle) != renderer else { return }
        _ = try await runWineserver(["-k"], bottle: bottle)
        try applyGraphicsRenderer(renderer, bottle: bottle)
        try recordAppliedGraphicsRenderer(renderer, bottle: bottle)
    }

    private static func appliedGraphicsRenderer(for bottle: Bottle) -> GraphicsRenderer? {
        let marker = rendererMarker(for: bottle)
        guard let rawValue = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return GraphicsRenderer(rawValue: rawValue)
    }

    private static func recordAppliedGraphicsRenderer(
        _ renderer: GraphicsRenderer, bottle: Bottle
    ) throws {
        try renderer.rawValue.write(
            to: rendererMarker(for: bottle), atomically: true, encoding: .utf8
        )
    }

    private static func rendererMarker(for bottle: Bottle) -> URL {
        bottle.url.appending(path: ".gameverse-graphics-renderer")
    }

    /// Restore Wine's builtin Direct3D DLLs, then install exactly one backend.
    /// Keeping each backend in its own runtime directory makes switching
    /// reversible and prevents GPTK DLLs from affecting Steam's CEF processes.
    public static func applyGraphicsRenderer(_ renderer: GraphicsRenderer, bottle: Bottle) throws {
        guard renderer != .auto else { return }
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        let syswow64 = bottle.url.appending(path: "drive_c/windows/syswow64")
        let x64Sources = rendererFolders(architecture: "x64")
        let x32Sources = rendererFolders(architecture: "x32")
        let wineLibrary = WineRuntimeInstaller.libraryFolder.appending(path: "Wine/lib/wine")

        try FileManager.default.restoreDLLs(
            in: system32, installedFrom: x64Sources,
            builtinDirectory: wineLibrary.appending(path: "x86_64-windows")
        )
        try FileManager.default.restoreDLLs(
            in: syswow64, installedFrom: x32Sources,
            builtinDirectory: wineLibrary.appending(path: "i386-windows")
        )

        switch renderer {
        case .d3dMetal:
            guard graphicsRendererAvailability.d3dMetal else {
                throw GraphicsRendererError.backendNotInstalled(.d3dMetal)
            }
            try FileManager.default.replaceDLLs(
                in: system32, withContentsIn: d3dMetalFolder.appending(path: "x64")
            )
        case .dxmt:
            guard graphicsRendererAvailability.dxmt else {
                throw GraphicsRendererError.backendNotInstalled(.dxmt)
            }
            try FileManager.default.replaceDLLs(
                in: system32, withContentsIn: dxmtFolder.appending(path: "x64")
            )
            let x32 = dxmtFolder.appending(path: "x32")
            if FileManager.default.fileExists(atPath: x32.path(percentEncoded: false)) {
                try FileManager.default.replaceDLLs(in: syswow64, withContentsIn: x32)
            }
        case .dxvk:
            guard graphicsRendererAvailability.dxvk else {
                throw GraphicsRendererError.backendNotInstalled(.dxvk)
            }
            try FileManager.default.replaceDLLs(
                in: system32, withContentsIn: dxvkFolder.appending(path: "x64")
            )
            try FileManager.default.replaceDLLs(
                in: syswow64, withContentsIn: dxvkFolder.appending(path: "x32")
            )
        case .wineD3D:
            break
        case .auto:
            break
        }
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:],
        resolvedRenderer: GraphicsRenderer? = nil
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            // fixme-all silences noise, but err+all and warn+module surface the
            // decisive lines on a crash (page faults, DLL load failures, SEH).
            "WINEDEBUG": "fixme-all,err+all,warn+module",
            "GST_DEBUG": "1"
            // NOTE: no DYLD_*_LIBRARY_PATH here on purpose. Wine strips those from the
            // target process, and modern dyld's default fallback only searches /usr/lib,
            // so an env var cannot feed Wine the x86_64 libgnutls/libMoltenVK it dlopen()s
            // by leaf name. Those libs are instead placed physically in Wine's own `lib`
            // dir by WineRuntimeInstaller.installRuntimeLibraries(), which Wine's loader
            // does search. See that method for the full rationale.
        ]
        bottle.settings.environmentVariables(wineEnv: &result, resolvedRenderer: resolvedRenderer)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    private static func rendererFolders(architecture: String) -> [URL] {
        [d3dMetalFolder, dxmtFolder, dxvkFolder].map { $0.appending(path: architecture) }
    }

    private static func rendererDLLsExist(in folder: URL, required: [String]) -> Bool {
        required.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false))
        }
    }

    private static func graphicsEnvironment(for renderer: GraphicsRenderer) -> [String: String] {
        guard renderer == .d3dMetal else { return [:] }
        let external = d3dMetalFolder.appending(path: "external")
        let frameworkRoot = FileManager.default.fileExists(atPath: external.path(percentEncoded: false))
            ? external : d3dMetalFolder
        let sharedLibrary = frameworkRoot.appending(path: "libd3dshared.dylib")
        var result = [
            "DYLD_FRAMEWORK_PATH": frameworkRoot.path,
            "DYLD_LIBRARY_PATH": frameworkRoot.path
        ]
        if FileManager.default.fileExists(atPath: sharedLibrary.path(percentEncoded: false)) {
            result["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = sharedLibrary.path
        }
        return result
    }
}

public enum GraphicsRendererError: LocalizedError {
    case backendNotInstalled(GraphicsRenderer)

    public var errorDescription: String? {
        switch self {
        case .backendNotInstalled(let renderer):
            return "\(renderer.displayName) is not installed in the current Wine runtime."
        }
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.gameVerseBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}

//
//  WineRuntimeSource.swift
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

/// Local artifact produced by `scripts/build-gameverse-runtime.sh`. The engine is compiled
/// from CodeWeavers' published CrossOver 26 Wine source (Wine 11.0 plus its macOS/D3DMetal
/// integration patches). Apple's closed-source D3DMetal files are supplied by the builder
/// after accepting Apple's license; they are intentionally not stored in this repository.
public enum WineRuntimeSource {
    public static var tarballURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.gameVerseBundleIdentifier)
            .appending(path: "WineRuntimeDist")
            .appending(path: "GameVerseRuntime-CX26-GPTK3.tar.gz")
    }
}

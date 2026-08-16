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

/// Where to obtain the Wine runtime tarball: a self-built Wine 11.0 core (compiled from
/// the official wine-mirror source, with gnutls enabled for bcrypt/package-signature support)
/// — replacing the old WhiskyWine 2.5.0 (Wine 7.7) bundle, whose upstream
/// `data.getwhisky.app/Wine` endpoint is dead and whose wine core is too old for current Steam
/// (steamwebhelper/CEF and general Win32 API compatibility).
/// GPTK 4.0 beta 2's D3DMetal bridge is deliberately NOT merged into this build: it requires
/// wine source patches (e.g. Mythic's crossover branch) that vanilla wine-mirror lacks, and
/// merging it caused a wine-core crash during Steam's self-update. DXVK remains the working
/// GPU-acceleration path. Distributed as a local file since there is no hosted CDN for this
/// personal build.
public enum WineRuntimeSource {
    public static let tarballURLString =
        // swiftlint:disable:next line_length
        "file:///Users/macbook/Library/Application%20Support/com.mrmengsea.GameVerse/WineRuntimeDist/GameVerseWineRuntime-11-nogptk.tar.gz"

    public static var tarballURL: URL? {
        URL(string: tarballURLString)
    }
}

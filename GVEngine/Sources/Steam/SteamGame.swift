//
//  SteamGame.swift
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

/// A Steam game discovered by scanning a bottle's Steam library manifests
/// directly — no Steam client UI interaction required to list it.
public struct SteamGame: Identifiable, Equatable {
    public let appId: Int
    public let name: String
    public let installDir: URL
    public let iconURL: URL?

    public var id: Int { appId }

    public init(appId: Int, name: String, installDir: URL, iconURL: URL?) {
        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.iconURL = iconURL
    }
}

//
//  SteamVDF.swift
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

/// A value in Valve's KeyValues/VDF text format: either a leaf string or a
/// nested object. Steam uses this format for `libraryfolders.vdf` and
/// `appmanifest_<id>.acf`.
public indirect enum VDFValue: Equatable {
    case string(String)
    case object([String: VDFValue])
}

/// Minimal recursive-descent parser for Valve's KeyValues/VDF format.
/// No third-party dependency covers this narrow a need.
public enum SteamVDF {
    public static func parse(_ text: String) -> [String: VDFValue] {
        var chars = Array(text)[...]
        return parseObjectBody(&chars)
    }

    private static func parseObjectBody(_ chars: inout ArraySlice<Character>) -> [String: VDFValue] {
        var result: [String: VDFValue] = [:]
        while let key = nextToken(&chars) {
            if key == "}" { break }
            guard let peeked = peekNextToken(&chars) else { break }
            if peeked == "{" {
                _ = nextToken(&chars)
                result[key] = .object(parseObjectBody(&chars))
            } else if let value = nextToken(&chars) {
                result[key] = .string(value)
            }
        }
        return result
    }

    private static func skipWhitespaceAndComments(_ chars: inout ArraySlice<Character>) {
        while let first = chars.first {
            if first.isWhitespace {
                chars.removeFirst()
            } else if first == "/", chars.dropFirst().first == "/" {
                while let next = chars.first, next != "\n" {
                    chars.removeFirst()
                }
            } else {
                break
            }
        }
    }

    private static func peekNextToken(_ chars: inout ArraySlice<Character>) -> String? {
        let checkpoint = chars
        let token = nextToken(&chars)
        chars = checkpoint
        return token
    }

    private static func nextToken(_ chars: inout ArraySlice<Character>) -> String? {
        skipWhitespaceAndComments(&chars)
        guard let first = chars.first else { return nil }

        if first == "{" || first == "}" {
            chars.removeFirst()
            return String(first)
        }

        guard first == "\"" else {
            chars.removeFirst()
            return nextToken(&chars)
        }
        chars.removeFirst()

        var result = ""
        while let char = chars.first {
            chars.removeFirst()
            if char == "\\" {
                if let escaped = chars.first {
                    chars.removeFirst()
                    result.append(escaped)
                }
            } else if char == "\"" {
                break
            } else {
                result.append(char)
            }
        }
        return result
    }
}

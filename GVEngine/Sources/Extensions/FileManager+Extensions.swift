//
//  FileManager+Extensions.swift
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

extension FileManager {
    func replaceDLLs(
        in destinationDirectory: URL, withContentsIn sourceDirectory: URL, makeOriginalCopy: Bool = true
    ) throws {
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "dll" else { continue }
            let originalURL = destinationDirectory.appending(path: fileURL.lastPathComponent)
            try FileManager.default.replaceFile(at: originalURL, with: fileURL, makeOriginalCopy: makeOriginalCopy)
        }
    }

    /// Restore Wine's original DLLs after a translation backend was installed.
    /// Backend files without a matching original (for example DXMT's
    /// `winemetal.dll`) are removed using the renderer's source directory.
    func restoreDLLs(
        in destinationDirectory: URL, installedFrom sourceDirectories: [URL], builtinDirectory: URL
    ) throws {
        for sourceDirectory in sourceDirectories {
            let enumerator = enumerator(at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey])
            while let sourceURL = enumerator?.nextObject() as? URL {
                guard sourceURL.pathExtension.lowercased() == "dll" else { continue }
                let activeURL = destinationDirectory.appending(path: sourceURL.lastPathComponent)
                let originalURL = activeURL.appendingPathExtension("orig")
                if fileExists(atPath: originalURL.path(percentEncoded: false)) {
                    if fileExists(atPath: activeURL.path(percentEncoded: false)) {
                        try removeItem(at: activeURL)
                    }
                    try moveItem(at: originalURL, to: activeURL)
                } else {
                    let builtinURL = builtinDirectory.appending(path: sourceURL.lastPathComponent)
                    if fileExists(atPath: activeURL.path(percentEncoded: false)) {
                        try removeItem(at: activeURL)
                    }
                    if fileExists(atPath: builtinURL.path(percentEncoded: false)) {
                        try copyItem(at: builtinURL, to: activeURL)
                    }
                }
            }
        }
    }

    func replaceFile(at originalURL: URL, with replacementURL: URL, makeOriginalCopy: Bool = true) throws {
        if fileExists(atPath: originalURL.path(percentEncoded: false)) {
            if makeOriginalCopy {
                let copyURL = originalURL.appendingPathExtension("orig")

                if fileExists(atPath: copyURL.path(percentEncoded: false)) {
                    // Preserve the first backup: it is Wine's builtin DLL, while
                    // the current file may belong to another renderer.
                    try FileManager.default.removeItem(at: originalURL)
                } else {
                    try FileManager.default.moveItem(at: originalURL, to: copyURL)
                }
            } else {
                try FileManager.default.removeItem(at: originalURL)
            }
        }
        try FileManager.default.copyItem(at: replacementURL, to: originalURL)
    }
}

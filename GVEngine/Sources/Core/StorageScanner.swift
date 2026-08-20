//
//  StorageScanner.swift
//  GVEngine
//

import Foundation

/// Calculates the logical size of installed game content. This intentionally
/// performs no caching or UI work so callers can run it on a utility task.
public enum StorageScanner {
    public static func logicalSize(of url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ]
        let rootValues = try url.resourceValues(forKeys: keys)

        if rootValues.isSymbolicLink == true {
            return 0
        }
        if rootValues.isRegularFile == true {
            return Int64(rootValues.fileSize ?? 0)
        }
        guard rootValues.isDirectory == true else { return 0 }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var total: Int64 = 0
        while let candidate = enumerator.nextObject() as? URL {
            guard let values = try? candidate.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

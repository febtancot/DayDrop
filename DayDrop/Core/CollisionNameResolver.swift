import Foundation

/// Produces a non-overwriting destination name by inserting ` (n)` before the
/// final extension.
enum CollisionNameResolver {
    static func availableName(
        for originalFileName: String,
        isDirectory: Bool = false,
        isTaken: (String) -> Bool
    ) -> String {
        guard isTaken(originalFileName) else {
            return originalFileName
        }

        let parts = isDirectory ? (stem: originalFileName, extensionWithDot: "") : splitFileName(originalFileName)
        var suffixNumber = 1

        while true {
            let candidate = "\(parts.stem) (\(suffixNumber))\(parts.extensionWithDot)"
            if !isTaken(candidate) {
                return candidate
            }
            suffixNumber += 1
        }
    }

    static func availableURL(
        for desiredURL: URL,
        isDirectory: Bool = false,
        fileExists: (URL) -> Bool
    ) -> URL {
        let parentURL = desiredURL.deletingLastPathComponent()
        let availableName = availableName(for: desiredURL.lastPathComponent, isDirectory: isDirectory) { candidateName in
            fileExists(parentURL.appendingPathComponent(candidateName, isDirectory: isDirectory))
        }
        return parentURL.appendingPathComponent(availableName, isDirectory: isDirectory)
    }

    private static func splitFileName(_ fileName: String) -> (stem: String, extensionWithDot: String) {
        guard
            let dotIndex = fileName.lastIndex(of: "."),
            dotIndex != fileName.startIndex,
            fileName.index(after: dotIndex) != fileName.endIndex
        else {
            return (fileName, "")
        }

        return (
            String(fileName[..<dotIndex]),
            String(fileName[dotIndex...])
        )
    }
}

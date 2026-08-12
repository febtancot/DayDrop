import Foundation

public struct SecurityScopedBookmarkResolution: Sendable {
    public let url: URL
    public let wasStale: Bool
    public let rebuiltStaleBookmark: Bool

    public init(url: URL, wasStale: Bool, rebuiltStaleBookmark: Bool) {
        self.url = url
        self.wasStale = wasStale
        self.rebuiltStaleBookmark = rebuiltStaleBookmark
    }
}

public enum DownloadsBookmarkError: Error, LocalizedError {
    case noSavedBookmark
    case unableToStartSecurityScopedAccess(URL)

    public var errorDescription: String? {
        switch self {
        case .noSavedBookmark:
            return "No Downloads folder authorization has been saved."
        case .unableToStartSecurityScopedAccess(let url):
            return "Unable to access the authorized folder at \(url.path)."
        }
    }
}

/// Owns one balanced security-scope access. Calling `stop()` more than once is safe.
public final class SecurityScopedFolderAccess: @unchecked Sendable {
    public let url: URL
    public let isSecurityScopeActive: Bool

    private let lock = NSLock()
    private var hasStopped = false

    fileprivate init(url: URL, requireSecurityScope: Bool) throws {
        self.url = url
        let didStart = url.startAccessingSecurityScopedResource()
        self.isSecurityScopeActive = didStart

        if requireSecurityScope && !didStart {
            throw DownloadsBookmarkError.unableToStartSecurityScopedAccess(url)
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard !hasStopped else {
            return
        }
        hasStopped = true

        if isSecurityScopeActive {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stop()
    }
}

/// Persists the user-selected Downloads bookmark and rebuilds stale bookmark data
/// from the resolved URL before returning it to the caller.
public final class DownloadsBookmarkStore: @unchecked Sendable {
    public static let defaultBookmarkKey = "DayDrop.DownloadsSecurityScopedBookmark"

    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        bookmarkKey: String = DownloadsBookmarkStore.defaultBookmarkKey
    ) {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
    }

    public var hasSavedBookmark: Bool {
        withLock {
            defaults.data(forKey: bookmarkKey) != nil
        }
    }

    public func saveBookmark(for folderURL: URL) throws {
        let bookmark = try Self.makeBookmark(for: folderURL)
        withLock {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
    }

    /// Explicit alias used when the user grants access to a replacement folder.
    public func refreshBookmark(for folderURL: URL) throws {
        try saveBookmark(for: folderURL)
    }

    public func clearBookmark() {
        withLock {
            defaults.removeObject(forKey: bookmarkKey)
        }
    }

    /// Resolves the saved URL. By default, stale data is immediately regenerated and
    /// atomically replaced in UserDefaults while the store lock is held.
    public func resolveBookmark(rebuildIfStale: Bool = true) throws -> SecurityScopedBookmarkResolution {
        try withLock {
            guard let bookmark = defaults.data(forKey: bookmarkKey) else {
                throw DownloadsBookmarkError.noSavedBookmark
            }

            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            var rebuilt = false
            if isStale && rebuildIfStale {
                let refreshedBookmark = try Self.makeBookmark(for: url)
                defaults.set(refreshedBookmark, forKey: bookmarkKey)
                rebuilt = true
            }

            return SecurityScopedBookmarkResolution(
                url: url,
                wasStale: isStale,
                rebuiltStaleBookmark: rebuilt
            )
        }
    }

    /// Resolves and starts a balanced security scope suitable for retaining while the
    /// monitor is active. Unsandboxed diagnostic callers can set `requireSecurityScope`
    /// to false because macOS may report that no scoped access was needed.
    public func beginAccessingDownloadsFolder(
        rebuildIfStale: Bool = true,
        requireSecurityScope: Bool = true
    ) throws -> SecurityScopedFolderAccess {
        let resolution = try resolveBookmark(rebuildIfStale: rebuildIfStale)
        return try SecurityScopedFolderAccess(
            url: resolution.url,
            requireSecurityScope: requireSecurityScope
        )
    }

    private static func makeBookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    @discardableResult
    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

public typealias SecurityScopedBookmarkStore = DownloadsBookmarkStore

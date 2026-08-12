import Darwin
import Dispatch
import Foundation

public struct DirectoryChangeEvent: @unchecked Sendable {
    public let directoryURL: URL
    public let flags: DispatchSource.FileSystemEvent
    public let observedAt: Date

    public init(
        directoryURL: URL,
        flags: DispatchSource.FileSystemEvent,
        observedAt: Date = Date()
    ) {
        self.directoryURL = directoryURL
        self.flags = flags
        self.observedAt = observedAt
    }

    /// The watched directory inode is no longer a dependable source. The coordinator
    /// should call `rearm()` after the directory is available at its expected path.
    public var requiresRearm: Bool {
        !flags.intersection([.delete, .rename, .revoke]).isEmpty
    }
}

public enum DirectoryEventMonitorError: Error, LocalizedError {
    case notDirectory(URL)
    case unableToOpen(URL, errno: Int32)
    case notStarted

    public var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "The monitored URL is not a directory: \(url.path)"
        case .unableToOpen(let url, let errorNumber):
            let message = String(cString: strerror(errorNumber))
            return "Unable to monitor \(url.path): \(message)"
        case .notStarted:
            return "The directory monitor has not been started."
        }
    }
}

/// A file-descriptor-backed directory watcher. All state transitions happen on one
/// private serial queue, and every descriptor is closed exactly once by its source's
/// cancellation handler.
public final class DirectoryEventMonitor: @unchecked Sendable {
    public typealias EventHandler = @Sendable (DirectoryChangeEvent) -> Void

    public static var defaultEventMask: DispatchSource.FileSystemEvent {
        [
            .write,
            .delete,
            .extend,
            .attrib,
            .link,
            .rename,
            .revoke
        ]
    }

    public let directoryURL: URL

    private let eventMask: DispatchSource.FileSystemEvent
    private let callbackQueue: DispatchQueue
    private let stateQueue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var source: DispatchSourceFileSystemObject?
    private var handler: EventHandler?
    private var sourceGeneration: UInt64 = 0
    private var sessionGeneration: UInt64 = 0

    public init(
        directoryURL: URL,
        eventMask: DispatchSource.FileSystemEvent = DirectoryEventMonitor.defaultEventMask,
        callbackQueue: DispatchQueue = .main
    ) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.eventMask = eventMask
        self.callbackQueue = callbackQueue
        self.stateQueue = DispatchQueue(
            label: "com.liuyuhang.DayDrop.directory-monitor.\(UUID().uuidString)",
            qos: .utility
        )
        self.stateQueue.setSpecific(key: queueKey, value: 1)
    }

    public var isRunning: Bool {
        syncOnStateQueue {
            source != nil
        }
    }

    /// Starting an already-running monitor only replaces its callback.
    public func start(handler newHandler: @escaping EventHandler) throws {
        try syncOnStateQueue {
            let beginsNewSession = handler == nil
            handler = newHandler
            if beginsNewSession {
                sessionGeneration &+= 1
            }

            guard source == nil else {
                return
            }

            do {
                try installSource()
            } catch {
                if beginsNewSession {
                    handler = nil
                    sessionGeneration &+= 1
                }
                throw error
            }
        }
    }

    public func stop() {
        syncOnStateQueue {
            handler = nil
            sessionGeneration &+= 1
            cancelCurrentSource()
        }
    }

    /// Closes the current descriptor and opens a fresh one for the same path. If the
    /// path is temporarily unavailable, the callback remains installed so a later
    /// `rearm()` can retry without another `start(handler:)` call.
    public func rearm() throws {
        try syncOnStateQueue {
            guard handler != nil else {
                throw DirectoryEventMonitorError.notStarted
            }

            cancelCurrentSource()
            try installSource()
        }
    }

    deinit {
        stop()
    }

    private func installSource() throws {
        let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw DirectoryEventMonitorError.notDirectory(directoryURL)
        }

        let descriptor = Darwin.open(directoryURL.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw DirectoryEventMonitorError.unableToOpen(directoryURL, errno: errno)
        }

        sourceGeneration &+= 1
        let installedGeneration = sourceGeneration
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: stateQueue
        )

        newSource.setCancelHandler {
            Darwin.close(descriptor)
        }
        newSource.setEventHandler { [weak self] in
            self?.receiveEvent(from: installedGeneration)
        }

        source = newSource
        newSource.resume()
    }

    private func cancelCurrentSource() {
        sourceGeneration &+= 1
        let oldSource = source
        source = nil
        oldSource?.setEventHandler {}
        oldSource?.cancel()
    }

    private func receiveEvent(from installedGeneration: UInt64) {
        guard installedGeneration == sourceGeneration,
              let source,
              let handler
        else {
            return
        }

        let flags = source.data
        guard !flags.isEmpty else {
            return
        }

        let event = DirectoryChangeEvent(directoryURL: directoryURL, flags: flags)
        let deliverySession = sessionGeneration
        callbackQueue.async { [weak self] in
            guard let self,
                  self.isSessionActive(deliverySession)
            else {
                return
            }
            handler(event)
        }
    }

    private func isSessionActive(_ expectedSession: UInt64) -> Bool {
        syncOnStateQueue {
            sessionGeneration == expectedSession && handler != nil
        }
    }

    private func syncOnStateQueue<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try operation()
        }
        return try stateQueue.sync(execute: operation)
    }
}

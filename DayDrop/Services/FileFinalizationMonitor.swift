import Darwin
import Dispatch
import Foundation

struct FileFinalizationEvent: @unchecked Sendable {
    let fileURL: URL
    let flags: DispatchSource.FileSystemEvent
    let observedAt: Date
    let observedUptime: TimeInterval

    var invalidatesMonitor: Bool {
        !flags.intersection([.delete, .revoke]).isEmpty
    }
}

enum FileFinalizationMonitorError: Error, LocalizedError {
    case unableToOpen(URL, errno: Int32)
    case notRegularFile(URL)

    var errorDescription: String? {
        switch self {
        case .unableToOpen(let url, let errorNumber):
            return "无法监听文件落盘状态：\(url.lastPathComponent)（\(String(cString: strerror(errorNumber)))）"
        case .notRegularFile(let url):
            return "只能监听普通文件的落盘状态：\(url.lastPathComponent)"
        }
    }
}

/// Watches one already-discovered file descriptor for writes and lifecycle
/// changes. The descriptor follows the same inode across a rename, while the
/// coordinator separately revalidates the current path and filesystem identity.
final class FileFinalizationMonitor: @unchecked Sendable {
    typealias EventHandler = @Sendable (FileFinalizationEvent) -> Void

    static var defaultEventMask: DispatchSource.FileSystemEvent {
        [.write, .extend, .attrib, .rename, .delete, .revoke]
    }

    let fileURL: URL

    private let eventMask: DispatchSource.FileSystemEvent
    private let callbackQueue: DispatchQueue
    private let stateQueue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var source: DispatchSourceFileSystemObject?
    private var handler: EventHandler?
    private var lastActivityUptime: TimeInterval?
    private var invalidated = false
    private var generation: UInt64 = 0

    init(
        fileURL: URL,
        eventMask: DispatchSource.FileSystemEvent = FileFinalizationMonitor.defaultEventMask,
        callbackQueue: DispatchQueue = .main
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.eventMask = eventMask
        self.callbackQueue = callbackQueue
        self.stateQueue = DispatchQueue(
            label: "com.liuyuhang.DayDrop.file-finalization.\(UUID().uuidString)",
            qos: .utility
        )
        self.stateQueue.setSpecific(key: queueKey, value: 1)
    }

    var isRunning: Bool {
        syncOnStateQueue { source != nil && !invalidated }
    }

    func start(
        observedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        handler newHandler: @escaping EventHandler
    ) throws {
        try syncOnStateQueue {
            handler = newHandler
            guard source == nil else { return }

            let descriptor = Darwin.open(
                fileURL.path,
                O_EVTONLY | O_CLOEXEC | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                handler = nil
                throw FileFinalizationMonitorError.unableToOpen(fileURL, errno: errno)
            }

            var status = stat()
            guard fstat(descriptor, &status) == 0,
                  status.st_mode & S_IFMT == S_IFREG
            else {
                Darwin.close(descriptor)
                handler = nil
                throw FileFinalizationMonitorError.notRegularFile(fileURL)
            }

            generation &+= 1
            let installedGeneration = generation
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

            lastActivityUptime = observedUptime
            invalidated = false
            source = newSource
            newSource.resume()
        }
    }

    func stop() {
        syncOnStateQueue {
            generation &+= 1
            handler = nil
            lastActivityUptime = nil
            invalidated = false
            let oldSource = source
            source = nil
            oldSource?.setEventHandler {}
            oldSource?.cancel()
        }
    }

    func hasBeenQuiet(
        for interval: TimeInterval,
        atUptime uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        syncOnStateQueue {
            guard source != nil,
                  !invalidated,
                  let lastActivityUptime
            else {
                return false
            }
            return uptime - lastActivityUptime >= interval
        }
    }

    deinit {
        stop()
    }

    private func receiveEvent(from installedGeneration: UInt64) {
        guard installedGeneration == generation,
              let source,
              let handler
        else {
            return
        }

        let flags = source.data
        guard !flags.isEmpty else { return }

        let observedAt = Date()
        let observedUptime = ProcessInfo.processInfo.systemUptime
        lastActivityUptime = observedUptime
        if !flags.intersection([.delete, .revoke]).isEmpty {
            invalidated = true
        }
        let event = FileFinalizationEvent(
            fileURL: fileURL,
            flags: flags,
            observedAt: observedAt,
            observedUptime: observedUptime
        )
        callbackQueue.async { [weak self] in
            guard let self, self.generationIsActive(installedGeneration) else { return }
            handler(event)
        }
    }

    private func generationIsActive(_ expectedGeneration: UInt64) -> Bool {
        syncOnStateQueue {
            generation == expectedGeneration && source != nil && handler != nil
        }
    }

    private func syncOnStateQueue<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try operation()
        }
        return try stateQueue.sync(execute: operation)
    }
}

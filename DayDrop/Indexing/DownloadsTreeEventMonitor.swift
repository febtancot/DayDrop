import CoreServices
import Dispatch
import Foundation

struct DownloadsTreeChangeEvent: @unchecked Sendable {
    let paths: [String]
    let flags: [FSEventStreamEventFlags]
    let latestEventID: FSEventStreamEventId
    let observedAt: Date

    var requiresFullScan: Bool {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        return flags.contains { $0 & rescanFlags != 0 }
    }
}

enum DownloadsTreeEventMonitorError: Error, LocalizedError {
    case unableToCreateStream(URL)
    case unableToStartStream(URL)

    var errorDescription: String? {
        switch self {
        case .unableToCreateStream(let url):
            return "无法创建下载目录递归监听：\(url.path)"
        case .unableToStartStream(let url):
            return "无法启动下载目录递归监听：\(url.path)"
        }
    }
}

/// FSEvents recursively observes the authorized Downloads hierarchy. Events only
/// trigger reconciliation; the recursive scanner remains the source of truth.
final class DownloadsTreeEventMonitor: @unchecked Sendable {
    typealias EventHandler = @Sendable (DownloadsTreeChangeEvent) -> Void

    let rootURL: URL

    private let latency: CFTimeInterval
    private let callbackQueue: DispatchQueue
    private let eventQueue: DispatchQueue
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var handler: EventHandler?

    init(
        rootURL: URL,
        latency: CFTimeInterval = 0.35,
        callbackQueue: DispatchQueue = .main
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.latency = latency
        self.callbackQueue = callbackQueue
        self.eventQueue = DispatchQueue(
            label: "com.liuyuhang.DayDrop.downloads-tree-events.\(UUID().uuidString)",
            qos: .utility
        )
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stream != nil
    }

    func start(handler newHandler: @escaping EventHandler) throws {
        lock.lock()
        defer { lock.unlock() }
        handler = newHandler
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            createFlags
        ) else {
            handler = nil
            throw DownloadsTreeEventMonitorError.unableToCreateStream(rootURL)
        }

        FSEventStreamSetDispatchQueue(newStream, eventQueue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            handler = nil
            throw DownloadsTreeEventMonitorError.unableToStartStream(rootURL)
        }
        stream = newStream
    }

    func stop() {
        lock.lock()
        let oldStream = stream
        stream = nil
        handler = nil
        lock.unlock()

        guard let oldStream else { return }
        FSEventStreamStop(oldStream)
        FSEventStreamInvalidate(oldStream)
        FSEventStreamRelease(oldStream)
    }

    deinit {
        stop()
    }

    private static let callback: FSEventStreamCallback = {
        _, context, eventCount, eventPaths, eventFlags, eventIDs in
        guard let context else { return }
        let monitor = Unmanaged<DownloadsTreeEventMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()
        let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self)
        let paths = (cfPaths as? [String]) ?? []
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: eventCount))
        let ids = Array(UnsafeBufferPointer(start: eventIDs, count: eventCount))
        monitor.deliver(paths: paths, flags: flags, ids: ids)
    }

    private func deliver(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        ids: [FSEventStreamEventId]
    ) {
        lock.lock()
        let activeHandler = handler
        let active = stream != nil
        lock.unlock()
        guard active, let activeHandler else { return }

        let event = DownloadsTreeChangeEvent(
            paths: paths,
            flags: flags,
            latestEventID: ids.max() ?? 0,
            observedAt: Date()
        )
        callbackQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            activeHandler(event)
        }
    }
}

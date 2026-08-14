import Foundation

enum FileFinalizationObservation: Equatable, Sendable {
    case settling
    case quiet
}

/// Tracks metadata stability independently from the vnode event monitor.
///
/// Some download managers preallocate the final byte count and then write into
/// the allocated range. Comparing size alone therefore cannot establish that
/// the file has stopped changing; the modification date and filesystem events
/// must remain quiet for the whole settling interval as well.
struct FileFinalizationTracker: Equatable, Sendable {
    let quietInterval: TimeInterval

    private(set) var lastSize: UInt64?
    private(set) var lastModificationDate: Date?
    private(set) var lastActivityUptime: TimeInterval

    init(
        size: UInt64?,
        modificationDate: Date?,
        observedUptime: TimeInterval,
        quietInterval: TimeInterval
    ) {
        self.quietInterval = quietInterval
        self.lastSize = size
        self.lastModificationDate = modificationDate
        self.lastActivityUptime = observedUptime
    }

    mutating func observe(
        size: UInt64?,
        modificationDate: Date?,
        atUptime observedUptime: TimeInterval
    ) -> FileFinalizationObservation {
        if size != lastSize || modificationDate != lastModificationDate {
            lastSize = size
            lastModificationDate = modificationDate
            lastActivityUptime = observedUptime
            return .settling
        }

        return observedUptime - lastActivityUptime >= quietInterval
            ? .quiet
            : .settling
    }

    mutating func recordFilesystemActivity(atUptime observedUptime: TimeInterval) {
        if observedUptime > lastActivityUptime {
            lastActivityUptime = observedUptime
        }
    }
}

import Foundation

enum FileSizeStabilityState: Equatable, Sendable {
    case awaitingFirstSample
    case awaitingMatchingSample(previousSize: UInt64)
    case stable(size: UInt64)
}

enum FileSizeStabilityObservation: Equatable, Sendable {
    case needsAnotherSample
    case stable
}

/// Requires two consecutive equal-size observations before a file is considered stable.
///
/// A coordinator should keep one tracker per candidate URL and call `reset()` when the
/// candidate disappears or becomes ineligible.
struct FileSizeStabilityTracker: Equatable, Sendable {
    private(set) var state: FileSizeStabilityState = .awaitingFirstSample

    var isStable: Bool {
        if case .stable = state {
            return true
        }
        return false
    }

    @discardableResult
    mutating func observe(size: UInt64) -> FileSizeStabilityObservation {
        switch state {
        case .awaitingFirstSample:
            state = .awaitingMatchingSample(previousSize: size)
            return .needsAnotherSample

        case let .awaitingMatchingSample(previousSize):
            if size == previousSize {
                state = .stable(size: size)
                return .stable
            }

            state = .awaitingMatchingSample(previousSize: size)
            return .needsAnotherSample

        case let .stable(stableSize):
            if size == stableSize {
                return .stable
            }

            state = .awaitingMatchingSample(previousSize: size)
            return .needsAnotherSample
        }
    }

    mutating func reset() {
        state = .awaitingFirstSample
    }
}

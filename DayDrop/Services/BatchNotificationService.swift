import Foundation
import UserNotifications

public protocol DayDropNotificationCenter: AnyObject {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
    func getNotificationSettings(
        completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void
    )
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: DayDropNotificationCenter {}

public enum BatchNotificationError: Error, Equatable, LocalizedError {
    case negativeCount

    public var errorDescription: String? {
        "Notification counts cannot be negative."
    }
}

/// Requests permission and submits one quiet summary per completed organization batch.
public final class BatchNotificationService: @unchecked Sendable {
    private let center: DayDropNotificationCenter

    public init(center: DayDropNotificationCenter = UNUserNotificationCenter.current()) {
        self.center = center
    }

    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Returns false when there is nothing to report or the user has not authorized
    /// notifications. Authorization prompts are kept separate from batch delivery.
    @discardableResult
    public func sendBatchNotification(
        succeededCount: Int,
        failedCount: Int
    ) async throws -> Bool {
        guard succeededCount >= 0, failedCount >= 0 else {
            throw BatchNotificationError.negativeCount
        }
        guard succeededCount + failedCount > 0 else {
            return false
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "DayDrop 整理完成"
        content.body = Self.message(
            succeededCount: succeededCount,
            failedCount: failedCount
        )
        content.sound = .default
        content.threadIdentifier = "daydrop.organization"

        let request = UNNotificationRequest(
            identifier: "daydrop.batch.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return true
    }

    private static func message(succeededCount: Int, failedCount: Int) -> String {
        switch (succeededCount, failedCount) {
        case (_, 0):
            return "已整理 \(succeededCount) 个文件。"
        case (0, _):
            return "\(failedCount) 个文件整理失败，原文件已保留。"
        default:
            return "已整理 \(succeededCount) 个文件，\(failedCount) 个失败。"
        }
    }
}

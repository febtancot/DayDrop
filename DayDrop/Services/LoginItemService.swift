import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

/// Main-app login-item facade for a MainActor coordinator or SwiftUI binding.
@MainActor
public final class LoginItemService {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var state: LoginItemState {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    public var isEnabled: Bool {
        state == .enabled
    }

    /// Registration remains subject to the user's Login Items approval. A denied
    /// request is surfaced to the coordinator as the original ServiceManagement error.
    public func setEnabled(_ shouldEnable: Bool) throws {
        if shouldEnable {
            guard service.status != .enabled else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered,
                  service.status != .notFound
            else {
                return
            }
            try service.unregister()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

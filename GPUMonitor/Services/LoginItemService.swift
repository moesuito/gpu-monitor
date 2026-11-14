import Foundation
import ServiceManagement

enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled:
            return false
        }
    }
}

protocol LoginItemManaging: Sendable {
    func currentState() -> LoginItemState
    func setEnabled(_ enabled: Bool) throws -> LoginItemState
}

/// Manages opt-in launch at login (disabled by default) via `SMAppService.mainApp`.
struct MainAppLoginItemManager: LoginItemManaging {
    func currentState() -> LoginItemState {
        Self.mapStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemState {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            let current = Self.mapStatus(SMAppService.mainApp.status)
            if current != .disabled {
                try SMAppService.mainApp.unregister()
            }
        }
        return Self.mapStatus(SMAppService.mainApp.status)
    }

    static func mapStatus(_ status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }
}

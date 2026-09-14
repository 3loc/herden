import Foundation

/// Why Notification Registration failed. Kept separate from the registration
/// model because the SSH transport is also compiled into the Share Extension.
enum NotificationRegistrationError: Error, Sendable, Equatable {
    case pluginNotInstalled
    case pluginProbeFailed(detail: String)
    case readFailed(detail: String)
    case writeFailed(detail: String)
    case unsupportedFileVersion(Int)
    case deviceNotRegistered
}

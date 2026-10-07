import Foundation

public struct CommandResponse: Codable, Equatable, Sendable {
    public let accepted: Bool
    public let state: RoomState?

    public init(accepted: Bool, state: RoomState?) {
        self.accepted = accepted
        self.state = state
    }
}

struct APIErrorPayload: Decodable, Sendable {
    let code: String?
    let message: String?
}

public enum DevicePanelError: Error, Equatable, Sendable {
    case invalidServerURL
    case authenticationRequired
    case permissionDenied
    case offline
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case server(status: Int, code: String?, message: String?)
    case keychain(status: Int32)
    case storage
}

extension DevicePanelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Enter a valid HTTPS Device Panel address."
        case .authenticationRequired:
            "Your session has expired. Sign in again."
        case .permissionDenied:
            "This account cannot control the room."
        case .offline:
            "Device Panel is offline. Check your connection and try again."
        case .timedOut:
            "Device Panel took too long to respond."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Too many requests. Try again in \(Int(retryAfter.rounded())) seconds."
            } else {
                "Too many requests. Wait a moment and try again."
            }
        case .invalidResponse:
            "Device Panel returned an unexpected response."
        case let .server(_, _, message):
            message ?? "Device Panel could not complete the request."
        case .keychain, .storage:
            "Secure storage is unavailable."
        }
    }
}

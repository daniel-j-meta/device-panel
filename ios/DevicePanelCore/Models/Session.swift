import Foundation

public struct Session: Codable, Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let serverLabel: String

    public init(token: String, expiresAt: Date, serverLabel: String) {
        self.token = token
        self.expiresAt = expiresAt
        self.serverLabel = serverLabel
    }

    public var isExpired: Bool {
        expiresAt <= Date()
    }
}

public struct SignInRequest: Codable, Equatable, Sendable {
    public let password: String
    public let clientId: UUID
    public let deviceName: String

    public init(password: String, clientId: UUID, deviceName: String) {
        self.password = password
        self.clientId = clientId
        self.deviceName = deviceName
    }
}

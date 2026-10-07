import Foundation

public enum RoomColor: String, Codable, CaseIterable, Sendable {
    case red
    case orange
}

public struct RoomChanges: Codable, Equatable, Sendable {
    public let on: Bool?
    public let brightness: Int?
    public let colorTemperaturePct: Double?
    public let color: RoomColor?

    public init(
        on: Bool? = nil,
        brightness: Int? = nil,
        colorTemperaturePct: Double? = nil,
        color: RoomColor? = nil
    ) throws {
        if let brightness, !(1 ... 100).contains(brightness) {
            throw RoomModelError.invalidBrightness(brightness)
        }
        if let colorTemperaturePct, !(0 ... 100).contains(colorTemperaturePct) {
            throw RoomModelError.invalidColorTemperature(colorTemperaturePct)
        }
        guard on != nil || brightness != nil || colorTemperaturePct != nil || color != nil else {
            throw RoomModelError.emptyChanges
        }
        self.on = on
        self.brightness = brightness
        self.colorTemperaturePct = colorTemperaturePct
        self.color = color
    }
}

public struct RoomCommand: Codable, Equatable, Sendable {
    public let commandId: UUID
    public let clientId: UUID
    public let revision: Int64
    public let changes: RoomChanges

    public init(commandId: UUID = UUID(), clientId: UUID, revision: Int64, changes: RoomChanges) {
        self.commandId = commandId
        self.clientId = clientId
        self.revision = revision
        self.changes = changes
    }
}

public struct ReconcileRequest: Codable, Equatable, Sendable {
    public let clientId: UUID
    public let revision: Int64
    public let on: Bool
    public let brightness: Int?
    public let colorTemperaturePct: Double?

    public init(
        clientId: UUID,
        revision: Int64,
        on: Bool,
        brightness: Int?,
        colorTemperaturePct: Double?
    ) {
        self.clientId = clientId
        self.revision = revision
        self.on = on
        self.brightness = brightness
        self.colorTemperaturePct = colorTemperaturePct
    }
}

public struct ReconcileResponse: Codable, Equatable, Sendable {
    public let state: RoomState?
    public let synchronized: Bool
    public let corrected: [String]
    public let stale: Bool

    public init(state: RoomState?, synchronized: Bool, corrected: [String], stale: Bool) {
        self.state = state
        self.synchronized = synchronized
        self.corrected = corrected
        self.stale = stale
    }
}

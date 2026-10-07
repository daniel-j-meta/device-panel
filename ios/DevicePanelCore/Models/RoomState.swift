import Foundation

public enum RoomColorMode: Equatable, Sendable {
    case temperature
    case red
    case orange
    case unknown(String)
}

extension RoomColorMode: Codable {
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "temperature": self = .temperature
        case "red": self = .red
        case "orange": self = .orange
        default: self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: String = switch self {
        case .temperature: "temperature"
        case .red: "red"
        case .orange: "orange"
        case let .unknown(value): value
        }
        try container.encode(rawValue)
    }
}

public enum RoomStateSource: String, Codable, Equatable, Sendable {
    case representative
    case aggregate
}

public struct RoomState: Codable, Equatable, Sendable {
    public let on: Bool
    public let brightness: Int
    public let colorTemperaturePct: Double
    public let colorMode: RoomColorMode
    public let observedAt: Date
    public let stateSource: RoomStateSource

    public init(
        on: Bool,
        brightness: Int,
        colorTemperaturePct: Double,
        colorMode: RoomColorMode,
        observedAt: Date,
        stateSource: RoomStateSource
    ) throws {
        guard (1 ... 100).contains(brightness) else {
            throw RoomModelError.invalidBrightness(brightness)
        }
        guard (0 ... 100).contains(colorTemperaturePct) else {
            throw RoomModelError.invalidColorTemperature(colorTemperaturePct)
        }
        self.on = on
        self.brightness = brightness
        self.colorTemperaturePct = colorTemperaturePct
        self.colorMode = colorMode
        self.observedAt = observedAt
        self.stateSource = stateSource
    }

    private enum CodingKeys: String, CodingKey {
        case on
        case brightness
        case colorTemperaturePct
        case colorMode
        case observedAt
        case stateSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            on: container.decode(Bool.self, forKey: .on),
            brightness: container.decode(Int.self, forKey: .brightness),
            colorTemperaturePct: container.decode(Double.self, forKey: .colorTemperaturePct),
            colorMode: container.decode(RoomColorMode.self, forKey: .colorMode),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            stateSource: container.decode(RoomStateSource.self, forKey: .stateSource)
        )
    }
}

extension RoomState {
    func applying(_ changes: RoomChanges, observedAt: Date? = nil) throws -> RoomState {
        let colorMode: RoomColorMode
        if let color = changes.color {
            colorMode = switch color {
            case .red: .red
            case .orange: .orange
            }
        } else if changes.colorTemperaturePct != nil {
            colorMode = .temperature
        } else {
            colorMode = self.colorMode
        }

        return try RoomState(
            on: changes.on ?? on,
            brightness: changes.brightness ?? brightness,
            colorTemperaturePct: changes.colorTemperaturePct ?? colorTemperaturePct,
            colorMode: colorMode,
            observedAt: observedAt ?? self.observedAt,
            stateSource: stateSource
        )
    }

    func merging(_ fields: Set<RoomField>, from other: RoomState) throws -> RoomState {
        try RoomState(
            on: fields.contains(.power) ? other.on : on,
            brightness: fields.contains(.brightness) ? other.brightness : brightness,
            colorTemperaturePct: fields.contains(.temperature) ? other.colorTemperaturePct : colorTemperaturePct,
            colorMode: fields.contains(.color) || fields.contains(.temperature) ? other.colorMode : colorMode,
            observedAt: max(observedAt, other.observedAt),
            stateSource: other.stateSource
        )
    }
}

enum RoomField: Hashable, Sendable {
    case power
    case brightness
    case temperature
    case color
}

extension RoomChanges {
    var affectedFields: Set<RoomField> {
        var fields = Set<RoomField>()
        if on != nil { fields.insert(.power) }
        if brightness != nil { fields.insert(.brightness) }
        if colorTemperaturePct != nil { fields.insert(.temperature) }
        if color != nil { fields.insert(.color) }
        return fields
    }
}

public enum RoomModelError: Error, Equatable, Sendable {
    case invalidBrightness(Int)
    case invalidColorTemperature(Double)
    case emptyChanges
}

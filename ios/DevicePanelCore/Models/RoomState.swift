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

public enum RoomModelError: Error, Equatable, Sendable {
    case invalidBrightness(Int)
    case invalidColorTemperature(Double)
    case emptyChanges
}

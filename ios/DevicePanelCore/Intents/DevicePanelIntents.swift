import AppIntents
import WidgetKit

public struct SetPowerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Living Room Power"
    public static let description = IntentDescription("Turns all Living Room lights on or off.")
    public static let openAppWhenRun = false

    @Parameter(title: "Power")
    public var isOn: Bool

    public init() {}

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set Living Room power to \(\.$isOn)")
    }

    public func perform() async throws -> some IntentResult {
        _ = try await IntentEnvironment.commandService().apply(RoomChanges(on: isOn))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

public enum BrightnessPreset: Int, AppEnum, Sendable {
    case ten = 10
    case fifty = 50
    case seventyFive = 75
    case oneHundred = 100

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Brightness")
    public static let caseDisplayRepresentations: [BrightnessPreset: DisplayRepresentation] = [
        .ten: "10 percent",
        .fifty: "50 percent",
        .seventyFive: "75 percent",
        .oneHundred: "100 percent",
    ]
}

public struct SetBrightnessIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Living Room Brightness"
    public static let description = IntentDescription("Sets a brightness preset on all Living Room lights.")
    public static let openAppWhenRun = false

    @Parameter(title: "Brightness")
    public var brightness: BrightnessPreset

    public init() {}

    public init(brightness: BrightnessPreset) {
        self.brightness = brightness
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set Living Room brightness to \(\.$brightness)")
    }

    public func perform() async throws -> some IntentResult {
        _ = try await IntentEnvironment.commandService().apply(
            RoomChanges(brightness: brightness.rawValue)
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 18.0, *)
public struct SetPowerControlIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Set Living Room Power"
    public static let openAppWhenRun = false

    @Parameter(title: "Power")
    public var value: Bool

    public init() {}

    public func perform() async throws -> some IntentResult {
        _ = try await IntentEnvironment.commandService().apply(RoomChanges(on: value))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

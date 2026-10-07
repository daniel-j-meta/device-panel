import Foundation
import XCTest
@testable import DevicePanelCore

final class RoomModelTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testDecodesValidRoomState() throws {
        let data = Data(
            """
            {
              "on": true,
              "brightness": 34,
              "colorTemperaturePct": 50,
              "colorMode": "temperature",
              "observedAt": "2026-10-07T20:00:00Z",
              "stateSource": "representative"
            }
            """.utf8
        )

        let state = try decoder.decode(RoomState.self, from: data)

        XCTAssertTrue(state.on)
        XCTAssertEqual(state.brightness, 34)
        XCTAssertEqual(state.colorTemperaturePct, 50)
        XCTAssertEqual(state.colorMode, .temperature)
        XCTAssertEqual(state.stateSource, .representative)
    }

    func testRejectsOutOfRangeBrightness() {
        XCTAssertThrowsError(
            try RoomState(
                on: true,
                brightness: 0,
                colorTemperaturePct: 50,
                colorMode: .temperature,
                observedAt: Date(),
                stateSource: .representative
            )
        ) { error in
            XCTAssertEqual(error as? RoomModelError, .invalidBrightness(0))
        }
    }

    func testPreservesUnknownColorMode() throws {
        let data = Data("\"future-mode\"".utf8)
        let mode = try decoder.decode(RoomColorMode.self, from: data)
        XCTAssertEqual(mode, .unknown("future-mode"))
    }

    func testRequiresAtLeastOneCommandChange() {
        XCTAssertThrowsError(try RoomChanges()) { error in
            XCTAssertEqual(error as? RoomModelError, .emptyChanges)
        }
    }

    func testFormatsTemperatureForDisplayAndAccessibility() {
        XCTAssertEqual(TemperatureFormatter.signedPercentage(for: 0), "-100%")
        XCTAssertEqual(TemperatureFormatter.signedPercentage(for: 50), "0%")
        XCTAssertEqual(TemperatureFormatter.signedPercentage(for: 100), "+100%")
        XCTAssertEqual(TemperatureFormatter.accessibilityValue(for: 25), "50 percent warm")
        XCTAssertEqual(TemperatureFormatter.accessibilityValue(for: 50), "neutral")
        XCTAssertEqual(TemperatureFormatter.accessibilityValue(for: 75), "50 percent cool")
    }
}

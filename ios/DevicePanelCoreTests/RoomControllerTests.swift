import Foundation
import XCTest
@testable import DevicePanelCore

@MainActor
final class RoomControllerTests: XCTestCase {
    func testStartsSignedOutWithoutStoredSession() async throws {
        let controller = try await makeController(api: FakeAPI())

        await controller.start()

        XCTAssertEqual(controller.authentication, .signedOut)
    }

    func testSignInFetchesRoomState() async throws {
        let api = FakeAPI(roomState: try makeState(on: true, brightness: 50))
        let controller = try await makeController(api: api)

        await controller.signIn(
            serverURL: "https://panel.example",
            password: "correct horse battery staple",
            deviceName: "Test iPhone"
        )

        XCTAssertEqual(controller.authentication, .signedIn(serverLabel: "Home"))
        XCTAssertEqual(controller.roomState?.brightness, 50)
        XCTAssertEqual(controller.connection, .connected)
    }

    func testFailedPowerCommandRollsBackOnlyPower() async throws {
        let initial = try makeState(on: false, brightness: 50)
        let api = FakeAPI(roomState: initial, commandError: .offline)
        let controller = try await makeController(
            api: api,
            storedSession: validSession,
            configuration: "https://panel.example"
        )
        await controller.start()

        await controller.setPower(true)

        XCTAssertEqual(controller.roomState?.on, false)
        XCTAssertEqual(controller.roomState?.brightness, 50)
        XCTAssertEqual(controller.connection, .stale)
        XCTAssertTrue(controller.canRetryLastCommand)
    }

    func testTemperatureCommandSwitchesBackToTemperatureMode() async throws {
        let initial = try makeState(on: true, brightness: 75, mode: .red)
        let api = FakeAPI(roomState: initial)
        let controller = try await makeController(
            api: api,
            storedSession: validSession,
            configuration: "https://panel.example"
        )
        await controller.start()

        await controller.setColorTemperature(25)

        XCTAssertEqual(controller.roomState?.colorTemperaturePct, 25)
        XCTAssertEqual(controller.roomState?.colorMode, .temperature)
    }

    private var validSession: Session {
        Session(token: "token", expiresAt: Date().addingTimeInterval(3_600), serverLabel: "Home")
    }

    private func makeController(
        api: FakeAPI,
        storedSession: Session? = nil,
        configuration: String? = nil
    ) async throws -> RoomController {
        let suiteName = "RoomControllerTests.\(UUID().uuidString)"
        let preferences = SharedPreferences(suiteName: suiteName)
        if let configuration {
            let value = try ServerConfiguration(urlString: configuration)
            await preferences.saveServerConfiguration(value)
        }
        return RoomController(
            api: api,
            sessionStore: InMemorySessionStore(session: storedSession),
            preferences: preferences,
            reconcileDelays: []
        )
    }

    private func makeState(
        on: Bool,
        brightness: Int,
        mode: RoomColorMode = .temperature
    ) throws -> RoomState {
        try RoomState(
            on: on,
            brightness: brightness,
            colorTemperaturePct: 50,
            colorMode: mode,
            observedAt: Date(),
            stateSource: .representative
        )
    }
}

private actor FakeAPI: DevicePanelAPI {
    private let roomState: RoomState?
    private let commandError: DevicePanelError?

    init(roomState: RoomState? = nil, commandError: DevicePanelError? = nil) {
        self.roomState = roomState
        self.commandError = commandError
    }

    func signIn(baseURL: URL, request: SignInRequest) async throws -> Session {
        Session(token: "token", expiresAt: Date().addingTimeInterval(3_600), serverLabel: "Home")
    }

    func signOut(baseURL: URL, token: String) async throws {}

    func fetchRoom(baseURL: URL, token: String) async throws -> RoomState {
        guard let roomState else { throw DevicePanelError.invalidResponse }
        return roomState
    }

    func sendCommand(
        baseURL: URL,
        token: String,
        command: RoomCommand
    ) async throws -> CommandResponse {
        if let commandError { throw commandError }
        return CommandResponse(accepted: true, state: nil)
    }

    func reconcile(
        baseURL: URL,
        token: String,
        request: ReconcileRequest
    ) async throws -> ReconcileResponse {
        ReconcileResponse(state: nil, synchronized: true, corrected: [], stale: false)
    }
}

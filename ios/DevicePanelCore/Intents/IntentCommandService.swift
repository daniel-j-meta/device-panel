import Foundation

public actor IntentCommandService {
    private let api: any DevicePanelAPI
    private let sessionStore: any SessionStoring
    private let preferences: SharedPreferences
    private let allowInsecureLocalhost: Bool

    public init(
        api: any DevicePanelAPI,
        sessionStore: any SessionStoring,
        preferences: SharedPreferences,
        allowInsecureLocalhost: Bool = false
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.preferences = preferences
        self.allowInsecureLocalhost = allowInsecureLocalhost
    }

    public func apply(_ changes: RoomChanges) async throws -> RoomState {
        guard
            let configuration = try await preferences.serverConfiguration(
                allowInsecureLocalhost: allowInsecureLocalhost
            ),
            let session = try await sessionStore.load(),
            !session.isExpired
        else {
            throw DevicePanelError.authenticationRequired
        }

        let currentState: RoomState
        if let cached = await preferences.cachedRoomState() {
            currentState = cached
        } else {
            currentState = try await api.fetchRoom(
                baseURL: configuration.baseURL,
                token: session.token
            )
        }

        let command = RoomCommand(
            clientId: await preferences.clientID(),
            revision: await preferences.nextRevision(),
            changes: changes
        )
        let response = try await api.sendCommand(
            baseURL: configuration.baseURL,
            token: session.token,
            command: command
        )
        guard response.accepted else {
            throw DevicePanelError.server(status: 500, code: "NOT_ACCEPTED", message: nil)
        }

        let state = try response.state ?? currentState.applying(changes, observedAt: Date())
        try await preferences.saveRoomState(state)
        return state
    }

    public func currentState() async throws -> RoomState {
        guard
            let configuration = try await preferences.serverConfiguration(
                allowInsecureLocalhost: allowInsecureLocalhost
            ),
            let session = try await sessionStore.load(),
            !session.isExpired
        else {
            throw DevicePanelError.authenticationRequired
        }
        let state = try await api.fetchRoom(baseURL: configuration.baseURL, token: session.token)
        try await preferences.saveRoomState(state)
        return state
    }
}

enum IntentEnvironment {
    static func commandService() -> IntentCommandService {
        let accessGroup = Bundle.main.object(
            forInfoDictionaryKey: "DevicePanelKeychainAccessGroup"
        ) as? String
        return IntentCommandService(
            api: HTTPDevicePanelAPI(),
            sessionStore: KeychainSessionStore(accessGroup: accessGroup),
            preferences: SharedPreferences()
        )
    }
}

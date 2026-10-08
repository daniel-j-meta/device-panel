import Combine
import Foundation

public enum AuthenticationPhase: Equatable, Sendable {
    case checking
    case signingIn
    case signedOut
    case signedIn(serverLabel: String)
}

public enum ConnectionPhase: Equatable, Sendable {
    case idle
    case loading
    case connected
    case applying
    case stale
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "Not connected"
        case .loading: "Loading"
        case .connected: "Connected"
        case .applying: "Applying"
        case .stale: "Last known state"
        case .failed: "Command failed"
        }
    }
}

@MainActor
public final class RoomController: ObservableObject {
    @Published public private(set) var authentication: AuthenticationPhase = .checking
    @Published public private(set) var connection: ConnectionPhase = .idle
    @Published public private(set) var roomState: RoomState?
    @Published public private(set) var isPowerCommandInFlight = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var serverURLString = ""

    private let api: any DevicePanelAPI
    private let sessionStore: any SessionStoring
    private let preferences: SharedPreferences
    private let allowInsecureLocalhost: Bool
    private let reconcileDelays: [Duration]
    private let resetPersistentStateOnStart: Bool

    private var configuration: ServerConfiguration?
    private var session: Session?
    private var confirmedState: RoomState?
    private var latestRevision: Int64 = 0
    private var fieldRevisions: [RoomField: Int64] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var lastFailedChanges: RoomChanges?

    public init(
        api: any DevicePanelAPI,
        sessionStore: any SessionStoring,
        preferences: SharedPreferences,
        allowInsecureLocalhost: Bool = false,
        reconcileDelays: [Duration] = [.seconds(3), .seconds(6), .seconds(10), .seconds(15)],
        resetPersistentStateOnStart: Bool = false
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.preferences = preferences
        self.allowInsecureLocalhost = allowInsecureLocalhost
        self.reconcileDelays = reconcileDelays
        self.resetPersistentStateOnStart = resetPersistentStateOnStart
    }

    public var canRetryLastCommand: Bool {
        lastFailedChanges != nil
    }

    public func start() async {
        if resetPersistentStateOnStart {
            try? await sessionStore.clear()
            await preferences.reset()
        }
        if let cached = await preferences.cachedRoomState() {
            roomState = cached
            confirmedState = cached
            connection = .stale
        }
        latestRevision = await preferences.currentRevision()

        do {
            let savedConfiguration = try await preferences.serverConfiguration(
                allowInsecureLocalhost: allowInsecureLocalhost
            )
            serverURLString = savedConfiguration?.baseURL.absoluteString ?? ""
            guard
                let configuration = savedConfiguration,
                let session = try await sessionStore.load(),
                !session.isExpired
            else {
                authentication = .signedOut
                return
            }
            self.configuration = configuration
            self.session = session
            authentication = .signedIn(serverLabel: session.serverLabel)
            await refresh()
        } catch {
            authentication = .signedOut
            present(error)
        }
    }

    public func signIn(serverURL: String, password: String, deviceName: String) async {
        guard authentication != .signingIn else { return }
        authentication = .signingIn
        lastError = nil

        do {
            let configuration = try ServerConfiguration(
                urlString: serverURL,
                allowInsecureLocalhost: allowInsecureLocalhost
            )
            let clientID = await preferences.clientID()
            let session = try await api.signIn(
                baseURL: configuration.baseURL,
                request: SignInRequest(password: password, clientId: clientID, deviceName: deviceName)
            )
            guard !session.isExpired else {
                throw DevicePanelError.authenticationRequired
            }
            try await sessionStore.save(session)
            await preferences.saveServerConfiguration(configuration)
            serverURLString = configuration.baseURL.absoluteString
            self.configuration = configuration
            self.session = session
            authentication = .signedIn(serverLabel: session.serverLabel)
            await refresh()
        } catch {
            authentication = .signedOut
            present(error)
        }
    }

    public func signOut() async {
        reconcileTask?.cancel()
        if let configuration, let session {
            try? await api.signOut(baseURL: configuration.baseURL, token: session.token)
        }
        try? await sessionStore.clear()
        await preferences.clearCachedRoomState()
        configuration = nil
        session = nil
        roomState = nil
        confirmedState = nil
        fieldRevisions.removeAll()
        lastFailedChanges = nil
        lastError = nil
        connection = .idle
        authentication = .signedOut
    }

    public func refresh() async {
        guard let configuration, let session else { return }
        let refreshRevision = latestRevision
        connection = roomState == nil ? .loading : .applying
        lastError = nil

        do {
            let state = try await api.fetchRoom(baseURL: configuration.baseURL, token: session.token)
            guard refreshRevision == latestRevision, fieldRevisions.isEmpty else { return }
            roomState = state
            confirmedState = state
            try await preferences.saveRoomState(state)
            connection = .connected
        } catch {
            await handle(error)
        }
    }

    public func setPower(_ isOn: Bool) async {
        guard !isPowerCommandInFlight else { return }
        isPowerCommandInFlight = true
        defer { isPowerCommandInFlight = false }
        do {
            try await apply(RoomChanges(on: isOn))
        } catch {
            await handle(error)
        }
    }

    public func setBrightness(_ brightness: Int) async {
        do {
            try await apply(RoomChanges(brightness: brightness))
        } catch {
            await handle(error)
        }
    }

    public func setColor(_ color: RoomColor) async {
        do {
            try await apply(RoomChanges(color: color))
        } catch {
            await handle(error)
        }
    }

    public func setColorTemperature(_ percentage: Double) async {
        do {
            try await apply(RoomChanges(colorTemperaturePct: percentage))
        } catch {
            await handle(error)
        }
    }

    public func retryLastCommand() async {
        guard let changes = lastFailedChanges else { return }
        do {
            try await apply(changes)
        } catch {
            await handle(error)
        }
    }

    public func clearError() {
        lastError = nil
        if case .failed(_) = connection {
            connection = roomState == nil ? .idle : .stale
        }
    }

    private func apply(_ changes: RoomChanges) async throws {
        guard let configuration, let session else {
            throw DevicePanelError.authenticationRequired
        }
        guard let currentState = roomState else {
            throw DevicePanelError.invalidResponse
        }

        let revision = await preferences.nextRevision()
        latestRevision = revision
        for field in changes.affectedFields {
            fieldRevisions[field] = revision
        }

        roomState = try currentState.applying(changes)
        connection = .applying
        lastError = nil
        lastFailedChanges = nil

        do {
            let command = RoomCommand(
                clientId: await preferences.clientID(),
                revision: revision,
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

            let baseConfirmed = confirmedState ?? currentState
            let commandConfirmed = try response.state ?? baseConfirmed.applying(changes, observedAt: Date())
            confirmedState = try baseConfirmed.merging(changes.affectedFields, from: commandConfirmed)

            for field in changes.affectedFields where fieldRevisions[field] == revision {
                fieldRevisions.removeValue(forKey: field)
            }
            if fieldRevisions.isEmpty {
                connection = .connected
            }
            if let state = roomState {
                try await preferences.saveRoomState(state)
            }
            if revision == latestRevision {
                startReconciliation(revision: revision)
            }
        } catch {
            let didRollback = try rollback(changes: changes, revision: revision)
            guard didRollback else { return }
            lastFailedChanges = changes
            throw error
        }
    }

    private func rollback(changes: RoomChanges, revision: Int64) throws -> Bool {
        guard let confirmedState, let currentState = roomState else { return false }
        let fieldsToRollback = Set(changes.affectedFields.filter { fieldRevisions[$0] == revision })
        guard !fieldsToRollback.isEmpty else { return false }
        roomState = try currentState.merging(fieldsToRollback, from: confirmedState)
        for field in fieldsToRollback {
            fieldRevisions.removeValue(forKey: field)
        }
        return true
    }

    private func startReconciliation(revision: Int64) {
        reconcileTask?.cancel()
        guard !reconcileDelays.isEmpty else { return }

        reconcileTask = Task { [weak self] in
            guard let self else { return }
            for delay in reconcileDelays {
                do {
                    try await Task.sleep(for: delay)
                    try Task.checkCancellation()
                    guard
                        revision == latestRevision,
                        let state = roomState,
                        let configuration,
                        let session
                    else { return }

                    let request = ReconcileRequest(
                        clientId: await preferences.clientID(),
                        revision: revision,
                        on: state.on,
                        brightness: state.on ? state.brightness : nil,
                        colorTemperaturePct: state.on && state.colorMode == .temperature
                            ? state.colorTemperaturePct
                            : nil
                    )
                    let response = try await api.reconcile(
                        baseURL: configuration.baseURL,
                        token: session.token,
                        request: request
                    )
                    if response.stale || revision != latestRevision {
                        return
                    }
                    if response.synchronized {
                        connection = .connected
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if error as? DevicePanelError == .authenticationRequired {
                        await handle(error)
                        return
                    }
                    connection = .stale
                    lastError = (error as? LocalizedError)?.errorDescription
                }
            }
            if revision == latestRevision {
                connection = .stale
            }
        }
    }

    private func handle(_ error: Error) async {
        if error as? DevicePanelError == .authenticationRequired {
            reconcileTask?.cancel()
            try? await sessionStore.clear()
            session = nil
            authentication = .signedOut
        }
        present(error)
    }

    private func present(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "Device Panel could not complete the request."
        lastError = message
        connection = error as? DevicePanelError == .offline ? .stale : .failed(message)
    }
}

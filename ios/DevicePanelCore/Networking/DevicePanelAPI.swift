import Foundation

public protocol DevicePanelAPI: Sendable {
    func signIn(baseURL: URL, request: SignInRequest) async throws -> Session
    func signOut(baseURL: URL, token: String) async throws
    func fetchRoom(baseURL: URL, token: String) async throws -> RoomState
    func sendCommand(baseURL: URL, token: String, command: RoomCommand) async throws -> CommandResponse
    func reconcile(baseURL: URL, token: String, request: ReconcileRequest) async throws -> ReconcileResponse
}

public actor HTTPDevicePanelAPI: DevicePanelAPI {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let allowedHosts: Set<String>?

    public init(session: URLSession? = nil, allowedHosts: Set<String>? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = false
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration)
        }
        self.allowedHosts = allowedHosts.map { Set($0.map { $0.lowercased() }) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date"
            )
        }
        self.decoder = decoder
    }

    public func signIn(baseURL: URL, request: SignInRequest) async throws -> Session {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/sessions",
            method: "POST",
            token: nil,
            body: try encoder.encode(request),
            unauthorizedError: .invalidCredentials
        )
    }

    public func signOut(baseURL: URL, token: String) async throws {
        try await sendWithoutResponse(
            baseURL: baseURL,
            path: "/api/v1/session",
            method: "DELETE",
            token: token,
            body: nil
        )
    }

    public func fetchRoom(baseURL: URL, token: String) async throws -> RoomState {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/rooms/living-room",
            method: "GET",
            token: token,
            body: nil
        )
    }

    public func sendCommand(
        baseURL: URL,
        token: String,
        command: RoomCommand
    ) async throws -> CommandResponse {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/rooms/living-room/commands",
            method: "POST",
            token: token,
            body: try encoder.encode(command),
            commandID: command.commandId
        )
    }

    public func reconcile(
        baseURL: URL,
        token: String,
        request: ReconcileRequest
    ) async throws -> ReconcileResponse {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/rooms/living-room/reconcile",
            method: "POST",
            token: token,
            body: try encoder.encode(request)
        )
    }

    private func send<Response: Decodable>(
        baseURL: URL,
        path: String,
        method: String,
        token: String?,
        body: Data?,
        commandID: UUID? = nil,
        unauthorizedError: DevicePanelError = .authenticationRequired
    ) async throws -> Response {
        let (data, response) = try await perform(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            body: body,
            commandID: commandID
        )
        try validate(response: response, data: data, unauthorizedError: unauthorizedError)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw DevicePanelError.invalidResponse
        }
    }

    private func sendWithoutResponse(
        baseURL: URL,
        path: String,
        method: String,
        token: String?,
        body: Data?
    ) async throws {
        let (data, response) = try await perform(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            body: body,
            commandID: nil
        )
        try validate(response: response, data: data, unauthorizedError: .authenticationRequired)
    }

    private func perform(
        baseURL: URL,
        path: String,
        method: String,
        token: String?,
        body: Data?,
        commandID: UUID?
    ) async throws -> (Data, HTTPURLResponse) {
        if let allowedHosts {
            guard let host = baseURL.host?.lowercased(), allowedHosts.contains(host) else {
                throw DevicePanelError.invalidServerURL
            }
        }
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + path) else {
            throw DevicePanelError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let commandID {
            request.setValue(commandID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DevicePanelError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as DevicePanelError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw DevicePanelError.offline
            case .timedOut:
                throw DevicePanelError.timedOut
            default:
                throw DevicePanelError.server(status: 0, code: "TRANSPORT", message: nil)
            }
        } catch {
            throw DevicePanelError.server(status: 0, code: "TRANSPORT", message: nil)
        }
    }

    private func validate(
        response: HTTPURLResponse,
        data: Data,
        unauthorizedError: DevicePanelError
    ) throws {
        guard (200 ... 299).contains(response.statusCode) else {
            switch response.statusCode {
            case 401:
                throw unauthorizedError
            case 403:
                throw DevicePanelError.permissionDenied
            case 429:
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw DevicePanelError.rateLimited(retryAfter: retryAfter)
            default:
                let payload = try? decoder.decode(APIErrorPayload.self, from: data)
                throw DevicePanelError.server(
                    status: response.statusCode,
                    code: payload?.code,
                    message: payload?.message
                )
            }
        }
    }
}

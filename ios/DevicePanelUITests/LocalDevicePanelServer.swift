import Foundation
import Network
import XCTest

final class LocalDevicePanelServer: @unchecked Sendable {
    struct RoomSnapshot: Equatable {
        var on = false
        var brightness = 50
        var colorTemperaturePct = 50.0
        var colorMode = "temperature"
    }

    private let queue = DispatchQueue(label: "DevicePanelUITests.LocalServer")
    private let lock = NSLock()
    private var listener: NWListener?
    private var listeningPort: UInt16?
    private var room = RoomSnapshot()
    private var failNextCommand = false
    private var expireNextRequest = false
    private var paths: [String] = []
    private let token = "local-ui-test-session-token"

    var baseURL: String {
        lock.lock()
        defer { lock.unlock() }
        return "http://localhost:\(listeningPort ?? 0)"
    }

    var snapshot: RoomSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return room
    }

    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let startup = StartupState()

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let self else { return }
                self.lock.lock()
                self.listeningPort = listener.port?.rawValue
                self.lock.unlock()
                startup.ready.signal()
            case let .failed(error):
                startup.set(error: error)
                startup.ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)

        guard startup.ready.wait(timeout: .now() + 5) == .success else {
            throw ServerError.startTimedOut
        }
        if let startupError = startup.error {
            throw startupError
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func failNextCommandRequest() {
        lock.lock()
        failNextCommand = true
        lock.unlock()
    }

    func expireNextAuthenticatedRequest() {
        lock.lock()
        expireNextRequest = true
        lock.unlock()
    }

    func setRoom(_ update: (inout RoomSnapshot) -> Void) {
        lock.lock()
        update(&room)
        lock.unlock()
    }

    func waitForRoom(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping (RoomSnapshot) -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(snapshot) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for loopback server state: \(snapshot)", file: file, line: line)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let request = HTTPRequest(data: buffer) {
                self.respond(to: request, on: connection)
            } else if error == nil, !complete {
                self.receive(on: connection, accumulated: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let response = route(request)
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        lock.lock()
        paths.append(request.path)
        lock.unlock()

        if request.method == "POST", request.path == "/api/v1/sessions" {
            guard
                let object = request.json as? [String: Any],
                object["password"] as? String == "test-pass"
            else {
                return .json(status: 401, ["code": "INVALID_CREDENTIALS", "message": "Incorrect password"])
            }
            return .json([
                "token": token,
                "expiresAt": "2099-01-01T00:00:00.000Z",
                "serverLabel": "Simulator Home",
            ])
        }

        guard request.headers["authorization"] == "Bearer \(token)" else {
            return .json(status: 401, ["code": "AUTH_EXPIRED", "message": "Sign in again"])
        }

        lock.lock()
        let shouldExpire = expireNextRequest
        expireNextRequest = false
        lock.unlock()
        if shouldExpire {
            return .json(status: 401, ["code": "AUTH_EXPIRED", "message": "Sign in again"])
        }

        switch (request.method, request.path) {
        case ("GET", "/api/v1/rooms/living-room"):
            return roomResponse()
        case ("POST", "/api/v1/rooms/living-room/commands"):
            lock.lock()
            let shouldFail = failNextCommand
            failNextCommand = false
            lock.unlock()
            if shouldFail {
                return .json(status: 502, ["code": "UPSTREAM_ERROR", "message": "Simulated command failure"])
            }
            applyCommand(request.json)
            return .json(["accepted": true, "state": NSNull()])
        case ("POST", "/api/v1/rooms/living-room/reconcile"):
            return .json([
                "state": roomJSON(),
                "synchronized": true,
                "corrected": [],
                "stale": false,
            ])
        case ("DELETE", "/api/v1/session"):
            return HTTPResponse(status: 204, body: Data())
        default:
            return .json(status: 404, ["code": "NOT_FOUND", "message": "Not found"])
        }
    }

    private func applyCommand(_ json: Any?) {
        guard
            let object = json as? [String: Any],
            let changes = object["changes"] as? [String: Any]
        else { return }

        lock.lock()
        if let on = changes["on"] as? Bool { room.on = on }
        if let brightness = changes["brightness"] as? Int { room.brightness = brightness }
        if let temperature = changes["colorTemperaturePct"] as? Double {
            room.colorTemperaturePct = temperature
            room.colorMode = "temperature"
        }
        if let color = changes["color"] as? String { room.colorMode = color }
        lock.unlock()
    }

    private func roomResponse() -> HTTPResponse {
        .json(roomJSON())
    }

    private func roomJSON() -> [String: Any] {
        let value = snapshot
        return [
            "on": value.on,
            "brightness": value.brightness,
            "colorTemperaturePct": value.colorTemperaturePct,
            "colorMode": value.colorMode,
            "observedAt": "2026-10-08T12:00:00.123Z",
            "stateSource": "representative",
        ]
    }

    private enum ServerError: Error {
        case startTimedOut
    }

    private final class StartupState: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var storedError: NWError?

        var error: NWError? {
            lock.lock()
            defer { lock.unlock() }
            return storedError
        }

        func set(error: NWError) {
            lock.lock()
            storedError = error
            lock.unlock()
        }
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + contentLength else { return nil }

        method = requestLine[0]
        path = requestLine[1].components(separatedBy: "?").first ?? requestLine[1]
        self.headers = headers
        body = data.subdata(in: bodyStart ..< bodyStart + contentLength)
    }

    var json: Any? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }
}

private struct HTTPResponse {
    let status: Int
    let body: Data
    var headers: [String: String] = ["Content-Type": "application/json"]

    var data: Data {
        let reason = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 502: "Bad Gateway"
        default: "Error"
        }
        var values = headers
        values["Content-Length"] = String(body.count)
        values["Connection"] = "close"
        let headerLines = values.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        var result = Data("HTTP/1.1 \(status) \(reason)\r\n\(headerLines)\r\n\r\n".utf8)
        result.append(body)
        return result
    }

    static func json(status: Int = 200, _ value: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        return HTTPResponse(status: status, body: data)
    }
}

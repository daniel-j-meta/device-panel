import Foundation
import XCTest
@testable import DevicePanelCore

final class HTTPDevicePanelAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.handler = nil
    }

    func testSignInDoesNotUseCookiesAndDecodesSession() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://panel.example/api/v1/sessions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Self.sessionJSON)
        }

        let client = HTTPDevicePanelAPI(session: makeSession())
        let session = try await client.signIn(
            baseURL: URL(string: "https://panel.example")!,
            request: SignInRequest(password: "not-logged", clientId: UUID(), deviceName: "Test iPhone")
        )

        XCTAssertEqual(session.token, "test-session-token")
        XCTAssertEqual(session.serverLabel, "Home")
    }

    func testCommandUsesBearerTokenAndIdempotencyKey() async throws {
        let commandID = UUID()
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), commandID.uuidString)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{\"accepted\":true,\"state\":null}".utf8))
        }

        let client = HTTPDevicePanelAPI(session: makeSession())
        let command = RoomCommand(
            commandId: commandID,
            clientId: UUID(),
            revision: 1,
            changes: try RoomChanges(on: true)
        )
        let response = try await client.sendCommand(
            baseURL: URL(string: "https://panel.example")!,
            token: "secret-token",
            command: command
        )

        XCTAssertTrue(response.accepted)
    }

    func testMapsUnauthorizedResponse() async {
        URLProtocolStub.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        let client = HTTPDevicePanelAPI(session: makeSession())
        do {
            _ = try await client.fetchRoom(
                baseURL: URL(string: "https://panel.example")!,
                token: "expired"
            )
            XCTFail("Expected authenticationRequired")
        } catch {
            XCTAssertEqual(error as? DevicePanelError, .authenticationRequired)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static let sessionJSON = Data(
        """
        {
          "token": "test-session-token",
          "expiresAt": "2026-11-07T20:00:00.123Z",
          "serverLabel": "Home"
        }
        """.utf8
    )
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("URLProtocolStub.handler was not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

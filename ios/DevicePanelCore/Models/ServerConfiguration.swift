import Foundation

public struct ServerConfiguration: Equatable, Sendable {
    public let baseURL: URL

    public init(urlString: String, allowInsecureLocalhost: Bool = false) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            let host = components.host,
            !host.isEmpty
        else {
            throw DevicePanelError.invalidServerURL
        }

        let scheme = components.scheme?.lowercased()
        let isSecure = scheme == "https"
        let isLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard isSecure || (allowInsecureLocalhost && isLocalhost && scheme == "http") else {
            throw DevicePanelError.invalidServerURL
        }

        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw DevicePanelError.invalidServerURL
        }
        baseURL = url
    }
}

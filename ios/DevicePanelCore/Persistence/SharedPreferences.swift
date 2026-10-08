import Foundation

public actor SharedPreferences {
    public static let appGroup = "group.com.danieljomaa.devicepanel"

    private enum Key {
        static let serverURL = "serverURL"
        static let clientID = "clientID"
        static let revision = "revision"
        static let roomState = "roomState"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(suiteName: String? = SharedPreferences.appGroup) {
        if let suiteName, let sharedDefaults = UserDefaults(suiteName: suiteName) {
            defaults = sharedDefaults
        } else {
            defaults = .standard
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func serverConfiguration(allowInsecureLocalhost: Bool = false) throws -> ServerConfiguration? {
        guard let value = defaults.string(forKey: Key.serverURL) else {
            return nil
        }
        return try ServerConfiguration(urlString: value, allowInsecureLocalhost: allowInsecureLocalhost)
    }

    public func saveServerConfiguration(_ configuration: ServerConfiguration) {
        defaults.set(configuration.baseURL.absoluteString, forKey: Key.serverURL)
    }

    public func clientID() -> UUID {
        if let rawValue = defaults.string(forKey: Key.clientID), let value = UUID(uuidString: rawValue) {
            return value
        }
        let value = UUID()
        defaults.set(value.uuidString, forKey: Key.clientID)
        return value
    }

    public func currentRevision() -> Int64 {
        Int64(defaults.string(forKey: Key.revision) ?? "0") ?? 0
    }

    public func nextRevision(now: Date = Date()) -> Int64 {
        let current = currentRevision()
        let timestamp = Int64(now.timeIntervalSince1970 * 1_000_000)
        let next = max(current + 1, timestamp)
        defaults.set(String(next), forKey: Key.revision)
        return next
    }

    public func cachedRoomState() -> RoomState? {
        guard let data = defaults.data(forKey: Key.roomState) else {
            return nil
        }
        return try? decoder.decode(RoomState.self, from: data)
    }

    public func saveRoomState(_ state: RoomState) throws {
        do {
            defaults.set(try encoder.encode(state), forKey: Key.roomState)
        } catch {
            throw DevicePanelError.storage
        }
    }

    public func clearCachedRoomState() {
        defaults.removeObject(forKey: Key.roomState)
    }

    public func reset() {
        defaults.removeObject(forKey: Key.serverURL)
        defaults.removeObject(forKey: Key.clientID)
        defaults.removeObject(forKey: Key.revision)
        defaults.removeObject(forKey: Key.roomState)
    }
}

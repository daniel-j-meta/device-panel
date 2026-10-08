import DevicePanelCore
import Foundation

@MainActor
enum AppEnvironment {
    static func makeRoomController() -> RoomController {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset") {
            let accessGroup = Bundle.main.object(
                forInfoDictionaryKey: "DevicePanelKeychainAccessGroup"
            ) as? String
            return RoomController(
                api: HTTPDevicePanelAPI(allowedHosts: ["127.0.0.1", "localhost", "::1"]),
                sessionStore: KeychainSessionStore(accessGroup: accessGroup),
                preferences: SharedPreferences(),
                allowInsecureLocalhost: true,
                reconcileDelays: [.milliseconds(50), .milliseconds(100)],
                resetPersistentStateOnStart: true
            )
        }

        let accessGroup = Bundle.main.object(
            forInfoDictionaryKey: "DevicePanelKeychainAccessGroup"
        ) as? String

        #if DEBUG
        let allowInsecureLocalhost = true
        #else
        let allowInsecureLocalhost = false
        #endif

        return RoomController(
            api: HTTPDevicePanelAPI(),
            sessionStore: KeychainSessionStore(accessGroup: accessGroup),
            preferences: SharedPreferences(),
            allowInsecureLocalhost: allowInsecureLocalhost
        )
    }
}

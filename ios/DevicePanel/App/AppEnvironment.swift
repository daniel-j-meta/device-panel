import DevicePanelCore
import Foundation

@MainActor
enum AppEnvironment {
    static func makeRoomController() -> RoomController {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset") {
            let suiteName = "com.danieljomaa.devicepanel.ui-tests"
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            return RoomController(
                api: HTTPDevicePanelAPI(),
                sessionStore: InMemorySessionStore(),
                preferences: SharedPreferences(suiteName: suiteName),
                allowInsecureLocalhost: true,
                reconcileDelays: []
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

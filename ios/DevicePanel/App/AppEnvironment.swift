import DevicePanelCore
import Foundation

@MainActor
enum AppEnvironment {
    static func makeRoomController() -> RoomController {
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

import AppIntents
import DevicePanelCore

struct DevicePanelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPowerIntent(isOn: true),
            phrases: ["Turn on Living Room with \(.applicationName)"],
            shortTitle: "Living Room On",
            systemImageName: "lightbulb.fill"
        )
        AppShortcut(
            intent: SetPowerIntent(isOn: false),
            phrases: ["Turn off Living Room with \(.applicationName)"],
            shortTitle: "Living Room Off",
            systemImageName: "lightbulb.slash"
        )
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: ["Set Living Room brightness with \(.applicationName)"],
            shortTitle: "Set Brightness",
            systemImageName: "sun.max.fill"
        )
    }
}

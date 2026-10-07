# Device Panel for iOS

The native client targets iOS 17 and later. The Xcode project is generated from `project.yml` so project-file changes remain reviewable.

## Generate and open the project

```bash
brew install xcodegen
cd ios
xcodegen generate
open DevicePanel.xcodeproj
```

Select a Development Team for the app and extension before running on a physical device. The app-group and Keychain-group identifiers are declared in the project and must also exist in the Apple Developer portal for distribution.

## What is included

- SwiftUI sign-in and responsive Living Room controls for power, red/orange color, brightness presets, and color temperature.
- Optimistic field-level updates, rollback, stale-state handling, pull-to-refresh, and 3/6/10/15-second reconciliation.
- Keychain session storage shared with a WidgetKit extension; the password and Govee API key are never stored by the app.
- Small and medium interactive widgets, Shortcuts/Siri App Intents, and an iOS 18 Control Center toggle.
- VoiceOver labels, Dynamic Type layouts, reduced-motion support, status text that does not rely on color, and native haptics.

## Test

With the generated project and an iOS 17+ simulator installed:

```bash
cd ios
xcodebuild test \
  -project DevicePanel.xcodeproj \
  -scheme DevicePanel \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

The same command runs in `.github/workflows/ios.yml`. The Worker API tests run with `npm test` from the repository root.

## Connect the app

Deploy the Worker after this change so the `/api/v1` routes and `SessionRegistry` Durable Object exist. In the app, enter the HTTPS Worker origin (for example, `https://device-panel.example.workers.dev`) and the existing `PANEL_PASSWORD` value. Debug builds also allow `http://localhost` for simulator development.

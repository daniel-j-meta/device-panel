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

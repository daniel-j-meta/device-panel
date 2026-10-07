import SwiftUI

@main
struct DevicePanelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.18), Color(red: 0.09, green: 0.13, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ProgressView("Preparing Device Panel…")
                .tint(.white)
                .foregroundStyle(.white)
        }
    }
}

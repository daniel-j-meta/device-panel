import DevicePanelCore
import SwiftUI
import WidgetKit

@main
struct DevicePanelWidgetBundle: WidgetBundle {
    var body: some Widget {
        LivingRoomWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            LivingRoomControlWidget()
        }
    }
}

struct LivingRoomEntry: TimelineEntry {
    let date: Date
    let state: RoomState?
    let isAuthenticated: Bool
}

struct LivingRoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> LivingRoomEntry {
        LivingRoomEntry(date: Date(), state: nil, isAuthenticated: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LivingRoomEntry) -> Void) {
        loadEntry(completion: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LivingRoomEntry>) -> Void) {
        loadEntry { entry in
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func loadEntry(completion: @escaping (LivingRoomEntry) -> Void) {
        Task {
            let preferences = SharedPreferences()
            let state = await preferences.cachedRoomState()
            let accessGroup = Bundle.main.object(
                forInfoDictionaryKey: "DevicePanelKeychainAccessGroup"
            ) as? String
            let session = try? await KeychainSessionStore(accessGroup: accessGroup).load()
            completion(LivingRoomEntry(
                date: Date(),
                state: state,
                isAuthenticated: session?.isExpired == false
            ))
        }
    }
}

struct LivingRoomWidget: Widget {
    let kind = "LivingRoomWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LivingRoomProvider()) { entry in
            LivingRoomWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.18),
                            Color(red: 0.09, green: 0.13, blue: 0.24),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Living Room")
        .description("Control Living Room power and brightness.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct LivingRoomWidgetView: View {
    let entry: LivingRoomEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.isAuthenticated {
            Link(destination: URL(string: "devicepanel://signin")!) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Sign in to Device Panel")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if let state = entry.state {
            if family == .systemMedium {
                mediumView(state)
            } else {
                smallView(state)
            }
        } else {
            Link(destination: URL(string: "devicepanel://living-room")!) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Open Device Panel to load state")
                        .font(.headline)
                }
            }
        }
    }

    private func smallView(_ state: RoomState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Living Room", systemImage: "lightbulb.max.fill")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button(intent: SetPowerIntent(isOn: !state.on)) {
                Label(state.on ? "Turn Off" : "Turn On", systemImage: "power")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.on ? .green : .orange)
            Text("\(state.brightness)% · \(state.observedAt, style: .relative)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mediumView(_ state: RoomState) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Living Room", systemImage: "lightbulb.max.fill")
                    .font(.headline)
                Text(state.on ? "On" : "Off")
                    .font(.title2.bold())
                Button(intent: SetPowerIntent(isOn: !state.on)) {
                    Label(state.on ? "Off" : "On", systemImage: "power")
                }
                .buttonStyle(.borderedProminent)
                .tint(state.on ? .green : .orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Brightness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    brightnessButton(.ten, current: state.brightness)
                    brightnessButton(.fifty, current: state.brightness)
                    brightnessButton(.seventyFive, current: state.brightness)
                    brightnessButton(.oneHundred, current: state.brightness)
                }
            }
        }
    }

    private func brightnessButton(_ preset: BrightnessPreset, current: Int) -> some View {
        Button(intent: SetBrightnessIntent(brightness: preset)) {
            Text("\(preset.rawValue)")
                .font(.caption.bold().monospacedDigit())
                .frame(minWidth: 28, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(current == preset.rawValue ? .orange : .secondary)
        .accessibilityLabel("\(preset.rawValue) percent brightness")
    }
}

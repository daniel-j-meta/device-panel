import DevicePanelCore
import SwiftUI

struct RoomControlView: View {
    @ObservedObject var controller: RoomController
    @State private var showingSettings = false
    @State private var temperatureDraft = 50.0
    @State private var isEditingTemperature = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        statusSection

                        if let state = controller.roomState {
                            PowerControl(
                                isOn: state.on,
                                isBusy: controller.isPowerCommandInFlight
                            ) {
                                Task { await controller.setPower(!state.on) }
                            }

                            ColorSection(selectedMode: state.colorMode) { color in
                                Task { await controller.setColor(color) }
                            }

                            BrightnessSection(
                                brightness: state.brightness,
                                wideLayout: horizontalSizeClass == .regular
                            ) { value in
                                Task { await controller.setBrightness(value) }
                            }

                            TemperatureSection(
                                value: $temperatureDraft,
                                isEditing: $isEditingTemperature
                            ) { value in
                                Task { await controller.setColorTemperature(value) }
                            }
                        } else if controller.connection == .loading {
                            ProgressView("Loading Living Room")
                                .tint(.white)
                                .padding(32)
                        }

                        if let error = controller.lastError {
                            ErrorBanner(
                                message: error,
                                canRetryCommand: controller.canRetryLastCommand,
                                retry: {
                                    Task {
                                        if controller.canRetryLastCommand {
                                            await controller.retryLastCommand()
                                        } else {
                                            await controller.refresh()
                                        }
                                    }
                                },
                                dismiss: controller.clearError
                            )
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await controller.refresh()
                }
            }
            .navigationTitle("Living Room")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await controller.refresh() }
                    }
                    .accessibilityIdentifier("refreshButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(controller: controller)
            }
            .onAppear(perform: syncTemperatureDraft)
            .onChange(of: controller.roomState?.colorTemperaturePct) { _, _ in
                guard !isEditingTemperature else { return }
                syncTemperatureDraft()
            }
            .sensoryFeedback(.success, trigger: controller.connection) { oldValue, newValue in
                oldValue == .applying && newValue == .connected
            }
        }
    }

    private var statusSection: some View {
        ConnectionStatusView(
            phase: controller.connection,
            observedAt: controller.roomState?.observedAt
        )
    }

    private func syncTemperatureDraft() {
        if let value = controller.roomState?.colorTemperaturePct {
            temperatureDraft = value
        }
    }
}

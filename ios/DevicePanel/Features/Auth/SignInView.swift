import DevicePanelCore
import SwiftUI
import UIKit

struct SignInView: View {
    @ObservedObject var controller: RoomController
    @State private var serverURL: String
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case server
        case password
    }

    init(controller: RoomController) {
        self.controller = controller
        _serverURL = State(initialValue: controller.serverURLString)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "lightbulb.max.fill")
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)

                        VStack(spacing: 8) {
                            Text("Device Panel")
                                .font(.largeTitle.bold())
                            Text("Control the Living Room from this device.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 16) {
                            TextField("Server URL", text: $serverURL)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focusedField, equals: .server)
                                .onSubmit { focusedField = .password }
                                .accessibilityHint("The HTTPS address of your Device Panel server")
                                .accessibilityIdentifier("serverURLField")

                            SecureField("Panel password", text: $password)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .password)
                                .onSubmit(signIn)
                                .accessibilityIdentifier("passwordField")

                            if let error = controller.lastError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.failure)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Sign-in error: \(error)")
                            }

                            Button(action: signIn) {
                                HStack {
                                    if controller.authentication == .signingIn {
                                        ProgressView()
                                            .tint(AppTheme.backgroundTop)
                                    }
                                    Text(controller.authentication == .signingIn ? "Signing In…" : "Sign In")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent)
                            .foregroundStyle(AppTheme.backgroundTop)
                            .disabled(!canSubmit || controller.authentication == .signingIn)
                            .accessibilityIdentifier("signInButton")
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(20)
                        .appSurface()
                    }
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                focusedField = serverURL.isEmpty ? .server : .password
            }
        }
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func signIn() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            await controller.signIn(
                serverURL: serverURL,
                password: password,
                deviceName: UIDevice.current.name
            )
            password = ""
        }
    }
}

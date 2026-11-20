//
//  EnvironmentLockView.swift
//  环境锁界面：设置 PIN / 校验 PIN / Face ID 解锁 / 关闭 PIN。
//

import SwiftUI

struct EnvironmentLockView: View {
    let environment: ViewingEnvironment
    @StateObject private var lock: EnvironmentLock

    @State private var pinInput = ""
    @State private var firstEntry: String?
    @State private var message: String?
    @State private var biometricFailed = false

    init(environment: ViewingEnvironment) {
        self.environment = environment
        _lock = StateObject(wrappedValue: EnvironmentLock(environmentID: environment.id))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("PIN", value: lock.hasPIN ? "On" : "Off")
                LabeledContent("Biometrics", value: lock.biometricsAvailable ? "Available" : "Unavailable")
                if case .locked = lock.state {
                    LabeledContent("Status", value: "Locked")
                }
                if case .cooldown = lock.state {
                    LabeledContent("Status",
                                   value: String(format: "Try again in %lld min",
                                                 Int(lock.cooldownRemaining() / 60) + 1))
                }
            } header: {
                Text(environment.name)
            }

            Section {
                SecureField("6 digits", text: $pinInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: pinInput) { _, newValue in
                        pinInput = String(newValue.filter(\.isNumber).prefix(6))
                    }

                Button(lock.hasPIN ? "Verify" : (firstEntry == nil ? "Continue" : "Confirm PIN")) {
                    handlePrimary()
                }
                .disabled(pinInput.count != 6)

                if lock.hasPIN, lock.biometricsAvailable {
                    Button {
                        Task {
                            biometricFailed = !(await lock.unlockWithBiometrics())
                            if biometricFailed { message = "Face ID didn't recognise you." }
                        }
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                    }
                }

                if lock.hasPIN {
                    Button("Turn off PIN", role: .destructive) {
                        lock.removePIN()
                        pinInput = ""
                        firstEntry = nil
                        message = nil
                    }
                }
            } footer: {
                if let message {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text(lock.hasPIN
                         ? "Enter the PIN to unlock this environment. 5 wrong attempts trigger a 5-minute cooldown."
                         : "A PIN lets devices without a passcode unlock this environment.")
                }
            }
        }
        .navigationTitle("Environment Lock")
    }

    private func handlePrimary() {
        message = nil
        if lock.hasPIN {
            if lock.verify(pin: pinInput) {
                message = "Unlocked."
            } else {
                message = "Wrong PIN."
            }
            pinInput = ""
            return
        }

        if let first = firstEntry {
            guard first == pinInput else {
                message = "The PINs don't match. Set it again."
                firstEntry = nil
                pinInput = ""
                return
            }
            try? lock.setPIN(pinInput)
            firstEntry = nil
            pinInput = ""
            message = "PIN set."
        } else {
            firstEntry = pinInput
            pinInput = ""
        }
    }
}

/// 进入环境前的全屏锁（PIN + Face ID）
struct LockGateView: View {
    let environment: ViewingEnvironment
    @ObservedObject var lock: EnvironmentLock
    let onUnlock: () -> Void

    @State private var pin = ""
    @State private var message: String?
    @State private var triedBiometrics = false

    var body: some View {
        ZStack {
            DesignTokens.Surface.base.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 42))
                    .foregroundStyle(DesignTokens.Accent.primary)
                Text(environment.name)
                    .font(DesignTokens.Typography.hero)
                Text("Enter this environment's 6-digit PIN")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)

                SecureField("6 digits", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .padding()
                    .background(DesignTokens.Surface.raised,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                    .frame(maxWidth: 260)
                    .onChange(of: pin) { _, newValue in
                        pin = String(newValue.filter(\.isNumber).prefix(6))
                        if pin.count == 6 { attempt() }
                    }

                if lock.biometricsAvailable {
                    Button {
                        Task {
                            if await lock.unlockWithBiometrics(reason: "Unlock \(environment.name)") {
                                onUnlock()
                            } else {
                                message = "Face ID didn't recognise you. Use the PIN."
                            }
                        }
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                    }
                }

                if let message {
                    Text(message)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.red)
                }

                if case .cooldown = lock.state {
                    Text(String(format: "Try again in %lld min", Int(lock.cooldownRemaining() / 60) + 1))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .task {
            guard !triedBiometrics, lock.biometricsAvailable else { return }
            triedBiometrics = true
            if await lock.unlockWithBiometrics(reason: "Unlock \(environment.name)") {
                onUnlock()
            }
        }
    }

    private func attempt() {
        if lock.verify(pin: pin) {
            message = nil
            onUnlock()
        } else {
            message = "Wrong PIN."
            pin = ""
        }
    }
}

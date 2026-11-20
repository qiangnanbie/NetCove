//
//  EnvironmentLock.swift
//  观看环境锁：6 位 PIN（加盐 SHA-256 迭代哈希）+ Face ID/Touch ID + 后台自动锁 + 失败冷却。
//

import Foundation
import Combine
import CryptoKit
import LocalAuthentication
import Security

@MainActor
final class EnvironmentLock: ObservableObject {
    enum LockState: Equatable {
        case unlocked
        case locked
        case cooldown(until: Date)
    }

    @Published private(set) var state: LockState = .unlocked
    @Published private(set) var failedAttempts: Int = 0

    private let defaults: UserDefaults
    private let environmentID: UUID
    private var backgroundedAt: Date?

    private static let maxAttempts = 5
    private static let cooldown: TimeInterval = 5 * 60
    private static let iterations = 12_000

    init(environmentID: UUID, defaults: UserDefaults = .standard) {
        self.environmentID = environmentID
        self.defaults = defaults
        if hasPIN { state = .locked }
    }

    // MARK: - PIN

    var hasPIN: Bool { defaults.string(forKey: key("pin.hash")) != nil }

    func setPIN(_ pin: String) throws {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { throw LockError.invalidFormat }
        let salt = Self.randomSalt()
        defaults.set(salt, forKey: key("pin.salt"))
        defaults.set(Self.hash(pin: pin, salt: salt), forKey: key("pin.hash"))
        defaults.set(0, forKey: key("pin.failures"))
        failedAttempts = 0
        state = .locked
    }

    func removePIN() {
        for suffix in ["pin.salt", "pin.hash", "pin.failures"] {
            defaults.removeObject(forKey: key(suffix))
        }
        state = .unlocked
        failedAttempts = 0
    }

    func verify(pin: String) -> Bool {
        if case .cooldown = state { return false }
        guard let salt = defaults.string(forKey: key("pin.salt")),
              let stored = defaults.string(forKey: key("pin.hash")) else { return false }

        if Self.constantTimeEquals(Self.hash(pin: pin, salt: salt), stored) {
            failedAttempts = 0
            defaults.set(0, forKey: key("pin.failures"))
            state = .unlocked
            return true
        }

        failedAttempts += 1
        defaults.set(failedAttempts, forKey: key("pin.failures"))
        if failedAttempts >= Self.maxAttempts {
            state = .cooldown(until: Date().addingTimeInterval(Self.cooldown))
            failedAttempts = 0
            defaults.set(0, forKey: key("pin.failures"))
        }
        return false
    }

    func cooldownRemaining() -> TimeInterval {
        guard case .cooldown(let until) = state else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    // MARK: - 生物识别

    var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func unlockWithBiometrics(reason: String = "Unlock this viewing environment") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success {
                state = .unlocked
                failedAttempts = 0
            }
            return success
        } catch {
            return false
        }
    }

    // MARK: - 自动锁

    func markBackgrounded() {
        backgroundedAt = Date()
    }

    /// 根据环境的 autoLock 策略决定是否重新上锁
    func markForegrounded(policy: ViewingEnvironment.AutoLockPolicy) {
        guard hasPIN, let backgroundedAt else { return }
        let elapsed = Date().timeIntervalSince(backgroundedAt)
        switch policy {
        case .immediately: state = .locked
        case .minutes5 where elapsed >= 300: state = .locked
        case .minutes30 where elapsed >= 1800: state = .locked
        case .never: break
        default: break
        }
        self.backgroundedAt = nil
    }

    func lock() { if hasPIN { state = .locked } }

    // MARK: - crypto

    private func key(_ suffix: String) -> String {
        "netcove.env.\(environmentID.uuidString).\(suffix)"
    }

    private static func randomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// 迭代 SHA-256 拉伸（无第三方依赖；生产可换 CommonCrypto PBKDF2）
    private static func hash(pin: String, salt: String) -> String {
        var digest = SHA256.hash(data: Data((pin + salt).utf8))
        for _ in 0..<iterations {
            digest = SHA256.hash(data: Data(digest) + Data(salt.utf8))
        }
        return Data(digest).base64EncodedString()
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for index in a.indices { diff |= a[index] ^ b[index] }
        return diff == 0
    }
}

enum LockError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "PIN must be 6 digits."
        }
    }
}

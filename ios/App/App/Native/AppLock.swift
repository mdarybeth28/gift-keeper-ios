import Foundation
import LocalAuthentication
import SwiftUI

/// Optional app lock — the native form of the web app's optional
/// PIN lock screen — Gift Keeper's web app locks with a 4-digit
/// PIN so nobody holding the phone can peek at the gifts; Face ID
/// is the native equivalent of that same promise.
///
/// How it works, plainly:
/// - OFF by default. The preference lives in UserDefaults under
///   `appLockEnabled`. No credential of any kind is stored for this —
///   the device itself does the checking (Face ID / Touch ID, with
///   the device passcode as the standard fallback, via
///   LAContext's `.deviceOwnerAuthentication` policy).
/// - When ON: the app locks at cold launch, and again when it comes
///   back from the background after more than
///   `backgroundGraceSeconds` away (a quick app-switch under that
///   does not re-lock).
/// - If this device cannot do device authentication at all (no
///   passcode set), the lock cannot be turned on — the toggle in the
///   More tab is disabled and says why.
@MainActor
final class AppLockManager: ObservableObject {
    /// How long the app may sit in the background before returning
    /// requires unlocking again.
    static let backgroundGraceSeconds: TimeInterval = 30

    private static let enabledKey = "appLockEnabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false

    private var backgroundedAt: Date?

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        // Cold launch with the lock on starts locked.
        isLocked = enabled
    }

    /// True when the device can authenticate its owner at all
    /// (biometrics or a passcode).
    var canUseDeviceAuth: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// True when biometrics specifically are available (used for
    /// honest words: if Face ID is not set up, the toggle is offered
    /// only when the passcode path exists, and labelled plainly).
    var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    var unlockButtonTitle: String {
        switch biometryType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        case .opticID: return "Unlock"
        default: return "Unlock"
        }
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        if !on { isLocked = false }
    }

    /// Called when the app leaves the foreground: remember when.
    func appDidEnterBackground() {
        backgroundedAt = Date()
    }

    /// Called when the app returns: lock if the lock is on and the
    /// app was away longer than the grace period.
    func appBecameActive() {
        guard isEnabled else { isLocked = false; return }
        if let backgroundedAt {
            if Date().timeIntervalSince(backgroundedAt) > Self.backgroundGraceSeconds {
                isLocked = true
            }
            self.backgroundedAt = nil
        }
    }

    /// Ask the device to authenticate its owner. Success unlocks;
    /// failure or cancel leaves the app locked, with the button
    /// still there to try again.
    func authenticate() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Gift Keeper to see your gift list."
            )
            if success { isLocked = false }
        } catch {
            // Stay locked. The lock screen's button tries again.
        }
    }
}

/// The lock screen: one gift, one sentence, one button. Shown over
/// the tabs whenever AppLockManager says the app is locked.
struct LockView: View {
    @EnvironmentObject private var appLock: AppLockManager

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("🎁").font(.system(size: 56))
                Text("Gift Keeper is locked")
                    .font(.headline)
                Text("Only the owner of this phone can open it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await appLock.authenticate() }
                } label: {
                    if appLock.isAuthenticating {
                        ProgressView()
                    } else {
                        Text(appLock.unlockButtonTitle).fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appLock.isAuthenticating)
                .padding(.top, 6)
            }
            .padding()
        }
        .task {
            await appLock.authenticate()
        }
    }
}

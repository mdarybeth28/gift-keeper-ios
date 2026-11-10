import Foundation

/// The approval gate, natively — grounded in the LIVE Gift Keeper
/// web app (the multi-person build), not in Pet Keeper's gate,
/// because the two gates behave differently and the difference
/// matters:
///
///   Web checkApproved():  sb.rpc("current_email_is_approved")
///                         -> approved ONLY when the RPC answers
///                            true with no error; ANY error or
///                            non-true answer -> false.
///
/// There is NO fail-open in Gift's web gate: if the RPC errors,
/// the web app shows the gate screen ("This email isn't on the
/// approved list yet…") and the person waits. The native gate
/// mirrors that exactly — an RPC failure is NOT an approval here.
///
/// The owner is handled the web app's way too: OWNER_EMAIL is a
/// local constant and isOwner() is a plain email comparison, asked
/// before the RPC. Owners are always in.
///
/// This service NEVER grants access from anything that happened on
/// the device: not a tapped button, not a StoreKit entitlement. It
/// only ever reports what the backend says (or the owner
/// short-circuit the web app itself performs).
enum ApprovalService {
    enum GateResult {
        case approved
        case waiting
        /// RPC missing/errored — Gift's web behaviour: stay at the
        /// gate (NOT open). Flagged so the paywall can say the
        /// check itself failed, in honest words.
        case checkFailed
    }

    static func checkGate(accessToken: String, email: String?) async -> GateResult {
        if StoreConfig.isOwner(email: email) { return .approved }

        var request = URLRequest(url: SupabaseConfig.restURL("rpc/current_email_is_approved"))
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .checkFailed }
            // PostgREST returns a bare JSON boolean for this RPC.
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text == "true" { return .approved }
            if text == "false" { return .waiting }
            return .checkFailed
        } catch {
            return .checkFailed
        }
    }
}

/// Observable holder for the gate result, owned by RootTabView.
/// Rechecked: on sign-in, after a purchase finishes, after a
/// restore, and whenever the paywall's "Check again" is tapped.
/// Between checks the last known result stands — the app never
/// upgrades a `waiting` to `approved` on its own word.
@MainActor
final class ApprovalStore: ObservableObject {
    enum State: Equatable {
        case unknown
        case checking
        case approved
        case waiting
        /// The check itself failed (Gift's web gate stays shut in
        /// this case too — it is not an approval).
        case checkFailed
    }

    @Published private(set) var state: State = .unknown

    var isWaiting: Bool { state == .waiting }
    var mayEnter: Bool { state == .approved }

    func reset() { state = .unknown }

    /// One backend question. Returns the resulting state so callers
    /// (the paywall's post-purchase poll) can loop on it.
    @discardableResult
    func check(session: SessionStore) async -> State {
        guard session.isSignedIn, let token = await session.validAccessToken() else {
            state = .unknown
            return state
        }
        state = .checking
        switch await ApprovalService.checkGate(accessToken: token, email: session.currentEmail) {
        case .approved: state = .approved
        case .waiting: state = .waiting
        case .checkFailed: state = .checkFailed
        }
        return state
    }

    /// Post-purchase / post-restore polling. Apple's server
    /// notification reaches the bridge asynchronously — a purchase
    /// can be fully paid seconds before the approved_emails row
    /// lands. Poll the BACKEND (never the local entitlement) a few
    /// times, then stop and let the paywall say honestly that the
    /// confirmation is still on its way.
    @discardableResult
    func checkUntilApproved(session: SessionStore, attempts: Int = 6, delaySeconds: UInt64 = 5) async -> State {
        for attempt in 0..<attempts {
            let result = await check(session: session)
            if result != .waiting { return result }
            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }
        return state
    }
}

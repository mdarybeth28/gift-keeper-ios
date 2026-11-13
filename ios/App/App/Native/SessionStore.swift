import Foundation

/// Sign-in state for the native layer, talking to the same Supabase
/// Auth the web app uses (email + password, POST /auth/v1/token).
/// Kept deliberately small for Phase 1: sign in, restore on launch
/// from the Keychain refresh token, refresh when the access token
/// expires, sign out. No social login exists in Gift Keeper, so no
/// Sign in with Apple is required (see the build plan §6).
@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    @Published private(set) var state: State = .restoring
    @Published var lastError: String?

    private var accessToken: String?
    private var accessTokenExpiresAt: Date?

    /// The signed-in account, from the token response's `user`
    /// object (Supabase Auth returns it on both grants). The id is
    /// a UUID — it is also the appAccountToken every Apple purchase
    /// is made under (see SubscriptionStore).
    private(set) var currentUserID: String?
    private(set) var currentEmail: String?

    var isSignedIn: Bool { state == .signedIn }

    /// The Supabase user id as a UUID, for StoreKit's
    /// appAccountToken. Identity mapping: Supabase Auth ids are
    /// UUIDs, so no derivation is needed; a non-UUID id (which
    /// should never occur) yields nil and purchases are refused
    /// rather than made under an unlinkable token.
    var appAccountToken: UUID? {
        guard let currentUserID else { return nil }
        return UUID(uuidString: currentUserID)
    }

    struct AuthUser: Decodable {
        let id: String
        let email: String?
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: AuthUser?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    struct ErrorResponse: Decodable {
        let errorDescription: String?
        let msg: String?
        let message: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case errorDescription = "error_description"
            case msg, message, error
        }

        var bestMessage: String? { errorDescription ?? msg ?? message ?? error }
    }

    /// The web app's friendlyErr: the handful of plain-words
    /// translations it makes, verbatim; anything else passes
    /// through as the server said it.
    static func friendlyMessage(_ raw: String) -> String {
        if raw.range(of: "Invalid login credentials", options: .caseInsensitive) != nil {
            return "That email and password don't match. Check them, or use Forgot password."
        }
        if raw.range(of: "Email not confirmed", options: .caseInsensitive) != nil {
            return "Your email isn't confirmed yet — open the email we sent you, tap the link in it, then sign in here."
        }
        if raw.range(of: "already registered", options: .caseInsensitive) != nil {
            return "That email already has an account. Tap \u{201C}Sign in\u{201D} above and use your password."
        }
        if raw.range(of: "Failed to fetch|NetworkError", options: .regularExpression) != nil {
            return "Couldn't reach Gift Keeper just now — check your internet and try again."
        }
        return raw
    }

    /// Called once at app start: if a refresh token is in the
    /// Keychain, trade it for a fresh session; otherwise signed out.
    func restore() async {
        guard let refreshToken = KeychainHelper.loadRefreshToken() else {
            state = .signedOut
            return
        }
        do {
            try await requestTokens(grantFields: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ], queryGrant: "refresh_token")
        } catch {
            KeychainHelper.clearRefreshToken()
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        lastError = nil
        do {
            try await requestTokens(grantFields: [
                "email": email,
                "password": password,
            ], queryGrant: "password")
        } catch {
            lastError = Self.friendlyMessage(error.localizedDescription)
            state = .signedOut
        }
    }

    /// The outcome of a sign-up attempt — the web's createPassword
    /// has exactly these two good shapes and one bad one.
    enum SignUpOutcome {
        /// The reply carried a session: signed in, the approval
        /// gate takes it from there.
        case signedIn
        /// The account was made but there is no session yet: this
        /// project's sign-ups confirm by email (the web's own
        /// "Your password is set!" branch), so the person taps the
        /// link in their inbox, then signs in.
        case needsEmailConfirmation
        case failed
    }

    /// Create a brand-new account — the web app's sign-up door
    /// (POST /auth/v1/signup). Gift's sign-ups come back WITHOUT a
    /// session until the email is confirmed, so that state is a
    /// normal outcome here, not an error: the caller tells the
    /// person to check their email (and spam).
    func signUp(email: String, thePassword: String) async -> SignUpOutcome {
        lastError = nil
        var request = URLRequest(url: SupabaseConfig.signupURL)
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": thePassword,
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.bestMessage
                lastError = Self.friendlyMessage(message ?? "That sign-up didn't go through (HTTP \(status)).")
                state = .signedOut
                return .failed
            }
            if let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data),
               !tokens.accessToken.isEmpty {
                adopt(tokens: tokens)
                // The web's createPassword marks the password set
                // once the gate approves; the mark is best-effort
                // there (wrapped so it can never block), and it is
                // best-effort here too.
                await markPasswordSet()
                return .signedIn
            }
            // No session in the reply: email confirmation is on.
            return .needsEmailConfirmation
        } catch {
            lastError = error.localizedDescription
            state = .signedOut
            return .failed
        }
    }

    /// POST /auth/v1/recover — the web app's forgotPassword
    /// (resetPasswordForEmail), sending the person to the website
    /// to set the new password. Returns true when the email went
    /// out.
    func sendPasswordReset(email: String) async -> Bool {
        var components = URLComponents(url: SupabaseConfig.recoverURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "redirect_to", value: "https://giftkeepersecret.com")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.bestMessage
                lastError = Self.friendlyMessage(message ?? "That reset email didn't go out (HTTP \(status)).")
                return false
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Adopt a token set returned outside the token endpoint
    /// (the sign-up reply) — the same field-for-field landing as
    /// requestTokens.
    private func adopt(tokens: TokenResponse) {
        accessToken = tokens.accessToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        if let user = tokens.user {
            currentUserID = user.id
            currentEmail = user.email
        }
        KeychainHelper.saveRefreshToken(tokens.refreshToken)
        state = .signedIn
    }

    /// sb.rpc("mark_password_set") — best-effort, as on the web.
    private func markPasswordSet() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: SupabaseConfig.restURL("rpc/mark_password_set"))
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = Data("{}".utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    func signOut() async {
        if let accessToken {
            var request = URLRequest(url: SupabaseConfig.logoutURL)
            request.httpMethod = "POST"
            for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
                request.setValue(value, forHTTPHeaderField: key)
            }
            _ = try? await URLSession.shared.data(for: request)
        }
        accessToken = nil
        accessTokenExpiresAt = nil
        currentUserID = nil
        currentEmail = nil
        KeychainHelper.clearRefreshToken()
        state = .signedOut
    }

    /// A currently-valid access token, refreshing first if needed.
    func validAccessToken() async -> String? {
        if let accessToken, let expiresAt = accessTokenExpiresAt,
           expiresAt.timeIntervalSinceNow > 60 {
            return accessToken
        }
        guard let refreshToken = KeychainHelper.loadRefreshToken() else {
            return accessToken
        }
        try? await requestTokens(grantFields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ], queryGrant: "refresh_token")
        return accessToken
    }

    // MARK: - Private

    /// One token endpoint round-trip. Supabase Auth takes the grant
    /// type in the query string and the rest as a JSON body.
    private func requestTokens(grantFields: [String: String], queryGrant: String) async throws {
        var components = URLComponents(url: SupabaseConfig.authTokenURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: queryGrant)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: grantFields)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.bestMessage
            throw NSError(domain: "GiftKeeperAuth", code: status, userInfo: [
                NSLocalizedDescriptionKey: message ?? "Sign-in failed (HTTP \(status)).",
            ])
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokens.accessToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        if let user = tokens.user {
            currentUserID = user.id
            currentEmail = user.email
        }
        KeychainHelper.saveRefreshToken(tokens.refreshToken)
        state = .signedIn
    }
}

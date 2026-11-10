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

        enum CodingKeys: String, CodingKey {
            case errorDescription = "error_description"
            case msg
        }

        var bestMessage: String? { errorDescription ?? msg }
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
            lastError = error.localizedDescription
            state = .signedOut
        }
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

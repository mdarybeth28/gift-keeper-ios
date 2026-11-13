import Foundation

/// Reads and writes the signed-in user's gift list through
/// Supabase's REST door, exactly as the web app does:
///
///   GET  /rest/v1/gift_lists?select=data&user_id=eq.<auth id>
///   POST /rest/v1/gift_lists   (the web's sb.from("gift_lists")
///        .upsert({user_id, data, updated_at}) — PostgREST's
///        merge-duplicates upsert on the user_id key)
///
/// The user id is the signed-in session's OWN id — never a value
/// typed or stored separately — so one account's list can only
/// ever be read into, or written from, that account, the native
/// echo of the web's account-safe rule. Row-level security does
/// the real protecting; a signed-out request can read nothing.
///
/// A missing row answers with an EMPTY list, not an error: the
/// web app treats "no cloud row yet" as a fresh empty list.
enum GiftListService {
    struct Row: Decodable {
        let data: GiftListData?
    }

    static var emptyList: GiftListData {
        GiftListData(budget: nil, reminderDays: nil, people: nil, gifts: nil, eventLimits: nil)
    }

    /// The typed read the views render from.
    static func fetchList(accessToken: String, userID: String) async throws -> GiftListData {
        guard let raw = try await fetchRawList(accessToken: accessToken, userID: userID) else {
            return emptyList
        }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return (try? JSONDecoder().decode(Row.self, from: wrapRow(data)))?.data ?? emptyList
    }

    /// The raw blob as a JSON dictionary — the shape the write
    /// path works in (see GiftStateKit). Nil when the account has
    /// no cloud row yet.
    static func fetchRawList(accessToken: String, userID: String) async throws -> [String: Any]? {
        var components = URLComponents(url: SupabaseConfig.restURL("gift_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "data"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
        ]
        var request = URLRequest(url: components.url!)
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // PostgREST's maybeSingle shape: zero rows is a valid
        // answer, not a 406.
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 406 {
            // maybeSingle with no row: a fresh, empty list.
            return nil
        }
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(SessionStore.ErrorResponse.self, from: data))?.bestMessage
            throw NSError(domain: "GiftKeeperList", code: status, userInfo: [
                NSLocalizedDescriptionKey: message ?? "Could not load your gift list (HTTP \(status)).",
            ])
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blob = object["data"] as? [String: Any] else {
            return nil
        }
        return blob
    }

    /// The web's pushCloud write: one upsert of the whole blob
    /// (PIN already stripped by the caller, exactly as the web's
    /// stripPin precedes its upsert).
    static func upsertList(accessToken: String, userID: String, data: [String: Any]) async throws {
        var request = URLRequest(url: SupabaseConfig.restURL("gift_lists"))
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        let now = ISO8601DateFormatter()
        now.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userID,
            "data": data,
            "updated_at": now.string(from: Date()),
        ])
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(SessionStore.ErrorResponse.self, from: responseData))?.bestMessage
            throw NSError(domain: "GiftKeeperList", code: status, userInfo: [
                NSLocalizedDescriptionKey: message ?? "The list didn't save to the account (HTTP \(status)).",
            ])
        }
    }

    /// fetchList decodes Row{data} — the raw path already unwrapped
    /// the row, so re-wrap for the one decode path.
    private static func wrapRow(_ blobData: Data) -> Data {
        var wrapped: [String: Any] = [:]
        if let blob = try? JSONSerialization.jsonObject(with: blobData) {
            wrapped["data"] = blob
        }
        return (try? JSONSerialization.data(withJSONObject: wrapped)) ?? Data("{}".utf8)
    }
}

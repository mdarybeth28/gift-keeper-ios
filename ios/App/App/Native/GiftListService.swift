import Foundation

/// Reads the signed-in user's gift list through Supabase's REST
/// door, exactly as the web app does:
///
///   GET /rest/v1/gift_lists?select=data&user_id=eq.<auth id>
///
/// (the web: sb.from("gift_lists").select("data")
///   .eq("user_id", user.id).maybeSingle()).
///
/// The user id is the signed-in session's OWN id — never a value
/// typed or stored separately — so one account's list can only
/// ever be read into that account, the native echo of the web's
/// account-safe rule. Row-level security does the real protecting;
/// a signed-out request can read nothing.
///
/// A missing row answers with an EMPTY list, not an error: the
/// web app treats "no cloud row yet" as a fresh empty list.
enum GiftListService {
    struct Row: Decodable {
        let data: GiftListData?
    }

    static func fetchList(accessToken: String, userID: String) async throws -> GiftListData {
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
            return GiftListData(budget: nil, people: nil, gifts: nil, eventLimits: nil)
        }
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(SessionStore.ErrorResponse.self, from: data))?.bestMessage
            throw NSError(domain: "GiftKeeperList", code: status, userInfo: [
                NSLocalizedDescriptionKey: message ?? "Could not load your gift list (HTTP \(status)).",
            ])
        }
        let row = try JSONDecoder().decode(Row.self, from: data)
        return row.data ?? GiftListData(budget: nil, people: nil, gifts: nil, eventLimits: nil)
    }
}

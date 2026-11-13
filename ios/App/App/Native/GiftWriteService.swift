import Foundation

/// One gift read, exactly as the read-gift function answers for a
/// single photo (the web's applyGiftRead reads these same keys):
/// { gift_name, price, purchase_date, tracking_number, carrier,
///   hiding_place, recipient_name, occasion, unsure[], cached }.
/// `price` comes back as a string on the web's reads; a numeric
/// price is accepted too and rendered the web's way.
struct GiftRead: Decodable {
    let giftName: String?
    let price: String?
    let purchaseDate: String?
    let trackingNumber: String?
    let carrier: String?
    let hidingPlace: String?
    let recipientName: String?
    let occasion: String?
    let unsure: [String]?
    let cached: Bool?

    enum CodingKeys: String, CodingKey {
        case giftName = "gift_name"
        case price
        case purchaseDate = "purchase_date"
        case trackingNumber = "tracking_number"
        case carrier
        case hidingPlace = "hiding_place"
        case recipientName = "recipient_name"
        case occasion, unsure, cached
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        giftName = try box.decodeIfPresent(String.self, forKey: .giftName)
        if let text = try? box.decodeIfPresent(String.self, forKey: .price) {
            price = text
        } else if let number = try? box.decodeIfPresent(Double.self, forKey: .price) {
            if let value = number {
                price = value == value.rounded() ? String(Int(value)) : String(value)
            } else {
                price = nil
            }
        } else {
            price = nil
        }
        purchaseDate = try box.decodeIfPresent(String.self, forKey: .purchaseDate)
        trackingNumber = try box.decodeIfPresent(String.self, forKey: .trackingNumber)
        carrier = try box.decodeIfPresent(String.self, forKey: .carrier)
        hidingPlace = try box.decodeIfPresent(String.self, forKey: .hidingPlace)
        recipientName = try box.decodeIfPresent(String.self, forKey: .recipientName)
        occasion = try box.decodeIfPresent(String.self, forKey: .occasion)
        unsure = try box.decodeIfPresent([String].self, forKey: .unsure)
        cached = try box.decodeIfPresent(Bool.self, forKey: .cached)
    }

    /// The web's giftReadIsEmpty(): none of the readable fields
    /// came back.
    var isEmpty: Bool {
        [giftName, price, recipientName, occasion, purchaseDate,
         trackingNumber, carrier, hidingPlace].allSatisfy { ($0 ?? "").isEmpty }
    }

    /// The web's giftReadFieldName().
    static func fieldName(_ key: String) -> String {
        [
            "gift_name": "the gift's name",
            "price": "the price",
            "purchase_date": "the purchase date",
            "tracking_number": "the tracking number",
            "carrier": "the carrier",
            "recipient_name": "who it's for",
            "occasion": "the occasion",
            "hiding_place": "the hiding place",
        ][key] ?? key
    }

    func value(forKey key: String) -> String? {
        switch key {
        case "gift_name": return giftName
        case "price": return price
        case "purchase_date": return purchaseDate
        case "tracking_number": return trackingNumber
        case "carrier": return carrier
        case "recipient_name": return recipientName
        case "occasion": return occasion
        case "hiding_place": return hidingPlace
        default: return nil
        }
    }
}

/// One wish-list read — read-gift in its list mode, exactly as the
/// web's applyWishRead reads it:
/// { items: [{name, note, unsure}], unsure_lines[], skipped[] }.
struct WishRead: Decodable {
    struct Item: Decodable {
        let name: String?
        let note: String?
        let unsure: Bool?
    }

    let items: [Item]?
    let unsureLines: [String]?
    let skipped: [String]?

    enum CodingKeys: String, CodingKey {
        case items
        case unsureLines = "unsure_lines"
        case skipped
    }
}

/// The doors behind the 📸 buttons and the Tell Mary screen: the
/// screenshot/label reader itself, the send-this-photo-to-Mary
/// chain, and the feedback door. All of them are the web app's own
/// backend calls, made the same way the web makes them.
enum GiftWriteService {
    /// An error whose words are the server's own when it sent any.
    static func serviceError(data: Data, status: Int, fallback: String) -> NSError {
        let message = (try? JSONDecoder().decode(SessionStore.ErrorResponse.self, from: data))?.bestMessage
        return NSError(domain: "GiftKeeperWrite", code: status, userInfo: [
            NSLocalizedDescriptionKey: message ?? fallback,
        ])
    }

    /// POST one Edge Function and hand back its JSON. Throws with
    /// the function's own plain-words error when it sends one.
    static func invoke(accessToken: String, function: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: SupabaseConfig.functionURL(function))
        request.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw serviceError(data: data, status: status, fallback: "That didn't go through (HTTP \(status)).")
        }
        return data
    }

    // MARK: - The readers

    /// Read one gift photo (an order screenshot or a shipping
    /// label). The photo goes as base64 JSON — read-gift's exact
    /// contract — and is never stored by the read itself.
    static func readGift(accessToken: String, imageData: Data, mimeType: String) async throws -> GiftRead {
        let data = try await invoke(accessToken: accessToken, function: "read-gift", body: [
            "image_base64": imageData.base64EncodedString(),
            "mime_type": mimeType,
        ])
        return try JSONDecoder().decode(GiftRead.self, from: data)
    }

    /// Read one whole wish-list photo — the same door in its list
    /// mode (the web sends mode: "list").
    static func readWishList(accessToken: String, imageData: Data, mimeType: String) async throws -> WishRead {
        let data = try await invoke(accessToken: accessToken, function: "read-gift", body: [
            "image_base64": imageData.base64EncodedString(),
            "mime_type": mimeType,
            "mode": "list",
        ])
        return try JSONDecoder().decode(WishRead.self, from: data)
    }

    // MARK: - Send a photo to Mary (the feedback photo chain)

    /// The web's sendFeedbackPhoto chain, step for step: upload
    /// the photo to the private help-photos bucket under the
    /// sender's own folder, leave the help_photos row, then ring
    /// send-help-photo to email Mary a link.
    static func sendPhotoToMary(accessToken: String, userID: String, userEmail: String?,
                                note: String, imageData: Data) async throws {
        let path = "\(userID)/\(GiftStateKit.nowMillis()).jpg"
        let email = userEmail?.lowercased()

        var upload = URLRequest(url: SupabaseConfig.storageObjectURL(bucket: "help-photos", path: path))
        upload.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            upload.setValue(value, forHTTPHeaderField: key)
        }
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.httpBody = imageData
        let (upData, upResponse) = try await URLSession.shared.data(for: upload)
        let upStatus = (upResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard upStatus == 200 else {
            throw serviceError(data: upData, status: upStatus, fallback: "That photo didn't send (HTTP \(upStatus)).")
        }

        var insert = URLRequest(url: SupabaseConfig.restURL("help_photos"))
        insert.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            insert.setValue(value, forHTTPHeaderField: key)
        }
        insert.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        var row: [String: Any] = [
            "user_id": userID,
            "note": note,
            "photo_path": path,
        ]
        if let email { row["user_email"] = email } else { row["user_email"] = NSNull() }
        insert.httpBody = try JSONSerialization.data(withJSONObject: row)
        let (inData, inResponse) = try await URLSession.shared.data(for: insert)
        let inStatus = (inResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard inStatus == 201 else {
            throw serviceError(data: inData, status: inStatus, fallback: "That photo didn't send (HTTP \(inStatus)).")
        }

        _ = try await invoke(accessToken: accessToken, function: "send-help-photo", body: [
            "photo_path": path,
            "note": note,
            "user_email": email ?? "",
        ])
    }

    // MARK: - Feedback (the Tell Mary door)

    /// The web's sendFeedback: the message lands in the feedback
    /// table FIRST (sender_email is the optional typed address;
    /// user_email is the account's), then send-feedback emails it.
    /// Throws only when the table insert fails — the web keeps the
    /// message even when the email copy doesn't go out, so the
    /// invoke's failure is reported by return value, not thrown.
    static func sendFeedback(accessToken: String, message: String, senderEmail: String,
                             userEmail: String?) async throws -> Bool {
        var insert = URLRequest(url: SupabaseConfig.restURL("feedback"))
        insert.httpMethod = "POST"
        for (key, value) in SupabaseConfig.baseHeaders(accessToken: accessToken) {
            insert.setValue(value, forHTTPHeaderField: key)
        }
        insert.setValue("return=representation", forHTTPHeaderField: "Prefer")
        var row: [String: Any] = ["message": message]
        row["sender_email"] = senderEmail.isEmpty ? NSNull() : senderEmail
        if let userEmail { row["user_email"] = userEmail.lowercased() } else { row["user_email"] = NSNull() }
        insert.httpBody = try JSONSerialization.data(withJSONObject: row)
        let (data, response) = try await URLSession.shared.data(for: insert)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 201 else {
            throw serviceError(data: data, status: status, fallback: "Your message didn't save (HTTP \(status)).")
        }
        do {
            _ = try await invoke(accessToken: accessToken, function: "send-feedback", body: [
                "message": message,
                "from": senderEmail,
                "fromUser": userEmail ?? "",
                "page": "https://giftkeepersecret.com",
            ])
            return true
        } catch {
            return false
        }
    }
}

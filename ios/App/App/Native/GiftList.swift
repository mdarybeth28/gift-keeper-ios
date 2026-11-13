import Foundation

/// The native mirror of Gift Keeper's list blob — the `data` JSON
/// of the signed-in user's one row in the `gift_lists` table:
///
///   gift_lists { user_id, data (jsonb), updated_at }
///   sb.from("gift_lists").upsert({user_id, data, updated_at})
///   sb.from("gift_lists").select("data").eq("user_id", user.id)
///
/// The field names and shapes below are copied from the LIVE web
/// app's own normalizers (normState / normPerson / normGift /
/// defaultState in the multi-person build), field for field.
/// Nothing is invented. Reminder/notification internals and the
/// PIN (device-local on the web, stripped before upload) are not
/// decoded into this typed mirror; decoding ignores unknown keys.
/// Gift photos ARE decoded (they are part of the gift, and the
/// parity round shows them). The full blob itself lives in
/// GiftListStore as a JSON dictionary — GiftStateKit carries the
/// web's normalizers, its merge-by-ID fold, and its save path,
/// ported whole; this typed shape is the read mirror the views
/// render from.
///
/// NORMALIZATION parity with the web (applied in GiftListService
/// after decode, mirroring normGift/normPerson):
/// - gift status: "idea" -> "thinking", "bought" -> "purchased"
///   (STATUS_ALIAS); a missing status defaults to "thinking".
/// - person category: anything outside Family/Friends/Work/Other
///   reads as "Other".
/// - a gift's price is a JSON number, defaulting to 0.

struct GiftListData: Decodable {
    let budget: Double?
    /// How many days ahead occasion reminders start (the web's
    /// state.reminderDays; the Upcoming view's window).
    let reminderDays: Double?
    let people: [GiftPerson]?
    let gifts: [GiftEntry]?
    /// Per-occasion spending limits, label -> dollars
    /// (state.eventLimits on the web).
    let eventLimits: [String: Double]?
}

struct GiftPerson: Decodable, Identifiable {
    let id: String
    let name: String?
    let relationship: String?
    let category: String?
    let color: String?
    let occasions: [GiftOccasion]?
    let sizes: String?
    let favorites: String?
    let hobbies: String?
    let notes: String?
    let archived: Bool?

    var displayName: String { name ?? "" }

    var displayCategory: String {
        guard let category, GiftListConstants.categories.contains(category) else { return "Other" }
        return category
    }

    var isArchived: Bool { archived == true }
}

struct GiftOccasion: Decodable, Identifiable {
    let id: String
    let kind: String?
    let label: String?
    let month: Int?
    let day: Int?
    let title: String?
    let remind: Bool?
}

struct GiftEntry: Decodable, Identifiable {
    let id: String
    let personId: String?
    let name: String?
    let idea: String?
    let price: Double?
    let boughtOn: String?
    let occasionLabel: String?
    let hidingPlace: String?
    let status: String?
    /// The gift's photo, stored in the blob as a data URL (the
    /// web's normGift `photo`). Null when there is none.
    let photo: String?
    let carrier: String?
    let trackingNumber: String?
    /// The shipping-label photo, also a data URL in the blob
    /// (the web's normGift `shippingPhoto`).
    let shippingPhoto: String?
    let trackingStatus: String?
    let archived: Bool?

    /// The web's STATUS_ALIAS applied (normGift): "idea" was the
    /// old word for "thinking", "bought" for "purchased"; a missing
    /// status is "thinking".
    var normalizedStatus: String {
        switch status {
        case "idea": return "thinking"
        case "bought": return "purchased"
        case let s?: return s
        default: return "thinking"
        }
    }

    var statusLabel: String { GiftListConstants.statusLabels[normalizedStatus] ?? normalizedStatus }
    var displayPrice: Double { price ?? 0 }
    var isArchived: Bool { archived == true }
}

enum GiftListConstants {
    /// The web app's CATEGORIES, in the web's order.
    static let categories = ["Family", "Friends", "Work", "Other"]
    /// The web app's STATUS_LABELS.
    static let statusLabels = [
        "thinking": "Thinking",
        "purchased": "Purchased",
        "wrapped": "Wrapped",
        "given": "Given",
    ]

    /// The web app's STATUS_ALIAS (normGift's alias table).
    static let statusAliases = [
        "idea": "thinking",
        "bought": "purchased",
    ]

    /// Every status, in the web's own order (the gift form's
    /// segment and the person page's Mark buttons).
    static let statuses = ["thinking", "purchased", "wrapped", "given"]

    /// The web app's CARRIERS.
    static let carriers = ["", "USPS", "UPS", "FedEx", "Other", "Yun Express"]

    /// USD formatting exactly as the web app's money(): no cents
    /// for whole dollars, two decimals otherwise.
    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        if value == value.rounded() {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

/// One gift joined to its person, for the cross-person lists
/// (Still to buy). A gift whose personId matches nobody (possible
/// in an old blob) keeps a blank person rather than disappearing.
struct GiftWithPerson: Identifiable {
    let gift: GiftEntry
    let person: GiftPerson?

    var id: String { gift.id }
    var personName: String { person?.displayName ?? "" }
}

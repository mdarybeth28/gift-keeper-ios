import Foundation

/// The web app's list machinery, ported whole — the PARITY audit's
/// instruction and the model file's own warning ("must be ported
/// whole, not piecemeal"). Everything here works on the blob as a
/// plain JSON dictionary, exactly like the web works on its `state`
/// object, so keys the native layer never shows (reminder and
/// notification settings, seenReminders, extra keys inside a
/// person or a gift) survive a native save untouched — the same
/// Object.assign({}, t, {...}) behaviour as the web's normPerson /
/// normGift / normState.
///
/// Ported from the live giftkeepersecret.com source:
///   defaultState, Zs, arr, normPerson, normGift, normState,
///   dedupeName, extractPersonName, lowerName, repairState,
///   fullNormalize, mergeStatesById, stripPin, gfSplitPrices,
///   newId shapes ("p-<ms>", "g-<ms>", "o-<ms>").
///
/// Numbers: the web's JS numbers and JSONSerialization's NSNumber
/// meet here. Values pulled from a dictionary are read through the
/// small helpers below (num/str/bool/arr/dict) so an Int stored by
/// the web and a Double stored here compare the same way JS would
/// have compared them.
enum GiftStateKit {
    typealias Dict = [String: Any]

    // MARK: - Small readers (the web's Zs / arr and friends)

    static func str(_ value: Any?) -> String {
        (value as? String) ?? ""
    }

    static func optStr(_ value: Any?) -> String? {
        value as? String
    }

    static func num(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) ?? 0 }
        return 0
    }

    static func optNum(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool {
        (value as? Bool) ?? false
    }

    static func arr(_ value: Any?) -> [Any] {
        (value as? [Any]) ?? []
    }

    static func dicts(_ value: Any?) -> [Dict] {
        arr(value).compactMap { $0 as? Dict }
    }

    static func dict(_ value: Any?) -> Dict {
        (value as? Dict) ?? [:]
    }

    static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    // MARK: - Constants (the web's own lists)

    static let categories = GiftListConstants.categories
    static let palette = ["#1f6f5c", "#b45309", "#1d4ed8", "#7c3aed", "#b91c1c", "#0f766e"]
    static let carriers = ["", "USPS", "UPS", "FedEx", "Other", "Yun Express"]

    struct Holiday {
        let label: String
        let month: Int
        let day: Int
    }

    /// The web's HOLIDAYS table, in its order.
    static let holidays: [Holiday] = [
        Holiday(label: "New Year's Day", month: 1, day: 1),
        Holiday(label: "Valentine's Day", month: 2, day: 14),
        Holiday(label: "Easter", month: 4, day: 5),
        Holiday(label: "Mother's Day", month: 5, day: 10),
        Holiday(label: "Father's Day", month: 6, day: 21),
        Holiday(label: "Halloween", month: 10, day: 31),
        Holiday(label: "Thanksgiving", month: 11, day: 26),
        Holiday(label: "Christmas Eve", month: 12, day: 24),
        Holiday(label: "Christmas", month: 12, day: 25),
    ]

    // MARK: - Ids and dates

    /// Milliseconds since the epoch — JS Date.now().
    static func nowMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    /// The web's todayISO(): the local calendar day, yyyy-MM-dd.
    static func todayISO() -> String {
        isoString(Date())
    }

    static func isoString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Parse a yyyy-MM-dd day string (the web stores boughtOn and
    /// occasion dates this way); nil for anything else.
    static func parseDay(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    // MARK: - defaultState / normalizers

    static func defaultState() -> Dict {
        [
            "pin": "1234",
            "budget": 0,
            "reminderDays": 30,
            "remindAll": false,
            "remind3": false,
            "notificationsOn": true,
            "notifyBy": "browser",
            "notifyEmail": "",
            "eventLimits": Dict(),
            "seenReminders": [Any](),
            "people": [Any](),
            "gifts": [Any](),
        ]
    }

    static func normPerson(_ raw: Any?) -> Dict {
        let t = dict(raw)
        var out = t
        out["id"] = str(t["id"])
        out["name"] = str(t["name"])
        out["relationship"] = str(t["relationship"])
        let category = str(t["category"])
        out["category"] = categories.contains(category) ? category : "Other"
        let color = str(t["color"])
        out["color"] = color.isEmpty ? "#1f6f5c" : color
        out["occasions"] = arr(t["occasions"]).map { occasion -> Any in
            let o = dict(occasion)
            var base = o
            base["id"] = str(o["id"])
            base["kind"] = isNull(o["kind"]) ? "custom" : (o["kind"] ?? "custom")
            base["label"] = str(o["label"])
            base["month"] = Int(num(o["month"])) != 0 ? Int(num(o["month"])) : 1
            base["day"] = Int(num(o["day"])) != 0 ? Int(num(o["day"])) : 1
            // The web keeps `title` only when it is a non-empty
            // string and `remind` only when it is a boolean; other
            // keys ride along untouched.
            if let title = o["title"] as? String, !title.isEmpty {
                base["title"] = title
            } else {
                base.removeValue(forKey: "title")
            }
            if o["remind"] is Bool {
                base["remind"] = o["remind"]
            } else {
                base.removeValue(forKey: "remind")
            }
            return base
        }
        out["sizes"] = str(t["sizes"])
        out["favorites"] = str(t["favorites"])
        out["hobbies"] = str(t["hobbies"])
        out["notes"] = str(t["notes"])
        out["archived"] = bool(t["archived"])
        return out
    }

    static func normGift(_ raw: Any?) -> Dict {
        let t = dict(raw)
        var out = t
        out["id"] = str(t["id"])
        out["personId"] = str(t["personId"])
        out["name"] = str(t["name"])
        out["idea"] = str(t["idea"])
        out["price"] = num(t["price"])
        out["boughtOn"] = str(t["boughtOn"])
        out["occasionLabel"] = str(t["occasionLabel"])
        out["hidingPlace"] = str(t["hidingPlace"])
        if let alias = GiftListConstants.statusAliases[str(t["status"])] {
            out["status"] = alias
        } else if isNull(t["status"]) {
            out["status"] = "thinking"
        } else {
            out["status"] = t["status"]
        }
        out["photo"] = isNull(t["photo"]) ? NSNull() : (t["photo"] ?? NSNull())
        out["carrier"] = isNull(t["carrier"]) ? "" : (t["carrier"] ?? "")
        out["trackingNumber"] = str(t["trackingNumber"])
        out["shippingPhoto"] = isNull(t["shippingPhoto"]) ? NSNull() : (t["shippingPhoto"] ?? NSNull())
        out["trackingStatus"] = str(t["trackingStatus"])
        out["trackingUpdatedAt"] = str(t["trackingUpdatedAt"])
        out["archived"] = bool(t["archived"])
        return out
    }

    static func normState(_ raw: Any?) -> Dict {
        let t = dict(raw)
        let d = defaultState()
        var out = d
        for (key, value) in t { out[key] = value }
        let pin = str(t["pin"])
        out["pin"] = pin.isEmpty ? str(d["pin"]) : pin
        out["budget"] = num(t["budget"])
        let reminderDays = num(t["reminderDays"])
        out["reminderDays"] = reminderDays != 0 ? reminderDays : num(d["reminderDays"])
        out["remindAll"] = bool(t["remindAll"])
        out["remind3"] = bool(t["remind3"])
        out["notificationsOn"] = (t["notificationsOn"] as? Bool) ?? true
        out["notifyBy"] = str(t["notifyBy"]) == "email" ? "email" : "browser"
        out["notifyEmail"] = str(t["notifyEmail"])
        var limits = dict(d["eventLimits"])
        for (key, value) in dict(t["eventLimits"]) { limits[key] = value }
        out["eventLimits"] = limits
        out["seenReminders"] = arr(t["seenReminders"])
        out["people"] = arr(t["people"]).map { normPerson($0) }
        out["gifts"] = arr(t["gifts"]).map { normGift($0) }
        return out
    }

    // MARK: - Name cleanup and the repair pass

    /// The web's dedupeName: collapse a doubled word —
    /// "Emily Cole Cole" -> "Emily Cole".
    static func dedupeName(_ value: String) -> String {
        var out: [String] = []
        for word in value.trimmingCharacters(in: .whitespaces).split(separator: " ") {
            let w = String(word)
            if let last = out.last, last.lowercased() == w.lowercased() { continue }
            out.append(w)
        }
        return out.joined(separator: " ")
    }

    static func lowerName(_ value: String?) -> String {
        str(value as Any?).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The web's extractPersonName (calendar-title person
    /// extraction), ported with the same rules in the same order.
    static func extractPersonName(_ value: String) -> String {
        if let range = value.range(of: #"(?i)^(.+?)['’]s\b"#, options: .regularExpression) {
            let matched = String(value[range])
            // Group 1 is everything before the possessive suffix.
            let suffixLength = matched.hasSuffix("'s") || matched.hasSuffix("’s") ? 2 : 2
            return String(matched.dropLast(suffixLength)).trimmingCharacters(in: .whitespaces)
        }
        var base = value
        base = base.replacingOccurrences(of: #"(?i)\b(birthday|bday|anniversary|wedding)\b"#, with: "", options: .regularExpression)
        base = base.replacingOccurrences(of: #"(?i)\bo[f]?\b"#, with: " ", options: .regularExpression)
        base = base.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        base = base.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // The web: base.split(/\s*(?:\band\b|&|,|\+)\s*/i)[0]
        let splitter = try? NSRegularExpression(pattern: #"\s*(?:\band\b|&|,|\+)\s*"#, options: [.caseInsensitive])
        var candidate = base
        if let splitter, let match = splitter.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)) {
            let range = Range(match.range, in: base)!
            candidate = String(base[..<range.lowerBound])
        }
        return candidate.trimmingCharacters(in: .whitespaces)
    }

    /// The web's repairState: an occasion carrying a calendar
    /// title files under the person named in that title; names
    /// are de-doubled.
    static func repairState(_ raw: Dict) -> Dict {
        var people = dicts(raw["people"]).map { person -> Dict in
            var p = person
            p["occasions"] = dicts(person["occasions"])
            return p
        }
        for index in people.indices {
            let occasions = dicts(people[index]["occasions"])
            for occasion in occasions {
                guard let title = occasion["title"] as? String, !title.isEmpty else { continue }
                let r = extractPersonName(title)
                if r.isEmpty || lowerName(r) == lowerName(people[index]["name"] as? String) { continue }
                var targetIndex = people.firstIndex { lowerName($0["name"] as? String) == lowerName(r) }
                if targetIndex == nil {
                    var target = Dict()
                    target["id"] = "p-import-\(nowMillis())-\(Int.random(in: 0..<1_000_000_000))"
                    target["name"] = r
                    target["relationship"] = "From calendar"
                    target["category"] = "Other"
                    target["color"] = palette[people.count % palette.count]
                    target["occasions"] = [Any]()
                    target["sizes"] = ""
                    target["favorites"] = ""
                    target["hobbies"] = ""
                    target["notes"] = "From your calendar dates"
                    people.append(target)
                    targetIndex = people.count - 1
                }
                guard let ti = targetIndex else { continue }
                let already = dicts(people[ti]["occasions"]).contains {
                    Int(num($0["month"])) == Int(num(occasion["month"]))
                        && Int(num($0["day"])) == Int(num(occasion["day"]))
                }
                if !already {
                    var occs = dicts(people[ti]["occasions"])
                    occs.append(occasion)
                    people[ti]["occasions"] = occs
                }
                var mine = dicts(people[index]["occasions"])
                mine.removeAll { str($0["id"]) == str(occasion["id"]) }
                people[index]["occasions"] = mine
            }
            people[index]["name"] = dedupeName(str(people[index]["name"]))
        }
        var out = raw
        out["people"] = people
        return out
    }

    static func fullNormalize(_ raw: Any?) -> Dict {
        repairState(normState(raw))
    }

    // MARK: - Merge by id (the web's mergeStatesById, 2026-11-09)

    /// Same fold shape as the web: `base` wins; `other` folds in.
    /// People match by stable id first (name only as a fallback
    /// for records with no id); for an id-matched person the
    /// OTHER copy's name wins, so a rename sticks; occasions
    /// dedupe by id or (month, day, label); gifts fold by id and
    /// re-point to the matched person's id. Used ONLY for this
    /// account's own copies.
    static func mergeStatesById(base: Dict, other: Dict) -> Dict {
        var people = dicts(base["people"]).map { person -> Dict in
            var p = person
            p["occasions"] = dicts(person["occasions"])
            return p
        }
        var gifts = dicts(base["gifts"])

        func matchFor(_ op: Dict) -> Int? {
            let opID = str(op["id"])
            if !opID.isEmpty, let hit = people.firstIndex(where: { str($0["id"]) == opID }) {
                return hit
            }
            return people.firstIndex { lowerName($0["name"] as? String) == lowerName(op["name"] as? String) }
        }

        for op in dicts(other["people"]) {
            guard let foundIndex = matchFor(op) else {
                var copy = op
                copy["occasions"] = dicts(op["occasions"])
                people.append(copy)
                continue
            }
            var found = people[foundIndex]
            if str(found["id"]) == str(op["id"]), !str(op["name"]).isEmpty {
                found["name"] = op["name"]
            }
            var occasions = dicts(found["occasions"])
            for o in dicts(op["occasions"]) {
                let dup = occasions.contains {
                    str($0["id"]) == str(o["id"])
                        || (Int(num($0["month"])) == Int(num(o["month"]))
                            && Int(num($0["day"])) == Int(num(o["day"]))
                            && str($0["label"]) == str(o["label"]))
                }
                if !dup {
                    var copy = o
                    if str(copy["id"]).isEmpty { copy["id"] = "o-\(nowMillis())" }
                    occasions.append(copy)
                }
            }
            found["occasions"] = occasions
            if str(found["sizes"]).isEmpty { found["sizes"] = op["sizes"] }
            if str(found["favorites"]).isEmpty { found["favorites"] = op["favorites"] }
            if str(found["hobbies"]).isEmpty { found["hobbies"] = op["hobbies"] }
            if str(found["notes"]).isEmpty { found["notes"] = op["notes"] }
            if str(found["relationship"]).isEmpty { found["relationship"] = op["relationship"] }
            found["archived"] = bool(found["archived"]) && bool(op["archived"])
            people[foundIndex] = found
        }

        var idByPersonId: [String: String] = [:]
        for p in people { idByPersonId[str(p["id"])] = str(p["id"]) }
        for op in dicts(other["people"]) {
            if let idx = matchFor(op) {
                idByPersonId[str(op["id"])] = str(people[idx]["id"])
            }
        }
        for og in dicts(other["gifts"]) {
            if gifts.contains(where: { str($0["id"]) == str(og["id"]) }) { continue }
            var copy = og
            copy["personId"] = idByPersonId[str(og["personId"])] ?? og["personId"]
            gifts.append(copy)
        }

        var out = base
        out["people"] = people
        out["gifts"] = gifts
        out["budget"] = num(base["budget"]) != 0 ? base["budget"] : other["budget"]
        var limits = dict(other["eventLimits"])
        for (key, value) in dict(base["eventLimits"]) { limits[key] = value }
        out["eventLimits"] = limits
        var seenOut: [Any] = []
        var seenKeys = Set<String>()
        for item in arr(base["seenReminders"]) + arr(other["seenReminders"]) {
            let key = "\(item)"
            if seenKeys.insert(key).inserted { seenOut.append(item) }
        }
        out["seenReminders"] = seenOut
        out["notifyEmail"] = !str(base["notifyEmail"]).isEmpty ? base["notifyEmail"] : other["notifyEmail"]
        return out
    }

    // MARK: - Save helpers

    /// The web's stripPin: the PIN (and the web's lock flag) are
    /// device-local and never ride to the cloud row.
    static func stripPin(_ state: Dict) -> Dict {
        var copy = state
        copy.removeValue(forKey: "pin")
        copy.removeValue(forKey: "lockOn")
        return copy
    }

    /// The web's gfSplitPrices, line for line: the total in cents,
    /// an even floor share for everyone, and the FIRST copy
    /// carries whatever cents are left over — so the copies sum
    /// to the entered price exactly.
    static func splitPrices(total: Double, count n: Int) -> [Double] {
        guard n > 0 else { return [] }
        let cents = Int((total * 100).rounded())
        let share = cents / n
        return (0..<n).map { i in
            let c = i == 0 ? cents - share * (n - 1) : share
            return (Double(c) / 100 * 100).rounded() / 100
        }
    }

    /// The web's giftNameKey: lowercased, punctuation folded to
    /// spaces, runs of spaces collapsed — how a read's names are
    /// matched against the form's own choices.
    static func giftNameKey(_ value: String) -> String {
        let lowered = value.lowercased()
        var spaced = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == " " {
                spaced.append(ch)
            } else {
                spaced.append(" ")
            }
        }
        return spaced.split(separator: " ").joined(separator: " ")
    }
}

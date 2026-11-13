import Foundation

/// The one shared copy of the signed-in account's gift list for
/// the native tabs (People + Still to buy both read from here, so
/// they can never disagree).
///
/// The working copy is the blob itself, as a JSON dictionary —
/// the web app's `state` — and every mutation funnels through
/// `mutate`, the native twin of the web's update(): change the
/// copy, publish it at once, then push the whole blob to the
/// account's gift_lists row (the web's pushCloud upsert, PIN
/// stripped first). The save state tells the truth the way the
/// web's header indicator does: "Saving…" while a push is owed or
/// in flight, "Saved ✓ <time>" when the account copy is home,
/// "Couldn't save" when it isn't — nothing is claimed saved that
/// the account didn't take, and a failed push keeps the local
/// copy (the web keeps its device copy the same way).
///
/// Loading mirrors the web's syncOnSignIn fold: the cloud row is
/// the base; a working copy already in memory (kept after a
/// failed push) folds into it by mergeStatesById — this
/// account's own copies only, matched by stable id.
@MainActor
final class GiftListStore: ObservableObject {
    @Published private(set) var list: GiftListData?
    @Published private(set) var isLoading = false
    @Published var loadError: String?

    /// The blob as a JSON dictionary (GiftStateKit's shape),
    /// fully normalized. The typed `list` above is decoded from
    /// this after every change.
    @Published private(set) var rawState: GiftStateKit.Dict?

    enum SaveState: Equatable {
        case idle
        case saving
        case saved(Date)
        case failed
    }

    @Published private(set) var saveState: SaveState = .idle

    /// The web's save-indicator words.
    var saveStatusText: String? {
        switch saveState {
        case .idle: return nil
        case .saving: return "Saving…"
        case .saved(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Saved ✓ \(formatter.string(from: date))"
        case .failed: return "Couldn't save — check your connection"
        }
    }

    // MARK: - Read accessors (typed mirror)

    /// People who are not archived, in the blob's own order (the
    /// web keeps people in the order they were added).
    var visiblePeople: [GiftPerson] {
        (list?.people ?? []).filter { !$0.isArchived }
    }

    var allPeople: [GiftPerson] { list?.people ?? [] }

    var archivedPeople: [GiftPerson] {
        (list?.people ?? []).filter { $0.isArchived }
    }

    var visibleGifts: [GiftEntry] {
        (list?.gifts ?? []).filter { !$0.isArchived }
    }

    /// People grouped by category, in the web's category order,
    /// empty categories left out — computed here as plain data so
    /// the People view's List body stays a flat, simple shape.
    var peopleByCategory: [(category: String, people: [GiftPerson])] {
        GiftListConstants.categories.compactMap { category in
            let people = visiblePeople.filter { $0.displayCategory == category }
            return people.isEmpty ? nil : (category: category, people: people)
        }
    }

    func person(id: String?) -> GiftPerson? {
        guard let id else { return nil }
        return (list?.people ?? []).first { $0.id == id }
    }

    func gifts(for person: GiftPerson) -> [GiftEntry] {
        visibleGifts.filter { $0.personId == person.id }
    }

    /// Archived gifts whose person is NOT archived (the web's
    /// Archived view rule — an archived person's gifts rest with
    /// the person, not in this list).
    var archivedGifts: [GiftEntry] {
        (list?.gifts ?? []).filter { gift in
            guard gift.isArchived else { return false }
            let owner = person(id: gift.personId)
            return !(owner?.isArchived ?? false)
        }
    }

    /// The web budget view's "spent" rule, verbatim: gifts whose
    /// status is not "thinking" and that are not archived. A
    /// split gift's copies each carry their share price, so the
    /// sum counts the shared gift once in total — the split math
    /// lives in the prices, not in a special case here.
    var spentTotal: Double {
        visibleGifts
            .filter { $0.normalizedStatus != "thinking" }
            .reduce(0) { $0 + $1.displayPrice }
    }

    var yearlyBudget: Double { list?.budget ?? 0 }

    func spent(for person: GiftPerson) -> Double {
        gifts(for: person)
            .filter { $0.normalizedStatus != "thinking" }
            .reduce(0) { $0 + $1.displayPrice }
    }

    /// Spent grouped by occasion label (the budget view's
    /// by-occasion rows), biggest first.
    var spentByOccasion: [(label: String, total: Double)] {
        var totals: [String: Double] = [:]
        for gift in visibleGifts where gift.normalizedStatus != "thinking" {
            totals[gift.occasionLabel ?? "", default: 0] += gift.displayPrice
        }
        return totals.map { (label: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    func spentByPerson() -> [(person: GiftPerson, total: Double)] {
        visiblePeople
            .map { (person: $0, total: spent(for: $0)) }
            .sorted { $0.total > $1.total }
    }

    var eventLimits: [String: Double] { list?.eventLimits ?? [:] }

    /// Occasion labels from every person's days, in first-seen
    /// order (the web's budget-limits editor labels).
    var occasionLabels: [String] {
        var seen: [String] = []
        for person in allPeople {
            for occasion in person.occasions ?? [] {
                let label = occasion.label ?? ""
                if !label.isEmpty && !seen.contains(label) { seen.append(label) }
            }
        }
        return seen
    }

    var reminderDays: Int { Int(list?.reminderDays ?? 30) }

    /// Still to buy — the cross-person errand list:
    /// - "Still to get": status thinking (an idea, not yet bought).
    /// - "Bought — still to wrap": status purchased (bought, not
    ///   yet wrapped or given). A purchased gift with a hiding
    ///   place shows it here — bought-and-hidden is exactly the
    ///   state this app exists for.
    var stillToGet: [GiftWithPerson] {
        visibleGifts
            .filter { $0.normalizedStatus == "thinking" }
            .map { GiftWithPerson(gift: $0, person: person(id: $0.personId)) }
    }

    var boughtToWrap: [GiftWithPerson] {
        visibleGifts
            .filter { $0.normalizedStatus == "purchased" }
            .map { GiftWithPerson(gift: $0, person: person(id: $0.personId)) }
    }

    // MARK: - Upcoming occasions (the web's upcomingList)

    struct UpcomingEntry: Identifiable {
        let person: GiftPerson
        let occasion: GiftOccasion
        let date: Date
        let daysAway: Int

        var id: String { person.id + "-" + occasion.id }
    }

    /// The web's nextOccurrence: this year's date, or next
    /// year's when this year's has passed.
    static func nextOccurrence(month: Int, day: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var components = DateComponents()
        components.year = calendar.component(.year, from: now)
        components.month = month
        components.day = day
        let thisYear = calendar.date(from: components) ?? today
        if thisYear >= today { return thisYear }
        components.year = (components.year ?? 0) + 1
        return calendar.date(from: components) ?? thisYear
    }

    static func daysAway(from date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The web's daysLabel.
    static func daysLabel(_ n: Int) -> String {
        if n == 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n < 14 { return "In \(n) days" }
        if n < 60 { return "In \(Int((Double(n) / 7).rounded())) weeks" }
        return "In \(Int((Double(n) / 30).rounded())) months"
    }

    var upcoming: [UpcomingEntry] {
        visiblePeople.flatMap { person in
            (person.occasions ?? []).map { occasion in
                let date = Self.nextOccurrence(month: occasion.month ?? 1, day: occasion.day ?? 1)
                return UpcomingEntry(person: person, occasion: occasion, date: date, daysAway: Self.daysAway(from: date))
            }
        }
        .sorted { $0.daysAway < $1.daysAway }
    }

    // MARK: - Load (the web's syncOnSignIn fold)

    func load(session: SessionStore) async {
        guard session.isSignedIn,
              let userID = session.currentUserID,
              let token = await session.validAccessToken() else {
            loadError = "Your sign-in expired. Please sign out and sign in again."
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let cloudRaw = try await GiftListService.fetchRawList(accessToken: token, userID: userID)
            let cloud = GiftStateKit.fullNormalize(cloudRaw as Any)
            if let local = rawState {
                // A working copy is already in memory (kept after
                // a failed push): fold it into the cloud base by
                // id, as the web folds its device copy at sign-in.
                publish(GiftStateKit.fullNormalize(
                    GiftStateKit.mergeStatesById(base: cloud, other: local)))
            } else {
                publish(cloud)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clear() {
        list = nil
        rawState = nil
        loadError = nil
        saveState = .idle
    }

    // MARK: - The save path (the web's update() + pushCloud())

    /// Every mutation funnels through here: change the working
    /// copy, publish it at once, push to the account. Immediate,
    /// like the web's saveNow — the forms here are deliberate
    /// saves, not keystroke streams, so there is no debounce.
    func mutate(session: SessionStore, _ transform: (inout GiftStateKit.Dict) -> Void) async {
        guard var working = rawState else {
            // Nothing loaded yet — refuse rather than push an
            // empty state over the real list, and say so.
            saveState = .failed
            return
        }
        transform(&working)
        let normalized = GiftStateKit.fullNormalize(working)
        publish(normalized)
        guard let userID = session.currentUserID,
              let token = await session.validAccessToken() else {
            saveState = .failed
            return
        }
        saveState = .saving
        do {
            try await GiftListService.upsertList(
                accessToken: token, userID: userID,
                data: GiftStateKit.stripPin(normalized))
            saveState = .saved(Date())
        } catch {
            saveState = .failed
        }
    }

    private func publish(_ state: GiftStateKit.Dict) {
        rawState = state
        guard let data = try? JSONSerialization.data(withJSONObject: ["data": state]),
              let row = try? JSONDecoder().decode(GiftListService.Row.self, from: data) else {
            list = nil
            return
        }
        list = row.data
    }
}

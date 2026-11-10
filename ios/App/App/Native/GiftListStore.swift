import Foundation

/// The one shared copy of the signed-in account's gift list for
/// the native tabs (People + Still to buy both read from here, so
/// they can never disagree). Read-only in this build: loads happen
/// on sign-in and on pull-to-refresh, from GiftListService, and
/// nowhere else — the web app's save path is not reimplemented
/// piecemeal (see GiftList.swift's header).
@MainActor
final class GiftListStore: ObservableObject {
    @Published private(set) var list: GiftListData?
    @Published private(set) var isLoading = false
    @Published var loadError: String?

    /// People who are not archived, in the blob's own order (the
    /// web keeps people in the order they were added).
    var visiblePeople: [GiftPerson] {
        (list?.people ?? []).filter { !$0.isArchived }
    }

    var visibleGifts: [GiftEntry] {
        (list?.gifts ?? []).filter { !$0.isArchived }
    }

    func person(id: String?) -> GiftPerson? {
        guard let id else { return nil }
        return (list?.people ?? []).first { $0.id == id }
    }

    func gifts(for person: GiftPerson) -> [GiftEntry] {
        visibleGifts.filter { $0.personId == person.id }
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

    /// Still to buy — the cross-person errand list, in the shape
    /// the task specified for this tab:
    /// - "Still to get": status thinking (an idea, not yet bought).
    /// - "Bought — still to wrap": status purchased (bought, not
    ///   yet wrapped or given). A purchased gift with a hiding
    ///   place shows it here — bought-and-hidden is exactly the
    ///   state this app exists for.
    /// Wrapped and given gifts are done; they live on the person's
    /// own page, not on the errand list.
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
            list = try await GiftListService.fetchList(accessToken: token, userID: userID)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clear() {
        list = nil
        loadError = nil
    }
}

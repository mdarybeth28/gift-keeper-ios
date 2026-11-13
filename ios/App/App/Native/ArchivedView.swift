import SwiftUI

/// The Archived view — the web's renderArchived: archived people
/// (with their gift counts kept) and archived gifts whose person
/// is not archived, each with its Restore button. Restoring is
/// the same save path as everything else.
struct ArchivedView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore

    var body: some View {
        List {
            Section {
                Text("Put aside, not deleted. Restore anything and it is back on your lists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if giftStore.archivedPeople.isEmpty && giftStore.archivedGifts.isEmpty {
                Section {
                    Text("Nothing archived.")
                        .foregroundStyle(.secondary)
                }
            }
            if !giftStore.archivedPeople.isEmpty {
                Section(header: Text("People")) {
                    ForEach(giftStore.archivedPeople) { person in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.displayName).font(.headline)
                                Text("\(person.relationship ?? "") · \(person.displayCategory) · \(giftCount(person)) kept")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore \(firstName(person))") {
                                Task { await setPersonArchived(person, archived: false) }
                            }
                            .font(.subheadline).fontWeight(.semibold)
                        }
                    }
                }
            }
            if !giftStore.archivedGifts.isEmpty {
                Section(header: Text("Gifts")) {
                    ForEach(giftStore.archivedGifts) { gift in
                        HStack(spacing: 10) {
                            GiftPhotoView(dataURL: gift.photo, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gift.name ?? "").font(.headline)
                                Text("\(personName(gift)) · \(gift.occasionLabel ?? "") · \(GiftListConstants.money(gift.displayPrice)) · \(gift.statusLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore gift") {
                                Task { await setGiftArchived(gift, archived: false) }
                            }
                            .font(.subheadline).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func giftCount(_ person: GiftPerson) -> Int {
        (giftStore.list?.gifts ?? []).filter { $0.personId == person.id }.count == 1
            ? "1 gift"
            : "\((giftStore.list?.gifts ?? []).filter { $0.personId == person.id }.count) gifts"
    }

    private func firstName(_ person: GiftPerson) -> String {
        person.displayName.split(separator: " ").first.map(String.init) ?? person.displayName
    }

    private func personName(_ gift: GiftEntry) -> String {
        giftStore.person(id: gift.personId)?.displayName ?? "Unknown person"
    }

    private func setPersonArchived(_ person: GiftPerson, archived: Bool) async {
        let pid = person.id
        await giftStore.mutate(session: session) { state in
            var people = GiftStateKit.dicts(state["people"])
            for index in people.indices where GiftStateKit.str(people[index]["id"]) == pid {
                people[index]["archived"] = archived
            }
            state["people"] = people
        }
    }

    private func setGiftArchived(_ gift: GiftEntry, archived: Bool) async {
        let gid = gift.id
        await giftStore.mutate(session: session) { state in
            var gifts = GiftStateKit.dicts(state["gifts"])
            for index in gifts.indices where GiftStateKit.str(gifts[index]["id"]) == gid {
                gifts[index]["archived"] = archived
            }
            state["gifts"] = gifts
        }
    }
}

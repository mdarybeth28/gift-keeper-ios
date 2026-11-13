import SwiftUI

/// One person's page: their facts, their days (with the occasion
/// editor — the web's pdOccasions rows plus its add/edit form),
/// this year's spending, and every gift for them — with the
/// hiding place shown right on the gift, because "where did I
/// hide it?" is the question this app exists to answer. Every
/// gift carries the web's own row actions: Mark <status>, Edit
/// gift, Archive gift, Delete gift. The person themselves can be
/// edited, archived/restored, or deleted (the web's words for
/// what deletion takes with it).
///
/// The page resolves its person LIVE from the store by id, so an
/// edit made in a sheet is on the page when the sheet closes.
struct PersonDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @Environment(\.dismiss) private var dismiss

    let personID: String

    init(personID: String) {
        self.personID = personID
    }

    /// Compatibility with the original read-only initializer.
    init(person: GiftPerson) {
        self.personID = person.id
    }

    @State private var showEditPerson = false
    @State private var showAddGift = false
    @State private var editingGift: GiftEntry?
    @State private var showWishList = false
    @State private var confirmDeletePerson = false
    @State private var confirmDeleteGift: GiftEntry?

    // The occasion editor (the web's occ* form).
    @State private var occLabel = ""
    @State private var occKind = "custom"
    @State private var occDate = Date()
    @State private var editingOccasionID: String?
    @State private var occError: String?

    private var person: GiftPerson? { giftStore.person(id: personID) }
    private var gifts: [GiftEntry] {
        guard let person else { return [] }
        return giftStore.gifts(for: person)
    }

    var body: some View {
        Group {
            if let person {
                List {
                    factsSection(person)
                    occasionsSection(person)
                    spendingSection(person)
                    giftsSection(person)
                    manageSection(person)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.page)
            } else {
                VStack(spacing: 10) {
                    Text("This person isn't on your list anymore.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle(person?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditPerson) {
            if let person {
                PersonFormView(editing: person)
            }
        }
        .sheet(isPresented: $showAddGift) {
            GiftFormView(editing: nil, defaultPersonID: personID)
        }
        .sheet(item: $editingGift) { gift in
            GiftFormView(editing: gift, defaultPersonID: personID)
        }
        .sheet(isPresented: $showWishList) {
            WishListView(defaultPersonID: personID)
        }
        .confirmationDialog(deletePersonTitle, isPresented: $confirmDeletePerson, titleVisibility: .visible) {
            Button("Delete this person", role: .destructive) {
                Task { await deletePerson() }
            }
            Button("Keep them", role: .cancel) {}
        }
        .confirmationDialog(deleteGiftTitle, isPresented: Binding(
            get: { confirmDeleteGift != nil },
            set: { if !$0 { confirmDeleteGift = nil } }
        ), titleVisibility: .visible) {
            Button("Delete gift", role: .destructive) {
                if let gift = confirmDeleteGift {
                    Task { await deleteGift(gift) }
                }
                confirmDeleteGift = nil
            }
            Button("Keep it", role: .cancel) { confirmDeleteGift = nil }
        }
    }

    private var firstName: String {
        person?.displayName.split(separator: " ").first.map(String.init) ?? "them"
    }

    private var deletePersonTitle: String {
        guard let person else { return "" }
        let n = (giftStore.list?.gifts ?? []).filter { $0.personId == person.id }.count
        return "Delete \(person.displayName) for good? "
            + (n > 0
               ? "This also deletes \(n) gift\(n == 1 ? "" : "s") saved for \(person.displayName), including photos and tracking numbers."
               : "No gifts are saved for \(person.displayName).")
            + " This can't be undone."
    }

    private var deleteGiftTitle: String {
        guard let gift = confirmDeleteGift, let person else { return "" }
        return "\u{201C}\(gift.name ?? "")\u{201D} for \(person.displayName) will be removed for good. Its photos and tracking number are deleted with it. To keep it without showing it, archive it instead."
    }

    // MARK: - Facts

    @ViewBuilder
    private func factsSection(_ person: GiftPerson) -> some View {
        let rows: [(String, String)] = [
            ("Relationship", person.relationship ?? ""),
            ("Sizes", person.sizes ?? ""),
            ("Likes", person.favorites ?? ""),
            ("Hobbies", person.hobbies ?? ""),
            ("Notes", person.notes ?? ""),
        ].filter { !$0.1.isEmpty }
        if !rows.isEmpty {
            Section(header: Text("About")) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.1)
                    }
                }
            }
        }
        if person.isArchived {
            Section {
                Text("\(person.displayName) is archived, so they and their gifts stay out of your lists. Their gift history is kept.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Their days (occasions, with the editor)

    @ViewBuilder
    private func occasionsSection(_ person: GiftPerson) -> some View {
        Section(header: Text("Their days")) {
            let occasions = person.occasions ?? []
            if occasions.isEmpty {
                Text("No dates saved yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(occasions) { occasion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occasion.label ?? "")
                            Text(longDay(occasion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(GiftListStore.daysLabel(daysAway(occasion)))
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.soft)
                            .clipShape(Capsule())
                        Button("Edit") { beginEditOccasion(occasion) }
                            .font(.subheadline)
                        Button("Delete", role: .destructive) {
                            Task { await deleteOccasion(occasion) }
                        }
                        .font(.subheadline)
                    }
                }
            }
            // The web's add-occasion form.
            VStack(alignment: .leading, spacing: 10) {
                TextField("Occasion name (e.g. Birthday)", text: $occLabel)
                Picker("Kind", selection: $occKind) {
                    Text("Custom").tag("custom")
                    Text("Birthday").tag("birthday")
                    Text("Anniversary").tag("anniversary")
                    Text("Holiday").tag("holiday")
                }
                .pickerStyle(.segmented)
                DatePicker("Date", selection: $occDate, displayedComponents: .date)
                Menu("Pick a holiday…") {
                    ForEach(GiftStateKit.holidays, id: \.label) { holiday in
                        Button(holiday.label) {
                            occLabel = holiday.label
                            occKind = "holiday"
                            var components = DateComponents()
                            components.year = Calendar.current.component(.year, from: Date())
                            components.month = holiday.month
                            components.day = holiday.day
                            occDate = Calendar.current.date(from: components) ?? occDate
                        }
                    }
                }
                .font(.subheadline)
                if let occError {
                    Text(occError).font(.caption).foregroundStyle(.red)
                }
                Button(editingOccasionID == nil ? "Save occasion" : "Save occasion") {
                    Task { await saveOccasion() }
                }
                .fontWeight(.semibold)
                if editingOccasionID != nil {
                    Button("Stop editing") {
                        editingOccasionID = nil
                        occLabel = ""
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func daysAway(_ occasion: GiftOccasion) -> Int {
        GiftListStore.daysAway(from: GiftListStore.nextOccurrence(month: occasion.month ?? 1, day: occasion.day ?? 1))
    }

    private func longDay(_ occasion: GiftOccasion) -> String {
        let date = GiftListStore.nextOccurrence(month: occasion.month ?? 1, day: occasion.day ?? 1)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }

    private func beginEditOccasion(_ occasion: GiftOccasion) {
        editingOccasionID = occasion.id
        occLabel = occasion.label ?? ""
        occKind = occasion.kind ?? "custom"
        var components = DateComponents()
        components.year = Calendar.current.component(.year, from: Date())
        components.month = occasion.month ?? 1
        components.day = occasion.day ?? 1
        occDate = Calendar.current.date(from: components) ?? Date()
    }

    private func saveOccasion() async {
        guard let person else { return }
        let label = occLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else {
            occError = "Add a name and a date for this occasion."
            return
        }
        occError = nil
        // The web: a label matching a holiday files as "holiday".
        let kind = GiftStateKit.holidays.contains { $0.label == label } ? "holiday" : occKind
        let parts = Calendar.current.dateComponents([.month, .day], from: occDate)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let pid = person.id
        let editingID = editingOccasionID
        await giftStore.mutate(session: session) { state in
            var people = GiftStateKit.dicts(state["people"])
            for index in people.indices where GiftStateKit.str(people[index]["id"]) == pid {
                var occasions = GiftStateKit.dicts(people[index]["occasions"])
                if let editingID {
                    for oIndex in occasions.indices where GiftStateKit.str(occasions[oIndex]["id"]) == editingID {
                        occasions[oIndex]["label"] = label
                        occasions[oIndex]["kind"] = kind
                        occasions[oIndex]["month"] = month
                        occasions[oIndex]["day"] = day
                    }
                } else {
                    var occasion: GiftStateKit.Dict = [:]
                    occasion["id"] = "o-\(GiftStateKit.nowMillis())"
                    occasion["kind"] = kind
                    occasion["label"] = label
                    occasion["month"] = month
                    occasion["day"] = day
                    occasions.append(occasion)
                }
                people[index]["occasions"] = occasions
            }
            state["people"] = people
        }
        if giftStore.saveState != .failed {
            occLabel = ""
            editingOccasionID = nil
        }
    }

    private func deleteOccasion(_ occasion: GiftOccasion) async {
        guard let person else { return }
        let pid = person.id
        let oid = occasion.id
        await giftStore.mutate(session: session) { state in
            var people = GiftStateKit.dicts(state["people"])
            for index in people.indices where GiftStateKit.str(people[index]["id"]) == pid {
                var occasions = GiftStateKit.dicts(people[index]["occasions"])
                occasions.removeAll { GiftStateKit.str($0["id"]) == oid }
                people[index]["occasions"] = occasions
            }
            state["people"] = people
        }
    }

    // MARK: - Spending

    @ViewBuilder
    private func spendingSection(_ person: GiftPerson) -> some View {
        if giftStore.spent(for: person) > 0 || giftStore.yearlyBudget > 0 {
            Section(header: Text("Spending")) {
                LabeledContent("Spent on \(firstName)", value: GiftListConstants.money(giftStore.spent(for: person)))
                if giftStore.yearlyBudget > 0 {
                    LabeledContent("Spent on everyone", value: GiftListConstants.money(giftStore.spentTotal))
                    LabeledContent("Yearly budget", value: GiftListConstants.money(giftStore.yearlyBudget))
                }
            }
        }
    }

    // MARK: - Gifts

    @ViewBuilder
    private func giftsSection(_ person: GiftPerson) -> some View {
        Section(header: Text("Gifts for \(firstName)")) {
            Button {
                showAddGift = true
            } label: {
                Label("Add a gift", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
            }
            Button {
                showWishList = true
            } label: {
                Label("Load \(firstName)'s wish list from a photo", systemImage: "list.bullet.rectangle")
            }
            if gifts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No gift ideas yet").fontWeight(.semibold)
                    Text("Add an idea now and fill in the details once you buy it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(gifts) { gift in
                    giftRow(gift)
                }
            }
            let archivedCount = (giftStore.list?.gifts ?? []).filter { $0.personId == person.id && $0.isArchived }.count
            if archivedCount > 0 {
                Text("\(archivedCount) archived gift\(archivedCount == 1 ? " is" : "s are") kept in Archived.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func giftRow(_ gift: GiftEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                GiftPhotoView(dataURL: gift.photo, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(gift.name ?? "")
                            .font(.headline)
                        Spacer()
                        if gift.displayPrice > 0 {
                            Text(GiftListConstants.money(gift.displayPrice))
                                .fontWeight(.semibold)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(gift.statusLabel)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.soft)
                            .clipShape(Capsule())
                        if let occasion = gift.occasionLabel, !occasion.isEmpty {
                            Text(occasion).font(.caption).foregroundStyle(.secondary)
                        }
                        if let bought = gift.boughtOn, !bought.isEmpty {
                            Text("Bought \(bought)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let hiding = gift.hidingPlace, !hiding.isEmpty {
                        Label("Hidden in: \(hiding)", systemImage: "eye.slash")
                            .font(.subheadline)
                            .foregroundStyle(Theme.orange)
                    }
                    if let idea = gift.idea, !idea.isEmpty, idea != (gift.name ?? "") {
                        Text(idea).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let tracking = gift.trackingNumber, !tracking.isEmpty {
                        Text("Tracking: \(tracking)\(gift.carrier.map { $0.isEmpty ? "" : " (\($0))" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let ship = gift.shippingPhoto, !ship.isEmpty {
                        GiftPhotoView(dataURL: ship, size: 40)
                    }
                }
            }
            // The web gift row's own buttons.
            HStack(spacing: 14) {
                Menu("Mark…") {
                    ForEach(GiftListConstants.statuses.filter { $0 != gift.normalizedStatus }, id: \.self) { value in
                        Button("Mark \(GiftListConstants.statusLabels[value]?.lowercased() ?? value)") {
                            Task { await setGiftStatus(gift, status: value) }
                        }
                    }
                }
                .font(.subheadline)
                Button("Edit gift") { editingGift = gift }
                    .font(.subheadline)
                Button("Archive gift") {
                    Task { await setGiftArchived(gift, archived: true) }
                }
                .font(.subheadline)
                Button("Delete gift", role: .destructive) { confirmDeleteGift = gift }
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Manage the person

    @ViewBuilder
    private func manageSection(_ person: GiftPerson) -> some View {
        Section(header: Text("About this person")) {
            Button("Edit \(firstName)'s details") { showEditPerson = true }
            Button(person.isArchived ? "Restore to my list" : "Archive this person") {
                Task { await setPersonArchived(person, archived: !person.isArchived) }
            }
            Text("Archiving hides \(person.displayName) from your lists and keeps their gifts. Deleting removes them for good.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete this person", role: .destructive) {
                confirmDeletePerson = true
            }
        }
    }

    // MARK: - Mutations

    private func setGiftStatus(_ gift: GiftEntry, status: String) async {
        let gid = gift.id
        await giftStore.mutate(session: session) { state in
            var gifts = GiftStateKit.dicts(state["gifts"])
            for index in gifts.indices where GiftStateKit.str(gifts[index]["id"]) == gid {
                gifts[index]["status"] = status
            }
            state["gifts"] = gifts
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

    private func deleteGift(_ gift: GiftEntry) async {
        let gid = gift.id
        await giftStore.mutate(session: session) { state in
            var gifts = GiftStateKit.dicts(state["gifts"])
            gifts.removeAll { GiftStateKit.str($0["id"]) == gid }
            state["gifts"] = gifts
        }
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

    /// The web's pdDeleteBtn: the person AND their gifts go.
    private func deletePerson() async {
        guard let person else { return }
        let pid = person.id
        await giftStore.mutate(session: session) { state in
            var people = GiftStateKit.dicts(state["people"])
            people.removeAll { GiftStateKit.str($0["id"]) == pid }
            state["people"] = people
            var gifts = GiftStateKit.dicts(state["gifts"])
            gifts.removeAll { GiftStateKit.str($0["personId"]) == pid }
            state["gifts"] = gifts
        }
        if giftStore.saveState != .failed {
            dismiss()
        }
    }
}

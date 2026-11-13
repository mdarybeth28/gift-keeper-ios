import SwiftUI

/// Add / edit a person — the web app's openPersonForm/savePerson
/// in native dress. Same fields, same rules:
/// - A name is required ("Please type the person's name.").
/// - Category is one of Family/Friends/Work/Other.
/// - A birthday can be set when the person is ADDED (it becomes
///   their first occasion, kind "birthday", label "Birthday");
///   the web form hides the birthday in edit mode — occasions are
///   edited on the person's own page instead.
/// - A new person's color comes from the web's PALETTE by their
///   index in the list, and a blank relationship saves as
///   "Friend" (new) — edits store exactly what was typed.
struct PersonFormView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @Environment(\.dismiss) private var dismiss

    /// nil when adding a new person.
    let editing: GiftPerson?

    var onSaved: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var relationship = ""
    @State private var category = "Other"
    @State private var sizes = ""
    @State private var favorites = ""
    @State private var hobbies = ""
    @State private var notes = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Relationship (e.g. Daughter, Friend)", text: $relationship)
                    Picker("Category", selection: $category) {
                        ForEach(GiftListConstants.categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if editing == nil {
                    Section(header: Text("Birthday")) {
                        Toggle("Add their birthday", isOn: $hasBirthday)
                        if hasBirthday {
                            DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                        }
                    }
                }
                Section(header: Text("Good to know")) {
                    TextField("Sizes", text: $sizes)
                    TextField("Favorite things", text: $favorites, axis: .vertical).lineLimit(1...3)
                    TextField("Hobbies and interests", text: $hobbies, axis: .vertical).lineLimit(1...3)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
                if giftStore.saveState == .failed {
                    Section {
                        Text("Couldn't save to your account — check your connection and try again.")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() }
                            Text(editing == nil ? "Add person" : "Save changes")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle(editing == nil ? "Add a person" : "Edit \(firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var firstName: String {
        (editing?.displayName ?? "").split(separator: " ").first.map(String.init) ?? "person"
    }

    private func prefill() {
        guard let editing, name.isEmpty else { return }
        name = editing.displayName
        relationship = editing.relationship ?? ""
        category = editing.displayCategory
        sizes = editing.sizes ?? ""
        favorites = editing.favorites ?? ""
        hobbies = editing.hobbies ?? ""
        notes = editing.notes ?? ""
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            error = "Please type the person's name."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let rel = relationship.trimmingCharacters(in: .whitespaces)
        if let editing {
            let pid = editing.id
            await giftStore.mutate(session: session) { state in
                var people = GiftStateKit.dicts(state["people"])
                for index in people.indices where GiftStateKit.str(people[index]["id"]) == pid {
                    people[index]["name"] = trimmedName
                    people[index]["relationship"] = rel
                    people[index]["category"] = category
                    people[index]["sizes"] = sizes
                    people[index]["favorites"] = favorites
                    people[index]["hobbies"] = hobbies
                    people[index]["notes"] = notes
                }
                state["people"] = people
            }
            onSaved(pid)
        } else {
            let stamp = GiftStateKit.nowMillis()
            let id = "p-\(stamp)"
            let index = giftStore.allPeople.count
            var occasions: [Any] = []
            if hasBirthday {
                let parts = Calendar.current.dateComponents([.month, .day], from: birthday)
                var occasion: GiftStateKit.Dict = [:]
                occasion["id"] = "o-\(stamp)"
                occasion["kind"] = "birthday"
                occasion["label"] = "Birthday"
                occasion["month"] = parts.month ?? 1
                occasion["day"] = parts.day ?? 1
                occasions.append(occasion)
            }
            var person: GiftStateKit.Dict = [:]
            person["id"] = id
            person["name"] = trimmedName
            person["relationship"] = rel.isEmpty ? "Friend" : rel
            person["category"] = GiftListConstants.categories.contains(category) ? category : "Other"
            person["color"] = GiftStateKit.palette[index % GiftStateKit.palette.count]
            person["occasions"] = occasions
            person["sizes"] = sizes.trimmingCharacters(in: .whitespaces)
            person["favorites"] = favorites.trimmingCharacters(in: .whitespaces)
            person["hobbies"] = hobbies.trimmingCharacters(in: .whitespaces)
            person["notes"] = notes
            await giftStore.mutate(session: session) { state in
                var people = GiftStateKit.dicts(state["people"])
                people.append(person)
                state["people"] = people
            }
            onSaved(id)
        }
        if giftStore.saveState != .failed {
            dismiss()
        }
    }
}

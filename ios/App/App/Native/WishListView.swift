import SwiftUI
import PhotosUI

/// Load a wish list from one photo — the web's openWishList /
/// readWishPhoto / saveWishList. One photo of a whole list
/// (handwritten or printed) is read by the same read-gift door in
/// its list mode into a REVIEW list: the person checks every
/// line, fixes or drops lines, adds lines the photo missed, and
/// only Save writes — every kept wish lands as a "thinking" gift
/// through the same save path as everything else. The list photo
/// itself is kept on the FIRST saved wish, in its gift photo slot
/// and marked in its note.
///
/// The web's other rules, kept:
/// - The person is picked from your own people and only ever
///   defaults to the person whose page you came from — a read
///   never creates a person.
/// - A read that fails or finds no lines never blocks anything:
///   the list can be typed in line by line, and the photo can be
///   sent to Mary through the feedback door.
struct WishListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @Environment(\.dismiss) private var dismiss

    var defaultPersonID: String? = nil
    var onSaved: (String) -> Void = { _ in }

    private struct WishRow: Identifiable {
        let id = UUID()
        var name = ""
        var note = ""
        var unsure = false
    }

    @State private var personID = ""
    @State private var occasion = "Christmas"
    @State private var rows: [WishRow] = []
    @State private var skipped: [String] = []
    @State private var photoData: Data?
    @State private var readItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var note = "Pick the photo of the whole list — one photo does it. I'll read every line, then you check them before anything is saved."
    @State private var error: String?
    @State private var isSaving = false
    @State private var showFeedback = false
    @State private var didInit = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Whose list is this?", selection: $personID) {
                        ForEach(giftStore.visiblePeople) { person in
                            Text(person.displayName).tag(person.id)
                        }
                    }
                    .onChange(of: personID) { _ in
                        occasion = "Christmas"
                    }
                    Picker("Occasion", selection: $occasion) {
                        ForEach(occasionOptions, id: \.self) { option in
                            Text(option.isEmpty ? "Any occasion" : option).tag(option)
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("📋 Load a whole wish list from one photo")
                            .font(.headline)
                            .foregroundStyle(Theme.brown)
                        PhotosPicker(selection: $readItem, matching: .images, photoLibrary: .shared()) {
                            HStack {
                                if isReading { ProgressView() }
                                Text(isReading ? "Reading…" : "Pick the list photo")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isReading)
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if photoData != nil {
                            Button("Can't read it? Send this photo to Mary") {
                                showFeedback = true
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(header: Text("Check the list")) {
                    Text("Fix any line, tap ✕ to drop one, and add anything the photo missed. The photo itself is kept on the first wish in the list, so you can look at the paper again any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Wish", text: $row.name)
                                TextField("Note (optional)", text: $row.note)
                                    .font(.subheadline)
                                if row.unsure {
                                    Text("Wasn't fully clear on the paper — double-check this one.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.amber)
                                }
                            }
                            Button {
                                rows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("＋ Add another item") {
                        rows.append(WishRow())
                    }
                }
                if !skipped.isEmpty {
                    Section(header: Text("Crossed out on the paper — left off on purpose")) {
                        ForEach(skipped, id: \.self) { line in
                            Text("✕ \(line)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                            Text(saveLabel).fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("Wish list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard !didInit else { return }
                didInit = true
                if let defaultPersonID, giftStore.person(id: defaultPersonID) != nil {
                    personID = defaultPersonID
                } else {
                    personID = giftStore.visiblePeople.first?.id ?? ""
                }
            }
            .onChange(of: readItem) { newItem in
                guard let newItem else { return }
                Task { await loadAndRead(newItem) }
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView(
                    initialMessage: "Gift Keeper couldn't read this wish list photo — could you look at it for me?",
                    initialPhotoData: photoData)
            }
        }
    }

    private var person: GiftPerson? { giftStore.person(id: personID) }

    private var saveLabel: String {
        let kept = rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return kept > 0 ? "Save \(kept) wish\(kept == 1 ? "" : "es")" : "Save wishes"
    }

    /// The web's fillWishOccasionSelect choices for the picked
    /// person (their labels, then holidays). "" = "Any occasion".
    private var occasionOptions: [String] {
        var options: [String] = [""]
        let labels = (person?.occasions ?? []).compactMap { $0.label }.filter { !$0.isEmpty }
        options += labels
        for holiday in GiftStateKit.holidays where !labels.contains(holiday.label) {
            options.append(holiday.label)
        }
        if !occasion.isEmpty && !options.contains(occasion) {
            options.insert(occasion, at: 1)
        }
        return options
    }

    // MARK: - The read (the web's readWishPhoto / applyWishRead)

    private func loadAndRead(_ item: PhotosPickerItem) async {
        isReading = true
        note = "Reading your photo…"
        defer { isReading = false }
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            note = "That photo could not be opened — you can still type the list in line by line below."
            return
        }
        let prepared = GiftPhoto.preparedJPEG(from: raw)
        photoData = prepared
        guard let token = await session.validAccessToken() else {
            note = "Your sign-in expired. Please sign out and sign in again."
            return
        }
        do {
            let rd = try await GiftWriteService.readWishList(accessToken: token, imageData: prepared, mimeType: "image/jpeg")
            applyWishRead(rd)
        } catch {
            note = "That read didn't go through — the reader may be busy, or the photo may not have loaded. The photo is shown above, you can type the list in line by line, and you can send the photo to Mary below."
        }
    }

    private func applyWishRead(_ rd: WishRead) {
        var newRows: [WishRow] = []
        let items = rd.items ?? []
        for item in items {
            newRows.append(WishRow(name: item.name ?? "", note: item.note ?? "", unsure: item.unsure == true))
        }
        let unsureLines = (rd.unsureLines ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for line in unsureLines {
            newRows.append(WishRow(name: line.trimmingCharacters(in: .whitespaces), note: "", unsure: true))
        }
        rows = newRows
        skipped = (rd.skipped ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let nUnsure = items.filter { $0.unsure == true }.count + unsureLines.count
        let total = items.count + unsureLines.count
        // The web's wishReadSummaryText, in its shape.
        var text = "📸 Read \(total) line\(total == 1 ? "" : "s") from your photo — nothing is saved yet."
        if nUnsure > 0 {
            text += " \(nUnsure) of them \(nUnsure == 1 ? "wasn't" : "weren't") fully clear — those are marked, so double-check them."
        }
        if !skipped.isEmpty {
            text += " \(skipped.count) crossed-out line\(skipped.count == 1 ? " was" : "s were") left off on purpose."
        }
        text += " Check every line, fix or drop any, then tap Save."
        if total == 0 {
            text = "I couldn't read any lines from that photo — the photo is shown above, you can type the list in line by line, and you can send the photo to Mary below."
        }
        note = text
    }

    // MARK: - Save (the web's saveWishList)

    private func save() async {
        guard let person else {
            error = "Pick whose list this is first."
            return
        }
        let kept = rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !kept.isEmpty else {
            error = "Add at least one wish first — type a line, or load a photo."
            return
        }
        error = nil
        isSaving = true
        defer { isSaving = false }
        let pid = person.id
        let occ = occasion.isEmpty ? "Any occasion" : occasion
        let base = GiftStateKit.nowMillis()
        let photoURL = photoData.map { GiftPhoto.dataURL(fromJPEG: $0) }
        var made: [GiftStateKit.Dict] = []
        for (index, row) in kept.enumerated() {
            var idea = row.note.trimmingCharacters(in: .whitespaces)
            if index == 0 && photoURL != nil {
                idea = idea.isEmpty ? "Wish list photo" : idea + " (wish list photo)"
            }
            var gift: GiftStateKit.Dict = [:]
            gift["id"] = "g-\(base + index)"
            gift["trackingStatus"] = ""
            gift["trackingUpdatedAt"] = ""
            gift["personId"] = pid
            gift["name"] = row.name.trimmingCharacters(in: .whitespaces)
            gift["idea"] = idea
            gift["price"] = 0
            gift["boughtOn"] = ""
            gift["occasionLabel"] = occ
            gift["hidingPlace"] = "Not hidden yet"
            gift["status"] = "thinking"
            if index == 0, let photoURL {
                gift["photo"] = photoURL
            } else {
                gift["photo"] = NSNull()
            }
            gift["shippingPhoto"] = NSNull()
            gift["carrier"] = ""
            gift["trackingNumber"] = ""
            made.append(gift)
        }
        await giftStore.mutate(session: session) { state in
            var gifts = GiftStateKit.dicts(state["gifts"])
            gifts = made + gifts
            state["gifts"] = gifts
        }
        if giftStore.saveState != .failed {
            onSaved(pid)
            dismiss()
        }
    }
}

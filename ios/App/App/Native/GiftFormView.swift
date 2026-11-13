import SwiftUI
import PhotosUI

/// Add / edit a gift — the web app's gift form (openGiftForm /
/// saveGift) in native dress, including Jessica's multi-person
/// chips and the price choice, and the 📸 screenshot/label
/// reader with review-before-save.
///
/// The web's rules, kept:
/// - Edit mode touches ONLY that gift's own copy; the chips lock
///   to its person. Add mode files one separate copy per picked
///   person in a single save.
/// - At 2+ picks the price choice appears: "Each pays full
///   price" (default — one copy each at the full price) vs
///   "Split it between them" (one shared gift — gfSplitPrices,
///   cent-exact, odd cent on the first copy).
/// - Defaults on save: occasion "Any occasion", hiding place
///   "Not hidden yet", boughtOn "" while the status is thinking,
///   new gifts start with empty trackingStatus/trackingUpdatedAt.
/// - The reader fills only fields the form still has empty (the
///   purchase date counts as empty while it still shows today),
///   never overwrites typed words, picks the recipient only when
///   the read name matches one of your people letter for letter
///   apart from case/spacing, and the occasion only when the read
///   names one the form offers. Nothing is saved by a read.
struct GiftFormView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @Environment(\.dismiss) private var dismiss

    let editing: GiftEntry?
    var defaultPersonID: String? = nil
    var onSaved: (String) -> Void = { _ in }

    // Form fields (the web's gf* inputs).
    @State private var pickedIDs: [String] = []
    @State private var name = ""
    @State private var occasion = ""
    @State private var priceText = ""
    @State private var boughtOn = Date()
    @State private var hiding = ""
    @State private var status = "purchased"
    @State private var idea = ""
    @State private var carrier = ""
    @State private var tracking = ""
    @State private var photoDataURL: String?
    @State private var shipDataURL: String?
    @State private var splitMode = "full"

    // The reader.
    @State private var readItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var readNote = ""
    @State private var lastReadPhotoData: Data?
    @State private var showFeedback = false

    // Photo slots.
    @State private var photoItem: PhotosPickerItem?
    @State private var shipItem: PhotosPickerItem?

    @State private var error: String?
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var didPrefill = false

    private var isEditing: Bool { editing != nil }
    private var folks: [GiftPerson] { giftStore.visiblePeople }

    var body: some View {
        NavigationStack {
            Form {
                readerSection
                whoSection
                giftSections
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
                            Text(isEditing ? "Save gift" : "Save gift").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
                if isEditing {
                    Section {
                        Button("Delete this gift", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle(isEditing ? "Edit gift" : "Add a gift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
            .confirmationDialog("Delete this gift for good?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete this gift", role: .destructive) {
                    Task { await deleteGift() }
                }
                Button("Keep it", role: .cancel) {}
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView(
                    initialMessage: "Gift Keeper couldn't read this photo — could you look at it for me?",
                    initialPhotoData: carryPhotoData)
            }
            .onChange(of: readItem) { newItem in
                guard let newItem else { return }
                Task { await loadAndRead(newItem) }
            }
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let raw = try? await newItem.loadTransferable(type: Data.self) {
                        photoDataURL = GiftPhoto.dataURL(fromJPEG: GiftPhoto.preparedJPEG(from: raw))
                    }
                }
            }
            .onChange(of: shipItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let raw = try? await newItem.loadTransferable(type: Data.self) {
                        shipDataURL = GiftPhoto.dataURL(fromJPEG: GiftPhoto.preparedJPEG(from: raw))
                    }
                }
            }
        }
    }

    // MARK: - The reader card (the web's 📸 door)

    @ViewBuilder
    private var readerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("📸 Read a screenshot or label")
                    .font(.headline)
                    .foregroundStyle(Theme.brown)
                Text("Pick an order screenshot or a shipping-label photo and I'll fill in what I can read. Nothing is saved until you tap Save gift.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PhotosPicker(selection: $readItem, matching: .images, photoLibrary: .shared()) {
                    HStack {
                        if isReading { ProgressView() }
                        Text(isReading ? "Reading…" : "Pick the photo")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isReading)
                if !readNote.isEmpty {
                    Text(readNote)
                        .font(.subheadline)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12))
                    if lastReadPhotoData != nil || photoDataURL != nil || shipDataURL != nil {
                        Button("Can't read it? Send this photo to Mary") {
                            showFeedback = true
                        }
                        .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var carryPhotoData: Data? {
        if let lastReadPhotoData { return lastReadPhotoData }
        for slot in [photoDataURL, shipDataURL] {
            if let slot, let comma = slot.firstIndex(of: ","),
               let data = Data(base64Encoded: String(slot[slot.index(after: comma)...])) {
                return data
            }
        }
        return nil
    }

    // MARK: - Who it's for (the chips)

    @ViewBuilder
    private var whoSection: some View {
        Section(header: Text("Who is it for? *")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(folks) { person in
                    Button {
                        togglePick(person.id)
                    } label: {
                        Text(person.displayName)
                            .font(.subheadline).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(pickedIDs.contains(person.id) ? Theme.orange : Theme.soft,
                                        in: Capsule())
                            .foregroundStyle(pickedIDs.contains(person.id) ? .white : Theme.brown)
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditing)
                }
            }
            Text(isEditing
                 ? "Editing changes only this person's copy — the same gift saved for somebody else keeps its own details."
                 : "Tap a name — or tap two or more when the same gift is for more than one person. You type it once; it saves under each name you tapped.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isEditing && pickedIDs.count > 1 {
                Picker("Price", selection: $splitMode) {
                    Text("Each pays full price").tag("full")
                    Text("Split it between them").tag("split")
                }
                .pickerStyle(.segmented)
                Text(splitNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func togglePick(_ id: String) {
        if let index = pickedIDs.firstIndex(of: id) {
            pickedIDs.remove(at: index)
        } else {
            pickedIDs.append(id)
        }
        // The occasion choices follow the FIRST picked person
        // (the web refills its occasion select the same way).
        occasion = firstPickedPerson?.occasions?.first?.label ?? ""
    }

    private var firstPickedPerson: GiftPerson? {
        guard let first = pickedIDs.first else { return nil }
        return giftStore.person(id: first)
    }

    /// The web's gfSplitNoteUpdate words.
    private var splitNote: String {
        let n = pickedIDs.count
        let price = Double(priceText) ?? 0
        let dollars = String(format: "$%.2f", price)
        if splitMode == "split" {
            return price > 0
                ? "One gift, bought once: \(dollars) split between the \(n) of them — together it still counts \(dollars) spent, not \(n) times that."
                : "One gift, bought once: its price is split between them, so together it counts once."
        }
        return "Bought one each: the full price counts for every person — the way typing it in for each of them did."
    }

    // MARK: - The gift fields

    @ViewBuilder
    private var giftSections: some View {
        Section(header: Text("The gift")) {
            TextField("Gift name *", text: $name)
            Picker("Occasion", selection: $occasion) {
                ForEach(occasionOptions, id: \.self) { option in
                    Text(option.isEmpty ? "Any occasion" : option).tag(option)
                }
            }
            HStack {
                Text("Price $")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $priceText)
                    .keyboardType(.decimalPad)
            }
            Picker("Status", selection: $status) {
                ForEach(GiftListConstants.statuses, id: \.self) { value in
                    Text(GiftListConstants.statusLabels[value] ?? value).tag(value)
                }
            }
            .pickerStyle(.segmented)
            if status != "thinking" {
                DatePicker("Bought on", selection: $boughtOn, displayedComponents: .date)
            }
            TextField("Where did you hide it?", text: $hiding)
            TextField("Idea / notes", text: $idea, axis: .vertical).lineLimit(1...3)
        }
        Section(header: Text("Shipping")) {
            Picker("Carrier", selection: $carrier) {
                ForEach(carrierOptions, id: \.self) { value in
                    Text(value.isEmpty ? "No carrier" : value).tag(value)
                }
            }
            TextField("Tracking number", text: $tracking)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
        }
        Section(header: Text("Photos")) {
            photoSlot(title: "Gift photo", dataURL: photoDataURL, item: $photoItem) {
                photoDataURL = nil
            }
            photoSlot(title: "Shipping label photo", dataURL: shipDataURL, item: $shipItem) {
                shipDataURL = nil
            }
        }
    }

    @ViewBuilder
    private func photoSlot(title: String, dataURL: String?, item: Binding<PhotosPickerItem?>, remove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).fontWeight(.semibold)
            if let dataURL, let image = GiftPhoto.image(fromDataURL: dataURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Remove this photo", role: .destructive, action: remove)
                    .font(.subheadline)
            } else {
                PhotosPicker(selection: item, matching: .images, photoLibrary: .shared()) {
                    Label("Add a photo", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The web's fillOccasionSelect choices for the first picked
    /// person: their own occasion labels first, then the holidays
    /// they don't already have, then the current value if it is
    /// something else entirely. "" stands for "Any occasion".
    private var occasionOptions: [String] {
        var options: [String] = [""]
        let labels = (firstPickedPerson?.occasions ?? []).compactMap { $0.label }.filter { !$0.isEmpty }
        options += labels
        for holiday in GiftStateKit.holidays where !labels.contains(holiday.label) {
            options.append(holiday.label)
        }
        if !occasion.isEmpty && !options.contains(occasion) {
            options.insert(occasion, at: 1)
        }
        return options
    }

    /// The web's fillCarrierSelect: the usual carriers, plus the
    /// gift's own carrier when it is something else (a read can
    /// bring one the list doesn't know).
    private var carrierOptions: [String] {
        var options = GiftListConstants.carriers
        if !carrier.isEmpty && !options.contains(carrier) {
            options.append(carrier)
        }
        return options
    }

    // MARK: - Prefill

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let editing {
            pickedIDs = [editing.personId ?? ""].filter { !$0.isEmpty }
            name = editing.name ?? ""
            occasion = editing.occasionLabel ?? ""
            priceText = (editing.price ?? 0) == 0 ? "" : Self.priceString(editing.price ?? 0)
            boughtOn = GiftStateKit.parseDay(editing.boughtOn) ?? Date()
            hiding = editing.hidingPlace ?? ""
            status = editing.normalizedStatus
            idea = editing.idea ?? ""
            carrier = editing.carrier ?? ""
            tracking = editing.trackingNumber ?? ""
            photoDataURL = editing.photo
            shipDataURL = editing.shippingPhoto
        } else {
            let start = defaultPersonID ?? folks.first?.id
            pickedIDs = start.map { [$0] } ?? []
            occasion = firstPickedPerson?.occasions?.first?.label ?? ""
            status = "purchased"
            boughtOn = Date()
        }
    }

    static func priceString(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    // MARK: - Save / delete (the web's saveGift / deleteGiftFromForm)

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let pids = isEditing ? [] : pickedIDs
        let pid = isEditing ? (editing?.personId ?? "") : (pids.first ?? "")
        guard !trimmedName.isEmpty else {
            error = "Give the gift a short name, like \u{201C}lavender soap\u{201D}."
            return
        }
        guard !pid.isEmpty else {
            error = "Tap the name of who this gift is for — tap two names if it is for two people."
            return
        }
        if !priceText.isEmpty && Double(priceText) == nil {
            error = "The price should be a number, like 24.50."
            return
        }
        error = nil
        isSaving = true
        defer { isSaving = false }

        var fields: GiftStateKit.Dict = [:]
        fields["personId"] = pid
        fields["name"] = trimmedName
        fields["idea"] = idea.trimmingCharacters(in: .whitespaces)
        fields["price"] = Double(priceText) ?? 0
        fields["boughtOn"] = status == "thinking" ? "" : GiftStateKit.isoString(boughtOn)
        fields["occasionLabel"] = occasion.isEmpty ? "Any occasion" : occasion
        let trimmedHiding = hiding.trimmingCharacters(in: .whitespaces)
        fields["hidingPlace"] = trimmedHiding.isEmpty ? "Not hidden yet" : trimmedHiding
        fields["status"] = status
        if let photoDataURL { fields["photo"] = photoDataURL } else { fields["photo"] = NSNull() }
        if let shipDataURL { fields["shippingPhoto"] = shipDataURL } else { fields["shippingPhoto"] = NSNull() }
        fields["carrier"] = carrier
        fields["trackingNumber"] = tracking.trimmingCharacters(in: .whitespaces)

        if let editing {
            let gid = editing.id
            await giftStore.mutate(session: session) { state in
                var gifts = GiftStateKit.dicts(state["gifts"])
                for index in gifts.indices where GiftStateKit.str(gifts[index]["id"]) == gid {
                    for (key, value) in fields { gifts[index][key] = value }
                }
                state["gifts"] = gifts
            }
        } else if pids.count > 1 {
            let stamp = GiftStateKit.nowMillis()
            let prices = splitMode == "split"
                ? GiftStateKit.splitPrices(total: Double(priceText) ?? 0, count: pids.count)
                : pids.map { _ in Double(priceText) ?? 0 }
            var made: [GiftStateKit.Dict] = []
            for (ix, pp) in pids.enumerated() {
                var copy = fields
                copy["id"] = "g-\(stamp)-\(ix)"
                copy["trackingStatus"] = ""
                copy["trackingUpdatedAt"] = ""
                copy["personId"] = pp
                copy["price"] = prices[ix]
                made.append(copy)
            }
            await giftStore.mutate(session: session) { state in
                var gifts = GiftStateKit.dicts(state["gifts"])
                gifts = made + gifts
                state["gifts"] = gifts
            }
        } else {
            var gift = fields
            gift["id"] = "g-\(GiftStateKit.nowMillis())"
            gift["trackingStatus"] = ""
            gift["trackingUpdatedAt"] = ""
            await giftStore.mutate(session: session) { state in
                var gifts = GiftStateKit.dicts(state["gifts"])
                gifts = [gift] + gifts
                state["gifts"] = gifts
            }
        }
        if giftStore.saveState != .failed {
            onSaved(pid)
            dismiss()
        }
    }

    private func deleteGift() async {
        guard let editing else { return }
        let gid = editing.id
        await giftStore.mutate(session: session) { state in
            var gifts = GiftStateKit.dicts(state["gifts"])
            gifts.removeAll { GiftStateKit.str($0["id"]) == gid }
            state["gifts"] = gifts
        }
        if giftStore.saveState != .failed {
            dismiss()
        }
    }

    // MARK: - The read (the web's readGiftPhoto / applyGiftRead)

    private func loadAndRead(_ item: PhotosPickerItem) async {
        isReading = true
        readNote = "Reading your photo…"
        defer { isReading = false }
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            readNote = "That photo could not be opened — the form works the same as always: fill in what you need and tap Save gift."
            return
        }
        let prepared = GiftPhoto.preparedJPEG(from: raw)
        lastReadPhotoData = prepared
        guard let token = await session.validAccessToken() else {
            readNote = "Your sign-in expired. Please sign out and sign in again."
            return
        }
        do {
            let rd = try await GiftWriteService.readGift(accessToken: token, imageData: prepared, mimeType: "image/jpeg")
            let durl = GiftPhoto.dataURL(fromJPEG: prepared)
            if rd.isEmpty {
                _ = attachReadPhoto(rd, dataURL: durl)
                readNote = "I couldn't read anything usable from that photo — it's still attached below, and the form works the same as always: fill in what you need and tap Save gift."
                return
            }
            applyGiftRead(rd, dataURL: durl)
        } catch {
            // The form is never blocked by a failed read: the
            // photo itself still lands in a photo slot.
            _ = attachReadPhoto(nil, dataURL: GiftPhoto.dataURL(fromJPEG: prepared))
            readNote = "That read didn't go through — the reader may be busy, or the photo may not have loaded. Your photo is attached below anyway, and you can fill the form in by hand, same as always."
        }
    }

    /// The web's attachReadPhoto: a label-looking read (tracking
    /// but no price) goes to the shipping-label slot, anything
    /// else to the gift photo slot; a slot already filled by hand
    /// is never overwritten — the other slot takes it instead.
    /// Returns "gift", "label", or "" when both slots were taken.
    private func attachReadPhoto(_ rd: GiftRead?, dataURL: String) -> String {
        let looksLabel = !(rd?.trackingNumber ?? "").isEmpty && (rd?.price ?? "").isEmpty
        if looksLabel {
            if shipDataURL == nil { shipDataURL = dataURL; return "label" }
            if photoDataURL == nil { photoDataURL = dataURL; return "gift" }
        } else {
            if photoDataURL == nil { photoDataURL = dataURL; return "gift" }
            if shipDataURL == nil { shipDataURL = dataURL; return "label" }
        }
        return ""
    }

    private func applyGiftRead(_ rd: GiftRead, dataURL: String) {
        var filled: [String] = []
        var notes: [String] = []
        var conflict = false
        let slot = attachReadPhoto(rd, dataURL: dataURL)

        func fillText(_ key: String, _ current: String, _ set: (String) -> Void) {
            guard let value = rd.value(forKey: key), !value.isEmpty else { return }
            if current.trimmingCharacters(in: .whitespaces).isEmpty {
                set(value)
                filled.append(GiftRead.fieldName(key))
            } else if current.trimmingCharacters(in: .whitespaces) != value {
                conflict = true
            }
        }

        fillText("gift_name", name) { name = $0 }
        fillText("price", priceText) { priceText = $0 }
        if let value = rd.purchaseDate, !value.isEmpty {
            let current = GiftStateKit.isoString(boughtOn)
            if current == GiftStateKit.todayISO() {
                if let day = GiftStateKit.parseDay(value) { boughtOn = day }
                filled.append("the purchase date")
            } else if current != value {
                conflict = true
            }
        }
        fillText("tracking_number", tracking) { tracking = $0 }
        if let value = rd.carrier, !value.isEmpty {
            if carrier.isEmpty {
                if !GiftListConstants.carriers.contains(value) {
                    // The web adds the read carrier to its select;
                    // the native picker shows it as the selection
                    // even when it isn't one of the usual carriers.
                }
                carrier = value
                filled.append("the carrier")
            } else if carrier != value {
                conflict = true
            }
        }
        fillText("hiding_place", hiding) { hiding = $0 }

        if !isEditing, let recipient = rd.recipientName, !recipient.isEmpty {
            let want = GiftStateKit.giftNameKey(recipient)
            if let matched = folks.first(where: { GiftStateKit.giftNameKey($0.displayName) == want }) {
                pickedIDs = [matched.id]
                occasion = matched.occasions?.first?.label ?? ""
                filled.append("who it's for (\(matched.displayName))")
            } else {
                notes.append("The photo is addressed to \u{201C}\(recipient)\u{201D} — that name doesn't match your people, so pick who it's for above (or add them first).")
            }
        }

        if let readOccasion = rd.occasion, !readOccasion.isEmpty {
            let key = GiftStateKit.giftNameKey(readOccasion)
            if let hit = occasionOptions.first(where: { !$0.isEmpty && GiftStateKit.giftNameKey($0) == key }) {
                occasion = hit
                filled.append("the occasion")
            } else {
                notes.append("It looked like the occasion was \u{201C}\(readOccasion)\u{201D} — pick it in the list above if that's right.")
            }
        }

        let allKeys: [(String, String)] = [
            ("gift_name", "the gift's name"), ("price", "the price"),
            ("purchase_date", "the purchase date"), ("tracking_number", "the tracking number"),
            ("carrier", "the carrier"), ("recipient_name", "who it's for"),
            ("occasion", "the occasion"),
        ]
        let missed = allKeys.filter { (rd.value(forKey: $0.0) ?? "").isEmpty }.map { $0.1 }
        var warn: [String] = []
        for key in rd.unsure ?? [] {
            if !(rd.value(forKey: key) ?? "").isEmpty {
                warn.append(GiftRead.fieldName(key))
            }
        }

        var text = "📸 Read from your photo" + (rd.cached == true ? " (this photo was read before, so this one was free)" : "") + " — nothing is saved yet."
        if !filled.isEmpty { text += " Filled in: " + filled.joined(separator: ", ") + "." }
        if slot == "gift" { text += " The photo is saved with the gift below." }
        if slot == "label" { text += " The photo is saved as the shipping label below." }
        if conflict { text += " A thing or two on the photo was already filled in on the form, so I left yours alone." }
        if !warn.isEmpty { text += " Double-check " + warn.joined(separator: " and ") + " — it wasn't fully clear." }
        if !missed.isEmpty { text += " Couldn't read: " + missed.joined(separator: ", ") + "." }
        for note in notes { text += " " + note }
        text += " Check it all over, fix anything, then tap Save gift."
        readNote = text
    }
}

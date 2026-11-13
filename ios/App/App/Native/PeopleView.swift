import SwiftUI

/// The People tab — the native home screen. Reads the signed-in
/// account's REAL gift list (the same gift_lists blob the web app
/// uses) and shows the people on it, grouped by the web's
/// categories. All states honest: restoring, signed out (the
/// sign-in form), loading, error with the server's words,
/// genuinely empty, and the list itself. There is no sample data
/// anywhere in this screen.
struct PeopleView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @State private var showAddPerson = false
    @State private var showAddGift = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Your people")
                .toolbar {
                    if session.isSignedIn {
                        ToolbarItem(placement: .navigationBarLeading) {
                            if let text = giftStore.saveStatusText {
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(giftStore.saveState == .failed ? Theme.warn : Theme.muted)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button("Add a person") { showAddPerson = true }
                                Button("Add a gift") { showAddGift = true }
                                Button("Sign out") {
                                    Task { await session.signOut() }
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showAddPerson) {
                    PersonFormView(editing: nil)
                }
                .sheet(isPresented: $showAddGift) {
                    GiftFormView(editing: nil, defaultPersonID: nil)
                }
        }
        .task(id: session.state) {
            if session.state == .signedIn { await giftStore.load(session: session) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .restoring:
            ProgressView("One moment…")
        case .signedOut:
            SignInView()
        case .signedIn:
            if giftStore.isLoading && giftStore.list == nil {
                ProgressView("Loading your list…")
            } else if let loadError = giftStore.loadError, giftStore.list == nil {
                VStack(spacing: 12) {
                    Text("Something went wrong")
                        .font(.headline)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await giftStore.load(session: session) } }
                }
                .padding()
            } else if giftStore.visiblePeople.isEmpty {
                VStack(spacing: 12) {
                    Text("🎁").font(.largeTitle)
                    Text("No people yet")
                        .font(.headline)
                    Text("Add your first person and Gift Keeper starts keeping track — what you bought, who it's for, and where you hid it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add a person") { showAddPerson = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding()
            } else {
                List {
                    ForEach(giftStore.peopleByCategory, id: \.category) { group in
                        Section(header: Text(group.category)) {
                            ForEach(group.people) { person in
                                NavigationLink {
                                    PersonDetailView(personID: person.id)
                                } label: {
                                    personRow(person)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.page)
                .refreshable { await giftStore.load(session: session) }
            }
        }
    }

    private func personRow(_ person: GiftPerson) -> some View {
        let gifts = giftStore.gifts(for: person)
        let spent = giftStore.spent(for: person)
        return HStack(spacing: 12) {
            Circle()
                .fill(Color(hexString: person.color) ?? Theme.orange)
                .frame(width: 38, height: 38)
                .overlay(
                    Text(initials(of: person.displayName))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.headline)
                Text(subtitle(giftCount: gifts.count, spent: spent, relationship: person.relationship))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(giftCount: Int, spent: Double, relationship: String?) -> String {
        var parts: [String] = []
        if let relationship, !relationship.isEmpty { parts.append(relationship) }
        parts.append(giftCount == 1 ? "1 gift" : "\(giftCount) gifts")
        if spent > 0 { parts.append("\(GiftListConstants.money(spent)) spent") }
        return parts.joined(separator: " · ")
    }

    /// The web app's initials(): first letters of the first two
    /// words of the name.
    private func initials(of name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
            .ifEmpty("?")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension Color {
    /// Parses the web palette's "#rrggbb" strings (person.color).
    /// Anything unparseable yields nil and the caller uses the
    /// web's own default green (#1f6f5c).
    init?(hexString: String?) {
        guard let hexString else { return nil }
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

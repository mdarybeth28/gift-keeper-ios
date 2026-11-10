import SwiftUI

/// The "Still to buy" tab — the errand list across all people.
/// Two sections, from the blob's real statuses:
///   Still to get          — status thinking (not bought yet)
///   Bought — still to wrap — status purchased (bought, not yet
///                            wrapped or given; the hiding place
///                            shows here, because bought-and-hidden
///                            is this app's home state)
/// Wrapped/given gifts are finished and live on each person's
/// page. Signed-out shows the sign-in form, same as People.
struct StillToBuyView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Still to buy")
        }
        .task(id: session.state) {
            if session.state == .signedIn && giftStore.list == nil {
                await giftStore.load(session: session)
            }
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
                    Text("Something went wrong").font(.headline)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await giftStore.load(session: session) } }
                }
                .padding()
            } else if giftStore.stillToGet.isEmpty && giftStore.boughtToWrap.isEmpty {
                VStack(spacing: 10) {
                    Text("✅").font(.largeTitle)
                    Text("Nothing still to buy")
                        .font(.headline)
                    Text("Everything on your list is wrapped or given. New ideas you save will show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    if !giftStore.stillToGet.isEmpty {
                        Section(header: Text("Still to get")) {
                            ForEach(giftStore.stillToGet) { item in
                                row(item, showHidingPlace: false)
                            }
                        }
                    }
                    if !giftStore.boughtToWrap.isEmpty {
                        Section(header: Text("Bought — still to wrap")) {
                            ForEach(giftStore.boughtToWrap) { item in
                                row(item, showHidingPlace: true)
                            }
                        }
                    }
                }
                .refreshable { await giftStore.load(session: session) }
            }
        }
    }

    private func row(_ item: GiftWithPerson, showHidingPlace: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.gift.name ?? "")
                    .font(.headline)
                Spacer()
                if item.gift.displayPrice > 0 {
                    Text(GiftListConstants.money(item.gift.displayPrice))
                        .fontWeight(.semibold)
                }
            }
            if !item.personName.isEmpty {
                Text("For \(item.personName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let occasion = item.gift.occasionLabel, !occasion.isEmpty {
                Text(occasion).font(.caption).foregroundStyle(.secondary)
            }
            if showHidingPlace, let hiding = item.gift.hidingPlace, !hiding.isEmpty {
                Label("Hidden in: \(hiding)", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.12, green: 0.44, blue: 0.36))
            }
        }
        .padding(.vertical, 2)
    }
}

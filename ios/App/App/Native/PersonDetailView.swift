import SwiftUI

/// One person's page: their facts, this year's spending, and every
/// gift for them — with the hiding place shown right on the gift,
/// because "where did I hide it?" is the question this app exists
/// to answer. Read-only in this build, like the rest of the native
/// layer.
struct PersonDetailView: View {
    @EnvironmentObject private var giftStore: GiftListStore
    let person: GiftPerson

    private var gifts: [GiftEntry] { giftStore.gifts(for: person) }

    var body: some View {
        List {
            factsSection
            if giftStore.spent(for: person) > 0 || giftStore.yearlyBudget > 0 {
                Section(header: Text("Spending")) {
                    LabeledContent("Spent on \(firstName)", value: GiftListConstants.money(giftStore.spent(for: person)))
                    if giftStore.yearlyBudget > 0 {
                        LabeledContent("Spent on everyone", value: GiftListConstants.money(giftStore.spentTotal))
                        LabeledContent("Yearly budget", value: GiftListConstants.money(giftStore.yearlyBudget))
                    }
                }
            }
            if let occasions = person.occasions, !occasions.isEmpty {
                Section(header: Text("Their days")) {
                    ForEach(occasions) { occasion in
                        HStack {
                            Text(occasion.label ?? "")
                            Spacer()
                            Text(monthDay(occasion))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(header: Text("Gifts")) {
                if gifts.isEmpty {
                    Text("No gifts for \(firstName) yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(gifts) { gift in
                        giftRow(gift)
                    }
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var firstName: String {
        person.displayName.split(separator: " ").first.map(String.init) ?? person.displayName
    }

    @ViewBuilder
    private var factsSection: some View {
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
    }

    private func giftRow(_ gift: GiftEntry) -> some View {
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
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                if let occasion = gift.occasionLabel, !occasion.isEmpty {
                    Text(occasion).font(.caption).foregroundStyle(.secondary)
                }
                if let bought = gift.boughtOn, !bought.isEmpty {
                    Text("Bought \(bought)").font(.caption).foregroundStyle(.secondary)
                }
            }
            // The killer field, always visible when it's there.
            if let hiding = gift.hidingPlace, !hiding.isEmpty {
                Label("Hidden in: \(hiding)", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.12, green: 0.44, blue: 0.36))
            }
            if let idea = gift.idea, !idea.isEmpty, idea != (gift.name ?? "") {
                Text(idea).font(.subheadline).foregroundStyle(.secondary)
            }
            if let tracking = gift.trackingNumber, !tracking.isEmpty {
                Text("Tracking: \(tracking)\(gift.carrier.map { $0.isEmpty ? "" : " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func monthDay(_ occasion: GiftOccasion) -> String {
        guard let month = occasion.month, let day = occasion.day,
              (1...12).contains(month), (1...31).contains(day) else { return "" }
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = 2000
        guard let date = Calendar.current.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

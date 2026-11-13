import SwiftUI

/// The budget view — the web's renderBudget: what's spent this
/// year against the yearly budget, spent by person, spent by
/// occasion, and the two editors the web exposes to customers:
/// the yearly budget (Change yearly budget → Save budget, a
/// number ≥ 0) and a spend limit per occasion label (blank =
/// no limit, saved on change). Spent follows the web's rule:
/// gifts whose status is not "thinking" and not archived.
struct BudgetView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore

    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var limitTexts: [String: String] = [:]

    var body: some View {
        List {
            Section(header: Text("Remaining this year")) {
                let spent = giftStore.spentTotal
                let budget = giftStore.yearlyBudget
                let remaining = budget - spent
                Text(GiftListConstants.money(abs(remaining)) + (remaining < 0 ? " over" : ""))
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(remaining < 0 ? Theme.warn : Theme.brown)
                ProgressView(value: min(100, (spent / max(budget, 1)) * 100), total: 100)
                    .tint(remaining < 0 ? Theme.warn : Theme.orange)
                HStack {
                    Text("Spent \(GiftListConstants.money(spent))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Budget \(GiftListConstants.money(budget))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                if editingBudget {
                    HStack {
                        Text("Yearly budget $").foregroundStyle(.secondary)
                        TextField("0", text: $budgetText)
                            .keyboardType(.decimalPad)
                    }
                    Button("Save budget") {
                        Task { await saveBudget() }
                    }
                    .fontWeight(.semibold)
                } else {
                    Button("Change yearly budget") {
                        budgetText = GiftFormView.priceString(giftStore.yearlyBudget)
                        editingBudget = true
                    }
                }
            }
            Section(header: Text("Spent by person")) {
                let rows = giftStore.spentByPerson()
                if rows.allSatisfy({ $0.total == 0 }) {
                    Text("Nothing bought yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.person.id) { row in
                        HStack {
                            Text(row.person.displayName).fontWeight(.semibold)
                            Spacer()
                            Text(GiftListConstants.money(row.total))
                        }
                    }
                }
            }
            Section(header: Text("Spent by occasion")) {
                let rows = giftStore.spentByOccasion
                if rows.isEmpty {
                    Text("Nothing bought yet. Gifts you save as purchased will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.label) { row in
                        let limit = giftStore.eventLimits[row.label]
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.label.isEmpty ? "Any occasion" : row.label).fontWeight(.semibold)
                                Spacer()
                                Text(GiftListConstants.money(row.total))
                                if let limit {
                                    Text("of \(GiftListConstants.money(limit))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let limit, row.total > limit {
                                Text("Over the limit")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                    }
                }
            }
            Section(header: Text("Spend limit per occasion")) {
                Text("Set how much you'd like to spend on each event. Leave it blank for no limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if giftStore.occasionLabels.isEmpty {
                    Text("No occasion labels yet — add a date to a person first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(giftStore.occasionLabels, id: \.self) { label in
                        HStack {
                            Text("$ \(label)")
                            Spacer()
                            TextField("No limit", text: limitBinding(label))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                    Button("Save limits") {
                        Task { await saveLimits() }
                    }
                    .fontWeight(.semibold)
                }
            }
            if giftStore.saveState == .failed {
                Section {
                    Text("Couldn't save to your account — check your connection and try again.")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Gift budget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            for label in giftStore.occasionLabels where limitTexts[label] == nil {
                if let value = giftStore.eventLimits[label] {
                    limitTexts[label] = GiftFormView.priceString(value)
                } else {
                    limitTexts[label] = ""
                }
            }
        }
    }

    private func limitBinding(_ label: String) -> Binding<String> {
        Binding(
            get: { limitTexts[label] ?? "" },
            set: { limitTexts[label] = $0 })
    }

    private func saveBudget() async {
        guard let value = Double(budgetText), value >= 0 else { return }
        await giftStore.mutate(session: session) { state in
            state["budget"] = value
        }
        if giftStore.saveState != .failed {
            editingBudget = false
        }
    }

    /// The web saves each limit on change: a blank or non-number
    /// clears the limit; a number sets it.
    private func saveLimits() async {
        let edits = limitTexts
        await giftStore.mutate(session: session) { state in
            var limits = GiftStateKit.dict(state["eventLimits"])
            for (label, text) in edits {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || Double(trimmed) == nil {
                    limits.removeValue(forKey: label)
                } else if let value = Double(trimmed) {
                    limits[label] = value
                }
            }
            state["eventLimits"] = limits
        }
    }
}

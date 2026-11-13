import SwiftUI

/// Upcoming occasions — the web's renderUpcoming: every
/// non-archived person's days, rolled to their next occurrence
/// and sorted by days away. The list opens on the reminder
/// window (state.reminderDays ahead; when nothing falls inside
/// it, the next three), with the web's Show all / Show only the
/// next few weeks toggle. Tapping a row opens that person.
struct UpcomingView: View {
    @EnvironmentObject private var giftStore: GiftListStore
    @State private var showAll = false

    var body: some View {
        List {
            Section {
                Text("Reminders start \(giftStore.reminderDays) days ahead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let all = giftStore.upcoming
            if all.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No occasions yet").font(.headline)
                        Text("Add a birthday or anniversary to a person and it will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                let window = all.filter { $0.daysAway <= giftStore.reminderDays }
                let shown = showAll ? all : (window.isEmpty ? Array(all.prefix(3)) : window)
                Section(header: Text(showAll ? "All occasions this year" : "\(giftStore.reminderDays)-day reminder window")) {
                    ForEach(shown) { entry in
                        NavigationLink {
                            PersonDetailView(personID: entry.person.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    Text(monthShort(entry.date))
                                        .font(.caption).fontWeight(.bold)
                                        .foregroundStyle(Theme.brown)
                                    Text("\(Calendar.current.component(.day, from: entry.date))")
                                        .font(.title3).fontWeight(.bold)
                                }
                                .frame(width: 44)
                                .padding(.vertical, 4)
                                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.person.displayName).font(.headline)
                                    Text("\(entry.occasion.label ?? "") · \(longDay(entry.date))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(GiftListStore.daysLabel(entry.daysAway))
                                    .font(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Theme.soft)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                if !showAll && window.count < all.count {
                    Button("Show all \(all.count) occasions") { showAll = true }
                } else if showAll {
                    Button("Show only the next few weeks") { showAll = false }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    private func longDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

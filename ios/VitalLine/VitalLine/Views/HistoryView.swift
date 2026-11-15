import SwiftUI

// History tab: a list of saved responses. Tap one to see its details.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var history

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "No saved responses",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Responses you save after completion appear here.")
                    )
                    .foregroundStyle(.textSecondary)
                    .padding(.top, 60)
                }

                ForEach(history.entries) { entry in
                    NavigationLink(value: entry.id) {
                        HistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .task { await history.refresh() }
        .refreshable { await history.refresh() }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { id in
            if let entry = history.entries.first(where: { $0.id == id }) {
                HistoryDetailView(entry: entry)
            }
        }
        .vitalScreen()
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cross.circle.fill")
                .font(.title2)
                .foregroundStyle(.critical)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.plan.dispatch.complaint)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("\(entry.plan.building.name) · \(placeText(floor: entry.plan.dispatch.floor, unit: entry.plan.dispatch.unit))")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.textSecondary)
        }
        .card()
        .contentShape(Rectangle())
    }
}

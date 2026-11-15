import SwiftUI

// Read-only record of one response: header, route map, timeline,
// and predicted vs actual access time.
struct HistoryDetailView: View {
    let entry: HistoryEntry

    private var dispatch: DispatchInfo { entry.plan.dispatch }

    private var equipmentName: String {
        dispatch.equipment.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var predictedText: String {
        "\(minutesText(entry.plan.time.minSeconds))–\(minutesText(entry.plan.time.maxSeconds)) min"
    }

    private var actualText: String {
        guard let minutes = entry.actualAccessMinutes else { return "—" }
        return String(format: "%.1f min", minutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(dispatch.complaint) · \(entry.plan.building.name) · \(placeText(floor: dispatch.floor, unit: dispatch.unit))")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · Unit \(entry.crewUnit) · \(equipmentName)")
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                }
                .card()

                // Route map (same map as Route Preview), not scrollable here
                RouteMapView(outdoor: entry.plan.outdoor)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)

                // Timeline
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entry.events) { event in
                        TimelineRow(event: event)
                    }

                    Divider().overlay(Color.textSecondary.opacity(0.3))

                    HStack(alignment: .top) {
                        stat("Predicted access", predictedText, color: .textPrimary)
                        Spacer()
                        stat("Actual", actualText, color: .brandPrimary)
                    }
                }
                .card()
            }
            .padding()
        }
        .navigationTitle("Response Details")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.textSecondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
        }
    }
}

private struct TimelineRow: View {
    let event: ResponseEvent

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(Self.timeFormat.string(from: event.date))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.textSecondary)

            if event.isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.caution)
            }

            Text(event.text)
                .foregroundStyle(event.isWarning ? Color.caution : Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import SwiftUI
import MapKit

struct RouteMapView: View {
    let outdoor: Outdoor

    var body: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: outdoor.route.map(\.coordinate))
                .stroke(.brandPrimary, lineWidth: 5)

            Annotation("Staging", coordinate: outdoor.staging.coordinate) {
                Image(systemName: "staroflife.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.critical, in: Circle())
            }

            Marker("Entrance", systemImage: "door.left.hand.open",
                   coordinate: outdoor.entrance.coordinate)
                .tint(.success)
        }
    }
}

struct FlagsList: View {
    let flags: [Flag]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(flags) { flag in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flag.text)
                        Text(flag.source).font(.caption).foregroundStyle(.textSecondary)
                    }
                } icon: {
                    Image(systemName: icon(for: flag.kind)).foregroundStyle(.caution)
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "road_work": return "cone.fill"
        case "weather": return "cloud.bolt.rain.fill"
        case "hazard": return "exclamationmark.triangle.fill"
        default: return "flag.fill"
        }
    }
}

struct AccessNotesView: View {
    let notes: [AccessNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text)
                    HStack(spacing: 6) {
                        Text("Confidence: \(note.confidence)")
                        if note.synthetic {
                            Text("SYNTHETIC")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                }
                .card()
            }
        }
    }
}

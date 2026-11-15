import SwiftUI

// Outside view for the recommended plan: Vexcel aerial imagery of the building with where to
// stop and where the building is. Markers are placed by the backend as fractions of the image.
struct AerialView: View {
    let aerial: Aerial
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .clipped()
                        ForEach(Array(aerial.markers.enumerated()), id: \.offset) { _, marker in
                            pin(marker)
                                .position(x: marker.fx * side, y: marker.fy * side)
                        }
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.surface)
                if failed {
                    Label("Aerial image unavailable", systemImage: "photo").foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Loading aerial view…").tint(.brandPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("AERIAL · VEXCEL")
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(10)
        }
        .task { await load() }
    }

    private func pin(_ marker: AerialMarker) -> some View {
        let isStop = marker.kind == "stop"
        return VStack(spacing: 2) {
            Image(systemName: isStop ? "parkingsign.circle.fill" : "door.left.hand.open")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(6)
                .background(isStop ? Color.critical : Color.success, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(isStop ? "Stop" : "Building")
                .font(.caption2.bold())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func load() async {
        guard image == nil else { return }
        var request = API.authorized(URLRequest(url: API.baseURL.appendingPathComponent(aerial.imageUrl)))
        request.timeoutInterval = 60
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200, let loaded = UIImage(data: data) {
            image = loaded
        } else {
            failed = true
        }
    }
}

// Legend under the aerial image: what each marker means, in the backend's own words.
struct AerialLegend: View {
    let aerial: Aerial

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(aerial.markers.enumerated()), id: \.offset) { _, marker in
                Label {
                    Text(marker.label).font(.footnote).foregroundStyle(.textPrimary)
                } icon: {
                    Image(systemName: marker.kind == "stop" ? "parkingsign.circle.fill" : "door.left.hand.open")
                        .foregroundStyle(marker.kind == "stop" ? .critical : .success)
                }
            }
            Text("\(aerial.note ?? "") Image covers about \(aerial.widthM) m across.")
                .font(.caption).foregroundStyle(.textSecondary)
        }
    }
}

import SwiftUI

// Shows the CoStar/Matterport floor-plan image when the backend sends one,
// and draws the crew path, doors and patient marker on top of it.
// With no image (or if it fails to load) it falls back to drawing the rooms.
//
// Contract with the backend:
//   indoor.floor_plan_image_url  -> full https URL, or a path like "/floorplans/demo-14.png"
//   The image must cover exactly width_m x height_m, origin top-left,
//   so path/door coordinates in meters line up with the picture.
struct FloorPlanCanvas: View {
    let indoor: Indoor
    var showsPath = true        // false = static reference map (Floor Plan tab)
    @State private var imageFailed = false

    private var imageURL: URL? {
        guard let s = indoor.floorPlanImageUrl, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: s, relativeTo: API.baseURL)   // backend-relative path
    }

    private var drawRooms: Bool { imageURL == nil || imageFailed }

    var body: some View {
        ZStack {
            // Layer 1: the real floor plan picture
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure:
                        Color.clear.onAppear { imageFailed = true }
                    default:
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Layer 2: everything we draw on top
            Canvas { context, size in
                let sx = Double(size.width) / indoor.widthM
                let sy = Double(size.height) / indoor.heightM

                func toScreen(_ p: PlanPoint) -> CGPoint {
                    CGPoint(x: p.x * sx, y: p.y * sy)
                }

                if drawRooms {
                    for room in indoor.rooms {
                        guard let first = room.polygon.first else { continue }
                        var shape = Path()
                        shape.move(to: toScreen(first))
                        for p in room.polygon.dropFirst() { shape.addLine(to: toScreen(p)) }
                        shape.closeSubpath()
                        context.fill(shape, with: .color(.gray.opacity(0.10)))
                        context.stroke(shape, with: .color(.gray.opacity(0.6)), lineWidth: 1)

                        let cx = room.polygon.map(\.x).reduce(0, +) / Double(room.polygon.count)
                        let cy = room.polygon.map(\.y).reduce(0, +) / Double(room.polygon.count)
                        context.draw(
                            Text(room.name).font(.caption2).foregroundStyle(.secondary),
                            at: toScreen(PlanPoint(x: cx, y: cy))
                        )
                    }
                }

                if showsPath {
                    // Crew path (dashed when using the stair chair)
                    if let start = indoor.path.first {
                        var route = Path()
                        route.move(to: toScreen(start))
                        for p in indoor.path.dropFirst() { route.addLine(to: toScreen(p)) }
                        let dash: [CGFloat] = indoor.mode == "stair_chair" ? [8, 6] : []
                        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: dash)
                        // dark outline first so the line stays visible on a busy image
                        context.stroke(route, with: .color(.black.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round, dash: dash))
                        context.stroke(route, with: .color(.blue), style: style)
                    }

                    // Doors: green fits the equipment, red does not
                    for door in indoor.doors {
                        let c = toScreen(door.at)
                        let dot = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                        context.fill(Path(ellipseIn: dot), with: .color(door.passable ? .green : .red))
                        context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1.5)
                    }

                    // Patient marker at the end of the path
                    if let end = indoor.path.last {
                        context.draw(Text(Image(systemName: "cross.circle.fill"))
                                        .font(.title2).foregroundStyle(.red),
                                     at: toScreen(end))
                    }
                }
            }
        }
        // Keeps the image and the drawing the same shape as the floor in meters.
        .aspectRatio(indoor.widthM / indoor.heightM, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: indoor.floorPlanImageUrl) { imageFailed = false }
    }
}

import SwiftUI

// Draws rooms, doors and the crew path with SwiftUI Canvas.
// Backend coordinates are meters; we scale them to fit the view.
struct FloorPlanView: View {
    let indoor: Indoor

    var body: some View {
        Canvas { context, size in
            let viewW = Double(size.width), viewH = Double(size.height)
            let scale = min(viewW / indoor.widthM, viewH / indoor.heightM)
            let offsetX = (viewW - indoor.widthM * scale) / 2
            let offsetY = (viewH - indoor.heightM * scale) / 2

            func toScreen(_ p: PlanPoint) -> CGPoint {
                CGPoint(x: offsetX + p.x * scale, y: offsetY + p.y * scale)
            }

            // Rooms
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

            // Crew path (dashed when using the stair chair)
            if let start = indoor.path.first {
                var route = Path()
                route.move(to: toScreen(start))
                for p in indoor.path.dropFirst() { route.addLine(to: toScreen(p)) }
                let dash: [CGFloat] = indoor.mode == "stair_chair" ? [8, 6] : []
                context.stroke(route, with: .color(.blue),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round,
                                                  lineJoin: .round, dash: dash))
            }

            // Doors: green fits the equipment, red does not
            for door in indoor.doors {
                let c = toScreen(door.at)
                let dot = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(door.passable ? .green : .red))
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

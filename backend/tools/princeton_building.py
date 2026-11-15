"""On-site test building (Princeton) from one Matterport scan, for the in-person AR test.

The scan's rooms are mostly unlabelled, so the walkable route is built from the scan
positions themselves: each is a spot where the camera stood. Two positions are linked when
they are close and, on the same level, the straight line between them crosses no wall.
Links with a height change are treated as stairs (the scan shows the levels joined there).

The route runs from a ground-level position to the farthest reachable upper-level position,
so the test covers a walk, the stairs and a second walk. All coordinates are metres.

Ids come from backend/config/demo_building.local.json (gitignored). Cached in data/cache.
"""

from __future__ import annotations

import itertools
import math
from typing import Any

import networkx as nx
from shapely.geometry import LineString

from app.config import demo_config
from connectors import cache, matterport
from geometry import scan_graph
from tools.wolfram import _run

BUILDING_ID = "princeton-live"
MAX_LINK_M = 5.0        # horizontal distance between linked scan positions
MAX_RISE_M = 2.2        # height change allowed on one stair link
SAME_LEVEL_M = 0.3      # below this, two positions are on the same level
FALLBACK_ADDRESS = "Princeton University campus, Princeton, NJ"


def _walls(model: dict) -> list[LineString]:
    out = []
    for f in model["floors"]:
        verts = {v["id"]: (v["position"]["x"], v["position"]["y"]) for v in f["vertices"]}
        for e in f["edges"]:
            ids = [v["id"] for v in e["vertices"]]
            if e["type"] == "wall" and len(ids) == 2 and all(i in verts for i in ids) and not e.get("openings"):
                out.append(LineString([verts[ids[0]], verts[ids[1]]]))
    return out


def _pano_graph(model: dict) -> tuple[nx.Graph, dict[str, tuple[float, float, float]]]:
    pts = {p["id"]: (p["position"]["x"], p["position"]["y"], p["position"]["z"])
           for p in model["panoLocations"] if p.get("position")}
    walls = _walls(model)
    g = nx.Graph()
    for (a, pa), (b, pb) in itertools.combinations(pts.items(), 2):
        run_m, rise = math.dist(pa[:2], pb[:2]), abs(pa[2] - pb[2])
        if run_m > MAX_LINK_M or rise > MAX_RISE_M:
            continue
        if rise > SAME_LEVEL_M and run_m < rise * 0.8:      # steeper than any stair
            continue
        if rise <= SAME_LEVEL_M and any(w.intersects(LineString([pa[:2], pb[:2]])) for w in walls):
            continue
        g.add_edge(a, b, weight=math.hypot(run_m, rise), run=run_m, rise=rise)
    return g, pts


def _route(g: nx.Graph, pts: dict) -> list[str]:
    """Ground-level start to the farthest upper-level position in the largest connected part."""
    part = g.subgraph(max(nx.connected_components(g), key=len))
    zs = {n: pts[n][2] for n in part}
    low, high = min(zs.values()), max(zs.values())
    ground = [n for n in part if zs[n] - low < SAME_LEVEL_M]
    upper = [n for n in part if high - zs[n] < SAME_LEVEL_M] or list(part)
    best = None
    for s in ground:
        dist, paths = nx.single_source_dijkstra(part, s, weight="weight")
        end = max(upper, key=lambda n: dist.get(n, -1))
        if best is None or dist[end] > best[0]:
            best = (dist[end], paths[end])
    return best[1]


async def _build() -> dict[str, Any]:
    ids = demo_config()["princeton"]["matterport"]
    model = await matterport.layout(ids["primary"])
    geo = model.get("geolocation") or (await matterport.layout(ids["other_processing"])).get("geolocation")
    g, pts = _pano_graph(model)
    path = _route(g, pts)
    labels = {p["id"]: p.get("label") for p in model["panoLocations"]}

    sg = scan_graph.build(model)
    z0 = pts[path[0]][2]
    ground_floor = min(sg.floors, key=lambda f: abs((sg.floors[f]["z"] or 99) - z0))
    rooms = [r for r in sg.rooms.values() if r.floor_id == ground_floor and r.polygon is not None]
    xs = [x for r in rooms for x, _ in r.polygon.exterior.coords] + [pts[n][0] for n in path]
    ys = [y for r in rooms for _, y in r.polygon.exterior.coords] + [pts[n][1] for n in path]
    minx, maxy = min(xs), max(ys)

    def tf(x: float, y: float) -> dict:
        return {"x": round(x - minx, 3), "y": round(maxy - y, 3)}

    # Nodes and edges in the planner's building format.
    nodes, edges, climbed = [], [], False
    for i, n in enumerate(path):
        x, y, z = pts[n]
        upper = z - z0 > SAME_LEVEL_M
        nodes.append({"id": f"p{i}", "floor": 2 if upper else 1, "label": f"Scan point {labels.get(n)}",
                      "checkpoint": i == 0, "patient": i == len(path) - 1, **tf(x, y)})
    for i, (a, b) in enumerate(itertools.pairwise(path)):
        e = g.edges[a, b]
        if e["rise"] > SAME_LEVEL_M:
            if edges and edges[-1]["kind"] == "stairs":
                # One flight split by a landing scan point: extend the same stairs edge.
                edges[-1]["to"] = f"p{i + 1}"
                edges[-1]["rise_m"] = round(edges[-1]["rise_m"] + e["rise"], 2)
                continue
            climbed = True
            edges.append({"from": f"p{i}", "to": f"p{i + 1}", "kind": "stairs", "stair": "S1", "floors": 1,
                          "rise_m": round(e["rise"], 2),
                          "instruction": "Stairs up one level ({vertical})"})
        else:
            edges.append({"from": f"p{i}", "to": f"p{i + 1}", "kind": "walk", "distance_m": round(e["run"], 2),
                          "overhead_s": [0, 0],
                          "instruction": ("Upper level: {distance} m along the scanned route to the destination"
                                          if climbed else "Walk {distance} m through the scanned foyer to the stairs")})

    path3d = [{"x": tf(pts[n][0], pts[n][1])["x"], "y": round(pts[n][2] - z0, 3),
               "z": tf(pts[n][0], pts[n][1])["y"]} for n in path]
    heights = sorted(h for h in sg.room_heights if h)
    scan_address = ((model.get("address") or {}).get("address") or "").strip()
    scan_name = (model.get("name") or "").split(" - ")[-1].strip()
    loc = {"lat": float(geo["lat"]), "lon": float(geo["long"])} if geo else None
    return {
        "_note": "Built from a Matterport scan for the event. Do not commit or publish.",
        "id": BUILDING_ID,
        "name": scan_name or "Princeton test building",
        "address": ", ".join(p for p in (scan_name, scan_address.removesuffix(", US") or FALLBACK_ADDRESS) if p),
        "location": loc,
        "timezone": "America/New_York",
        "floors": len(sg.floors),
        "type": f"Campus building, {len(sg.floors)} scanned levels",
        "source": "Matterport scan (Princeton)",
        "parking": [{"id": "p1", "label": "Parking", "detail": "not in the data, on-site test",
                     "clearance_ft": None, "location": None, "near_entrance": "main",
                     "walk_to_entrance_m": 0}],
        "entrances": [{"id": "main", "label": "Start point", "detail": f"scan point {labels.get(path[0])}",
                       "node": "p0", "location": loc}],
        "elevators": [],
        "stairs": [{"id": "S1", "label": "stairs, from scan heights (scanned)"}],
        "nodes": nodes,
        "edges": edges,
        "floor_plan": {"floor": 1, "width_m": round(max(xs) - minx, 2), "height_m": round(maxy - min(ys), 2),
                       "rooms": [{"id": r.id, "name": r.label if r.label not in ("Void", "Unlabelled") else "",
                                  "polygon": [tf(x, y) for x, y in list(r.polygon.exterior.coords)[:-1]]}
                                 for r in rooms],
                       "doors": [], "wall_height_m": round(heights[len(heights) // 2], 2) if heights else None},
        "path3d": path3d,
        "mesh": {"model_id": ids["primary"], "min_x": minx, "max_y": maxy, "ref_z": z0,
                 "rise_m": max(p["y"] for p in path3d)},
        "start_scan_point": labels.get(path[0]),
        "hazards_sample": [],
    }


def build(refresh: bool = False) -> dict[str, Any]:
    key = cache.key_for("princeton_building", 4)
    if not refresh and (hit := cache.get("building", key)) is not None:
        return hit
    return cache.put("building", key, _run(_build()))

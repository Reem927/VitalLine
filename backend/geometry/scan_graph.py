"""Walkable graph from one Matterport scan, plus equipment-aware path search.

Each scan has its own metre frame (x, y on the floor, z up). Rooms come from the wall graph:
a room's boundary is a loop of wall edges. Rooms connect through doorways, open passages and
invisible edges (open plan). Staircase rooms link adjacent floors.

Every door carries a confidence:
  high   measured by the scanner
  medium scanner default 36 x 80 in (not a measurement)
  low    no width at all, code minimum assumed
"""

import itertools
import math
import statistics
from dataclasses import dataclass, field

import networkx as nx
from shapely.geometry import Point, Polygon

from geometry import fit
from rules import equipment as eq

PASSABLE_OPENINGS = ("doorway", "opening", "divider")
UNLABELLED_PENALTY = 3.0  # prefer labelled rooms over "Void" or unlabelled spaces


@dataclass
class Room:
    id: str
    floor_id: str
    label: str
    polygon: Polygon | None
    point: tuple[float, float] | None
    short_side_m: float | None


@dataclass
class Door:
    id: str
    floor_id: str
    kind: str
    label: str | None
    x: float
    y: float
    width_m: float
    height_m: float | None
    measured: bool
    confidence: str
    source: str
    rooms: list[str] = field(default_factory=list)


@dataclass
class ScanGraph:
    model_id: str
    name: str
    floors: dict          # floor_id -> {"label", "sequence", "z"}
    rooms: dict           # room_id -> Room
    doors: dict           # door_id -> Door
    graph: nx.Graph
    room_heights: list = field(default_factory=list)   # scanned ceiling heights, metres


def _label(room: dict) -> str:
    cls = room.get("classifications") or []
    return (cls[0].get("label") if cls else None) or "Unlabelled"


def _polygon(room: dict, verts: dict, edges: dict) -> Polygon | None:
    chain = [edges[e["id"]] for e in ((room.get("boundary") or {}).get("edges") or []) if e["id"] in edges]
    if not chain:
        return None
    loop, rest = list(chain[0]), chain[1:]
    while rest:
        for i, (a, b) in enumerate(rest):
            if loop[-1] in (a, b):
                loop.append(b if a == loop[-1] else a)
                rest.pop(i)
                break
        else:
            break
    pts = [verts[v] for v in loop if v in verts]
    if len(pts) < 3:
        return None
    poly = Polygon(pts)
    if not poly.is_valid:
        poly = poly.buffer(0)
    return poly if poly.area > 0 else None


def _short_side(poly: Polygon | None, dims: dict | None) -> float | None:
    if poly is not None:
        rect = poly.minimum_rotated_rectangle
        xs, ys = rect.exterior.coords.xy
        sides = [math.dist((xs[i], ys[i]), (xs[i + 1], ys[i + 1])) for i in range(2)]
        return min(sides)
    dims = dims or {}
    vals = [v for v in (dims.get("width"), dims.get("depth")) if v]
    return min(vals) if vals else None


def classify_door(opening: dict) -> tuple[float, bool, str, str]:
    """Width to use, whether it was measured, confidence, and source text."""
    w = opening.get("width")
    if opening["type"] != "doorway":
        return w, True, "high", f"Matterport {opening['type']} (measured)"
    if not w:
        return eq.CODE_MIN_DOOR_M, False, "low", eq.CODE_MIN_DOOR_SOURCE
    if abs(w - eq.PLACEHOLDER_DOOR[0]) < 1e-4:
        return w, False, "medium", "Matterport default 36 in width (not measured)"
    return w, True, "high", "Matterport doorway (measured)"


def build(model: dict) -> ScanGraph:
    floors, rooms, doors = {}, {}, {}
    g = nx.Graph()
    edge_rooms: dict[str, list[str]] = {}

    for f in model["floors"]:
        floors[f["id"]] = {"label": f["label"], "sequence": f.get("sequence"), "z": None}
    floor_geo = {}
    for f in model["floors"]:
        verts = {v["id"]: (v["position"]["x"], v["position"]["y"]) for v in f["vertices"]}
        edges = {e["id"]: [v["id"] for v in e["vertices"]] for e in f["edges"]}
        floor_geo[f["id"]] = (verts, edges, f["edges"])

    for r in model["rooms"]:
        fid = (r.get("floor") or {}).get("id")
        if fid not in floor_geo:
            continue
        verts, edges, _ = floor_geo[fid]
        poly = _polygon(r, verts, edges)
        pt = poly.representative_point() if poly is not None else None
        rooms[r["id"]] = Room(r["id"], fid, _label(r), poly, (pt.x, pt.y) if pt else None,
                              _short_side(poly, r.get("dimensions")))
        for e in ((r.get("boundary") or {}).get("edges") or []):
            edge_rooms.setdefault(e["id"], []).append(r["id"])

    # Floor heights from scan points: the median scanner height of points inside each floor's rooms.
    for fid, info in floors.items():
        zs = [p["position"]["z"] for p in model.get("panoLocations") or [] if p.get("position")
              and any(rm.floor_id == fid and rm.polygon is not None
                      and rm.polygon.contains(Point(p["position"]["x"], p["position"]["y"]))
                      for rm in rooms.values())]
        info["z"] = statistics.median(zs) if zs else None

    for rid, rm in rooms.items():
        if rm.point:
            g.add_node(f"room:{rid}", kind="room", ref=rid, floor=rm.floor_id, xy=rm.point)

    for fid, (verts, edges, raw_edges) in floor_geo.items():
        for e in raw_edges:
            ids = edges[e["id"]]
            if len(ids) != 2 or ids[0] not in verts or ids[1] not in verts:
                continue
            (x1, y1), (x2, y2) = verts[ids[0]], verts[ids[1]]
            adjacent = [r for r in edge_rooms.get(e["id"], []) if f"room:{r}" in g]
            passages = [o for o in e.get("openings") or [] if o["type"] in PASSABLE_OPENINGS]
            if e["type"] == "invisible" and len(adjacent) == 2:
                passages = [{"id": f"{e['id']}-open", "type": "opening", "label": "open plan",
                             "width": math.dist((x1, y1), (x2, y2)), "height": None, "relativeCenter": 0.5}]
            for o in passages:
                t = o.get("relativeCenter") if o.get("relativeCenter") is not None else 0.5
                x, y = x1 + t * (x2 - x1), y1 + t * (y2 - y1)
                width, measured, conf, source = classify_door(o)
                did = o.get("id") or f"{e['id']}-{t:.3f}"
                d = Door(did, fid, o["type"], o.get("label"), x, y, width, o.get("height"),
                         measured, conf, source, adjacent)
                doors[did] = d
                g.add_node(f"door:{did}", kind="door", ref=did, floor=fid, xy=(x, y))
                for rid in adjacent:
                    rx, ry = rooms[rid].point
                    w = math.dist((x, y), (rx, ry))
                    if rooms[rid].label in ("Void", "Unlabelled"):
                        w *= UNLABELLED_PENALTY
                    g.add_edge(f"door:{did}", f"room:{rid}", weight=w, length=math.dist((x, y), (rx, ry)), kind="walk")

    # Stairs: link each staircase room to the overlapping room on the neighbouring floor.
    order = sorted(floors, key=lambda k: (floors[k]["sequence"] is None, floors[k]["sequence"] or 0, floors[k]["label"]))
    for i, fid in enumerate(order):
        for rm in [r for r in rooms.values() if r.floor_id == fid and r.label == "Staircase" and r.polygon is not None]:
            for other_fid in order[max(0, i - 1):i + 2]:
                if other_fid == fid:
                    continue
                best = max((r for r in rooms.values() if r.floor_id == other_fid and r.polygon is not None),
                           key=lambda r: r.polygon.intersection(rm.polygon.buffer(1.0)).area, default=None)
                if best is None or best.polygon.intersection(rm.polygon.buffer(1.0)).area == 0:
                    continue
                za, zb = floors[fid]["z"], floors[other_fid]["z"]
                rise = abs(za - zb) if za is not None and zb is not None else None
                run = math.dist(rm.point, best.point)
                length = math.hypot(run, rise) if rise is not None else run
                g.add_edge(f"room:{rm.id}", f"room:{best.id}", weight=length, length=length, kind="stairs", rise_m=rise)

    heights = [((r.get("dimensions") or {}).get("height")) for r in model["rooms"]]
    return ScanGraph(model["id"], model.get("name", ""), floors, rooms, doors, g,
                     [h for h in heights if h])


def rooms_labelled(sg: ScanGraph, label: str) -> list[str]:
    return [r.id for r in sg.rooms.values() if r.label == label and f"room:{r.id}" in sg.graph]


def door_checks(sg: ScanGraph, door: Door, equip: dict) -> dict:
    """Width and turn checks for one door with one piece of equipment."""
    if equip["width_m"] is None:
        return {"door_id": door.id, "status": "unknown", "reason": "equipment size unknown"}
    width = fit.door_fit(door.width_m, equip["width_m"])
    turns = []
    for rid in door.rooms:
        b = sg.rooms[rid].short_side_m
        if b is None:
            turns.append({"room": rid, "status": "unknown", "reason": "room width unknown"})
            continue
        c = fit.corner_fit(door.width_m, b, equip["width_m"], equip["length_m"])
        turns.append({"room": rid, "room_label": sg.rooms[rid].label, "room_short_side_m": b,
                      "status": "pass" if c["passes"] else "fail", **c})
    ok = width["passes"] and all(t["status"] != "fail" for t in turns)
    return {"door_id": door.id, "status": "pass" if ok else "fail", "width_m": door.width_m,
            "confidence": door.confidence, "source": door.source, "width_check": width, "turns": turns}


def find_path(sg: ScanGraph, start_room: str, end_room: str, equipment_name: str) -> dict:
    """Shortest walkable path for the equipment, or why there is none."""
    equip = eq.get(equipment_name)
    g = sg.graph.copy()
    blocked = []
    for did, door in sg.doors.items():
        chk = door_checks(sg, door, equip)
        g.nodes[f"door:{did}"]["check"] = chk
        if chk["status"] == "fail":
            blocked.append(chk)
            g.remove_node(f"door:{did}")
    if not equip["stairs_ok"]:
        g.remove_edges_from([(u, v) for u, v, d in g.edges(data=True) if d.get("kind") == "stairs"])
    try:
        nodes = nx.shortest_path(g, f"room:{start_room}", f"room:{end_room}", weight="weight")
    except (nx.NetworkXNoPath, nx.NodeNotFound):
        return {"found": False, "equipment": equipment_name, "blocked_doors": blocked,
                "reason": "No path that fits this equipment"}

    waypoints, segments, doors_used = [], [], []
    for n in nodes:
        data = g.nodes[n]
        floor = sg.floors[data["floor"]]
        waypoints.append({"x": data["xy"][0], "y": data["xy"][1], "z": floor["z"],
                          "floor_label": floor["label"], "kind": data["kind"], "ref": data["ref"],
                          "label": sg.rooms[data["ref"]].label if data["kind"] == "room" else sg.doors[data["ref"]].kind})
        if data["kind"] == "door":
            doors_used.append(data["check"])
    for u, v in itertools.pairwise(nodes):
        e = g.edges[u, v]
        segments.append({"kind": e["kind"], "length_m": e["length"], "rise_m": e.get("rise_m")})
    return {
        "found": True,
        "equipment": equipment_name,
        "equipment_source": equip["source"],
        "waypoints": waypoints,
        "segments": segments,
        "distance_m": sum(s["length_m"] for s in segments),
        "uses_stairs": any(s["kind"] == "stairs" for s in segments),
        "doors": doors_used,
        "blocked_doors": blocked,
        "z_note": "z is scanner height on each floor, from Matterport scan points",
    }

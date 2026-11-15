"""The demo building from real data, in the same format as data/synthetic/demo_tower.json.

Sources, leg by leg:
- Building facts (floors, type, elevator exists, parking exists): CoStar kit.
- Entrance to the stairs and elevator core: Matterport concierge scan, walk distance from the
  scanned Entrance room to the scanned Staircase room.
- Elevator: CoStar says a passenger elevator exists; its car size is not in any source, so the
  code minimum car is assumed and labelled. It is assumed to sit at the scanned staircase.
- Corridor from the core to the unit door: not scanned. Bounded by the distance between the two
  scans' recorded positions (straight line) and the rectilinear upper bound (x sqrt 2).
- Inside the unit: Matterport unit scan. The path, rooms and doors come from the scan graph,
  and the equipment that fits its doors and turns is checked there.

Ids and the address come from backend/config/demo_building.local.json (gitignored). The built
building is cached under data/cache (gitignored, deleted after the event).
"""

from __future__ import annotations

import asyncio
import math
from typing import Any

from app.config import demo_config
from connectors import cache, costar_kit, matterport
from geometry import scan_graph
from rules.equipment import CODE_MIN_CAR_IN, EQUIPMENT, INCH_M
from tools.wolfram import _run

BUILDING_ID = "houston-dunlavy"
PATIENT_ROOM = "Bedroom"


def _geodesic_m(a: dict, b: dict) -> float:
    la1, lo1, la2, lo2 = map(math.radians, (float(a["lat"]), float(a["long"]), float(b["lat"]), float(b["long"])))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def _best_path(sg, start_label: str, end_label: str, equipment: str) -> dict | None:
    best = None
    for s in scan_graph.rooms_labelled(sg, start_label):
        for e in scan_graph.rooms_labelled(sg, end_label):
            p = scan_graph.find_path(sg, s, e, equipment)
            if p["found"] and (best is None or p["distance_m"] < best["distance_m"]):
                best = p
    return best


def _floor_plan(sg, path: dict, floor: int) -> tuple[dict, list[dict]]:
    """Unit floor plan in app coordinates: origin top-left, y grows downward, metres."""
    polys = [r for r in sg.rooms.values() if r.polygon is not None and r.label != "Void"]
    xs = [x for r in polys for x, _ in r.polygon.exterior.coords]
    ys = [y for r in polys for _, y in r.polygon.exterior.coords]
    minx, maxy = min(xs), max(ys)

    def tf(x: float, y: float) -> dict:
        return {"x": round(x - minx, 3), "y": round(maxy - y, 3)}

    rooms = [{"id": r.id, "name": r.label, "polygon": [tf(x, y) for x, y in list(r.polygon.exterior.coords)[:-1]]}
             for r in polys]
    doors = [{"id": d.id, "at": tf(d.x, d.y), "width_in": round(d.width_m / INCH_M, 1), "kind": "door",
              "confidence": d.confidence, "measured": d.measured, "source": d.source}
             for d in sg.doors.values() if d.floor_id in {r.floor_id for r in polys}]
    heights = sorted(h for h in (sg.room_heights or []) if h)
    fp = {"floor": floor, "width_m": round(max(xs) - minx, 2), "height_m": round(maxy - min(ys), 2),
          "rooms": rooms, "doors": doors,
          "wall_height_m": round(heights[len(heights) // 2], 2) if heights else None}
    points = [tf(w["x"], w["y"]) for w in path["waypoints"]]
    return fp, points


async def _build() -> dict[str, Any]:
    cfg = demo_config()["primary"]
    ids = cfg["matterport"]
    floor = int(cfg["patient_floor"])
    unit = str(cfg["patient_unit"])

    concierge = await matterport.layout(ids["concierge_entrance_stairs"])
    unit_scan = await matterport.layout(ids["unit_203"])
    pid = await asyncio.to_thread(costar_kit.property_id_for_model, ids["unit_203"])
    facts = await asyncio.to_thread(costar_kit.property_summary, pid) if pid else None

    sg_c, sg_u = scan_graph.build(concierge), scan_graph.build(unit_scan)
    entry_path = _best_path(sg_c, "Entrance", "Staircase", "stair_chair")
    unit_paths = {k: _best_path(sg_u, "Entrance", PATIENT_ROOM, k) for k in EQUIPMENT}
    unit_ok = [k for k, p in unit_paths.items() if p]
    unit_path = unit_paths.get("stretcher") or unit_paths.get("stair_chair")
    if entry_path is None or unit_path is None:
        raise RuntimeError("Scans do not give a usable entrance or unit path")

    straight = _geodesic_m(concierge["geolocation"], unit_scan["geolocation"])
    corridor_upper = straight * math.sqrt(2)

    fp, unit_points = _floor_plan(sg_u, unit_path, floor)
    unit_doors = list(unit_path["doors"])
    measured = sum(1 for d in unit_doors if d.get("confidence") == "high")

    nodes = [
        {"id": "entry", "floor": 1, "label": "Main entrance (scanned)", "checkpoint": True},
        {"id": "core_1", "floor": 1, "label": "Stairs and elevator core (scanned staircase)"},
        {"id": f"elev_{floor}", "floor": floor, "label": f"Floor {floor} elevator landing"},
        {"id": f"stairs_{floor}", "floor": floor, "label": f"Floor {floor} stair landing"},
        {"id": "unit_door", "floor": floor, "label": f"Unit {unit} door", "checkpoint": True,
         **unit_points[0]},
    ]
    edges = [
        {"from": "entry", "to": "core_1", "kind": "walk", "distance_m": round(entry_path["distance_m"], 2),
         "overhead_s": [0, 0], "instruction": "Enter at the {entrance}; {distance} m to the stairs and elevator (scanned)",
         "source": "Matterport concierge scan"},
        {"from": "core_1", "to": f"elev_{floor}", "kind": "elevator", "elevator": "E1", "floors": floor - 1,
         "instruction": "Elevator to floor {floor} ({vertical})"},
        {"from": "core_1", "to": f"stairs_{floor}", "kind": "stairs", "stair": "S1", "floors": floor - 1,
         "instruction": "Stairs to floor {floor} ({vertical})"},
    ]
    for landing in (f"elev_{floor}", f"stairs_{floor}"):
        edges.append({"from": landing, "to": "unit_door", "kind": "walk", "distance_m": round(corridor_upper, 2),
                      "overhead_s": [0, 0],
                      "instruction": "Corridor to unit {unit}: not scanned, up to {distance} m (estimated from scan positions)",
                      "source": f"Estimate: {straight:.1f} m between scan positions x sqrt(2) for rectilinear corridors"})
    prev = "unit_door"
    for i, (pt, seg) in enumerate(zip(unit_points[1:], unit_path["segments"], strict=True), start=1):
        nid = "patient" if i == len(unit_path["segments"]) else f"unit_{i}"
        nodes.append({"id": nid, "floor": floor, "label": f"Unit {unit}" if nid == "patient" else "Unit path point",
                      "patient": nid == "patient", **pt})
        edges.append({"from": prev, "to": nid, "kind": "walk", "distance_m": round(seg["length_m"], 3),
                      "overhead_s": [0, 0], "equipment_ok": unit_ok,
                      "instruction": ("Inside unit {unit}: {distance} m to the bedroom through "
                                      f"{len(unit_doors)} doors ({measured} measured)"
                                      + ("" if "stretcher" in unit_ok else
                                         "; stretcher cannot make the turns, use the stair chair")),
                      "source": "Matterport unit scan"})
        prev = nid

    fp["doors"] = [{**d, "kind": "door"} for d in fp["doors"]]
    loc = concierge["geolocation"]
    stories = (facts or {}).get("stories")
    return {
        "_note": "Built from CoStar and Matterport data for the event. Do not commit or publish.",
        "id": BUILDING_ID,
        "name": f"{(facts or {}).get('property_type', 'Unknown')} building",
        "address": cfg["address"],
        "location": {"lat": float(loc["lat"]), "lon": float(loc["long"])},
        "timezone": "America/Chicago",
        "floors": stories,
        "type": f"{(facts or {}).get('property_type', 'Unknown')}, {stories} stories",
        "source": "CoStar + Matterport",
        "parking": [{"id": "p1", "label": "On-site parking", "detail": "per CoStar, exact spot unknown",
                     "clearance_ft": None, "location": None, "near_entrance": "main",
                     "walk_to_entrance_m": 0, "synthetic": False}],
        "entrances": [{"id": "main", "label": "Main entrance", "detail": "concierge, scanned",
                       "node": "entry", "location": {"lat": float(loc["lat"]), "lon": float(loc["long"])}}],
        "elevators": [{"id": "E1", "label": "Elevator (car size assumed: code minimum)",
                       "car_depth_in": CODE_MIN_CAR_IN[0], "car_width_in": CODE_MIN_CAR_IN[1],
                       "in_service": True, "source": "CoStar: passenger elevator exists; size assumed"}],
        "stairs": [{"id": "S1", "label": "stair core"}],
        "nodes": nodes,
        "edges": edges,
        "floor_plan": fp,
        "hazards_sample": [],
        "facts": {"costar": facts, "unit_equipment_ok": unit_ok, "corridor_straight_m": straight,
                  "corridor_upper_m": corridor_upper},
    }


def build(refresh: bool = False) -> dict[str, Any]:
    key = cache.key_for("real_building", BUILDING_ID, 5)
    if not refresh and (hit := cache.get("building", key)) is not None:
        return hit
    return cache.put("building", key, _run(_build()))

"""Geometry tests on a synthetic five-room floor. No sponsor data.

Layout (metres), rooms are 4 x 4:
    D (4..8, 4..8)   E (8..12, 4..8)
    A (0..4, 0..4)   B (4..8, 0..4)   C (8..12, 0..4)
Doors: A-B 1.0 m, B-C 0.5 m (too narrow for the stretcher), B-D, D-E, E-C 1.0 m.
"""

import math

import pytest

from geometry import fit, scan_graph

V = {"v00": (0, 0), "v40": (4, 0), "v80": (8, 0), "v120": (12, 0), "v04": (0, 4), "v44": (4, 4),
     "v84": (8, 4), "v124": (12, 4), "v48": (4, 8), "v88": (8, 8), "v128": (12, 8)}
E = {"a1": ("v00", "v40"), "ab": ("v40", "v44"), "a3": ("v44", "v04"), "a4": ("v04", "v00"),
     "b1": ("v40", "v80"), "bc": ("v80", "v84"), "bd": ("v84", "v44"),
     "c1": ("v80", "v120"), "c2": ("v120", "v124"), "ce": ("v124", "v84"),
     "de": ("v84", "v88"), "d3": ("v88", "v48"), "d4": ("v48", "v44"),
     "e2": ("v124", "v128"), "e3": ("v128", "v88")}
DOORS = {"ab": 1.0, "bc": 0.5, "bd": 1.0, "de": 1.0, "ce": 1.0}
ROOMS = {"A": ["a1", "ab", "a3", "a4"], "B": ["b1", "bc", "bd", "ab"], "C": ["c1", "c2", "ce", "bc"],
         "D": ["bd", "de", "d3", "d4"], "E": ["ce", "e2", "e3", "de"]}


def synthetic_model():
    edges = []
    for eid, (a, b) in E.items():
        openings = []
        if eid in DOORS:
            openings = [{"id": f"door-{eid}", "type": "doorway", "label": "door-pivot", "width": DOORS[eid],
                         "height": 2.1, "relativeCenter": 0.5}]
        edges.append({"id": eid, "type": "wall", "thickness": 0.15, "vertices": [{"id": a}, {"id": b}],
                      "openings": openings})
    floor = {"id": "f1", "label": "Floor 1", "sequence": 0,
             "vertices": [{"id": k, "position": {"x": x, "y": y}} for k, (x, y) in V.items()], "edges": edges}
    rooms = [{"id": r, "floor": {"id": "f1"}, "classifications": [{"label": "Hallway" if r == "B" else "Bedroom"}],
              "boundary": {"edges": [{"id": e} for e in es]}, "dimensions": None} for r, es in ROOMS.items()]
    panos = [{"id": "p1", "position": {"x": 2, "y": 2, "z": 1.4}}]
    return {"id": "synthetic", "name": "Synthetic", "floors": [floor], "rooms": rooms, "panoLocations": panos}


def test_ladder_around_corner_matches_closed_form():
    # Zero-width ladder between two 1 m corridors: (1^(2/3) + 1^(2/3))^(3/2) = 2^(3/2).
    assert fit.max_length_around_corner(1.0, 1.0, 0.0) == pytest.approx(2 ** 1.5, rel=1e-4)


def test_stretcher_cannot_turn_into_a_narrow_hallway():
    stretcher_w, stretcher_l = 24 * 0.0254, 84 * 0.0254
    assert not fit.corner_fit(0.9, 0.9, stretcher_w, stretcher_l)["passes"]
    assert fit.corner_fit(1.5, 4.0, stretcher_w, stretcher_l)["passes"]


def test_door_classification():
    assert scan_graph.classify_door({"type": "doorway", "width": 0.9144, "height": 2.032})[2] == "medium"
    assert scan_graph.classify_door({"type": "doorway", "width": 0.751, "height": 2.1})[2] == "high"
    width, measured, conf, _ = scan_graph.classify_door({"type": "doorway", "width": None, "height": None})
    assert (round(width, 4), measured, conf) == (0.8128, False, "low")


def test_stretcher_path_detours_around_narrow_door():
    sg = scan_graph.build(synthetic_model())
    path = scan_graph.find_path(sg, "A", "C", "stretcher")
    assert path["found"]
    rooms = [w["ref"] for w in path["waypoints"] if w["kind"] == "room"]
    assert rooms == ["A", "B", "D", "E", "C"]
    assert any(b["door_id"] == "door-bc" for b in path["blocked_doors"])
    assert math.isclose(path["waypoints"][0]["z"], 1.4)


def test_no_path_reports_why():
    model = synthetic_model()
    for e in model["floors"][0]["edges"]:
        if e["id"] in ("ab",):
            e["openings"][0]["width"] = 0.4
    path = scan_graph.find_path(scan_graph.build(model), "A", "C", "stretcher")
    assert not path["found"] and path["reason"]

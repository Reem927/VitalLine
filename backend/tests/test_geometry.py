from geometry.fit import fits_in_car
from geometry.indoor_graph import BuildingGraph
from rules.equipment import STAIR_CHAIR, STRETCHER
from tools.building import load_building


def graph():
    return BuildingGraph(load_building())


def test_stretcher_fits_elevator_2_not_elevator_1():
    assert fits_in_car(STRETCHER, 80, 54).fits
    assert not fits_in_car(STRETCHER, 60, 51).fits
    assert fits_in_car(STAIR_CHAIR, 60, 51).fits


def test_default_route_matches_demo():
    r = graph().best_route()
    assert r.entrance_id == "east"
    assert r.equipment is STRETCHER
    assert r.vertical == "Elevator 2"
    assert r.total_minutes == (2.6, 3.8)
    assert [s.text for s in r.steps] == [
        "Stage at the east entrance; take the lobby door",
        "Lobby to Elevator 2 (stretcher fits: 80 x 54 in car)",
        "Ride to floor 14",
        "Corridor east 35 m to unit 1404",
    ]
    assert [s.label for s in r.steps][2:] == ["60–100 s", "46–48 s"]


def test_elevator_2_out_uses_elevator_1_with_stair_chair():
    r = graph().best_route({"E2"})
    assert r.vertical == "Elevator 1"
    assert r.equipment is STAIR_CHAIR


def test_all_elevators_out_uses_stairs():
    r = graph().best_route({"E1", "E2"})
    assert r.vertical_kind == "stairs"
    assert r.equipment is STAIR_CHAIR
    lo, hi = r.total_minutes
    assert 5 < lo < hi < 9


def test_step_sums_equal_total():
    r = graph().best_route()
    lo, hi = r.total_seconds
    assert abs(lo - sum(s.seconds[0] for s in r.steps)) < 1e-9
    assert abs(hi - sum(s.seconds[1] for s in r.steps)) < 1e-9

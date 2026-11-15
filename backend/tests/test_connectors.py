"""Offline tests for connector helpers. Synthetic inputs only, no sponsor data."""

from connectors import costar_kit, valhalla, wolfram


def test_polyline6_decodes_known_points():
    # Two points encoded at 6-digit precision: (38.5, -120.2) then (40.7, -120.95).
    encoded = "_izlhA~rlgdF_{geC~ywl@"
    points = valhalla._decode_polyline6(encoded)
    assert points[0] == {"lat": 38.5, "lon": -120.2}
    assert points[1] == {"lat": 40.7, "lon": -120.95}


def test_wolfram_number_parses_outputs():
    assert wolfram.number("Out[1]= 92.") == 92.0
    assert wolfram.number("Out[1]= 1.5*^-3") == 0.0015
    assert wolfram.number("Out[1]= True") is None
    noisy = "NMinimize::unproc: Could not process x = 3.\nGeneral::messages: note.\n\nOut[1]= 1.6749"
    assert wolfram.number(noisy) == 1.6749


def test_costar_summary_reads_nested_elevators_and_keeps_unknowns():
    record = {
        "id": 1, "propertyType": 11, "numStoriesAboveGrade": 4,
        "propertyApartment": {"elevators": [
            {"elevatorType": 1, "numElevators": None, "elevatorState": 1},
            {"elevatorType": 3, "numElevators": None, "elevatorState": 2},
        ], "isWalkup": False},
        "primaryAddress": {"latitude": 1.0, "longitude": 2.0, "city": "Testville"},
    }
    s = costar_kit.summarize(record)
    assert s["property_type"] == "Multifamily"
    assert s["stories"] == 4
    assert s["elevators"] == [{"type": "passenger", "count": None}]
    assert s["height_ft"] is None

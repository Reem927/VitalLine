from fractions import Fraction

import pytest

from tools import wolfram
from tools.geocode import geocode
from tools.valhalla import decode_polyline6, drive_route


def test_exact_arithmetic():
    assert wolfram.exact("12/0.76+15") == Fraction(12) / Fraction("0.76") + 15
    with pytest.raises(ValueError):
        wolfram.exact("__import__('os')")


def test_verify_flags_mismatch():
    ok = wolfram.verify([{"name": "a", "expr": "1+2", "claimed": 3}])
    bad = wolfram.verify([{"name": "a", "expr": "1+2", "claimed": 4}])
    assert ok["verified"] and not bad["verified"]
    assert ok["verified_by"] == "local_exact_arithmetic"


def test_polyline6_decode():
    # Two points: (38.5, -120.2), (40.7, -120.95) encoded with precision 6.
    assert decode_polyline6("_izlhA~rlgdF_{geC~ywl@") == [[38.5, -120.2], [40.7, -120.95]]


def test_offline_fallbacks_are_labelled():
    g = geocode("1200 Demo St, Houston, TX", fallback={"lat": 1.0, "lon": 2.0})
    assert g["source"] == "building_fixture" and "census.gov" in g["request_url"]
    assert geocode("nowhere")["source"] == "unknown"
    r = drive_route({"lat": 29.75, "lon": -95.37}, {"lat": 29.76, "lon": -95.36})
    assert r["source"] == "straight_line_estimate" and r["confidence"] == "low"

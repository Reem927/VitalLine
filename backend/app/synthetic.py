"""Synthetic dispatches. Our endpoint plays the role of the dispatch (CAD) system."""

from __future__ import annotations

from typing import Any

from tools.building import load_building
from tools.geocode import geocode

_HOUSTON = {"building_id": "demo-tower", "incident_type": "Cardiac arrest",
            "floor": 14, "unit": "1404", "priority": "High"}

# scenario_id -> call details. "houston-cardiac-14" is the id the app sends today.
SCENARIOS: dict[str, dict[str, Any]] = {
    "houston-demo": _HOUSTON,
    "houston-cardiac-14": _HOUSTON,
}


def make_dispatch(scenario_id: str, crew_location: dict[str, float] | None) -> dict[str, Any]:
    sc = SCENARIOS[scenario_id]
    building = load_building(sc["building_id"])
    geo = geocode(building["address"], fallback=building["location"])
    return {
        "incident_type": sc["incident_type"],
        "address": building["address"],
        "floor": sc["floor"],
        "unit": sc["unit"],
        "building_id": building["id"],
        "location": {"lat": geo["lat"], "lon": geo["lon"]},
        "geocode": geo,
        "rig_location": crew_location,
        "responder": "M-12",
        "source": {"kind": "synthetic", "scenario_id": scenario_id},
        "synthetic": True,
    }

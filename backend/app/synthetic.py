"""Synthetic dispatches. Our endpoint plays the role of the dispatch (CAD) system."""

from __future__ import annotations

from typing import Any

from tools.building import load_building
from tools.geocode import geocode

_TOWER = {"building_id": "demo-tower", "incident_type": "Cardiac arrest",
          "floor": 14, "unit": "1404", "priority": "High"}


def _real() -> dict[str, Any]:
    """The real demo building. Floor and unit come from the gitignored local config."""
    from app.config import demo_config
    cfg = demo_config()["primary"]
    return {"building_id": "houston-dunlavy", "incident_type": "Cardiac arrest",
            "floor": int(cfg["patient_floor"]), "unit": str(cfg["patient_unit"]), "priority": "High"}


def _scenario(scenario_id: str) -> dict[str, Any]:
    # "houston-cardiac-14" is the id the app sends today; it now means the real building.
    # Offline (tests, no network) always uses the synthetic tower.
    from app.settings import get_settings
    if scenario_id in ("houston-demo", "houston-cardiac-14"):
        return _TOWER if get_settings().offline else _real()
    if scenario_id == "synthetic-tower":
        return _TOWER
    raise KeyError(scenario_id)


SCENARIOS = ("houston-demo", "houston-cardiac-14", "synthetic-tower")


def make_dispatch(scenario_id: str, crew_location: dict[str, float] | None) -> dict[str, Any]:
    sc = _scenario(scenario_id)
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

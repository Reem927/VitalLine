"""Building data: the real demo building (CoStar + Matterport) or the synthetic fixture."""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from app.settings import get_settings


@lru_cache
def load_building(building_id: str = "demo-tower") -> dict[str, Any]:
    if building_id == "houston-dunlavy":
        from tools import real_building
        return real_building.build()
    data = json.loads(get_settings().building_fixture.read_text())
    if data["id"] != building_id:
        raise KeyError(f"unknown building {building_id}")
    return data


def find_building_for_address(address: str) -> dict[str, Any] | None:
    """Match an address to a known building. Only the demo tower exists for now."""
    b = load_building()
    norm = lambda s: " ".join(s.lower().replace(",", " ").split())
    return b if norm(b["address"]).split(" tx")[0] in norm(address) else None


def nearby_hazards(building: dict[str, Any]) -> list[dict[str, Any]]:
    """Hazards near the destination: sample road flags (labelled) plus live NWS weather alerts."""
    flags = [{**h, "sample": True} for h in building.get("hazards_sample", [])]
    if building.get("source", "").startswith("CoStar") and not get_settings().offline:
        from connectors import nws
        from tools.wolfram import _run
        try:
            alerts = _run(nws.alerts(building["location"]["lat"], building["location"]["lon"]))
        except Exception:  # noqa: BLE001 - weather is optional context, never blocks a plan
            alerts = []
        flags += [{"kind": "weather", "title": a["headline"] or a["event"], "source": a["source"],
                   "location": building["location"]} for a in alerts]
    return flags

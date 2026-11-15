"""Building data. Today: the synthetic fixture. Later: CoStar / Matterport / Vexcel connectors."""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from app.settings import get_settings


@lru_cache
def load_building(building_id: str = "demo-tower") -> dict[str, Any]:
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
    """Road hazards near the destination.

    Sample data labelled with its intended public source (TxDOT DriveTexas, Houston 311).
    Swap for live connectors when keys and endpoints are confirmed.
    """
    return [{**h, "sample": True} for h in building.get("hazards_sample", [])]

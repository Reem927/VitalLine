"""Aerial view of the building from Vexcel, with where to stop and where the building is.

Two markers, both stated for what they are:
- "Stop here": the last point of the drive route, which is the nearest road point to the
  building. It is the place to pull up, not a surveyed parking bay.
- "Building / entrance area": the position recorded with the scan. The exact door is not in
  the data, so it is labelled approximate.

The image is cached under data/cache/aerial (gitignored, deleted after the event). Outside
Vexcel's coverage, or with no key, there is simply no aerial view.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import httpx

from app.config import cache_dir, env
from app.settings import get_settings

ORTHO_URL = "https://api.vexcelgroup.com/v2/ortho/extract"
M_PER_DEG = 111_320
PIXELS = 1000


def _dir() -> Path:
    return cache_dir("aerial")


def image_path(building_id: str) -> Path:
    return _dir() / f"{building_id}.jpg"


def _distance_m(a: dict, b: dict) -> float:
    dlat = (a["lat"] - b["lat"]) * M_PER_DEG
    dlon = (a["lon"] - b["lon"]) * M_PER_DEG * math.cos(math.radians(a["lat"]))
    return math.hypot(dlat, dlon)


def view(building: dict[str, Any], stop: dict[str, float] | None) -> dict[str, Any] | None:
    """Aerial view description for the plan, or None when it is not available."""
    site = building.get("location")
    key = env("VEXCEL_API_KEY")
    if not site or not key or get_settings().offline:
        return None
    bid = building["id"]
    meta_path = _dir() / f"{bid}.json"
    stop = stop or site
    center = {"lat": (site["lat"] + stop["lat"]) / 2, "lon": (site["lon"] + stop["lon"]) / 2}
    half = max(70.0, _distance_m(site, stop) * 0.75 + 35.0)
    dlat = half / M_PER_DEG
    dlon = half / (M_PER_DEG * math.cos(math.radians(center["lat"])))
    west, east = center["lon"] - dlon, center["lon"] + dlon
    south, north = center["lat"] - dlat, center["lat"] + dlat

    cached = json.loads(meta_path.read_text()) if meta_path.exists() else None
    if not (cached and cached.get("bounds") == [west, south, east, north] and image_path(bid).exists()):
        wkt = f"POLYGON(({west} {south},{east} {south},{east} {north},{west} {north},{west} {south}))"
        try:
            resp = httpx.post(ORTHO_URL, headers={"X-API-KEY": key}, timeout=120, json={
                "wkt": wkt, "srid": 4326, "layer": "urban,urban-r,wide-area,urban-g",
                "crop": "bounding_box", "image-format": "jpeg",
                "destination-dimensions": f"{PIXELS},{PIXELS}", "attribution": "false"})
        except httpx.HTTPError:
            return None
        if resp.status_code != 200 or not resp.headers.get("content-type", "").startswith("image"):
            return None
        image_path(bid).write_bytes(resp.content)
        meta_path.write_text(json.dumps({"bounds": [west, south, east, north]}))

    def frac(p: dict) -> dict:
        return {"fx": round((p["lon"] - west) / (east - west), 4),
                "fy": round((north - p["lat"]) / (north - south), 4)}

    markers = [{"kind": "building", "label": "Building / entrance area (scan position, approximate)", **frac(site)}]
    if _distance_m(site, stop) > 3:
        markers.append({"kind": "stop", "label": "Stop here: nearest road point on the route", **frac(stop)})
    return {"image_url": f"/aerial/{bid}/image", "width_m": round(2 * half), "markers": markers,
            "source": "Vexcel aerial imagery",
            "note": "Exact door and parking bays are not in the data. Crew decides where to park."}

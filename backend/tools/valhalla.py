"""Outdoor driving route with Valhalla (OpenStreetMap). Public instance unless VALHALLA_URL is set.

Truck costing sized to the ambulance in rules/vehicle.py. Turn-by-turn maneuvers are kept with
the shape index where each begins, so the app can show a next-turn banner during the drive.
Results are cached under data/cache.
"""

from __future__ import annotations

import math
import os
from typing import Any

import httpx

from app.settings import get_settings
from tools.http import client


def decode_polyline6(encoded: str) -> list[list[float]]:
    """Valhalla shapes are Google polyline encoded with 6 decimals. Returns [[lat, lon], ...]."""
    coords, index, lat, lon = [], 0, 0, 0
    while index < len(encoded):
        for axis in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lon += delta
        coords.append([lat / 1e6, lon / 1e6])
    return coords


def haversine_km(a: dict[str, float], b: dict[str, float]) -> float:
    r = 6371.0
    p1, p2 = math.radians(a["lat"]), math.radians(b["lat"])
    dp, dl = p2 - p1, math.radians(b["lon"] - a["lon"])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def drive_route(origin: dict[str, float], dest: dict[str, float]) -> dict[str, Any]:
    """Return {"minutes","km","shape":[[lat,lon],...],"maneuvers","vehicle","source","confidence"}."""
    from connectors import cache
    from rules import vehicle

    settings = get_settings()
    v = vehicle.profile()
    truck = {"height": round(v["height_m"], 2), "width": round(v["width_m"], 2)}
    if v.get("length_m"):
        truck["length"] = round(v["length_m"], 2)
    # Emergency driving: an ambulance responding with lights and siren may, with due care,
    # go against one-way streets and turn restrictions. Set EMERGENCY_ROUTING=0 to route as
    # ordinary traffic. The plan labels the route either way and the crew decides.
    emergency = os.getenv("EMERGENCY_ROUTING", "1").strip().lower() not in {"0", "false", "no", "off"}
    if emergency:
        truck.update(ignore_oneways=True, ignore_restrictions=True)
    body = {
        "locations": [{"lat": origin["lat"], "lon": origin["lon"]},
                      {"lat": dest["lat"], "lon": dest["lon"]}],
        "costing": "truck",
        "costing_options": {"truck": truck},
        "units": "kilometers",
    }
    url = f"{settings.valhalla_url}/route"
    note = "offline mode"
    if not settings.offline:
        key = cache.key_for("drive_route", body)
        if (hit := cache.get("valhalla", key)) is not None:
            return hit
        try:
            with client() as c:
                resp = c.post(url, json=body, headers={"X-Client-Id": "hackathon-prototype"})
                resp.raise_for_status()
                trip = resp.json()["trip"]
            shape, maneuvers = [], []
            for leg in trip["legs"]:
                offset = len(shape)
                shape += decode_polyline6(leg["shape"])
                for m in leg.get("maneuvers", []):
                    i = offset + m.get("begin_shape_index", 0)
                    lat, lon = shape[min(i, len(shape) - 1)]
                    maneuvers.append({"text": m.get("instruction", ""), "shape_index": i,
                                      "lat": lat, "lon": lon, "km": m.get("length"),
                                      "seconds": m.get("time"), "type": m.get("type")})
            return cache.put("valhalla", key, {
                "minutes": round(trip["summary"]["time"] / 60, 1),
                "km": round(trip["summary"]["length"], 2),
                "shape": shape,
                "maneuvers": maneuvers,
                "vehicle": {"source": v["source"], **truck},
                "rules_note": ("Emergency route: one-way streets and turn restrictions ignored. "
                               "Crew decides; drive with due care." if emergency
                               else "Route follows ordinary traffic rules."),
                "source": "valhalla",
                "request_url": url,
                "confidence": "medium",   # no live traffic in Valhalla
            })
        except (httpx.HTTPError, KeyError, ValueError) as exc:
            note = f"Valhalla unavailable: {type(exc).__name__}"

    # Fallback: straight line x 1.4 detour factor at 30 km/h urban average. Low confidence.
    km = haversine_km(origin, dest) * 1.4
    return {
        "minutes": round(km / 30 * 60, 1),
        "km": round(km, 2),
        "shape": [[origin["lat"], origin["lon"]], [dest["lat"], dest["lon"]]],
        "maneuvers": [],
        "source": "straight_line_estimate",
        "request_url": url,
        "confidence": "low",
        "note": note,
    }

"""Road routing through Valhalla with a truck profile sized to the ambulance.

Vehicle size comes from rules.vehicle: the agency's spec when set in backend/.env,
otherwise a cited reference ambulance. The result says which one was used.
"""

import httpx

from app.config import env
from connectors import cache
from rules import vehicle

PUBLIC_URL = "https://valhalla1.openstreetmap.de"
CLIENT_ID = "hackathon-prototype"


def _decode_polyline6(encoded: str) -> list[dict]:
    """Valhalla shapes use Google polyline encoding with 6 digits of precision."""
    coords, index, lat, lon = [], 0, 0, 0
    while index < len(encoded):
        for which in ("lat", "lon"):
            shift, result = 0, 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if which == "lat":
                lat += delta
            else:
                lon += delta
        coords.append({"lat": lat / 1e6, "lon": lon / 1e6})
    return coords


async def route(start: dict, end: dict) -> dict:
    """Truck-profile route from start to end ({"lat", "lon"} each)."""
    v = vehicle.profile()
    truck = {"height": round(v["height_m"], 2), "width": round(v["width_m"], 2)}
    if v.get("length_m"):
        truck["length"] = round(v["length_m"], 2)
    options = {"truck": truck}
    body = {"locations": [start, end], "costing": "truck", "costing_options": options,
            "units": "kilometers", "directions_options": {"units": "kilometers"}}
    key = cache.key_for(body)
    if (hit := cache.get("valhalla", key)) is not None:
        return hit
    base = env("VALHALLA_URL", PUBLIC_URL)
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(f"{base}/route", json=body, headers={"X-Client-Id": CLIENT_ID})
    resp.raise_for_status()
    trip = resp.json()["trip"]
    leg = trip["legs"][0]
    return cache.put("valhalla", key, {
        "shape": _decode_polyline6(leg["shape"]),
        "distance_km": trip["summary"]["length"],
        "time_s": trip["summary"]["time"],
        "maneuvers": [m["instruction"] for m in leg["maneuvers"]],
        "vehicle": {"source": v["source"], **truck},
        "source": "Valhalla (truck profile)",
    })

"""Vexcel aerial data. The key goes in the X-API-KEY header.

Hackathon keys cover Houston, Los Angeles, Northern California, the Florida panhandle and
the Princeton campus. Anywhere else answers 403, which we report as unknown.
"""

import httpx

from app.config import require
from connectors import cache

BASE = "https://api.vexcelgroup.com/v2"


async def property_extract(lat: float, lon: float) -> dict:
    """Parcel outline and property attributes at a point. Returns {"available": False} outside coverage."""
    key = cache.key_for("property", round(lat, 6), round(lon, 6))
    if (hit := cache.get("vexcel", key)) is not None:
        return hit
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.get(f"{BASE}/property/extract",
                                params={"wkt": f"POINT({lon} {lat})", "srid": 4326},
                                headers={"X-API-KEY": require("VEXCEL_API_KEY")})
    if resp.status_code == 403:
        return {"available": False, "reason": "Outside Vexcel hackathon coverage"}
    resp.raise_for_status()
    features = resp.json().get("features", [])
    if not features:
        return cache.put("vexcel", key, {"available": False, "reason": "No parcel at this point"})
    props = features[0].get("properties") or {}
    return cache.put("vexcel", key, {
        "available": True,
        "parcel_geometry": features[0]["geometry"],
        "imagery_date": props.get("metadata.ortho-date-estimate"),
        "pool_detected": props.get("pool.detected"),
        "source": "Vexcel",
    })

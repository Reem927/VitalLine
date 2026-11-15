"""Address -> coordinates with the US Census Geocoder (free, no key).

Every result says where the coordinates came from, so the dispatch record is traceable.
"""

from __future__ import annotations

from typing import Any

import httpx

from app.settings import get_settings
from tools.http import client

CENSUS_URL = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"


def geocode(address: str, fallback: dict[str, float] | None = None) -> dict[str, Any]:
    """Return {"lat","lon","matched_address","source","request_url","matched"}.

    If the Census service has no match (e.g. the synthetic demo address) or is unreachable,
    use `fallback` (building fixture coordinates) and say so in `source`.
    """
    params = {"address": address, "benchmark": "Public_AR_Current", "format": "json"}
    request_url = str(httpx.URL(CENSUS_URL, params=params))
    result: dict[str, Any] = {"request_url": request_url, "matched": False}

    if not get_settings().offline:
        try:
            with client() as c:
                data = c.get(CENSUS_URL, params=params).json()
            matches = data.get("result", {}).get("addressMatches", [])
            if matches:
                m = matches[0]
                return {
                    **result,
                    "matched": True,
                    "lat": m["coordinates"]["y"],
                    "lon": m["coordinates"]["x"],
                    "matched_address": m["matchedAddress"],
                    "source": "census_geocoder",
                }
            result["note"] = "Census geocoder returned no match"
        except (httpx.HTTPError, ValueError, KeyError) as exc:
            result["note"] = f"Census geocoder unavailable: {type(exc).__name__}"
    else:
        result["note"] = "offline mode"

    if fallback:
        return {**result, "lat": fallback["lat"], "lon": fallback["lon"],
                "matched_address": address, "source": "building_fixture"}
    return {**result, "lat": None, "lon": None, "matched_address": None, "source": "unknown"}

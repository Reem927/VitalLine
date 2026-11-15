"""Active weather alerts from the National Weather Service (api.weather.gov). Nationwide, no key."""

import httpx

USER_AGENT = "hackathon-prototype (decision-aid demo)"


async def alerts(lat: float, lon: float) -> list[dict]:
    """Active alerts at a point. Not cached: alerts change."""
    async with httpx.AsyncClient(timeout=30, headers={"User-Agent": USER_AGENT}) as client:
        resp = await client.get("https://api.weather.gov/alerts/active", params={"point": f"{lat:.4f},{lon:.4f}"})
    resp.raise_for_status()
    return [
        {"event": f["properties"].get("event"), "headline": f["properties"].get("headline"),
         "severity": f["properties"].get("severity"), "source": "National Weather Service"}
        for f in resp.json().get("features", [])
    ]

"""Matterport Model API (GraphQL) client.

HTTP basic auth: the API key is the user name, the token is the password.
Responses are cached on disk so the demo replays without network calls.
"""

import httpx

from app.config import require
from connectors import cache

API_URL = "https://api.matterport.com/api/models/graph"

LAYOUT_QUERY = """query Layout($id: ID!) { model(id: $id) {
  id name visibility
  address { address locality administrativeArea }
  geolocation { lat long }
  floors { id label sequence
    vertices { id position { x y } }
    edges { id type thickness vertices { id }
      openings { id type label width height lowerElevation relativeCenter } } }
  rooms { id floor { id }
    classifications { label confidence }
    boundary { edges { id } }
    dimensions(units: metric) { areaFloor width depth height } }
  panoLocations { id label position { x y z } }
  assets { floorplans(provider: "matterport") { format flags url width height resolution origin { x y } } }
} }"""


class MatterportError(RuntimeError):
    pass


async def query(gql: str, variables: dict | None = None, *, use_cache: bool = True) -> dict:
    """Run a GraphQL query and return its `data`."""
    variables = variables or {}
    key = cache.key_for(gql, variables)
    if use_cache and (hit := cache.get("matterport", key)) is not None:
        return hit
    auth = (require("MATTERPORT_API_KEY"), require("MATTERPORT_API_TOKEN"))
    async with httpx.AsyncClient(auth=auth, timeout=120) as client:
        resp = await client.post(API_URL, json={"query": gql, "variables": variables})
    if resp.status_code in (401, 403):
        raise MatterportError(f"Matterport rejected the key (HTTP {resp.status_code})")
    resp.raise_for_status()
    body = resp.json()
    if body.get("errors"):
        raise MatterportError(body["errors"][0].get("message", "GraphQL error"))
    return cache.put("matterport", key, body["data"])


async def layout(model_id: str) -> dict:
    """Floors, walls with openings, rooms, scan points and floor-plan images for one scan."""
    data = await query(LAYOUT_QUERY, {"id": model_id})
    model = data.get("model")
    if not model:
        raise MatterportError(f"Scan {model_id} not found or not shared with this key")
    return model

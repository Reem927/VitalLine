"""CoStar data kit reader.

The kit is a password-protected zip on a signed link. We read only the parts we need with
HTTP range requests (8 MB blocks), so the kit itself is never saved to disk. Records we use
are cached under data/cache/costar and deleted after the event.
"""

import csv
import io
import json
import zipfile

import httpx

from app.config import require
from connectors import cache

BLOCK = 8 * 2**20

PROPERTY_TYPES = {
    0: "Unknown", 1: "Hospitality", 2: "Industrial", 3: "Land", 5: "Office", 6: "General retail",
    7: "Flex", 8: "Sports and entertainment", 9: "Mixed use", 10: "Specialty", 11: "Multifamily",
    13: "Healthcare", 14: "Unknown", 15: "Residential", 16: "Homes",
}
ELEVATOR_TYPES = {0: "unknown", 1: "passenger", 2: "freight", 3: "escalator", 4: "parking"}
# Where elevator lists live, by property type (from the kit's commercial-property docs).
ELEVATOR_PATHS = [
    ("propertyApartment", "elevators"),
    ("propertyOffice", "structural", "elevators"),
    ("propertyRetail", "structural", "elevators"),
    ("propertyIndustrial", "structural", "elevators"),
    ("propertyFlex", "structural", "elevators"),
]


class _RangeFile(io.RawIOBase):
    """Read-only, seekable view of a remote file through HTTP range requests."""

    def __init__(self, url: str):
        self.url, self.pos, self._blocks = url, 0, {}
        self._client = httpx.Client(timeout=180)
        head = self._client.get(url, headers={"Range": "bytes=0-0"})
        if head.status_code == 403:
            raise RuntimeError("CoStar kit link expired. Run /costar-keys again and update COSTAR_KIT_URL.")
        self.size = int(head.headers["content-range"].split("/")[1])

    def _block(self, i: int) -> bytes:
        if i not in self._blocks:
            start = i * BLOCK
            end = min(start + BLOCK, self.size) - 1
            self._blocks[i] = self._client.get(self.url, headers={"Range": f"bytes={start}-{end}"}).content
        return self._blocks[i]

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos

    def seek(self, offset, whence=0):
        self.pos = {0: offset, 1: self.pos + offset, 2: self.size + offset}[whence]
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        out = bytearray()
        while n > 0 and self.pos < self.size:
            i, offset = divmod(self.pos, BLOCK)
            chunk = self._block(i)[offset:offset + n]
            out += chunk
            self.pos += len(chunk)
            n -= len(chunk)
        return bytes(out)


def _kit() -> zipfile.ZipFile:
    z = zipfile.ZipFile(_RangeFile(require("COSTAR_KIT_URL")))
    z.setpassword(require("COSTAR_ZIP_PASSWORD").encode())
    return z


def _dig(record: dict, path: tuple) -> list:
    node = record
    for key in path:
        node = (node or {}).get(key)
    return node or []


def summarize(record: dict) -> dict:
    """The building facts VitalLine uses. Missing values stay None (unknown)."""
    elevators = []
    for path in ELEVATOR_PATHS:
        for e in _dig(record, path):
            if e.get("elevatorState") == 1:  # 1 = exists
                elevators.append({"type": ELEVATOR_TYPES.get(e.get("elevatorType"), "unknown"),
                                  "count": e.get("numElevators")})
    addr = record.get("primaryAddress") or {}
    apt = record.get("propertyApartment") or {}
    return {
        "property_id": str(record.get("id")),
        "property_type": PROPERTY_TYPES.get(record.get("propertyType"), "Unknown"),
        "stories": record.get("numStoriesAboveGrade"),
        "height_ft": record.get("buildingHeightInFeet"),
        "units": apt.get("numUnits"),
        "walkup": apt.get("isWalkup"),
        "elevators": elevators,
        "parking_types": [p.get("parkingType") for p in record.get("parking") or []],
        "lat": addr.get("latitude"),
        "lon": addr.get("longitude"),
        "city": addr.get("city"),
        "source": "CoStar",
    }


def property_id_for_model(model_id: str) -> str | None:
    """CoStar property id linked to a Matterport scan, from the kit's starter CSV."""
    key = cache.key_for("model_to_property")
    index = cache.get("costar", key)
    if index is None:
        with _kit().open("commercial-properties.csv") as f:
            rows = csv.DictReader(io.TextIOWrapper(f, "utf-8"))
            index = cache.put("costar", key, {r["MatterportModelId"]: r["PropertyId"] for r in rows if r["MatterportModelId"]})
    return index.get(model_id)


def property_summary(property_id: str) -> dict | None:
    """Building facts for one CoStar property. First call scans the kit (about 20 s), then cached."""
    key = cache.key_for("property", property_id)
    if (hit := cache.get("costar", key)) is not None:
        return hit
    with _kit().open("data/commercial-property.jsonl") as f:
        for line in io.TextIOWrapper(f, "utf-8"):
            record = json.loads(line)
            if str(record.get("id")) == str(property_id):
                return cache.put("costar", key, summarize(record))
    return None

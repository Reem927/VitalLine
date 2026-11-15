"""A small JSON file cache under data/cache (gitignored).

Sponsor data cached here is deleted at the end of the event with the rest of the cache.
"""

import hashlib
import json
from typing import Any

from app.config import cache_dir


def key_for(*parts: Any) -> str:
    raw = json.dumps(parts, sort_keys=True, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def get(namespace: str, key: str) -> Any | None:
    path = cache_dir(namespace) / f"{key}.json"
    if path.exists():
        return json.loads(path.read_text())
    return None


def put(namespace: str, key: str, value: Any) -> Any:
    path = cache_dir(namespace) / f"{key}.json"
    path.write_text(json.dumps(value))
    return value

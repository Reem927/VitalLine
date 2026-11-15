"""Settings, paths and the demo scenario config.

Keys come from backend/.env only. Sponsor identifiers (addresses, scan ids) come from
backend/config/demo_building.local.json, which is gitignored and deleted after the event.
"""

import json
import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent
CACHE_DIR = REPO_DIR / "data" / "cache"
DEMO_CONFIG_PATH = BACKEND_DIR / "config" / "demo_building.local.json"

load_dotenv(BACKEND_DIR / ".env")

DEFAULT_MODEL = "gemini-3.6-flash"


def env(name: str, default: str | None = None) -> str | None:
    """Read a setting. Empty strings count as unset."""
    value = os.getenv(name)
    return value if value else default


def require(name: str) -> str:
    value = env(name)
    if not value:
        raise RuntimeError(f"{name} is not set in backend/.env")
    return value


def model_name() -> str:
    return env("MODEL_NAME", DEFAULT_MODEL)


@lru_cache
def demo_config() -> dict:
    """The local scenario config. Raises a plain error if it is missing."""
    if not DEMO_CONFIG_PATH.exists():
        raise RuntimeError(
            f"{DEMO_CONFIG_PATH.name} is missing. It holds the demo building ids and is never committed."
        )
    return json.loads(DEMO_CONFIG_PATH.read_text())


def cache_dir(name: str) -> Path:
    path = CACHE_DIR / name
    path.mkdir(parents=True, exist_ok=True)
    return path

"""Runtime settings, read once from the environment (and backend/.env if present)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent
load_dotenv(BACKEND_DIR / ".env")

DEFAULT_MODEL = "google_genai:gemini-2.5-flash"
PUBLIC_VALHALLA = "https://valhalla1.openstreetmap.de"


def _flag(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    model_name: str
    google_api_key: str
    anthropic_api_key: str
    wolfram_app_id: str
    valhalla_url: str
    supabase_url: str
    supabase_service_key: str
    sqlite_path: Path
    building_fixture: Path
    offline: bool          # no outbound HTTP at all (tests, flights)
    agents_enabled: bool   # use LLM agents; False runs the same tools deterministically

    @property
    def has_model_key(self) -> bool:
        if self.model_name.startswith("anthropic:"):
            return bool(self.anthropic_api_key)
        return bool(self.google_api_key)

    @property
    def use_agents(self) -> bool:
        return self.agents_enabled and self.has_model_key and not self.offline

    @property
    def use_supabase(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_key)


@lru_cache
def get_settings() -> Settings:
    return Settings(
        model_name=os.getenv("MODEL_NAME") or DEFAULT_MODEL,
        google_api_key=os.getenv("GOOGLE_API_KEY", ""),
        anthropic_api_key=os.getenv("ANTHROPIC_API_KEY", ""),
        wolfram_app_id=os.getenv("WOLFRAM_API_KEY", ""),
        valhalla_url=(os.getenv("VALHALLA_URL") or PUBLIC_VALHALLA).rstrip("/"),
        supabase_url=os.getenv("SUPABASE_URL", ""),
        supabase_service_key=os.getenv("SUPABASE_SERVICE_KEY", ""),
        sqlite_path=Path(os.getenv("SQLITE_PATH") or REPO_DIR / "data" / "vitalline.db"),
        building_fixture=Path(
            os.getenv("BUILDING_FIXTURE") or REPO_DIR / "data" / "synthetic" / "demo_tower.json"
        ),
        offline=_flag("VITALLINE_OFFLINE"),
        agents_enabled=not _flag("AGENTS_DISABLED"),
    )

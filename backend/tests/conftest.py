import os
import sys
from pathlib import Path

# Tests never call outside services or an LLM, and use an in-memory store.
os.environ["VITALLINE_OFFLINE"] = "1"
os.environ["AGENTS_DISABLED"] = "1"
os.environ["SQLITE_PATH"] = ":memory:"
for key in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY", "WOLFRAM_API_KEY"):
    os.environ[key] = ""

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest

from connectors.store import SQLiteStore


@pytest.fixture
def store():
    return SQLiteStore(":memory:")


@pytest.fixture
def client(store):
    from fastapi.testclient import TestClient

    from app.main import create_app

    return TestClient(create_app(store))

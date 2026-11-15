"""Shared HTTP client settings for outside services."""

from __future__ import annotations

import httpx

USER_AGENT = "VitalLine-prototype/0.1"
TIMEOUT = httpx.Timeout(8.0, connect=4.0)


def client() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, headers={"User-Agent": USER_AGENT})

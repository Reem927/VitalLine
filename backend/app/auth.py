"""Simple sign-in for the crew app.

Accounts live in Supabase Auth. The app never talks to Supabase: it sends email and password
to this backend, which checks them with Supabase and hands back its own session token.
Sessions are kept in data/cache/sessions.json (gitignored) so they survive a backend restart.

Creating an account needs the team code (DEMO_TOKEN) whenever one is set, so a stranger who
finds the tunnel address cannot sign themselves up.

With no Supabase keys (tests, offline) sign-in is off and the app skips the sign-in screen.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import threading
from datetime import UTC, datetime

from app.config import cache_dir
from app.settings import get_settings

MIN_PASSWORD = 8
_lock = threading.Lock()


class AuthError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def enabled() -> bool:
    s = get_settings()
    return bool(s.supabase_url and s.supabase_service_key) and not s.offline


# --- Supabase calls (kept small so tests can replace them) ---------------------

def _provider_create(email: str, password: str) -> None:
    from supabase import create_client

    s = get_settings()
    admin = create_client(s.supabase_url, s.supabase_service_key)
    try:
        admin.auth.admin.create_user({"email": email, "password": password, "email_confirm": True})
    except Exception as exc:  # noqa: BLE001 - supabase raises several error types
        text = str(exc).lower()
        if "already" in text or "registered" in text or "exists" in text:
            raise AuthError("An account with this email already exists.", 409) from None
        raise AuthError("Could not create the account.", 502) from None


def _provider_login(email: str, password: str) -> bool:
    from supabase import create_client

    s = get_settings()
    key = os.getenv("SUPABASE_ANON_KEY") or s.supabase_service_key
    try:
        res = create_client(s.supabase_url, key).auth.sign_in_with_password(
            {"email": email, "password": password})
        return res.session is not None
    except Exception:  # noqa: BLE001 - wrong password and unknown email both land here
        return False


# --- sessions --------------------------------------------------------------------

def _path():
    return cache_dir("auth") / "sessions.json"


def _load() -> dict[str, dict]:
    p = _path()
    return json.loads(p.read_text()) if p.exists() else {}


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _new_session(email: str) -> str:
    token = secrets.token_urlsafe(32)
    with _lock:
        sessions = _load()
        sessions[_digest(token)] = {"email": email, "created_at": datetime.now(UTC).isoformat()}
        _path().write_text(json.dumps(sessions))
    return token


def session_email(token: str | None) -> str | None:
    """Email of the signed-in user for this session token, or None."""
    if not token:
        return None
    return (_load().get(_digest(token)) or {}).get("email")


def end_session(token: str | None) -> None:
    if not token:
        return
    with _lock:
        sessions = _load()
        if sessions.pop(_digest(token), None) is not None:
            _path().write_text(json.dumps(sessions))


# --- operations ------------------------------------------------------------------

def _clean(email: str, password: str) -> tuple[str, str]:
    email = (email or "").strip().lower()
    if "@" not in email or "." not in email.split("@")[-1]:
        raise AuthError("Enter a valid email address.")
    if len(password or "") < MIN_PASSWORD:
        raise AuthError(f"Password must be at least {MIN_PASSWORD} characters.")
    return email, password


def sign_up(email: str, password: str, team_code: str | None) -> dict:
    if not enabled():
        raise AuthError("Sign-in is not set up on this backend.", 503)
    required = os.getenv("DEMO_TOKEN", "").strip()
    if required and not hmac.compare_digest((team_code or "").strip().encode(), required.encode()):
        raise AuthError("Wrong team code.", 403)
    email, password = _clean(email, password)
    _provider_create(email, password)
    return {"email": email, "token": _new_session(email)}


def sign_in(email: str, password: str) -> dict:
    if not enabled():
        raise AuthError("Sign-in is not set up on this backend.", 503)
    email = (email or "").strip().lower()
    if not _provider_login(email, password or ""):
        raise AuthError("Wrong email or password.", 401)
    return {"email": email, "token": _new_session(email)}

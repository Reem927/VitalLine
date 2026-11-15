"""Dispatch storage and the append-only event log.

`SQLiteStore` is the default (file under data/). `SupabaseStore` is used when SUPABASE_URL and
SUPABASE_SERVICE_KEY are set; its tables are in connectors/supabase_schema.sql.

Events are never updated or deleted. Each event carries sha256(prev_hash + row) so an edited
row breaks the chain (`verify_chain`).
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol


def now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="milliseconds")


def event_hash(prev_hash: str | None, row: dict[str, Any]) -> str:
    body = {k: row[k] for k in
            ("dispatch_id", "seq", "occurred_at", "actor", "type", "summary", "payload")}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(((prev_hash or "") + canonical).encode()).hexdigest()


class Store(Protocol):
    def create_dispatch(self, data: dict[str, Any]) -> dict[str, Any]: ...
    def get_dispatch(self, dispatch_id: str) -> dict[str, Any] | None: ...
    def update_dispatch(self, dispatch_id: str, **fields: Any) -> None: ...
    def list_dispatches(self, saved: bool | None = None) -> list[dict[str, Any]]: ...
    def append_event(self, dispatch_id: str, type: str, summary: str, actor: str = "system",
                     payload: dict | None = None, occurred_at: str | None = None,
                     trace_id: str | None = None) -> dict[str, Any]: ...
    def list_events(self, dispatch_id: str, after_seq: int = 0) -> list[dict[str, Any]]: ...
    def save_plan(self, dispatch_id: str, plan: dict[str, Any]) -> int: ...
    def latest_plan(self, dispatch_id: str) -> dict[str, Any] | None: ...
    def list_plans(self, dispatch_id: str) -> list[dict[str, Any]]: ...


def verify_chain(events: list[dict[str, Any]]) -> bool:
    prev = None
    for e in sorted(events, key=lambda e: e["seq"]):
        if e["prev_hash"] != prev or e["hash"] != event_hash(prev, e):
            return False
        prev = e["hash"]
    return True


_DISPATCH_JSON = ("geocode", "source", "rig_location", "location")


class SQLiteStore:
    def __init__(self, path: Path | str):
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(self.path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock:
            self._db.executescript(
                """
                create table if not exists dispatches (
                  id text primary key,
                  created_at text not null,
                  incident_type text not null,
                  address text not null,
                  floor integer,
                  unit text,
                  building_id text,
                  location text,
                  geocode text,
                  rig_location text,
                  source text,
                  responder text,
                  synthetic integer not null default 1,
                  status text not null default 'open',
                  saved integer
                );
                create table if not exists dispatch_events (
                  id integer primary key autoincrement,
                  dispatch_id text not null references dispatches(id),
                  seq integer not null,
                  occurred_at text not null,
                  recorded_at text not null,
                  actor text not null,
                  type text not null,
                  summary text not null,
                  payload text not null,
                  trace_id text,
                  prev_hash text,
                  hash text not null,
                  unique (dispatch_id, seq)
                );
                create table if not exists plans (
                  dispatch_id text not null references dispatches(id),
                  version integer not null,
                  created_at text not null,
                  plan text not null,
                  primary key (dispatch_id, version)
                );
                create trigger if not exists events_no_update before update on dispatch_events
                  begin select raise(abort, 'dispatch_events is append-only'); end;
                create trigger if not exists events_no_delete before delete on dispatch_events
                  begin select raise(abort, 'dispatch_events is append-only'); end;
                """
            )
            self._db.commit()

    # dispatches -------------------------------------------------------------

    def _row_to_dispatch(self, row: sqlite3.Row) -> dict[str, Any]:
        d = dict(row)
        for k in _DISPATCH_JSON:
            d[k] = json.loads(d[k]) if d[k] else None
        d["synthetic"] = bool(d["synthetic"])
        d["saved"] = None if d["saved"] is None else bool(d["saved"])
        return d

    def create_dispatch(self, data: dict[str, Any]) -> dict[str, Any]:
        row = {
            "id": data.get("id") or str(uuid.uuid4()),
            "created_at": data.get("created_at") or now_iso(),
            "incident_type": data["incident_type"],
            "address": data["address"],
            "floor": data.get("floor"),
            "unit": data.get("unit"),
            "building_id": data.get("building_id"),
            "responder": data.get("responder"),
            "synthetic": 1 if data.get("synthetic", True) else 0,
            "status": data.get("status", "open"),
            "saved": None,
        }
        for k in _DISPATCH_JSON:
            row[k] = json.dumps(data.get(k)) if data.get(k) is not None else None
        cols = ",".join(row)
        with self._lock:
            self._db.execute(f"insert into dispatches ({cols}) values "
                             f"({','.join('?' * len(row))})", list(row.values()))
            self._db.commit()
        return self.get_dispatch(row["id"])  # type: ignore[return-value]

    def get_dispatch(self, dispatch_id: str) -> dict[str, Any] | None:
        with self._lock:
            row = self._db.execute("select * from dispatches where id = ?",
                                   (dispatch_id,)).fetchone()
        return self._row_to_dispatch(row) if row else None

    def update_dispatch(self, dispatch_id: str, **fields: Any) -> None:
        if not fields:
            return
        vals = []
        for k, v in fields.items():
            if k in _DISPATCH_JSON and v is not None:
                v = json.dumps(v)
            if isinstance(v, bool):
                v = int(v)
            vals.append(v)
        sets = ",".join(f"{k} = ?" for k in fields)
        with self._lock:
            self._db.execute(f"update dispatches set {sets} where id = ?", [*vals, dispatch_id])
            self._db.commit()

    def list_dispatches(self, saved: bool | None = None) -> list[dict[str, Any]]:
        q, args = "select * from dispatches", []
        if saved is not None:
            q += " where saved = ?"
            args.append(int(saved))
        q += " order by created_at desc"
        with self._lock:
            rows = self._db.execute(q, args).fetchall()
        return [self._row_to_dispatch(r) for r in rows]

    # events -----------------------------------------------------------------

    def append_event(self, dispatch_id: str, type: str, summary: str, actor: str = "system",
                     payload: dict | None = None, occurred_at: str | None = None,
                     trace_id: str | None = None) -> dict[str, Any]:
        with self._lock:
            last = self._db.execute(
                "select seq, hash from dispatch_events where dispatch_id = ? "
                "order by seq desc limit 1", (dispatch_id,)).fetchone()
            seq = (last["seq"] if last else 0) + 1
            prev_hash = last["hash"] if last else None
            row = {
                "dispatch_id": dispatch_id,
                "seq": seq,
                "occurred_at": occurred_at or now_iso(),
                "recorded_at": now_iso(),
                "actor": actor,
                "type": type,
                "summary": summary,
                "payload": payload or {},
                "trace_id": trace_id,
                "prev_hash": prev_hash,
            }
            row["hash"] = event_hash(prev_hash, row)
            db_row = {**row, "payload": json.dumps(row["payload"], default=str)}
            self._db.execute(
                f"insert into dispatch_events ({','.join(db_row)}) values "
                f"({','.join('?' * len(db_row))})", list(db_row.values()))
            self._db.commit()
        return row

    def list_events(self, dispatch_id: str, after_seq: int = 0) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._db.execute(
                "select * from dispatch_events where dispatch_id = ? and seq > ? order by seq",
                (dispatch_id, after_seq)).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            d.pop("id", None)
            d["payload"] = json.loads(d["payload"])
            out.append(d)
        return out

    # plans ------------------------------------------------------------------

    def save_plan(self, dispatch_id: str, plan: dict[str, Any]) -> int:
        with self._lock:
            last = self._db.execute("select max(version) v from plans where dispatch_id = ?",
                                    (dispatch_id,)).fetchone()
            version = (last["v"] or 0) + 1
            plan = {**plan, "version": version}
            self._db.execute("insert into plans values (?,?,?,?)",
                             (dispatch_id, version, now_iso(), json.dumps(plan, default=str)))
            self._db.commit()
        return version

    def list_plans(self, dispatch_id: str) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._db.execute("select plan from plans where dispatch_id = ? order by version",
                                    (dispatch_id,)).fetchall()
        return [json.loads(r["plan"]) for r in rows]

    def latest_plan(self, dispatch_id: str) -> dict[str, Any] | None:
        plans = self.list_plans(dispatch_id)
        return plans[-1] if plans else None


class SupabaseStore:
    """Same interface on Supabase (Postgres). Not exercised by the test suite; needs a project."""

    def __init__(self, url: str, service_key: str):
        from supabase import create_client

        self.client = create_client(url, service_key)
        self._lock = threading.Lock()  # seq allocation; the unique index is the real guard

    def create_dispatch(self, data: dict[str, Any]) -> dict[str, Any]:
        row = {k: v for k, v in data.items() if v is not None}
        row.setdefault("id", str(uuid.uuid4()))
        return self.client.table("dispatches").insert(row).execute().data[0]

    def get_dispatch(self, dispatch_id: str) -> dict[str, Any] | None:
        res = self.client.table("dispatches").select("*").eq("id", dispatch_id).execute()
        return res.data[0] if res.data else None

    def update_dispatch(self, dispatch_id: str, **fields: Any) -> None:
        if fields:
            self.client.table("dispatches").update(fields).eq("id", dispatch_id).execute()

    def list_dispatches(self, saved: bool | None = None) -> list[dict[str, Any]]:
        q = self.client.table("dispatches").select("*")
        if saved is not None:
            q = q.eq("saved", saved)
        return q.order("created_at", desc=True).execute().data

    def append_event(self, dispatch_id: str, type: str, summary: str, actor: str = "system",
                     payload: dict | None = None, occurred_at: str | None = None,
                     trace_id: str | None = None) -> dict[str, Any]:
        with self._lock:
            last = (self.client.table("dispatch_events").select("seq,hash")
                    .eq("dispatch_id", dispatch_id).order("seq", desc=True).limit(1)
                    .execute().data)
            seq = (last[0]["seq"] if last else 0) + 1
            prev_hash = last[0]["hash"] if last else None
            row = {
                "dispatch_id": dispatch_id, "seq": seq,
                "occurred_at": occurred_at or now_iso(), "actor": actor, "type": type,
                "summary": summary, "payload": payload or {}, "trace_id": trace_id,
                "prev_hash": prev_hash,
            }
            row["hash"] = event_hash(prev_hash, row)
            return self.client.table("dispatch_events").insert(row).execute().data[0]

    def list_events(self, dispatch_id: str, after_seq: int = 0) -> list[dict[str, Any]]:
        return (self.client.table("dispatch_events").select("*").eq("dispatch_id", dispatch_id)
                .gt("seq", after_seq).order("seq").execute().data)

    def save_plan(self, dispatch_id: str, plan: dict[str, Any]) -> int:
        with self._lock:
            last = (self.client.table("plans").select("version").eq("dispatch_id", dispatch_id)
                    .order("version", desc=True).limit(1).execute().data)
            version = (last[0]["version"] if last else 0) + 1
            self.client.table("plans").insert(
                {"dispatch_id": dispatch_id, "version": version,
                 "plan": {**plan, "version": version}}).execute()
        return version

    def list_plans(self, dispatch_id: str) -> list[dict[str, Any]]:
        rows = (self.client.table("plans").select("plan").eq("dispatch_id", dispatch_id)
                .order("version").execute().data)
        return [r["plan"] for r in rows]

    def latest_plan(self, dispatch_id: str) -> dict[str, Any] | None:
        plans = self.list_plans(dispatch_id)
        return plans[-1] if plans else None


def make_store(settings) -> Store:
    if settings.use_supabase:
        return SupabaseStore(settings.supabase_url, settings.supabase_service_key)
    return SQLiteStore(settings.sqlite_path)

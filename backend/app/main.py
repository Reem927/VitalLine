"""VitalLine API, matching the iOS client (ios/VitalLine/VitalLine/Services/APIClient.swift).

Run: cd backend && .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0
All responses the app reads are 200: the client treats any other status as a failure.
"""

from __future__ import annotations

import asyncio
import hmac
import json
import os
from typing import Any, Literal

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from agents.planner import get_job, start_job
from agents.run import dispatch_info
from app import auth
from app.history import access_times, build_history
from app.settings import get_settings
from app.synthetic import SCENARIOS, make_dispatch
from connectors.store import Store, make_store, verify_chain
from tools.building import load_building

# ---------------------------------------------------------------- request bodies


class LatLon(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class PlanRequest(BaseModel):
    """Body of POST /dispatch and POST /plan/start (app: `PlanRequest`)."""
    scenario_id: str = "houston-demo"
    elevator_out: bool = False
    crew_location: LatLon | None = None
    dispatch_id: str | None = None    # from POST /dispatch; links the job to that call


CrewEventKind = Literal["en_route", "arrived_at_building", "entered_lobby", "at_patient"]
CREW_EVENTS = {
    "en_route": ("acknowledged", "Acknowledged / En route"),
    "arrived_at_building": ("arrived_building", "Arrived at building"),
    "entered_lobby": ("entered_lobby", "Entered lobby"),
    "at_patient": ("at_patient", "At patient"),
}


class CrewEvent(BaseModel):
    kind: CrewEventKind
    at: str | None = None             # ISO 8601 from the phone; server time if missing


class CompleteRequest(BaseModel):
    save: bool


class Credentials(BaseModel):
    email: str
    password: str
    team_code: str | None = None      # needed to create an account when DEMO_TOKEN is set


OPEN_PATHS = {"/health", "/auth/login", "/auth/signup"}


def _bearer(request: Request) -> str | None:
    value = request.headers.get("authorization", "")
    return value[7:].strip() if value.lower().startswith("bearer ") else None


# ---------------------------------------------------------------- app


def create_app(store: Store | None = None) -> FastAPI:
    app = FastAPI(title="VitalLine API", version="1.0.0",
                  description="Prototype, not a medical device. Synthetic dispatch data.")
    app.state.store = store or make_store(get_settings())

    # Access check, active whenever DEMO_TOKEN is set (always set it before opening a tunnel).
    # A request passes with a signed-in session (Authorization: Bearer ...) or with the shared
    # demo token (X-Demo-Token). Health and sign-in stay open.
    demo_token = os.getenv("DEMO_TOKEN", "").strip()

    @app.middleware("http")
    async def require_access(request: Request, call_next):
        if demo_token and request.url.path not in OPEN_PATHS:
            sent = request.headers.get("x-demo-token", "")
            token_ok = hmac.compare_digest(sent.encode(), demo_token.encode())
            if not token_ok and auth.session_email(_bearer(request)) is None:
                return JSONResponse({"detail": "sign in or send X-Demo-Token"}, status_code=401)
        return await call_next(request)

    # -- sign-in ---------------------------------------------------------------

    def _auth_call(fn, *args) -> Any:
        try:
            return fn(*args)
        except auth.AuthError as exc:
            return JSONResponse({"detail": str(exc)}, status_code=exc.status)

    @app.post("/auth/signup")
    def auth_signup(body: Credentials) -> Any:
        return _auth_call(auth.sign_up, body.email, body.password, body.team_code)

    @app.post("/auth/login")
    def auth_login(body: Credentials) -> Any:
        return _auth_call(auth.sign_in, body.email, body.password)

    @app.get("/auth/me")
    def auth_me(request: Request) -> Any:
        email = auth.session_email(_bearer(request))
        if email is None:
            return JSONResponse({"detail": "not signed in"}, status_code=401)
        return {"email": email}

    @app.post("/auth/logout")
    def auth_logout(request: Request) -> dict[str, Any]:
        auth.end_session(_bearer(request))
        return {"ok": True}

    def st() -> Store:
        return app.state.store

    def dispatch_or_404(dispatch_id: str) -> dict[str, Any]:
        d = st().get_dispatch(dispatch_id)
        if d is None:
            raise HTTPException(404, "dispatch not found")
        return d

    def new_dispatch(body: PlanRequest) -> dict[str, Any]:
        if body.scenario_id not in SCENARIOS:
            raise HTTPException(400, f"unknown scenario_id {body.scenario_id!r}")
        data = make_dispatch(body.scenario_id,
                             body.crew_location.model_dump() if body.crew_location else None)
        d = st().create_dispatch(data)
        st().append_event(d["id"], "dispatch_received", "Dispatch received", actor="system",
                          payload={"scenario_id": body.scenario_id, "source": d["source"],
                                   "geocode": d["geocode"], "synthetic": True})
        return d

    @app.get("/health")
    def health() -> dict[str, Any]:
        s = get_settings()
        return {"ok": True, "agents": s.use_agents, "model": s.model_name if s.use_agents else None,
                "store": type(st()).__name__.removesuffix("Store").lower(),
                "wolfram": bool(s.wolfram_app_id), "offline": s.offline,
                "token_required": bool(demo_token), "auth": auth.enabled()}

    # -- real scan mesh for the 3D plan view -----------------------------------

    @app.get("/scan-mesh/{building_id}/manifest")
    def scan_mesh_manifest(building_id: str) -> dict[str, Any]:
        """Files of the converted scan mesh. First call builds it (can take a minute)."""
        from tools import scan_mesh
        # "<building>--<part>" names an extra scan of the same building, e.g. the entrance scan.
        base, _, part = building_id.partition("--")
        try:
            building = load_building(base)
        except KeyError:
            raise HTTPException(404, "unknown building") from None
        mesh = (building.get("meshes") or {}).get(part) if part else building.get("mesh")
        info = scan_mesh.build(building_id, **mesh) if mesh else None
        if info is None:
            raise HTTPException(404, "no scan mesh for this building")
        return info

    @app.get("/scan-mesh/{building_id}/{name}")
    def scan_mesh_file(building_id: str, name: str) -> FileResponse:
        from tools import scan_mesh
        info = scan_mesh.manifest(building_id)
        if info is None or name not in info["files"] or "/" in name:
            raise HTTPException(404, "unknown mesh file")
        return FileResponse(scan_mesh.mesh_dir(building_id) / name)

    @app.get("/aerial/{building_id}/image")
    def aerial_image(building_id: str) -> FileResponse:
        """Vexcel aerial image for the plan's outside view (built during the outdoor step)."""
        from tools import aerial
        path = aerial.image_path(building_id)
        if "/" in building_id or not path.exists():
            raise HTTPException(404, "no aerial image for this building")
        return FileResponse(path, media_type="image/jpeg")

    # -- app contract v1 -------------------------------------------------------

    @app.post("/dispatch")
    def post_dispatch(body: PlanRequest) -> dict[str, Any]:
        """The raw synthetic call. No agents run."""
        d = new_dispatch(body)
        return {"dispatch": dispatch_info(d), "dispatch_id": d["id"]}

    @app.post("/plan/start")
    def plan_start(body: PlanRequest) -> dict[str, Any]:
        """Start the six agents as one job. Poll GET /plan/{job_id}."""
        d = st().get_dispatch(body.dispatch_id) if body.dispatch_id else None
        if d is None:
            d = new_dispatch(body)   # older clients that do not send dispatch_id
        if body.crew_location:
            st().update_dispatch(d["id"], rig_location=body.crew_location.model_dump())
        job = start_job(st(), d["id"], body.elevator_out)
        return {"job_id": job.job_id, "dispatch_id": d["id"]}

    @app.get("/plan/{job_id}")
    def plan_status(job_id: str) -> dict[str, Any]:
        job = get_job(job_id)
        if job is None:
            raise HTTPException(404, "unknown job_id")
        return job.to_json()

    # -- crew timeline + history (traceability) --------------------------------

    @app.post("/dispatch/{dispatch_id}/events")
    def post_crew_event(dispatch_id: str, body: CrewEvent) -> dict[str, Any]:
        d = dispatch_or_404(dispatch_id)
        etype, text = CREW_EVENTS[body.kind]
        if any(e["type"] == etype for e in st().list_events(dispatch_id)):
            return {"recorded": False, "reason": "already recorded"}
        e = st().append_event(dispatch_id, etype, text,
                              actor=f"crew:{d.get('responder') or 'unit'}", occurred_at=body.at)
        return {"recorded": True, "seq": e["seq"]}

    @app.post("/dispatch/{dispatch_id}/complete")
    def complete(dispatch_id: str, body: CompleteRequest) -> dict[str, Any]:
        """"Completed! Save to History?" Yes/No."""
        dispatch_or_404(dispatch_id)
        times = access_times(st().list_events(dispatch_id), st().list_plans(dispatch_id))
        p, a = times["predicted_min"], times["actual_min"]
        text = (f"Predicted access: {p[0]}–{p[1]} min" if p else "Predicted access: unknown") + \
               (f"; actual: {a} min" if a is not None else "; actual: unknown")
        st().append_event(dispatch_id, "completed", text, actor="system",
                          payload={**times, "saved": body.save})
        st().update_dispatch(dispatch_id, status="closed", saved=body.save)
        return {"saved": body.save, "access": times}

    @app.get("/dispatch/{dispatch_id}/events")
    def list_events(dispatch_id: str, after_seq: int = 0) -> list[dict[str, Any]]:
        dispatch_or_404(dispatch_id)
        return st().list_events(dispatch_id, after_seq)

    @app.get("/dispatch/{dispatch_id}/events/verify")
    def verify_events(dispatch_id: str) -> dict[str, Any]:
        dispatch_or_404(dispatch_id)
        events = st().list_events(dispatch_id)
        return {"intact": verify_chain(events), "count": len(events)}

    @app.get("/dispatch/{dispatch_id}/events/stream")
    async def stream_events(dispatch_id: str, request: Request, after_seq: int = 0):
        """Server-sent events: one message per log row, live. Ends after `completed`."""
        dispatch_or_404(dispatch_id)

        async def gen():
            seq, idle = after_seq, 0
            while not await request.is_disconnected():
                new = st().list_events(dispatch_id, seq)
                for e in new:
                    seq = e["seq"]
                    yield f"id: {seq}\nevent: {e['type']}\ndata: {json.dumps(e, default=str)}\n\n"
                    if e["type"] == "completed":
                        return
                idle = 0 if new else idle + 1
                if idle and idle % 30 == 0:
                    yield ": keep-alive\n\n"
                await asyncio.sleep(0.5)

        return StreamingResponse(gen(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache"})

    @app.get("/history")
    def history_list() -> list[dict[str, Any]]:
        return [{"dispatch_id": d["id"], "title": dispatch_info(d)["complaint"],
                 "address": d["address"], "created_at": d["created_at"]}
                for d in st().list_dispatches(saved=True)]

    @app.get("/history/full")
    def history_full() -> list[dict[str, Any]]:
        """Saved responses with their latest plan and crew timeline, newest first (History tab)."""
        out = []
        for d in st().list_dispatches(saved=True):
            plans = st().list_plans(d["id"])
            if not plans:
                continue
            events = [{"type": e["type"], "occurred_at": e["occurred_at"], "text": e["summary"]}
                      for e in st().list_events(d["id"])
                      if e["type"] in {"dispatch_received", "acknowledged", "arrived_building",
                                       "entered_lobby", "route_updated", "at_patient"}]
            out.append({"dispatch_id": d["id"], "crew_unit": d.get("responder"),
                        "plan": plans[-1], "events": events})
        out.sort(key=lambda r: r["events"][0]["occurred_at"] if r["events"] else "", reverse=True)
        return out

    @app.get("/history/{dispatch_id}")
    def history_detail(dispatch_id: str) -> dict[str, Any]:
        d = dispatch_or_404(dispatch_id)
        building = load_building(d["building_id"]) if d.get("building_id") else None
        return build_history(d, st().list_events(dispatch_id), st().list_plans(dispatch_id),
                             building)

    return app


app = create_app()

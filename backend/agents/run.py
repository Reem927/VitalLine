"""The six plan steps, shared by the agents and the deterministic runner.

Step ids match the app's "Creating Plan…" tasks (ios Models/AgentTask.swift):
  location -> outdoor -> access -> indoor -> verify -> brief

Each step computes its answer with plain code, keeps it on the `PlanRun`, and logs
`plan_step` events (running, then done/failed) so History can trace every step.
Agents call these through tools; they never write numbers themselves.
"""

from __future__ import annotations

import contextvars
import math
import re
import threading
import uuid
from dataclasses import dataclass, field
from typing import Any

from connectors.store import Store
from geometry.indoor_graph import BuildingGraph, IndoorRoute, NoRoute
from rules.equipment import AMBULANCE_HEIGHT_FT, ELEVATOR_CLEARANCE_IN
from tools import wolfram
from tools.building import nearby_hazards
from tools.valhalla import drive_route

STEP_ORDER = ["location", "outdoor", "access", "indoor", "verify", "brief"]
STEP_TITLES = {
    "location": "Building lookup",
    "outdoor": "Outdoor route",
    "access": "Access check",
    "indoor": "Indoor route",
    "verify": "Wolfram verification",
    "brief": "Crew brief",
}
STEP_ACTORS = {
    "location": "agent:location-resolver",
    "outdoor": "agent:outdoor-route",
    "access": "agent:access-checker",
    "indoor": "agent:indoor-planner",
    "verify": "agent:verifier",
    "brief": "agent:briefer",
}
# Steps whose result does not depend on elevator status; reused on a re-plan.
CACHEABLE = {"location", "outdoor"}
FLAG_KIND = {"lane_closure": "road_work", "pothole": "hazard", "weather": "weather"}

ALL_ELEVATORS = "all_elevators"


def _trace_id() -> str | None:
    try:
        from langsmith.run_helpers import get_current_run_tree

        rt = get_current_run_tree()
        return str(rt.trace_id) if rt else None
    except Exception:  # noqa: BLE001 - tracing is optional and must never break a plan
        return None


def _km(a: dict[str, float], b: dict[str, float]) -> float:
    la1, la2 = math.radians(a["lat"]), math.radians(b["lat"])
    h = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin(math.radians(b["lon"] - a["lon"]) / 2) ** 2)
    return 6371 * 2 * math.asin(math.sqrt(h))


def _ar_route(path: list[dict[str, float]]) -> list[dict[str, float]]:
    """Plan path (x, y up, z = floor-plan y) as AR waypoints: origin at the first point,
    Y up, first horizontal leg along -Z.

    The AR view assumes the phone starts at the first point facing along the first leg, so
    the crew stands at the start and faces the way the first arrow points.
    """
    if len(path) < 2:
        return []
    x0, y0, z0 = path[0]["x"], path[0].get("y", 0.0), path[0]["z"]
    nxt = next((p for p in path[1:] if math.hypot(p["x"] - x0, p["z"] - z0) > 0.05), path[1])
    dx, dz = nxt["x"] - x0, nxt["z"] - z0
    length = math.hypot(dx, dz) or 1.0
    s, c = -dx / length, -dz / length          # rotation that sends the first leg to -Z
    out = []
    for p in path:
        x, z = p["x"] - x0, p["z"] - z0
        out.append({"x": round(x * c - z * s, 3), "y": round(p.get("y", 0.0) - y0, 3),
                    "z": round(x * s + z * c, 3)})
    return out


def _is_real(text: str, kind: str) -> bool:
    """Whether a step comes from scan data (True) or is modeled or estimated (False)."""
    if "not scanned" in text or "estimated" in text or "assumed" in text:
        return False
    return kind == "walk" or "(scanned)" in text


class PlanBlocked(Exception):
    """A step failed in a way that must stop the plan (e.g. Wolfram mismatch, no route)."""


@dataclass
class PlanRun:
    store: Store
    dispatch: dict[str, Any]
    building: dict[str, Any]
    out_of_service: set[str] = field(default_factory=set)
    reason: str = "initial"
    cached: dict[str, dict[str, Any]] = field(default_factory=dict)
    run_id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    results: dict[str, dict[str, Any]] = field(default_factory=dict)
    status: dict[str, str] = field(default_factory=lambda: dict.fromkeys(STEP_ORDER, "pending"))
    mode: str = "deterministic"
    _route: IndoorRoute | None = None

    def __post_init__(self) -> None:
        self.graph = BuildingGraph(self.building)
        if ALL_ELEVATORS in self.out_of_service:
            self.out_of_service = (self.out_of_service - {ALL_ELEVATORS}) | set(self.graph.elevators)
        self._lock = threading.RLock()

    @property
    def dispatch_id(self) -> str:
        return self.dispatch["id"]

    def log(self, step: str, status: str, detail: str = "", payload: dict | None = None,
            actor: str | None = None) -> None:
        self.store.append_event(
            self.dispatch_id,
            type="plan_step",
            summary=f"{STEP_TITLES[step]}: {detail}" if detail else f"{STEP_TITLES[step]}…",
            actor=actor or STEP_ACTORS[step],
            payload={"run_id": self.run_id, "step": step, "status": status,
                     "title": STEP_TITLES[step], "detail": detail, **(payload or {})},
            trace_id=_trace_id(),
        )

    # --- running steps ---------------------------------------------------------

    def run_step(self, step: str, actor: str | None = None) -> dict[str, Any]:
        """Run one step. Idempotent: a finished step returns its stored result."""
        with self._lock:
            if step in self.results:
                return self.results[step]
            self.status[step] = "running"
            if step in self.cached:
                result = {**self.cached[step], "cached": True}
                self.log(step, "running", actor=actor)
            else:
                self.log(step, "running", actor=actor)
                try:
                    result = getattr(self, f"_step_{step}")()
                except NoRoute as exc:
                    result = {"ok": False, "detail": "Unknown: no usable route", "error": str(exc)}
            self.results[step] = result
            self.status[step] = "done" if result.get("ok", True) else "failed"
            self.log(step, self.status[step], result["detail"],
                     payload={"result": _small(result), "cached": step in self.cached},
                     actor=actor)
            return result

    def tasks(self) -> list[dict[str, Any]]:
        return [{"id": s, "title": STEP_TITLES[s], "status": self.status[s],
                 "detail": self.results.get(s, {}).get("detail")} for s in STEP_ORDER]

    # --- helpers ---------------------------------------------------------------

    def route(self) -> IndoorRoute:
        if self._route is None:
            self._route = self.graph.best_route(self.out_of_service)
        return self._route

    def _parking_for(self, entrance_id: str) -> tuple[dict | None, list[dict]]:
        ok = [p for p in self.building["parking"]
              if p["clearance_ft"] is None or p["clearance_ft"] >= AMBULANCE_HEIGHT_FT]
        rejected = [p for p in self.building["parking"] if p not in ok]
        if not ok:
            return None, rejected
        best = min(ok, key=lambda p: (p["near_entrance"] != entrance_id, p["walk_to_entrance_m"]))
        return best, rejected

    # --- steps -----------------------------------------------------------------

    def _step_location(self) -> dict[str, Any]:
        b, geo = self.building, self.dispatch.get("geocode") or {}
        src = b.get("source", "")
        source = "CoStar" if src.startswith("CoStar") else ("Matterport" if src.startswith("Matterport") else "synthetic")
        return {
            "ok": True,
            "building": {"name": b["name"], "floors": b["floors"], "type": b["type"],
                         "source": source},
            "geocode_source": geo.get("source"),
            "geocode_url": geo.get("request_url"),
            "detail": (f"CoStar: {b['floors']} floors, {b['type'].split(',')[0].lower()}"
                       if source == "CoStar"
                       else f"Matterport scan: {b['floors']} levels scanned" if source == "Matterport"
                       else f"Synthetic: {b['name']}, {b['floors']} floors, {b['type'].lower()}"),
        }

    def _step_outdoor(self) -> dict[str, Any]:
        # Staging uses the default entrance; elevator status does not change it.
        entrance_id = self.graph.best_route().entrance_id
        parking, _ = self._parking_for(entrance_id)
        entrance = self.graph.entrances[entrance_id]
        staging = (parking or {}).get("location") or entrance["location"]
        flags = [
            {"id": f"f{i}", "kind": FLAG_KIND.get(h["kind"], h["kind"]), "text": h["title"],
             "source": h["source"]}
            for i, h in enumerate(nearby_hazards(self.building), start=1)
        ]
        rig = self.dispatch.get("rig_location")
        rig_note = None
        if rig and staging and _km(rig, staging) > 50:
            # The app's rig position is in another city: start a simulated drive nearby instead.
            rig = {"lat": staging["lat"] - 0.012, "lon": staging["lon"] - 0.008}
            rig_note = "Rig start simulated about 1.5 km away (app location was in another city)"
        outdoor: dict[str, Any] = {"staging": staging, "entrance": entrance["location"],
                                   "flags": flags, "route": [], "eta_minutes": None,
                                   "distance_km": None, "maneuvers": [], "route_note": None}
        meta: dict[str, Any] = {}
        if rig:
            r = drive_route(rig, staging)
            outdoor.update(
                route=[{"lat": lat, "lon": lon} for lat, lon in r["shape"]],
                eta_minutes=max(1, math.ceil(r["minutes"])),
                distance_km=r["km"],
                maneuvers=r.get("maneuvers", []),
                route_note=r.get("rules_note"),
            )
            meta = {k: r.get(k) for k in ("source", "confidence", "request_url", "note", "minutes")}
            if rig_note:
                meta["rig_note"] = rig_note
            drive = f"{outdoor['eta_minutes']} min via {'Valhalla' if r['source'] == 'valhalla' else 'estimate'}"
        else:
            drive = "drive time unknown (no crew location)"
        try:
            from tools import aerial
            stop = outdoor["route"][-1] if outdoor["route"] else None
            outdoor["aerial"] = aerial.view(self.building, stop)
        except Exception:  # noqa: BLE001 - the aerial view is optional and must never block a plan
            outdoor["aerial"] = None
        sample = all("(sample)" in f["source"] for f in flags) and flags
        flag_txt = f"{len(flags)} flag{'s' if len(flags) != 1 else ''}"
        if sample:
            flag_txt += " (sample)"
        return {"ok": True, "outdoor": outdoor, "route_meta": meta,
                "detail": f"{drive} · {flag_txt}"}

    def _step_access(self) -> dict[str, Any]:
        route = self.route()
        parking, rejected = self._parking_for(route.entrance_id)
        ent = self.graph.entrances[route.entrance_id]
        synthetic = not self.building.get("source", "").startswith("CoStar")
        notes = []
        if parking:
            clr = parking["clearance_ft"]
            notes.append({
                "id": "a1",
                "text": f"Park: {parking['label']} ({parking['detail']})"
                        + (f", {clr:g} ft clearance" if clr else ""),
                "confidence": "medium", "synthetic": synthetic})
        else:
            notes.append({"id": "a1", "text": "Parking unknown: no spot clears the rig",
                          "confidence": "unknown", "synthetic": synthetic})
        notes.append({"id": "a2", "text": f"Entrance: {ent['label']}, {ent['detail']}",
                      "confidence": "medium", "synthetic": synthetic})
        for i, p in enumerate(rejected, start=3):
            notes.append({"id": f"a{i}",
                          "text": f"Avoid {p['label']} {p['detail']}: {p['clearance_ft']:g} ft "
                                  f"clearance, rig needs {AMBULANCE_HEIGHT_FT:g} ft",
                          "confidence": "medium", "synthetic": synthetic})
        detail = (f"Parking: {parking['label']} · " if parking else "Parking: unknown · ") + \
                 f"Entrance: {ent['detail'].split(',')[0]}"
        return {"ok": parking is not None, "access": notes, "parking": parking,
                "entrance_id": ent["id"], "detail": detail}

    def _step_indoor(self) -> dict[str, Any]:
        route = self.route()
        fp = self.building["floor_plan"]
        nodes = self.graph.nodes
        path = [{"x": nodes[n]["x"], "y": nodes[n]["y"]} for n in route.path
                if nodes[n].get("floor") == fp["floor"] and "x" in nodes[n]]
        used_elevator = route.vertical_kind == "elevator"
        need_in = route.equipment.width_in + 2 * ELEVATOR_CLEARANCE_IN

        def passable(door: dict) -> bool:
            if door["kind"] == "elevator":
                car = self.graph.elevators[door["elevator"]]
                return (door["elevator"] not in self.out_of_service and car["in_service"]
                        and door["width_in"] >= need_in)
            if door["kind"] == "stair":
                return route.equipment.can_use_stairs and door["width_in"] >= need_in
            return door["width_in"] >= need_in

        indoor = {
            "floor": fp["floor"], "width_m": fp["width_m"], "height_m": fp["height_m"],
            "rooms": fp["rooms"],
            "doors": [{"id": d["id"], "at": d["at"], "width_in": d["width_in"],
                       "passable": passable(d)} for d in fp["doors"]],
            "path": path,
            "mode": route.equipment.key,
            "elevator_ok": used_elevator,
            "floor_plan_image_url": None,
            "wall_height_m": fp.get("wall_height_m"),
            "mesh_url": f"/scan-mesh/{self.building['id']}/manifest" if self.building.get("mesh") else None,
            "path3d": self.building.get("path3d") or [{"x": p["x"], "y": 0.0, "z": p["y"]} for p in path],
            "ar_route": _ar_route(self.building.get("path3d")
                                  or [{"x": p["x"], "y": 0.0, "z": p["y"]} for p in path]),
            "nav": self.building.get("nav"),
            "legs": [{"id": s.index, "kind": s.kind, "text": s.text, "real": _is_real(s.text, s.kind)}
                     for s in route.steps],
        }
        steps = [{"id": s.index, "text": s.text, "seconds_min": math.floor(s.seconds[0]),
                  "seconds_max": math.ceil(s.seconds[1])} for s in route.steps]
        lo, hi = route.total_seconds
        time = {"min_seconds": math.floor(lo), "max_seconds": math.ceil(hi)}
        corridor = next((s for s in route.steps if s.text.startswith("Corridor east ")), None)
        if used_elevator:
            dist = f" · {corridor.text.split('Corridor east ')[1]}" if corridor else ""
            detail = f"{route.vertical} fits {route.equipment.label.lower()}{dist}"
        else:
            if not self.graph.elevators:
                out = "No elevator in the data"
            elif set(self.graph.elevators) <= self.out_of_service:
                out = "Elevators out"
            else:
                out = "No usable elevator"
            detail = f"{out}: {route.vertical} with {route.equipment.label.lower()}"
        return {"ok": True, "indoor": indoor, "steps": steps, "time": time,
                "equipment": route.equipment.key, "vertical": route.vertical, "detail": detail}

    def _step_verify(self) -> dict[str, Any]:
        route = self.route()
        indoor = self.results.get("indoor") or self.run_step("indoor")
        checks = []
        for s, shown in zip(route.steps, indoor["steps"], strict=True):
            lo_expr = "+".join(g.lo_expr for g in s.segments)
            hi_expr = "+".join(g.hi_expr for g in s.segments)
            # Displayed whole seconds must bracket the exact value.
            checks.append({"name": f"Step {s.index} min", "expr": lo_expr,
                           "claimed": shown["seconds_min"], "tolerance": 1.0})
            checks.append({"name": f"Step {s.index} max", "expr": hi_expr,
                           "claimed": shown["seconds_max"], "tolerance": 1.0})
        lo_all = "+".join(g.lo_expr for s in route.steps for g in s.segments)
        hi_all = "+".join(g.hi_expr for s in route.steps for g in s.segments)
        checks.append({"name": "Door to patient min (s)", "expr": lo_all,
                       "claimed": indoor["time"]["min_seconds"], "tolerance": 1.0})
        checks.append({"name": "Door to patient max (s)", "expr": hi_all,
                       "claimed": indoor["time"]["max_seconds"], "tolerance": 1.0})

        # One batched call: every check shares the same whole-second tolerance.
        batch = wolfram.verify([{k: c[k] for k in ("name", "expr", "claimed")} for c in checks],
                               tolerance=1.0)
        flat = batch["checks"]
        verified = batch["verified"]
        by = batch["verified_by"]
        total = flat[-1]
        result_text = f"{total['local']:g} s" + ("" if by == "wolfram"
                                                  else " (exact arithmetic; Wolfram not configured)")
        return {
            "ok": verified,
            "verification": {
                "verified": verified,
                "verified_by": by,
                "expression": total["expr"],
                "result": result_text,
                "checks": [{"id": f"c{i}", "what": c["name"], "python": f"{c['local']:g}",
                            "wolfram": None if c.get("wolfram") is None else f"{c['wolfram']:g}",
                            "claimed": c["claimed"], "match": c["ok"]}
                           for i, c in enumerate(flat, start=1)],
            },
            "detail": ("Distances and times verified" if by == "wolfram"
                       else "Times re-checked with exact arithmetic") if verified
                      else "Mismatch found: plan blocked",
        }

    def facts(self) -> dict[str, Any]:
        """Everything the briefer may cite. Numbers in the brief must appear here."""
        a, i = self.results.get("access", {}), self.results.get("indoor", {})
        o = self.results.get("outdoor", {}).get("outdoor", {})
        return {
            "drive_minutes": o.get("eta_minutes"), "distance_km": o.get("distance_km"),
            "flags": [f["text"] for f in o.get("flags", [])],
            "access": [n["text"] for n in a.get("access", [])],
            "steps": [f"{s['text']} ({s['seconds_min']}–{s['seconds_max']} s)"
                      for s in i.get("steps", [])],
            "door_to_patient_min": [round(i["time"]["min_seconds"] / 60, 1),
                                    round(i["time"]["max_seconds"] / 60, 1)] if i else None,
            "equipment": i.get("equipment"),
            "unit": self.dispatch.get("unit"), "floor": self.dispatch.get("floor"),
        }

    def submit_brief(self, lines: list[str]) -> dict[str, Any]:
        """Accept a brief only if every number in it appears in the facts."""
        allowed = set(re.findall(r"\d+(?:\.\d+)?", str(self.facts())))
        bad = sorted({n for line in lines for n in re.findall(r"\d+(?:\.\d+)?", line)} - allowed)
        if not lines or len(lines) > 6:
            return {"ok": False, "error": "Send 1 to 6 short lines."}
        if bad:
            return {"ok": False, "error": f"Numbers not in the tool results: {bad}. Use only "
                                          "numbers from get_plan_facts."}
        self._agent_brief = [line.strip() for line in lines]
        return {"ok": True}

    def _step_brief(self) -> dict[str, Any]:
        lines = getattr(self, "_agent_brief", None)
        source = "agent"
        if not lines:
            lines, source = self._template_brief(), "template"
        return {"ok": True, "brief": lines, "source": source,
                "detail": f"{len(lines)}-line brief ready"}

    def _template_brief(self) -> list[str]:
        f = self.facts()
        a = self.results.get("access", {})
        lines = []
        if a.get("parking"):
            p = a["parking"]
            lines.append(f"Park at {p['label']} ({p['detail']}).")
        lines.extend(f"{s['text']}." for s in self.results.get("indoor", {}).get("steps", []))
        if f["door_to_patient_min"]:
            lo, hi = f["door_to_patient_min"]
            eq = (f["equipment"] or "").replace("_", " ")
            lines.append(f"Door to patient {lo}–{hi} min with {eq}.")
        return lines[:6]

    # --- final assembly (contract: ios Models/Models.swift `Plan`) --------------

    def fill_missing(self) -> list[str]:
        filled = []
        for step in STEP_ORDER:
            if step not in self.results:
                self.run_step(step, actor="system:fallback")
                filled.append(step)
        return filled

    def assemble(self) -> dict[str, Any]:
        r, d = self.results, self.dispatch
        if not r["indoor"].get("ok", True) or "indoor" not in r["indoor"]:
            raise PlanBlocked("No usable indoor route; door-to-patient time unknown.")
        if not r["verify"]["verification"]["verified"]:
            raise PlanBlocked("Verification found a mismatch in the times; plan blocked.")
        outdoor = r["outdoor"]["outdoor"]
        unknowns = [
            {"id": "u1", "what": "Elevator status", "why": "No live building feed",
             "handled_as": "Crew reports it with the elevator toggle", "confidence": "unknown"},
            {"id": "u2", "what": "Building layout and sizes",
             "why": "Synthetic fixture, not a scan",
             "handled_as": "Used as given; labelled synthetic", "confidence": "low"},
        ]
        if outdoor["eta_minutes"] is None:
            unknowns.append({"id": "u3", "what": "Drive time", "why": "No crew location sent",
                             "handled_as": "Shown as unknown", "confidence": "unknown"})
        return {
            "dispatch": dispatch_info(d, equipment=r["indoor"]["equipment"],
                                      eta=outdoor["eta_minutes"]),
            "building": r["location"]["building"],
            "outdoor": outdoor,
            "access": r["access"]["access"],
            "indoor": r["indoor"]["indoor"],
            "steps": r["indoor"]["steps"],
            "time": r["indoor"]["time"],
            "verification": r["verify"]["verification"],
            "brief": r["brief"]["brief"],
            "unknowns": unknowns,
            "meta": {"run_id": self.run_id, "mode": self.mode, "reason": self.reason,
                     "brief_source": r["brief"]["source"], "dispatch_id": self.dispatch_id},
        }


def dispatch_info(d: dict[str, Any], equipment: str = "stretcher",
                  eta: int | None = None) -> dict[str, Any]:
    """`DispatchInfo` in the app contract."""
    return {
        "address": d["address"],
        "floor": d.get("floor"),
        "unit": d.get("unit"),
        "complaint": f"{d['incident_type']} (synthetic call)" if d.get("synthetic", True)
                     else d["incident_type"],
        "equipment": equipment,
        "priority": d.get("priority") or "High",
        "eta_minutes": eta,
    }


def _small(result: dict[str, Any]) -> dict[str, Any]:
    """Event payload copy without bulky geometry."""
    out = dict(result)
    if "outdoor" in out:
        out["outdoor"] = {k: v for k, v in out["outdoor"].items() if k != "route"} | {
            "route_points": len(out["outdoor"]["route"])}
    if "indoor" in out:
        out["indoor"] = {k: out["indoor"][k] for k in ("mode", "elevator_ok", "path")}
    return out


# The run the current agent invocation is working on (set by the runner, read by tools).
current_run: contextvars.ContextVar[PlanRun | None] = contextvars.ContextVar(
    "current_run", default=None)
_runs_by_id: dict[str, PlanRun] = {}


def register(run: PlanRun) -> None:
    _runs_by_id[run.run_id] = run


def unregister(run: PlanRun) -> None:
    _runs_by_id.pop(run.run_id, None)


def lookup(run_id: str | None) -> PlanRun | None:
    return current_run.get() or (_runs_by_id.get(run_id) if run_id else None)

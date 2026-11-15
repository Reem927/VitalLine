"""Plan jobs: a deepagents orchestrator with six subagents, one per task the app shows.

`run_job` always ends in `done` (full plan) or `error` (plan blocked, with a plain reason).
With a model key it runs the agents; any step an agent skips, or an agent error, is filled
by the same deterministic code, and the event log records which path produced each step.
"""

from __future__ import annotations

import logging
import threading
import uuid
from dataclasses import dataclass, field
from typing import Any

from agents.prompts import BRIEFER_PROMPT, PLANNER_PROMPT, SUBAGENT_PROMPT
from agents.run import (
    ALL_ELEVATORS,
    CACHEABLE,
    STEP_ORDER,
    PlanBlocked,
    PlanRun,
    current_run,
    register,
    unregister,
)
from agents.tools import SUBAGENT_TOOLS
from app.settings import get_settings
from connectors.store import Store
from tools.building import load_building

log = logging.getLogger(__name__)

SUBAGENT_DESCRIPTIONS = {
    "location-resolver": "Looks up the building at the dispatch address.",
    "outdoor-route": "Drive route from the crew to the staging spot, plus road flags.",
    "access-checker": "Picks parking the rig fits and the best entrance.",
    "indoor-planner": "Elevator or stairs, equipment fit, indoor steps and time ranges.",
    "verifier": "Re-checks all time arithmetic (Wolfram when configured).",
    "briefer": "Writes the short crew brief from finished results only.",
}


@dataclass
class Job:
    job_id: str
    dispatch_id: str
    run: PlanRun
    status: str = "running"          # running | done | error
    plan: dict[str, Any] | None = None
    error: str | None = None
    thread: threading.Thread | None = field(default=None, repr=False)

    def to_json(self) -> dict[str, Any]:
        r = self.run.results
        return {
            "job_id": self.job_id,
            "status": self.status,
            "tasks": self.run.tasks(),
            "building": r.get("location", {}).get("building"),
            "outdoor": r.get("outdoor", {}).get("outdoor"),
            "plan": self.plan,
            "error": self.error,
            "dispatch_id": self.dispatch_id,
        }


_jobs: dict[str, Job] = {}
_cache: dict[str, dict[str, dict[str, Any]]] = {}     # dispatch_id -> step -> result
_locks: dict[str, threading.Lock] = {}
_guard = threading.Lock()


def get_job(job_id: str) -> Job | None:
    return _jobs.get(job_id)


def _lock_for(dispatch_id: str) -> threading.Lock:
    with _guard:
        return _locks.setdefault(dispatch_id, threading.Lock())


def build_planner(model: Any):
    from deepagents import create_deep_agent

    subagents = [
        {
            "name": name,
            "description": SUBAGENT_DESCRIPTIONS[name],
            "system_prompt": BRIEFER_PROMPT if name == "briefer" else SUBAGENT_PROMPT,
            "tools": tools,
        }
        for name, tools in SUBAGENT_TOOLS.items()
    ]
    return create_deep_agent(model=model, tools=[], subagents=subagents,
                             system_prompt=PLANNER_PROMPT, name="vitalline-planner")


def _run_agents(run: PlanRun) -> None:
    agent = build_planner(get_settings().model_name)
    d = run.dispatch
    request = (
        f"Plan access for dispatch {run.dispatch_id}: {d['incident_type']} at {d['address']}, "
        f"floor {d.get('floor')}, unit {d.get('unit')}. Elevators out of service: "
        f"{', '.join(sorted(run.out_of_service)) or 'none'}. Reason: {run.reason}."
    )
    agent.invoke(
        {"messages": [{"role": "user", "content": request}]},
        config={
            "configurable": {"run_id": run.run_id},
            "recursion_limit": 100,
            "run_name": "vitalline-planner",
            "metadata": {"dispatch_id": run.dispatch_id, "plan_run_id": run.run_id},
        },
    )


def start_job(store: Store, dispatch_id: str, elevator_out: bool,
              background: bool = True) -> Job:
    dispatch = store.get_dispatch(dispatch_id)
    if dispatch is None:
        raise KeyError(dispatch_id)
    previous = store.latest_plan(dispatch_id)
    if previous is None:
        reason = "initial"
    else:
        was_out = bool(previous.get("meta", {}).get("elevator_out"))
        reason = ("Elevators unavailable" if elevator_out else "Elevators back in service") \
            if elevator_out != was_out else "Re-plan requested"
    building = load_building(dispatch.get("building_id") or "demo-tower")
    run = PlanRun(store=store, dispatch=dispatch, building=building,
                  out_of_service={ALL_ELEVATORS} if elevator_out else set(), reason=reason,
                  cached=dict(_cache.get(dispatch_id, {})))
    job = Job(job_id=f"j_{uuid.uuid4().hex[:10]}", dispatch_id=dispatch_id, run=run)
    _jobs[job.job_id] = job
    if background:
        job.thread = threading.Thread(target=run_job, args=(job, elevator_out), daemon=True)
        job.thread.start()
    else:
        run_job(job, elevator_out)
    return job


def run_job(job: Job, elevator_out: bool) -> None:
    run, store = job.run, job.run.store
    with _lock_for(job.dispatch_id):
        settings = get_settings()
        run.mode = "agents" if settings.use_agents else "deterministic"
        if run.reason not in ("initial", "Re-plan requested"):
            store.append_event(job.dispatch_id, "condition_reported", run.reason,
                               actor=f"crew:{run.dispatch.get('responder') or 'unit'}",
                               payload={"elevator_out": elevator_out})
        store.append_event(
            job.dispatch_id, "plan_started",
            "Creating plan…" if run.reason == "initial" else "Agents re-planning…",
            actor="agent:planner",
            payload={"run_id": run.run_id, "job_id": job.job_id, "reason": run.reason,
                     "mode": run.mode, "steps": STEP_ORDER, "elevator_out": elevator_out,
                     "cached": sorted(run.cached)},
        )
        try:
            if run.mode == "agents":
                register(run)
                token = current_run.set(run)
                try:
                    _run_agents(run)
                except Exception as exc:
                    log.exception("planner agents failed")
                    store.append_event(job.dispatch_id, "agent_error",
                                       f"Agents failed ({type(exc).__name__}); using rules engine",
                                       actor="agent:planner",
                                       payload={"run_id": run.run_id, "error": str(exc)[:500]})
                    run.mode = "deterministic_fallback"
                finally:
                    current_run.reset(token)
                    unregister(run)

            filled = run.fill_missing()
            plan = run.assemble()
            plan["meta"]["filled_by_rules"] = filled
            plan["meta"]["elevator_out"] = elevator_out
            version = store.save_plan(job.dispatch_id, plan)
            plan["meta"]["version"] = version
            _cache[job.dispatch_id] = {s: run.results[s] for s in CACHEABLE
                                       if run.results[s].get("ok", True)}
            job.plan, job.status = plan, "done"
            t = plan["time"]
            eta = f"{t['min_seconds'] / 60:.1f}–{t['max_seconds'] / 60:.1f} min"
            if run.reason == "initial":
                store.append_event(job.dispatch_id, "plan_ready", f"Plan ready: {eta} door to patient",
                                   actor="agent:planner",
                                   payload={"run_id": run.run_id, "job_id": job.job_id,
                                            "version": version, "time": t,
                                            "equipment": plan["indoor"]["mode"]})
            else:
                store.append_event(
                    job.dispatch_id, "route_updated",
                    f"Route updated: {run.reason}; {run.results['indoor']['detail']}, {eta}",
                    actor="agent:planner",
                    payload={"run_id": run.run_id, "job_id": job.job_id, "version": version,
                             "time": t, "equipment": plan["indoor"]["mode"], "warning": True})
        except PlanBlocked as exc:
            job.status, job.error = "error", str(exc)
            store.append_event(job.dispatch_id, "plan_blocked", str(exc), actor="agent:planner",
                               payload={"run_id": run.run_id, "job_id": job.job_id})
        except Exception as exc:
            log.exception("plan job failed")
            job.status, job.error = "error", f"Planning failed: {type(exc).__name__}"
            store.append_event(job.dispatch_id, "plan_blocked", job.error, actor="system",
                               payload={"run_id": run.run_id, "job_id": job.job_id,
                                        "error": str(exc)[:500]})

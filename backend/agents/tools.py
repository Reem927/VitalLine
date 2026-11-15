"""LangChain tools the agents call. Thin wrappers over agents/run.py.

Tools find the active run through a context variable, or through `run_id` in the
LangGraph config if the context did not propagate (e.g. into a subagent thread).
"""

from __future__ import annotations

import json
from typing import Any

from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from agents import run as plan_run

_BULKY = {"outdoor", "indoor", "verification", "access", "route_meta"}


def _plan(config: RunnableConfig | None) -> plan_run.PlanRun:
    run_id = ((config or {}).get("configurable") or {}).get("run_id")
    run = plan_run.lookup(run_id)
    if run is None:
        raise RuntimeError("no active plan run")
    return run


def _step(name: str, config: RunnableConfig | None) -> dict[str, Any]:
    result = _plan(config).run_step(name, actor=plan_run.STEP_ACTORS[name])
    # The model sees a short version; the full result stays on the run.
    small = {k: v for k, v in result.items() if k not in _BULKY}
    if name == "access":
        small["notes"] = [n["text"] for n in result.get("access", [])]
    if name == "verify":
        small["verified"] = result["verification"]["verified"]
        small["verified_by"] = result["verification"]["verified_by"]
    return small


@tool
def resolve_location(config: RunnableConfig) -> dict:
    """Look up the building at the dispatch address (geocode + building profile)."""
    return _step("location", config)


@tool
def plan_outdoor_route(config: RunnableConfig) -> dict:
    """Drive route from the crew to the staging spot (Valhalla) plus road flags."""
    return _step("outdoor", config)


@tool
def check_access(config: RunnableConfig) -> dict:
    """Pick parking the rig fits and the entrance with the fastest path to the patient."""
    return _step("access", config)


@tool
def plan_indoor_route(config: RunnableConfig) -> dict:
    """Indoor route, elevator or stairs, equipment fit and per-step time ranges."""
    return _step("indoor", config)


@tool
def verify_plan_math(config: RunnableConfig) -> dict:
    """Re-check every time sum (exact arithmetic, plus Wolfram when configured)."""
    return _step("verify", config)


@tool
def get_plan_facts(config: RunnableConfig) -> str:
    """All finished results the crew brief may use. Numbers must come from here."""
    return json.dumps(_plan(config).facts(), ensure_ascii=False)


@tool
def submit_brief(lines: list[str], config: RunnableConfig) -> dict:
    """Submit the crew brief: 3 to 6 short lines. Rejected if a number is not in the facts."""
    run = _plan(config)
    res = run.submit_brief(lines)
    if res["ok"]:
        return _step("brief", config)
    return res


SUBAGENT_TOOLS = {
    "location-resolver": [resolve_location],
    "outdoor-route": [plan_outdoor_route],
    "access-checker": [check_access],
    "indoor-planner": [plan_indoor_route],
    "verifier": [verify_plan_math],
    "briefer": [get_plan_facts, submit_brief],
}

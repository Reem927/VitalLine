"""Build the History screen from the event log (read-only, nothing recomputed by agents)."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

TIMELINE_TYPES = {
    "dispatch_received", "acknowledged", "arrived_building", "entered_lobby",
    "route_updated", "at_patient",
}


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts)


def access_times(events: list[dict[str, Any]], plans: list[dict[str, Any]]) -> dict[str, Any]:
    """Predicted = first plan (what the crew was told). Actual = building/lobby -> at patient."""
    predicted = None
    if plans and plans[0].get("time"):
        t = plans[0]["time"]
        predicted = [round(t["min_seconds"] / 60, 1), round(t["max_seconds"] / 60, 1)]

    by_type: dict[str, dict] = {}
    for e in events:
        by_type.setdefault(e["type"], e)   # first occurrence
    end = by_type.get("at_patient")
    start = by_type.get("arrived_building") or by_type.get("entered_lobby")
    actual, actual_note = None, None
    if end and start:
        actual = round((_parse(end["occurred_at"]) - _parse(start["occurred_at"]))
                       .total_seconds() / 60, 1)
        actual_note = f"from {start['type'].replace('_', ' ')} to at patient"
    else:
        missing = [n for n, ev in (("arrived at building", start), ("at patient", end)) if not ev]
        actual_note = "unknown: no " + " / ".join(missing) + " event"
    within = None if (predicted is None or actual is None) else predicted[0] <= actual <= predicted[1]
    return {"predicted_min": predicted, "actual_min": actual, "actual_basis": actual_note,
            "within_prediction": within}


def build_history(dispatch: dict[str, Any], events: list[dict[str, Any]],
                  plans: list[dict[str, Any]], building: dict[str, Any] | None) -> dict[str, Any]:
    tz = ZoneInfo((building or {}).get("timezone", "UTC"))
    received = next((e for e in events if e["type"] == "dispatch_received"), None)
    started = _parse(received["occurred_at"] if received else dispatch["created_at"]).astimezone(tz)

    equipment = None
    if plans and plans[0].get("indoor"):
        equipment = plans[0]["indoor"]["mode"].replace("_", " ").capitalize()

    site = (building or {}).get("name")
    unit = dispatch.get("unit")
    title = " · ".join(x for x in (dispatch["incident_type"], site,
                                    f"Unit {unit}" if unit else None) if x)
    subtitle = " · ".join(x for x in (
        started.strftime("%b %-d, %-I:%M %p"),
        f"Unit {dispatch['responder']}" if dispatch.get("responder") else None,
        equipment) if x)

    timeline = []
    for e in events:
        if e["type"] not in TIMELINE_TYPES:
            continue
        local = _parse(e["occurred_at"]).astimezone(tz)
        timeline.append({
            "seq": e["seq"],
            "time": local.strftime("%H:%M:%S"),
            "occurred_at": e["occurred_at"],
            "type": e["type"],
            "text": e["summary"],
            "warning": e["type"] == "route_updated",
            "actor": e["actor"],
        })

    return {
        "dispatch_id": dispatch["id"],
        "title": title,
        "subtitle": subtitle,
        "address": dispatch["address"],
        "synthetic": dispatch.get("synthetic", True),
        "timeline": timeline,
        "access": access_times(events, plans),
        "plan_versions": len(plans),
        "event_count": len(events),
    }

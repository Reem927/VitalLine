"""End-to-end flow the iOS app runs: dispatch -> plan job -> elevator toggle -> history."""

import time

import pytest

REQ = {"scenario_id": "houston-cardiac-14", "elevator_out": False,
       "crew_location": {"lat": 29.757, "lon": -95.364}}

PLAN_KEYS = {"dispatch", "building", "outdoor", "access", "indoor", "steps", "time",
             "verification", "brief"}


def _wait(client, job_id):
    for _ in range(100):
        job = client.get(f"/plan/{job_id}").json()
        if job["status"] != "running":
            return job
        time.sleep(0.05)
    raise AssertionError("job did not finish")


def _dispatch(client):
    r = client.post("/dispatch", json=REQ)
    assert r.status_code == 200
    return r.json()


def test_dispatch_matches_app_contract(client):
    body = _dispatch(client)
    d = body["dispatch"]
    assert set(d) == {"address", "floor", "unit", "complaint", "equipment", "priority",
                      "eta_minutes"}
    assert d["complaint"] == "Cardiac arrest (synthetic call)"
    assert body["dispatch_id"]


def test_unknown_scenario_is_400(client):
    assert client.post("/dispatch", json={**REQ, "scenario_id": "nope"}).status_code == 400
    assert client.get("/plan/j_missing").status_code == 404


def test_full_response_flow(client):
    did = _dispatch(client)["dispatch_id"]
    r = client.post("/plan/start", json={**REQ, "dispatch_id": did})
    assert r.status_code == 200
    job = _wait(client, r.json()["job_id"])

    assert job["status"] == "done", job["error"]
    assert [t["id"] for t in job["tasks"]] == [
        "location", "outdoor", "access", "indoor", "verify", "brief"]
    assert all(t["status"] == "done" for t in job["tasks"])
    plan = job["plan"]
    assert PLAN_KEYS <= set(plan)
    assert job["building"] == plan["building"] and job["outdoor"] == plan["outdoor"]
    assert [(s["seconds_min"], s["seconds_max"]) for s in plan["steps"]] == [
        (30, 45), (20, 35), (60, 100), (46, 48)]
    assert plan["time"] == {"min_seconds": 157, "max_seconds": 228}
    assert plan["indoor"]["mode"] == "stretcher" and plan["indoor"]["elevator_ok"]
    assert plan["verification"]["verified"]
    assert plan["outdoor"]["route"] and plan["outdoor"]["eta_minutes"] >= 1
    assert {f["kind"] for f in plan["outdoor"]["flags"]} == {"road_work", "hazard"}
    assert 1 <= len(plan["brief"]) <= 6
    # floor plan is top-left origin, y down: patient (1404) is in the bottom row
    assert plan["indoor"]["path"][-1] == {"x": 36.5, "y": 8.5}

    client.post(f"/dispatch/{did}/events",
                json={"kind": "en_route", "at": "2026-11-14T16:24:40+00:00"})
    client.post(f"/dispatch/{did}/events",
                json={"kind": "arrived_at_building", "at": "2026-11-14T16:31:12+00:00"})
    # Toggle: same dispatch, elevator_out true -> location/outdoor come from cache.
    j2 = _wait(client, client.post(
        "/plan/start", json={**REQ, "elevator_out": True, "dispatch_id": did}).json()["job_id"])
    assert j2["status"] == "done"
    assert j2["plan"]["indoor"]["mode"] == "stair_chair"
    assert not j2["plan"]["indoor"]["elevator_ok"]
    assert j2["tasks"][3]["detail"] == "Elevators out: Stair B with stair chair"

    client.post(f"/dispatch/{did}/events",
                json={"kind": "at_patient", "at": "2026-11-14T16:37:48+00:00"})
    done = client.post(f"/dispatch/{did}/complete", json={"save": True}).json()
    assert done["access"]["predicted_min"] == [2.6, 3.8]
    assert done["access"]["actual_min"] == 6.6

    assert [h["dispatch_id"] for h in client.get("/history").json()] == [did]
    detail = client.get(f"/history/{did}").json()
    assert detail["title"] == "Cardiac arrest · Houston Residential Tower · Unit 1404"
    assert detail["subtitle"].endswith("Unit M-12 · Stretcher")
    kinds = [t["type"] for t in detail["timeline"]]
    assert kinds == ["dispatch_received", "acknowledged", "arrived_building",
                     "route_updated", "at_patient"]
    assert [t["time"] for t in detail["timeline"]][1:3] == ["10:24:40", "10:31:12"]
    assert detail["timeline"][3]["warning"]

    events = client.get(f"/dispatch/{did}/events").json()
    cached = [e for e in events if e["type"] == "plan_step" and e["payload"].get("cached")]
    assert {e["payload"]["step"] for e in cached} == {"location", "outdoor"}
    assert client.get(f"/dispatch/{did}/events/verify").json()["intact"]


def test_crew_events_are_recorded_once(client):
    did = _dispatch(client)["dispatch_id"]
    assert client.post(f"/dispatch/{did}/events", json={"kind": "at_patient"}).json()["recorded"]
    assert not client.post(f"/dispatch/{did}/events",
                           json={"kind": "at_patient"}).json()["recorded"]


def test_unknown_actual_when_arrival_missing(client):
    did = _dispatch(client)["dispatch_id"]
    client.post(f"/dispatch/{did}/events", json={"kind": "at_patient"})
    done = client.post(f"/dispatch/{did}/complete", json={"save": False}).json()
    assert done["access"]["actual_min"] is None
    assert "unknown" in done["access"]["actual_basis"]
    assert client.get("/history").json() == []


def test_plan_without_crew_location_says_unknown(client):
    did = _dispatch(client)["dispatch_id"]
    job = _wait(client, client.post("/plan/start", json={
        "scenario_id": "houston-demo", "elevator_out": False, "dispatch_id": did}).json()["job_id"])
    # The dispatch was created with a crew location; a new one without it has no drive time.
    body = client.post("/dispatch", json={"scenario_id": "houston-demo"}).json()
    job = _wait(client, client.post("/plan/start", json={
        "scenario_id": "houston-demo", "dispatch_id": body["dispatch_id"]}).json()["job_id"])
    assert job["plan"]["outdoor"]["eta_minutes"] is None
    assert "unknown" in job["tasks"][1]["detail"]
    assert any(u["what"] == "Drive time" for u in job["plan"]["unknowns"])


def test_wolfram_mismatch_blocks_plan(client, monkeypatch):
    from tools import wolfram

    real = wolfram.verify
    monkeypatch.setattr(wolfram, "verify", lambda checks, tolerance=0.51: {
        **real(checks, tolerance), "verified": False})
    did = _dispatch(client)["dispatch_id"]
    job = _wait(client, client.post("/plan/start", json={**REQ, "dispatch_id": did})
                .json()["job_id"])
    assert job["status"] == "error" and job["plan"] is None
    assert "blocked" in job["error"]


@pytest.mark.parametrize("path", ["/dispatch/nope/events", "/history/nope"])
def test_404(client, path):
    assert client.get(path).status_code == 404


def test_event_stream_ends_after_completed(client):
    did = _dispatch(client)["dispatch_id"]
    client.post(f"/dispatch/{did}/complete", json={"save": False})
    with client.stream("GET", f"/dispatch/{did}/events/stream") as r:
        body = "".join(r.iter_text())
    assert "event: dispatch_received" in body and "event: completed" in body


def test_demo_token_is_required_when_set(store, monkeypatch):
    from fastapi.testclient import TestClient

    from app.main import create_app

    monkeypatch.setenv("DEMO_TOKEN", "test-token")
    c = TestClient(create_app(store))
    assert c.get("/health").json()["token_required"] is True      # health stays open
    assert c.get("/history").status_code == 401
    assert c.get("/history", headers={"X-Demo-Token": "wrong"}).status_code == 401
    assert c.get("/history", headers={"X-Demo-Token": "test-token"}).status_code == 200

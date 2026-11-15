# VitalLine API

Contract between the iOS app (`ios/VitalLine/VitalLine/Services/APIClient.swift`, `Models/*.swift`) and the FastAPI backend (`backend/app/main.py`). Prototype, not a medical device. All dispatches are synthetic.

## Base URL

- Simulator: `http://localhost:8000` (set automatically in `APIClient.swift`).
- Phone: a tunnel to port 8000; paste it into `API.baseURL` (device branch).
- Start the backend: `cd backend && .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0`. Docs at `/docs`.

## Conventions

- JSON keys are `snake_case`; the app decodes them to camelCase.
- Every endpoint the app calls returns **200** (the client treats anything else as a failure).
- Units: metres on the floor plan (origin top-left, y grows down), inches for doors and cars, seconds for indoor times, km and minutes outdoors.
- Every number comes from code: the indoor graph, geometry, Valhalla, exact arithmetic / Wolfram. Missing data is `null` plus an entry in `unknowns`, never a guess.
- Anything simulated is labelled (`source: "synthetic"`, `synthetic: true`, "(sample)").

## App flow

| App action | Call |
|---|---|
| Launch / pull to refresh | `POST /dispatch` → `dispatch` + `dispatch_id` |
| Start Response | `POST /plan/start` (with `dispatch_id`), then poll `GET /plan/{job_id}` every 0.7 s |
| Elevator toggle | `POST /plan/start` again with `elevator_out` flipped (location and outdoor reuse cached results) |
| Timeline marks (en route, arrived, lobby, at patient) | `POST /dispatch/{id}/events` |
| Completed → Yes / No | `POST /dispatch/{id}/complete` |

## Endpoints

### `POST /dispatch`

Request (`PlanRequest`):

```json
{"scenario_id": "houston-cardiac-14", "elevator_out": false, "crew_location": {"lat": 29.757, "lon": -95.364}}
```

`scenario_id`: `houston-demo` or `houston-cardiac-14` (alias). Unknown → `400`.

Response:

```json
{"dispatch": {"address": "1200 Demo St, Houston, TX", "floor": 14, "unit": "1404",
              "complaint": "Cardiac arrest (synthetic call)", "equipment": "stretcher",
              "priority": "High", "eta_minutes": null},
 "dispatch_id": "6f1c…"}
```

### `POST /plan/start`

Same body as `/dispatch`, plus `"dispatch_id"` (optional; without it a new dispatch is created). Response: `{"job_id": "j_…", "dispatch_id": "…"}`.

### `GET /plan/{job_id}`

```json
{"job_id": "j_…", "status": "running | done | error",
 "tasks": [{"id": "location", "title": "Building lookup", "status": "done", "detail": "Synthetic: Houston Residential Tower, 20 floors, residential high-rise"}, …],
 "building": {…} | null, "outdoor": {…} | null, "plan": {…} | null, "error": null, "dispatch_id": "…"}
```

`building` appears once `location` is done and `outdoor` once `outdoor` is done (Route Preview renders early). `plan` appears only with `status: "done"`. `status: "error"` means the plan is blocked (no usable route, or verification mismatch); `error` says why. `404` for an unknown job.

Tasks, in order, one subagent each:

| id | title | subagent | does |
|---|---|---|---|
| `location` | Building lookup | location-resolver | Census geocode + building profile |
| `outdoor` | Outdoor route | outdoor-route | Valhalla route crew → staging, road flags |
| `access` | Access check | access-checker | parking the rig clears, best entrance |
| `indoor` | Indoor route | indoor-planner | elevator/stairs, stretcher fit, steps and times |
| `verify` | Wolfram verification | verifier | re-checks every time sum |
| `brief` | Crew brief | briefer | 3–6 lines; numbers must exist in the results |

Task `status`: `pending | running | done | failed`.

### `Plan`

Matches `Models.swift`. Example (stretcher):

```json
{
  "dispatch": {…DispatchInfo, "equipment": "stretcher", "eta_minutes": 2},
  "building": {"name": "Houston Residential Tower", "floors": 20, "type": "Residential high-rise", "source": "synthetic"},
  "outdoor": {"route": [{"lat": …, "lon": …}], "staging": {…}, "entrance": {…},
              "flags": [{"id": "f1", "kind": "road_work", "text": "Lane closure on approach street", "source": "TxDOT DriveTexas (sample)"}],
              "eta_minutes": 2, "distance_km": 0.7},
  "access": [{"id": "a1", "text": "Park: Garage A (Level 1), 11 ft clearance", "confidence": "medium", "synthetic": true}],
  "indoor": {"floor": 14, "width_m": 40, "height_m": 10, "rooms": [{"id", "name", "polygon": [{"x", "y"}]}],
             "doors": [{"id": "d_elev2", "at": {"x": 4.5, "y": 4}, "width_in": 42, "passable": true}],
             "path": [{"x": 4.5, "y": 3.5}, …, {"x": 36.5, "y": 8.5}], "mode": "stretcher", "elevator_ok": true,
             "floor_plan_image_url": null},
  "steps": [{"id": 1, "text": "Stage at the east entrance; take the lobby door", "seconds_min": 30, "seconds_max": 45},
            {"id": 2, "text": "Lobby to Elevator 2 (stretcher fits: 80 x 54 in car)", "seconds_min": 20, "seconds_max": 35},
            {"id": 3, "text": "Ride to floor 14", "seconds_min": 60, "seconds_max": 100},
            {"id": 4, "text": "Corridor east 35 m to unit 1404", "seconds_min": 46, "seconds_max": 48}],
  "time": {"min_seconds": 157, "max_seconds": 228},
  "verification": {"verified": true, "verified_by": "wolfram | local_exact_arithmetic",
                   "expression": "12/0.73+28+…", "result": "227.342 s",
                   "checks": [{"id": "c1", "what": "Step 1 min", "python": "30.789", "wolfram": null, "claimed": 30, "match": true}]},
  "brief": ["Park at Garage A (Level 1).", "…", "Door to patient 2.6–3.8 min with stretcher."],
  "unknowns": [{"id": "u1", "what": "Elevator status", "why": "No live building feed", "handled_as": "…", "confidence": "unknown"}],
  "meta": {"run_id", "mode": "agents | deterministic | deterministic_fallback", "reason", "brief_source", "dispatch_id", "version", "filled_by_rules": []}
}
```

With `elevator_out: true` all elevators are treated as out: Stair B with a stair chair, 337–475 s, `mode: "stair_chair"`, `elevator_ok: false`.

The app shows "Verified by Wolfram" only when `verified_by` is `wolfram` (needs `WOLFRAM_API_KEY`); otherwise "Math checked".

### `POST /dispatch/{id}/events`

`{"kind": "en_route | arrived_at_building | entered_lobby | at_patient", "at": "2026-11-14T16:31:12Z"}` → `{"recorded": true, "seq": 7}`. Each kind is recorded once per dispatch.

### `POST /dispatch/{id}/complete`

`{"save": true}` → `{"saved": true, "access": {"predicted_min": [2.6, 3.8], "actual_min": 6.6, "actual_basis": "from arrived building to at patient", "within_prediction": false}}`. Predicted is the first plan; actual is arrival (building or lobby) → at patient, or `null` with the reason.

### History and trace

| Endpoint | Returns |
|---|---|
| `GET /history` | saved dispatches `[{dispatch_id, title, address, created_at}]` |
| `GET /history/{id}` | title, subtitle, timestamped timeline (warning rows for route updates), predicted vs actual |
| `GET /dispatch/{id}/events?after_seq=N` | every log row: `{seq, occurred_at, actor, type, summary, payload, trace_id, prev_hash, hash}` |
| `GET /dispatch/{id}/events/stream` | the same rows live as server-sent events; ends after `completed` |
| `GET /dispatch/{id}/events/verify` | `{"intact": true}` if the hash chain is unbroken |
| `GET /health` | agents on/off, model, store, Wolfram, offline |

Event types: `dispatch_received`, `plan_started`, `plan_step` (per task, `running` then `done`/`failed`, actor = subagent), `plan_ready`, `condition_reported`, `route_updated`, `plan_blocked`, `agent_error`, `acknowledged`, `arrived_building`, `entered_lobby`, `at_patient`, `completed`. The log is append-only (database triggers) and hash-chained. `trace_id` holds the LangSmith trace when tracing is on.

## Data sources

| Data | Source | Fallback (labelled) |
|---|---|---|
| Geocoding | US Census Geocoder | building fixture coordinates |
| Drive route | Valhalla / OSM (`VALHALLA_URL`, public instance default) | straight line × 1.4 at 30 km/h, `confidence: low` |
| Road flags | sample rows labelled TxDOT DriveTexas / Houston 311 | — |
| Building | `data/synthetic/demo_tower.json` | — |
| Math check | exact arithmetic + Wolfram Short Answers (`WOLFRAM_API_KEY`) | exact arithmetic only |

## Errors

`400` unknown `scenario_id`, `404` unknown job or dispatch, `422` invalid body, `200` + `"status": "error"` when a plan is blocked.

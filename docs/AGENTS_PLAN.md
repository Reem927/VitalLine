# Agents, dispatch history and map: plan

Status: built and connected to the app. The planner has six subagents, one per task the app shows: `location-resolver`, `outdoor-route`, `access-checker`, `indoor-planner`, `verifier`, `briefer`. The contract is in [API.md](API.md); where this early plan differs from the code, the code and API.md win.

## 1. Screens the agents serve

| Screen | What it shows | Who fills it |
|---|---|---|
| Dispatch summary | Incident type, address, unit, equipment, map of the address, predicted access time with confidence | `summary` agent |
| Plan load | Outdoor approach, site access, indoor path, equipment fit, unknowns | `planner` orchestrator + 5 subagents |
| History | Timestamped steps (dispatch received → at patient), route updates, predicted vs actual | Event log (no agent, read-only) |

## 2. Dispatch source: synthetic, but traceable

There is no public API for live 911/CAD dispatches with patient-level detail (that data is protected). Houston publishes an [active incidents page](https://cohweb.houstontx.gov/ActiveIncidents/Combined.aspx?agency=F) as HTML only, no official feed.

What we do instead:

1. **Our own dispatch endpoint** acts as the CAD. `POST /dispatches` creates a synthetic dispatch and returns a `dispatch_id`. Every later step hangs off that id.
2. **Real, public services for everything around the dispatch**, so the numbers are checkable:
   - Geocoding: US Census Geocoder (free, no key) turns the address into coordinates. The request URL and matched address are stored with the dispatch.
   - Outdoor routing: Valhalla (`VALHALLA_URL`, public OSM instance by default). The route request and response are stored.
   - Building data: CoStar / Matterport / Vexcel when keys arrive; until then a fixture in `data/synthetic/`.
3. **Optional realism:** replay real incident types, addresses (block level) and timestamps from [Seattle Real Time Fire 911 Calls](https://catalog.data.gov/dataset/seattle-real-time-fire-911-calls) (Socrata, updated every 5 minutes). Each synthetic dispatch then records `source: "seattle_fire_911"` and the source row id, so it traces back to a public record.
4. **Format:** dispatch fields follow NEMSIS v3.5 names where one exists (e.g. `eTimes.03` unit notified, `eTimes.06` arrived on scene, `eTimes.07` arrived at patient), so the history matches what real EMS records use.

Every dispatch is marked `synthetic: true` in the API and in the app.

## 3. Event log (history and traceability)

One append-only table in Supabase. Nothing is updated or deleted; corrections are new events.

```sql
create table dispatch_events (
  id            bigint generated always as identity primary key,
  dispatch_id   uuid not null references dispatches(id),
  seq           int  not null,                 -- 1, 2, 3 per dispatch
  occurred_at   timestamptz not null,          -- when it happened (crew clock / agent clock)
  recorded_at   timestamptz not null default now(),
  actor         text not null,                 -- 'system' | 'crew:M-12' | 'agent:indoor-path'
  type          text not null,                 -- see list below
  summary       text not null,                 -- line shown in History
  payload       jsonb not null default '{}',   -- inputs/outputs, source URLs
  trace_id      text,                          -- LangSmith run id for agent steps
  prev_hash     text,
  hash          text not null,                 -- sha256(prev_hash || row) for tamper evidence
  unique (dispatch_id, seq)
);
```

Event types (the screenshot timeline maps 1:1):

| type | Example summary | Actor |
|---|---|---|
| `dispatch_received` | Dispatch received | system |
| `acknowledged` | Acknowledged / En route | crew |
| `summary_ready` | Summary ready, access 3.5–5.0 min (medium confidence) | agent:summary |
| `plan_step` | Indoor path planned via Elevator B | agent:<subagent> |
| `plan_ready` | Plan loaded | agent:planner |
| `arrived_building` | Arrived at building | crew |
| `entered_lobby` | Entered lobby | crew |
| `route_updated` | ⚠ Elevator B unavailable, stairs used | crew → agent:indoor-path |
| `at_patient` | At patient | crew |
| `closed` | Predicted 3.5–5.0 min, actual 6.6 min | system |

"Actual access" = `at_patient.occurred_at − arrived_building.occurred_at`. Stored on `closed` so the History screen does not recompute.

How agent steps get logged: a LangChain callback handler (`backend/agents/event_logger.py`) listens for `on_tool_end` and subagent completion and writes a `plan_step` event with the LangSmith `run_id` as `trace_id`. Tapping a step in History can then open the exact trace.

API:

- `POST /dispatches` → create (synthetic), logs `dispatch_received`
- `POST /dispatches/{id}/events` → crew status taps (acknowledged, arrived, lobby, blocked, at patient)
- `GET  /dispatches/{id}/events` → History screen
- `GET  /dispatches/{id}/summary` → Dispatch summary screen
- `POST /dispatches/{id}/plan` → runs planner, streams `plan_step` events (SSE)

## 4. Agents (deepagents, already pinned: `deepagents==0.7.38`)

### 4.1 `summary` agent (dispatch summary screen)

Small, fast. Single `create_deep_agent` with no subagents, or a plain structured-output chain.

- Tools: `geocode_address`, `get_building_profile`, `get_outdoor_eta`
- Output (Pydantic): incident, address, coordinates, unit, equipment, `predicted_access_min: [low, high]`, `confidence`, `unknowns: list[str]`
- Rule: if the building profile is missing, `predicted_access_min` is `null` and `unknowns` says why. Never guess.

### 4.2 `planner` orchestrator (plan load screen)

```python
from deepagents import create_deep_agent

planner = create_deep_agent(
    model=settings.model_name,            # MODEL_NAME, default Gemini
    tools=[get_dispatch, get_building_profile],
    subagents=[outdoor_route, site_access, indoor_path, equipment_fit, verifier],
    system_prompt=PLANNER_PROMPT,
)
```

| Subagent | Job | Tools | Data |
|---|---|---|---|
| `outdoor-route` | Rig → best curb / entrance | `valhalla_route`, `list_entrances` | Valhalla, OSM |
| `site-access` | Gates, key box, lobby desk, loading dock | `get_site_access` | CoStar / Vexcel, fixture |
| `indoor-path` | Entrance → unit, elevator vs stairs | `indoor_graph_path` (networkx), `elevator_status` | Matterport scan → graph |
| `equipment-fit` | Will the stretcher fit (elevator depth, door width, stair landing turns) | `fit_check` (shapely), `wolfram_verify` | Equipment specs |
| `verifier` | Recompute times, combine confidence, list unknowns | `wolfram_verify` | Outputs above |

Each subagent returns a typed result plus `confidence` and `unknowns`. The orchestrator only assembles; it does not invent numbers. Deterministic math (graph shortest path, geometry, time sums) lives in plain Python tools under `backend/geometry/` and `backend/tools/`, and the LLM only decides which to call and explains the result.

Re-plan: a `route_updated` crew event (e.g. "Elevator B unavailable") calls only `indoor-path` + `equipment-fit` + `verifier` with the blocked edge removed, and logs the new plan as `plan_step` events.

### 4.3 Folder layout

```
backend/
  app/main.py              FastAPI routes above
  app/settings.py          env (MODEL_NAME, VALHALLA_URL, ...)
  agents/summary.py
  agents/planner.py        orchestrator + subagent dicts
  agents/prompts.py
  agents/event_logger.py   callback → dispatch_events
  tools/geocode.py         US Census Geocoder
  tools/valhalla.py
  tools/building.py        CoStar/Matterport or fixture
  tools/wolfram.py
  geometry/indoor_graph.py networkx graph from scan
  geometry/fit.py          shapely stretcher fit
  connectors/supabase.py   dispatches + dispatch_events
  rules/                   hard rules (e.g. stretcher min elevator depth)
  tests/
data/synthetic/houston_tower.json   building fixture for the demo
```

## 5. Map

- **iOS display: Apple MapKit (SwiftUI `Map`).** Free, no API key, native on iOS 26, supports markers, polylines and look-around. Implemented in `ios/VitalLine/VitalLine/Views/DispatchSummaryView.swift`.
- **Route line:** today the app asks MapKit (`MKDirections`) for the driving route as a stand-in. When `/dispatches/{id}/plan` exists, the app draws Valhalla's route shape instead, so the map matches the plan the agents computed.
- **Coordinates come from the backend** (Census geocoder) and are stored on the dispatch, so map and history agree on one location.

## 6. Build order

1. Supabase tables `dispatches`, `dispatch_events` + `connectors/supabase.py`
2. `POST/GET /dispatches`, `/events` with synthetic generator + Census geocode
3. iOS: History screen reading `/events`; swap sample data in `DispatchSummaryView` for the API
4. `summary` agent + `/summary`
5. Tools (Valhalla, building fixture, indoor graph, fit check)
6. `planner` + subagents + event logger, SSE to Plan load screen
7. Re-plan on `route_updated`

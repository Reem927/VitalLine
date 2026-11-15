# VitalLine API

Contract between the iOS app and the FastAPI backend. Version 1 matches what the app already sends and decodes (`ios/VitalLine/VitalLine/Services/APIClient.swift` and `Models/*.swift`). Version 1.1 fields are optional additions: the app ignores them until it adds matching properties.

VitalLine is a decision aid, not a medical device. The crew makes the final call.

## Base URL

- Simulator: `http://localhost:8000`
- Phone: the tunnel URL. Set `API.baseURL` in `APIClient.swift` and `API.useMock = false`.

## Conventions

- JSON keys are `snake_case`. The app decodes them to camelCase.
- Units: metres for floor-plan coordinates, inches for door widths (`width_in`), seconds for times, kilometres for road distance.
- Floor-plan coordinates: origin at the top-left of the drawn area, `y` grows downward.
- Every number comes from a tool (geometry code, Valhalla, Wolfram, CoStar, Matterport). If no tool returned it, the field is `null` and the item says so.
- Anything simulated is labeled: `"source": "synthetic"`, `"synthetic": true`, or "(sample)" in a flag source.
- v1.1: every request carries the header `X-Demo-Token`. The value lives in the backend `.env` and in the app's local build settings, never in git. Requests without it get `401`.

## Endpoints

### `POST /dispatch`

The raw synthetic call. No agents run.

Request (`PlanRequest`):

```json
{ "scenario_id": "houston-demo", "elevator_out": false, "crew_location": { "lat": 29.757, "lon": -95.364 } }
```

Response (`DispatchResponse`):

```json
{ "dispatch": { "address": "...", "floor": 2, "unit": "...", "complaint": "Cardiac arrest (synthetic call)",
                "equipment": "stretcher", "priority": "High", "eta_minutes": null } }
```

`scenario_id` values: `houston-demo` (primary), `la-highrise` (alternate), `princeton-live` (on-site AR test). The app's current `houston-cardiac-14` is accepted as an alias for `houston-demo`.

### `POST /plan/start`

Starts the six agents as one job. Same request body as `/dispatch`. Response:

```json
{ "job_id": "j_123" }
```

### `GET /plan/{job_id}`

The app polls this about every 0.7 s until `status` is not `running`.

```json
{
  "job_id": "j_123",
  "status": "running",
  "tasks": [ { "id": "location", "title": "Building lookup", "status": "done", "detail": "CoStar: 4 stories, residential" } ],
  "building": null,
  "outdoor": null,
  "plan": null,
  "error": null
}
```

- `status`: `running`, `done` or `error`.
- `building` is filled once `location` is done, and `outdoor` once `outdoor` is done, so Route Preview can render early.
- `plan` is filled only when `status` is `done`.
- `error` is set when `status` is `error`. A Wolfram mismatch blocks the plan and returns `error`, never a partial plan.

Task ids, in order. Each maps to one subagent:

| id | Title | Subagent | Sources |
|---|---|---|---|
| `location` | Building lookup | location-resolver | Geocode, CoStar property |
| `outdoor` | Outdoor route | outdoor-route | Valhalla, TxDOT, Houston 311, NWS |
| `access` | Access check | access-checker | Vexcel, building profile |
| `indoor` | Indoor route | indoor-planner | Matterport scans, equipment fit |
| `verify` | Wolfram verification | verifier | Wolfram |
| `brief` | Crew brief | briefer | Tool results only |

Task `status`: `pending`, `running`, `done` or `failed`.

### `POST /plan/start` with `elevator_out: true`

The elevator toggle is a new job with the flag set. The backend reuses cached `location` and `outdoor` results, so those tasks finish at once.

### `GET /plan/{job_id}/why?step={step_id}` (v1.1)

The proof behind one step: the tool results it came from and the Wolfram check.

```json
{ "step_id": 3, "claims": [ { "text": "Doorway 0.75 m clears a 24 in stretcher", "tool": "geometry.door_fit",
  "inputs": { "door_width_m": 0.75, "stretcher_width_in": 24 }, "result": "pass",
  "wolfram": { "expression": "...", "result": "...", "match": true } } ] }
```

## Data models

### `Plan`

| Field | Type | Notes |
|---|---|---|
| `dispatch` | DispatchInfo | Echo of the call |
| `building` | Building | |
| `outdoor` | Outdoor | |
| `access` | [AccessNote] | |
| `indoor` | Indoor | |
| `steps` | [Step] | Ordered crew steps |
| `time` | TimeRange | Door to patient, as a range |
| `verification` | Verification | |
| `brief` | [String] | Short crew brief, one line per item |
| `unknowns` | [Unknown] | v1.1 |

### `DispatchInfo`

`address`, `floor` (int), `unit`, `complaint`, `equipment` (`stretcher`, `stair_chair` or `bariatric`), `priority` (optional), `eta_minutes` (optional).

### `Building`

`name`, `floors` (int, above grade), `type`, `source` (`CoStar` or `synthetic`).

### `Outdoor`

`route` ([LatLon]), `staging` (LatLon), `entrance` (LatLon), `flags` ([Flag]), `eta_minutes` (optional), `distance_km` (optional). The ETA is Valhalla's road estimate for a truck profile, not an ambulance response time.

`Flag`: `id`, `kind` (`road_work`, `hazard`, `weather`, or other), `text`, `source`.

### `AccessNote`

`id`, `text`, `confidence` (`high`, `medium`, `low`, `unknown`), `synthetic` (bool).

### `Indoor`

v1 fields (one drawn floor):

| Field | Type | Notes |
|---|---|---|
| `floor` | int | Building floor shown |
| `width_m`, `height_m` | number | Drawn area size |
| `rooms` | [Room] | `id`, `name`, `polygon` ([PlanPoint]) |
| `doors` | [Door] | `id`, `at` (PlanPoint), `width_in`, `passable` |
| `path` | [PlanPoint] | Route on the drawn floor |
| `mode` | string | `stretcher` or `stair_chair` |
| `elevator_ok` | bool | False when out of service or the car fit fails |
| `floor_plan_image_url` | string, optional | Matterport floor-plan image for the drawn floor |

v1.1 additions:

`Door` gains:

| Field | Type | Notes |
|---|---|---|
| `confidence` | string | `high` (measured), `medium` (scanner default size), `low` (code minimum) |
| `measured` | bool | False when the width is a default or assumed value |
| `source` | string | For example `matterport` or `assumed: code minimum` |

`Indoor` gains `legs`, the whole route from entrance to patient across scans:

```json
"legs": [
  { "id": "L1", "kind": "scan", "label": "Entrance to stairs and elevator", "real": true,
    "scan_ref": "concierge", "floor_label": "Floor 1",
    "waypoints": [ { "x": 1.2, "y": 3.4, "z": 0.0 } ],
    "pano_ids": [ "..." ] },
  { "id": "L2", "kind": "elevator", "label": "Elevator to floor 2", "real": false,
    "from_floor": 1, "to_floor": 2, "expected_climb_m": null, "climb_source": "assumed floor height" },
  { "id": "L3", "kind": "corridor_gap", "label": "Corridor to unit door not scanned", "real": false,
    "distance_m": null },
  { "id": "L4", "kind": "scan", "label": "Unit door to patient", "real": true, "scan_ref": "unit",
    "waypoints": [ { "x": 0.5, "y": 0.8, "z": 0.0 } ] }
]
```

- `kind`: `scan` (real scan data), `elevator`, `stairs`, `corridor_gap` or `outdoor`.
- `real: false` legs are modeled or unknown. The app should say so on screen.
- `waypoints` are in that scan's own metre coordinates (x, y, z up). Each scan has its own frame; legs are not in one shared frame.
- `scan_ref` names a scan in the backend config. The 3D viewer model id is sent at runtime only. It is never stored in git.
- `expected_climb_m` lets the app confirm the elevator ride with the barometer (`CMAltimeter`). `null` when unknown.

### `Step`

`id` (int), `text`, `seconds_min`, `seconds_max`.

### `TimeRange`

`min_seconds`, `max_seconds`.

### `Verification`

v1: `verified` (bool), `expression`, `result`.

v1.1 adds `checks`: one entry per verified number.

```json
"checks": [ { "id": "c1", "what": "Total path length", "python": "41.2", "wolfram": "41.2", "match": true } ]
```

## Unknowns and confidence

v1.1 `Unknown`:

```json
{ "id": "u1", "what": "Elevator car interior size", "why": "Not in CoStar or the scans",
  "handled_as": "Assumed code minimum for stretcher fit", "confidence": "low" }
```

Rules the backend follows:

- "Unknown" is a valid answer. The backend never fills a gap with an invented number.
- Door widths of exactly 36 x 80 in from the scanner are treated as default values, not measurements (`confidence: medium`).
- Stretcher fit checks the doorway width and the turn into the next hallway. Wolfram verifies the turn calculation.

## Errors

- `400`: bad request body or unknown `scenario_id`.
- `401` (v1.1): missing or wrong `X-Demo-Token`.
- `404`: unknown `job_id`.
- `200` with `"status": "error"`: planning failed or Wolfram blocked the plan. `error` explains why in plain words.

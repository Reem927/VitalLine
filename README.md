# VitalLine

VitalLine is a decision aid for EMS crews. After dispatch, it plans an equipment-aware path from the rig to the patient: the drive, where to stop, the way in, and the route inside the building. It works from real building scans, aerial imagery, property records and road data, and it checks its own math. It shows its work, gives confidence levels and says "unknown" when it does not know. The crew makes the final call.

**Prototype, not a medical device.** It uses synthetic dispatch calls, gives no clinical advice and controls no doors or elevators.

Built for HackPrinceton Fall 2026.

## What it does

1. **Dispatch.** A synthetic call arrives with an address, floor, unit and complaint.
2. **Drive.** A route sized to an ambulance, with emergency driving rules applied and labelled, turn-by-turn guidance and live weather alerts.
3. **Arrival.** An aerial view of the building showing where the route ends and where the building is.
4. **Indoor plan.** The path through the building's 3D scan. Every door on it is checked for width and for the turn into the next room, for a stretcher and for a stair chair. If the stretcher cannot make a turn, the plan says so and switches equipment.
5. **Elevator out.** One switch shows the stairs route, computed and verified with the plan.
6. **Floor plan.** Every door on the floor with its width, whether it was measured, and what blocks each kind of equipment, so the crew can choose their own way.
7. **AR navigation.** On site, arrows on the phone's camera view follow the planned route.
8. **History.** Each response is saved with its timeline: dispatch received, en route, arrived, at patient.

## How it works

Six agents each own one step of the plan and report progress to the app as they finish:

| Agent | Job | Data |
|---|---|---|
| Location resolver | Find the building and its facts | CoStar property records |
| Outdoor route | Drive route and road flags | Valhalla, National Weather Service |
| Access checker | Parking and entrance | Vexcel aerial imagery, building data |
| Indoor planner | Path, equipment fit, time ranges | Matterport scans |
| Verifier | Recompute every time sum | Wolfram |
| Briefer | Write the crew brief | Results of the other five only |

Two rules shape the design:

- **Numbers come from tools, never from the language model.** Geometry, door and turn checks, path search and time math are plain code. The agents decide what to run and write the brief. A brief containing a number that no tool returned is rejected.
- **Unknown is a valid answer.** Each leg of the route is marked as scan data or as modeled. Door widths the scanner did not measure are labelled as assumed. Legs with no scan, such as an elevator car or an unscanned corridor, are shown as not scanned instead of being filled in.

## Tech stack

| Layer | Choice |
|---|---|
| iOS app | SwiftUI, MapKit, SceneKit (3D plan), ARKit and RealityKit (AR navigation) |
| Backend | Python, FastAPI |
| Agents | LangChain Deep Agents (orchestrator and six subagents), traced in LangSmith |
| Model | Set by `MODEL_NAME`. Claude by default; Gemini also works |
| Geometry | networkx (walkable graph), shapely (door and turn fit) |
| Math verification | Wolfram, through the Wolfram MCP server |
| Routing | Valhalla, truck profile sized to an ambulance |
| Building data | CoStar property records, Matterport 3D scans, Vexcel aerial imagery |
| Storage | Supabase (Postgres and Auth), SQLite when no Supabase keys are set |
| Phone to backend | Cloudflare quick tunnel, with a shared access token |

## Run it

The repository holds code only. Keys and licensed building data are not included.

**Backend**

```bash
scripts/run_backend.sh
```

The first run creates `backend/.venv` and installs the pinned packages. Copy `backend/.env.example` to `backend/.env` and fill in the keys you have. Endpoints are listed at http://localhost:8000/docs and in [docs/API.md](docs/API.md).

- With no keys at all, set `VITALLINE_OFFLINE=1`. The backend then plans on a synthetic building (`data/synthetic/demo_tower.json`) with no outside calls.
- The real demo buildings need CoStar, Matterport and Vexcel keys, plus a local file `backend/config/demo_building.local.json` naming the scans to use. That file is not in the repository.

**iOS app**

Open `ios/VitalLine/VitalLine.xcodeproj` in Xcode and run it. The simulator talks to the backend at `localhost:8000`.

To run on a phone:

```bash
scripts/run_tunnel.sh
```

Set `DEMO_TOKEN` in `backend/.env` first. The script prints the token and a temporary address. Paste the address into the app's sign-in screen under "Backend address". AR navigation needs a real iPhone and the camera permission in the app target.

**Tests**

```bash
cd backend && .venv/bin/python -m pytest
```

## Data and honesty

- Dispatch calls are synthetic and labelled as synthetic in the app. There is no patient information.
- Equipment sizes come from published spec sheets and model code, cited in `backend/rules/`. Walking speeds and elevator timing are prototype assumptions and are labelled as assumed.
- The drive time is a routing-engine estimate, not an ambulance response time.
- The app makes no claim about time or lives saved.
- Building scans, aerial imagery and property records were provided by CoStar Group, Matterport and Vexcel for the hackathon. None of that data is in this repository.

## Possible next steps

- **More reliable AR.** The phone lines up with the scan from a known start point today. Saving a visual map of the space once would let it find its own position and direction, and correct drift along the way.
- **Whole-building routes.** Scans of lobbies, corridors and stairwells would let the path run from the entrance to the unit door without modeled gaps.
- **Hospital suggestion.** After the patient is reached, suggest a destination hospital by capability and distance, using public hospital data. The crew and medical direction would still decide.
- **Nearest AED.** Show defibrillators along the route from open map data.
- **Choose the patient's location.** Let the crew tap a room and re-plan to it.
- **Bariatric equipment.** Add a published bariatric stretcher profile and wider-door routing.
- **Ask why.** Let the crew ask why a step was chosen and get the tool results and the verification behind it.
- **Live inputs.** Real dispatch feeds and elevator status need partnerships with dispatch and building system vendors.

## Repository

```
backend/    FastAPI service: agents, tools, geometry, rules, connectors, tests
ios/        SwiftUI app
docs/       API contract and agent design
scripts/    Start the backend, open the tunnel, connection checks
data/       Synthetic building for offline runs
```

# VitalLine

VitalLine is a decision aid for EMS crews. After dispatch, it plans an equipment-aware path from the rig to the patient using building scans, road and access data, and checked math. It covers the outdoor approach, site access and the indoor path. It shows its work, gives confidence levels and says "unknown" when it does not know. The crew makes the final call.

**Prototype, not a medical device.** It uses synthetic dispatch data, gives no clinical advice and controls no doors or elevators.

Built for HackPrinceton Fall 2026.

## Backend

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.lock
cp .env.example .env   # optional: add GOOGLE_API_KEY to run the LLM agents
.venv/bin/uvicorn app.main:app --reload --host 0.0.0.0
```

Open http://localhost:8000/docs. The iOS app in the Simulator talks to it at `localhost:8000` (`API.useMock = false` in `APIClient.swift`). Run the tests with `.venv/bin/python -m pytest`.
Endpoints are in [docs/API.md](docs/API.md); the agent design is in [docs/AGENTS_PLAN.md](docs/AGENTS_PLAN.md).

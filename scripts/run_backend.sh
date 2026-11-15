#!/bin/sh
# Start the VitalLine backend on port 8000. Run from anywhere:
#   scripts/run_backend.sh
# First run creates backend/.venv and installs the pinned packages.
# Needs backend/.env (copy backend/.env.example) and, for the real demo building,
# backend/config/demo_building.local.json. Neither file is in git.
set -e
cd "$(dirname "$0")/../backend"
if [ ! -x .venv/bin/uvicorn ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.lock
fi
[ -f .env ] || echo "Note: backend/.env is missing. Copy backend/.env.example and fill it in."
exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"

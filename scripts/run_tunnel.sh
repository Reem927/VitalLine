#!/bin/sh
# Give the phone a temporary HTTPS address for the backend on this Mac (port 8000).
#   1. Start the backend first:  scripts/run_backend.sh
#   2. Then, in a second terminal: scripts/run_tunnel.sh
# Paste the printed address and the demo token into the app: Settings > Backend.
# The address changes every time this script restarts. Stop it with Ctrl-C when done.
# Needs cloudflared (brew install cloudflared) and DEMO_TOKEN in backend/.env.
set -e
cd "$(dirname "$0")/../backend"
TOKEN=$(grep -E '^DEMO_TOKEN=' .env 2>/dev/null | tail -1 | cut -d= -f2-)
if [ -z "$TOKEN" ]; then
  echo "DEMO_TOKEN is not set in backend/.env. Set it first: without it anyone with the"
  echo "tunnel address could read building data. Then restart the backend."
  exit 1
fi
if ! curl -s -m 3 "http://localhost:${PORT:-8000}/health" | grep -q '"token_required":true'; then
  echo "The backend is not running with the demo token. Start (or restart) scripts/run_backend.sh first."
  exit 1
fi
echo "Demo token for the app: $TOKEN"
echo "Starting tunnel. Look for the https://....trycloudflare.com address below."
exec cloudflared tunnel --url "http://localhost:${PORT:-8000}"

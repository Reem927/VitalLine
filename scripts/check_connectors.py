"""Live check of every backend connector against the demo building.

Run from the repo root:
    backend/.venv/bin/python scripts/check_connectors.py

Prints counts and statuses only, never keys or sponsor values. Needs
backend/config/demo_building.local.json (gitignored).
"""

import asyncio
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

from app.config import demo_config
from connectors import costar_kit, matterport, nws, valhalla, vexcel, wolfram


async def step(name, coro):
    t = time.perf_counter()
    try:
        result = await coro
        print(f"ok   {name:<12} {time.perf_counter() - t:5.1f}s  {result}")
    except Exception as e:  # noqa: BLE001
        print(f"FAIL {name:<12} {time.perf_counter() - t:5.1f}s  {type(e).__name__}: {str(e)[:120]}")


async def main():
    scans = demo_config()["primary"]["matterport"]

    async def mp():
        m = await matterport.layout(scans["concierge_entrance_stairs"])
        doors = sum(o["type"] == "doorway" for f in m["floors"] for e in f["edges"] for o in e["openings"] or [])
        return f"{len(m['floors'])} floors, {len(m['rooms'])} rooms, {doors} doorways, {len(m['panoLocations'])} scan points"

    async def cs():
        pid = await asyncio.to_thread(costar_kit.property_id_for_model, scans["unit_203"])
        s = await asyncio.to_thread(costar_kit.property_summary, pid)
        return f"linked property found: {pid is not None}, stories={s['stories']}, elevators={s['elevators']}"

    async def location():
        g = (await matterport.layout(scans["concierge_entrance_stairs"]))["geolocation"]
        return float(g["lat"]), float(g["long"])

    lat, lon = await location()

    async def vx():
        v = await vexcel.property_extract(lat, lon)
        return f"available={v['available']}"

    async def vh():
        r = await valhalla.route({"lat": lat + 0.02, "lon": lon + 0.02}, {"lat": lat, "lon": lon})
        return f"{r['distance_km']} km, {len(r['shape'])} shape points, size limits applied={r['vehicle_size_applied']}"

    async def wx():
        return f"{len(await nws.alerts(lat, lon))} active alerts"

    async def wf():
        out = await wolfram.evaluate("Total[{12.5, 30.0, 8.2, 41.3}]")
        return f"{out!r} -> {wolfram.number(out)}"

    for name, coro in [("matterport", mp()), ("costar", cs()), ("vexcel", vx()), ("valhalla", vh()),
                       ("nws", wx()), ("wolfram", wf())]:
        await step(name, coro)


if __name__ == "__main__":
    asyncio.run(main())

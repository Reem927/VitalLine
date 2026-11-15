"""The real scan mesh for the 3D plan view.

Pulls the textured OBJ out of the model's MatterPak (range reads, the zip itself is never
saved), rewrites it into the plan frame the app already uses for the path, and keeps the
result under data/cache/mesh/<building_id>/ (gitignored, deleted after the event).

Plan frame, metres: x = scan X - min_x, y = scan Z - floor height (up), z = max_y - scan Y.
That is a pure rotation and shift, so the mesh, the path and the doors line up.

Faces entirely above the cut height (the ceiling and anything over it) are dropped so the
view reads as a cut-away. Large texture sets are skipped: the mesh is then sent untextured.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import zipfile
from pathlib import Path
from typing import Any

import numpy as np

from app.config import cache_dir
from connectors import matterport
from connectors.costar_kit import _RangeFile
from tools.wolfram import _run

MAX_TEXTURE_BYTES = 40 * 2**20
# Scan textures are 2048 px squares, about 16 MB each once loaded on a phone. They are scaled
# down so a whole scan fits in memory. Bump MESH_VERSION when the output changes: the backend
# rebuilds and the app downloads the new files.
MESH_VERSION = 2
DEFAULT_TEXTURE_PX = 1024
TRIPOD_RANGE_M = (0.9, 1.9)     # scanner height above the floor it stands on
CUT_ABOVE_FLOOR_M = 2.1

BUNDLE_QUERY = """query($id: ID!) { model(id: $id) {
  bundle(id: "mp:matterpak") { availability assets { ... on Resource { format status filename url } } }
} }"""


def mesh_dir(building_id: str) -> Path:
    return cache_dir("mesh") / building_id


def manifest(building_id: str) -> dict[str, Any] | None:
    path = mesh_dir(building_id) / "manifest.json"
    return json.loads(path.read_text()) if path.exists() else None


def _floor_z(z: np.ndarray, ref_z: float) -> float:
    """Height of the floor under a scanner at ref_z: the most common vertex height below it."""
    lo, hi = ref_z - TRIPOD_RANGE_M[1], ref_z - TRIPOD_RANGE_M[0]
    band = z[(z >= lo) & (z <= hi)]
    if band.size < 100:
        return ref_z - 1.4
    counts, edges = np.histogram(band, bins=max(10, int((hi - lo) / 0.02)))
    i = int(counts.argmax())
    return float((edges[i] + edges[i + 1]) / 2)


def _rewrite_obj(text: str, min_x: float, max_y: float, ref_z: float, rise_m: float,
                 textured: bool) -> tuple[str, dict[str, Any]]:
    lines = text.splitlines()
    verts = np.array([[float(p) for p in ln.split()[1:4]] for ln in lines if ln.startswith("v ")])
    floor = _floor_z(verts[:, 2], ref_z)
    cut = floor + rise_m + CUT_ABOVE_FLOOR_M
    out, kept, dropped = [], 0, 0
    for ln in lines:
        if ln.startswith("v "):
            x, y, z = (float(p) for p in ln.split()[1:4])
            out.append(f"v {x - min_x:.3f} {z - floor:.3f} {max_y - y:.3f}")
        elif ln.startswith("vn "):
            x, y, z = (float(p) for p in ln.split()[1:4])
            out.append(f"vn {x:.3f} {z:.3f} {-y:.3f}")
        elif ln.startswith("f "):
            idx = [int(tok.split("/")[0]) for tok in ln.split()[1:]]
            if min(verts[i - 1, 2] for i in idx) > cut:
                dropped += 1
                continue
            kept += 1
            out.append(ln if textured else "f " + " ".join(
                tok.split("/")[0] + ("//" + tok.split("/")[2] if tok.count("/") == 2 else "")
                for tok in ln.split()[1:]))
        elif ln.startswith("mtllib"):
            out.append("mtllib model.mtl")
        elif ln.startswith(("usemtl", "vt ")) and not textured:
            continue
        else:
            out.append(ln)
    if not textured:
        out.insert(0, "usemtl scan")
    return "\n".join(out) + "\n", {"floor_z": floor, "faces": kept, "faces_cut": dropped,
                                   "vertices": len(verts)}


async def _pak_url(model_id: str) -> str | None:
    data = await matterport.query(BUNDLE_QUERY, {"id": model_id}, use_cache=False)
    bundle = (data.get("model") or {}).get("bundle") or {}
    asset = next((a for a in bundle.get("assets") or [] if a.get("url")), None)
    return asset["url"] if asset else None


def _shrink(path: Path, max_px: int) -> None:
    """Scale an image down in place with macOS sips. Left as is where sips is missing."""
    if shutil.which("sips"):
        subprocess.run(["sips", "-Z", str(max_px), str(path)], capture_output=True, check=False)


def build(building_id: str, model_id: str, min_x: float, max_y: float, ref_z: float,
          rise_m: float = 0.0, texture_px: int = DEFAULT_TEXTURE_PX) -> dict[str, Any] | None:
    """Fetch, convert and cache the mesh. Returns its manifest, or None if there is no MatterPak."""
    if (hit := manifest(building_id)) is not None and hit.get("version") == MESH_VERSION:
        return hit
    url = _run(_pak_url(model_id))
    if not url:
        return None
    pak = zipfile.ZipFile(_RangeFile(url))
    obj = next(i for i in pak.infolist() if i.filename.endswith(".obj"))
    mtl = next((i for i in pak.infolist() if i.filename.endswith(".mtl")), None)
    stem = Path(obj.filename).stem
    textures = [i for i in pak.infolist() if i.filename.startswith(stem) and i.filename.lower().endswith((".jpg", ".png"))]
    textured = bool(mtl and textures) and sum(i.file_size for i in textures) <= MAX_TEXTURE_BYTES

    out = mesh_dir(building_id)
    out.mkdir(parents=True, exist_ok=True)
    text, stats = _rewrite_obj(pak.read(obj).decode("utf-8", "ignore"), min_x, max_y, ref_z, rise_m, textured)
    (out / "model.obj").write_text(text)
    files = ["model.obj", "model.mtl"]
    if textured:
        (out / "model.mtl").write_bytes(pak.read(mtl))
        for t in textures:
            (out / Path(t.filename).name).write_bytes(pak.read(t))
            _shrink(out / Path(t.filename).name, texture_px)
            files.append(Path(t.filename).name)
    else:
        (out / "model.mtl").write_text("newmtl scan\nKd 0.72 0.76 0.82\nKa 0.2 0.2 0.2\n")
    info = {"building_id": building_id, "version": MESH_VERSION, "texture_px": texture_px,
            "files": files, "textured": textured,
            "bytes": sum((out / f).stat().st_size for f in files), **stats,
            "source": "Matterport MatterPak mesh"}
    (out / "manifest.json").write_text(json.dumps(info))
    return info

"""Clearance checks for moving equipment through a building. Plain geometry, no LLM.

Two checks:
- Elevator car: does the equipment footprint (at its elevator length, plus clearance) fit
  inside the car, straight or rotated up to 45 degrees.
- Door and corner: does it pass a doorway, and can it turn from the doorway into the next
  room. The corner check is the classic "move a rectangle around a right-angle corner"
  problem: a rectangle of width w passes from a passage of width a into width b only if its
  length is at most  min over t in (0, pi/2) of  a/cos t + b/sin t - w/(sin t cos t).
  The verifier recomputes it in Wolfram with FindMinValue. The door opening is treated as
  the first passage, which is conservative: a crew can pivot within the doorway's depth.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from shapely import affinity
from shapely.geometry import box

from rules.equipment import ELEVATOR_CLEARANCE_IN, Equipment


@dataclass(frozen=True)
class FitResult:
    fits: bool
    angle_deg: float | None    # rotation that fits, None if nothing fits
    margin_in: float           # smallest gap left on the tight axis (negative = short by)
    car: str                   # "80 x 54 in"


def fits_in_car(equipment: Equipment, car_depth_in: float, car_width_in: float) -> FitResult:
    """Try the footprint (plus clearance) straight and at angles up to 45 degrees."""
    c = ELEVATOR_CLEARANCE_IN
    length = equipment.elevator_length_in
    car = box(0, 0, car_depth_in, car_width_in)
    item = box(0, 0, length + 2 * c, equipment.width_in + 2 * c)
    margin = min(car_depth_in - (length + 2 * c), car_width_in - (equipment.width_in + 2 * c))
    label = f"{car_depth_in:g} x {car_width_in:g} in"

    for angle in range(0, 46, 5):
        rotated = affinity.rotate(item, angle, origin="centroid")
        minx, miny, maxx, maxy = rotated.bounds
        placed = affinity.translate(
            rotated,
            xoff=(car_depth_in - (maxx - minx)) / 2 - minx,
            yoff=(car_width_in - (maxy - miny)) / 2 - miny,
        )
        if car.contains(placed):
            return FitResult(True, float(angle), round(margin, 1), label)
    return FitResult(False, None, round(margin, 1), label)


def door_fit(door_width_m: float, equipment_width_m: float) -> dict:
    margin = door_width_m - equipment_width_m
    return {"passes": margin >= 0, "margin_m": margin}


def max_length_around_corner(a: float, b: float, w: float, steps: int = 20000) -> float:
    """Longest rectangle of width w that turns from width a into width b. 0 if it cannot."""
    if w >= a or w >= b:
        return 0.0
    best = math.inf
    for i in range(1, steps):
        t = (math.pi / 2) * i / steps
        s, c = math.sin(t), math.cos(t)
        best = min(best, a / c + b / s - w / (s * c))
    return max(best, 0.0)


def corner_fit(a: float, b: float, w: float, length: float) -> dict:
    limit = max_length_around_corner(a, b, w)
    return {
        "passes": length <= limit,
        "max_length_m": limit,
        "wolfram": (f"FindMinValue[{a:.4f} Sec[t] + {b:.4f} Csc[t] - {w:.4f} Sec[t] Csc[t], "
                    f"{{t, Pi/4, 0.001, Pi/2 - 0.001}}]"),
    }

"""Does a piece of equipment fit inside an elevator car? Plain geometry, no LLM."""

from __future__ import annotations

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
    car = box(0, 0, car_depth_in, car_width_in)
    item = box(0, 0, equipment.length_in + 2 * c, equipment.width_in + 2 * c)
    margin = min(car_depth_in - (equipment.length_in + 2 * c),
                 car_width_in - (equipment.width_in + 2 * c))
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

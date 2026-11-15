"""Hard rules: equipment sizes and movement speeds. One file for the planner and the scan graph.

Sizes are published specs:
- Stretcher: Stryker Power-PRO XT spec sheet. Standard length 81 in, minimum length 63 in
  (used for elevator fit, head section raised), width 23 in.
  https://www.stryker.com/content/dam/stryker/ems/products/power-proxt/resources/au/Power-PRO%20XT%20Spec%20Sheet-ANZ.pdf
- Stair chair: Stryker Stair-PRO 6252 spec sheet. 20.5 in wide, 28 in deep (handles retracted).
  https://www.stryker.com/content/dam/stryker/ems/products/stairpro/resources/Stair-PRO%20Spec%20Sheet.pdf
- Bariatric stretcher: no published size chosen; its fit is reported as unknown.

Speeds and elevator timing are prototype assumptions, not measured values. They are
labelled as assumptions wherever they reach the app. Every range is (low, high).
"""

from __future__ import annotations

from dataclasses import dataclass

Range = tuple[float, float]
INCH_M = 0.0254


@dataclass(frozen=True)
class Equipment:
    key: str
    label: str
    length_in: float           # footprint for doors and turns
    width_in: float
    walk_speed_mps: Range      # crew moving with this equipment on level floors (assumed)
    can_use_stairs: bool
    stair_seconds_per_floor: Range | None = None   # assumed
    car_length_in: float | None = None             # length when riding an elevator
    source: str = ""

    @property
    def elevator_length_in(self) -> float:
        return self.car_length_in if self.car_length_in is not None else self.length_in


STRETCHER = Equipment(
    key="stretcher",
    label="Stretcher",
    length_in=81.0,
    width_in=23.0,
    walk_speed_mps=(0.73, 0.76),
    can_use_stairs=False,
    car_length_in=63.0,
    source="Stryker Power-PRO XT spec sheet (81 in long, 63 in minimum, 23 in wide)",
)

STAIR_CHAIR = Equipment(
    key="stair_chair",
    label="Stair chair",
    length_in=28.0,
    width_in=20.5,
    walk_speed_mps=(1.0, 1.2),
    can_use_stairs=True,
    stair_seconds_per_floor=(20.0, 28.0),
    source="Stryker Stair-PRO 6252 spec sheet (20.5 x 28 in)",
)

EQUIPMENT = {e.key: e for e in (STRETCHER, STAIR_CHAIR)}

TIMING_SOURCE = "Assumed prototype speeds and elevator timing, not measured"

# Clearance the crew needs around equipment inside a car or doorway, per side (inches).
ELEVATOR_CLEARANCE_IN = 1.0

# Elevator timing: fixed part (doors, call wait at destination) + per floor travelled.
ELEVATOR_BASE_S: Range = (8.0, 22.0)
ELEVATOR_PER_FLOOR_S: Range = (4.0, 6.0)

# Rig height for garage clearance (feet): reference Type III ambulance, 106 in overall
# (Demers MX 164 spec, see rules/vehicle.py), rounded up.
AMBULANCE_HEIGHT_FT = 9.5

# Elevator car size used when a building's car is unknown: CBC 3002.4.3a minimum clear car
# for a stretcher elevator, 80 x 54 in. Labelled as assumed wherever used.
CODE_MIN_CAR_IN = (80.0, 54.0)

# Code default used when a doorway has no width at all (accessible door clear width).
CODE_MIN_DOOR_M = 32 * INCH_M
CODE_MIN_DOOR_SOURCE = "Assumed: 32 in accessible door clear width (code minimum)"

# Matterport fills unmeasured doors with a standard 36 x 80 in size.
PLACEHOLDER_DOOR = (0.9144, 2.032)


def get(name: str) -> dict:
    """Metric view for the scan graph. Unknown sizes stay None."""
    if name == "bariatric":
        return {"label": "Bariatric stretcher", "width_m": None, "length_m": None,
                "stairs_ok": False, "source": "No published size chosen; fit unknown"}
    if name not in EQUIPMENT:
        raise ValueError(f"Unknown equipment {name!r}")
    e = EQUIPMENT[name]
    return {"label": e.label, "width_m": e.width_in * INCH_M, "length_m": e.length_in * INCH_M,
            "stairs_ok": e.can_use_stairs, "source": e.source}

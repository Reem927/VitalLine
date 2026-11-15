"""Hard rules: equipment sizes and movement speeds.

These are prototype assumptions, not measured values. Every range is (low, high).
Change them here only; the planner and the verifier both read from this file.
"""

from __future__ import annotations

from dataclasses import dataclass

Range = tuple[float, float]


@dataclass(frozen=True)
class Equipment:
    key: str
    label: str
    length_in: float           # footprint when it must fit in an elevator car
    width_in: float
    walk_speed_mps: Range      # crew moving with this equipment on level floors
    can_use_stairs: bool
    stair_seconds_per_floor: Range | None = None


STRETCHER = Equipment(
    key="stretcher",
    label="Stretcher",
    length_in=76.0,
    width_in=23.0,
    walk_speed_mps=(0.73, 0.76),
    can_use_stairs=False,
)

STAIR_CHAIR = Equipment(
    key="stair_chair",
    label="Stair chair",
    length_in=36.0,
    width_in=21.0,
    walk_speed_mps=(1.0, 1.2),
    can_use_stairs=True,
    stair_seconds_per_floor=(20.0, 28.0),
)

EQUIPMENT = {e.key: e for e in (STRETCHER, STAIR_CHAIR)}

# Clearance the crew needs around the stretcher inside a car, per side (inches).
ELEVATOR_CLEARANCE_IN = 1.0

# Elevator timing: fixed part (doors, call wait at destination) + per floor travelled.
ELEVATOR_BASE_S: Range = (8.0, 22.0)
ELEVATOR_PER_FLOOR_S: Range = (4.0, 6.0)

# Minimum vertical clearance for the rig to enter a garage level (feet). Type III ambulance.
AMBULANCE_HEIGHT_FT = 9.5

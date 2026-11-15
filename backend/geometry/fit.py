"""Clearance checks for moving equipment through a building. Pure math, no I/O.

The corner check is the classic "move a rectangle around a right-angle corner" problem:
a rectangle of width w passes from a passage of width a into a passage of width b only if
its length is at most  min over t in (0, pi/2) of  a/cos t + b/sin t - w/(sin t cos t).
The verifier recomputes this in Wolfram with FindMinValue.

The door opening is treated as the first passage, which is conservative: a real crew can
pivot within the doorway's depth. Results are labelled approximate.
"""

import math


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

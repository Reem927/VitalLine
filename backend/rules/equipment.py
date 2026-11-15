"""Equipment the crew moves to the patient, with where each size comes from.

Sources:
- Stretcher: IBC 3002.4 (model code) sizes the required elevator for an ambulance stretcher
  of 24 by 84 inches. Used as the stretcher footprint.
- Stair chair: Stryker Stair-PRO 6252 spec sheet, 20.5 in wide, 28 in deep with handles
  retracted, 500 lb rated load.
  https://www.stryker.com/content/dam/stryker/ems/products/stairpro/resources/Stair-PRO%20Spec%20Sheet.pdf
- Bariatric stretcher: no published size chosen yet, so its fit is reported as unknown.
"""

INCH_M = 0.0254

EQUIPMENT = {
    "stretcher": {
        "label": "Ambulance stretcher",
        "width_m": 24 * INCH_M,
        "length_m": 84 * INCH_M,
        "stairs_ok": False,
        "source": "IBC 3002.4 stretcher size (24 x 84 in)",
    },
    "stair_chair": {
        "label": "Stair chair",
        "width_m": 20.5 * INCH_M,
        "length_m": 28 * INCH_M,
        "stairs_ok": True,
        "source": "Stryker Stair-PRO 6252 spec sheet (20.5 x 28 in)",
    },
    "bariatric": {
        "label": "Bariatric stretcher",
        "width_m": None,
        "length_m": None,
        "stairs_ok": False,
        "source": "No published size chosen; fit unknown",
    },
}

# Code default used when a doorway has no width at all (accessible door clear width).
CODE_MIN_DOOR_M = 32 * INCH_M
CODE_MIN_DOOR_SOURCE = "Assumed: 32 in accessible door clear width (code minimum)"

# Matterport fills unmeasured doors with a standard 36 x 80 in size.
PLACEHOLDER_DOOR = (0.9144, 2.032)


def get(name: str) -> dict:
    if name not in EQUIPMENT:
        raise ValueError(f"Unknown equipment {name!r}")
    return EQUIPMENT[name]

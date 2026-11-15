"""Ambulance profile for outdoor routing and turn checks.

These are published figures for a reference vehicle, not the responding agency's unit.
Set VEHICLE_HEIGHT_M, VEHICLE_WIDTH_M and VEHICLE_LENGTH_M in backend/.env to use an
agency's own spec; the plan then says "agency spec" instead of "reference vehicle".

Sources:
- Body: Demers MX 164 Type III dealer listing and brochure (PennCare):
  https://www.penncare.net/?p=69228
  https://www.penncare.net/wp-content/uploads/2023/02/Demers-MX164-T3-Brochure-8.5x11-web.pdf
  Overall height 106 in, overall width 95 in (excludes fenders and mirrors), overall
  length up to 278 in, wheelbase 158 to 159 in. Height can differ by chassis.
- Turning: AASHTO SU-30 design vehicle, the single-unit truck that road designers and
  AutoTURN studies use for this class. TxDOT Roadway Design Manual, control vehicles:
  https://www.txdot.gov/manuals/des/rdw/chapter-4--basic-design-criteria/4-3-traffic-characteristics/4-3-3-control-vehicles.html
  Minimum design turning radius about 42 ft, centerline 38 ft, minimum inside radius 28.4 ft.
  SU-30 is longer than a Type III ambulance, so these turn values are conservative.
"""

from app.config import env

INCH_M = 0.0254
FOOT_M = 0.3048

REFERENCE = {
    "name": "Reference Type III ambulance (Demers MX 164, published spec)",
    "height_in": 106,
    "width_in": 95,
    "length_in": 278,
    "wheelbase_in": 159,
    "width_note": "excludes fenders and mirrors",
    "turn_design_vehicle": "AASHTO SU-30",
    "turn_radius_ft": 42,
    "turn_centerline_radius_ft": 38,
    "turn_inside_radius_ft": 28.4,
}


def profile() -> dict:
    """Vehicle size in metres, with where each number came from."""
    h, w, length = env("VEHICLE_HEIGHT_M"), env("VEHICLE_WIDTH_M"), env("VEHICLE_LENGTH_M")
    turn = {
        "design_vehicle": REFERENCE["turn_design_vehicle"],
        "radius_m": REFERENCE["turn_radius_ft"] * FOOT_M,
        "centerline_radius_m": REFERENCE["turn_centerline_radius_ft"] * FOOT_M,
        "inside_radius_m": REFERENCE["turn_inside_radius_ft"] * FOOT_M,
        "source": "TxDOT Roadway Design Manual, AASHTO SU-30 control vehicle",
    }
    if h and w:
        return {"source": "agency spec", "height_m": float(h), "width_m": float(w),
                "length_m": float(length) if length else None, "turn": turn}
    return {
        "source": REFERENCE["name"],
        "height_m": REFERENCE["height_in"] * INCH_M,
        "width_m": REFERENCE["width_in"] * INCH_M,
        "length_m": REFERENCE["length_in"] * INCH_M,
        "width_note": REFERENCE["width_note"],
        "turn": turn,
    }

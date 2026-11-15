"""Indoor routing: building graph -> fastest usable path -> grouped crew steps with time ranges.

Everything here is deterministic. The agents call these functions as tools; they never
produce distances or times themselves.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field

import networkx as nx

from geometry.fit import FitResult, fits_in_car
from rules.equipment import (
    ELEVATOR_BASE_S,
    ELEVATOR_PER_FLOOR_S,
    STAIR_CHAIR,
    STRETCHER,
    Equipment,
    Range,
)


@dataclass
class Segment:
    """One edge of the path with its time range and the arithmetic behind it."""
    src: str
    dst: str
    kind: str
    seconds: Range
    distance_m: float = 0.0
    floors: int = 0
    lo_expr: str = ""        # arithmetic behind seconds[0], e.g. "12/0.76+15" (re-checked by verifier)
    hi_expr: str = ""


@dataclass
class Step:
    index: int
    text: str
    seconds: Range
    kind: str                # walk | elevator | stairs
    nodes: list[str]
    segments: list[Segment] = field(default_factory=list)

    @property
    def label(self) -> str:
        return f"{round(self.seconds[0])}–{round(self.seconds[1])} s"


@dataclass
class IndoorRoute:
    entrance_id: str
    equipment: Equipment
    vertical: str            # "Elevator 2" / "Stair B"
    vertical_kind: str       # elevator | stairs
    fit: FitResult | None
    steps: list[Step]
    path: list[str]

    @property
    def total_seconds(self) -> Range:
        return (sum(s.seconds[0] for s in self.steps), sum(s.seconds[1] for s in self.steps))

    @property
    def total_minutes(self) -> Range:
        lo, hi = self.total_seconds
        return (round(lo / 60, 1), round(hi / 60, 1))


class NoRoute(Exception):
    """No usable path with the given closures and equipment. Report as unknown, never guess."""


def _segment_time(edge: dict, equipment: Equipment) -> Segment:
    kind = edge["kind"]
    if kind == "walk":
        d = float(edge["distance_m"])
        oh = edge.get("overhead_s", [0, 0])
        v_lo, v_hi = equipment.walk_speed_mps
        lo, hi = d / v_hi + oh[0], d / v_lo + oh[1]
        return Segment(edge["from"], edge["to"], kind, (lo, hi), distance_m=d,
                       lo_expr=f"{d:g}/{v_hi:g}+{oh[0]:g}", hi_expr=f"{d:g}/{v_lo:g}+{oh[1]:g}")
    if kind == "elevator":
        n = int(edge["floors"])
        lo = ELEVATOR_BASE_S[0] + n * ELEVATOR_PER_FLOOR_S[0]
        hi = ELEVATOR_BASE_S[1] + n * ELEVATOR_PER_FLOOR_S[1]
        return Segment(edge["from"], edge["to"], kind, (lo, hi), floors=n,
                       lo_expr=f"{ELEVATOR_BASE_S[0]:g}+{n}*{ELEVATOR_PER_FLOOR_S[0]:g}",
                       hi_expr=f"{ELEVATOR_BASE_S[1]:g}+{n}*{ELEVATOR_PER_FLOOR_S[1]:g}")
    if kind == "stairs":
        n = int(edge["floors"])
        per = equipment.stair_seconds_per_floor
        assert per is not None
        return Segment(edge["from"], edge["to"], kind, (n * per[0], n * per[1]), floors=n,
                       lo_expr=f"{n}*{per[0]:g}", hi_expr=f"{n}*{per[1]:g}")
    raise ValueError(f"unknown edge kind {kind}")


class BuildingGraph:
    def __init__(self, building: dict):
        self.building = building
        self.nodes = {n["id"]: n for n in building["nodes"]}
        self.elevators = {e["id"]: e for e in building["elevators"]}
        self.stairs = {s["id"]: s for s in building["stairs"]}
        self.entrances = {e["id"]: e for e in building["entrances"]}

    def patient_node(self) -> str:
        return next(n["id"] for n in self.building["nodes"] if n.get("patient"))

    def _graph(self, equipment: Equipment, out_of_service: set[str]) -> nx.DiGraph:
        g = nx.DiGraph()
        for edge in self.building["edges"]:
            if edge["kind"] == "elevator":
                car = self.elevators[edge["elevator"]]
                if edge["elevator"] in out_of_service or not car["in_service"]:
                    continue
                if not fits_in_car(equipment, car["car_depth_in"], car["car_width_in"]).fits:
                    continue
            if edge["kind"] == "stairs" and (
                not equipment.can_use_stairs or edge["stair"] in out_of_service
            ):
                continue
            seg = _segment_time(edge, equipment)
            g.add_edge(edge["from"], edge["to"], edge=edge, seg=seg, weight=seg.seconds[1])
        return g

    def route(self, entrance_id: str, equipment: Equipment,
              out_of_service: set[str] = frozenset()) -> IndoorRoute:
        g = self._graph(equipment, set(out_of_service))
        start = self.entrances[entrance_id]["node"]
        goal = self.patient_node()
        try:
            path = nx.shortest_path(g, start, goal, weight="weight")
        except (nx.NetworkXNoPath, nx.NodeNotFound) as exc:
            raise NoRoute(f"no path from {entrance_id} for {equipment.label}") from exc
        return self._to_route(g, path, entrance_id, equipment)

    def best_route(self, out_of_service: set[str] = frozenset(),
                   entrance_id: str | None = None) -> IndoorRoute:
        """Prefer the stretcher; fall back to the stair chair. Fastest upper bound wins."""
        entrances = [entrance_id] if entrance_id else list(self.entrances)
        for equipment in (STRETCHER, STAIR_CHAIR):
            options = []
            for ent in entrances:
                try:
                    options.append(self.route(ent, equipment, out_of_service))
                except NoRoute:
                    continue
            if options:
                return min(options, key=lambda r: r.total_seconds[1])
        raise NoRoute("no usable route with any equipment")

    def _to_route(self, g: nx.DiGraph, path: list[str], entrance_id: str,
                  equipment: Equipment) -> IndoorRoute:
        pairs = list(itertools.pairwise(path))
        edges = [g.edges[a, b]["edge"] for a, b in pairs]
        segs = [g.edges[a, b]["seg"] for a, b in pairs]

        vertical_edge = next(e for e in edges if e["kind"] in ("elevator", "stairs"))
        if vertical_edge["kind"] == "elevator":
            car = self.elevators[vertical_edge["elevator"]]
            fit = fits_in_car(equipment, car["car_depth_in"], car["car_width_in"])
            vertical = car["label"]
            vertical_text = (f"{vertical} (stretcher fits: {fit.car} car)"
                             if equipment is STRETCHER else vertical)
        else:
            fit = None
            vertical = self.stairs[vertical_edge["stair"]]["label"]
            vertical_text = vertical

        goal = self.nodes[path[-1]]

        # Group edges into crew steps: break at checkpoints and at mode changes.
        groups: list[list[int]] = []
        for i, e in enumerate(edges):
            new_group = (
                not groups
                or e["kind"] != edges[i - 1]["kind"]
                or self.nodes[e["from"]].get("checkpoint")
            )
            if new_group:
                groups.append([i])
            else:
                groups[-1].append(i)

        steps: list[Step] = []
        for idx, group in enumerate(groups, start=1):
            g_edges = [edges[i] for i in group]
            g_segs = [segs[i] for i in group]
            dist = sum(s.distance_m for s in g_segs)
            text = g_edges[0]["instruction"].format(
                entrance=f"{entrance_id} entrance",
                vertical=vertical_text,
                floor=goal["floor"],
                distance=f"{dist:g}",
                unit=goal["label"].replace("Unit ", ""),
            )
            steps.append(Step(
                index=idx,
                text=text,
                seconds=(round(sum(s.seconds[0] for s in g_segs), 1),
                         round(sum(s.seconds[1] for s in g_segs), 1)),
                kind=g_edges[0]["kind"],
                nodes=[g_edges[0]["from"]] + [e["to"] for e in g_edges],
                segments=g_segs,
            ))

        return IndoorRoute(
            entrance_id=entrance_id,
            equipment=equipment,
            vertical=vertical,
            vertical_kind=vertical_edge["kind"],
            fit=fit,
            steps=steps,
            path=path,
        )

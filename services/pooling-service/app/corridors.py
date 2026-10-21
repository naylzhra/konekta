"""Corridor identification: which corridor, in which direction, serves a
trip from origin to destination (DESIGN.md §13.1)."""
from dataclasses import dataclass
from typing import Optional

from app.geo import project_onto_path
from app.models import Corridor, Direction, GeoPoint


@dataclass(frozen=True)
class CorridorMatch:
    corridor_id: str
    direction: Direction


def identify_corridor(
    origin: GeoPoint,
    destination: GeoPoint,
    corridors: list[Corridor],
    min_progress_m: float,
) -> Optional[CorridorMatch]:
    """The corridor whose catchment holds both ends of the trip and along
    which the trip makes real progress; ties go to the closest corridor.
    None when no corridor serves the trip."""
    best: Optional[tuple[float, CorridorMatch]] = None
    for corridor in corridors:
        start = project_onto_path(origin, corridor.path)
        end = project_onto_path(destination, corridor.path)
        if start.offset_m > corridor.catchment_m or end.offset_m > corridor.catchment_m:
            continue
        progress = end.along_m - start.along_m
        if abs(progress) < min_progress_m:
            continue
        direction = Direction.FORWARD if progress > 0 else Direction.BACKWARD
        distance = start.offset_m + end.offset_m
        if best is None or distance < best[0]:
            best = (distance, CorridorMatch(corridor_id=corridor.id, direction=direction))
    return None if best is None else best[1]

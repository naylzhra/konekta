"""City-scale geometry helpers.

Distances use haversine; polyline work uses a local equirectangular
projection (metres), accurate to well under 1% across Bandung Raya.
"""
import math
from dataclasses import dataclass

from app.models import GeoPoint

EARTH_RADIUS_M = 6_371_008.8


def haversine_m(a: GeoPoint, b: GeoPoint) -> float:
    phi1, phi2 = math.radians(a.lat), math.radians(b.lat)
    dphi = math.radians(b.lat - a.lat)
    dlambda = math.radians(b.lng - a.lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(min(1.0, h)))


class LocalProjection:
    """Flat x/y metres around a reference point."""

    def __init__(self, origin: GeoPoint) -> None:
        self._lat0 = origin.lat
        self._lng0 = origin.lng
        self._kx = math.radians(1) * EARTH_RADIUS_M * math.cos(math.radians(origin.lat))
        self._ky = math.radians(1) * EARTH_RADIUS_M

    def to_xy(self, point: GeoPoint) -> tuple[float, float]:
        return (point.lng - self._lng0) * self._kx, (point.lat - self._lat0) * self._ky

    def to_point(self, x: float, y: float) -> GeoPoint:
        return GeoPoint(lat=self._lat0 + y / self._ky, lng=self._lng0 + x / self._kx)


@dataclass(frozen=True)
class PathProjection:
    # Distance from the point to the path.
    offset_m: float
    # Distance along the path (from its first vertex) to the closest point.
    along_m: float
    # Index of the path segment holding the closest point.
    segment: int
    # The closest point on the path itself.
    point: GeoPoint


def project_onto_path(point: GeoPoint, path: list[GeoPoint]) -> PathProjection:
    projection = LocalProjection(path[0])
    px, py = projection.to_xy(point)
    vertices = [projection.to_xy(p) for p in path]
    best: tuple[float, float, int, float, float] | None = None
    walked = 0.0
    for index, ((ax, ay), (bx, by)) in enumerate(zip(vertices, vertices[1:])):
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        t = 0.0 if length == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length**2))
        cx, cy = ax + t * dx, ay + t * dy
        offset = math.hypot(px - cx, py - cy)
        if best is None or offset < best[0]:
            best = (offset, walked + t * length, index, cx, cy)
        walked += length
    assert best is not None  # paths have >= 2 vertices
    offset, along, segment, cx, cy = best
    return PathProjection(offset_m=offset, along_m=along, segment=segment, point=projection.to_point(cx, cy))

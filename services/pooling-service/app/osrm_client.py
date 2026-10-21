"""
OSRM client used by the pooling service to snap virtual stop candidates
and demand clusters onto the road network.

TODO(bandung-map-data): currently points at services/osrm-mock via the
OSRM_BASE_URL env var, since we don't have the real Bandung .osm.pbf
extract processed into .osrm files yet. Once a real OSRM instance is
deployed with Bandung map data, just change OSRM_BASE_URL in the
environment/.env — no code changes needed here.
"""
import os
from dataclasses import dataclass

import httpx

from app.models import GeoPoint

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "http://osrm-mock:8000")
OSRM_TIMEOUT_S = 10.0


class OsrmUnavailable(Exception):
    """OSRM could not answer (down, timeout, or no road nearby)."""


@dataclass(frozen=True)
class SnapResult:
    location: GeoPoint
    # How far the point moved to reach the road.
    distance_m: float


async def get_route(coordinates: list[tuple[float, float]], profile: str = "driving") -> dict:
    """
    coordinates: list of (lon, lat) tuples, in OSRM order.
    Returns the raw OSRM-shaped route response — see services/osrm-mock
    for the exact response shape being mimicked.
    """
    coord_str = ";".join(f"{lon},{lat}" for lon, lat in coordinates)
    url = f"{OSRM_BASE_URL}/route/v1/{profile}/{coord_str}"

    async with httpx.AsyncClient(timeout=OSRM_TIMEOUT_S) as client:
        response = await client.get(url, params={"overview": "full", "geometries": "geojson"})
        response.raise_for_status()
        return response.json()


async def snap_to_road(point: GeoPoint, profile: str = "driving") -> SnapResult:
    """Nearest point on the road network (OSRM `/nearest`), so a stop never
    lands in the middle of a block."""
    url = f"{OSRM_BASE_URL}/nearest/v1/{profile}/{point.lng},{point.lat}"
    try:
        async with httpx.AsyncClient(timeout=OSRM_TIMEOUT_S) as client:
            response = await client.get(url, params={"number": 1})
            response.raise_for_status()
            body = response.json()
        waypoint = body["waypoints"][0]
        lng, lat = waypoint["location"]
        return SnapResult(location=GeoPoint(lat=lat, lng=lng), distance_m=float(waypoint["distance"]))
    except (httpx.HTTPError, KeyError, IndexError, ValueError, TypeError) as exc:
        raise OsrmUnavailable(type(exc).__name__) from exc

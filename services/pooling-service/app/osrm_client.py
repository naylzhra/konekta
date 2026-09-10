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

import httpx

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "http://osrm-mock:8000")


async def get_route(coordinates: list[tuple[float, float]], profile: str = "driving") -> dict:
    """
    coordinates: list of (lon, lat) tuples, in OSRM order.
    Returns the raw OSRM-shaped route response — see services/osrm-mock
    for the exact response shape being mimicked.
    """
    coord_str = ";".join(f"{lon},{lat}" for lon, lat in coordinates)
    url = f"{OSRM_BASE_URL}/route/v1/{profile}/{coord_str}"

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(url, params={"overview": "full", "geometries": "geojson"})
        response.raise_for_status()
        return response.json()

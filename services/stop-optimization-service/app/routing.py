"""Driving time between points via an OSRM-compatible `/route` endpoint
(osrm-mock by default; real OSRM needs only OSRM_BASE_URL)."""
import os

import httpx

from app.models import GeoPoint

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "http://osrm-mock:8000")
OSRM_TIMEOUT_S = 10.0


class OsrmUnavailable(Exception):
    """OSRM could not answer (down, timeout, or no route)."""


async def route_duration_s(points: list[GeoPoint]) -> float:
    coordinates = ";".join(f"{p.lng},{p.lat}" for p in points)
    url = f"{OSRM_BASE_URL.rstrip('/')}/route/v1/driving/{coordinates}"
    try:
        async with httpx.AsyncClient(timeout=OSRM_TIMEOUT_S) as client:
            response = await client.get(url, params={"overview": "false"})
            response.raise_for_status()
            body = response.json()
        if body.get("code") != "Ok":
            raise OsrmUnavailable(str(body.get("code")))
        return float(body["routes"][0]["duration"])
    except (httpx.HTTPError, KeyError, IndexError, ValueError, TypeError) as exc:
        raise OsrmUnavailable(type(exc).__name__) from exc

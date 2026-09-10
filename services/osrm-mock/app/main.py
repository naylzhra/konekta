"""
osrm-mock: a lightweight stand-in for a real OSRM routing server.

TODO(bandung-map-data): this is a PLACEHOLDER pending the real Bandung
.osm.pbf extract being processed into .osrm files and a real OSRM instance
being deployed. It mimics OSRM's `/route/v1/{profile}/{coordinates}`
response shape closely enough for pooling-service to develop against
(straight-line path through the given waypoints, fake duration/distance
from haversine distance + an assumed average speed).

Once real OSRM is available, just point OSRM_BASE_URL (see
pooling-service/app/osrm_client.py) at it — no client code changes needed.
"""
import math

from fastapi import FastAPI, HTTPException

app = FastAPI(title="KONEKTA OSRM Mock")

# Rough average urban feeder-vehicle speed, used only to fabricate a
# plausible duration. Not based on real Bandung traffic data.
AVERAGE_SPEED_KMH = 25.0


def haversine_km(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Great-circle distance between two (lon, lat) points, in km."""
    earth_radius_km = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * earth_radius_km * math.asin(math.sqrt(a))


def parse_coordinates(coordinates: str) -> list[tuple[float, float]]:
    """Parse OSRM-style 'lon,lat;lon,lat;...' into a list of (lon, lat)."""
    points = []
    for pair in coordinates.split(";"):
        try:
            lon_str, lat_str = pair.split(",")
            points.append((float(lon_str), float(lat_str)))
        except ValueError as exc:
            raise ValueError(f"Invalid coordinate pair: {pair!r}") from exc
    return points


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "osrm-mock"}


@app.get("/route/v1/{profile}/{coordinates}")
async def route(
    profile: str,
    coordinates: str,
    overview: str = "full",
    geometries: str = "geojson",
) -> dict:
    """
    Mimics OSRM's route endpoint shape:
    https://project-osrm.org/docs/v5.24.0/api/#route-service

    `coordinates` is a semicolon-separated list of "lon,lat" pairs.
    Returns a straight-line path through the waypoints with a
    haversine-based fake distance/duration.
    """
    try:
        points = parse_coordinates(coordinates)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if len(points) < 2:
        raise HTTPException(
            status_code=400, detail="At least two coordinates are required"
        )

    legs = []
    total_distance_m = 0.0
    for (lon1, lat1), (lon2, lat2) in zip(points, points[1:]):
        leg_distance_m = haversine_km(lon1, lat1, lon2, lat2) * 1000
        leg_duration_s = (leg_distance_m / 1000) / AVERAGE_SPEED_KMH * 3600
        legs.append({"distance": leg_distance_m, "duration": leg_duration_s, "steps": []})
        total_distance_m += leg_distance_m

    total_duration_s = (total_distance_m / 1000) / AVERAGE_SPEED_KMH * 3600

    geometry = {
        "type": "LineString",
        "coordinates": [[lon, lat] for lon, lat in points],
    }

    waypoints = [
        {"location": [lon, lat], "name": "", "hint": ""} for lon, lat in points
    ]

    return {
        "code": "Ok",
        "routes": [
            {
                "geometry": geometry,
                "legs": legs,
                "distance": total_distance_m,
                "duration": total_duration_s,
                "weight": total_duration_s,
                "weight_name": "routability",
            }
        ],
        "waypoints": waypoints,
    }

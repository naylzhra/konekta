"""Replace K1 stop-to-stop chords with the actual OSRM road geometry, for
both directions (corridors.path = forward, corridors.return_path = backward).

Snapping each stop to its single nearest road makes OSRM loop around blocks
whenever a stop lands on the wrong carriageway or a one-way side street. So
each stop gets several nearby road candidates, and the cheapest consecutive
chain (drive time plus snap distance) is chosen before routing through it.
"""
import asyncio
import json
import os

import asyncpg
import httpx

from app.db import DATABASE_URL

CANDIDATES_PER_STOP = 6
MAX_SNAP_M = 100
# Seconds of drive time one metre of snap offset is worth.
SNAP_PENALTY_S_PER_M = 1.0
# Moves the feeder makes that OSM cannot route, keyed by (direction, position
# of the stop the leg starts at); see ROUTES.md. After that stop the path runs
# straight through these (lng, lat) points instead of being routed around.
MANUAL_LINKS: dict[tuple[str, int], list[tuple[float, float]]] = {
    # Jalan Merdeka -> left onto Jalan Aceh (turn forbidden in OSM).
    ("forward", 39): [(107.610593, -6.9097), (107.610591, -6.909806), (107.6110, -6.909769)],
    # Jalan Trunojoyo -> east along Jalan Diponegoro to Lapangan Gasibu A
    # (OSM tags part of this stretch highway=construction).
    ("backward", 15): [
        (107.61598, -6.901369), (107.616365, -6.901357), (107.616974, -6.901337),
        (107.617635, -6.901307), (107.618155, -6.901287), (107.618981, -6.901261),
        (107.619302, -6.901193), (107.619919, -6.901174),
    ],
}
# Stops whose coordinate sits off the street the feeder uses (e.g. inside a
# park, nearer to internal paths than to the road): route through this
# (lng, lat) on the right street instead. Keyed by (direction, position).
SNAP_AT = {
    # Balai Kota Bandung: the route passes it on Jalan Wastukencana.
    ("backward", 6): (107.609048, -6.912851),
}
DIRECTIONS = {"forward": "path", "backward": "return_path"}


async def _get(client: httpx.AsyncClient, url: str, **params) -> dict:
    response = await client.get(url, params=params)
    response.raise_for_status()
    body = response.json()
    if body.get("code") != "Ok":
        raise RuntimeError(f"OSRM request failed: {body.get('code')} {body.get('message', '')}")
    return body


def _coords(waypoints: list[dict]) -> str:
    return ";".join(f"{w['location'][0]},{w['location'][1]}" for w in waypoints)


async def _snap_candidates(client, base_url, lng, lat, exact=False) -> list[dict]:
    body = await _get(client, f"{base_url}/nearest/v1/driving/{lng},{lat}",
                      number=1 if exact else CANDIDATES_PER_STOP)
    near = [w for w in body["waypoints"] if w["distance"] <= MAX_SNAP_M]
    return near or body["waypoints"][:1]


async def _best_chain(client, base_url, candidates: list[list[dict]]) -> list[dict]:
    cost = [w["distance"] * SNAP_PENALTY_S_PER_M for w in candidates[0]]
    back: list[list[int]] = []
    for prev, cur in zip(candidates, candidates[1:]):
        both = prev + cur
        body = await _get(
            client, f"{base_url}/table/v1/driving/{_coords(both)}",
            sources=";".join(str(i) for i in range(len(prev))),
            destinations=";".join(str(i) for i in range(len(prev), len(both))),
            hints=";".join(w["hint"] for w in both),
        )
        durations = body["durations"]
        next_cost, next_back = [], []
        for j, waypoint in enumerate(cur):
            def total(i: int) -> float:
                leg = durations[i][j]
                return cost[i] + (leg if leg is not None else float("inf"))
            best = min(range(len(prev)), key=total)
            next_cost.append(total(best) + waypoint["distance"] * SNAP_PENALTY_S_PER_M)
            next_back.append(best)
        cost, back = next_cost, back + [next_back]
    pick = min(range(len(cost)), key=cost.__getitem__)
    chosen = [pick]
    for step in reversed(back):
        pick = step[pick]
        chosen.append(pick)
    return [stop[i] for stop, i in zip(candidates, reversed(chosen))]


async def _route_coords(client, base_url, chain: list[dict]) -> tuple[list[list[float]], float]:
    body = await _get(
        client, f"{base_url}/route/v1/driving/{_coords(chain)}",
        overview="full", geometries="geojson", continue_straight="false",
        hints=";".join(w["hint"] for w in chain),
    )
    route = body["routes"][0]
    return route["geometry"]["coordinates"], route["distance"]


async def _build_path(client, base_url, direction: str, rows) -> tuple[list[list[float]], float]:
    runs: list[list[list[dict]]] = [[]]
    links: list[list[tuple[float, float]]] = []
    for row in rows:
        at = SNAP_AT.get((direction, row["position"]))
        runs[-1].append(await _snap_candidates(client, base_url, *at, exact=True) if at
                        else await _snap_candidates(client, base_url, row["lng"], row["lat"]))
        link = MANUAL_LINKS.get((direction, row["position"]))
        if link:
            runs[-1].append(await _snap_candidates(client, base_url, *link[0], exact=True))
            runs.append([await _snap_candidates(client, base_url, *link[-1], exact=True)])
            links.append(link)
    coordinates: list[list[float]] = []
    distance = 0.0
    for i, run in enumerate(runs):
        if len(run) > 1:
            part, length = await _route_coords(client, base_url, await _best_chain(client, base_url, run))
            coordinates += part
            distance += length
        if i < len(links):
            coordinates += [list(point) for point in links[i]]
    return coordinates, distance


async def main() -> None:
    conn = await asyncpg.connect(DATABASE_URL)
    try:
        base_url = os.getenv("OSRM_BASE_URL", "").rstrip("/")
        if not base_url or "osrm-mock" in base_url:
            raise RuntimeError("OSRM_BASE_URL must point to a real OSRM instance")
        async with httpx.AsyncClient(timeout=120) as client:
            for direction, column in DIRECTIONS.items():
                rows = await conn.fetch(
                    """SELECT position, ST_Y(location::geometry) AS lat,
                              ST_X(location::geometry) AS lng
                       FROM corridor_route_stops
                       WHERE corridor_id = 'K1' AND direction = $1 ORDER BY position""",
                    direction,
                )
                if len(rows) < 2 or any(row["lat"] is None for row in rows):
                    raise RuntimeError(f"K1 {direction} needs located stops")
                coordinates, distance = await _build_path(client, base_url, direction, rows)
                if len(coordinates) < 2:
                    raise RuntimeError("OSRM returned no line geometry")
                await conn.execute(
                    f"UPDATE corridors SET {column} = ST_GeomFromGeoJSON($1)::geography WHERE id = 'K1'",
                    json.dumps({"type": "LineString", "coordinates": coordinates}),
                )
                print(f"Updated K1 {direction} road path with {len(coordinates)} vertices, "
                      f"{distance / 1000:.1f} km")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())

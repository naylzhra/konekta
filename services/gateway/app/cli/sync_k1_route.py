"""Replace K1 stop-to-stop chords with the actual OSRM road geometry."""
import asyncio
import json
import os

import asyncpg
import httpx

from app.db import DATABASE_URL


async def main() -> None:
    conn = await asyncpg.connect(DATABASE_URL)
    try:
        rows = await conn.fetch(
            """SELECT position, ST_Y(location::geometry) AS lat,
                      ST_X(location::geometry) AS lng
               FROM corridor_route_stops
               WHERE corridor_id = 'K1' ORDER BY position"""
        )
        if len(rows) != 51 or any(row["lat"] is None for row in rows):
            raise RuntimeError("K1 must have all 51 located stops")
        coordinates = ";".join(f"{row['lng']},{row['lat']}" for row in rows)
        base_url = os.getenv("OSRM_BASE_URL", "").rstrip("/")
        if not base_url or "osrm-mock" in base_url:
            raise RuntimeError("OSRM_BASE_URL must point to a real OSRM instance")
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.get(
                f"{base_url}/route/v1/driving/{coordinates}",
                params={"overview": "full", "geometries": "geojson"},
            )
            response.raise_for_status()
            body = response.json()
        if body.get("code") != "Ok" or not body.get("routes"):
            raise RuntimeError(f"OSRM route failed: {body.get('code')}")
        geometry = body["routes"][0]["geometry"]
        if geometry.get("type") != "LineString" or len(geometry.get("coordinates", [])) < 2:
            raise RuntimeError("OSRM returned no line geometry")
        await conn.execute(
            "UPDATE corridors SET path = ST_GeomFromGeoJSON($1)::geography WHERE id = 'K1'",
            json.dumps(geometry),
        )
        print(f"Updated K1 road path with {len(geometry['coordinates'])} vertices")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())

import json
from typing import Optional
from uuid import UUID

import asyncpg

from app.feeders.models import AssignedFeeder, CorridorPath, CorridorStops, CorridorWithFeeders, DeviceFeeder, FeederOption, RoutePoint, RouteStop


class FeederRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def list_corridors(self) -> list[CorridorWithFeeders]:
        rows = await self._pool.fetch(
            """
            SELECT c.id AS corridor_id, c.name AS corridor_name, c.is_dummy, c.route_code,
                   f.id, f.number, f.capacity, f.driver_id IS NULL AS available
            FROM corridors c
            JOIN feeders f ON f.corridor_id = c.id
            ORDER BY c.id, f.number
            """
        )
        corridors: dict[str, CorridorWithFeeders] = {}
        for row in rows:
            corridor = corridors.setdefault(
                row["corridor_id"],
                CorridorWithFeeders(id=row["corridor_id"], name=row["corridor_name"],
                                    is_dummy=row["is_dummy"], route_code=row["route_code"], feeders=[]),
            )
            corridor.feeders.append(
                FeederOption(id=row["id"], number=row["number"], capacity=row["capacity"], available=row["available"])
            )
        return list(corridors.values())

    async def route_stops(self, corridor_id: str, direction: str = "forward") -> Optional[CorridorStops]:
        corridor = await self._pool.fetchrow(
            """SELECT id, name, is_dummy, operating_hours, operating_days, fare_from_idr
               FROM corridors WHERE id = $1""",
            corridor_id,
        )
        if corridor is None:
            return None
        rows = await self._pool.fetch(
            """SELECT position, name,
                      ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
               FROM corridor_route_stops WHERE corridor_id = $1 AND direction = $2
               ORDER BY position""",
            corridor_id, direction,
        )
        return CorridorStops(**dict(corridor), items=[RouteStop(**dict(row)) for row in rows])

    async def route_members(self, corridor_id: str) -> list[str]:
        """[corridor_id] plus the corridors sharing its route code: the same
        road to passengers, so their feeders count toward its arrivals."""
        rows = await self._pool.fetch(
            """SELECT c.id FROM corridors c, corridors me
               WHERE me.id = $1
                 AND (c.id = me.id OR (me.route_code IS NOT NULL AND c.route_code = me.route_code))
               ORDER BY c.id = me.id DESC, c.id""",
            corridor_id,
        )
        return [row["id"] for row in rows]

    async def route_progress(
        self, corridor_id: str, direction: str, points: list[tuple[float, float]]
    ) -> Optional[tuple[list[tuple[int, str, Optional[float]]], list[Optional[float]]]]:
        """Distance (m) along [direction]'s corridor line of each route stop
        (position, name, along_m) and of each (lat, lng) point. Distances are
        None without a line; None overall when the corridor doesn't exist."""
        column = "return_path" if direction == "backward" else "path"
        if await self._pool.fetchval("SELECT 1 FROM corridors WHERE id = $1", corridor_id) is None:
            return None
        stops = await self._pool.fetch(
            f"""SELECT s.position, s.name,
                       ST_LineLocatePoint(c.{column}::geometry, s.location::geometry)
                         * ST_Length(c.{column}) AS along_m
                FROM corridor_route_stops s JOIN corridors c ON c.id = s.corridor_id
                WHERE s.corridor_id = $1 AND s.direction = $2
                ORDER BY s.position""",
            corridor_id, direction,
        )
        along: dict[int, float] = {}
        if points:
            rows = await self._pool.fetch(
                f"""SELECT p.ord, ST_LineLocatePoint(c.{column}::geometry,
                              ST_SetSRID(ST_MakePoint(p.lng, p.lat), 4326)) * ST_Length(c.{column}) AS along_m
                    FROM corridors c,
                         unnest($2::float8[], $3::float8[]) WITH ORDINALITY AS p(lat, lng, ord)
                    WHERE c.id = $1 AND c.{column} IS NOT NULL""",
                corridor_id, [lat for lat, _ in points], [lng for _, lng in points],
            )
            along = {row["ord"]: row["along_m"] for row in rows}
        return (
            [(row["position"], row["name"], row["along_m"]) for row in stops],
            [along.get(i + 1) for i in range(len(points))],
        )

    async def route_path(self, corridor_id: str, direction: str = "forward") -> Optional[CorridorPath]:
        column = "return_path" if direction == "backward" else "path"
        row = await self._pool.fetchrow(
            f"SELECT id, ST_AsGeoJSON({column}::geometry) AS geometry FROM corridors WHERE id = $1",
            corridor_id,
        )
        if row is None:
            return None
        coordinates = json.loads(row["geometry"])["coordinates"] if row["geometry"] else []
        return CorridorPath(
            id=row["id"],
            points=[RoutePoint(lat=lat, lng=lng) for lng, lat in coordinates],
        )

    async def get_for_driver(self, driver_id: UUID) -> Optional[AssignedFeeder]:
        row = await self._pool.fetchrow(
            """
            SELECT f.id, f.number, f.capacity, f.corridor_id, c.name AS corridor_name
            FROM feeders f JOIN corridors c ON c.id = f.corridor_id
            WHERE f.driver_id = $1
            """,
            driver_id,
        )
        return AssignedFeeder(**dict(row)) if row else None

    async def get_device(self, device_id: str) -> Optional[DeviceFeeder]:
        row = await self._pool.fetchrow(
            """
            SELECT d.device_id, d.token_hash, d.active, f.driver_id,
                   f.id, f.number, f.capacity, f.corridor_id, c.name AS corridor_name
            FROM feeder_devices d
            JOIN feeders f ON f.id = d.feeder_id
            JOIN corridors c ON c.id = f.corridor_id
            WHERE d.device_id = $1
            """,
            device_id,
        )
        if row is None:
            return None
        return DeviceFeeder(
            device_id=row["device_id"],
            token_hash=row["token_hash"],
            active=row["active"],
            driver_id=row["driver_id"],
            feeder=AssignedFeeder(
                id=row["id"], number=row["number"], capacity=row["capacity"],
                corridor_id=row["corridor_id"], corridor_name=row["corridor_name"],
            ),
        )

    async def occupancy(self, feeder_id: str) -> int:
        # Read-only use of booking's table: seats of passengers on board.
        return await self._pool.fetchval(
            "SELECT COALESCE(SUM(seats), 0) FROM bookings WHERE feeder_id = $1 AND status = 'BOARDED'",
            feeder_id,
        )


async def claim_feeder(conn: asyncpg.Connection, feeder_id: str, driver_id: UUID) -> bool:
    """Assigns an unassigned feeder to the driver. Run inside the
    registration transaction; False if the feeder is unknown or taken."""
    status = await conn.execute(
        "UPDATE feeders SET driver_id = $1 WHERE id = $2 AND driver_id IS NULL",
        driver_id,
        feeder_id,
    )
    return status == "UPDATE 1"


async def upsert_device(conn: asyncpg.Connection, device_id: str, feeder_id: str, token_hash: str) -> None:
    """Registers a device for the feeder, replacing the feeder's previous
    device (and token) if any."""
    async with conn.transaction():
        await conn.execute("DELETE FROM feeder_devices WHERE feeder_id = $1 AND device_id <> $2", feeder_id, device_id)
        await conn.execute(
            """
            INSERT INTO feeder_devices (device_id, feeder_id, token_hash) VALUES ($1, $2, $3)
            ON CONFLICT (device_id) DO UPDATE
                SET feeder_id = EXCLUDED.feeder_id, token_hash = EXCLUDED.token_hash, active = true
            """,
            device_id,
            feeder_id,
            token_hash,
        )

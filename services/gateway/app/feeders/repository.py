from typing import Optional
from uuid import UUID

import asyncpg

from app.feeders.models import AssignedFeeder, CorridorStops, CorridorWithFeeders, FeederOption, RouteStop


class FeederRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def list_corridors(self) -> list[CorridorWithFeeders]:
        rows = await self._pool.fetch(
            """
            SELECT c.id AS corridor_id, c.name AS corridor_name, c.is_dummy,
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
                                    is_dummy=row["is_dummy"], feeders=[]),
            )
            corridor.feeders.append(
                FeederOption(id=row["id"], number=row["number"], capacity=row["capacity"], available=row["available"])
            )
        return list(corridors.values())

    async def route_stops(self, corridor_id: str) -> Optional[CorridorStops]:
        corridor = await self._pool.fetchrow("SELECT id, name, is_dummy FROM corridors WHERE id = $1", corridor_id)
        if corridor is None:
            return None
        rows = await self._pool.fetch(
            """SELECT position, name,
                      ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
               FROM corridor_route_stops WHERE corridor_id = $1 ORDER BY position""",
            corridor_id,
        )
        return CorridorStops(
            id=corridor["id"], name=corridor["name"], is_dummy=corridor["is_dummy"],
            items=[RouteStop(**dict(row)) for row in rows],
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

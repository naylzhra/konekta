# TODO: most of the domain data (virtual_stops, ride_requests, feeder_locations) still doesn't have a schema yet (see infra/db/migrations).
import os
from typing import Optional

import asyncpg

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://konekta:konekta@localhost:5432/konekta")

_pool: Optional[asyncpg.Pool] = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(DATABASE_URL)
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None

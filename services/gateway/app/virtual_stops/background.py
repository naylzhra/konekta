"""Periodically turn qualifying demand into reviewable stop proposals."""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

import asyncpg

from app.virtual_stops import config
from app.virtual_stops.clients import evaluation_client, pooling_client
from app.virtual_stops.service import run_virtual_stops


logger = logging.getLogger(__name__)
_task: asyncio.Task | None = None
_LOCK_KEY = 0x4B4F4E45  # One automatic run across gateway processes.


async def scan_once(pool: asyncpg.Pool, now: datetime | None = None) -> dict | None:
    now = now or datetime.now(timezone.utc)
    start = now - timedelta(days=config.WINDOW_DAYS)
    async with pool.acquire() as conn:
        if not await conn.fetchval("SELECT pg_try_advisory_lock($1)", _LOCK_KEY):
            return None
        try:
            demand = await conn.fetchrow(
                """SELECT count(*)::int AS requests, max(created_at) AS newest
                   FROM trip_plans WHERE created_at >= $1 AND created_at < $2""",
                start, now,
            )
            if demand["requests"] < config.REQUEST_THRESHOLD:
                return None
            last_window_end = await conn.fetchval(
                "SELECT max(window_end) FROM virtual_stop_runs WHERE endpoint = 'pickup' AND triggered_by IS NULL"
            )
            if last_window_end is not None and demand["newest"] <= last_window_end:
                return None
            return await run_virtual_stops(
                pool, pooling_client(), evaluation_client(),
                window_start=start, window_end=now, endpoint="pickup", triggered_by=None,
                pooling_params={
                    "eps_m": config.CLUSTER_RADIUS_M,
                    "min_pts": config.REQUEST_THRESHOLD,
                    "min_unique_users": 1,
                    "min_active_days": 1,
                    "min_temporal_consistency": 0,
                    "slot_minutes": config.SLOT_MINUTES,
                },
                evaluation_params={
                    "min_stop_spacing_m": config.STOP_SPACING_M,
                    "max_shift_m": 0,
                },
            )
        finally:
            await conn.execute("SELECT pg_advisory_unlock($1)", _LOCK_KEY)


async def _scan_forever(pool: asyncpg.Pool) -> None:
    while True:
        try:
            await scan_once(pool)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("automatic virtual stop scan failed")
        await asyncio.sleep(config.SCAN_INTERVAL_S)


def start_background(pool: asyncpg.Pool) -> None:
    global _task
    if config.AUTO_RUN and _task is None:
        _task = asyncio.create_task(_scan_forever(pool))


async def stop_background() -> None:
    global _task
    if _task is not None:
        _task.cancel()
        await asyncio.gather(_task, return_exceptions=True)
        _task = None

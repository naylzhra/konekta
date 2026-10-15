from typing import Optional

import redis.asyncio as redis

from app.bookings.clients import FeederPosition
from app.feeders import config

GEO_KEY = "feeders:geo"


def _position_key(feeder_id: str) -> str:
    return f"feeders:pos:{feeder_id}"


def _rate_key(feeder_id: str) -> str:
    return f"feeders:rate:{feeder_id}"


class RedisFeederPositionProvider:
    def __init__(
        self,
        client: redis.Redis,
        ttl_s: int = config.POSITION_TTL_S,
        min_interval_ms: int = config.MIN_REPORT_INTERVAL_MS,
    ) -> None:
        self._redis = client
        self._ttl_s = ttl_s
        self._min_interval_ms = min_interval_ms

    async def try_acquire_report_slot(self, feeder_id: str) -> bool:
        """False if this feeder already reported within the minimum interval."""
        return bool(await self._redis.set(_rate_key(feeder_id), "1", nx=True, px=self._min_interval_ms))

    async def store(self, position: FeederPosition) -> None:
        async with self._redis.pipeline(transaction=True) as pipe:
            pipe.geoadd(GEO_KEY, [position.lng, position.lat, position.feeder_id])
            pipe.set(_position_key(position.feeder_id), position.model_dump_json(), ex=self._ttl_s)
            await pipe.execute()

    async def remove(self, feeder_id: str) -> None:
        async with self._redis.pipeline(transaction=True) as pipe:
            pipe.zrem(GEO_KEY, feeder_id)
            pipe.delete(_position_key(feeder_id))
            await pipe.execute()

    async def get_last_known(self, feeder_id: str) -> Optional[FeederPosition]:
        raw = await self._redis.get(_position_key(feeder_id))
        return FeederPosition.model_validate_json(raw) if raw is not None else None

    async def nearest(
        self,
        lat: float,
        lng: float,
        radius_m: float,
        corridor_id: Optional[str] = None,
        limit: int = 5,
    ) -> list[FeederPosition]:
        members = await self._redis.geosearch(
            GEO_KEY, longitude=lng, latitude=lat, radius=radius_m, unit="m", sort="ASC"
        )
        if not members:
            return []
        raws = await self._redis.mget([_position_key(member) for member in members])
        stale = [member for member, raw in zip(members, raws) if raw is None]
        if stale:
            await self._redis.zrem(GEO_KEY, *stale)
        positions = [FeederPosition.model_validate_json(raw) for raw in raws if raw is not None]
        if corridor_id is not None:
            positions = [p for p in positions if p.corridor_id == corridor_id]
        return positions[:limit]

# Wiring for live tracking: one process-wide service and Redis client.
from typing import Optional

import redis.asyncio as redis

from app.db import get_pool
from app.feeders import config
from app.feeders.position_store import RedisFeederPositionProvider
from app.feeders.repository import FeederRepository
from app.feeders.service import FeederTrackingService, HubFeederPositionPublisher
from app.websocket.manager import manager

_redis: Optional[redis.Redis] = None
_service: Optional[FeederTrackingService] = None


def get_position_provider() -> RedisFeederPositionProvider:
    """Also what booking's build_feeder_provider() should return for
    FEEDER_PROVIDER=redis (DESIGN.md §11)."""
    global _redis
    if _redis is None:
        _redis = redis.from_url(config.REDIS_URL, decode_responses=True)
    return RedisFeederPositionProvider(_redis)


async def get_feeder_repository() -> FeederRepository:
    return FeederRepository(await get_pool())


async def get_feeder_service() -> FeederTrackingService:
    global _service
    if _service is None:
        _service = FeederTrackingService(
            await get_feeder_repository(),
            get_position_provider(),
            HubFeederPositionPublisher(manager),
        )
    return _service

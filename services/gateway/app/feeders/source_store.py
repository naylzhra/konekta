# Redis state for choosing between the IoT device and the driver app as a
# feeder's location source (FeederTrackingService). Everything here expires on
# its own, so a device or app that goes silent needs no cleanup job.
from typing import Protocol

import redis.asyncio as redis

from app.feeders import config


def _duty_key(driver_id: str) -> str:
    return f"feeders:duty:{driver_id}"


def _iot_streak_key(feeder_id: str) -> str:
    return f"feeders:iot:{feeder_id}"


def _device_rate_key(device_id: str) -> str:
    return f"feeders:rate:device:{device_id}"


class LocationSourceStore(Protocol):
    async def mark_on_duty(self, driver_id: str) -> None: ...

    async def clear_on_duty(self, driver_id: str) -> None: ...

    async def is_on_duty(self, driver_id: str) -> bool: ...

    async def try_acquire_device_slot(self, device_id: str) -> bool: ...

    async def record_valid_fix(self, feeder_id: str) -> int: ...

    async def reset_streak(self, feeder_id: str) -> None: ...

    async def streak(self, feeder_id: str) -> int: ...


class RedisLocationSourceStore:
    def __init__(
        self,
        client: redis.Redis,
        duty_ttl_s: int = config.DUTY_TTL_S,
        iot_fresh_s: int = config.IOT_FRESH_S,
        device_min_interval_ms: int = config.IOT_MIN_REPORT_INTERVAL_MS,
    ) -> None:
        self._redis = client
        self._duty_ttl_s = duty_ttl_s
        self._iot_fresh_s = iot_fresh_s
        self._device_min_interval_ms = device_min_interval_ms

    async def mark_on_duty(self, driver_id: str) -> None:
        await self._redis.set(_duty_key(driver_id), "1", ex=self._duty_ttl_s)

    async def clear_on_duty(self, driver_id: str) -> None:
        await self._redis.delete(_duty_key(driver_id))

    async def is_on_duty(self, driver_id: str) -> bool:
        return bool(await self._redis.exists(_duty_key(driver_id)))

    async def try_acquire_device_slot(self, device_id: str) -> bool:
        return bool(
            await self._redis.set(_device_rate_key(device_id), "1", nx=True, px=self._device_min_interval_ms)
        )

    async def record_valid_fix(self, feeder_id: str) -> int:
        """Extends the run of consecutive valid fixes; the run is lost once no
        valid fix arrives for iot_fresh_s."""
        async with self._redis.pipeline(transaction=True) as pipe:
            pipe.incr(_iot_streak_key(feeder_id))
            pipe.expire(_iot_streak_key(feeder_id), self._iot_fresh_s)
            count, _ = await pipe.execute()
        return int(count)

    async def reset_streak(self, feeder_id: str) -> None:
        await self._redis.delete(_iot_streak_key(feeder_id))

    async def streak(self, feeder_id: str) -> int:
        raw = await self._redis.get(_iot_streak_key(feeder_id))
        return int(raw) if raw is not None else 0

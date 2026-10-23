import logging
from datetime import datetime, timezone
from typing import Optional, Protocol
from uuid import UUID

from fastapi import status

from app.bookings.clients import FeederPosition
from app.feeders import config
from app.feeders.device_tokens import verify_token
from app.feeders.models import (
    AssignedFeeder,
    DevicePositionAccepted,
    DevicePositionReport,
    FeederError,
    FeederErrorCode,
    PositionAccepted,
    PositionReport,
)
from app.feeders.position_store import RedisFeederPositionProvider
from app.feeders.repository import FeederRepository
from app.feeders.source_store import LocationSourceStore
from app.websocket.manager import ConnectionManager

logger = logging.getLogger(__name__)

_PUBLISHED_FIELDS = {"feeder_id", "lat", "lng", "heading", "occupancy", "capacity", "corridor_id", "updated_at"}


def in_service_area(lat: float, lng: float) -> bool:
    min_lat, max_lat, min_lng, max_lng = config.SERVICE_AREA
    return min_lat <= lat <= max_lat and min_lng <= lng <= max_lng


class FeederPositionPublisher(Protocol):
    async def feeder_position(self, position: FeederPosition) -> None: ...


class HubFeederPositionPublisher:
    def __init__(self, hub: ConnectionManager) -> None:
        self._hub = hub

    async def feeder_position(self, position: FeederPosition) -> None:
        payload = position.model_dump(mode="json", include=_PUBLISHED_FIELDS)
        # feeder:<id> for a passenger following their booked feeder,
        # corridor:<id> for the passenger map showing every feeder.
        topics = [f"feeder:{position.feeder_id}"]
        if position.corridor_id is not None:
            topics.append(f"corridor:{position.corridor_id}")
        try:
            for topic in topics:
                await self._hub.publish(topic, "feeder.position", payload)
        except Exception:  # noqa: BLE001 -- position is stored; subscribers catch up on the next report
            logger.exception("failed to publish feeder.position")


class FeederTrackingService:
    def __init__(
        self,
        repository: FeederRepository,
        positions: RedisFeederPositionProvider,
        publisher: FeederPositionPublisher,
        clock=lambda: datetime.now(timezone.utc),
        sources: Optional[LocationSourceStore] = None,
    ) -> None:
        self._repository = repository
        self._positions = positions
        self._publisher = publisher
        self._clock = clock
        # None = driver app is the only source (no IoT devices).
        self._sources = sources

    async def assigned_feeder(self, driver_id: UUID) -> AssignedFeeder:
        feeder = await self._repository.get_for_driver(driver_id)
        if feeder is None:
            raise FeederError(
                FeederErrorCode.NO_FEEDER_ASSIGNED, status.HTTP_404_NOT_FOUND, "No feeder assigned to this driver"
            )
        return feeder

    async def report_position(self, driver_id: UUID, report: PositionReport) -> PositionAccepted:
        if self._sources is not None:
            # The app only reports while the driver is on duty, so any report
            # (even a rejected one) keeps the duty flag alive.
            await self._sources.mark_on_duty(str(driver_id))
        if not in_service_area(report.lat, report.lng):
            raise FeederError(
                FeederErrorCode.OUTSIDE_SERVICE_AREA,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "Position is outside the service area",
            )
        if report.accuracy_m is not None and report.accuracy_m > config.MAX_ACCURACY_M:
            raise FeederError(
                FeederErrorCode.INACCURATE_POSITION,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "Position fix is too inaccurate",
            )
        if not await self._positions.try_acquire_report_slot(str(driver_id)):
            raise FeederError(
                FeederErrorCode.TOO_FREQUENT, status.HTTP_429_TOO_MANY_REQUESTS, "Position reported too frequently"
            )
        feeder = await self._assigned_for_write(driver_id)
        if await self._iot_is_primary(feeder.id):
            # The device's fixes are being published; the app's report is the
            # fallback and needs no action until the device goes quiet.
            return PositionAccepted(feeder_id=feeder.id, updated_at=self._clock())
        position = await self._publish(feeder, report.lat, report.lng, report.heading)
        return PositionAccepted(feeder_id=feeder.id, updated_at=position.updated_at)

    async def report_device_position(
        self, device_id: str, token: str, report: DevicePositionReport
    ) -> DevicePositionAccepted:
        """A fix from the feeder's IoT GPS device. While the driver is on duty
        and the device sends valid fixes, they replace the driver app's
        reports; a missing, stale or invalid fix hands back to the app."""
        if self._sources is None:
            raise RuntimeError("report_device_position needs a LocationSourceStore")
        device = await self._repository.get_device(device_id)
        if device is None or not device.active or not verify_token(token, device.token_hash):
            raise FeederError(FeederErrorCode.INVALID_DEVICE, status.HTTP_401_UNAUTHORIZED, "Invalid device credentials")
        if not await self._sources.try_acquire_device_slot(device.device_id):
            raise FeederError(
                FeederErrorCode.TOO_FREQUENT, status.HTTP_429_TOO_MANY_REQUESTS, "Position reported too frequently"
            )
        feeder = device.feeder

        rejection = self._invalid_device_fix(report)
        if rejection is not None:
            await self._sources.reset_streak(feeder.id)
            raise rejection
        streak = await self._sources.record_valid_fix(feeder.id)

        if device.driver_id is None or not await self._sources.is_on_duty(str(device.driver_id)):
            raise FeederError(FeederErrorCode.OFF_DUTY, status.HTTP_409_CONFLICT, "Feeder's driver is not on duty")
        if streak < config.IOT_RECOVERY_FIXES:
            return DevicePositionAccepted(feeder_id=feeder.id, updated_at=self._clock(), primary=False)
        position = await self._publish(feeder, report.lat, report.lng, report.heading)
        return DevicePositionAccepted(feeder_id=feeder.id, updated_at=position.updated_at, primary=True)

    async def live_feeders(self, corridor_id: Optional[str] = None) -> list[FeederPosition]:
        return await self._positions.list_live(corridor_id)

    async def go_offline(self, driver_id: UUID) -> None:
        feeder = await self._assigned_for_write(driver_id)
        if self._sources is not None:
            await self._sources.clear_on_duty(str(driver_id))
        await self._positions.remove(feeder.id)

    async def _iot_is_primary(self, feeder_id: str) -> bool:
        return self._sources is not None and await self._sources.streak(feeder_id) >= config.IOT_RECOVERY_FIXES

    async def _publish(
        self, feeder: AssignedFeeder, lat: float, lng: float, heading: Optional[float]
    ) -> FeederPosition:
        # Server time, whichever the source, so updated_at never runs
        # backwards when the source switches.
        position = FeederPosition(
            feeder_id=feeder.id,
            lat=lat,
            lng=lng,
            heading=heading,
            occupancy=await self._repository.occupancy(feeder.id),
            capacity=feeder.capacity,
            corridor_id=feeder.corridor_id,
            updated_at=self._clock(),
        )
        await self._positions.store(position)
        await self._publisher.feeder_position(position)
        return position

    def _invalid_device_fix(self, report: DevicePositionReport) -> Optional[FeederError]:
        if not in_service_area(report.lat, report.lng):
            return FeederError(
                FeederErrorCode.OUTSIDE_SERVICE_AREA,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "Position is outside the service area",
            )
        if report.satellites is not None and report.satellites < config.IOT_MIN_SATELLITES:
            return FeederError(FeederErrorCode.NO_FIX, status.HTTP_422_UNPROCESSABLE_ENTITY, "Not enough satellites")
        if report.accuracy_m > config.MAX_ACCURACY_M:
            return FeederError(
                FeederErrorCode.INACCURATE_POSITION,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "Position fix is too inaccurate",
            )
        age_s = (self._clock() - report.recorded_at).total_seconds()
        if age_s > config.IOT_FRESH_S or age_s < -config.IOT_MAX_CLOCK_SKEW_S:
            return FeederError(FeederErrorCode.STALE_FIX, status.HTTP_422_UNPROCESSABLE_ENTITY, "Position fix is stale")
        return None

    async def _assigned_for_write(self, driver_id: UUID) -> AssignedFeeder:
        feeder = await self._repository.get_for_driver(driver_id)
        if feeder is None:
            raise FeederError(
                FeederErrorCode.NO_FEEDER_ASSIGNED, status.HTTP_409_CONFLICT, "No feeder assigned to this driver"
            )
        return feeder

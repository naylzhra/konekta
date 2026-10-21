import logging
from datetime import datetime, timezone
from typing import Optional, Protocol
from uuid import UUID

from fastapi import status

from app.bookings.clients import FeederPosition
from app.feeders import config
from app.feeders.models import AssignedFeeder, FeederError, FeederErrorCode, PositionAccepted, PositionReport
from app.feeders.position_store import RedisFeederPositionProvider
from app.feeders.repository import FeederRepository
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
    ) -> None:
        self._repository = repository
        self._positions = positions
        self._publisher = publisher
        self._clock = clock

    async def assigned_feeder(self, driver_id: UUID) -> AssignedFeeder:
        feeder = await self._repository.get_for_driver(driver_id)
        if feeder is None:
            raise FeederError(
                FeederErrorCode.NO_FEEDER_ASSIGNED, status.HTTP_404_NOT_FOUND, "No feeder assigned to this driver"
            )
        return feeder

    async def report_position(self, driver_id: UUID, report: PositionReport) -> PositionAccepted:
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
        position = FeederPosition(
            feeder_id=feeder.id,
            lat=report.lat,
            lng=report.lng,
            heading=report.heading,
            occupancy=await self._repository.occupancy(feeder.id),
            capacity=feeder.capacity,
            corridor_id=feeder.corridor_id,
            updated_at=self._clock(),
        )
        await self._positions.store(position)
        await self._publisher.feeder_position(position)
        return PositionAccepted(feeder_id=feeder.id, updated_at=position.updated_at)

    async def live_feeders(self, corridor_id: Optional[str] = None) -> list[FeederPosition]:
        return await self._positions.list_live(corridor_id)

    async def go_offline(self, driver_id: UUID) -> None:
        feeder = await self._assigned_for_write(driver_id)
        await self._positions.remove(feeder.id)

    async def _assigned_for_write(self, driver_id: UUID) -> AssignedFeeder:
        feeder = await self._repository.get_for_driver(driver_id)
        if feeder is None:
            raise FeederError(
                FeederErrorCode.NO_FEEDER_ASSIGNED, status.HTTP_409_CONFLICT, "No feeder assigned to this driver"
            )
        return feeder

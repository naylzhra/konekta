# Wiring for the booking service: one process-wide instance, plus the
# background sweep (expiry + feeder-approaching) started from app lifespan.
import asyncio
import logging
from typing import Optional
from uuid import UUID

from fastapi import Depends

from app.auth.dependencies import require_role
from app.bookings import config
from app.bookings.clients import OsrmRoutingClient, build_feeder_provider, build_stop_assigner
from app.bookings.events import HubBookingEventPublisher
from app.bookings.repository import BookingRepository
from app.bookings.service import BookingService
from app.bookings.simulator import BookingSimulator
from app.db import get_pool
from app.websocket.manager import manager

logger = logging.getLogger(__name__)

_service: Optional[BookingService] = None
_simulator: Optional[BookingSimulator] = None
_sweeper: Optional[asyncio.Task] = None


async def get_booking_service() -> BookingService:
    global _service, _simulator
    if _service is None:
        _service = BookingService(
            BookingRepository(await get_pool()),
            build_stop_assigner(),
            build_feeder_provider(),
            OsrmRoutingClient(),
            HubBookingEventPublisher(manager),
        )
        if config.BOOKING_SIMULATOR:
            logger.warning("BOOKING_SIMULATOR=1: demo driver simulator is active")
            _simulator = BookingSimulator(_service)
            _simulator.attach()
    return _service


async def _sweep_forever(service: BookingService) -> None:
    while True:
        try:
            await service.sweep_once()
        except Exception:
            logger.exception("booking sweep failed")
        await asyncio.sleep(config.SWEEP_INTERVAL_S)


async def start_background() -> None:
    global _sweeper
    service = await get_booking_service()
    _sweeper = asyncio.create_task(_sweep_forever(service))


async def stop_background() -> None:
    global _sweeper
    if _sweeper is not None:
        _sweeper.cancel()
        await asyncio.gather(_sweeper, return_exceptions=True)
        _sweeper = None
    if _simulator is not None:
        await _simulator.stop()


require_passenger = require_role("passenger")
require_driver = require_role("driver")


def session_user_id(session: dict) -> UUID:
    return UUID(session["user_id"])


async def passenger_id(session: dict = Depends(require_passenger)) -> UUID:
    return session_user_id(session)

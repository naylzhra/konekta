# Booking -> WS hub (DESIGN.md §5.1). The service only talks to the
# BookingEventPublisher protocol so tests can record events.
import logging
from typing import Protocol
from uuid import UUID

from app.bookings.models import Booking, BookingUpdatedEvent
from app.websocket.manager import ConnectionManager

logger = logging.getLogger(__name__)


class BookingEventPublisher(Protocol):
    async def booking_updated(self, user_id: UUID, booking: Booking) -> None: ...


class HubBookingEventPublisher:
    def __init__(self, hub: ConnectionManager) -> None:
        self._hub = hub

    async def booking_updated(self, user_id: UUID, booking: Booking) -> None:
        event = BookingUpdatedEvent(payload=booking)
        try:
            await self._hub.send_to_user(str(user_id), event.type, event.payload)
        except Exception:  # noqa: BLE001 -- clients resync via GET /bookings/active
            logger.exception("failed to publish booking.updated for booking %s", booking.id)

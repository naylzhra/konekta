# Demo-only stand-in for the driver app (BOOKING_SIMULATOR=1, DESIGN.md §3).
# Drives the same per-stop driver events a real driver would send:
# arrive at pickup -> wait -> depart (non-boarded -> NO_SHOW) -> arrive at
# drop-off (boarded -> COMPLETED). Never enable in production.
import asyncio
import logging

from app.bookings import config
from app.bookings.models import Booking
from app.bookings.service import BookingService
from app.bookings.state_machine import BookingStatus

logger = logging.getLogger(__name__)


class BookingSimulator:
    def __init__(
        self,
        service: BookingService,
        *,
        to_pickup_s: float = config.SIM_TO_PICKUP_S,
        dwell_s: float = config.SIM_DWELL_S,
        ride_s: float = config.SIM_RIDE_S,
        poll_s: float = 1.0,
    ) -> None:
        self._service = service
        self._to_pickup_s = to_pickup_s
        self._dwell_s = dwell_s
        self._ride_s = ride_s
        self._poll_s = poll_s
        self._tasks: set[asyncio.Task] = set()

    def attach(self) -> None:
        self._service.on_confirmed = self.start

    async def start(self, booking: Booking) -> None:
        task = asyncio.create_task(self._run(booking))
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def stop(self) -> None:
        for task in list(self._tasks):
            task.cancel()
        await asyncio.gather(*self._tasks, return_exceptions=True)

    async def _status(self, booking: Booking) -> BookingStatus | None:
        return await self._service.get_status(booking.id)

    async def _run(self, booking: Booking) -> None:
        if booking.pickup_stop is None or booking.dropoff_stop is None or booking.feeder_id is None:
            return
        pickup_id, dropoff_id, feeder_id = booking.pickup_stop.id, booking.dropoff_stop.id, booking.feeder_id
        if pickup_id is None or dropoff_id is None:
            return
        try:
            await asyncio.sleep(self._to_pickup_s)
            await self._service.driver_arrived(pickup_id, feeder_id)

            waited = 0.0
            while waited < self._dwell_s:
                if await self._status(booking) is not BookingStatus.FEEDER_ARRIVING:
                    break
                await asyncio.sleep(self._poll_s)
                waited += self._poll_s
            await self._service.driver_departed(pickup_id, feeder_id)

            if await self._status(booking) is not BookingStatus.BOARDED:
                return
            await asyncio.sleep(self._ride_s)
            await self._service.driver_arrived(dropoff_id, feeder_id)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("simulator failed for booking %s", booking.id)

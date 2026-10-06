# Driver stop events (DESIGN.md §5.6): the driver works per stop, never per
# passenger. Idempotent: repeating an event finds nothing left to update.
#
# TODO: feeder_id is trusted from the body; bind drivers to feeders once a
# driver/feeder assignment exists.
from uuid import UUID

from fastapi import APIRouter, Depends

from app.bookings.dependencies import get_booking_service, require_driver
from app.bookings.models import DriverStopEventRequest, DriverStopEventResult
from app.bookings.service import BookingService

router = APIRouter(prefix="/driver/stops", tags=["driver"], dependencies=[Depends(require_driver)])


@router.post("/{stop_id}/arrived", response_model=DriverStopEventResult)
async def driver_arrived(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
) -> DriverStopEventResult:
    updated = await service.driver_arrived(stop_id, payload.feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)


@router.post("/{stop_id}/departed", response_model=DriverStopEventResult)
async def driver_departed(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
) -> DriverStopEventResult:
    updated = await service.driver_departed(stop_id, payload.feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)

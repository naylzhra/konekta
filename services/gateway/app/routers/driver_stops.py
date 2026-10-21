# Driver stop events (DESIGN.md §5.6): the driver works per stop, never per
# passenger. Idempotent: repeating an event finds nothing left to update.
#
# The feeder is resolved from the authenticated driver's assignment.
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.bookings.dependencies import get_booking_service, require_driver
from app.bookings.models import DriverStopEventRequest, DriverStopEventResult
from app.bookings.service import BookingService
from app.db import get_pool

router = APIRouter(prefix="/driver/stops", tags=["driver"], dependencies=[Depends(require_driver)])


async def _assigned_feeder(session: dict) -> str:
    pool = await get_pool()
    feeder_id = await pool.fetchval("SELECT id FROM feeders WHERE driver_id = $1", UUID(session["user_id"]))
    if feeder_id is None:
        raise HTTPException(status_code=404, detail="No feeder assigned")
    return feeder_id


@router.get("")
async def driver_stops(session: dict = Depends(require_driver)) -> dict:
    feeder_id = await _assigned_feeder(session)
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT stop_id, name, type, phase, SUM(seats)::int AS seats
        FROM (
            SELECT pickup_stop_id AS stop_id, pickup_stop_name AS name,
                   pickup_stop_type::text AS type, 'pickup' AS phase, seats
            FROM bookings WHERE feeder_id = $1 AND status IN ('CONFIRMED', 'FEEDER_ARRIVING')
            UNION ALL
            SELECT dropoff_stop_id, dropoff_stop_name, dropoff_stop_type::text,
                   'dropoff', seats
            FROM bookings WHERE feeder_id = $1 AND status = 'BOARDED'
        ) AS assigned
        WHERE stop_id IS NOT NULL
        GROUP BY stop_id, name, type, phase
        ORDER BY phase DESC, name""",
        feeder_id,
    )
    return {"items": [{"stop_id": str(row["stop_id"]), "name": row["name"],
                       "type": row["type"], "phase": row["phase"], "seats": row["seats"]}
                      for row in rows]}


@router.post("/{stop_id}/arrived", response_model=DriverStopEventResult)
async def driver_arrived(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
    session: dict = Depends(require_driver),
) -> DriverStopEventResult:
    feeder_id = await _assigned_feeder(session)
    if payload.feeder_id != feeder_id:
        raise HTTPException(status_code=403, detail="Feeder does not belong to this driver")
    updated = await service.driver_arrived(stop_id, feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)


@router.post("/{stop_id}/departed", response_model=DriverStopEventResult)
async def driver_departed(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
    session: dict = Depends(require_driver),
) -> DriverStopEventResult:
    feeder_id = await _assigned_feeder(session)
    if payload.feeder_id != feeder_id:
        raise HTTPException(status_code=403, detail="Feeder does not belong to this driver")
    updated = await service.driver_departed(stop_id, feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)

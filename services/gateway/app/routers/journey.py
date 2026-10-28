"""Journey geometry for the authenticated passenger's own booking."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from app.bookings.clients import OsrmRoutingClient
from app.bookings.dependencies import passenger_id
from app.bookings.journey import JourneyResponse, JourneyUnavailable, passenger_journey
from app.bookings.models import GeoPoint
from app.bookings.repository import BookingRepository
from app.db import get_pool


router = APIRouter(tags=["journey"])


@router.get("/bookings/{booking_id}/journey", response_model=JourneyResponse)
async def get_journey(
    booking_id: UUID,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    user_id: UUID = Depends(passenger_id),
    pool=Depends(get_pool),
) -> JourneyResponse:
    if (lat is None) != (lng is None):
        raise HTTPException(422, detail="lat and lng must be supplied together")
    try:
        journey = await passenger_journey(
            BookingRepository(pool), OsrmRoutingClient(), booking_id, user_id,
            GeoPoint(lat=lat, lng=lng) if lat is not None and lng is not None else None,
        )
    except JourneyUnavailable as exc:
        raise HTTPException(503, detail=str(exc)) from exc
    if journey is None:
        raise HTTPException(404, detail="Booking not found")
    return journey

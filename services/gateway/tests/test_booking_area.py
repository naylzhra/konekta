import asyncio
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.bookings.models import ErrorCode, GeoPoint, TripPlanRequest
from app.bookings.service import BookingError, BookingService


def test_outside_bandung_rejected_before_corridor_lookup() -> None:
    stops = AsyncMock()
    service = BookingService(AsyncMock(), stops, AsyncMock(), AsyncMock(), AsyncMock())
    service._require_consent = AsyncMock()

    request = TripPlanRequest(
        origin=GeoPoint(lat=-6.2, lng=106.8),
        destination=GeoPoint(lat=-6.92, lng=107.62),
    )
    with pytest.raises(BookingError) as error:
        asyncio.run(service.plan_trip(uuid4(), request))

    assert error.value.code == ErrorCode.OUTSIDE_SERVICE_AREA
    stops.match_corridor.assert_not_awaited()

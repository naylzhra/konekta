from datetime import datetime, timezone

import httpx
import pytest

from app.bookings import config
from app.bookings.clients import (
    STUB_STOPS,
    OsrmRoutingClient,
    RoutingError,
    StopAssignmentRequest,
    StubFeederPositionProvider,
    StubStopAssigner,
    haversine_m,
)
from app.bookings.models import GeoPoint, StopType
from app.bookings.service import BookingError, compute_fare_idr, decode_cursor, encode_cursor


def test_haversine_known_distance() -> None:
    # 0.01 deg latitude ~ 1.11 km
    assert haversine_m(GeoPoint(lat=-6.90, lng=107.6), GeoPoint(lat=-6.91, lng=107.6)) == pytest.approx(1112, rel=0.01)


async def test_stub_assigner_static_virtual_and_outside() -> None:
    assigner = StubStopAssigner(clock=lambda: datetime(2026, 10, 6, tzinfo=timezone.utc))
    near = await assigner.assign_pickup_stop(StopAssignmentRequest(location=STUB_STOPS[0].location))
    assert near == STUB_STOPS[0]

    far = await assigner.assign_pickup_stop(StopAssignmentRequest(location=GeoPoint(lat=-6.97, lng=107.68)))
    assert far is not None and far.type is StopType.VIRTUAL and far.valid_until is not None

    outside = await assigner.assign_pickup_stop(StopAssignmentRequest(location=GeoPoint(lat=-6.2, lng=106.8)))
    assert outside is None


def test_stub_stops_are_labelled_placeholders() -> None:
    assert all("placeholder" in stop.name for stop in STUB_STOPS)


async def test_stub_feeder_supply_switch() -> None:
    assert len(await StubFeederPositionProvider(supply=True).nearest(-6.9, 107.6, 3000)) == 1
    assert await StubFeederPositionProvider(supply=False).nearest(-6.9, 107.6, 3000) == []


@pytest.mark.parametrize(("distance_m", "expected"), [(0, 2000), (1000, 3000), (1200, 3500), (2500, 4500), (2600, 5000)])
def test_fare_is_rounded_up(distance_m: float, expected: int) -> None:
    assert compute_fare_idr(distance_m) == expected
    assert expected % config.FARE_ROUNDING_IDR == 0


def test_cursor_round_trip_and_garbage() -> None:
    from uuid import uuid4

    from app.bookings.models import Booking
    from app.bookings.state_machine import BookingStatus

    now = datetime(2026, 10, 6, 8, 0, tzinfo=timezone.utc)
    booking = Booking(
        id=uuid4(), status=BookingStatus.COMPLETED, seats=1, fare_estimate_idr=0, version=1,
        created_at=now, updated_at=now,
    )
    assert decode_cursor(encode_cursor(booking)) == (now, booking.id)
    with pytest.raises(BookingError):
        decode_cursor("garbage")


async def test_osrm_client_parses_route_and_maps_errors() -> None:
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        return httpx.Response(200, json={"code": "Ok", "routes": [{"distance": 1500.0, "duration": 216.0}]})

    client = OsrmRoutingClient("http://osrm", transport=httpx.MockTransport(handler))
    result = await client.route([GeoPoint(lat=-6.9, lng=107.6), GeoPoint(lat=-6.91, lng=107.61)])
    assert (result.distance_m, result.duration_s) == (1500.0, 216.0)
    # OSRM order is lon,lat
    assert seen == ["/route/v1/driving/107.6,-6.9;107.61,-6.91"]

    failing = OsrmRoutingClient("http://osrm", transport=httpx.MockTransport(lambda _: httpx.Response(500)))
    with pytest.raises(RoutingError):
        await failing.route([GeoPoint(lat=0, lng=0), GeoPoint(lat=0, lng=1)])

    no_route = OsrmRoutingClient(
        "http://osrm", transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"code": "NoRoute"}))
    )
    with pytest.raises(RoutingError):
        await no_route.route([GeoPoint(lat=0, lng=0), GeoPoint(lat=0, lng=1)])

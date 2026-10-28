"""Driver navigation: target choice and OSRM maneuver parsing."""
import httpx

from app.bookings.clients import OsrmRoutingClient
from app.bookings.models import GeoPoint
from app.routers.driver_stops import NavStop, stops_ahead


def _stop(stop_id: str) -> NavStop:
    return NavStop(stop_id=stop_id, name=stop_id, type="static", lat=-6.9, lng=107.6)


def test_stops_ahead_orders_by_route_and_skips_passed_stops() -> None:
    stops = [(900.0, _stop("c")), (100.0, _stop("a")), (500.0, _stop("b"))]
    assert [s.stop_id for s in stops_ahead(stops, 0)] == ["a", "b", "c"]
    # Just past "a" (within PASSED_M counts as reached, not ahead).
    assert [s.stop_id for s in stops_ahead(stops, 95)] == ["b", "c"]
    # Beyond the last stop the terminal stays the target.
    assert [s.stop_id for s in stops_ahead(stops, 2000)] == ["c"]
    assert stops_ahead([], 0) == []


async def test_osrm_client_parses_steps_when_requested() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["steps"] == "true"
        return httpx.Response(200, json={"code": "Ok", "routes": [{
            "distance": 500.0, "duration": 90.0,
            "geometry": {"type": "LineString", "coordinates": [[107.61, -6.91], [107.62, -6.92]]},
            "legs": [{"steps": [
                {"maneuver": {"type": "depart", "location": [107.61, -6.91]},
                 "name": "Jalan Merdeka", "distance": 200.0, "duration": 40.0},
                {"maneuver": {"type": "turn", "modifier": "left", "location": [107.611, -6.9097]},
                 "name": "Jalan Aceh", "distance": 300.0, "duration": 50.0},
            ]}],
        }]})

    client = OsrmRoutingClient("http://osrm", transport=httpx.MockTransport(handler))
    route = await client.route([GeoPoint(lat=-6.91, lng=107.61), GeoPoint(lat=-6.92, lng=107.62)],
                               geometry=True, steps=True)
    assert [(s.type, s.modifier, s.name) for s in route.steps] == [
        ("depart", None, "Jalan Merdeka"), ("turn", "left", "Jalan Aceh")]
    assert route.steps[1].location == GeoPoint(lat=-6.9097, lng=107.611)


async def test_eligible_feeders_match_direction_and_skip_ones_past_pickup() -> None:
    from datetime import datetime, timezone
    from uuid import uuid4

    from app.bookings.clients import FeederPosition
    from app.bookings.models import Stop, StopType
    from app.bookings.service import BookingService

    now = datetime.now(timezone.utc)

    def feeder(feeder_id, lat, direction, occupancy=0):
        return FeederPosition(feeder_id=feeder_id, lat=lat, lng=107.61, capacity=8, occupancy=occupancy,
                              corridor_id="K1", direction=direction, updated_at=now)

    fleet = [
        feeder("ahead", -6.900, "forward"),     # already past the pickup
        feeder("behind", -6.940, "forward"),
        feeder("other-way", -6.935, "backward"),
        feeder("legacy", -6.930, None),          # no direction reported: forward
        feeder("full", -6.938, "forward", occupancy=8),
    ]
    along = {-6.920: 1000.0, -6.900: 1500.0, -6.940: 200.0, -6.930: 600.0, -6.938: 300.0, -6.935: 900.0}

    class Feeders:
        async def nearest(self, lat, lng, radius_m, corridor_id=None, limit=5):
            return fleet

    class Stops:
        async def progress_m(self, corridor_id, direction, points):
            return [along[p.lat] for p in points]

    service = BookingService.__new__(BookingService)
    service._feeders, service._stops = Feeders(), Stops()
    pickup = Stop(id=uuid4(), type=StopType.STATIC, name="Halte", corridor_id="K1",
                  location=GeoPoint(lat=-6.920, lng=107.61))
    picked = await service._eligible_feeders(pickup, "forward", seats=1)
    assert [f.feeder_id for f in picked] == ["legacy", "behind"]
    assert [f.feeder_id for f in await service._eligible_feeders(pickup, "backward", seats=1)] == ["other-way"]

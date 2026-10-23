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

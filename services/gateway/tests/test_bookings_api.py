import asyncio
from uuid import UUID, uuid4

import httpx
import pytest

from app.bookings import config
from app.bookings.models import CreateBookingRequest
from tests.conftest import PASSENGER_ID, auth

# Near placeholder stop 1 and stop 3 (app/bookings/clients.py STUB_STOPS).
ORIGIN = {"lat": -6.9170, "lng": 107.6185}
DESTINATION = {"lat": -6.8920, "lng": 107.6110}
OUTSIDE_AREA = {"lat": -6.2000, "lng": 106.8000}

P1, P2, DRIVER = "t-passenger", "t-passenger-2", "t-driver"


async def give_consent(client: httpx.AsyncClient, token: str = P1) -> None:
    response = await client.post(
        "/consents",
        json={"purpose": "trip_location", "policy_version": config.CONSENT_POLICY_VERSION, "granted": True},
        headers=auth(token),
    )
    assert response.status_code == 201, response.text


async def plan(client: httpx.AsyncClient, token: str = P1, origin=ORIGIN, destination=DESTINATION) -> dict:
    response = await client.post(
        "/trip-plans", json={"origin": origin, "destination": destination}, headers=auth(token)
    )
    assert response.status_code == 200, response.text
    return response.json()["plans"][0]


async def book(client: httpx.AsyncClient, plan_id: str, token: str = P1, key: str | None = None, seats: int = 1):
    return await client.post(
        "/bookings",
        json={"trip_plan_id": plan_id, "seats": seats},
        headers={**auth(token), "Idempotency-Key": key or str(uuid4())},
    )


async def confirmed_booking(client: httpx.AsyncClient, token: str = P1) -> dict:
    await give_consent(client, token)
    trip = await plan(client, token)
    response = await book(client, trip["id"], token)
    assert response.status_code == 201, response.text
    active = await client.get("/bookings/active", headers=auth(token))
    assert active.json()["status"] == "CONFIRMED"
    return active.json()


async def driver_event(client: httpx.AsyncClient, stop_id: str, kind: str, feeder_id: str) -> httpx.Response:
    return await client.post(f"/driver/stops/{stop_id}/{kind}", json={"feeder_id": feeder_id}, headers=auth(DRIVER))


# --- consent -----------------------------------------------------------------


async def test_plan_requires_consent(client):
    response = await client.post("/trip-plans", json={"origin": ORIGIN, "destination": DESTINATION}, headers=auth(P1))
    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "consent_required"


async def test_withdrawn_or_outdated_consent_blocks(client):
    await give_consent(client)
    await client.post(
        "/consents",
        json={"purpose": "trip_location", "policy_version": config.CONSENT_POLICY_VERSION, "granted": False},
        headers=auth(P1),
    )
    response = await client.post("/trip-plans", json={"origin": ORIGIN, "destination": DESTINATION}, headers=auth(P1))
    assert response.json()["detail"]["code"] == "consent_required"

    await client.post(
        "/consents", json={"purpose": "trip_location", "policy_version": "old", "granted": True}, headers=auth(P1)
    )
    response = await client.post("/trip-plans", json={"origin": ORIGIN, "destination": DESTINATION}, headers=auth(P1))
    assert response.json()["detail"]["code"] == "consent_required"

    consents = (await client.get("/consents", headers=auth(P1))).json()["items"]
    assert len(consents) == 1
    assert consents[0]["policy_version"] == "old" and consents[0]["granted"] is True


# --- trip plans --------------------------------------------------------------


async def test_plan_returns_server_fare_and_static_stops(client):
    await give_consent(client)
    trip = await plan(client)
    assert trip["fare_estimate_idr"] > 0 and trip["fare_estimate_idr"] % config.FARE_ROUNDING_IDR == 0
    assert trip["pickup_stop"]["type"] == "static"
    assert trip["dropoff_stop"]["type"] == "static"
    assert [leg["mode"] for leg in trip["legs"]] == ["walk", "feeder", "walk"]
    assert trip["nearest_feeder_eta_s"] is not None
    assert trip["eta_minutes"] > 0


async def test_plan_far_from_static_stops_gets_virtual_stop(client):
    await give_consent(client)
    trip = await plan(client, origin={"lat": -6.9700, "lng": 107.6800})
    assert trip["pickup_stop"]["type"] == "virtual"
    assert trip["pickup_stop"]["valid_until"] is not None


async def test_plan_outside_area_is_no_route(client):
    await give_consent(client)
    response = await client.post(
        "/trip-plans", json={"origin": OUTSIDE_AREA, "destination": DESTINATION}, headers=auth(P1)
    )
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "no_route"


async def test_plan_too_short_is_no_route(client):
    await give_consent(client)
    response = await client.post("/trip-plans", json={"origin": ORIGIN, "destination": ORIGIN}, headers=auth(P1))
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "no_route"


async def test_plan_routing_down_is_503(client, routing):
    await give_consent(client)
    routing.fail = True
    response = await client.post("/trip-plans", json={"origin": ORIGIN, "destination": DESTINATION}, headers=auth(P1))
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "routing_unavailable"


async def test_driver_cannot_plan(client):
    response = await client.post(
        "/trip-plans", json={"origin": ORIGIN, "destination": DESTINATION}, headers=auth(DRIVER)
    )
    assert response.status_code == 403


# --- create + matching ---------------------------------------------------------


async def test_create_booking_matches_and_publishes_in_order(client, publisher):
    await give_consent(client)
    trip = await plan(client)
    response = await book(client, trip["id"])
    assert response.status_code == 201
    created = response.json()
    assert created["status"] == "REQUESTED"
    assert created["fare_estimate_idr"] == trip["fare_estimate_idr"]

    active = (await client.get("/bookings/active", headers=auth(P1))).json()
    assert active["id"] == created["id"]
    assert active["status"] == "CONFIRMED"
    assert active["version"] == 3
    assert active["feeder_id"] == "stub-feeder-1"
    assert active["eta_to_pickup_s"] is not None
    assert active["pickup_stop"]["name"] == trip["pickup_stop"]["name"]
    assert active["dropoff_stop"]["id"] == trip["dropoff_stop"]["id"]

    booking_id = UUID(created["id"])
    assert publisher.statuses(booking_id) == ["REQUESTED", "MATCHING", "CONFIRMED"]
    assert all(user_id == PASSENGER_ID for user_id, _ in publisher.events)
    versions = [b.version for _, b in publisher.events if b.id == booking_id]
    assert versions == [1, 2, 3]


async def test_create_requires_idempotency_key(client):
    await give_consent(client)
    trip = await plan(client)
    response = await client.post("/bookings", json={"trip_plan_id": trip["id"]}, headers=auth(P1))
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "idempotency_key_required"


async def test_same_key_same_body_returns_same_booking(client, pool):
    await give_consent(client)
    trip = await plan(client)
    first = await book(client, trip["id"], key="tap-1")
    second = await book(client, trip["id"], key="tap-1")
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert await pool.fetchval("SELECT count(*) FROM bookings") == 1


async def test_same_key_different_body_is_409(client):
    await give_consent(client)
    trip = await plan(client)
    await book(client, trip["id"], key="tap-1")
    response = await book(client, trip["id"], key="tap-1", seats=2)
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "idempotency_key_reused"


async def test_concurrent_double_tap_creates_one_booking(client, pool):
    await give_consent(client)
    trip = await plan(client)
    responses = await asyncio.gather(*(book(client, trip["id"], key="double-tap") for _ in range(5)))
    assert sorted(r.status_code for r in responses) == [200, 200, 200, 200, 201]
    assert len({r.json()["id"] for r in responses}) == 1
    assert await pool.fetchval("SELECT count(*) FROM bookings") == 1


async def test_second_active_booking_rejected(client, pool):
    await give_consent(client)
    trip = await plan(client)
    assert (await book(client, trip["id"])).status_code == 201
    response = await book(client, trip["id"])
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "active_booking_exists"
    assert await pool.fetchval("SELECT count(*) FROM bookings") == 1


async def test_concurrent_different_keys_one_wins(client, pool):
    await give_consent(client)
    trip = await plan(client)
    responses = await asyncio.gather(*(book(client, trip["id"]) for _ in range(3)))
    assert sorted(r.status_code for r in responses) == [201, 409, 409]
    assert await pool.fetchval("SELECT count(*) FROM bookings") == 1


async def test_expired_plan_is_410(client, clock):
    await give_consent(client)
    trip = await plan(client)
    clock.advance(config.PLAN_TTL_S + 1)
    response = await book(client, trip["id"])
    assert response.status_code == 410
    assert response.json()["detail"]["code"] == "plan_expired"


async def test_other_users_plan_is_404(client):
    await give_consent(client, P1)
    await give_consent(client, P2)
    trip = await plan(client, P1)
    response = await book(client, trip["id"], token=P2)
    assert response.status_code == 404


async def test_no_supply_fails(client, feeders):
    await give_consent(client)
    trip = await plan(client)
    feeders._supply = False  # noqa: SLF001 -- stub switch
    created = (await book(client, trip["id"])).json()
    assert (await client.get("/bookings/active", headers=auth(P1))).status_code == 204
    history = (await client.get("/bookings", headers=auth(P1))).json()["items"]
    assert history[0]["id"] == created["id"]
    assert history[0]["status"] == "FAILED"


# --- cancel / board --------------------------------------------------------------


async def test_cancel_is_free_and_idempotent(client):
    booking = await confirmed_booking(client)
    first = await client.post(f"/bookings/{booking['id']}/cancel", json={"reason": "ganti rencana"}, headers=auth(P1))
    second = await client.post(f"/bookings/{booking['id']}/cancel", json={}, headers=auth(P1))
    assert first.status_code == second.status_code == 200
    assert first.json()["status"] == "CANCELLED"
    assert first.json()["cancellation_fee_idr"] == config.CANCELLATION_PENALTY_IDR == 0
    assert second.json()["version"] == first.json()["version"]
    assert (await client.get("/bookings/active", headers=auth(P1))).status_code == 204


async def test_cannot_cancel_someone_elses_booking(client):
    booking = await confirmed_booking(client)
    response = await client.post(f"/bookings/{booking['id']}/cancel", json={}, headers=auth(P2))
    assert response.status_code == 404


async def test_boarded_before_feeder_arrives_is_invalid(client):
    booking = await confirmed_booking(client)
    response = await client.post(f"/bookings/{booking['id']}/boarded", headers=auth(P1))
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "invalid_transition"


# --- driver stop events ------------------------------------------------------------


async def test_full_trip_via_driver_stop_events(client, publisher):
    booking = await confirmed_booking(client)
    pickup, dropoff, feeder = booking["pickup_stop"]["id"], booking["dropoff_stop"]["id"], booking["feeder_id"]

    arrived = await driver_event(client, pickup, "arrived", feeder)
    assert arrived.json()["updated_booking_ids"] == [booking["id"]]
    assert (await client.get("/bookings/active", headers=auth(P1))).json()["status"] == "FEEDER_ARRIVING"

    boarded = await client.post(f"/bookings/{booking['id']}/boarded", headers=auth(P1))
    assert boarded.json()["status"] == "BOARDED"
    again = await client.post(f"/bookings/{booking['id']}/boarded", headers=auth(P1))
    assert again.json()["version"] == boarded.json()["version"]

    cancel = await client.post(f"/bookings/{booking['id']}/cancel", json={}, headers=auth(P1))
    assert cancel.status_code == 409

    departed = await driver_event(client, pickup, "departed", feeder)
    assert departed.json()["updated_booking_ids"] == []  # boarded passenger is not a no-show

    done = await driver_event(client, dropoff, "arrived", feeder)
    assert done.json()["updated_booking_ids"] == [booking["id"]]
    assert (await client.get("/bookings/active", headers=auth(P1))).status_code == 204
    assert publisher.statuses(UUID(booking["id"])) == [
        "REQUESTED", "MATCHING", "CONFIRMED", "FEEDER_ARRIVING", "BOARDED", "COMPLETED",
    ]


async def test_driver_departs_without_passenger_is_no_show(client):
    booking = await confirmed_booking(client)
    pickup, feeder = booking["pickup_stop"]["id"], booking["feeder_id"]
    await driver_event(client, pickup, "arrived", feeder)
    departed = await driver_event(client, pickup, "departed", feeder)
    assert departed.json()["updated_booking_ids"] == [booking["id"]]
    history = (await client.get("/bookings", headers=auth(P1))).json()["items"]
    assert history[0]["status"] == "NO_SHOW"
    # repeating the event is a no-op
    assert (await driver_event(client, pickup, "departed", feeder)).json()["updated_booking_ids"] == []


async def test_driver_event_for_other_feeder_does_nothing(client):
    booking = await confirmed_booking(client)
    response = await driver_event(client, booking["pickup_stop"]["id"], "arrived", "some-other-feeder")
    assert response.json()["updated_booking_ids"] == []


async def test_passenger_cannot_send_driver_events(client):
    response = await client.post(f"/driver/stops/{uuid4()}/arrived", json={"feeder_id": "x"}, headers=auth(P1))
    assert response.status_code == 403


# --- reads ---------------------------------------------------------------------------


async def test_active_is_204_when_none(client):
    assert (await client.get("/bookings/active", headers=auth(P1))).status_code == 204


async def test_history_pagination(client):
    await give_consent(client)
    ids = []
    for _ in range(5):
        trip = await plan(client)
        created = (await book(client, trip["id"])).json()
        await client.post(f"/bookings/{created['id']}/cancel", json={}, headers=auth(P1))
        ids.append(created["id"])

    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = (await client.get("/bookings", params=params, headers=auth(P1))).json()
        seen += [item["id"] for item in page["items"]]
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert seen == list(reversed(ids))
    assert (await client.get("/bookings", headers=auth(P2))).json()["items"] == []


async def test_invalid_cursor_is_400(client):
    response = await client.get("/bookings", params={"cursor": "not-a-cursor"}, headers=auth(P1))
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "invalid_cursor"


# --- sweep -----------------------------------------------------------------------------


async def test_sweep_expires_stuck_requests(client, service, clock):
    await give_consent(client)
    trip = await plan(client)
    # create directly through the service, so the background matching step never runs
    request = CreateBookingRequest(trip_plan_id=UUID(trip["id"]))
    booking, _ = await service.create_booking(PASSENGER_ID, request, "no-match")
    await service.sweep_once(clock.now)
    assert (await client.get("/bookings/active", headers=auth(P1))).json()["status"] == "REQUESTED"

    clock.advance(config.MATCHING_TIMEOUT_S + 60)
    await service.sweep_once(clock.now)
    history = (await client.get("/bookings", headers=auth(P1))).json()["items"]
    assert history[0]["id"] == str(booking.id)
    assert history[0]["status"] == "EXPIRED"


async def test_sweep_marks_feeder_approaching_when_close(client, service, feeders):
    booking = await confirmed_booking(client)
    position = await feeders.get_last_known(booking["feeder_id"])
    pickup = booking["pickup_stop"]["location"]
    feeders._last[booking["feeder_id"]] = position.model_copy(  # noqa: SLF001 -- move the stub feeder
        update={"lat": pickup["lat"], "lng": pickup["lng"]}
    )
    await service.sweep_once()
    assert (await client.get("/bookings/active", headers=auth(P1))).json()["status"] == "FEEDER_ARRIVING"


@pytest.mark.parametrize("path", ["/bookings/active", "/bookings"])
async def test_requires_auth(client, path):
    assert (await client.get(path)).status_code == 422  # missing Authorization header
    assert (await client.get(path, headers=auth("bogus"))).status_code == 401

import json
import os
from datetime import datetime, timezone
from typing import AsyncIterator, Optional
from uuid import UUID

import httpx
import pytest

from app.auth import session_store
from app.auth.dependencies import get_current_session
from app.bookings.clients import FeederPosition
from app.feeders.dependencies import get_feeder_service
from app.feeders.models import AssignedFeeder, FeederError, PositionReport
from app.feeders.repository import FeederRepository
from app.feeders.service import FeederTrackingService, HubFeederPositionPublisher
from app.main import app
from app.websocket.manager import ConnectionManager
from tests.conftest import DRIVER_ID, _fake_session, auth

NOW = datetime(2026, 10, 15, 8, 0, tzinfo=timezone.utc)
IN_BANDUNG = {"lat": -6.9175, "lng": 107.6191}
JAKARTA = {"lat": -6.2000, "lng": 106.8000}
FEEDER = AssignedFeeder(id="K1-01", number=1, capacity=8, corridor_id="K1", corridor_name="Koridor 1")


# --- fakes -----------------------------------------------------------------


class FakeRepository:
    def __init__(self, feeder: Optional[AssignedFeeder] = FEEDER, occupancy: int = 2) -> None:
        self.feeder = feeder
        self._occupancy = occupancy

    async def get_for_driver(self, driver_id: UUID) -> Optional[AssignedFeeder]:
        return self.feeder

    async def occupancy(self, feeder_id: str) -> int:
        return self._occupancy


class FakePositions:
    def __init__(self) -> None:
        self.stored: list[FeederPosition] = []
        self.removed: list[str] = []
        self.slot_free = True

    async def try_acquire_report_slot(self, reporter_id: str) -> bool:
        return self.slot_free

    async def store(self, position: FeederPosition) -> None:
        self.stored.append(position)

    async def remove(self, feeder_id: str) -> None:
        self.removed.append(feeder_id)


class RecordingPositionPublisher:
    def __init__(self) -> None:
        self.published: list[FeederPosition] = []

    async def feeder_position(self, position: FeederPosition) -> None:
        self.published.append(position)


class FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def accept(self) -> None:
        pass

    async def send_text(self, message: str) -> None:
        self.sent.append(json.loads(message))


@pytest.fixture
def positions() -> FakePositions:
    return FakePositions()


@pytest.fixture
def position_publisher() -> RecordingPositionPublisher:
    return RecordingPositionPublisher()


@pytest.fixture
def tracking(positions, position_publisher) -> FeederTrackingService:
    return FeederTrackingService(FakeRepository(), positions, position_publisher, clock=lambda: NOW)


async def _error_code(call) -> tuple[int, str]:
    with pytest.raises(FeederError) as info:
        await call
    return info.value.status_code, info.value.code.value


# --- service -----------------------------------------------------------------


async def test_report_stores_and_publishes_with_feeder_details(tracking, positions, position_publisher):
    accepted = await tracking.report_position(DRIVER_ID, PositionReport(**IN_BANDUNG, heading=90, accuracy_m=8))

    assert accepted.feeder_id == "K1-01"
    assert accepted.updated_at == NOW
    [stored] = positions.stored
    assert (stored.feeder_id, stored.corridor_id, stored.capacity, stored.occupancy) == ("K1-01", "K1", 8, 2)
    assert (stored.lat, stored.lng, stored.heading) == (IN_BANDUNG["lat"], IN_BANDUNG["lng"], 90)
    assert position_publisher.published == [stored]


async def test_report_outside_service_area_is_rejected(tracking, positions):
    assert await _error_code(tracking.report_position(DRIVER_ID, PositionReport(**JAKARTA))) == (
        422,
        "outside_service_area",
    )
    assert positions.stored == []


async def test_inaccurate_fix_is_rejected(tracking, positions):
    report = PositionReport(**IN_BANDUNG, accuracy_m=500)
    assert await _error_code(tracking.report_position(DRIVER_ID, report)) == (422, "inaccurate_position")
    assert positions.stored == []


async def test_too_frequent_report_is_rejected(tracking, positions):
    positions.slot_free = False
    assert await _error_code(tracking.report_position(DRIVER_ID, PositionReport(**IN_BANDUNG))) == (
        429,
        "too_frequent",
    )
    assert positions.stored == []


async def test_driver_without_feeder_cannot_report_or_go_offline(positions, position_publisher):
    service = FeederTrackingService(FakeRepository(feeder=None), positions, position_publisher)
    assert await _error_code(service.report_position(DRIVER_ID, PositionReport(**IN_BANDUNG))) == (
        409,
        "no_feeder_assigned",
    )
    assert await _error_code(service.go_offline(DRIVER_ID)) == (409, "no_feeder_assigned")
    assert await _error_code(service.assigned_feeder(DRIVER_ID)) == (404, "no_feeder_assigned")


async def test_go_offline_removes_the_drivers_feeder(tracking, positions):
    await tracking.go_offline(DRIVER_ID)
    assert positions.removed == ["K1-01"]


async def test_hub_publisher_sends_contract_payload_to_feeder_topic_subscribers():
    hub = ConnectionManager()
    subscriber, other = FakeSocket(), FakeSocket()
    await hub.connect("s", subscriber, user_id="u1")
    await hub.connect("o", other, user_id="u2")
    hub.subscribe("s", "feeder:K1-01")

    position = FeederPosition(
        feeder_id="K1-01", **IN_BANDUNG, heading=45, occupancy=1, capacity=8, corridor_id="K1", updated_at=NOW
    )
    await HubFeederPositionPublisher(hub).feeder_position(position)

    assert subscriber.sent == [
        {
            "type": "feeder.position",
            "payload": {
                "feeder_id": "K1-01",
                **IN_BANDUNG,
                "heading": 45.0,
                "occupancy": 1,
                "updated_at": "2026-10-15T08:00:00Z",
            },
        }
    ]
    assert other.sent == []


# --- router (no DB/Redis) ------------------------------------------------------


@pytest.fixture
async def feeder_client(tracking) -> AsyncIterator[httpx.AsyncClient]:
    app.dependency_overrides[get_feeder_service] = lambda: tracking
    app.dependency_overrides[get_current_session] = _fake_session
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http:
        yield http
    app.dependency_overrides.clear()


async def test_position_endpoint_accepts_driver_reports(feeder_client, positions):
    response = await feeder_client.post("/feeders/me/position", json=IN_BANDUNG, headers=auth("t-driver"))
    assert response.status_code == 200, response.text
    assert response.json()["feeder_id"] == "K1-01"
    assert len(positions.stored) == 1


async def test_position_endpoint_maps_errors_to_typed_detail(feeder_client):
    response = await feeder_client.post("/feeders/me/position", json=JAKARTA, headers=auth("t-driver"))
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "outside_service_area"


async def test_feeder_endpoints_are_driver_only(feeder_client):
    for method, path in [("POST", "/feeders/me/position"), ("POST", "/feeders/me/offline"), ("GET", "/feeders/me")]:
        response = await feeder_client.request(method, path, json=IN_BANDUNG, headers=auth("t-passenger"))
        assert response.status_code == 403, path


async def test_my_feeder_and_offline_endpoints(feeder_client, positions):
    response = await feeder_client.get("/feeders/me", headers=auth("t-driver"))
    assert response.json() == FEEDER.model_dump()
    response = await feeder_client.post("/feeders/me/offline", headers=auth("t-driver"))
    assert response.status_code == 204
    assert positions.removed == ["K1-01"]


# --- Redis-backed position store -------------------------------------------------

TEST_REDIS_URL = os.getenv("TEST_REDIS_URL")


@pytest.fixture
async def redis_positions():
    if not TEST_REDIS_URL:
        pytest.skip("TEST_REDIS_URL not set; skipping Redis-backed tests")
    if TEST_REDIS_URL.rstrip("/").endswith("/0") or TEST_REDIS_URL.count("/") < 3:
        raise RuntimeError("TEST_REDIS_URL must name a dedicated Redis db index other than 0; it is flushed")
    import redis.asyncio as redis

    from app.feeders.position_store import RedisFeederPositionProvider

    client = redis.from_url(TEST_REDIS_URL, decode_responses=True)
    await client.flushdb()
    yield client, RedisFeederPositionProvider(client, ttl_s=30, min_interval_ms=1000)
    await client.flushdb()
    await client.aclose()


def _position(feeder_id: str, lat: float, lng: float, corridor_id: str = "K1") -> FeederPosition:
    return FeederPosition(
        feeder_id=feeder_id, lat=lat, lng=lng, occupancy=0, capacity=8, corridor_id=corridor_id, updated_at=NOW
    )


async def test_redis_store_and_get_last_known(redis_positions):
    _, store = redis_positions
    await store.store(_position("K1-01", -6.9175, 107.6191))
    assert (await store.get_last_known("K1-01")).lat == pytest.approx(-6.9175)
    assert await store.get_last_known("K1-02") is None


async def test_redis_nearest_orders_by_distance_and_filters(redis_positions):
    _, store = redis_positions
    await store.store(_position("far", -6.9175 + 0.02, 107.6191))  # ~2.2 km
    await store.store(_position("near", -6.9175 + 0.002, 107.6191))  # ~220 m
    await store.store(_position("other-corridor", -6.9175 + 0.001, 107.6191, corridor_id="K2"))
    await store.store(_position("out-of-radius", -6.9175 + 0.05, 107.6191))  # ~5.5 km

    found = await store.nearest(-6.9175, 107.6191, radius_m=3000, corridor_id="K1")
    assert [p.feeder_id for p in found] == ["near", "far"]
    assert [p.feeder_id for p in await store.nearest(-6.9175, 107.6191, radius_m=3000, limit=1)] == [
        "other-corridor"
    ]


async def test_redis_expired_position_is_offline_and_pruned(redis_positions):
    client, store = redis_positions
    await store.store(_position("K1-01", -6.9175, 107.6191))
    await client.delete("feeders:pos:K1-01")  # what TTL expiry does

    assert await store.nearest(-6.9175, 107.6191, radius_m=1000) == []
    assert await client.zscore("feeders:geo", "K1-01") is None


async def test_redis_remove_and_rate_slot(redis_positions):
    _, store = redis_positions
    await store.store(_position("K1-01", -6.9175, 107.6191))
    await store.remove("K1-01")
    assert await store.get_last_known("K1-01") is None

    assert await store.try_acquire_report_slot("driver-1") is True
    assert await store.try_acquire_report_slot("driver-1") is False
    assert await store.try_acquire_report_slot("driver-2") is True


# --- DB-backed: corridors and driver registration ------------------------------


@pytest.fixture
async def feeder_pool(pool, monkeypatch):
    """`pool` truncates users CASCADE, which also empties feeders; re-seed."""
    await pool.execute(
        """
        INSERT INTO corridors (id, name) VALUES ('K1', 'Koridor 1'), ('K2', 'Koridor 2')
            ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
        INSERT INTO feeders (id, corridor_id, number) VALUES ('K1-01', 'K1', 1), ('K1-02', 'K1', 2), ('K2-01', 'K2', 1);
        """
    )
    # /auth/register uses the app-wide pool and a Redis session.
    monkeypatch.setattr("app.db._pool", pool)

    async def fake_create_session(user_id: str, role: str) -> str:
        return f"session-{role}"

    monkeypatch.setattr(session_store, "create_session", fake_create_session)
    return pool


@pytest.fixture
async def http(feeder_pool) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


def _register(phone: str, role: str, feeder_id: Optional[str] = None) -> dict:
    body = {"phone_number": phone, "password": "rahasia-1", "role": role}
    if feeder_id is not None:
        body["feeder_id"] = feeder_id
    return body


async def test_driver_registration_claims_the_feeder(http, feeder_pool):
    response = await http.post("/auth/register", json=_register("+628111", "driver", "K1-02"))
    assert response.status_code == 201, response.text

    user_id = await feeder_pool.fetchval("SELECT id FROM users WHERE phone_number = '+628111'")
    assert await FeederRepository(feeder_pool).get_for_driver(user_id) == AssignedFeeder(
        id="K1-02", number=2, capacity=8, corridor_id="K1", corridor_name="Koridor 1"
    )
    corridors = (await http.get("/corridors")).json()["items"]
    availability = {f["id"]: f["available"] for c in corridors for f in c["feeders"]}
    assert availability == {"K1-01": True, "K1-02": False, "K2-01": True}


async def test_taken_or_unknown_feeder_rolls_back_the_new_user(http, feeder_pool):
    assert (await http.post("/auth/register", json=_register("+628111", "driver", "K1-01"))).status_code == 201

    for phone, feeder_id in [("+628222", "K1-01"), ("+628333", "nope")]:
        response = await http.post("/auth/register", json=_register(phone, "driver", feeder_id))
        assert response.status_code == 409
        assert response.json()["detail"] == "Feeder not available"
        assert await feeder_pool.fetchval("SELECT count(*) FROM users WHERE phone_number = $1", phone) == 0


async def test_feeder_id_is_required_for_drivers_only(http):
    for body in [_register("+628111", "driver"), _register("+628222", "passenger", "K1-01")]:
        response = await http.post("/auth/register", json=body)
        assert response.status_code == 422
        assert response.json()["detail"] == "Feeder is required for drivers only"

    assert (await http.post("/auth/register", json=_register("+628333", "passenger"))).status_code == 201

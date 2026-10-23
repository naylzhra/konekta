import os
from datetime import datetime, timedelta, timezone
from typing import AsyncIterator, Optional
from uuid import UUID

import httpx
import pytest

from app.bookings.clients import FeederPosition
from app.feeders import config
from app.feeders.dependencies import get_feeder_service
from app.feeders.device_tokens import generate_token, hash_token, verify_token
from app.feeders.models import AssignedFeeder, DeviceFeeder, DevicePositionReport, FeederError, PositionReport
from app.feeders.service import FeederTrackingService
from app.main import app
from tests.conftest import DRIVER_ID
from tests.test_feeders import FakePositions, RecordingPositionPublisher

START = datetime(2026, 10, 15, 8, 0, tzinfo=timezone.utc)
PHONE_FIX = {"lat": -6.9175, "lng": 107.6191}
IOT_FIX = {"lat": -6.9180, "lng": 107.6200}
FEEDER = AssignedFeeder(id="K1-01", number=1, capacity=8, corridor_id="K1", corridor_name="Koridor 1")
DEVICE_ID = "esp32-k1-01"
TOKEN = "device-secret-token"


# --- fakes -----------------------------------------------------------------


class Clock:
    def __init__(self) -> None:
        self.now = START

    def __call__(self) -> datetime:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += timedelta(seconds=seconds)


class FakeRepository:
    def __init__(self, device: Optional[DeviceFeeder]) -> None:
        self.device = device

    async def get_for_driver(self, driver_id: UUID) -> Optional[AssignedFeeder]:
        return FEEDER

    async def get_device(self, device_id: str) -> Optional[DeviceFeeder]:
        return self.device if self.device is not None and self.device.device_id == device_id else None

    async def occupancy(self, feeder_id: str) -> int:
        return 0


class FakeSources:
    """In-memory RedisLocationSourceStore: keys expire on the shared clock."""

    def __init__(self, clock: Clock) -> None:
        self._clock = clock
        self._keys: dict[str, tuple[int, datetime]] = {}
        self.device_slot_free = True

    def _get(self, key: str) -> Optional[int]:
        entry = self._keys.get(key)
        if entry is None or entry[1] <= self._clock():
            self._keys.pop(key, None)
            return None
        return entry[0]

    def _set(self, key: str, value: int, ttl_s: float) -> None:
        self._keys[key] = (value, self._clock() + timedelta(seconds=ttl_s))

    async def mark_on_duty(self, driver_id: str) -> None:
        self._set(f"duty:{driver_id}", 1, config.DUTY_TTL_S)

    async def clear_on_duty(self, driver_id: str) -> None:
        self._keys.pop(f"duty:{driver_id}", None)

    async def is_on_duty(self, driver_id: str) -> bool:
        return self._get(f"duty:{driver_id}") is not None

    async def try_acquire_device_slot(self, device_id: str) -> bool:
        return self.device_slot_free

    async def record_valid_fix(self, feeder_id: str) -> int:
        count = (self._get(f"iot:{feeder_id}") or 0) + 1
        self._set(f"iot:{feeder_id}", count, config.IOT_FRESH_S)
        return count

    async def reset_streak(self, feeder_id: str) -> None:
        self._keys.pop(f"iot:{feeder_id}", None)

    async def streak(self, feeder_id: str) -> int:
        return self._get(f"iot:{feeder_id}") or 0


def _device(active: bool = True, driver_id: Optional[UUID] = DRIVER_ID) -> DeviceFeeder:
    return DeviceFeeder(
        device_id=DEVICE_ID, token_hash=hash_token(TOKEN), active=active, feeder=FEEDER, driver_id=driver_id
    )


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def sources(clock) -> FakeSources:
    return FakeSources(clock)


@pytest.fixture
def positions() -> FakePositions:
    return FakePositions()


@pytest.fixture
def published() -> RecordingPositionPublisher:
    return RecordingPositionPublisher()


@pytest.fixture
def repository() -> FakeRepository:
    return FakeRepository(_device())


@pytest.fixture
def tracking(repository, positions, published, clock, sources) -> FeederTrackingService:
    return FeederTrackingService(repository, positions, published, clock=clock, sources=sources)


def _iot(clock: Clock, age_s: float = 1, **overrides) -> DevicePositionReport:
    fields = {**IOT_FIX, "recorded_at": clock() - timedelta(seconds=age_s), "accuracy_m": 5, "satellites": 8}
    return DevicePositionReport(**{**fields, **overrides})


async def _phone(tracking: FeederTrackingService) -> None:
    await tracking.report_position(DRIVER_ID, PositionReport(**PHONE_FIX, accuracy_m=10))


async def _device_fix(tracking: FeederTrackingService, clock: Clock, **overrides):
    return await tracking.report_device_position(DEVICE_ID, TOKEN, _iot(clock, **overrides))


async def _make_iot_primary(tracking: FeederTrackingService, clock: Clock) -> None:
    for _ in range(config.IOT_RECOVERY_FIXES):
        clock.advance(1)
        await _device_fix(tracking, clock)


async def _error(call) -> tuple[int, str]:
    with pytest.raises(FeederError) as info:
        await call
    return info.value.status_code, info.value.code.value


def _source(position: FeederPosition) -> str:
    return "iot" if (position.lat, position.lng) == (IOT_FIX["lat"], IOT_FIX["lng"]) else "phone"


# --- device authentication ----------------------------------------------------


def test_tokens_are_random_and_verified_against_their_hash():
    token = generate_token()
    assert token != generate_token()
    assert len(token) >= 43
    assert verify_token(token, hash_token(token))
    assert not verify_token(token + "x", hash_token(token))


async def test_unknown_device_wrong_token_and_inactive_device_are_rejected_alike(tracking, repository, clock):
    assert await _error(tracking.report_device_position("nope", TOKEN, _iot(clock))) == (401, "invalid_device")
    assert await _error(tracking.report_device_position(DEVICE_ID, "wrong", _iot(clock))) == (401, "invalid_device")
    repository.device = _device(active=False)
    assert await _error(_device_fix(tracking, clock)) == (401, "invalid_device")


async def test_device_of_a_feeder_without_driver_is_off_duty(tracking, repository, positions, clock):
    repository.device = _device(driver_id=None)
    assert await _error(_device_fix(tracking, clock)) == (409, "off_duty")
    assert positions.stored == []


async def test_device_fix_is_ignored_while_driver_is_off_duty(tracking, positions, published, clock):
    assert await _error(_device_fix(tracking, clock)) == (409, "off_duty")
    await _phone(tracking)
    await tracking.go_offline(DRIVER_ID)
    for _ in range(config.IOT_RECOVERY_FIXES + 1):
        clock.advance(1)
        assert await _error(_device_fix(tracking, clock)) == (409, "off_duty")
    assert [_source(p) for p in published.published] == ["phone"]


async def test_too_frequent_device_report_is_rejected(tracking, sources, clock):
    sources.device_slot_free = False
    assert await _error(_device_fix(tracking, clock)) == (429, "too_frequent")


# --- GPS validation -----------------------------------------------------------


@pytest.mark.parametrize(
    ("overrides", "code"),
    [
        ({"lat": 0.0, "lng": 0.0}, "outside_service_area"),  # NEO-6M before its first fix
        ({"lat": 999.0}, "outside_service_area"),
        ({"accuracy_m": 500}, "inaccurate_position"),
        ({"satellites": 2}, "no_fix"),
        ({"age_s": config.IOT_FRESH_S + 1}, "stale_fix"),
        ({"age_s": -(config.IOT_MAX_CLOCK_SKEW_S + 1)}, "stale_fix"),
    ],
)
async def test_invalid_device_fixes_are_rejected(tracking, positions, clock, overrides, code):
    await _phone(tracking)
    assert await _error(_device_fix(tracking, clock, **overrides)) == (422, code)
    assert [_source(p) for p in positions.stored] == ["phone"]


def test_report_model_rejects_malformed_payloads():
    base = {**IOT_FIX, "recorded_at": "2026-10-15T08:00:00Z", "accuracy_m": 5}
    DevicePositionReport(**base)
    for bad in [
        {"recorded_at": "2026-10-15T08:00:00"},  # no timezone
        {"lat": float("nan")},
        {"accuracy_m": -1},
        {"heading": 360},
    ]:
        with pytest.raises(ValueError):
            DevicePositionReport(**{**base, **bad})
    with pytest.raises(ValueError):
        DevicePositionReport(**{k: v for k, v in base.items() if k != "accuracy_m"})


# --- source switching --------------------------------------------------------------


async def test_phone_stays_primary_until_the_device_is_stable(tracking, published, clock):
    await _phone(tracking)
    for _ in range(config.IOT_RECOVERY_FIXES - 1):
        clock.advance(1)
        assert (await _device_fix(tracking, clock)).primary is False
        await _phone(tracking)
    clock.advance(1)
    assert (await _device_fix(tracking, clock)).primary is True

    sources = [_source(p) for p in published.published]
    assert sources == ["phone"] * config.IOT_RECOVERY_FIXES + ["iot"]


async def test_phone_reports_are_not_published_while_iot_is_primary(tracking, positions, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)
    published.published.clear()

    accepted = await tracking.report_position(DRIVER_ID, PositionReport(**PHONE_FIX))
    assert accepted.feeder_id == "K1-01"  # same response contract for the app
    clock.advance(1)
    await _device_fix(tracking, clock)
    assert [_source(p) for p in published.published] == ["iot"]
    assert _source(positions.stored[-1]) == "iot"


async def test_stale_device_falls_back_to_the_phone(tracking, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)

    clock.advance(config.IOT_FRESH_S)  # device went silent
    await _phone(tracking)
    assert _source(published.published[-1]) == "phone"


async def test_invalid_device_fix_falls_back_immediately(tracking, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)

    clock.advance(1)
    with pytest.raises(FeederError):
        await _device_fix(tracking, clock, lat=0.0, lng=0.0)
    await _phone(tracking)
    assert _source(published.published[-1]) == "phone"


async def test_device_still_primary_just_inside_the_freshness_window(tracking, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)
    count = len(published.published)

    clock.advance(config.IOT_FRESH_S - 1)
    await _phone(tracking)
    assert len(published.published) == count


# --- connection recovery ----------------------------------------------------------


async def test_device_regains_primary_after_reconnecting(tracking, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)
    clock.advance(config.IOT_FRESH_S + 5)  # disconnected
    await _phone(tracking)

    results = []
    for _ in range(config.IOT_RECOVERY_FIXES):
        clock.advance(1)
        results.append((await _device_fix(tracking, clock)).primary)
    assert results == [False] * (config.IOT_RECOVERY_FIXES - 1) + [True]
    await _phone(tracking)
    assert _source(published.published[-1]) == "iot"


async def test_gaps_between_fixes_restart_the_recovery_count(tracking, clock):
    await _phone(tracking)
    for _ in range(config.IOT_RECOVERY_FIXES - 1):
        clock.advance(1)
        await _device_fix(tracking, clock)
    clock.advance(config.IOT_FRESH_S)
    await _phone(tracking)
    assert (await _device_fix(tracking, clock)).primary is False


async def test_a_flapping_device_never_becomes_primary(tracking, published, clock):
    await _phone(tracking)
    for _ in range(4):
        for _ in range(config.IOT_RECOVERY_FIXES - 1):
            clock.advance(1)
            await _device_fix(tracking, clock)
        clock.advance(1)
        with pytest.raises(FeederError):
            await _device_fix(tracking, clock, accuracy_m=500)
    assert {_source(p) for p in published.published} == {"phone"}


async def test_device_streaming_before_duty_is_primary_as_duty_starts(tracking, published, clock):
    for _ in range(config.IOT_RECOVERY_FIXES):
        clock.advance(1)
        with pytest.raises(FeederError):
            await _device_fix(tracking, clock)
    await _phone(tracking)  # "Mulai Bertugas"
    assert published.published == []
    clock.advance(1)
    assert (await _device_fix(tracking, clock)).primary is True


async def test_duty_lapses_when_the_app_stops_reporting(tracking, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)
    for _ in range(config.DUTY_TTL_S):
        clock.advance(1)
        try:
            await _device_fix(tracking, clock)
        except FeederError as exc:
            assert exc.code.value == "off_duty"
            break
    else:
        pytest.fail("device kept publishing after the driver app went silent")


# --- real-time consistency ----------------------------------------------------------


async def test_stored_and_published_positions_match_and_never_go_back_in_time(tracking, positions, published, clock):
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)
    clock.advance(config.IOT_FRESH_S)
    await _phone(tracking)
    await _make_iot_primary(tracking, clock)

    assert positions.stored == published.published
    times = [p.updated_at for p in published.published]
    assert times == sorted(times)
    assert all(p.feeder_id == "K1-01" and p.corridor_id == "K1" for p in published.published)


async def test_iot_position_uses_device_heading_and_server_time(tracking, published, clock):
    await _phone(tracking)
    for _ in range(config.IOT_RECOVERY_FIXES):
        clock.advance(1)
        await _device_fix(tracking, clock, heading=270, age_s=2)
    latest = published.published[-1]
    assert (latest.lat, latest.lng, latest.heading) == (IOT_FIX["lat"], IOT_FIX["lng"], 270)
    assert latest.updated_at == clock()


async def test_without_a_source_store_the_phone_flow_is_unchanged(positions, published, clock):
    service = FeederTrackingService(FakeRepository(_device()), positions, published, clock=clock)
    await _phone(service)
    assert len(published.published) == 1
    with pytest.raises(RuntimeError):
        await service.report_device_position(DEVICE_ID, TOKEN, _iot(clock))


# --- router -------------------------------------------------------------------------


@pytest.fixture
async def device_client(tracking) -> AsyncIterator[httpx.AsyncClient]:
    app.dependency_overrides[get_feeder_service] = lambda: tracking
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http:
        yield http
    app.dependency_overrides.clear()


def _body(clock: Clock, **overrides) -> dict:
    return {**IOT_FIX, "recorded_at": clock().isoformat(), "accuracy_m": 4.5, "satellites": 7, **overrides}


def _device_headers(token: str = TOKEN) -> dict[str, str]:
    return {"X-Device-Id": DEVICE_ID, "Authorization": f"Bearer {token}"}


async def test_device_endpoint_accepts_and_reports_primary(device_client, tracking, clock):
    await _phone(tracking)
    for expected in [False] * (config.IOT_RECOVERY_FIXES - 1) + [True]:
        clock.advance(1)
        response = await device_client.post("/devices/position", json=_body(clock), headers=_device_headers())
        assert response.status_code == 200, response.text
        assert response.json()["feeder_id"] == "K1-01"
        assert response.json()["primary"] is expected


async def test_device_endpoint_requires_credentials(device_client, clock):
    response = await device_client.post("/devices/position", json=_body(clock))
    assert response.status_code == 422  # missing headers
    for headers in [_device_headers("wrong"), {"X-Device-Id": DEVICE_ID, "Authorization": TOKEN}]:
        response = await device_client.post("/devices/position", json=_body(clock), headers=headers)
        assert response.status_code == 401
        assert response.json()["detail"]["code"] == "invalid_device"


async def test_device_endpoint_maps_errors_to_typed_detail(device_client, tracking, clock):
    await _phone(tracking)
    response = await device_client.post(
        "/devices/position", json=_body(clock, lat=0, lng=0), headers=_device_headers()
    )
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "outside_service_area"


# --- Redis-backed source store ---------------------------------------------------------

TEST_REDIS_URL = os.getenv("TEST_REDIS_URL")


@pytest.fixture
async def redis_sources():
    if not TEST_REDIS_URL:
        pytest.skip("TEST_REDIS_URL not set; skipping Redis-backed tests")
    if TEST_REDIS_URL.rstrip("/").endswith("/0") or TEST_REDIS_URL.count("/") < 3:
        raise RuntimeError("TEST_REDIS_URL must name a dedicated Redis db index other than 0; it is flushed")
    import redis.asyncio as redis

    from app.feeders.source_store import RedisLocationSourceStore

    client = redis.from_url(TEST_REDIS_URL, decode_responses=True)
    await client.flushdb()
    yield client, RedisLocationSourceStore(client, duty_ttl_s=30, iot_fresh_s=10, device_min_interval_ms=500)
    await client.flushdb()
    await client.aclose()


async def test_redis_streak_counts_expires_and_resets(redis_sources):
    client, store = redis_sources
    assert await store.streak("K1-01") == 0
    assert [await store.record_valid_fix("K1-01") for _ in range(3)] == [1, 2, 3]
    assert 0 < await client.ttl("feeders:iot:K1-01") <= 10
    await store.reset_streak("K1-01")
    assert await store.streak("K1-01") == 0


async def test_redis_duty_flag_and_device_rate_slot(redis_sources):
    client, store = redis_sources
    assert await store.is_on_duty("d1") is False
    await store.mark_on_duty("d1")
    assert await store.is_on_duty("d1") is True
    assert 0 < await client.ttl("feeders:duty:d1") <= 30
    await store.clear_on_duty("d1")
    assert await store.is_on_duty("d1") is False

    assert await store.try_acquire_device_slot("dev") is True
    assert await store.try_acquire_device_slot("dev") is False

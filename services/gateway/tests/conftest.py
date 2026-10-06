# DB-backed fixtures run against a dedicated *_test database that is dropped
# and re-created from infra/db/migrations once per session. Tests that need
# it are skipped unless TEST_DATABASE_URL is set (see README).
import asyncio
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import AsyncIterator
from uuid import UUID

import asyncpg
import httpx
import pytest
from fastapi import Header, HTTPException

from app.auth.dependencies import get_current_session
from app.bookings.clients import (
    RouteResult,
    RoutingError,
    StubFeederPositionProvider,
    StubStopAssigner,
    haversine_m,
)
from app.bookings.dependencies import get_booking_service
from app.bookings.models import Booking, GeoPoint
from app.bookings.repository import BookingRepository
from app.bookings.service import BookingService
from app.main import app

TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")


def _migrations_dir() -> Path:
    if "MIGRATIONS_DIR" in os.environ:
        return Path(os.environ["MIGRATIONS_DIR"])
    # services/gateway/tests -> repo root
    return Path(__file__).resolve().parents[3] / "infra" / "db" / "migrations"


PASSENGER_ID = UUID("00000000-0000-0000-0000-00000000000a")
PASSENGER_2_ID = UUID("00000000-0000-0000-0000-00000000000b")
DRIVER_ID = UUID("00000000-0000-0000-0000-00000000000d")

SESSIONS = {
    "t-passenger": {"user_id": str(PASSENGER_ID), "role": "passenger", "status": "active", "active_trip_id": None},
    "t-passenger-2": {"user_id": str(PASSENGER_2_ID), "role": "passenger", "status": "active", "active_trip_id": None},
    "t-driver": {"user_id": str(DRIVER_ID), "role": "driver", "status": "active", "active_trip_id": None},
}


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _recreate_database(url: str) -> None:
    base, name = url.rsplit("/", 1)
    if not name.endswith("_test"):
        raise RuntimeError("TEST_DATABASE_URL must point at a database whose name ends with _test")
    admin = await asyncpg.connect(f"{base}/postgres")
    try:
        await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        await admin.execute(f'CREATE DATABASE "{name}"')
    finally:
        await admin.close()
    conn = await asyncpg.connect(url)
    try:
        migrations = sorted(_migrations_dir().glob("*.sql"))
        if not migrations:
            raise RuntimeError("No migrations found; set MIGRATIONS_DIR")
        for migration in migrations:
            await conn.execute(migration.read_text(encoding="utf-8"))
    finally:
        await conn.close()


@pytest.fixture(scope="session")
def database_url() -> str:
    if not TEST_DATABASE_URL:
        pytest.skip("TEST_DATABASE_URL not set; skipping DB-backed tests")
    asyncio.run(_recreate_database(TEST_DATABASE_URL))
    return TEST_DATABASE_URL


@pytest.fixture
async def pool(database_url: str) -> AsyncIterator[asyncpg.Pool]:
    pool = await asyncpg.create_pool(database_url, min_size=1, max_size=5)
    await pool.execute("TRUNCATE consent_log, bookings, trip_plans, stops, users CASCADE")
    await pool.executemany(
        "INSERT INTO users (id, phone_number, password_hash, role) VALUES ($1, $2, 'x', $3)",
        [
            (PASSENGER_ID, "+620000000001", "passenger"),
            (PASSENGER_2_ID, "+620000000002", "passenger"),
            (DRIVER_ID, "+620000000003", "driver"),
        ],
    )
    yield pool
    await pool.close()


class FakeClock:
    def __init__(self) -> None:
        self.now = datetime.now(timezone.utc)

    def __call__(self) -> datetime:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += timedelta(seconds=seconds)


class FakeRouting:
    """Straight-line routing at ~25 km/h; no network."""

    def __init__(self) -> None:
        self.fail = False

    async def route(self, points: list[GeoPoint], profile: str = "driving") -> RouteResult:
        if self.fail:
            raise RoutingError("forced failure")
        distance = sum(haversine_m(a, b) for a, b in zip(points, points[1:]))
        return RouteResult(distance_m=distance, duration_s=distance / 7.0)


class RecordingPublisher:
    def __init__(self) -> None:
        self.events: list[tuple[UUID, Booking]] = []

    async def booking_updated(self, user_id: UUID, booking: Booking) -> None:
        self.events.append((user_id, booking))

    def statuses(self, booking_id: UUID) -> list[str]:
        return [booking.status.value for _, booking in self.events if booking.id == booking_id]


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
def publisher() -> RecordingPublisher:
    return RecordingPublisher()


@pytest.fixture
def feeders(clock: FakeClock) -> StubFeederPositionProvider:
    return StubFeederPositionProvider(supply=True, clock=clock)


@pytest.fixture
def routing() -> FakeRouting:
    return FakeRouting()


@pytest.fixture
def service(pool, clock, publisher, feeders, routing) -> BookingService:
    return BookingService(
        BookingRepository(pool),
        StubStopAssigner(clock=clock),
        feeders,
        routing,
        publisher,
        clock=clock,
    )


async def _fake_session(authorization: str = Header(...)) -> dict:
    token = authorization.removeprefix("Bearer ")
    if token not in SESSIONS:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return {**SESSIONS[token], "token": token}


@pytest.fixture
async def client(service: BookingService) -> AsyncIterator[httpx.AsyncClient]:
    app.dependency_overrides[get_booking_service] = lambda: service
    app.dependency_overrides[get_current_session] = _fake_session
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http:
        yield http
    app.dependency_overrides.clear()

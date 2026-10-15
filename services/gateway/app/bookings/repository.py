# Postgres access for booking (asyncpg, raw SQL -- same as app/auth/user_store.py).
# Schema: infra/db/migrations/004_bookings.sql.
import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

import asyncpg

from app.bookings.models import (
    Booking,
    Consent,
    ConsentPurpose,
    GeoPoint,
    Stop,
    StopSnapshot,
    StopType,
    TripLeg,
    TripPlan,
)
from app.bookings.state_machine import ACTIVE_STATUSES, BookingStatus

_ACTIVE_SQL = "(" + ", ".join(f"'{s.value}'" for s in sorted(ACTIVE_STATUSES)) + ")"


class ActiveBookingExists(Exception):
    pass


class DuplicateIdempotencyKey(Exception):
    pass


@dataclass(frozen=True)
class BookingRecord:
    booking: Booking
    user_id: UUID
    request_hash: str

    @property
    def id(self) -> UUID:
        return self.booking.id

    @property
    def status(self) -> BookingStatus:
        return self.booking.status

    @property
    def version(self) -> int:
        return self.booking.version


@dataclass(frozen=True)
class TripPlanRecord:
    plan: TripPlan
    user_id: UUID
    created_at: datetime


def _point_sql(lng_param: int, lat_param: int) -> str:
    return f"ST_SetSRID(ST_MakePoint(${lng_param}, ${lat_param}), 4326)::geography"


_STOP_COLUMNS = """
    s.id, s.type::text AS type, s.name, s.corridor_id, s.valid_until,
    ST_Y(s.location::geometry) AS lat, ST_X(s.location::geometry) AS lng
"""

_BOOKING_COLUMNS = """
    b.id, b.user_id, b.trip_plan_id, b.status::text AS status, b.seats,
    b.pickup_stop_id, b.pickup_stop_name, b.pickup_stop_type::text AS pickup_stop_type,
    ST_Y(b.pickup_location::geometry) AS pickup_lat, ST_X(b.pickup_location::geometry) AS pickup_lng,
    b.dropoff_stop_id, b.dropoff_stop_name, b.dropoff_stop_type::text AS dropoff_stop_type,
    ST_Y(b.dropoff_location::geometry) AS dropoff_lat, ST_X(b.dropoff_location::geometry) AS dropoff_lng,
    b.feeder_id, b.fare_estimate_idr, b.cancellation_fee_idr, b.eta_to_pickup_s, b.cancel_reason,
    b.request_hash, b.version, b.created_at, b.updated_at
"""


def _stop_from_row(row: asyncpg.Record, prefix: str = "") -> Optional[Stop]:
    if row[f"{prefix}id"] is None:
        return None
    return Stop(
        id=row[f"{prefix}id"],
        type=StopType(row[f"{prefix}type"]),
        name=row[f"{prefix}name"],
        location=GeoPoint(lat=row[f"{prefix}lat"], lng=row[f"{prefix}lng"]),
        corridor_id=row[f"{prefix}corridor_id"],
        valid_until=row[f"{prefix}valid_until"],
    )


def _snapshot(row: asyncpg.Record, side: str) -> Optional[StopSnapshot]:
    if row[f"{side}_stop_name"] is None:
        return None
    return StopSnapshot(
        id=row[f"{side}_stop_id"],
        type=StopType(row[f"{side}_stop_type"]),
        name=row[f"{side}_stop_name"],
        location=GeoPoint(lat=row[f"{side}_lat"], lng=row[f"{side}_lng"]),
    )


def _booking_from_row(row: asyncpg.Record) -> BookingRecord:
    booking = Booking(
        id=row["id"],
        status=BookingStatus(row["status"]),
        trip_plan_id=row["trip_plan_id"],
        seats=row["seats"],
        pickup_stop=_snapshot(row, "pickup"),
        dropoff_stop=_snapshot(row, "dropoff"),
        feeder_id=row["feeder_id"],
        fare_estimate_idr=row["fare_estimate_idr"],
        cancellation_fee_idr=row["cancellation_fee_idr"],
        eta_to_pickup_s=row["eta_to_pickup_s"],
        cancel_reason=row["cancel_reason"],
        version=row["version"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )
    return BookingRecord(booking=booking, user_id=row["user_id"], request_hash=row["request_hash"])


class BookingRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    # --- stops -------------------------------------------------------------

    async def upsert_stop(self, stop: Stop) -> None:
        await self._pool.execute(
            f"""
            INSERT INTO stops (id, type, name, location, corridor_id, valid_until)
            VALUES ($1, $2::stop_type, $3, {_point_sql(4, 5)}, $6, $7)
            ON CONFLICT (id) DO UPDATE SET valid_until = EXCLUDED.valid_until
            """,
            stop.id,
            stop.type.value,
            stop.name,
            stop.location.lng,
            stop.location.lat,
            stop.corridor_id,
            stop.valid_until,
        )

    # --- trip plans --------------------------------------------------------

    async def insert_trip_plan(self, user_id: UUID, plan: TripPlan) -> None:
        await self._pool.execute(
            f"""
            INSERT INTO trip_plans (
                id, user_id, origin, destination, pickup_stop_id, dropoff_stop_id,
                corridor_id, legs, fare_estimate_idr, eta_minutes, expires_at
            )
            VALUES ($1, $2, {_point_sql(3, 4)}, {_point_sql(5, 6)}, $7, $8, $9, $10::jsonb, $11, $12, $13)
            """,
            plan.id,
            user_id,
            plan.origin.lng,
            plan.origin.lat,
            plan.destination.lng,
            plan.destination.lat,
            plan.pickup_stop.id if plan.pickup_stop else None,
            plan.dropoff_stop.id if plan.dropoff_stop else None,
            plan.corridor_id,
            json.dumps([leg.model_dump(mode="json") for leg in plan.legs]),
            plan.fare_estimate_idr,
            plan.eta_minutes,
            plan.expires_at,
        )

    async def get_trip_plan(self, plan_id: UUID, user_id: Optional[UUID] = None) -> Optional[TripPlanRecord]:
        row = await self._pool.fetchrow(
            f"""
            SELECT p.id, p.user_id, p.corridor_id, p.legs, p.fare_estimate_idr, p.eta_minutes,
                   p.expires_at, p.created_at,
                   ST_Y(p.origin::geometry) AS origin_lat, ST_X(p.origin::geometry) AS origin_lng,
                   ST_Y(p.destination::geometry) AS dest_lat, ST_X(p.destination::geometry) AS dest_lng,
                   ps.id AS pu_id, ps.type::text AS pu_type, ps.name AS pu_name, ps.corridor_id AS pu_corridor_id,
                   ps.valid_until AS pu_valid_until,
                   ST_Y(ps.location::geometry) AS pu_lat, ST_X(ps.location::geometry) AS pu_lng,
                   ds.id AS do_id, ds.type::text AS do_type, ds.name AS do_name, ds.corridor_id AS do_corridor_id,
                   ds.valid_until AS do_valid_until,
                   ST_Y(ds.location::geometry) AS do_lat, ST_X(ds.location::geometry) AS do_lng
            FROM trip_plans p
            LEFT JOIN stops ps ON ps.id = p.pickup_stop_id
            LEFT JOIN stops ds ON ds.id = p.dropoff_stop_id
            WHERE p.id = $1 AND ($2::uuid IS NULL OR p.user_id = $2)
            """,
            plan_id,
            user_id,
        )
        if row is None:
            return None
        plan = TripPlan(
            id=row["id"],
            origin=GeoPoint(lat=row["origin_lat"], lng=row["origin_lng"]),
            destination=GeoPoint(lat=row["dest_lat"], lng=row["dest_lng"]),
            legs=[TripLeg.model_validate(leg) for leg in json.loads(row["legs"])],
            fare_estimate_idr=row["fare_estimate_idr"],
            eta_minutes=row["eta_minutes"],
            pickup_stop=_stop_from_row(row, "pu_"),
            dropoff_stop=_stop_from_row(row, "do_"),
            corridor_id=row["corridor_id"],
            expires_at=row["expires_at"],
        )
        return TripPlanRecord(plan=plan, user_id=row["user_id"], created_at=row["created_at"])

    # --- bookings ----------------------------------------------------------

    async def get_booking_by_key(self, user_id: UUID, idempotency_key: str) -> Optional[BookingRecord]:
        row = await self._pool.fetchrow(
            f"SELECT {_BOOKING_COLUMNS} FROM bookings b WHERE b.user_id = $1 AND b.idempotency_key = $2",
            user_id,
            idempotency_key,
        )
        return _booking_from_row(row) if row else None

    async def insert_booking(
        self,
        *,
        user_id: UUID,
        trip_plan_id: UUID,
        seats: int,
        fare_estimate_idr: int,
        idempotency_key: str,
        request_hash: str,
    ) -> BookingRecord:
        try:
            row = await self._pool.fetchrow(
                f"""
                WITH inserted AS (
                    INSERT INTO bookings (user_id, trip_plan_id, seats, fare_estimate_idr, idempotency_key, request_hash)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    RETURNING *
                )
                SELECT {_BOOKING_COLUMNS} FROM inserted b
                """,
                user_id,
                trip_plan_id,
                seats,
                fare_estimate_idr,
                idempotency_key,
                request_hash,
            )
        except asyncpg.UniqueViolationError as exc:
            if exc.constraint_name == "bookings_user_idempotency_key_uniq":
                raise DuplicateIdempotencyKey from exc
            if exc.constraint_name == "bookings_one_active_per_user_uniq":
                raise ActiveBookingExists from exc
            raise
        return _booking_from_row(row)

    async def get_booking(self, booking_id: UUID, user_id: Optional[UUID] = None) -> Optional[BookingRecord]:
        row = await self._pool.fetchrow(
            f"SELECT {_BOOKING_COLUMNS} FROM bookings b WHERE b.id = $1 AND ($2::uuid IS NULL OR b.user_id = $2)",
            booking_id,
            user_id,
        )
        return _booking_from_row(row) if row else None

    async def get_active_booking(self, user_id: UUID) -> Optional[BookingRecord]:
        row = await self._pool.fetchrow(
            f"SELECT {_BOOKING_COLUMNS} FROM bookings b WHERE b.user_id = $1 AND b.status IN {_ACTIVE_SQL}",
            user_id,
        )
        return _booking_from_row(row) if row else None

    async def list_bookings(
        self, user_id: UUID, limit: int, before: Optional[tuple[datetime, UUID]] = None
    ) -> list[BookingRecord]:
        rows = await self._pool.fetch(
            f"""
            SELECT {_BOOKING_COLUMNS} FROM bookings b
            WHERE b.user_id = $1
              AND ($2::timestamptz IS NULL OR (b.created_at, b.id) < ($2::timestamptz, $3::uuid))
            ORDER BY b.created_at DESC, b.id DESC
            LIMIT $4
            """,
            user_id,
            before[0] if before else None,
            before[1] if before else None,
            limit,
        )
        return [_booking_from_row(row) for row in rows]

    async def update_booking(
        self,
        booking_id: UUID,
        expected_version: int,
        status: BookingStatus,
        *,
        pickup_stop: Optional[Stop] = None,
        dropoff_stop: Optional[Stop] = None,
        **fields: Any,
    ) -> Optional[BookingRecord]:
        """Optimistic-concurrency update: applies only if `version` still
        matches, bumping it. Returns None if someone else got there first."""
        allowed = {"feeder_id", "eta_to_pickup_s", "cancel_reason", "cancellation_fee_idr"}
        unknown = set(fields) - allowed
        if unknown:
            raise ValueError(f"Unsupported booking fields: {sorted(unknown)}")

        sets = ["status = $3::booking_status", "version = version + 1", "updated_at = now()"]
        values: list[Any] = [booking_id, expected_version, status.value]

        def param(value: Any) -> int:
            values.append(value)
            return len(values)

        for side, stop in (("pickup", pickup_stop), ("dropoff", dropoff_stop)):
            if stop is None:
                continue
            sets.append(f"{side}_stop_id = ${param(stop.id)}")
            sets.append(f"{side}_stop_name = ${param(stop.name)}")
            sets.append(f"{side}_stop_type = ${param(stop.type.value)}::stop_type")
            lng, lat = param(stop.location.lng), param(stop.location.lat)
            sets.append(f"{side}_location = {_point_sql(lng, lat)}")
        for name, value in fields.items():
            sets.append(f"{name} = ${param(value)}")

        row = await self._pool.fetchrow(
            f"""
            WITH updated AS (
                UPDATE bookings SET {", ".join(sets)}
                WHERE id = $1 AND version = $2
                RETURNING *
            )
            SELECT {_BOOKING_COLUMNS} FROM updated b
            """,
            *values,
        )
        return _booking_from_row(row) if row else None

    async def find_waiting_at_pickup(self, stop_id: UUID, feeder_id: str) -> list[BookingRecord]:
        rows = await self._pool.fetch(
            f"""
            SELECT {_BOOKING_COLUMNS} FROM bookings b
            WHERE b.pickup_stop_id = $1 AND b.feeder_id = $2 AND b.status IN ('CONFIRMED', 'FEEDER_ARRIVING')
            """,
            stop_id,
            feeder_id,
        )
        return [_booking_from_row(row) for row in rows]

    async def find_riding_to_dropoff(self, stop_id: UUID, feeder_id: str) -> list[BookingRecord]:
        rows = await self._pool.fetch(
            f"""
            SELECT {_BOOKING_COLUMNS} FROM bookings b
            WHERE b.dropoff_stop_id = $1 AND b.feeder_id = $2 AND b.status = 'BOARDED'
            """,
            stop_id,
            feeder_id,
        )
        return [_booking_from_row(row) for row in rows]

    async def find_stale(
        self, now: datetime, matching_timeout_s: int, confirmed_timeout_s: int
    ) -> list[BookingRecord]:
        rows = await self._pool.fetch(
            f"""
            SELECT {_BOOKING_COLUMNS} FROM bookings b
            WHERE (b.status IN ('REQUESTED', 'MATCHING') AND b.updated_at < $1::timestamptz - make_interval(secs => $2))
               OR (b.status = 'CONFIRMED' AND b.updated_at < $1::timestamptz - make_interval(secs => $3))
            """,
            now,
            float(matching_timeout_s),
            float(confirmed_timeout_s),
        )
        return [_booking_from_row(row) for row in rows]

    async def find_confirmed_with_feeder(self) -> list[BookingRecord]:
        rows = await self._pool.fetch(
            f"SELECT {_BOOKING_COLUMNS} FROM bookings b WHERE b.status = 'CONFIRMED' AND b.feeder_id IS NOT NULL"
        )
        return [_booking_from_row(row) for row in rows]

    # --- consent -----------------------------------------------------------

    async def insert_consent(
        self, user_id: UUID, purpose: ConsentPurpose, policy_version: str, granted: bool
    ) -> Consent:
        row = await self._pool.fetchrow(
            """
            INSERT INTO consent_log (user_id, purpose, policy_version, granted)
            VALUES ($1, $2, $3, $4)
            RETURNING purpose, policy_version, granted, created_at
            """,
            user_id,
            purpose.value,
            policy_version,
            granted,
        )
        return Consent(**dict(row))

    async def latest_consents(self, user_id: UUID) -> list[Consent]:
        rows = await self._pool.fetch(
            """
            SELECT DISTINCT ON (purpose) purpose, policy_version, granted, created_at
            FROM consent_log
            WHERE user_id = $1
            ORDER BY purpose, created_at DESC, id DESC
            """,
            user_id,
        )
        return [Consent(**dict(row)) for row in rows]

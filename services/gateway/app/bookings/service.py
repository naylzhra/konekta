# Booking orchestration: idempotent create, matching, cancel/board, driver
# stop events, expiry sweep. All status changes go through the pure state
# machine and an optimistic version check, then publish booking.updated.
import base64
import hashlib
import json
import logging
import math
import uuid
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable, Optional
from uuid import UUID

from app.bookings import config
from app.bookings.clients import (
    FeederPositionProvider,
    RouteResult,
    RoutingClient,
    RoutingError,
    StopAssigner,
    StopAssignmentRequest,
    haversine_m,
)
from app.bookings.events import BookingEventPublisher
from app.bookings.models import (
    Booking,
    BookingPage,
    Consent,
    ConsentList,
    ConsentPurpose,
    ConsentRequest,
    CreateBookingRequest,
    ErrorCode,
    GeoPoint,
    LegMode,
    Stop,
    TripLeg,
    TripPlan,
    TripPlanRequest,
    TripPlansResponse,
)
from app.bookings.repository import (
    ActiveBookingExists,
    BookingRecord,
    BookingRepository,
    DuplicateIdempotencyKey,
)
from app.bookings.state_machine import BookingEvent, BookingStatus, InvalidTransition, next_status

logger = logging.getLogger(__name__)

Clock = Callable[[], datetime]
ConfirmedHook = Callable[[Booking], Awaitable[None]]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class BookingError(Exception):
    def __init__(self, code: ErrorCode, status_code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code
        self.message = message


def compute_fare_idr(feeder_distance_m: float) -> int:
    raw = config.FARE_BASE_IDR + config.FARE_PER_KM_IDR * feeder_distance_m / 1000
    return int(math.ceil(raw / config.FARE_ROUNDING_IDR) * config.FARE_ROUNDING_IDR)


def request_hash(payload: CreateBookingRequest) -> str:
    canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def encode_cursor(booking: Booking) -> str:
    raw = f"{booking.created_at.isoformat()}|{booking.id}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        created_at, booking_id = base64.urlsafe_b64decode(padded).decode().split("|")
        return datetime.fromisoformat(created_at), UUID(booking_id)
    except (ValueError, UnicodeDecodeError) as exc:
        raise BookingError(ErrorCode.INVALID_CURSOR, 400, "Invalid cursor") from exc


class BookingService:
    def __init__(
        self,
        repo: BookingRepository,
        stop_assigner: StopAssigner,
        feeders: FeederPositionProvider,
        routing: RoutingClient,
        publisher: BookingEventPublisher,
        *,
        clock: Clock = utcnow,
    ) -> None:
        self._repo = repo
        self._stops = stop_assigner
        self._feeders = feeders
        self._routing = routing
        self._publisher = publisher
        self._clock = clock
        # set by BookingSimulator when BOOKING_SIMULATOR=1
        self.on_confirmed: Optional[ConfirmedHook] = None

    # --- consent -----------------------------------------------------------

    async def record_consent(self, user_id: UUID, request: ConsentRequest) -> Consent:
        return await self._repo.insert_consent(user_id, request.purpose, request.policy_version, request.granted)

    async def list_consents(self, user_id: UUID) -> ConsentList:
        return ConsentList(items=await self._repo.latest_consents(user_id))

    async def _require_consent(self, user_id: UUID) -> None:
        for consent in await self._repo.latest_consents(user_id):
            if (
                consent.purpose is ConsentPurpose.TRIP_LOCATION
                and consent.granted
                and consent.policy_version == config.CONSENT_POLICY_VERSION
            ):
                return
        raise BookingError(ErrorCode.CONSENT_REQUIRED, 403, "Location consent is required")

    # --- trip plans --------------------------------------------------------

    async def _route(self, points: list[GeoPoint], profile: str) -> RouteResult:
        try:
            return await self._routing.route(points, profile=profile)
        except RoutingError as exc:
            raise BookingError(ErrorCode.ROUTING_UNAVAILABLE, 503, "Routing is unavailable") from exc

    async def plan_trip(self, user_id: UUID, request: TripPlanRequest) -> TripPlansResponse:
        await self._require_consent(user_id)

        pickup = await self._stops.assign_pickup_stop(
            StopAssignmentRequest(location=request.origin, seats=request.seats)
        )
        dropoff = await self._stops.assign_dropoff_stop(
            StopAssignmentRequest(location=request.destination, seats=request.seats)
        )
        if pickup is None or dropoff is None:
            raise BookingError(ErrorCode.NO_ROUTE, 422, "Outside the service area")
        if pickup.id == dropoff.id:
            raise BookingError(ErrorCode.NO_ROUTE, 422, "Destination is too close to need a feeder")

        walk_to = haversine_m(request.origin, pickup.location)
        walk_from = haversine_m(dropoff.location, request.destination)
        ride = await self._route([pickup.location, dropoff.location], "driving")
        legs = [
            TripLeg(mode=LegMode.WALK, distance_m=walk_to, duration_s=walk_to / config.WALK_SPEED_MPS),
            TripLeg(mode=LegMode.FEEDER, distance_m=ride.distance_m, duration_s=ride.duration_s),
            TripLeg(mode=LegMode.WALK, distance_m=walk_from, duration_s=walk_from / config.WALK_SPEED_MPS),
        ]

        nearest_feeder_eta_s: Optional[int] = None
        feeders = await self._feeders.nearest(
            pickup.location.lat, pickup.location.lng, config.FEEDER_SEARCH_RADIUS_M, pickup.corridor_id, limit=1
        )
        if feeders:
            to_pickup = await self._route([feeders[0].location, pickup.location], "driving")
            nearest_feeder_eta_s = int(to_pickup.duration_s)

        walk_s = legs[0].duration_s
        wait_s = max(walk_s, nearest_feeder_eta_s or 0)
        total_s = wait_s + legs[1].duration_s + legs[2].duration_s

        plan = TripPlan(
            id=uuid.uuid4(),
            origin=request.origin,
            destination=request.destination,
            legs=legs,
            fare_estimate_idr=compute_fare_idr(ride.distance_m) * request.seats,
            eta_minutes=int(math.ceil(total_s / 60)),
            pickup_stop=pickup,
            dropoff_stop=dropoff,
            corridor_id=pickup.corridor_id,
            nearest_feeder_eta_s=nearest_feeder_eta_s,
            expires_at=self._clock() + timedelta(seconds=config.PLAN_TTL_S),
        )
        await self._repo.upsert_stop(pickup)
        await self._repo.upsert_stop(dropoff)
        await self._repo.insert_trip_plan(user_id, plan)
        return TripPlansResponse(plans=[plan])

    # --- create (idempotent) -------------------------------------------------

    async def create_booking(
        self, user_id: UUID, request: CreateBookingRequest, idempotency_key: str
    ) -> tuple[Booking, bool]:
        """Returns (booking, created). Same key + same body -> existing
        booking with created=False; same key + different body -> 409."""
        body_hash = request_hash(request)
        existing = await self._repo.get_booking_by_key(user_id, idempotency_key)
        if existing is not None:
            return self._replay(existing, body_hash), False

        await self._require_consent(user_id)
        plan_record = await self._repo.get_trip_plan(request.trip_plan_id, user_id)
        if plan_record is None:
            raise BookingError(ErrorCode.NOT_FOUND, 404, "Trip plan not found")
        if plan_record.plan.expires_at <= self._clock():
            raise BookingError(ErrorCode.PLAN_EXPIRED, 410, "Trip plan expired, plan again")

        try:
            record = await self._repo.insert_booking(
                user_id=user_id,
                trip_plan_id=plan_record.plan.id,
                seats=request.seats,
                fare_estimate_idr=plan_record.plan.fare_estimate_idr,
                idempotency_key=idempotency_key,
                request_hash=body_hash,
            )
        except DuplicateIdempotencyKey:
            # concurrent double-tap with the same key: the other request won
            existing = await self._repo.get_booking_by_key(user_id, idempotency_key)
            if existing is None:
                raise
            return self._replay(existing, body_hash), False
        except ActiveBookingExists as exc:
            raise BookingError(ErrorCode.ACTIVE_BOOKING_EXISTS, 409, "You already have an active booking") from exc

        await self._publisher.booking_updated(record.user_id, record.booking)
        return record.booking, True

    @staticmethod
    def _replay(existing: BookingRecord, body_hash: str) -> Booking:
        if existing.request_hash != body_hash:
            raise BookingError(
                ErrorCode.IDEMPOTENCY_KEY_REUSED, 409, "Idempotency-Key was already used for a different request"
            )
        return existing.booking

    # --- transitions -------------------------------------------------------

    async def _apply(
        self,
        booking_id: UUID,
        event: BookingEvent,
        fields: Optional[Callable[[BookingRecord], dict]] = None,
        *,
        user_id: Optional[UUID] = None,
    ) -> BookingRecord:
        for _ in range(3):
            record = await self._repo.get_booking(booking_id, user_id)
            if record is None:
                raise BookingError(ErrorCode.NOT_FOUND, 404, "Booking not found")
            status = next_status(record.status, event)  # raises InvalidTransition
            updated = await self._repo.update_booking(
                record.id, record.version, status, **(fields(record) if fields else {})
            )
            if updated is not None:
                await self._publisher.booking_updated(updated.user_id, updated.booking)
                return updated
        raise BookingError(ErrorCode.CONCURRENT_UPDATE, 409, "Booking changed concurrently, retry")

    async def run_matching(self, booking_id: UUID) -> None:
        """REQUESTED -> MATCHING -> CONFIRMED | FAILED. Safe to call for a
        booking that was cancelled meanwhile."""
        try:
            await self._apply(booking_id, BookingEvent.START_MATCHING)
            confirmed = await self._match(booking_id)
        except InvalidTransition:
            logger.info("matching skipped for booking %s: status changed", booking_id)
            return
        except Exception:
            logger.exception("matching failed for booking %s", booking_id)
            try:
                await self._apply(booking_id, BookingEvent.MATCH_FAILED)
            except (InvalidTransition, BookingError):
                pass
            return
        if confirmed is not None and self.on_confirmed is not None:
            await self.on_confirmed(confirmed.booking)

    async def _match(self, booking_id: UUID) -> Optional[BookingRecord]:
        record = await self._repo.get_booking(booking_id)
        plan_record = await self._repo.get_trip_plan(record.booking.trip_plan_id) if record else None
        if record is None or plan_record is None:
            await self._apply(booking_id, BookingEvent.MATCH_FAILED)
            return None
        plan = plan_record.plan

        pickup = plan.pickup_stop
        if pickup is None or (pickup.valid_until is not None and pickup.valid_until <= self._clock()):
            pickup = await self._stops.assign_pickup_stop(
                StopAssignmentRequest(location=plan.origin, seats=record.booking.seats)
            )
            if pickup is not None:
                await self._repo.upsert_stop(pickup)
        dropoff = plan.dropoff_stop
        if pickup is None or dropoff is None:
            await self._apply(booking_id, BookingEvent.MATCH_FAILED)
            return None

        seats = record.booking.seats
        candidates = [
            feeder
            for feeder in await self._feeders.nearest(
                pickup.location.lat, pickup.location.lng, config.FEEDER_SEARCH_RADIUS_M, pickup.corridor_id
            )
            if feeder.capacity - feeder.occupancy >= seats
        ]
        if not candidates:
            await self._apply(booking_id, BookingEvent.MATCH_FAILED)
            return None
        feeder = candidates[0]
        try:
            eta_s: Optional[int] = int(
                (await self._routing.route([feeder.location, pickup.location], profile="driving")).duration_s
            )
        except RoutingError:
            eta_s = None

        return await self._apply(
            booking_id,
            BookingEvent.MATCH_FOUND,
            lambda _: {
                "pickup_stop": pickup,
                "dropoff_stop": dropoff,
                "feeder_id": feeder.feeder_id,
                "eta_to_pickup_s": eta_s,
            },
        )

    async def cancel(self, user_id: UUID, booking_id: UUID, reason: Optional[str]) -> Booking:
        record = await self._get_owned(user_id, booking_id)
        if record.status is BookingStatus.CANCELLED:
            return record.booking  # idempotent repeat

        def fields(current: BookingRecord) -> dict:
            fee = (
                config.CANCELLATION_PENALTY_IDR
                if current.status in (BookingStatus.CONFIRMED, BookingStatus.FEEDER_ARRIVING)
                else 0
            )
            return {"cancel_reason": reason, "cancellation_fee_idr": fee}

        return (await self._apply(booking_id, BookingEvent.CANCEL, fields, user_id=user_id)).booking

    async def mark_boarded(self, user_id: UUID, booking_id: UUID) -> Booking:
        record = await self._get_owned(user_id, booking_id)
        if record.status is BookingStatus.BOARDED:
            return record.booking  # idempotent repeat
        return (await self._apply(booking_id, BookingEvent.PASSENGER_BOARDED, user_id=user_id)).booking

    async def _get_owned(self, user_id: UUID, booking_id: UUID) -> BookingRecord:
        record = await self._repo.get_booking(booking_id, user_id)
        if record is None:
            raise BookingError(ErrorCode.NOT_FOUND, 404, "Booking not found")
        return record

    # --- reads -------------------------------------------------------------

    async def get_status(self, booking_id: UUID) -> Optional[BookingStatus]:
        """Internal lookup without an ownership check (simulator, sweeps)."""
        record = await self._repo.get_booking(booking_id)
        return record.status if record else None

    async def get_active(self, user_id: UUID) -> Optional[Booking]:
        record = await self._repo.get_active_booking(user_id)
        return record.booking if record else None

    async def list_bookings(self, user_id: UUID, cursor: Optional[str], limit: int) -> BookingPage:
        before = decode_cursor(cursor) if cursor else None
        records = await self._repo.list_bookings(user_id, limit + 1, before)
        items = [record.booking for record in records[:limit]]
        next_cursor = encode_cursor(items[-1]) if len(records) > limit else None
        return BookingPage(items=items, next_cursor=next_cursor)

    # --- driver stop events (DESIGN.md §5.6) ---------------------------------

    async def _apply_many(self, records: list[BookingRecord], event: BookingEvent) -> list[UUID]:
        updated: list[UUID] = []
        for record in records:
            try:
                updated.append((await self._apply(record.id, event)).id)
            except (InvalidTransition, BookingError):
                continue  # changed meanwhile (e.g. cancelled); nothing to do
        return updated

    async def driver_arrived(self, stop_id: UUID, feeder_id: str) -> list[UUID]:
        waiting = [
            record
            for record in await self._repo.find_waiting_at_pickup(stop_id, feeder_id)
            if record.status is BookingStatus.CONFIRMED
        ]
        riding = await self._repo.find_riding_to_dropoff(stop_id, feeder_id)
        return await self._apply_many(waiting, BookingEvent.FEEDER_APPROACHING) + await self._apply_many(
            riding, BookingEvent.DRIVER_ARRIVED_DROPOFF
        )

    async def driver_departed(self, stop_id: UUID, feeder_id: str) -> list[UUID]:
        waiting = await self._repo.find_waiting_at_pickup(stop_id, feeder_id)
        return await self._apply_many(waiting, BookingEvent.DRIVER_DEPARTED_PICKUP)

    # --- background sweep --------------------------------------------------

    async def sweep_once(self, now: Optional[datetime] = None) -> None:
        now = now or self._clock()
        stale = await self._repo.find_stale(now, config.MATCHING_TIMEOUT_S, config.CONFIRMED_TIMEOUT_S)
        await self._apply_many(stale, BookingEvent.EXPIRE)

        approaching: list[BookingRecord] = []
        for record in await self._repo.find_confirmed_with_feeder():
            pickup = record.booking.pickup_stop
            position = await self._feeders.get_last_known(record.booking.feeder_id)
            if pickup is None or position is None:
                continue
            if haversine_m(position.location, pickup.location) <= config.ARRIVING_RADIUS_M:
                approaching.append(record)
        await self._apply_many(approaching, BookingEvent.FEEDER_APPROACHING)

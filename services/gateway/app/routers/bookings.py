# Booking REST API (DESIGN.md §6). Errors: {"detail": {"code", "message"}}.
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Query, Response, status

from app.auth.dependencies import require_not_suspended
from app.bookings.dependencies import get_booking_service, passenger_id
from app.bookings.models import (
    Booking,
    BookingPage,
    CancelBookingRequest,
    CreateBookingRequest,
    ErrorCode,
    TripPlanRequest,
    TripPlansResponse,
)
from app.bookings.service import BookingError, BookingService
from app.bookings.state_machine import InvalidTransition

router = APIRouter(tags=["bookings"])


def raise_http(exc: Exception) -> None:
    if isinstance(exc, BookingError):
        raise HTTPException(exc.status_code, detail={"code": exc.code.value, "message": exc.message}) from exc
    if isinstance(exc, InvalidTransition):
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail={"code": ErrorCode.INVALID_TRANSITION.value, "message": str(exc)}
        ) from exc
    raise exc


def require_idempotency_key(idempotency_key: Optional[str] = Header(default=None)) -> str:
    if not idempotency_key or len(idempotency_key) > 64:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={
                "code": ErrorCode.IDEMPOTENCY_KEY_REQUIRED.value,
                "message": "Idempotency-Key header (1-64 chars) is required",
            },
        )
    return idempotency_key


@router.post(
    "/trip-plans",
    response_model=TripPlansResponse,
    dependencies=[Depends(require_not_suspended)],
)
async def create_trip_plans(
    payload: TripPlanRequest,
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
) -> TripPlansResponse:
    try:
        return await service.plan_trip(user_id, payload)
    except BookingError as exc:
        raise_http(exc)


@router.post(
    "/bookings",
    response_model=Booking,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_not_suspended)],
)
async def create_booking(
    payload: CreateBookingRequest,
    response: Response,
    background: BackgroundTasks,
    idempotency_key: str = Depends(require_idempotency_key),
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
) -> Booking:
    try:
        booking, created = await service.create_booking(user_id, payload, idempotency_key)
    except BookingError as exc:
        raise_http(exc)
    if created:
        background.add_task(service.run_matching, booking.id)
    else:
        response.status_code = status.HTTP_200_OK
    return booking


# Cancel and boarded are idempotent by state: repeating them returns the
# current booking, so no Idempotency-Key is required.
@router.post("/bookings/{booking_id}/cancel", response_model=Booking)
async def cancel_booking(
    booking_id: UUID,
    payload: CancelBookingRequest,
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
) -> Booking:
    try:
        return await service.cancel(user_id, booking_id, payload.reason)
    except (BookingError, InvalidTransition) as exc:
        raise_http(exc)


@router.post("/bookings/{booking_id}/boarded", response_model=Booking)
async def mark_boarded(
    booking_id: UUID,
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
) -> Booking:
    try:
        return await service.mark_boarded(user_id, booking_id)
    except (BookingError, InvalidTransition) as exc:
        raise_http(exc)


@router.get(
    "/bookings/active",
    response_model=Booking,
    responses={204: {"description": "No active booking"}},
)
async def get_active_booking(
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
):
    booking = await service.get_active(user_id)
    if booking is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    return booking


@router.get("/bookings", response_model=BookingPage)
async def list_bookings(
    cursor: Optional[str] = Query(default=None, max_length=200),
    limit: int = Query(default=20, ge=1, le=50),
    user_id: UUID = Depends(passenger_id),
    service: BookingService = Depends(get_booking_service),
) -> BookingPage:
    try:
        return await service.list_bookings(user_id, cursor, limit)
    except BookingError as exc:
        raise_http(exc)

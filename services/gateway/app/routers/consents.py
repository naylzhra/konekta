# Location-processing consent (UU PDP, DESIGN.md §8). Append-only.
from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.auth.dependencies import get_current_session
from app.bookings.dependencies import get_booking_service, session_user_id
from app.bookings.models import Consent, ConsentList, ConsentRequest
from app.bookings.service import BookingService

router = APIRouter(prefix="/consents", tags=["consents"])


async def _user_id(session: dict = Depends(get_current_session)) -> UUID:
    return session_user_id(session)


@router.post("", response_model=Consent, status_code=status.HTTP_201_CREATED)
async def record_consent(
    payload: ConsentRequest,
    user_id: UUID = Depends(_user_id),
    service: BookingService = Depends(get_booking_service),
) -> Consent:
    return await service.record_consent(user_id, payload)


@router.get("", response_model=ConsentList)
async def list_consents(
    user_id: UUID = Depends(_user_id),
    service: BookingService = Depends(get_booking_service),
) -> ConsentList:
    return await service.list_consents(user_id)

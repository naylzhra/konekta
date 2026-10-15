# Live tracking REST (DESIGN.md §5.8). Drivers report their position here;
# subscribers receive it as `feeder.position` over the WS hub (§5.1).
from typing import NoReturn
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.auth.dependencies import require_role
from app.feeders.dependencies import get_feeder_repository, get_feeder_service
from app.feeders.models import AssignedFeeder, CorridorList, FeederError, PositionAccepted, PositionReport
from app.feeders.repository import FeederRepository
from app.feeders.service import FeederTrackingService

router = APIRouter(tags=["feeders"])

require_driver = require_role("driver")


def _http_error(exc: FeederError) -> NoReturn:
    raise HTTPException(exc.status_code, detail={"code": exc.code.value, "message": exc.message}) from exc


def _driver_id(session: dict) -> UUID:
    return UUID(session["user_id"])


# Public: the registration form lists feeders before the driver has an account.
@router.get("/corridors", response_model=CorridorList)
async def list_corridors(repository: FeederRepository = Depends(get_feeder_repository)) -> CorridorList:
    return CorridorList(items=await repository.list_corridors())


@router.get("/feeders/me", response_model=AssignedFeeder)
async def my_feeder(
    session: dict = Depends(require_driver),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> AssignedFeeder:
    try:
        return await service.assigned_feeder(_driver_id(session))
    except FeederError as exc:
        _http_error(exc)


@router.post("/feeders/me/position", response_model=PositionAccepted)
async def report_position(
    report: PositionReport,
    session: dict = Depends(require_driver),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> PositionAccepted:
    try:
        return await service.report_position(_driver_id(session), report)
    except FeederError as exc:
        _http_error(exc)


@router.post("/feeders/me/offline", status_code=status.HTTP_204_NO_CONTENT)
async def go_offline(
    session: dict = Depends(require_driver),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> Response:
    try:
        await service.go_offline(_driver_id(session))
    except FeederError as exc:
        _http_error(exc)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# Live tracking REST (DESIGN.md §5.8). Drivers report their position here;
# subscribers receive it as `feeder.position` over the WS hub (§5.1).
from typing import Literal, NoReturn, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status

from app.auth.dependencies import get_current_session, require_role
from app.feeders import config
from app.feeders.dependencies import get_feeder_repository, get_feeder_service
from app.feeders.models import (
    AssignedFeeder,
    CorridorArrivals,
    CorridorList,
    CorridorPath,
    CorridorStops,
    FeederError,
    LiveFeeder,
    LiveFeederList,
    PositionAccepted,
    PositionReport,
)
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


@router.get("/corridors/{corridor_id}/stops", response_model=CorridorStops)
async def corridor_stops(
    corridor_id: str,
    direction: Literal["forward", "backward"] = "forward",
    repository: FeederRepository = Depends(get_feeder_repository),
) -> CorridorStops:
    route = await repository.route_stops(corridor_id, direction)
    if route is None:
        raise HTTPException(status_code=404, detail="Corridor not found")
    return route


@router.get("/corridors/{corridor_id}/path", response_model=CorridorPath)
async def corridor_path(
    corridor_id: str,
    direction: Literal["forward", "backward"] = "forward",
    repository: FeederRepository = Depends(get_feeder_repository),
) -> CorridorPath:
    path = await repository.route_path(corridor_id, direction)
    if path is None:
        raise HTTPException(status_code=404, detail="Corridor not found")
    return path


# Upcoming feeders per route stop, for the passenger's route page.
@router.get("/corridors/{corridor_id}/arrivals", response_model=CorridorArrivals)
async def corridor_arrivals(
    corridor_id: str,
    direction: Literal["forward", "backward"] = "forward",
    max_eta_s: int = Query(config.ARRIVALS_DEFAULT_MAX_ETA_S, ge=0, le=config.ARRIVALS_MAX_ETA_S),
    _session: dict = Depends(get_current_session),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> CorridorArrivals:
    arrivals = await service.arrivals(corridor_id, direction, max_eta_s)
    if arrivals is None:
        raise HTTPException(status_code=404, detail="Corridor not found")
    return arrivals


# Snapshot for the passenger map; live updates follow on corridor:<id> topics.
@router.get("/feeders/live", response_model=LiveFeederList)
async def live_feeders(
    corridor_id: Optional[str] = None,
    _session: dict = Depends(get_current_session),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> LiveFeederList:
    positions = await service.live_feeders(corridor_id)
    return LiveFeederList(items=[LiveFeeder.model_validate(p.model_dump()) for p in positions])


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

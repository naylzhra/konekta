# Driver stop events (DESIGN.md §5.6): the driver works per stop, never per
# passenger. Idempotent: repeating an event finds nothing left to update.
#
# The feeder is resolved from the authenticated driver's assignment.
from uuid import UUID

from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.bookings.clients import OsrmRoutingClient, RouteStep, RoutingError
from app.bookings.dependencies import get_booking_service, require_driver
from app.bookings.models import DriverStopEventRequest, DriverStopEventResult, GeoPoint
from app.bookings.service import BookingService
from app.db import get_pool

router = APIRouter(prefix="/driver/stops", tags=["driver"], dependencies=[Depends(require_driver)])


async def _assigned_feeder(session: dict) -> str:
    pool = await get_pool()
    feeder_id = await pool.fetchval("SELECT id FROM feeders WHERE driver_id = $1", UUID(session["user_id"]))
    if feeder_id is None:
        raise HTTPException(status_code=404, detail="No feeder assigned")
    return feeder_id


class DriverStop(BaseModel):
    stop_id: str
    name: Optional[str]
    type: str
    phase: str
    seats: int
    lat: Optional[float] = None
    lng: Optional[float] = None


class NavStop(BaseModel):
    """A stop on the way, with whoever is waiting there or riding to it."""
    stop_id: str
    name: Optional[str]
    type: str
    position: Optional[int] = None  # order on the corridor; None for virtual stops
    lat: float
    lng: float
    pickup_seats: int = 0
    dropoff_seats: int = 0


class DriverNavigation(BaseModel):
    target: NavStop
    upcoming: list[NavStop]
    distance_m: float
    duration_s: float
    points: list[GeoPoint]
    steps: list[RouteStep]


# A stop this close behind the driver's projection counts as passed.
PASSED_M = 20.0
UPCOMING_LIMIT = 3


async def _stops_for(feeder_id: str) -> list[DriverStop]:
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT stop_id, name, type, phase, SUM(seats)::int AS seats,
                  ST_Y(ST_Centroid(ST_Collect(location::geometry))) AS lat,
                  ST_X(ST_Centroid(ST_Collect(location::geometry))) AS lng
        FROM (
            SELECT pickup_stop_id AS stop_id, pickup_stop_name AS name,
                   pickup_stop_type::text AS type, 'pickup' AS phase, seats,
                   pickup_location AS location
            FROM bookings WHERE feeder_id = $1 AND status IN ('CONFIRMED', 'FEEDER_ARRIVING')
            UNION ALL
            SELECT dropoff_stop_id, dropoff_stop_name, dropoff_stop_type::text,
                   'dropoff', seats, dropoff_location
            FROM bookings WHERE feeder_id = $1 AND status = 'BOARDED'
        ) AS assigned
        WHERE stop_id IS NOT NULL
        GROUP BY stop_id, name, type, phase
        ORDER BY phase DESC, name""",
        feeder_id,
    )
    return [DriverStop(stop_id=str(row["stop_id"]), name=row["name"], type=row["type"],
                       phase=row["phase"], seats=row["seats"], lat=row["lat"], lng=row["lng"])
            for row in rows]


def stops_ahead(stops: list[tuple[float, NavStop]], driver_m: float) -> list[NavStop]:
    """Stops in driving order from the driver's along-route position; at the
    end of the route the terminal stays the target."""
    ordered = sorted(stops, key=lambda item: item[0])
    ahead = [stop for along_m, stop in ordered if along_m > driver_m + PASSED_M]
    return ahead or [stop for _, stop in ordered[-1:]]


async def _route_stops(
    corridor_id: str, direction: str, here: GeoPoint, tasks: list[DriverStop]
) -> tuple[float, list[tuple[float, NavStop]]]:
    """Every stop of the corridor in [direction] plus task stops off that list
    (virtual), each with its distance along that direction's line, and the
    driver's own."""
    pool = await get_pool()
    extra = {t.stop_id: t for t in tasks if t.lat is not None}
    rows = await pool.fetch(
        """WITH c AS (SELECT line::geometry AS g, ST_Length(line) AS len
                      FROM (SELECT CASE WHEN $9 = 'backward' THEN return_path ELSE path END AS line
                            FROM corridors WHERE id = $1) AS d),
                pts AS (
                    SELECT s.id::text AS stop_id, s.name, s.type::text AS type, crs.position,
                           s.location::geometry AS geom
                    FROM corridor_route_stops crs JOIN stops s ON s.id = crs.stop_id
                    WHERE crs.corridor_id = $1 AND crs.direction = $9 AND s.location IS NOT NULL
                    UNION ALL
                    SELECT t.stop_id, t.name, t.type, NULL, ST_SetSRID(ST_MakePoint(t.lng, t.lat), 4326)
                    FROM unnest($4::text[], $5::text[], $6::text[], $7::float8[], $8::float8[])
                         AS t(stop_id, name, type, lat, lng)
                )
           SELECT pts.stop_id, pts.name, pts.type, pts.position,
                  ST_Y(pts.geom) AS lat, ST_X(pts.geom) AS lng,
                  ST_LineLocatePoint(c.g, pts.geom) * c.len AS along_m,
                  ST_LineLocatePoint(c.g, ST_SetSRID(ST_MakePoint($3, $2), 4326)) * c.len AS driver_m
           FROM pts, c WHERE c.g IS NOT NULL""",
        corridor_id, here.lat, here.lng,
        [t.stop_id for t in extra.values()], [t.name or "Halte" for t in extra.values()],
        [t.type for t in extra.values()], [t.lat for t in extra.values()], [t.lng for t in extra.values()],
        direction,
    )
    seats: dict[str, dict[str, int]] = {}
    for task in tasks:
        seats.setdefault(task.stop_id, {"pickup": 0, "dropoff": 0})[task.phase] += task.seats
    stops: dict[str, tuple[float, NavStop]] = {}
    for row in rows:
        if row["stop_id"] in stops:  # a task at a corridor stop: keep the corridor entry
            continue
        counts = seats.get(row["stop_id"], {})
        stops[row["stop_id"]] = (row["along_m"], NavStop(
            stop_id=row["stop_id"], name=row["name"], type=row["type"], position=row["position"],
            lat=row["lat"], lng=row["lng"],
            pickup_seats=counts.get("pickup", 0), dropoff_seats=counts.get("dropoff", 0)))
    return (rows[0]["driver_m"] if rows else 0.0), list(stops.values())


@router.get("")
async def driver_stops(session: dict = Depends(require_driver)) -> dict:
    stops = await _stops_for(await _assigned_feeder(session))
    return {"items": [stop.model_dump() for stop in stops]}


@router.get("/navigation", response_model=DriverNavigation)
async def driver_navigation(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
    stop_id: Optional[str] = None,
    direction: Literal["forward", "backward"] = "forward",
    session: dict = Depends(require_driver),
) -> DriverNavigation:
    """Road route from the driver's position to the next stop on the corridor
    (passengers or not), or to [stop_id] when the driver picked one."""
    here = GeoPoint(lat=lat, lng=lng)
    feeder_id = await _assigned_feeder(session)
    corridor_id = await (await get_pool()).fetchval("SELECT corridor_id FROM feeders WHERE id = $1", feeder_id)
    driver_m, stops = await _route_stops(corridor_id, direction, here, await _stops_for(feeder_id))
    ahead = stops_ahead(stops, driver_m)
    if stop_id is not None:
        chosen = next((stop for _, stop in stops if stop.stop_id == stop_id), None)
        if chosen is not None:
            ahead = [chosen] + [stop for stop in ahead if stop.stop_id != stop_id]
    if not ahead:
        raise HTTPException(status_code=404, detail="Corridor has no located stops")
    target = ahead[0]
    try:
        route = await OsrmRoutingClient().route(
            [here, GeoPoint(lat=target.lat, lng=target.lng)], geometry=True, steps=True)
    except RoutingError as exc:
        raise HTTPException(status_code=503, detail="Routing unavailable") from exc
    return DriverNavigation(target=target, upcoming=ahead[1:1 + UPCOMING_LIMIT],
                            distance_m=route.distance_m, duration_s=route.duration_s,
                            points=route.points, steps=route.steps)


@router.post("/{stop_id}/arrived", response_model=DriverStopEventResult)
async def driver_arrived(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
    session: dict = Depends(require_driver),
) -> DriverStopEventResult:
    feeder_id = await _assigned_feeder(session)
    if payload.feeder_id != feeder_id:
        raise HTTPException(status_code=403, detail="Feeder does not belong to this driver")
    updated = await service.driver_arrived(stop_id, feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)


@router.post("/{stop_id}/departed", response_model=DriverStopEventResult)
async def driver_departed(
    stop_id: UUID,
    payload: DriverStopEventRequest,
    service: BookingService = Depends(get_booking_service),
    session: dict = Depends(require_driver),
) -> DriverStopEventResult:
    feeder_id = await _assigned_feeder(session)
    if payload.feeder_id != feeder_id:
        raise HTTPException(status_code=403, detail="Feeder does not belong to this driver")
    updated = await service.driver_departed(stop_id, feeder_id)
    return DriverStopEventResult(stop_id=stop_id, updated_booking_ids=updated)

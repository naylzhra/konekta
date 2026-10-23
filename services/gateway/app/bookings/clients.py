# Interfaces booking consumes (DESIGN.md §5.2, §5.7) plus their stub
# implementations. Stubs are selected by env flags in config.py; real
# implementations go behind the same Protocols.
import math
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Protocol

import httpx
import asyncpg
from pydantic import BaseModel, Field

from app.bookings import config
from app.bookings.models import GeoPoint, Stop, StopType


def haversine_m(a: GeoPoint, b: GeoPoint) -> float:
    earth_radius_m = 6_371_000.0
    phi1, phi2 = math.radians(a.lat), math.radians(b.lat)
    dphi = math.radians(b.lat - a.lat)
    dlambda = math.radians(b.lng - a.lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * earth_radius_m * math.asin(math.sqrt(h))


# --- StopAssigner -> pooling-service / stop-optimization-service -----------


class StopAssignmentRequest(BaseModel):
    location: GeoPoint
    seats: int = 1
    corridor_id: Optional[str] = None


class StopAssigner(Protocol):
    async def match_corridor(self, origin: GeoPoint, destination: GeoPoint) -> Optional[str]: ...

    async def is_active(self, stop: Stop) -> bool: ...

    async def assign_pickup_stop(self, request: StopAssignmentRequest) -> Optional[Stop]: ...

    async def assign_dropoff_stop(self, request: StopAssignmentRequest) -> Optional[Stop]: ...


def _placeholder_stop(index: int, lat: float, lng: float) -> Stop:
    return Stop(
        id=uuid.uuid5(uuid.NAMESPACE_URL, f"konekta:stub-stop:{index}"),
        type=StopType.STATIC,
        name=f"Halte Contoh {index} (placeholder)",
        location=GeoPoint(lat=lat, lng=lng),
        corridor_id="stub-corridor",
    )


# NOT real halte: placeholder points around central Bandung until real
# halte/corridor data exists (DESIGN.md §11).
STUB_STOPS: tuple[Stop, ...] = (
    _placeholder_stop(1, -6.9175, 107.6191),
    _placeholder_stop(2, -6.9025, 107.6186),
    _placeholder_stop(3, -6.8915, 107.6107),
    _placeholder_stop(4, -6.9339, 107.6044),
    _placeholder_stop(5, -6.9147, 107.6098),
)

# Rough Bandung service area for the stub; outside it -> no stop.
_STUB_AREA = (-7.05, -6.80, 107.50, 107.75)  # min_lat, max_lat, min_lng, max_lng


class StubStopAssigner:
    """Nearest placeholder static stop within walking distance, else a
    virtual stop at the requested point if inside the service area."""

    def __init__(self, clock=lambda: datetime.now(timezone.utc)) -> None:
        self._clock = clock

    def _in_area(self, point: GeoPoint) -> bool:
        min_lat, max_lat, min_lng, max_lng = _STUB_AREA
        return min_lat <= point.lat <= max_lat and min_lng <= point.lng <= max_lng

    def _assign(self, request: StopAssignmentRequest) -> Optional[Stop]:
        if not self._in_area(request.location):
            return None
        nearest = min(STUB_STOPS, key=lambda stop: haversine_m(stop.location, request.location))
        if haversine_m(nearest.location, request.location) <= config.MAX_WALK_TO_STOP_M:
            return nearest
        return Stop(
            id=uuid.uuid4(),
            type=StopType.VIRTUAL,
            name="Titik Jemput Virtual",
            location=request.location,
            corridor_id="stub-corridor",
            valid_until=self._clock() + timedelta(seconds=config.VIRTUAL_STOP_TTL_S),
        )

    async def assign_pickup_stop(self, request: StopAssignmentRequest) -> Optional[Stop]:
        return self._assign(request)

    async def assign_dropoff_stop(self, request: StopAssignmentRequest) -> Optional[Stop]:
        return self._assign(request)

    async def match_corridor(self, origin: GeoPoint, destination: GeoPoint) -> Optional[str]:
        return "stub-corridor" if self._in_area(origin) and self._in_area(destination) else None

    async def is_active(self, stop: Stop) -> bool:
        return stop.valid_until is None or stop.valid_until > self._clock()


class DbStopAssigner:
    """Assign only stored, currently active stops; never invent a stop."""

    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def match_corridor(self, origin: GeoPoint, destination: GeoPoint) -> Optional[str]:
        return await self._pool.fetchval(
            """SELECT id FROM corridors c
               WHERE c.path IS NOT NULL AND NOT c.is_dummy
                 AND ST_DWithin(c.path,
                       ST_SetSRID(ST_MakePoint($1, $2),4326)::geography, c.catchment_m)
                 AND ST_DWithin(c.path,
                       ST_SetSRID(ST_MakePoint($3, $4),4326)::geography, c.catchment_m)
                 AND (ST_LineLocatePoint(c.path::geometry,
                       ST_SetSRID(ST_MakePoint($3, $4),4326))
                    - ST_LineLocatePoint(c.path::geometry,
                       ST_SetSRID(ST_MakePoint($1, $2),4326))) * ST_Length(c.path) >= 300
               ORDER BY ST_Distance(c.path,
                        ST_SetSRID(ST_MakePoint($1, $2),4326)::geography)
                      + ST_Distance(c.path,
                        ST_SetSRID(ST_MakePoint($3, $4),4326)::geography)
               LIMIT 1""",
            origin.lng, origin.lat, destination.lng, destination.lat,
        )

    async def is_active(self, stop: Stop) -> bool:
        return bool(await self._pool.fetchval(
            """SELECT 1 FROM stops s
               WHERE s.id = $1 AND s.retired_at IS NULL
                 AND (s.valid_until IS NULL OR s.valid_until > now())
                 AND (s.type = 'static' OR EXISTS (
                      SELECT 1 FROM stop_candidates c
                      WHERE c.approved_stop_id = s.id AND c.status = 'approved'))""",
            stop.id,
        ))

    async def _assign(self, request: StopAssignmentRequest) -> Optional[Stop]:
        row = await self._pool.fetchrow(
            """SELECT s.id, s.type::text AS type, s.name, s.corridor_id, s.valid_until,
                      ST_Y(s.location::geometry) AS lat, ST_X(s.location::geometry) AS lng
               FROM stops s JOIN corridors c ON c.id = s.corridor_id
               WHERE s.retired_at IS NULL
                 AND (s.valid_until IS NULL OR s.valid_until > now())
                 AND (s.type = 'static' OR EXISTS (
                      SELECT 1 FROM stop_candidates candidate
                      WHERE candidate.approved_stop_id = s.id AND candidate.status = 'approved'))
                 AND c.path IS NOT NULL AND NOT c.is_dummy
                 AND ($3::text IS NULL OR s.corridor_id = $3)
                 AND ST_DWithin(s.location,
                      ST_SetSRID(ST_MakePoint($1, $2),4326)::geography, $4)
               ORDER BY ST_Distance(s.location,
                      ST_SetSRID(ST_MakePoint($1, $2),4326)::geography), s.id
               LIMIT 1""",
            request.location.lng, request.location.lat, request.corridor_id,
            config.MAX_WALK_TO_STOP_M,
        )
        if row is None:
            return None
        return Stop(
            id=row["id"], type=StopType(row["type"]), name=row["name"],
            location=GeoPoint(lat=row["lat"], lng=row["lng"]),
            corridor_id=row["corridor_id"], valid_until=row["valid_until"],
        )

    async def assign_pickup_stop(self, request: StopAssignmentRequest) -> Optional[Stop]:
        return await self._assign(request)

    async def assign_dropoff_stop(self, request: StopAssignmentRequest) -> Optional[Stop]:
        return await self._assign(request)


# --- FeederPositionProvider (owned by live tracking, DESIGN.md §5.2) --------


class FeederPosition(BaseModel):
    feeder_id: str
    lat: float
    lng: float
    heading: Optional[float] = None
    occupancy: int = 0
    capacity: int
    corridor_id: Optional[str] = None
    updated_at: datetime

    @property
    def location(self) -> GeoPoint:
        return GeoPoint(lat=self.lat, lng=self.lng)


class FeederPositionProvider(Protocol):
    async def get_last_known(self, feeder_id: str) -> Optional[FeederPosition]: ...

    async def nearest(
        self,
        lat: float,
        lng: float,
        radius_m: float,
        corridor_id: Optional[str] = None,
        limit: int = 5,
    ) -> list[FeederPosition]: ...


class StubFeederPositionProvider:
    """One fake feeder ~450 m north of any requested point (or none when
    STUB_FEEDER_SUPPLY=0). Stands in until live tracking's Redis GEO
    provider lands."""

    FEEDER_ID = "stub-feeder-1"

    def __init__(self, supply: bool = True, clock=lambda: datetime.now(timezone.utc)) -> None:
        self._supply = supply
        self._clock = clock
        self._last: dict[str, FeederPosition] = {}

    async def get_last_known(self, feeder_id: str) -> Optional[FeederPosition]:
        return self._last.get(feeder_id)

    async def nearest(
        self,
        lat: float,
        lng: float,
        radius_m: float,
        corridor_id: Optional[str] = None,
        limit: int = 5,
    ) -> list[FeederPosition]:
        if not self._supply:
            return []
        position = FeederPosition(
            feeder_id=self.FEEDER_ID,
            lat=lat + 0.004,
            lng=lng,
            occupancy=0,
            capacity=8,
            corridor_id=corridor_id,
            updated_at=self._clock(),
        )
        self._last[position.feeder_id] = position
        return [position]


# --- RoutingClient -> OSRM-compatible (DESIGN.md §5.7) ----------------------


class RouteResult(BaseModel):
    distance_m: float
    duration_s: float
    points: list[GeoPoint] = Field(default_factory=list)


class RoutingError(Exception):
    pass


class RoutingClient(Protocol):
    async def route(self, points: list[GeoPoint], profile: str = "driving") -> RouteResult: ...


class OsrmRoutingClient:
    """Calls /route/v1/{profile}/{lon,lat;...} on OSRM_BASE_URL (osrm-mock by
    default; real OSRM needs no code change)."""

    def __init__(
        self,
        base_url: str = config.OSRM_BASE_URL,
        timeout_s: float = config.ROUTING_TIMEOUT_S,
        transport: Optional[httpx.AsyncBaseTransport] = None,
        foot_base_url: str = config.OSRM_FOOT_BASE_URL,
        motorcycle_base_url: str = config.OSRM_MOTORCYCLE_BASE_URL,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._foot_base_url = foot_base_url.rstrip("/")
        self._motorcycle_base_url = motorcycle_base_url.rstrip("/")
        self._timeout_s = timeout_s
        self._transport = transport

    async def route(self, points: list[GeoPoint], profile: str = "driving", *, geometry: bool = False) -> RouteResult:
        if profile not in {"driving", "walking", "motorcycle"}:
            raise RoutingError(f"unsupported route profile: {profile}")
        base_url = {
            "driving": self._base_url,
            "walking": self._foot_base_url,
            "motorcycle": self._motorcycle_base_url,
        }[profile]
        coordinates = ";".join(f"{p.lng},{p.lat}" for p in points)
        url = f"{base_url}/route/v1/{profile}/{coordinates}"
        try:
            async with httpx.AsyncClient(timeout=self._timeout_s, transport=self._transport) as client:
                response = await client.get(url, params={"overview": "full" if geometry else "false", "geometries": "geojson"})
            response.raise_for_status()
            body = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise RoutingError("routing request failed") from exc
        if body.get("code") != "Ok" or not body.get("routes"):
            raise RoutingError("no route")
        best = body["routes"][0]
        coordinates = best.get("geometry", {}).get("coordinates", []) if geometry else []
        return RouteResult(
            distance_m=float(best["distance"]), duration_s=float(best["duration"]),
            points=[GeoPoint(lat=lat, lng=lng) for lng, lat in coordinates],
        )


def build_stop_assigner(pool: Optional[asyncpg.Pool] = None) -> StopAssigner:
    if config.STOP_ASSIGNER == "stub":
        return StubStopAssigner()
    if config.STOP_ASSIGNER == "db" and pool is not None:
        return DbStopAssigner(pool)
    raise ValueError(f"Unknown STOP_ASSIGNER={config.STOP_ASSIGNER!r}")


def build_feeder_provider() -> FeederPositionProvider:
    if config.FEEDER_PROVIDER == "stub":
        return StubFeederPositionProvider(supply=config.STUB_FEEDER_SUPPLY)
    raise ValueError(f"Unknown FEEDER_PROVIDER={config.FEEDER_PROVIDER!r}")

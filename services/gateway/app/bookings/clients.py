# Interfaces booking consumes (DESIGN.md §5.2, §5.7) plus their stub
# implementations. Stubs are selected by env flags in config.py; real
# implementations go behind the same Protocols.
import math
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Protocol

import httpx
from pydantic import BaseModel

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
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout_s = timeout_s
        self._transport = transport

    async def route(self, points: list[GeoPoint], profile: str = "driving") -> RouteResult:
        coordinates = ";".join(f"{p.lng},{p.lat}" for p in points)
        url = f"{self._base_url}/route/v1/{profile}/{coordinates}"
        try:
            async with httpx.AsyncClient(timeout=self._timeout_s, transport=self._transport) as client:
                response = await client.get(url, params={"overview": "false"})
            response.raise_for_status()
            body = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise RoutingError("routing request failed") from exc
        if body.get("code") != "Ok" or not body.get("routes"):
            raise RoutingError("no route")
        best = body["routes"][0]
        return RouteResult(distance_m=float(best["distance"]), duration_s=float(best["duration"]))


def build_stop_assigner() -> StopAssigner:
    if config.STOP_ASSIGNER == "stub":
        return StubStopAssigner()
    raise ValueError(f"Unknown STOP_ASSIGNER={config.STOP_ASSIGNER!r}")


def build_feeder_provider() -> FeederPositionProvider:
    if config.FEEDER_PROVIDER == "stub":
        return StubFeederPositionProvider(supply=config.STUB_FEEDER_SUPPLY)
    raise ValueError(f"Unknown FEEDER_PROVIDER={config.FEEDER_PROVIDER!r}")

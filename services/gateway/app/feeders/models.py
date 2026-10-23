from datetime import datetime
from enum import StrEnum
from typing import Optional
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field


class FeederErrorCode(StrEnum):
    NO_FEEDER_ASSIGNED = "no_feeder_assigned"
    OUTSIDE_SERVICE_AREA = "outside_service_area"
    INACCURATE_POSITION = "inaccurate_position"
    TOO_FREQUENT = "too_frequent"
    INVALID_DEVICE = "invalid_device"
    OFF_DUTY = "off_duty"
    STALE_FIX = "stale_fix"
    NO_FIX = "no_fix"


class FeederError(Exception):
    def __init__(self, code: FeederErrorCode, status_code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code
        self.message = message


class FeederOption(BaseModel):
    id: str
    number: int
    capacity: int
    available: bool


class CorridorWithFeeders(BaseModel):
    id: str
    name: str
    is_dummy: bool = False
    feeders: list[FeederOption]


class CorridorList(BaseModel):
    items: list[CorridorWithFeeders]


class RouteStop(BaseModel):
    position: int
    name: str
    lat: Optional[float] = None
    lng: Optional[float] = None


class CorridorStops(BaseModel):
    id: str
    name: str
    is_dummy: bool = False
    items: list[RouteStop]


class RoutePoint(BaseModel):
    lat: float
    lng: float


class CorridorPath(BaseModel):
    id: str
    points: list[RoutePoint]


class AssignedFeeder(BaseModel):
    id: str
    number: int
    capacity: int
    corridor_id: str
    corridor_name: str


class PositionReport(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    heading: Optional[float] = Field(default=None, ge=0, lt=360)
    accuracy_m: Optional[float] = Field(default=None, ge=0)


class LiveFeeder(BaseModel):
    """Same shape as the `feeder.position` WS payload."""

    feeder_id: str
    lat: float
    lng: float
    heading: Optional[float] = None
    occupancy: int
    capacity: int
    corridor_id: Optional[str] = None
    updated_at: datetime


class LiveFeederList(BaseModel):
    items: list[LiveFeeder]


class PositionAccepted(BaseModel):
    feeder_id: str
    updated_at: datetime


class DeviceFeeder(BaseModel):
    """A registered IoT device and the feeder vehicle it is mounted in."""

    device_id: str
    token_hash: str
    active: bool
    feeder: AssignedFeeder
    driver_id: Optional[UUID] = None


class DevicePositionReport(BaseModel):
    # Ranges are checked by the service, not here, so that garbage coordinates
    # (e.g. the NEO-6M's 0,0 before a fix) also count against the device.
    lat: float = Field(allow_inf_nan=False)
    lng: float = Field(allow_inf_nan=False)
    recorded_at: AwareDatetime
    accuracy_m: float = Field(ge=0, allow_inf_nan=False)
    satellites: Optional[int] = Field(default=None, ge=0)
    heading: Optional[float] = Field(default=None, ge=0, lt=360)
    speed_kmh: Optional[float] = Field(default=None, ge=0)


class DevicePositionAccepted(BaseModel):
    feeder_id: str
    updated_at: datetime
    # True when this fix was published; False while the device is still
    # proving itself stable and the driver app remains the source.
    primary: bool

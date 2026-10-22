from datetime import datetime
from enum import StrEnum
from typing import Optional

from pydantic import BaseModel, Field


class FeederErrorCode(StrEnum):
    NO_FEEDER_ASSIGNED = "no_feeder_assigned"
    OUTSIDE_SERVICE_AREA = "outside_service_area"
    INACCURATE_POSITION = "inaccurate_position"
    TOO_FREQUENT = "too_frequent"


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
    feeders: list[FeederOption]


class CorridorList(BaseModel):
    items: list[CorridorWithFeeders]


class RouteStop(BaseModel):
    position: int
    name: str


class CorridorStops(BaseModel):
    id: str
    name: str
    items: list[RouteStop]


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

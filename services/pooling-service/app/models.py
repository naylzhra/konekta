"""Request/response models for demand clustering (DESIGN.md §13).

The service is stateless: the gateway (system of record) sends corridors and
a window of trip requests, and stores what comes back. Requests carry a
pseudonymous `requester_key` (per-run hash), never a user id.
"""
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import AwareDatetime, BaseModel, Field, model_validator


class GeoPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class Corridor(BaseModel):
    id: str = Field(min_length=1, max_length=32)
    # Ordered route of the corridor; "forward" travel follows this order.
    path: list[GeoPoint] = Field(min_length=2)
    # Max distance from the path for an origin/destination to belong to it.
    catchment_m: float = Field(default=800, gt=0)


class Direction(str, Enum):
    FORWARD = "forward"
    BACKWARD = "backward"


class StopEndpoint(str, Enum):
    """Which end of the trip is clustered: origins (pickup stops) or
    destinations (drop-off stops)."""

    PICKUP = "pickup"
    DROPOFF = "dropoff"


class DemandRequest(BaseModel):
    id: str = Field(min_length=1, max_length=64)
    requester_key: str = Field(min_length=1, max_length=128)
    origin: GeoPoint
    destination: GeoPoint
    requested_at: AwareDatetime
    seats: int = Field(default=1, ge=1, le=4)


class PoolingParams(BaseModel):
    """Defaults are starting points to tune with real Bandung demand."""

    # DBSCAN neighbourhood radius (ε) and minimum points (MinPts).
    eps_m: float = Field(default=150, gt=0)
    min_pts: int = Field(default=4, ge=2)
    # Requests are only pooled with others in the same time-of-day slot.
    slot_minutes: int = Field(default=60, ge=15, le=240)
    # A trip must move at least this far along the corridor to use it.
    min_corridor_progress_m: float = Field(default=300, ge=0)
    # Hotspot validation thresholds.
    min_unique_users: int = Field(default=5, ge=1)
    max_radius_p80_m: float = Field(default=250, gt=0)
    min_active_days: int = Field(default=3, ge=1)
    min_temporal_consistency: float = Field(default=0.3, ge=0, le=1)
    # Older requests weigh less in the centroid.
    recency_half_life_days: float = Field(default=14, gt=0)

    @model_validator(mode="after")
    def _slot_divides_day(self) -> "PoolingParams":
        if (24 * 60) % self.slot_minutes:
            raise ValueError("slot_minutes must divide 1440")
        return self


class ClusterRequest(BaseModel):
    endpoint: StopEndpoint = StopEndpoint.PICKUP
    window_start: AwareDatetime
    window_end: AwareDatetime
    corridors: list[Corridor] = Field(min_length=1)
    requests: list[DemandRequest] = Field(max_length=50_000)
    params: PoolingParams = PoolingParams()

    @model_validator(mode="after")
    def _window_order(self) -> "ClusterRequest":
        if self.window_end <= self.window_start:
            raise ValueError("window_end must be after window_start")
        return self


class HotspotCheck(str, Enum):
    UNIQUE_USERS = "unique_users"
    SPATIAL_CONCENTRATION = "spatial_concentration"
    TEMPORAL_CONSISTENCY = "temporal_consistency"


class DemandCluster(BaseModel):
    cluster_id: str
    corridor_id: str
    direction: Direction
    endpoint: StopEndpoint
    # Index of the time-of-day slot (WIB), and its start as "HH:MM".
    time_slot: int
    slot_start: str
    member_ids: list[str]
    size: int
    unique_users: int
    active_days: int
    observed_days: int
    temporal_consistency: float
    radius_p80_m: float
    centroid: GeoPoint
    # Set only for validated clusters (candidates); others are history.
    snapped_location: Optional[GeoPoint] = None
    snap_distance_m: Optional[float] = None
    validated: bool
    failed_checks: list[HotspotCheck]


class ClusterSummary(BaseModel):
    requests: int
    outside_window: int
    no_corridor: int
    noise: int
    clusters: int
    validated: int


class ClusterResponse(BaseModel):
    generated_at: datetime
    clusters: list[DemandCluster]
    summary: ClusterSummary

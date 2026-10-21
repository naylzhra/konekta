"""Request/response models for stop-candidate evaluation (DESIGN.md §13.5)
and feeder stop priority (§13.7).

Stateless like pooling-service: the gateway sends candidates, corridors,
existing stops and restricted zones, and stores the result. Demand points
carry no identifiers.
"""
from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, Field


class GeoPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class Corridor(BaseModel):
    id: str = Field(min_length=1, max_length=32)
    path: list[GeoPoint] = Field(min_length=2)


class DemandPoint(BaseModel):
    """Where one request in the candidate's cluster starts (or ends)."""

    location: GeoPoint
    weight: float = Field(default=1.0, gt=0)


class StopCandidate(BaseModel):
    candidate_id: str = Field(min_length=1, max_length=64)
    corridor_id: str
    # Road-snapped weighted centroid from pooling-service.
    location: GeoPoint
    demand_points: list[DemandPoint] = Field(min_length=1)
    unique_users: int = Field(ge=1)


class ExistingStop(BaseModel):
    id: str
    location: GeoPoint
    corridor_id: Optional[str] = None
    type: Literal["static", "virtual"]


class RestrictionKind(str, Enum):
    INTERSECTION = "intersection"
    NO_STOPPING = "no_stopping"
    OTHER = "other"


class RestrictedZone(BaseModel):
    """Where a feeder must not stop (traffic safety), e.g. around junctions."""

    id: str
    kind: RestrictionKind
    location: GeoPoint
    radius_m: float = Field(gt=0)


class EvaluationParams(BaseModel):
    """Starting values; the regulatory ones must be confirmed with Dishub
    Kota Bandung before production use."""

    # Corridor coverage: the stop must sit on the corridor's route.
    corridor_buffer_m: float = Field(default=100, gt=0)
    # Pedestrian accessibility: estimated walk = straight line × detour factor.
    walk_detour_factor: float = Field(default=1.3, ge=1)
    max_walk_m: float = Field(default=400, gt=0)
    min_walk_coverage: float = Field(default=0.8, ge=0, le=1)
    # Regulation: service distance between stops, how far an existing stop
    # may be shifted, and the extra feeder travel time a stop may add.
    min_stop_spacing_m: float = Field(default=300, ge=0)
    max_shift_m: float = Field(default=500, ge=0)
    max_added_travel_s: float = Field(default=120, gt=0)
    # Traffic safety: clearance from a restricted zone that scores full marks.
    safety_reference_m: float = Field(default=50, gt=0)
    # Ranking weights for eligible candidates (sum to 1).
    weight_demand: float = Field(default=0.4, ge=0)
    weight_access: float = Field(default=0.25, ge=0)
    weight_travel_time: float = Field(default=0.2, ge=0)
    weight_safety: float = Field(default=0.15, ge=0)


class EvaluateRequest(BaseModel):
    candidates: list[StopCandidate] = Field(min_length=1, max_length=500)
    corridors: list[Corridor] = Field(min_length=1)
    existing_stops: list[ExistingStop] = []
    restricted_zones: list[RestrictedZone] = []
    params: EvaluationParams = EvaluationParams()


class Criterion(str, Enum):
    CORRIDOR_COVERAGE = "corridor_coverage"
    PEDESTRIAN_ACCESS = "pedestrian_access"
    TRAFFIC_SAFETY = "traffic_safety"
    STOP_SPACING = "stop_spacing"
    OPERATIONAL_TIME = "operational_time"


class CriterionResult(BaseModel):
    criterion: Criterion
    passed: bool
    value: float
    threshold: float
    detail: Optional[str] = None


class CandidateEvaluation(BaseModel):
    candidate_id: str
    eligible: bool
    # 1 = best; only eligible candidates are ranked.
    rank: Optional[int] = None
    score: float
    # Shift an existing stop (within max_shift_m) or add a new one.
    action: Literal["new_stop", "relocate_stop"]
    relocates_stop_id: Optional[str] = None
    corridor_offset_m: float
    walk_p85_m: float
    walk_coverage: float
    added_travel_s: float
    nearest_restriction_clearance_m: Optional[float] = None
    checks: list[CriterionResult]


class EvaluateResponse(BaseModel):
    evaluations: list[CandidateEvaluation]


# --- feeder operations (§13.7) ---------------------------------------------


class FeederStopSignal(BaseModel):
    stop_id: str
    # Passengers with an active booking waiting at this stop.
    active_demand: int = Field(ge=0)
    # Extra driving time for this feeder to serve the stop.
    detour_s: float = Field(ge=0)
    seconds_since_served: float = Field(ge=0)


class FeederHeuristicParams(BaseModel):
    weight_demand: float = Field(default=0.5, ge=0)
    weight_detour: float = Field(default=0.3, ge=0)
    weight_recency: float = Field(default=0.2, ge=0)
    # Detour at/after which the penalty is maxed out.
    max_detour_s: float = Field(default=600, gt=0)
    # Waiting time at/after which the recency bonus is maxed out.
    recency_cap_s: float = Field(default=1800, gt=0)


class FeederPriorityRequest(BaseModel):
    signals: list[FeederStopSignal] = Field(max_length=500)
    params: FeederHeuristicParams = FeederHeuristicParams()


class ScoredStop(BaseModel):
    stop_id: str
    score: float


class FeederPriorityResponse(BaseModel):
    items: list[ScoredStop]

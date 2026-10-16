"""Demand hotspot validation (DESIGN.md §13.3): is a DBSCAN cluster real,
recurring demand worth a stop, or one-off noise to keep only as history?"""
from dataclasses import dataclass
from datetime import date

import numpy as np

from app.geo import haversine_m
from app.models import GeoPoint, HotspotCheck, PoolingParams


@dataclass(frozen=True)
class HotspotStats:
    unique_users: int
    active_days: int
    observed_days: int
    temporal_consistency: float
    radius_p80_m: float


def hotspot_stats(
    requester_keys: list[str],
    local_dates: list[date],
    points: list[GeoPoint],
    centroid: GeoPoint,
    observed_days: int,
) -> HotspotStats:
    active_days = len(set(local_dates))
    distances = [haversine_m(point, centroid) for point in points]
    return HotspotStats(
        # Volume counts people, not requests: one rider re-planning ten
        # times is one unit of demand.
        unique_users=len(set(requester_keys)),
        active_days=active_days,
        observed_days=observed_days,
        temporal_consistency=active_days / observed_days,
        radius_p80_m=float(np.percentile(distances, 80)),
    )


def failed_checks(stats: HotspotStats, params: PoolingParams) -> list[HotspotCheck]:
    failed = []
    if stats.unique_users < params.min_unique_users:
        failed.append(HotspotCheck.UNIQUE_USERS)
    if stats.radius_p80_m > params.max_radius_p80_m:
        failed.append(HotspotCheck.SPATIAL_CONCENTRATION)
    if stats.active_days < params.min_active_days or stats.temporal_consistency < params.min_temporal_consistency:
        failed.append(HotspotCheck.TEMPORAL_CONSISTENCY)
    return failed

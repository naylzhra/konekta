"""Demand-weighted centroid of a cluster (DESIGN.md §13.4).

Each request weighs `seats × 0.5^(age_days / half_life)`, so recent demand
pulls the stop harder than old demand. Snapping the result onto the road
network happens afterwards via OSRM `/nearest` (app/osrm_client.py).
"""
from datetime import datetime
from typing import Optional

from app.geo import LocalProjection
from app.models import GeoPoint

SECONDS_PER_DAY = 86_400


def recency_weight(seats: int, requested_at: datetime, reference: datetime, half_life_days: float) -> float:
    age_days = max(0.0, (reference - requested_at).total_seconds() / SECONDS_PER_DAY)
    return seats * 0.5 ** (age_days / half_life_days)


def weighted_centroid(points_with_weights: list[tuple[GeoPoint, float]]) -> Optional[GeoPoint]:
    """None for no points or zero total weight."""
    total_weight = sum(weight for _, weight in points_with_weights)
    if not points_with_weights or total_weight <= 0:
        return None
    projection = LocalProjection(points_with_weights[0][0])
    x = y = 0.0
    for point, weight in points_with_weights:
        px, py = projection.to_xy(point)
        x += px * weight
        y += py * weight
    return projection.to_point(x / total_weight, y / total_weight)

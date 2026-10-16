"""DBSCAN over demand points (DESIGN.md §13.2).

Uses the haversine metric, so ε is a real ground distance in metres rather
than degrees. Callers partition by corridor, direction and time slot first;
this module only does the spatial step.
"""
import numpy as np
from sklearn.cluster import DBSCAN

from app.geo import EARTH_RADIUS_M
from app.models import GeoPoint

NOISE = -1


def cluster_demand_points(points: list[GeoPoint], eps_m: float, min_pts: int) -> list[int]:
    """One label per point; NOISE (-1) for points in no cluster."""
    if not points:
        return []
    coordinates = np.radians([[p.lat, p.lng] for p in points])
    model = DBSCAN(eps=eps_m / EARTH_RADIUS_M, min_samples=min_pts, metric="haversine", algorithm="ball_tree")
    return [int(label) for label in model.fit_predict(coordinates)]

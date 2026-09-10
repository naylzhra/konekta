"""
DBSCAN clustering for demand pooling.

TODO: implement real clustering logic (parameter tuning, feature scaling,
integration with live demand-point stream). This is a placeholder so the
service boots and the module shape is stable for callers to build against.
"""
from sklearn.cluster import DBSCAN


def cluster_demand_points(points: list[tuple[float, float]], eps: float = 0.3, min_samples: int = 3):
    """
    points: list of (lat, lon) pairs.
    Returns sklearn DBSCAN cluster labels (-1 = noise). Not yet wired into
    any endpoint.
    """
    if not points:
        return []
    model = DBSCAN(eps=eps, min_samples=min_samples)
    return model.fit_predict(points)

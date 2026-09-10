"""
Weighted centroid computation for virtual stop placement.

TODO: implement demand-weighted centroid + snap-to-road (via
app/osrm_client.py) so the centroid lands on a driveable road segment
instead of floating in the middle of a block. Placeholder only.
"""


def weighted_centroid(points_with_weights: list[tuple[tuple[float, float], float]]):
    """
    points_with_weights: list of ((lat, lon), weight) tuples.
    Returns (lat, lon) of the weighted centroid, or None if empty.
    """
    if not points_with_weights:
        return None
    total_weight = sum(weight for _, weight in points_with_weights)
    if total_weight == 0:
        return None
    lat = sum(point[0] * weight for point, weight in points_with_weights) / total_weight
    lon = sum(point[1] * weight for point, weight in points_with_weights) / total_weight
    return lat, lon

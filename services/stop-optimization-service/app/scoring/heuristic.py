"""
Heuristic scoring for candidate virtual stop locations.

TODO: implement the real scoring model. Planned inputs:
  - demand density (from pooling-service clusters)
  - route-deviation cost (added detour for the feeder vehicle)
  - time-since-last-served (recency, to avoid starving low-traffic areas)

This is a placeholder so downstream services can import a stable function
signature while the real weighting/tuning is worked out.
"""
from typing import Optional


def score_candidate_stop(
    demand_density: float,
    route_deviation_cost: float,
    time_since_last_served: float,
    weights: Optional[dict] = None,
) -> float:
    weights = weights or {"demand": 0.5, "deviation": -0.3, "recency": 0.2}
    return (
        weights["demand"] * demand_density
        + weights["deviation"] * route_deviation_cost
        + weights["recency"] * time_since_last_served
    )

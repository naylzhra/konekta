"""
Feeder operations heuristic (DESIGN.md §13.7): which active stop a feeder
should serve next.

    score = w_demand  · active_demand / max_active_demand
          − w_detour  · min(detour_s / max_detour_s, 1)
          + w_recency · min(seconds_since_served / recency_cap_s, 1)

Demand density pulls the feeder to busy stops, the detour term keeps it from
zig-zagging off its run, and the recency term stops quiet stops from
starving. Stops with nobody waiting are not ranked.
"""
from app.models import FeederHeuristicParams, FeederStopSignal, ScoredStop


def score_feeder_stop(signal: FeederStopSignal, max_active_demand: int, params: FeederHeuristicParams) -> float:
    demand = signal.active_demand / max_active_demand if max_active_demand else 0.0
    detour = min(signal.detour_s / params.max_detour_s, 1.0)
    recency = min(signal.seconds_since_served / params.recency_cap_s, 1.0)
    return params.weight_demand * demand - params.weight_detour * detour + params.weight_recency * recency


def rank_feeder_stops(signals: list[FeederStopSignal], params: FeederHeuristicParams) -> list[ScoredStop]:
    waiting = [s for s in signals if s.active_demand > 0]
    max_active_demand = max((s.active_demand for s in waiting), default=0)
    scored = [ScoredStop(stop_id=s.stop_id, score=round(score_feeder_stop(s, max_active_demand, params), 4)) for s in waiting]
    return sorted(scored, key=lambda s: -s.score)

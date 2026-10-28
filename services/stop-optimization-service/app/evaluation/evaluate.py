"""Virtual stop candidate evaluation (DESIGN.md §13.5).

Every candidate is checked against hard criteria; the ones that pass all of
them are ranked by a weighted score:

- corridor coverage: the stop sits on the corridor route;
- pedestrian accessibility: most of the cluster's riders can walk to it;
- traffic safety: it is outside every restricted zone (junctions, no-stopping);
- regulation (Dishub): it keeps the minimum service distance to other stops,
  and the detour it adds to the feeder's run stays within the time limit.
  A candidate within `max_shift_m` of an existing stop on its corridor is a
  proposal to shift that stop rather than to add a new one.

Within one batch, a candidate that would sit too close to a better-scoring
one (or shift the same stop) is dropped, so recommendations never conflict.
"""
from typing import Awaitable, Callable, Optional

import numpy as np

from app.geo import haversine_m, project_onto_path
from app.models import (
    CandidateEvaluation,
    Corridor,
    Criterion,
    CriterionResult,
    EvaluateRequest,
    EvaluationParams,
    ExistingStop,
    RestrictedZone,
    StopCandidate,
)

# Driving duration through the given points, in seconds.
Router = Callable[[list], Awaitable[float]]


class UnknownCorridor(ValueError):
    pass


def _walk_metrics(candidate: StopCandidate, params: EvaluationParams) -> tuple[float, float]:
    """(85th-percentile walk in metres, demand-weighted share within max walk)."""
    walks = [haversine_m(p.location, candidate.location) * params.walk_detour_factor for p in candidate.demand_points]
    weights = [p.weight for p in candidate.demand_points]
    within = sum(w for walk, w in zip(walks, weights) if walk <= params.max_walk_m)
    return float(np.percentile(walks, 85)), within / sum(weights)


def _nearest_clearance(candidate: StopCandidate, zones: list[RestrictedZone]) -> Optional[float]:
    """Distance to the edge of the closest restricted zone (negative = inside)."""
    if not zones:
        return None
    return min(haversine_m(candidate.location, zone.location) - zone.radius_m for zone in zones)


def _relocation_target(
    candidate: StopCandidate, stops: list[ExistingStop], params: EvaluationParams
) -> Optional[tuple[ExistingStop, float]]:
    if params.max_shift_m == 0:
        return None
    same_corridor = [s for s in stops if s.corridor_id == candidate.corridor_id]
    if not same_corridor:
        return None
    nearest = min(same_corridor, key=lambda s: haversine_m(s.location, candidate.location))
    distance = haversine_m(nearest.location, candidate.location)
    return (nearest, distance) if distance <= params.max_shift_m else None


async def _added_travel_s(candidate: StopCandidate, corridor: Corridor, route: Router) -> float:
    """Extra feeder driving time to call at the candidate: leave the corridor
    at its closest point, drive to the stop, and come back. (Comparing
    segment-start -> stop -> segment-end with the direct segment would make
    a stop far off a long, straight segment look almost free.)"""
    leave_at = project_onto_path(candidate.location, corridor.path).point
    return await route([leave_at, candidate.location, leave_at])


async def _evaluate_one(
    candidate: StopCandidate,
    corridor: Corridor,
    request: EvaluateRequest,
    route: Router,
    max_unique_users: int,
) -> CandidateEvaluation:
    params = request.params
    offset_m = project_onto_path(candidate.location, corridor.path).offset_m
    walk_p85, walk_coverage = _walk_metrics(candidate, params)
    clearance = _nearest_clearance(candidate, request.restricted_zones)
    relocation = _relocation_target(candidate, request.existing_stops, params)
    relocated_id = relocation[0].id if relocation else None
    other_stops = [
        s for s in request.existing_stops if s.corridor_id == candidate.corridor_id and s.id != relocated_id
    ]
    # Automatic new-stop proposals (max_shift_m=0) must sit between two
    # operational stops along the corridor, never beyond an endpoint.
    candidate_progress = project_onto_path(candidate.location, corridor.path).along_m
    stop_progress = [project_onto_path(s.location, corridor.path).along_m for s in other_stops]
    between_stops = any(p < candidate_progress for p in stop_progress) and any(
        p > candidate_progress for p in stop_progress
    )
    adjacent_gap = 0.0
    if between_stops:
        before = max(p for p in stop_progress if p < candidate_progress)
        after = min(p for p in stop_progress if p > candidate_progress)
        adjacent_gap = after - before
    spacing = min((haversine_m(s.location, candidate.location) for s in other_stops), default=float("inf"))
    spacing_value = adjacent_gap if params.max_shift_m == 0 else spacing
    spacing_passed = (
        adjacent_gap > params.min_stop_spacing_m
        if params.max_shift_m == 0
        else spacing >= params.min_stop_spacing_m
    )
    added_s = await _added_travel_s(candidate, corridor, route)

    checks = [
        CriterionResult(
            criterion=Criterion.CORRIDOR_COVERAGE,
            passed=offset_m <= params.corridor_buffer_m,
            value=round(offset_m, 1),
            threshold=params.corridor_buffer_m,
        ),
        CriterionResult(
            criterion=Criterion.PEDESTRIAN_ACCESS,
            passed=walk_coverage >= params.min_walk_coverage,
            value=round(walk_coverage, 4),
            threshold=params.min_walk_coverage,
            detail=f"p85 walk {walk_p85:.0f} m",
        ),
        CriterionResult(
            criterion=Criterion.TRAFFIC_SAFETY,
            passed=clearance is None or clearance >= 0,
            value=round(clearance, 1) if clearance is not None else 0.0,
            threshold=0.0,
            detail=None if clearance is not None else "no restricted zones provided",
        ),
        CriterionResult(
            criterion=Criterion.STOP_SPACING,
            passed=spacing_passed and (params.max_shift_m > 0 or between_stops),
            value=round(spacing_value, 1) if other_stops else 0.0,
            threshold=params.min_stop_spacing_m,
            detail=("candidate must be between two stops" if params.max_shift_m == 0 and not between_stops
                    else "neighboring stop gap must exceed threshold" if params.max_shift_m == 0 and not spacing_passed
                    else None if other_stops else "no other stops on this corridor"),
        ),
        CriterionResult(
            criterion=Criterion.OPERATIONAL_TIME,
            passed=added_s <= params.max_added_travel_s,
            value=round(added_s, 1),
            threshold=params.max_added_travel_s,
        ),
    ]

    safety = 1.0 if clearance is None else max(0.0, min(1.0, clearance / params.safety_reference_m))
    score = (
        params.weight_demand * candidate.unique_users / max_unique_users
        + params.weight_access * walk_coverage
        + params.weight_travel_time * (1 - min(added_s / params.max_added_travel_s, 1.0))
        + params.weight_safety * safety
    )
    return CandidateEvaluation(
        candidate_id=candidate.candidate_id,
        eligible=all(check.passed for check in checks),
        score=round(score, 4),
        action="relocate_stop" if relocation else "new_stop",
        relocates_stop_id=relocated_id,
        corridor_offset_m=round(offset_m, 1),
        walk_p85_m=round(walk_p85, 1),
        walk_coverage=round(walk_coverage, 4),
        added_travel_s=round(added_s, 1),
        nearest_restriction_clearance_m=None if clearance is None else round(clearance, 1),
        checks=checks,
    )


def _resolve_conflicts(
    evaluations: list[CandidateEvaluation], locations: dict, params: EvaluationParams
) -> None:
    """Greedy by score: keep a candidate only if it is far enough from every
    already-kept one and doesn't shift a stop that one already shifts."""
    kept: list[CandidateEvaluation] = []
    for evaluation in sorted(evaluations, key=lambda e: -e.score):
        if not evaluation.eligible:
            continue
        conflict = next(
            (
                other
                for other in kept
                if params.max_shift_m > 0
                and haversine_m(locations[other.candidate_id], locations[evaluation.candidate_id])
                < params.min_stop_spacing_m
                or (evaluation.relocates_stop_id is not None and evaluation.relocates_stop_id == other.relocates_stop_id)
            ),
            None,
        )
        if conflict is None:
            kept.append(evaluation)
            continue
        evaluation.eligible = False
        for check in evaluation.checks:
            if check.criterion == Criterion.STOP_SPACING:
                check.passed = False
                check.detail = f"conflicts with higher-scoring candidate {conflict.candidate_id}"
    for rank, evaluation in enumerate(kept, start=1):
        evaluation.rank = rank


async def evaluate_candidates(request: EvaluateRequest, route: Router) -> list[CandidateEvaluation]:
    corridors = {c.id: c for c in request.corridors}
    unknown = sorted({c.corridor_id for c in request.candidates} - corridors.keys())
    if unknown:
        raise UnknownCorridor(", ".join(unknown))
    max_unique_users = max(c.unique_users for c in request.candidates)
    evaluations = [
        await _evaluate_one(candidate, corridors[candidate.corridor_id], request, route, max_unique_users)
        for candidate in request.candidates
    ]
    _resolve_conflicts(evaluations, {c.candidate_id: c.location for c in request.candidates}, request.params)
    # Ranked recommendations first, then the rest by score.
    return sorted(evaluations, key=lambda e: (e.rank is None, e.rank or 0, -e.score))

import pytest
from fastapi.testclient import TestClient

from app.evaluation.evaluate import evaluate_candidates
from app.geo import haversine_m
from app.main import app, get_router
from app.models import (
    Corridor,
    Criterion,
    DemandPoint,
    EvaluateRequest,
    ExistingStop,
    FeederHeuristicParams,
    FeederStopSignal,
    GeoPoint,
    RestrictedZone,
    RestrictionKind,
    StopCandidate,
)
from app.routing import OsrmUnavailable
from app.scoring.heuristic import rank_feeder_stops

CORRIDOR = Corridor(id="K1", path=[GeoPoint(lat=-6.95, lng=107.61), GeoPoint(lat=-6.87, lng=107.61)])
ON_ROUTE = GeoPoint(lat=-6.93, lng=107.61)
M_PER_DEG = 111_195.0
SPEED_MPS = 25 / 3.6


def offset(point: GeoPoint, north_m: float = 0, east_m: float = 0) -> GeoPoint:
    return GeoPoint(lat=point.lat + north_m / M_PER_DEG, lng=point.lng + east_m / (M_PER_DEG * 0.9927))


async def straight_line_router(points: list[GeoPoint]) -> float:
    """Same model as osrm-mock: straight lines at 25 km/h."""
    return sum(haversine_m(a, b) for a, b in zip(points, points[1:])) / SPEED_MPS


def candidate(cid: str, location: GeoPoint, users: int = 6, spread_m: float = 50) -> StopCandidate:
    return StopCandidate(
        candidate_id=cid,
        corridor_id="K1",
        location=location,
        demand_points=[DemandPoint(location=offset(location, north_m=spread_m * (i % 3 - 1), east_m=20)) for i in range(users)],
        unique_users=users,
    )


def check(evaluation, criterion: Criterion):
    return next(c for c in evaluation.checks if c.criterion == criterion)


async def evaluate(*candidates: StopCandidate, **extra) -> list:
    return await evaluate_candidates(EvaluateRequest(candidates=list(candidates), corridors=[CORRIDOR], **extra), straight_line_router)


async def test_good_candidate_is_eligible_new_stop() -> None:
    [result] = await evaluate(candidate("a", offset(ON_ROUTE, east_m=10)))
    assert result.eligible and result.rank == 1
    assert result.action == "new_stop" and result.relocates_stop_id is None
    assert all(c.passed for c in result.checks)
    # 10 m off the route = ~20 m extra driving at 25 km/h.
    assert result.added_travel_s == pytest.approx(20 / SPEED_MPS, abs=0.5)


async def test_off_corridor_candidate_fails_coverage_and_time() -> None:
    [result] = await evaluate(candidate("far", offset(ON_ROUTE, east_m=500)))
    assert not result.eligible and result.rank is None
    assert not check(result, Criterion.CORRIDOR_COVERAGE).passed
    # ~1 km round trip off the route at 25 km/h = ~144 s > 120 s.
    assert not check(result, Criterion.OPERATIONAL_TIME).passed


async def test_scattered_riders_fail_pedestrian_access() -> None:
    [result] = await evaluate(candidate("wide", ON_ROUTE, spread_m=600))
    assert not check(result, Criterion.PEDESTRIAN_ACCESS).passed
    assert result.walk_coverage < 0.8


async def test_restricted_zone_fails_traffic_safety() -> None:
    junction = RestrictedZone(id="j1", kind=RestrictionKind.INTERSECTION, location=offset(ON_ROUTE, north_m=20), radius_m=30)
    [result] = await evaluate(candidate("unsafe", ON_ROUTE), restricted_zones=[junction])
    safety = check(result, Criterion.TRAFFIC_SAFETY)
    assert not safety.passed and safety.value == pytest.approx(-10, abs=1)


async def test_near_existing_stop_is_a_relocation() -> None:
    halte = ExistingStop(id="halte-1", location=offset(ON_ROUTE, north_m=200), corridor_id="K1", type="static")
    [result] = await evaluate(candidate("shift", ON_ROUTE), existing_stops=[halte])
    assert result.eligible
    assert (result.action, result.relocates_stop_id) == ("relocate_stop", "halte-1")


async def test_spacing_checked_against_other_stops() -> None:
    shifted = ExistingStop(id="h1", location=offset(ON_ROUTE, north_m=100), corridor_id="K1", type="static")
    neighbour = ExistingStop(id="h2", location=offset(ON_ROUTE, north_m=-250), corridor_id="K1", type="static")
    [result] = await evaluate(candidate("tight", ON_ROUTE), existing_stops=[shifted, neighbour])
    assert result.relocates_stop_id == "h1"
    spacing = check(result, Criterion.STOP_SPACING)
    assert not spacing.passed and spacing.value == pytest.approx(250, abs=1)


async def test_stops_on_other_corridors_are_ignored() -> None:
    other = ExistingStop(id="k2", location=offset(ON_ROUTE, north_m=50), corridor_id="K2", type="static")
    [result] = await evaluate(candidate("a", ON_ROUTE), existing_stops=[other])
    assert result.action == "new_stop" and result.eligible


async def test_conflicting_candidates_keep_the_better_one() -> None:
    busy = candidate("busy", ON_ROUTE, users=12)
    quiet = candidate("quiet", offset(ON_ROUTE, north_m=150), users=5)
    far = candidate("far-enough", offset(ON_ROUTE, north_m=1000), users=5)
    results = await evaluate(quiet, far, busy)
    by_id = {r.candidate_id: r for r in results}
    assert by_id["busy"].rank == 1 and by_id["far-enough"].rank == 2
    assert not by_id["quiet"].eligible
    assert "busy" in check(by_id["quiet"], Criterion.STOP_SPACING).detail
    assert [r.candidate_id for r in results] == ["busy", "far-enough", "quiet"]


async def test_score_prefers_more_demand() -> None:
    results = await evaluate(candidate("small", ON_ROUTE, users=3), candidate("big", offset(ON_ROUTE, north_m=2000), users=9))
    assert [r.candidate_id for r in results] == ["big", "small"]
    assert results[0].score > results[1].score


# --- feeder heuristic -------------------------------------------------------


def test_feeder_heuristic_balances_demand_detour_and_recency() -> None:
    signals = [
        FeederStopSignal(stop_id="busy-far", active_demand=6, detour_s=600, seconds_since_served=60),
        FeederStopSignal(stop_id="busy-near", active_demand=6, detour_s=60, seconds_since_served=60),
        FeederStopSignal(stop_id="starved", active_demand=1, detour_s=60, seconds_since_served=3600),
        FeederStopSignal(stop_id="empty", active_demand=0, detour_s=0, seconds_since_served=9999),
    ]
    ranked = rank_feeder_stops(signals, FeederHeuristicParams())
    assert [s.stop_id for s in ranked] == ["busy-near", "starved", "busy-far"]
    assert ranked[0].score == pytest.approx(0.5 - 0.3 * 0.1 + 0.2 * (60 / 1800), abs=1e-4)


def test_feeder_heuristic_empty() -> None:
    assert rank_feeder_stops([], FeederHeuristicParams()) == []


# --- HTTP ---------------------------------------------------------------------


def _post(body: dict, router=straight_line_router):
    app.dependency_overrides[get_router] = lambda: router
    try:
        return TestClient(app).post("/v1/stop-candidates/evaluate", json=body)
    finally:
        app.dependency_overrides.clear()


def _body(*candidates: StopCandidate) -> dict:
    return EvaluateRequest(candidates=list(candidates), corridors=[CORRIDOR]).model_dump(mode="json")


def test_endpoint_evaluates() -> None:
    response = _post(_body(candidate("a", ON_ROUTE)))
    assert response.status_code == 200
    assert response.json()["evaluations"][0]["rank"] == 1


def test_endpoint_rejects_unknown_corridor() -> None:
    body = _body(candidate("a", ON_ROUTE))
    body["candidates"][0]["corridor_id"] = "K9"
    response = _post(body)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "unknown_corridor"


def test_endpoint_maps_osrm_failure_to_503() -> None:
    async def broken(_: list) -> float:
        raise OsrmUnavailable("down")

    response = _post(_body(candidate("a", ON_ROUTE)), router=broken)
    assert response.status_code == 503 and response.json()["detail"]["code"] == "routing_unavailable"


def test_feeder_priorities_endpoint() -> None:
    body = {"signals": [{"stop_id": "s1", "active_demand": 2, "detour_s": 30, "seconds_since_served": 100}]}
    response = TestClient(app).post("/v1/feeder-stop-priorities", json=body)
    assert response.status_code == 200 and response.json()["items"][0]["stop_id"] == "s1"

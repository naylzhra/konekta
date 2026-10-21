from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.clustering.dbscan import NOISE, cluster_demand_points
from app.corridors import identify_corridor
from app.geo import haversine_m, project_onto_path
from app.main import app, get_snapper
from app.models import (
    ClusterRequest,
    Corridor,
    DemandRequest,
    Direction,
    GeoPoint,
    HotspotCheck,
    PoolingParams,
    StopEndpoint,
)
from app.osrm_client import OsrmUnavailable, SnapResult
from app.pipeline import WIB, build_clusters
from app.virtual_stop.centroid import recency_weight, weighted_centroid

# Synthetic corridor running ~9 km south -> north; "forward" = northbound.
CORRIDOR = Corridor(
    id="K1",
    path=[GeoPoint(lat=-6.95, lng=107.61), GeoPoint(lat=-6.91, lng=107.61), GeoPoint(lat=-6.87, lng=107.61)],
    catchment_m=800,
)
NORTH_END = GeoPoint(lat=-6.875, lng=107.611)
SOUTH_END = GeoPoint(lat=-6.945, lng=107.611)
HOTSPOT = GeoPoint(lat=-6.930, lng=107.612)
MONDAY = datetime(2026, 10, 5, tzinfo=WIB)
WINDOW = (MONDAY, MONDAY + timedelta(days=7))
M_PER_DEG = 111_195.0


def offset(point: GeoPoint, north_m: float = 0, east_m: float = 0) -> GeoPoint:
    return GeoPoint(lat=point.lat + north_m / M_PER_DEG, lng=point.lng + east_m / (M_PER_DEG * 0.9927))


def demand(
    rid: str,
    user: str,
    origin: GeoPoint,
    destination: GeoPoint = NORTH_END,
    day: int = 0,
    hour: int = 7,
    seats: int = 1,
) -> DemandRequest:
    return DemandRequest(
        id=rid,
        requester_key=user,
        origin=origin,
        destination=destination,
        requested_at=MONDAY + timedelta(days=day, hours=hour, minutes=10),
        seats=seats,
    )


async def fake_snap(point: GeoPoint) -> SnapResult:
    return SnapResult(location=offset(point, east_m=10), distance_m=10.0)


def cluster_request(requests: list[DemandRequest], **params) -> ClusterRequest:
    return ClusterRequest(
        endpoint=StopEndpoint.PICKUP,
        window_start=WINDOW[0],
        window_end=WINDOW[1],
        corridors=[CORRIDOR],
        requests=requests,
        params=PoolingParams(**params),
    )


# --- geometry and corridor identification ---------------------------------


def test_project_onto_path() -> None:
    projection = project_onto_path(offset(GeoPoint(lat=-6.93, lng=107.61), east_m=100), CORRIDOR.path)
    assert projection.offset_m == pytest.approx(100, abs=1)
    assert projection.along_m == pytest.approx(haversine_m(CORRIDOR.path[0], GeoPoint(lat=-6.93, lng=107.61)), abs=2)
    assert projection.segment == 0


def test_identify_corridor_direction() -> None:
    assert identify_corridor(HOTSPOT, NORTH_END, [CORRIDOR], 300).direction == Direction.FORWARD
    assert identify_corridor(HOTSPOT, SOUTH_END, [CORRIDOR], 300).direction == Direction.BACKWARD


def test_identify_corridor_rejects_off_corridor_and_short_trips() -> None:
    far_east = GeoPoint(lat=-6.93, lng=107.70)
    assert identify_corridor(far_east, NORTH_END, [CORRIDOR], 300) is None
    assert identify_corridor(HOTSPOT, offset(HOTSPOT, north_m=100), [CORRIDOR], 300) is None


def test_identify_corridor_prefers_closest() -> None:
    parallel = Corridor(id="K2", path=[offset(p, east_m=600) for p in CORRIDOR.path])
    match = identify_corridor(offset(HOTSPOT, east_m=500), offset(NORTH_END, east_m=500), [CORRIDOR, parallel], 300)
    assert match.corridor_id == "K2"


# --- DBSCAN and centroid --------------------------------------------------


def test_dbscan_uses_metres() -> None:
    tight = [offset(HOTSPOT, north_m=20 * i) for i in range(4)]
    far = [offset(HOTSPOT, north_m=2000)]
    labels = cluster_demand_points(tight + far, eps_m=50, min_pts=4)
    assert labels[:4] == [0, 0, 0, 0]
    assert labels[4] == NOISE
    # Same points, ε too small to chain them.
    assert set(cluster_demand_points(tight, eps_m=10, min_pts=4)) == {NOISE}


def test_weighted_centroid_pulls_towards_weight() -> None:
    a, b = HOTSPOT, offset(HOTSPOT, north_m=100)
    centroid = weighted_centroid([(a, 1.0), (b, 3.0)])
    assert haversine_m(a, centroid) == pytest.approx(75, abs=1)
    assert weighted_centroid([]) is None


def test_recency_weight_halves_per_half_life() -> None:
    now = MONDAY + timedelta(days=14)
    assert recency_weight(2, now, now, 14) == pytest.approx(2)
    assert recency_weight(2, MONDAY, now, 14) == pytest.approx(1)


# --- full pipeline ----------------------------------------------------------


def hotspot_requests() -> list[DemandRequest]:
    """Six riders, six different days, within ~40 m of HOTSPOT."""
    return [
        demand(f"h{i}", f"user-{i}", offset(HOTSPOT, north_m=(i % 3) * 15, east_m=(i % 2) * 20), day=i)
        for i in range(6)
    ]


async def test_recurring_hotspot_becomes_a_snapped_candidate() -> None:
    response = await build_clusters(cluster_request(hotspot_requests()), fake_snap, MONDAY)
    [cluster] = response.clusters
    assert cluster.validated and cluster.failed_checks == []
    assert (cluster.corridor_id, cluster.direction, cluster.slot_start) == ("K1", Direction.FORWARD, "07:00")
    assert cluster.unique_users == 6 and cluster.active_days == 6 and cluster.observed_days == 7
    assert haversine_m(cluster.centroid, HOTSPOT) < 40
    assert cluster.snap_distance_m == 10.0
    assert haversine_m(cluster.snapped_location, cluster.centroid) == pytest.approx(10, abs=0.5)
    assert sorted(cluster.member_ids) == [f"h{i}" for i in range(6)]


async def test_one_rider_repeating_is_not_a_hotspot() -> None:
    spam = [demand(f"s{i}", "same-user", offset(HOTSPOT, north_m=i * 10), day=i) for i in range(6)]
    [cluster] = (await build_clusters(cluster_request(spam), fake_snap, MONDAY)).clusters
    assert cluster.failed_checks == [HotspotCheck.UNIQUE_USERS]
    assert cluster.snapped_location is None


async def test_one_day_burst_fails_temporal_consistency() -> None:
    burst = [demand(f"b{i}", f"user-{i}", offset(HOTSPOT, north_m=i * 10), day=2) for i in range(6)]
    [cluster] = (await build_clusters(cluster_request(burst), fake_snap, MONDAY)).clusters
    assert cluster.failed_checks == [HotspotCheck.TEMPORAL_CONSISTENCY]


async def test_spread_out_cluster_fails_spatial_concentration() -> None:
    chain = [demand(f"c{i}", f"user-{i}", offset(HOTSPOT, north_m=i * 120), day=i) for i in range(6)]
    # MinPts 2 lets DBSCAN chain points 120 m apart into one long cluster.
    [cluster] = (await build_clusters(cluster_request(chain, min_pts=2), fake_snap, MONDAY)).clusters
    assert HotspotCheck.SPATIAL_CONCENTRATION in cluster.failed_checks


async def test_direction_and_time_slot_partition_pooling() -> None:
    southbound = [demand(f"s{i}", f"south-{i}", HOTSPOT, destination=SOUTH_END, day=i) for i in range(6)]
    evening = [demand(f"e{i}", f"eve-{i}", HOTSPOT, day=i, hour=18) for i in range(6)]
    response = await build_clusters(cluster_request(hotspot_requests() + southbound + evening), fake_snap, MONDAY)
    keys = {(c.direction, c.slot_start): sorted(c.member_ids)[0][0] for c in response.clusters}
    assert keys == {
        (Direction.FORWARD, "07:00"): "h",
        (Direction.BACKWARD, "07:00"): "s",
        (Direction.FORWARD, "18:00"): "e",
    }


async def test_summary_counts_dropped_requests() -> None:
    requests = hotspot_requests() + [
        demand("far", "x", GeoPoint(lat=-6.93, lng=107.70)),
        demand("late", "y", HOTSPOT, day=9),
        demand("alone", "z", offset(HOTSPOT, north_m=3000)),
    ]
    summary = (await build_clusters(cluster_request(requests), fake_snap, MONDAY)).summary
    assert (summary.requests, summary.outside_window, summary.no_corridor, summary.noise) == (9, 1, 1, 1)
    assert (summary.clusters, summary.validated) == (1, 1)


async def test_dropoff_clusters_destinations() -> None:
    to_hotspot = [demand(f"d{i}", f"user-{i}", SOUTH_END, destination=offset(HOTSPOT, north_m=i * 10), day=i) for i in range(6)]
    request = cluster_request(to_hotspot).model_copy(update={"endpoint": StopEndpoint.DROPOFF})
    [cluster] = (await build_clusters(request, fake_snap, MONDAY)).clusters
    assert cluster.endpoint == StopEndpoint.DROPOFF
    assert haversine_m(cluster.centroid, HOTSPOT) < 60


# --- HTTP ---------------------------------------------------------------------


def _body(requests: list[DemandRequest]) -> dict:
    return cluster_request(requests).model_dump(mode="json")


def test_endpoint_returns_clusters() -> None:
    app.dependency_overrides[get_snapper] = lambda: fake_snap
    try:
        response = TestClient(app).post("/v1/demand-clusters", json=_body(hotspot_requests()))
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json()["summary"]["validated"] == 1


def test_endpoint_maps_osrm_failure_to_503() -> None:
    async def broken(_: GeoPoint) -> SnapResult:
        raise OsrmUnavailable("down")

    app.dependency_overrides[get_snapper] = lambda: broken
    try:
        response = TestClient(app).post("/v1/demand-clusters", json=_body(hotspot_requests()))
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "routing_unavailable"


def test_endpoint_rejects_reversed_window() -> None:
    body = _body([])
    body["window_start"], body["window_end"] = body["window_end"], body["window_start"]
    assert TestClient(app).post("/v1/demand-clusters", json=body).status_code == 422

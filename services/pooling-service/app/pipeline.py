"""Demand → validated stop candidates (DESIGN.md §13.1–13.4).

1. Identify each request's corridor and direction; drop trips no corridor serves.
2. Partition by (corridor, direction, time-of-day slot), so only trips
   heading the same way at the same time of day are pooled together.
3. DBSCAN each partition on the clustered endpoint (origin or destination).
4. Validate each cluster as a demand hotspot.
5. Weighted centroid for every cluster; snap validated ones onto the road.
"""
import math
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable

from app.clustering.dbscan import NOISE, cluster_demand_points
from app.corridors import identify_corridor
from app.models import (
    ClusterRequest,
    ClusterResponse,
    ClusterSummary,
    DemandCluster,
    DemandRequest,
    Direction,
    GeoPoint,
    StopEndpoint,
)
from app.osrm_client import SnapResult
from app.validation import failed_checks, hotspot_stats
from app.virtual_stop.centroid import SECONDS_PER_DAY, recency_weight, weighted_centroid

# Bandung's local time (WIB, no DST): time-of-day slots and "active days".
WIB = timezone(timedelta(hours=7), "WIB")

Snapper = Callable[[GeoPoint], Awaitable[SnapResult]]
PartitionKey = tuple[str, Direction, int]


def _endpoint_point(request: DemandRequest, endpoint: StopEndpoint) -> GeoPoint:
    return request.origin if endpoint == StopEndpoint.PICKUP else request.destination


def _slot_of(moment: datetime, slot_minutes: int) -> int:
    local = moment.astimezone(WIB)
    return (local.hour * 60 + local.minute) // slot_minutes


def _slot_start(slot: int, slot_minutes: int) -> str:
    minutes = slot * slot_minutes
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


async def build_clusters(request: ClusterRequest, snap: Snapper, now: datetime) -> ClusterResponse:
    params = request.params
    partitions: dict[PartitionKey, list[DemandRequest]] = defaultdict(list)
    outside_window = no_corridor = 0
    for demand in request.requests:
        if not request.window_start <= demand.requested_at < request.window_end:
            outside_window += 1
            continue
        match = identify_corridor(demand.origin, demand.destination, request.corridors, params.min_corridor_progress_m)
        if match is None:
            no_corridor += 1
            continue
        slot = _slot_of(demand.requested_at, params.slot_minutes)
        partitions[(match.corridor_id, match.direction, slot)].append(demand)

    observed_days = max(1, math.ceil((request.window_end - request.window_start).total_seconds() / SECONDS_PER_DAY))
    clusters: list[DemandCluster] = []
    noise = 0
    for key in sorted(partitions, key=lambda k: (k[0], k[1].value, k[2])):
        corridor_id, direction, slot = key
        members = partitions[key]
        labels = cluster_demand_points(
            [_endpoint_point(m, request.endpoint) for m in members], params.eps_m, params.min_pts
        )
        noise += labels.count(NOISE)
        for label in sorted(set(labels) - {NOISE}):
            group = [m for m, member_label in zip(members, labels) if member_label == label]
            points = [_endpoint_point(m, request.endpoint) for m in group]
            centroid = weighted_centroid(
                [
                    (point, recency_weight(m.seats, m.requested_at, request.window_end, params.recency_half_life_days))
                    for point, m in zip(points, group)
                ]
            )
            assert centroid is not None  # clusters are non-empty with positive weights
            stats = hotspot_stats(
                requester_keys=[m.requester_key for m in group],
                local_dates=[m.requested_at.astimezone(WIB).date() for m in group],
                points=points,
                centroid=centroid,
                observed_days=observed_days,
            )
            failed = failed_checks(stats, params)
            # Only validated hotspots become stop candidates, so only they
            # are worth an OSRM call.
            snapped = None if failed else await snap(centroid)
            clusters.append(
                DemandCluster(
                    cluster_id=f"{corridor_id}-{direction.value}-{slot:02d}-{label}",
                    corridor_id=corridor_id,
                    direction=direction,
                    endpoint=request.endpoint,
                    time_slot=slot,
                    slot_start=_slot_start(slot, params.slot_minutes),
                    member_ids=[m.id for m in group],
                    size=len(group),
                    unique_users=stats.unique_users,
                    active_days=stats.active_days,
                    observed_days=stats.observed_days,
                    temporal_consistency=round(stats.temporal_consistency, 4),
                    radius_p80_m=round(stats.radius_p80_m, 1),
                    centroid=centroid,
                    snapped_location=None if snapped is None else snapped.location,
                    snap_distance_m=None if snapped is None else round(snapped.distance_m, 1),
                    validated=not failed,
                    failed_checks=failed,
                )
            )

    return ClusterResponse(
        generated_at=now,
        clusters=clusters,
        summary=ClusterSummary(
            requests=len(request.requests),
            outside_window=outside_window,
            no_corridor=no_corridor,
            noise=noise,
            clusters=len(clusters),
            validated=sum(c.validated for c in clusters),
        ),
    )

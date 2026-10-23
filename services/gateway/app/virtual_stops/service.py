"""Run the existing clustering and evaluation services over stored trip plans."""
import hashlib
import hmac
import json
import os
import secrets
import uuid
from datetime import datetime, timezone

import asyncpg

from app.virtual_stops.clients import ServiceClient

POOLING_DEFAULTS = {
    "eps_m": 150, "min_pts": 4, "slot_minutes": 60,
    "min_corridor_progress_m": 300, "min_unique_users": 5,
    "max_radius_p80_m": 250, "min_active_days": 3,
    "min_temporal_consistency": 0.3, "recency_half_life_days": 14,
}
EVALUATION_DEFAULTS = {
    "corridor_buffer_m": 100, "walk_detour_factor": 1.3,
    "max_walk_m": 400, "min_walk_coverage": 0.8,
    "min_stop_spacing_m": 300, "max_shift_m": 500,
    "max_added_travel_s": 120, "safety_reference_m": 50,
    "weight_demand": 0.4, "weight_access": 0.25,
    "weight_travel_time": 0.2, "weight_safety": 0.15,
}


def _point(row: asyncpg.Record, prefix: str) -> dict:
    return {"lat": row[f"{prefix}_lat"], "lng": row[f"{prefix}_lng"]}


async def run_virtual_stops(
    pool: asyncpg.Pool,
    pooling: ServiceClient,
    evaluation: ServiceClient,
    *,
    window_start: datetime,
    window_end: datetime,
    endpoint: str,
    triggered_by: uuid.UUID | None,
    pooling_params: dict,
    evaluation_params: dict,
) -> dict:
    pooling_params = {**POOLING_DEFAULTS, **pooling_params}
    evaluation_params = {**EVALUATION_DEFAULTS, **evaluation_params}
    corridors = await pool.fetch(
        "SELECT id, catchment_m, ST_AsGeoJSON(path::geometry) AS path FROM corridors WHERE path IS NOT NULL"
    )
    corridor_payload = [
        {
            "id": row["id"],
            "catchment_m": row["catchment_m"],
            "path": [{"lat": lat, "lng": lng} for lng, lat in json.loads(row["path"])["coordinates"]],
        }
        for row in corridors
    ]
    if not corridor_payload:
        raise ValueError("No spatial corridor is available")

    trips = await pool.fetch(
        """SELECT p.id, p.user_id, p.created_at,
                  ST_Y(p.origin::geometry) AS origin_lat, ST_X(p.origin::geometry) AS origin_lng,
                  ST_Y(p.destination::geometry) AS destination_lat,
                  ST_X(p.destination::geometry) AS destination_lng,
                  COALESCE(MAX(b.seats), 1) AS seats
           FROM trip_plans p LEFT JOIN bookings b ON b.trip_plan_id = p.id
           WHERE p.created_at >= $1 AND p.created_at < $2
           GROUP BY p.id""",
        window_start,
        window_end,
    )
    salt = secrets.token_bytes(32)
    requests = [
        {
            "id": str(row["id"]),
            "requester_key": hmac.new(salt, str(row["user_id"]).encode(), hashlib.sha256).hexdigest(),
            "origin": _point(row, "origin"),
            "destination": _point(row, "destination"),
            "requested_at": row["created_at"].isoformat(),
            "seats": row["seats"],
        }
        for row in trips
    ]
    clustered = await pooling.post(
        "/v1/demand-clusters",
        {
            "endpoint": endpoint,
            "window_start": window_start.isoformat(),
            "window_end": window_end.isoformat(),
            "corridors": corridor_payload,
            "requests": requests,
            "params": pooling_params,
        },
    )

    by_id = {str(row["id"]): row for row in trips}
    candidate_input = []
    for cluster in clustered["clusters"]:
        if not cluster["validated"]:
            continue
        points = []
        for member_id in cluster["member_ids"]:
            member = by_id[member_id]
            age_days = max(0.0, (window_end - member["created_at"]).total_seconds() / 86400)
            weight = member["seats"] * 0.5 ** (age_days / pooling_params.get("recency_half_life_days", 14))
            points.append({"location": _point(member, "origin" if endpoint == "pickup" else "destination"), "weight": weight})
        candidate_input.append(
            {
                "candidate_id": cluster["cluster_id"],
                "corridor_id": cluster["corridor_id"],
                "location": cluster["snapped_location"],
                "demand_points": points,
                "unique_users": cluster["unique_users"],
            }
        )

    evaluated = {"evaluations": []}
    if candidate_input:
        stop_rows = await pool.fetch(
            """SELECT id, type::text AS type, corridor_id,
                      ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
               FROM stops WHERE retired_at IS NULL AND (valid_until IS NULL OR valid_until > now())"""
        )
        zone_rows = await pool.fetch(
            """SELECT id, kind, radius_m,
                      ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
               FROM restricted_zones"""
        )
        evaluated = await evaluation.post(
            "/v1/stop-candidates/evaluate",
            {
                "candidates": candidate_input,
                "corridors": [{"id": c["id"], "path": c["path"]} for c in corridor_payload],
                "existing_stops": [
                    {"id": str(s["id"]), "type": s["type"], "corridor_id": s["corridor_id"],
                     "location": {"lat": s["lat"], "lng": s["lng"]}}
                    for s in stop_rows
                ],
                "restricted_zones": [
                    {"id": str(z["id"]), "kind": z["kind"], "radius_m": z["radius_m"],
                     "location": {"lat": z["lat"], "lng": z["lng"]}}
                    for z in zone_rows
                ],
                "params": evaluation_params,
            },
        )

    results = {item["candidate_id"]: item for item in evaluated["evaluations"]}
    run_id = uuid.uuid4()
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            """INSERT INTO virtual_stop_runs
                  (id, window_start, window_end, endpoint, params, summary, triggered_by, finished_at)
               VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7, $8)""",
            run_id, window_start, window_end, endpoint,
            json.dumps({"pooling": pooling_params, "evaluation": evaluation_params,
                        "routing_ready": os.getenv("ROUTING_DATA_READY", "0") == "1"}),
            json.dumps(clustered["summary"]), triggered_by, datetime.now(timezone.utc),
        )
        for cluster in clustered["clusters"]:
            centroid, snapped = cluster["centroid"], cluster["snapped_location"]
            cluster_id = await conn.fetchval(
                """INSERT INTO demand_clusters
                      (run_id, service_cluster_id, corridor_id, direction, time_slot,
                       size, unique_users, centroid, snapped_location, validated, result)
                   VALUES ($1, $2, $3, $4, $5, $6, $7,
                           ST_SetSRID(ST_MakePoint($8, $9),4326)::geography,
                           CASE WHEN $10::float8 IS NULL THEN NULL
                                ELSE ST_SetSRID(ST_MakePoint($10, $11),4326)::geography END,
                           $12, $13::jsonb) RETURNING id""",
                run_id, cluster["cluster_id"], cluster["corridor_id"], cluster["direction"],
                cluster["time_slot"], cluster["size"], cluster["unique_users"],
                centroid["lng"], centroid["lat"],
                snapped["lng"] if snapped else None, snapped["lat"] if snapped else None,
                cluster["validated"], json.dumps(cluster),
            )
            for member_id in cluster["member_ids"]:
                await conn.execute(
                    "INSERT INTO demand_cluster_members (cluster_id, trip_plan_id) VALUES ($1, $2)",
                    cluster_id, uuid.UUID(member_id),
                )
            result = results.get(cluster["cluster_id"])
            if result is None:
                continue
            if result["eligible"]:
                await conn.execute(
                    """UPDATE stop_candidates old SET status = 'superseded'
                       FROM demand_clusters previous, virtual_stop_runs previous_run
                       WHERE old.cluster_id = previous.id
                         AND previous.run_id = previous_run.id
                         AND old.status = 'proposed' AND old.eligible
                         AND previous.corridor_id = $1 AND previous.direction = $2
                         AND previous_run.endpoint = $3
                         AND ST_DWithin(old.location,
                             ST_SetSRID(ST_MakePoint($4, $5),4326)::geography, $6)""",
                    cluster["corridor_id"], cluster["direction"], endpoint,
                    snapped["lng"], snapped["lat"], evaluation_params["min_stop_spacing_m"],
                )
            await conn.execute(
                """INSERT INTO stop_candidates
                      (cluster_id, location, evaluation, eligible, rank, score, action, relocates_stop_id)
                   VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3),4326)::geography,
                           $4::jsonb, $5, $6, $7, $8, $9)""",
                cluster_id, snapped["lng"], snapped["lat"], json.dumps(result),
                result["eligible"], result["rank"], result["score"], result["action"],
                uuid.UUID(result["relocates_stop_id"]) if result["relocates_stop_id"] else None,
            )
    return {"id": str(run_id), "summary": clustered["summary"], "candidates": len(results)}

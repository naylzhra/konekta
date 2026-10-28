"""DB-backed checks for the supplied K1 route and review lifecycle."""
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.bookings.clients import DbStopAssigner, StopAssignmentRequest
from app.bookings.models import GeoPoint, StopType
from app.routers.virtual_stops import (
    ReviewRequest, approve_candidate, get_run, list_candidates, retire_virtual_stop,
)

pytestmark = pytest.mark.asyncio

GOVERNMENT_ID = UUID("00000000-0000-0000-0000-00000000000e")


async def test_k1_route_has_51_points_and_k2_is_dummy(pool):
    rows = await pool.fetch(
        """SELECT position, name, ST_Y(location::geometry) AS lat
           FROM corridor_route_stops WHERE corridor_id = 'K1' AND direction = 'forward'
           ORDER BY position"""
    )
    assert len(rows) == 51
    assert [row["position"] for row in rows] == list(range(1, 52))
    assert (rows[39]["name"], rows[39]["lat"]) == ("Simpang Sumatera - Aceh", -6.909767)
    assert (rows[40]["name"], rows[40]["lat"]) == ("Taman Lalu Lintas Kota Bandung", -6.9122313413532686)
    backward = await pool.fetch(
        """SELECT position, name FROM corridor_route_stops
           WHERE corridor_id = 'K1' AND direction = 'backward' ORDER BY position"""
    )
    assert [backward[0]["name"], backward[-1]["name"], len(backward)] == [
        "Pasar Baru ABC", "Simpang Soetta Kiaracondong 2", 54]
    assert await pool.fetchval("SELECT return_path IS NOT NULL FROM corridors WHERE id = 'K1'") is True
    assert await pool.fetchval("SELECT is_dummy FROM corridors WHERE id = 'K2'") is True
    assert await pool.fetchval("SELECT path IS NULL FROM corridors WHERE id = 'K2'") is True


async def test_db_assigner_uses_k1_direction_and_only_active_stops(pool):
    assigner = DbStopAssigner(pool)
    origin = GeoPoint(lat=-6.945891140531955, lng=107.64085963908062)
    destination = GeoPoint(lat=-6.918301385527375, lng=107.60567416923172)
    forward = await assigner.match_corridor(origin, destination)
    assert (forward.corridor_id, forward.direction) == ("K1", "forward")
    # The return trip rides K1's backward route.
    backward = await assigner.match_corridor(destination, origin)
    assert (backward.corridor_id, backward.direction) == ("K1", "backward")
    assert await assigner.match_corridor(origin, GeoPoint(lat=-6.9460, lng=107.6400)) is None

    stop_id = await pool.fetchval(
        """INSERT INTO stops (type, name, location, corridor_id)
           VALUES ('static', 'K1 awal', ST_SetSRID(ST_MakePoint($1,$2),4326)::geography, 'K1')
           RETURNING id""",
        origin.lng, origin.lat,
    )
    stop = await assigner.assign_pickup_stop(StopAssignmentRequest(location=origin, corridor_id="K1"))
    assert stop is not None and stop.id == stop_id and stop.type == StopType.STATIC
    await pool.execute("UPDATE stops SET retired_at = now() WHERE id = $1", stop_id)
    assert await assigner.assign_pickup_stop(StopAssignmentRequest(location=origin, corridor_id="K1")) is None


async def test_government_review_creates_indefinite_stop_and_can_retire_it(pool):
    await pool.execute(
        "INSERT INTO users (id, phone_number, password_hash, role) VALUES ($1, '+620000000004', 'x', 'government')",
        GOVERNMENT_ID,
    )
    run_id = await pool.fetchval(
        """INSERT INTO virtual_stop_runs
              (window_start, window_end, endpoint, params, triggered_by)
           VALUES (now() - interval '7 days', now(), 'pickup',
                   '{"routing_ready": false}'::jsonb, $1) RETURNING id""",
        GOVERNMENT_ID,
    )
    cluster_id = await pool.fetchval(
        """INSERT INTO demand_clusters
              (run_id, service_cluster_id, corridor_id, direction, time_slot,
               size, unique_users, centroid, validated, result)
           VALUES ($1, 'K1-forward-08-0', 'K1', 'forward', 8, 6, 6,
                   ST_SetSRID(ST_MakePoint(107.62,-6.92),4326)::geography,
                   true, '{}'::jsonb) RETURNING id""",
        run_id,
    )
    candidate_id = await pool.fetchval(
        """INSERT INTO stop_candidates
              (cluster_id, location, evaluation, eligible, score, action)
           VALUES ($1, ST_SetSRID(ST_MakePoint(107.62,-6.92),4326)::geography,
                   '{}'::jsonb, true, 0.8, 'new_stop') RETURNING id""",
        cluster_id,
    )
    session = {"user_id": str(GOVERNMENT_ID)}
    run = await get_run(run_id, _session=session, pool=pool)
    assert run["params"]["routing_ready"] is False
    candidates = await list_candidates(status=None, corridor_id=None, _session=session, pool=pool)
    assert candidates["items"][0]["evaluation"] == {}
    with pytest.raises(HTTPException) as error:
        await approve_candidate(
            candidate_id, ReviewRequest(), session=session, pool=pool,
        )
    assert error.value.status_code == 409
    await pool.execute(
        "UPDATE virtual_stop_runs SET params = '{\"routing_ready\": true}'::jsonb WHERE id = $1",
        run_id,
    )
    approved = await approve_candidate(
        candidate_id, ReviewRequest(review_note="Disetujui"),
        session=session, pool=pool,
    )
    stop_id = UUID(approved["stop_id"])
    row = await pool.fetchrow("SELECT type::text AS type, valid_until, retired_at FROM stops WHERE id = $1", stop_id)
    assert row["type"] == "virtual" and row["valid_until"] is None and row["retired_at"] is None
    assigner = DbStopAssigner(pool)
    selected = await assigner.assign_pickup_stop(
        StopAssignmentRequest(location=GeoPoint(lat=-6.92, lng=107.62), corridor_id="K1")
    )
    assert selected is not None and selected.id == stop_id
    assert (await approve_candidate(candidate_id, ReviewRequest(), session=session, pool=pool))["stop_id"] == str(stop_id)
    await retire_virtual_stop(stop_id, _session=session, pool=pool)
    assert await pool.fetchval("SELECT retired_at IS NOT NULL FROM stops WHERE id = $1", stop_id)
    assert await assigner.assign_pickup_stop(
        StopAssignmentRequest(location=GeoPoint(lat=-6.92, lng=107.62), corridor_id="K1")
    ) is None

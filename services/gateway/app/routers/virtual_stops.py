"""Operational runs and review of adaptive virtual stop candidates."""
import json
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import AwareDatetime, BaseModel, Field, model_validator

from app.auth.dependencies import require_role
from app.db import get_pool
from app.virtual_stops.clients import VirtualStopServiceUnavailable, evaluation_client, pooling_client
from app.virtual_stops.service import run_virtual_stops

router = APIRouter(prefix="/virtual-stops", tags=["virtual-stops"])


class RunRequest(BaseModel):
    window_start: AwareDatetime
    window_end: AwareDatetime
    endpoint: str = Field(pattern="^(pickup|dropoff)$")
    pooling_params: dict = Field(default_factory=dict)
    evaluation_params: dict = Field(default_factory=dict)

    @model_validator(mode="after")
    def valid_window(self) -> "RunRequest":
        if self.window_end <= self.window_start:
            raise ValueError("window_end must be after window_start")
        return self


class ReviewRequest(BaseModel):
    review_note: str | None = Field(default=None, max_length=1000)


@router.post("/runs")
async def start_run(
    payload: RunRequest,
    session: dict = Depends(require_role("admin", "government")),
    pool=Depends(get_pool),
) -> dict:
    try:
        return await run_virtual_stops(
            pool, pooling_client(), evaluation_client(),
            window_start=payload.window_start, window_end=payload.window_end,
            endpoint=payload.endpoint, triggered_by=UUID(session["user_id"]),
            pooling_params=payload.pooling_params, evaluation_params=payload.evaluation_params,
        )
    except VirtualStopServiceUnavailable as exc:
        raise HTTPException(503, detail={"code": "service_unavailable", "message": str(exc)}) from exc
    except ValueError as exc:
        raise HTTPException(422, detail={"code": "invalid_run", "message": str(exc)}) from exc


@router.get("/runs/{run_id}")
async def get_run(
    run_id: UUID,
    _session: dict = Depends(require_role("admin", "government")),
    pool=Depends(get_pool),
) -> dict:
    row = await pool.fetchrow("SELECT * FROM virtual_stop_runs WHERE id = $1", run_id)
    if row is None:
        raise HTTPException(404, detail="Run not found")
    result = dict(row)
    for field in ("params", "summary"):
        if isinstance(result[field], str):
            result[field] = json.loads(result[field])
    return result


@router.get("/candidates")
async def list_candidates(
    status: str | None = Query(default=None, pattern="^(proposed|approved|rejected|superseded)$"),
    corridor_id: str | None = None,
    _session: dict = Depends(require_role("admin", "government")),
    pool=Depends(get_pool),
) -> dict:
    rows = await pool.fetch(
        """SELECT c.id, c.status, c.eligible, c.rank, c.score, c.action,
                  c.relocates_stop_id, c.reviewed_by, c.reviewed_at, c.review_note,
                  c.evaluation, c.created_at, d.corridor_id, d.direction,
                  d.time_slot, d.unique_users, d.result AS cluster,
                  ST_Y(c.location::geometry) AS lat, ST_X(c.location::geometry) AS lng
           FROM stop_candidates c JOIN demand_clusters d ON d.id = c.cluster_id
           WHERE ($1::text IS NULL OR c.status = $1)
             AND ($2::text IS NULL OR d.corridor_id = $2)
           ORDER BY c.created_at DESC LIMIT 500""",
        status, corridor_id,
    )
    items = []
    for row in rows:
        item = dict(row)
        for field in ("evaluation", "cluster"):
            if isinstance(item[field], str):
                item[field] = json.loads(item[field])
        items.append(item)
    return {"items": items}


@router.post("/candidates/{candidate_id}/approve")
async def approve_candidate(
    candidate_id: UUID,
    payload: ReviewRequest,
    session: dict = Depends(require_role("government")),
    pool=Depends(get_pool),
) -> dict:
    async with pool.acquire() as conn, conn.transaction():
        candidate = await conn.fetchrow(
            """SELECT c.*, ST_AsEWKT(c.location::geometry) AS location_wkt,
                      d.corridor_id, d.direction, r.endpoint,
                      r.params->>'routing_ready' AS routing_ready
               FROM stop_candidates c JOIN demand_clusters d ON d.id = c.cluster_id
               JOIN virtual_stop_runs r ON r.id = d.run_id
               WHERE c.id = $1 FOR UPDATE OF c""",
            candidate_id,
        )
        if candidate is None:
            raise HTTPException(404, detail="Candidate not found")
        if candidate["status"] == "approved":
            return {"id": str(candidate_id), "status": "approved", "stop_id": str(candidate["approved_stop_id"])}
        if candidate["status"] != "proposed" or not candidate["eligible"]:
            raise HTTPException(409, detail={"code": "invalid_transition", "message": "Candidate cannot be approved"})
        if candidate["routing_ready"] != "true":
            raise HTTPException(409, detail={"code": "routing_not_ready", "message": "Run used mock routing data"})
        stop_id = await conn.fetchval(
            """INSERT INTO stops (type, name, location, corridor_id, valid_until)
               VALUES ('virtual', $1, ST_GeogFromText($2), $3, NULL) RETURNING id""",
            f"Titik Virtual {candidate['corridor_id']}", candidate["location_wkt"], candidate["corridor_id"],
        )
        if candidate["action"] == "relocate_stop" and candidate["relocates_stop_id"] is not None:
            await conn.execute(
                "UPDATE stops SET retired_at = now() WHERE id = $1 AND retired_at IS NULL",
                candidate["relocates_stop_id"],
            )
        await conn.execute(
            """UPDATE stop_candidates
               SET status = 'approved', approved_stop_id = $2, reviewed_by = $3,
                   reviewed_at = now(), review_note = $4
               WHERE id = $1""",
            candidate_id, stop_id, UUID(session["user_id"]), payload.review_note,
        )
        return {"id": str(candidate_id), "status": "approved", "stop_id": str(stop_id)}


@router.post("/candidates/{candidate_id}/reject")
async def reject_candidate(
    candidate_id: UUID,
    payload: ReviewRequest,
    session: dict = Depends(require_role("government")),
    pool=Depends(get_pool),
) -> dict:
    async with pool.acquire() as conn, conn.transaction():
        candidate = await conn.fetchrow("SELECT status FROM stop_candidates WHERE id = $1 FOR UPDATE", candidate_id)
        if candidate is None:
            raise HTTPException(404, detail="Candidate not found")
        if candidate["status"] == "rejected":
            return {"id": str(candidate_id), "status": "rejected"}
        if candidate["status"] != "proposed":
            raise HTTPException(409, detail={"code": "invalid_transition", "message": "Candidate cannot be rejected"})
        await conn.execute(
            """UPDATE stop_candidates SET status = 'rejected', reviewed_by = $2,
                      reviewed_at = now(), review_note = $3 WHERE id = $1""",
            candidate_id, UUID(session["user_id"]), payload.review_note,
        )
        return {"id": str(candidate_id), "status": "rejected"}


@router.post("/stops/{stop_id}/retire")
async def retire_virtual_stop(
    stop_id: UUID,
    _session: dict = Depends(require_role("government")),
    pool=Depends(get_pool),
) -> dict:
    row = await pool.fetchrow(
        """UPDATE stops SET retired_at = COALESCE(retired_at, now())
           WHERE id = $1 AND type = 'virtual' RETURNING id, retired_at""",
        stop_id,
    )
    if row is None:
        raise HTTPException(404, detail="Virtual stop not found")
    return {"id": str(row["id"]), "retired_at": row["retired_at"]}

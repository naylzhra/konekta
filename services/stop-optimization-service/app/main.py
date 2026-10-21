from fastapi import Depends, FastAPI, HTTPException

from app.evaluation.evaluate import Router, UnknownCorridor, evaluate_candidates
from app.models import EvaluateRequest, EvaluateResponse, FeederPriorityRequest, FeederPriorityResponse
from app.routing import OsrmUnavailable, route_duration_s
from app.scoring.heuristic import rank_feeder_stops

app = FastAPI(title="KONEKTA Stop Optimization Service")


def get_router() -> Router:
    return route_duration_s


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "stop-optimization-service"}


@app.post("/v1/stop-candidates/evaluate", response_model=EvaluateResponse)
async def evaluate(request: EvaluateRequest, route: Router = Depends(get_router)) -> EvaluateResponse:
    """Check candidates against corridor coverage, pedestrian access, traffic
    safety and regulation, and rank the eligible ones (DESIGN.md §13.5)."""
    try:
        return EvaluateResponse(evaluations=await evaluate_candidates(request, route))
    except UnknownCorridor as exc:
        raise HTTPException(
            status_code=422,
            detail={"code": "unknown_corridor", "message": f"Candidates reference unknown corridors: {exc}"},
        ) from exc
    except OsrmUnavailable as exc:
        raise HTTPException(
            status_code=503,
            detail={"code": "routing_unavailable", "message": "Travel time estimation is unavailable"},
        ) from exc


@app.post("/v1/feeder-stop-priorities", response_model=FeederPriorityResponse)
async def feeder_stop_priorities(request: FeederPriorityRequest) -> FeederPriorityResponse:
    """Rank stops with waiting passengers for one feeder (DESIGN.md §13.7)."""
    return FeederPriorityResponse(items=rank_feeder_stops(request.signals, request.params))

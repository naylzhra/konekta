from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException

from app.models import ClusterRequest, ClusterResponse
from app.osrm_client import OsrmUnavailable, snap_to_road
from app.pipeline import Snapper, build_clusters

app = FastAPI(title="KONEKTA Pooling Service")


def get_snapper() -> Snapper:
    return snap_to_road


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "pooling-service"}


@app.post("/v1/demand-clusters", response_model=ClusterResponse)
async def demand_clusters(request: ClusterRequest, snap: Snapper = Depends(get_snapper)) -> ClusterResponse:
    """Cluster a window of trip requests into validated stop candidates
    (DESIGN.md §13). Stateless: the caller stores the result."""
    try:
        return await build_clusters(request, snap, datetime.now(timezone.utc))
    except OsrmUnavailable as exc:
        raise HTTPException(
            status_code=503,
            detail={"code": "routing_unavailable", "message": "Road snapping is unavailable"},
        ) from exc

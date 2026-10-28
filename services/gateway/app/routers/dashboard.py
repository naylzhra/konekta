"""Read-only aggregates for the government ops dashboard."""
from fastapi import APIRouter, Depends, Query

from app.auth.dependencies import require_role
from app.db import get_pool

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/demand-forecast")
async def demand_forecast(
    days: int = Query(default=7, ge=1, le=14),
    _session: dict = Depends(require_role("admin", "government")),
    pool=Depends(get_pool),
) -> dict:
    """Forecast feeder demand from today (Asia/Jakarta) for `days` days.

    Written by forecasting-service's predict job (demand_forecasts).
    """
    window = """
        ts >= date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta'
        AND ts < (date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') + make_interval(days => $1))
                 AT TIME ZONE 'Asia/Jakarta'
    """
    daily = await pool.fetch(
        f"""SELECT (ts AT TIME ZONE 'Asia/Jakarta')::date AS date, sum(predicted_trips) AS trips
              FROM demand_forecasts WHERE {window} GROUP BY 1 ORDER BY 1""",
        days,
    )
    by_kecamatan = await pool.fetch(
        f"""SELECT kecamatan, sum(predicted_trips) AS trips
              FROM demand_forecasts WHERE {window} GROUP BY 1 ORDER BY 2 DESC""",
        days,
    )
    meta = await pool.fetchrow(
        f"SELECT max(model_version) AS model_version, max(generated_at) AS generated_at "
        f"FROM demand_forecasts WHERE {window}",
        days,
    )
    return {
        "model_version": meta["model_version"],
        "generated_at": meta["generated_at"].isoformat() if meta["generated_at"] else None,
        "daily": [{"date": r["date"].isoformat(), "trips": round(float(r["trips"]), 1)} for r in daily],
        "kecamatan": [
            {"name": r["kecamatan"], "trips_per_day": round(float(r["trips"]) / days, 1)} for r in by_kecamatan
        ],
    }

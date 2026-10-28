"""
Forecasts hourly feeder demand per kecamatan for the next HORIZON_DAYS days
and upserts it into demand_forecasts. Meant to run as a one-off job (cron),
not a long-lived service:

    python -m app.jobs.predict
"""
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pandas as pd

from app.data.kecamatan import NAMES, SERVICE_HOURS
from app.models.demand_model import DemandForecastModel

JAKARTA = ZoneInfo("Asia/Jakarta")
HORIZON_DAYS = int(os.getenv("FORECAST_HORIZON_DAYS", "7"))

UPSERT = """
    INSERT INTO demand_forecasts (kecamatan, ts, predicted_trips, model_version, generated_at)
    VALUES (%s, %s, %s, %s, now())
    ON CONFLICT (kecamatan, ts) DO UPDATE
       SET predicted_trips = EXCLUDED.predicted_trips,
           model_version = EXCLUDED.model_version,
           generated_at = EXCLUDED.generated_at
"""


def future_frame(days: int, today: datetime | None = None) -> pd.DataFrame:
    start = (today or datetime.now(JAKARTA)).date()
    rows = [
        (name, datetime(d.year, d.month, d.day, hour))
        for d in (start + timedelta(days=i) for i in range(days))
        for hour in SERVICE_HOURS
        for name in NAMES
    ]
    frame = pd.DataFrame(rows, columns=["kecamatan", "ts"])
    frame["ts"] = frame["ts"].dt.strftime("%Y-%m-%dT%H:%M:%S")
    return frame


def main() -> None:
    import psycopg

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise SystemExit("DATABASE_URL is not set")

    try:
        model = DemandForecastModel.load()
    except FileNotFoundError:
        raise SystemExit("No trained model in artifacts/ — run `python -m app.training.train` first")
    frame = future_frame(HORIZON_DAYS)
    frame["predicted"] = model.predict(frame)

    rows = [
        (row.kecamatan, datetime.fromisoformat(row.ts).replace(tzinfo=JAKARTA), round(float(row.predicted), 3), model.version)
        for row in frame.itertuples()
    ]
    with psycopg.connect(database_url) as conn:
        with conn.cursor() as cur:
            cur.executemany(UPSERT, rows)
            # Keep a bit of history for comparing forecasts with actuals later.
            cur.execute("DELETE FROM demand_forecasts WHERE ts < now() - interval '60 days'")
    print(f"Wrote {len(rows)} forecasts ({HORIZON_DAYS} days) with model {model.version}")


if __name__ == "__main__":
    main()

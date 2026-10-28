"""
Trains the demand forecasting model and writes artifacts/model.json +
artifacts/meta.json.

Training data = data/synthetic_demand.csv + trial demand from Postgres
(trip_plans, counted per kecamatan per hour). Synthetic rows get
SYNTHETIC_WEIGHT so real trial data dominates as soon as it exists.

    python -m app.training.train            # synthetic + trial data (needs DATABASE_URL)
    python -m app.training.train --no-db    # synthetic only

The last HOLDOUT_DAYS days are held out to compare against a seasonal
baseline (kecamatan × hour × day-type mean), then the final model is
refit on everything.
"""
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

from app.data.kecamatan import NAMES, SERVICE_HOURS
from app.features import FEATURES, build_features, fit_encodings
from app.models.demand_model import ARTIFACT_DIR

SYNTHETIC_CSV = Path(__file__).resolve().parents[2] / "data" / "synthetic_demand.csv"
SYNTHETIC_WEIGHT = float(os.getenv("SYNTHETIC_WEIGHT", "0.3"))
HOLDOUT_DAYS = 3

PARAMS = {
    "objective": "count:poisson",
    "n_estimators": 300,
    "max_depth": 4,
    "learning_rate": 0.05,
    "subsample": 0.9,
    "colsample_bytree": 0.9,
    "random_state": 42,
}

# Trial demand: trip plans counted by the kecamatan their origin falls in,
# per local hour. Hours with no plans are filled with 0 in load_trials().
TRIALS_QUERY = """
    SELECT k.name AS kecamatan,
           date_trunc('hour', tp.created_at AT TIME ZONE 'Asia/Jakarta') AS ts,
           count(*) AS trips
      FROM trip_plans tp
      JOIN kecamatan k ON ST_Contains(k.geom, tp.origin::geometry)
     GROUP BY 1, 2
"""


def load_synthetic() -> pd.DataFrame:
    return pd.read_csv(SYNTHETIC_CSV)


def load_trials(database_url: str) -> pd.DataFrame:
    import psycopg

    with psycopg.connect(database_url) as conn:
        rows = conn.execute(TRIALS_QUERY).fetchall()
    if not rows:
        return pd.DataFrame(columns=["kecamatan", "ts", "trips", "source"])

    counts = pd.DataFrame(rows, columns=["kecamatan", "ts", "trips"])
    counts["ts"] = pd.to_datetime(counts["ts"])
    # Every kecamatan × service hour across the trial period, 0 where nothing was requested.
    days = pd.date_range(counts["ts"].min().normalize(), counts["ts"].max().normalize(), freq="D")
    grid = pd.DataFrame(
        [(k, d + pd.Timedelta(hours=h)) for d in days for h in SERVICE_HOURS for k in NAMES],
        columns=["kecamatan", "ts"],
    )
    frame = grid.merge(counts, on=["kecamatan", "ts"], how="left").fillna({"trips": 0})
    frame["ts"] = frame["ts"].dt.strftime("%Y-%m-%dT%H:%M:%S")
    frame["source"] = "trial"
    return frame


def sample_weights(frame: pd.DataFrame) -> np.ndarray:
    return np.where(frame["source"] == "synthetic", SYNTHETIC_WEIGHT, 1.0)


def fit(frame: pd.DataFrame) -> tuple[xgb.XGBRegressor, dict]:
    encodings = fit_encodings(frame)
    features = build_features(frame, encodings)[FEATURES]
    model = xgb.XGBRegressor(**PARAMS)
    model.fit(features, frame["trips"], sample_weight=sample_weights(frame))
    return model, encodings


def evaluate(frame: pd.DataFrame) -> dict:
    """Train on all but the last HOLDOUT_DAYS days, score on those days."""
    ts = pd.to_datetime(frame["ts"])
    cutoff = ts.max().normalize() - pd.Timedelta(days=HOLDOUT_DAYS - 1)
    train, test = frame[ts < cutoff], frame[ts >= cutoff]

    model, encodings = fit(train)
    test_features = build_features(test, encodings)
    predicted = np.clip(model.predict(test_features[FEATURES]), 0, None)
    baseline = test_features["kec_hour_mean"] * (
        test_features["kec_daytype_mean"] / test_features["kec_mean"].replace(0, np.nan)
    ).fillna(1)
    actual = test["trips"].to_numpy()

    def mae(values) -> float:
        return round(float(np.mean(np.abs(np.asarray(values) - actual))), 4)

    return {
        "holdout_from": cutoff.strftime("%Y-%m-%d"),
        "holdout_rows": int(len(test)),
        "mae_xgboost": mae(predicted),
        "mae_baseline": mae(baseline),
        "daily_total_actual": round(float(actual.sum()) / HOLDOUT_DAYS, 1),
        "daily_total_predicted": round(float(predicted.sum()) / HOLDOUT_DAYS, 1),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Train the KONEKTA demand forecasting model")
    parser.add_argument("--no-db", action="store_true", help="train on synthetic data only")
    parser.add_argument("--output", type=Path, default=ARTIFACT_DIR)
    args = parser.parse_args()

    frames = [load_synthetic()]
    database_url = os.getenv("DATABASE_URL")
    if not args.no_db:
        if not database_url:
            raise SystemExit("DATABASE_URL is not set (use --no-db to train on synthetic data only)")
        frames.append(load_trials(database_url))
    frame = pd.concat(frames, ignore_index=True)
    sources = frame["source"].value_counts().to_dict()
    print(f"Training rows by source: {sources}")

    metrics = evaluate(frame)
    print(f"Holdout metrics: {metrics}")

    model, encodings = fit(frame)
    trained_at = datetime.now(timezone.utc)
    meta = {
        "version": trained_at.strftime("xgb-%Y%m%d%H%M"),
        "trained_at": trained_at.isoformat(),
        "rows": {k: int(v) for k, v in sources.items()},
        "synthetic_weight": SYNTHETIC_WEIGHT,
        "features": FEATURES,
        "params": PARAMS,
        "metrics": metrics,
        "encodings": encodings,
    }
    args.output.mkdir(parents=True, exist_ok=True)
    model.save_model(args.output / "model.json")
    (args.output / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Saved model {meta['version']} to {args.output}")


if __name__ == "__main__":
    main()

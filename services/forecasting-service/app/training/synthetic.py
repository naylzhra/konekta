"""
Generates a small synthetic feeder-demand dataset to bootstrap the model
until trial bookings exist (see README "Data").

Calibration:
- Volume: Trans Metro Bandung carried 873,572 passengers in 2019 (Open Data
  Bandung, the last year before COVID-19) ≈ 2,393 trips/day. TMB is trunk
  transit, not a feeder, so only FEEDER_SHARE of that — riders who live
  beyond walking distance of a halte — is treated as feeder demand. The
  share is an assumption.
- Space: split across kecamatan by the assumed weights in app/data/kecamatan.py.
- Time: twin weekday peaks (≈07.00 and ≈17.00), flatter weekends.

Deliberately short (two weeks) so trial data outweighs it quickly; it is
also down-weighted during training (SYNTHETIC_WEIGHT in train.py).

    python -m app.training.synthetic          # writes data/synthetic_demand.csv
"""
import argparse
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

from app.data.kecamatan import KECAMATAN, NAMES, SERVICE_HOURS

TMB_PASSENGERS_2019 = 873_572
FEEDER_SHARE = 0.25
DAILY_FEEDER_TRIPS = TMB_PASSENGERS_2019 / 365 * FEEDER_SHARE  # ≈ 598

# Relative demand per service hour (05.00 … 21.00).
WEEKDAY_PROFILE = [2, 6, 10, 8, 5, 4, 4, 4, 4, 5, 6, 9, 8, 5, 3, 2, 1]
WEEKEND_PROFILE = [1, 2, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 5, 4, 3, 2, 1]
WEEKEND_VOLUME = 0.8

START = date(2026, 9, 7)  # a Monday
DAYS = 14
SEED = 42

DEFAULT_OUTPUT = Path(__file__).resolve().parents[2] / "data" / "synthetic_demand.csv"


def generate(start: date = START, days: int = DAYS, seed: int = SEED) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    total_weight = sum(k["weight"] for k in KECAMATAN.values())
    weekday_profile = np.array(WEEKDAY_PROFILE) / sum(WEEKDAY_PROFILE)
    weekend_profile = np.array(WEEKEND_PROFILE) / sum(WEEKEND_PROFILE)

    rows = []
    for offset in range(days):
        day = start + timedelta(days=offset)
        weekend = day.weekday() >= 5
        profile = weekend_profile if weekend else weekday_profile
        # Day-to-day variation (weather, events) shared by the whole city.
        day_noise = rng.normal(1.0, 0.08)
        for name in NAMES:
            k = KECAMATAN[name]
            daily = DAILY_FEEDER_TRIPS * k["weight"] / total_weight * day_noise
            if weekend:
                daily *= WEEKEND_VOLUME * k["weekend"]
            expected = daily * profile
            trips = rng.poisson(expected)
            for hour, count in zip(SERVICE_HOURS, trips):
                rows.append({
                    "kecamatan": name,
                    "ts": datetime(day.year, day.month, day.day, hour).isoformat(),
                    "trips": int(count),
                    "source": "synthetic",
                })
    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    frame = generate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(args.output, index=False)
    per_day = frame["trips"].sum() / DAYS
    print(f"Wrote {len(frame)} rows to {args.output} (≈{per_day:.0f} trips/day)")


if __name__ == "__main__":
    main()

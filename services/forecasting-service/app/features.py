"""
Feature engineering shared by training and prediction.

Rows are (kecamatan, local hour) with a `trips` target. Features are
calendar fields plus target encodings learned from the training data (each
kecamatan's typical demand overall, per hour and per day type), so a
forecast never needs the most recent actuals — fine for a 7-day horizon on
patchy cold-start data.

TODO: once trial data is continuous, add lag features (same hour last
week) and public holidays.
"""
import pandas as pd

from app.data.kecamatan import NAMES

FEATURES = [
    "hour",
    "dow",
    "is_weekend",
    "kecamatan_idx",
    "kec_mean",
    "kec_hour_mean",
    "kec_daytype_mean",
]


def add_calendar(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy()
    ts = pd.to_datetime(frame["ts"])
    frame["hour"] = ts.dt.hour
    frame["dow"] = ts.dt.dayofweek
    frame["is_weekend"] = (frame["dow"] >= 5).astype(int)
    frame["kecamatan_idx"] = frame["kecamatan"].map({name: i for i, name in enumerate(NAMES)})
    return frame


def fit_encodings(train: pd.DataFrame) -> dict:
    """Mean trips per hour-row by kecamatan, kecamatan×hour, kecamatan×day type."""
    train = add_calendar(train)
    return {
        "global": float(train["trips"].mean()),
        "kec": train.groupby("kecamatan")["trips"].mean().to_dict(),
        "kec_hour": {
            f"{k}|{h}": v for (k, h), v in train.groupby(["kecamatan", "hour"])["trips"].mean().items()
        },
        "kec_daytype": {
            f"{k}|{w}": v for (k, w), v in train.groupby(["kecamatan", "is_weekend"])["trips"].mean().items()
        },
    }


def build_features(frame: pd.DataFrame, encodings: dict) -> pd.DataFrame:
    frame = add_calendar(frame)
    fallback = encodings["global"]
    frame["kec_mean"] = frame["kecamatan"].map(encodings["kec"]).fillna(fallback)
    frame["kec_hour_mean"] = [
        encodings["kec_hour"].get(f"{k}|{h}", fallback) for k, h in zip(frame["kecamatan"], frame["hour"])
    ]
    frame["kec_daytype_mean"] = [
        encodings["kec_daytype"].get(f"{k}|{w}", fallback) for k, w in zip(frame["kecamatan"], frame["is_weekend"])
    ]
    return frame

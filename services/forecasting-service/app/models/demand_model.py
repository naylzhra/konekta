"""
XGBoost demand forecasting model wrapper.

The trained booster lives in artifacts/model.json and everything needed to
rebuild its features (target encodings, feature order, version) in
artifacts/meta.json — both written by app.training.train.
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

from app.features import FEATURES, build_features

ARTIFACT_DIR = Path(__file__).resolve().parents[2] / "artifacts"


class DemandForecastModel:
    def __init__(self, model: xgb.XGBRegressor, meta: dict):
        self.model = model
        self.meta = meta

    @property
    def version(self) -> str:
        return self.meta["version"]

    @classmethod
    def load(cls, artifact_dir: Path = ARTIFACT_DIR) -> "DemandForecastModel":
        model_path = artifact_dir / "model.json"
        if not model_path.exists():
            raise FileNotFoundError(model_path)
        model = xgb.XGBRegressor()
        model.load_model(model_path)
        meta = json.loads((artifact_dir / "meta.json").read_text(encoding="utf-8"))
        return cls(model, meta)

    def predict(self, frame: pd.DataFrame) -> np.ndarray:
        """Expected trips for each (kecamatan, ts) row in `frame`."""
        features = build_features(frame, self.meta["encodings"])[FEATURES]
        return np.clip(self.model.predict(features), 0, None)

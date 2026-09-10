"""
XGBoost demand forecasting model wrapper.

TODO: implement real feature engineering (time-of-day, day-of-week,
weather, nearby events, historical demand) and load a trained model
artifact. This is a placeholder so the service boots and the class shape
is stable for the API layer / training pipeline to build against.
"""
from typing import Optional

import xgboost as xgb


class DemandForecastModel:
    def __init__(self, model_path: Optional[str] = None):
        self.model = xgb.XGBRegressor()
        self.model_path = model_path
        self._is_fitted = False

    def predict(self, features):
        if not self._is_fitted:
            raise RuntimeError("Model has not been trained/loaded yet.")
        return self.model.predict(features)

"""Adjustable thresholds for automatic demand proposals."""
import os


def _positive_int(name: str, default: int) -> int:
    value = int(os.getenv(name, str(default)))
    if value < 1:
        raise ValueError(f"{name} must be at least 1")
    return value


AUTO_RUN = os.getenv("VIRTUAL_STOP_AUTO_RUN", "1") == "1"
SCAN_INTERVAL_S = _positive_int("VIRTUAL_STOP_SCAN_INTERVAL_S", 60)
WINDOW_DAYS = _positive_int("VIRTUAL_STOP_WINDOW_DAYS", 7)
REQUEST_THRESHOLD = _positive_int("VIRTUAL_STOP_REQUEST_THRESHOLD", 10)
CLUSTER_RADIUS_M = float(os.getenv("VIRTUAL_STOP_CLUSTER_RADIUS_M", "150"))
STOP_SPACING_M = float(os.getenv("VIRTUAL_STOP_STOP_SPACING_M", "300"))
SLOT_MINUTES = _positive_int("VIRTUAL_STOP_SLOT_MINUTES", 1440)

if CLUSTER_RADIUS_M <= 0 or STOP_SPACING_M < 0:
    raise ValueError("Virtual stop distance thresholds must be positive")
if REQUEST_THRESHOLD < 2:
    raise ValueError("VIRTUAL_STOP_REQUEST_THRESHOLD must be at least 2")
if not 15 <= SLOT_MINUTES <= 1440 or 1440 % SLOT_MINUTES:
    raise ValueError("VIRTUAL_STOP_SLOT_MINUTES must divide 1440 and be between 15 and 1440")

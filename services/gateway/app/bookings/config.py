# Booking configuration. Env flags select stub vs real implementations
# (DESIGN.md §5); constants are product decisions recorded in DESIGN.md §11.
import os


def _int_env(name: str, default: int) -> int:
    return int(os.getenv(name, str(default)))


# --- implementation selection ----------------------------------------------
# Only "stub" exists until pooling/stop-optimization expose a real endpoint
# and live tracking ships its Redis-backed FeederPositionProvider.
STOP_ASSIGNER = os.getenv("STOP_ASSIGNER", "stub")
FEEDER_PROVIDER = os.getenv("FEEDER_PROVIDER", "stub")
# Stub supply switch for demoing the no-supply (FAILED) path.
STUB_FEEDER_SUPPLY = os.getenv("STUB_FEEDER_SUPPLY", "1") == "1"
# Demo-only driver stand-in (DESIGN.md §3); never enable in production.
BOOKING_SIMULATOR = os.getenv("BOOKING_SIMULATOR", "0") == "1"
SIM_TO_PICKUP_S = _int_env("SIM_TO_PICKUP_S", 10)
SIM_DWELL_S = _int_env("SIM_DWELL_S", 45)
SIM_RIDE_S = _int_env("SIM_RIDE_S", 20)

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "http://localhost:5001")
ROUTING_TIMEOUT_S = 5.0

# --- product decisions -----------------------------------------------------
CANCELLATION_PENALTY_IDR = 0  # MVP: free cancellation (DESIGN.md §11.5)
CONSENT_POLICY_VERSION = os.getenv("CONSENT_POLICY_VERSION", "2026-10")

# TODO: placeholder tariff until the real fare policy is decided.
FARE_BASE_IDR = 2000
FARE_PER_KM_IDR = 1000
FARE_ROUNDING_IDR = 500

# --- timings and distances -------------------------------------------------
PLAN_TTL_S = _int_env("PLAN_TTL_S", 300)
MATCHING_TIMEOUT_S = _int_env("MATCHING_TIMEOUT_S", 120)
CONFIRMED_TIMEOUT_S = _int_env("CONFIRMED_TIMEOUT_S", 1800)
SWEEP_INTERVAL_S = _int_env("SWEEP_INTERVAL_S", 15)
ARRIVING_RADIUS_M = 300
FEEDER_SEARCH_RADIUS_M = 3000
MAX_WALK_TO_STOP_M = 800
VIRTUAL_STOP_TTL_S = 900
WALK_SPEED_MPS = 1.25

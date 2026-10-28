import os

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Bandung Raya service area: (min_lat, max_lat, min_lng, max_lng). Same box
# as booking's StubStopAssigner (_STUB_AREA in app/bookings/clients.py).
SERVICE_AREA = (-7.05, -6.80, 107.50, 107.75)

# A feeder with no position report for this long counts as offline: its
# Redis entry expires and nearest() stops returning it.
POSITION_TTL_S = 30
# Reports faster than this per feeder are rejected (429).
MIN_REPORT_INTERVAL_MS = 1000
# Fixes less accurate than this are rejected rather than shown on the map.
MAX_ACCURACY_M = 100.0

# --- stop arrivals (GET /corridors/{id}/arrivals) --------------------------
# Estimates divide the distance left along the route by this speed.
# TODO: placeholder (~20 km/h) until measured from real trips.
FEEDER_AVG_SPEED_MPS = 5.5
# A feeder this far past a stop along the route still counts as arriving.
ARRIVAL_PASSED_TOLERANCE_M = 50
# Default and upper bound for the endpoint's max_eta_s.
ARRIVALS_DEFAULT_MAX_ETA_S = 300
ARRIVALS_MAX_ETA_S = 3600

# --- IoT GPS devices (ESP32 + NEO-6M), app/routers/devices.py ---------------
# A driver counts as on duty while their app keeps reporting (it reports only
# between "Mulai Bertugas" and "Selesai Bertugas"; the latter calls
# /feeders/me/offline). Device fixes are ignored while the driver is off duty.
DUTY_TTL_S = POSITION_TTL_S
# The device is the primary source only while its last valid fix is younger
# than this; after that the driver app's reports are published again.
IOT_FRESH_S = 10
# Consecutive valid fixes (each within IOT_FRESH_S of the previous) before the
# device takes over, so a flapping device doesn't make the marker jump.
IOT_RECOVERY_FIXES = 3
# Device clocks come from GPS time; tolerate this much drift into the future.
IOT_MAX_CLOCK_SKEW_S = 5
# A NEO-6M needs at least 4 satellites for a 3D fix.
IOT_MIN_SATELLITES = 4
# Devices report at ~1 Hz; allow some jitter before rejecting (429).
IOT_MIN_REPORT_INTERVAL_MS = 500

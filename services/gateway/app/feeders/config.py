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

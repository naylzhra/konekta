-- 013_feeder_devices.sql
-- IoT GPS devices (ESP32 + NEO-6M) mounted in feeder vehicles
-- (services/gateway/app/routers/devices.py). One device per feeder.
-- Devices authenticate with device_id + an API token; only the token's
-- SHA-256 is stored (provision with `python -m app.cli.create_device`).
--
-- Positions are NOT stored here: like driver-app reports they go to Redis
-- with a short TTL (app/feeders/position_store.py).

CREATE TABLE feeder_devices (
    device_id TEXT PRIMARY KEY CHECK (device_id ~ '^[A-Za-z0-9_-]{1,64}$'),
    feeder_id TEXT NOT NULL UNIQUE REFERENCES feeders (id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

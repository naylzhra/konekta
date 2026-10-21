-- 004_bookings.sql
-- Booking system: stops, trip plans, bookings, consent log (see DESIGN.md
-- §2, §3, §8 and services/gateway/app/bookings/).
--
-- Locations are geography(Point,4326). At-rest encryption is expected at
-- the storage/volume level; column-level pgcrypto would break the spatial
-- indexes (DESIGN.md §8).
--
-- Bookings snapshot their pickup/dropoff stop and fare at confirmation, so
-- stop changes or trip-plan cleanup never rewrite trip history.

CREATE TYPE stop_type AS ENUM ('static', 'virtual');

CREATE TYPE booking_status AS ENUM (
    'REQUESTED',
    'MATCHING',
    'CONFIRMED',
    'FEEDER_ARRIVING',
    'BOARDED',
    'COMPLETED',
    'CANCELLED',
    'FAILED',
    'NO_SHOW',
    'EXPIRED'
);

CREATE TABLE stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type stop_type NOT NULL,
    name TEXT NOT NULL,
    location geography(Point, 4326) NOT NULL,
    -- free text until a corridors table exists
    corridor_id TEXT,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- virtual stops are time-bound, static halte are not
    CONSTRAINT stops_valid_until_matches_type
        CHECK ((type = 'virtual') = (valid_until IS NOT NULL))
);

CREATE INDEX stops_location_gix ON stops USING GIST (location);

-- Stored server-side so fare and expiry can't be forged by the client.
CREATE TABLE trip_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    origin geography(Point, 4326) NOT NULL,
    destination geography(Point, 4326) NOT NULL,
    -- preview only; the booking's actual stop is assigned during MATCHING
    pickup_stop_id UUID REFERENCES stops (id) ON DELETE SET NULL,
    dropoff_stop_id UUID REFERENCES stops (id) ON DELETE SET NULL,
    corridor_id TEXT,
    legs JSONB NOT NULL DEFAULT '[]'::jsonb,
    fare_estimate_idr INTEGER NOT NULL CHECK (fare_estimate_idr >= 0),
    eta_minutes INTEGER NOT NULL CHECK (eta_minutes >= 0),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX trip_plans_user_created_idx ON trip_plans (user_id, created_at DESC);

CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    trip_plan_id UUID REFERENCES trip_plans (id) ON DELETE SET NULL,
    status booking_status NOT NULL DEFAULT 'REQUESTED',
    seats SMALLINT NOT NULL DEFAULT 1 CHECK (seats BETWEEN 1 AND 4),

    -- snapshots, written once at confirmation
    pickup_stop_id UUID REFERENCES stops (id) ON DELETE SET NULL,
    pickup_stop_name TEXT,
    pickup_stop_type stop_type,
    pickup_location geography(Point, 4326),
    dropoff_stop_id UUID REFERENCES stops (id) ON DELETE SET NULL,
    dropoff_stop_name TEXT,
    dropoff_stop_type stop_type,
    dropoff_location geography(Point, 4326),
    fare_estimate_idr INTEGER NOT NULL CHECK (fare_estimate_idr >= 0),

    feeder_id TEXT,
    eta_to_pickup_s INTEGER CHECK (eta_to_pickup_s >= 0),
    cancellation_fee_idr INTEGER NOT NULL DEFAULT 0 CHECK (cancellation_fee_idr >= 0),
    cancel_reason TEXT,

    idempotency_key TEXT NOT NULL,
    -- hash of the create request body: same key + different body -> 409
    request_hash TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT bookings_user_idempotency_key_uniq UNIQUE (user_id, idempotency_key),
    -- once a stop has been assigned the snapshot must be complete
    CONSTRAINT bookings_assigned_has_pickup_snapshot CHECK (
        status IN ('REQUESTED', 'MATCHING', 'FAILED', 'EXPIRED', 'CANCELLED')
        OR (pickup_stop_name IS NOT NULL AND pickup_stop_type IS NOT NULL AND pickup_location IS NOT NULL)
    )
);

CREATE INDEX bookings_user_status_idx ON bookings (user_id, status);

-- history pagination: ORDER BY created_at DESC, id DESC
CREATE INDEX bookings_user_created_idx ON bookings (user_id, created_at DESC, id DESC);

-- one active (non-terminal) booking per user (MVP)
CREATE UNIQUE INDEX bookings_one_active_per_user_uniq ON bookings (user_id)
    WHERE status IN ('REQUESTED', 'MATCHING', 'CONFIRMED', 'FEEDER_ARRIVING', 'BOARDED');

-- driver stop events: who is waiting at / riding to a stop
CREATE INDEX bookings_waiting_at_pickup_idx ON bookings (pickup_stop_id)
    WHERE status IN ('CONFIRMED', 'FEEDER_ARRIVING');
CREATE INDEX bookings_riding_to_dropoff_idx ON bookings (dropoff_stop_id)
    WHERE status = 'BOARDED';

-- expiry sweep
CREATE INDEX bookings_pending_created_idx ON bookings (created_at)
    WHERE status IN ('REQUESTED', 'MATCHING', 'CONFIRMED');

-- Append-only record of location-processing consent (UU PDP). The latest
-- row per (user_id, purpose) is the current state.
CREATE TABLE consent_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    purpose TEXT NOT NULL,
    policy_version TEXT NOT NULL,
    granted BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX consent_log_user_purpose_idx ON consent_log (user_id, purpose, created_at DESC);

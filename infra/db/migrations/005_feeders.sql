-- 005_feeders.sql
-- Corridors and feeder vehicles for live tracking (DESIGN.md §2, §5.2,
-- services/gateway/app/feeders/). A driver picks their feeder at
-- registration; one feeder belongs to at most one driver.
--
-- Live positions are NOT stored here: they live in Redis with a short TTL
-- (app/feeders/position_store.py). No location history is persisted yet
-- (DESIGN.md §8).

CREATE TABLE corridors (
    -- referenced as free text by stops/trip_plans/bookings.corridor_id
    id TEXT PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9_-]{1,32}$'),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE feeders (
    -- also the WS topic suffix (feeder:<id>, see app/websocket/envelope.py)
    id TEXT PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9_-]{1,64}$'),
    corridor_id TEXT NOT NULL REFERENCES corridors (id),
    -- "feeder ke-N" within its corridor
    number SMALLINT NOT NULL CHECK (number > 0),
    capacity SMALLINT NOT NULL DEFAULT 8 CHECK (capacity > 0),
    driver_id UUID UNIQUE REFERENCES users (id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (corridor_id, number)
);

-- PLACEHOLDER data until the real corridor/fleet list is decided: two
-- corridors with five feeders each. Names and counts are dummies.
INSERT INTO corridors (id, name) VALUES
    ('K1', 'Koridor 1 (placeholder)'),
    ('K2', 'Koridor 2 (placeholder)');

INSERT INTO feeders (id, corridor_id, number)
SELECT corridor_id || '-' || lpad(n::text, 2, '0'), corridor_id, n
FROM (VALUES ('K1'), ('K2')) AS c (corridor_id)
CROSS JOIN generate_series(1, 5) AS n;

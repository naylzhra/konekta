-- The 51 supplied K1 route points are active boarding/alighting stops.
-- K2 remains visible as dummy names without spatial stop records.
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS is_dummy BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE corridors SET is_dummy = FALSE WHERE id = 'K1';
UPDATE corridors SET is_dummy = TRUE WHERE id = 'K2';

-- Keep the route list independent of stop lifecycle and test-data cleanup.
ALTER TABLE corridor_route_stops ADD COLUMN IF NOT EXISTS stop_id UUID;

INSERT INTO stops (id, type, name, location, corridor_id, valid_until)
SELECT md5('konekta:K1:stop:' || position)::uuid,
       'static'::stop_type, name, location, 'K1', NULL
FROM corridor_route_stops
WHERE corridor_id = 'K1' AND location IS NOT NULL
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, location = EXCLUDED.location, corridor_id = EXCLUDED.corridor_id;

UPDATE corridor_route_stops
SET stop_id = md5('konekta:K1:stop:' || position)::uuid
WHERE corridor_id = 'K1';

-- Approved adaptive stops remain active until a government reviewer retires them.
ALTER TABLE stops DROP CONSTRAINT stops_valid_until_matches_type;
ALTER TABLE stops ADD CONSTRAINT stops_static_has_no_expiry
    CHECK (type <> 'static' OR valid_until IS NULL);

-- Move K1 stops 39-42 to their real OSM positions (see ROUTES.md).
-- 009 already carries these values for fresh databases; this file updates
-- databases initialised before the correction. Safe to re-run.
-- Run `python -m app.cli.sync_k1_route` afterwards to rebuild the road path.
BEGIN;

UPDATE corridor_route_stops c
SET location = ST_SetSRID(ST_MakePoint(v.lng, v.lat), 4326)::geography
FROM (VALUES
    (39, -6.90699, 107.61061),
    (40, -6.909767, 107.612391),
    (41, -6.9122313413532686, 107.61442513113882),
    (42, -6.913796517478549, 107.61471115735989)
) AS v(position, lat, lng)
WHERE c.corridor_id = 'K1' AND c.position = v.position;

UPDATE stops s
SET location = c.location
FROM corridor_route_stops c
WHERE c.corridor_id = 'K1' AND c.position BETWEEN 39 AND 42 AND s.id = c.stop_id;

COMMIT;

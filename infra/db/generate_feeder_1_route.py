"""Regenerate migrations 009 (forward) and 013 (backward) from ROUTES.md."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = ROOT / "ROUTES.md"
FORWARD_HEADING = "### Arah pergi"
BACKWARD_HEADING = "### Arah balik"


def read_tables() -> dict[str, list[tuple[int, str, str, str]]]:
    tables: dict[str, list[tuple[int, str, str, str]]] = {"forward": [], "backward": []}
    current = None
    for line in source.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            current = ("forward" if line.startswith(FORWARD_HEADING)
                       else "backward" if line.startswith(BACKWARD_HEADING) else None)
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if current is None or len(cells) < 4 or not cells[0].isdigit():
            continue
        position, name, lat, lng = cells[:4]
        float(lat), float(lng)
        tables[current].append((int(position), name, lat, lng))
    for direction, rows in tables.items():
        if not rows or [position for position, *_ in rows] != list(range(1, len(rows) + 1)):
            raise ValueError(f"K1 {direction} stops must be numbered 1..n")
    return tables


def values(rows) -> str:
    return ",\n".join(
        f"    ({position}, '{name.replace(chr(39), chr(39) * 2)}', {lat}, {lng})"
        for position, name, lat, lng in rows
    )


tables = read_tables()
if len(tables["forward"]) != 51:
    raise ValueError("Feeder 1 forward must have exactly 51 ordered stops")

forward_sql = f"""-- Generated from ROUTES.md by infra/db/generate_feeder_1_route.py.
-- Feeder 2 remains unlocated dummy data; do not derive geometry for K2.
BEGIN;

ALTER TABLE corridor_route_stops ADD COLUMN IF NOT EXISTS location geography(Point, 4326);
CREATE INDEX IF NOT EXISTS corridor_route_stops_location_gix
    ON corridor_route_stops USING GIST (location);
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS path geography(LineString, 4326);
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS catchment_m DOUBLE PRECISION NOT NULL DEFAULT 800;

UPDATE corridors
SET name = 'Simpang Soetta Kiaracondong 2 - Pasar Baru ABC'
WHERE id = 'K1';

DELETE FROM corridor_route_stops WHERE corridor_id = 'K1';
INSERT INTO corridor_route_stops (corridor_id, position, name, location)
SELECT 'K1', route.position, route.name,
       ST_SetSRID(ST_MakePoint(route.lng, route.lat), 4326)::geography
FROM (VALUES
{values(tables["forward"])}
) AS route(position, name, lat, lng);

UPDATE corridors
SET path = (
    SELECT ST_MakeLine(location::geometry ORDER BY position)::geography
    FROM corridor_route_stops WHERE corridor_id = 'K1'
)
WHERE id = 'K1';

COMMIT;
"""

backward_sql = f"""-- Generated from ROUTES.md by infra/db/generate_feeder_1_route.py.
-- K1 return direction (Pasar Baru ABC -> Simpang Soetta Kiaracondong 2).
-- Route stops gain a direction; corridors.path stays the forward line and
-- return_path holds this one. Safe to re-run. Run
-- `python -m app.cli.sync_k1_route` afterwards for the road geometry.
BEGIN;

ALTER TABLE corridor_route_stops ADD COLUMN IF NOT EXISTS direction TEXT NOT NULL DEFAULT 'forward'
    CHECK (direction IN ('forward', 'backward'));
ALTER TABLE corridor_route_stops DROP CONSTRAINT IF EXISTS corridor_route_stops_pkey;
ALTER TABLE corridor_route_stops ADD PRIMARY KEY (corridor_id, direction, position);
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS return_path geography(LineString, 4326);
ALTER TABLE trip_plans ADD COLUMN IF NOT EXISTS direction TEXT
    CHECK (direction IN ('forward', 'backward'));

DELETE FROM corridor_route_stops WHERE corridor_id = 'K1' AND direction = 'backward';
INSERT INTO corridor_route_stops (corridor_id, direction, position, name, location, stop_id)
SELECT 'K1', 'backward', route.position, route.name,
       ST_SetSRID(ST_MakePoint(route.lng, route.lat), 4326)::geography,
       md5('konekta:K1:backward:stop:' || route.position)::uuid
FROM (VALUES
{values(tables["backward"])}
) AS route(position, name, lat, lng);

INSERT INTO stops (id, type, name, location, corridor_id, valid_until)
SELECT stop_id, 'static'::stop_type, name, location, 'K1', NULL
FROM corridor_route_stops
WHERE corridor_id = 'K1' AND direction = 'backward'
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, location = EXCLUDED.location, corridor_id = EXCLUDED.corridor_id;

UPDATE corridors
SET return_path = (
    SELECT ST_MakeLine(location::geometry ORDER BY position)::geography
    FROM corridor_route_stops WHERE corridor_id = 'K1' AND direction = 'backward'
)
WHERE id = 'K1';

COMMIT;
"""

(ROOT / "infra/db/migrations/009_feeder_1_route.sql").write_text(forward_sql, encoding="utf-8")
(ROOT / "infra/db/migrations/013_k1_return_route.sql").write_text(backward_sql, encoding="utf-8")

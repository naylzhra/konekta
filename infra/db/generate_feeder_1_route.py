"""Regenerate migration 009 from the route table in ROUTES.md."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = ROOT / "ROUTES.md"
target = ROOT / "infra/db/migrations/009_feeder_1_route.sql"
rows = []
for line in source.read_text(encoding="utf-8").splitlines():
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) != 4 or not cells[0].isdigit():
        continue
    position, name, lat, lng = cells
    float(lat), float(lng)
    rows.append((int(position), name, lat, lng))

if len(rows) != 51 or [position for position, *_ in rows] != list(range(1, 52)):
    raise ValueError("Feeder 1 must have exactly 51 ordered stops")

values = ",\n".join(
    f"    ({position}, '{name.replace(chr(39), chr(39) * 2)}', {lat}, {lng})"
    for position, name, lat, lng in rows
)
sql = f"""-- Generated from ROUTES.md by infra/db/generate_feeder_1_route.py.
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
{values}
) AS route(position, name, lat, lng);

UPDATE corridors
SET path = (
    SELECT ST_MakeLine(location::geometry ORDER BY position)::geography
    FROM corridor_route_stops WHERE corridor_id = 'K1'
)
WHERE id = 'K1';

COMMIT;
"""
target.write_text(sql, encoding="utf-8")

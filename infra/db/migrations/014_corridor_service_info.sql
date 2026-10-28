-- 014_corridor_service_info.sql
-- Passenger-facing service info for the route detail page. NULL means "not
-- set yet" and the app hides that card. Fill per corridor, e.g.:
--
--   UPDATE corridors
--   SET operating_hours = '05.00–21.00',
--       operating_days  = 'Setiap hari',
--       fare_from_idr   = 2000
--   WHERE id = 'K1';

ALTER TABLE corridors ADD COLUMN IF NOT EXISTS operating_hours TEXT;
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS operating_days TEXT;
-- Lowest fare on the route; actual fares grow with distance (booking config).
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS fare_from_idr INTEGER CHECK (fare_from_idr >= 0);

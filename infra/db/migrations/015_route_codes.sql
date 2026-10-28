-- 015_route_codes.sql
-- Passenger-facing route codes. Corridors sharing a route_code are one route
-- to passengers: the app lists them once, under the code. Drivers and
-- registration still see each corridor.
--
-- K2 is FD-1's return direction from before K1 carried both directions
-- (013_k1_return_route.sql). It stays for its feeders, shown as part of FD-1.

ALTER TABLE corridors ADD COLUMN IF NOT EXISTS route_code TEXT;
UPDATE corridors SET route_code = 'FD-1' WHERE id IN ('K1', 'K2');

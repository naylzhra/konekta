-- 001_init.sql
-- Placeholder initial migration: enables PostGIS.
--
-- TODO: add real schema (virtual_stops, ride_requests, feeder_locations,
-- demand_points, etc.) as the data model firms up.

CREATE EXTENSION IF NOT EXISTS postgis;

-- 003_add_government_role.sql
-- Adds the "government" role: read-only oversight accounts used by the
-- ops dashboard (apps/dashboard) to monitor virtual stops, feeder
-- positions, and demand analytics. Distinct from "admin", which is an
-- internal moderation role (suspend/reactivate users, see
-- services/gateway/app/routers/auth.py) and is intentionally not
-- self-registrable.

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'government';
